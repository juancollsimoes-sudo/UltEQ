//! AutoEq DSP Module: Data structures, RBJ filter evaluation, SQLite extraction,
//! and parametric optimization engine for headphone frequency response correction.

use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::f64::consts::PI;

/// Domain error type for AutoEq operations.
#[derive(Debug)]
pub enum AutoEqError {
    EmptyData(String),
    MismatchedLengths { freq_len: usize, db_len: usize },
    InvalidFrequency(String),
    DatabaseError(rusqlite::Error),
    SerializationError(serde_json::Error),
    CsvError(csv::Error),
    MeasurementNotFound(String),
    TargetNotFound(String),
    OptimizationFailed(String),
}

impl std::fmt::Display for AutoEqError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyData(msg) => write!(f, "AutoEq error: empty data - {msg}"),
            Self::MismatchedLengths { freq_len, db_len } => {
                write!(f, "AutoEq error: frequencies ({freq_len}) and dB ({db_len}) length mismatch")
            }
            Self::InvalidFrequency(msg) => write!(f, "AutoEq error: invalid frequency - {msg}"),
            Self::DatabaseError(err) => write!(f, "AutoEq database error: {err}"),
            Self::SerializationError(err) => write!(f, "AutoEq serialization error: {err}"),
            Self::CsvError(err) => write!(f, "AutoEq CSV error: {err}"),
            Self::MeasurementNotFound(query) => write!(f, "Measurement not found for query: '{query}'"),
            Self::TargetNotFound(target) => write!(f, "Target curve not found for: '{target}'"),
            Self::OptimizationFailed(msg) => write!(f, "Optimization failed: {msg}"),
        }
    }
}

impl std::error::Error for AutoEqError {}

impl From<rusqlite::Error> for AutoEqError {
    fn from(err: rusqlite::Error) -> Self {
        Self::DatabaseError(err)
    }
}

impl From<serde_json::Error> for AutoEqError {
    fn from(err: serde_json::Error) -> Self {
        Self::SerializationError(err)
    }
}

impl From<csv::Error> for AutoEqError {
    fn from(err: csv::Error) -> Self {
        Self::CsvError(err)
    }
}

/// Raw frequency response measurement of an earphone/headphone.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EarphoneMeasurement {
    pub brand: String,
    pub model: String,
    pub form_factor: Option<String>,
    pub rig: Option<String>,
    pub file_path: Option<String>,
    pub frequencies: Vec<f64>,
    pub raw_db: Vec<f64>,
}

impl EarphoneMeasurement {
    /// Creates a new `EarphoneMeasurement` with validation.
    pub fn new(
        brand: impl Into<String>,
        model: impl Into<String>,
        frequencies: Vec<f64>,
        raw_db: Vec<f64>,
    ) -> Result<Self, AutoEqError> {
        let measurement = Self {
            brand: brand.into(),
            model: model.into(),
            form_factor: None,
            rig: None,
            file_path: None,
            frequencies,
            raw_db,
        };
        measurement.validate()?;
        Ok(measurement)
    }

    /// Validates data integrity: non-empty, equal vector lengths, positive sorted frequencies.
    pub fn validate(&self) -> Result<(), AutoEqError> {
        if self.frequencies.is_empty() {
            return Err(AutoEqError::EmptyData("Frequencies vector is empty".into()));
        }
        if self.frequencies.len() != self.raw_db.len() {
            return Err(AutoEqError::MismatchedLengths {
                freq_len: self.frequencies.len(),
                db_len: self.raw_db.len(),
            });
        }
        for (i, &f) in self.frequencies.iter().enumerate() {
            if f <= 0.0 || !f.is_finite() {
                return Err(AutoEqError::InvalidFrequency(format!(
                    "Frequency at index {i} is invalid ({f})"
                )));
            }
            if i > 0 && f <= self.frequencies[i - 1] {
                return Err(AutoEqError::InvalidFrequency(format!(
                    "Frequencies must be strictly ascending: index {i} ({f}) <= index {} ({})",
                    i - 1,
                    self.frequencies[i - 1]
                )));
            }
        }
        Ok(())
    }

    /// Interpolates the dB magnitude at an arbitrary frequency using logarithmic frequency interpolation.
    pub fn interpolate_at(&self, freq: f64) -> f64 {
        interpolate_log_scale(&self.frequencies, &self.raw_db, freq)
    }

    /// Interpolates this measurement onto a target frequency grid.
    pub fn interpolate_grid(&self, target_grid: &[f64]) -> Vec<f64> {
        target_grid.iter().map(|&f| self.interpolate_at(f)).collect()
    }

    /// Normalizes the curve so that magnitude at `center_freq` is 0.0 dB.
    pub fn normalize_at(&mut self, center_freq: f64) {
        let offset = self.interpolate_at(center_freq);
        for db in &mut self.raw_db {
            *db -= offset;
        }
    }

    /// Converts from `MeasurementPoint` structures (used by `fetcher`).
    pub fn from_points(
        brand: &str,
        model: &str,
        points: &[crate::fetcher::MeasurementPoint],
    ) -> Result<Self, AutoEqError> {
        if points.is_empty() {
            return Err(AutoEqError::EmptyData("Points slice is empty".into()));
        }
        let mut frequencies = Vec::with_capacity(points.len());
        let mut raw_db = Vec::with_capacity(points.len());

        for pt in points {
            frequencies.push(pt.frequency as f64);
            raw_db.push(pt.raw as f64);
        }

        Self::new(brand, model, frequencies, raw_db)
    }

    /// Parses CSV content (with `frequency` and `raw` columns).
    pub fn from_csv_str(brand: &str, model: &str, csv_content: &str) -> Result<Self, AutoEqError> {
        let mut rdr = csv::ReaderBuilder::new()
            .flexible(true)
            .from_reader(csv_content.as_bytes());

        let headers = rdr.headers()?.clone();
        let freq_idx = headers
            .iter()
            .position(|h| h.eq_ignore_ascii_case("frequency"))
            .ok_or_else(|| AutoEqError::InvalidFrequency("Missing 'frequency' column in CSV".into()))?;
        let raw_idx = headers
            .iter()
            .position(|h| h.eq_ignore_ascii_case("raw"))
            .ok_or_else(|| AutoEqError::EmptyData("Missing 'raw' column in CSV".into()))?;

        let mut frequencies = Vec::new();
        let mut raw_db = Vec::new();

        for record in rdr.records() {
            let rec = record?;
            if let (Some(f_str), Some(r_str)) = (rec.get(freq_idx), rec.get(raw_idx)) {
                if let (Ok(f), Ok(r)) = (f_str.trim().parse::<f64>(), r_str.trim().parse::<f64>()) {
                    if f > 0.0 && f.is_finite() && r.is_finite() {
                        frequencies.push(f);
                        raw_db.push(r);
                    }
                }
            }
        }

        Self::new(brand, model, frequencies, raw_db)
    }

    /// Loads a measurement from SQLite by fuzzy model search (or LIKE query).
    pub fn load_from_db(conn: &Connection, query: &str) -> Result<Self, AutoEqError> {
        let pattern = if query.contains('%') {
            query.to_string()
        } else {
            format!("%{query}%")
        };
        let mut stmt = conn.prepare(
            "SELECT brand, model, form_factor, rig, file_path, spl_blob
             FROM measurements
             WHERE model LIKE ?1 OR brand LIKE ?1 OR (brand || ' ' || model) LIKE ?1
             ORDER BY CASE WHEN spl_blob IS NOT NULL THEN 0 ELSE 1 END, id ASC
             LIMIT 1",
        )?;

        let mut rows = stmt.query([&pattern])?;
        if let Some(row) = rows.next()? {
            let brand: String = row.get(0)?;
            let model: String = row.get(1)?;
            let form_factor: Option<String> = row.get(2)?;
            let rig: Option<String> = row.get(3)?;
            let file_path: Option<String> = row.get(4)?;
            let spl_blob: Option<Vec<u8>> = row.get(5)?;

            let blob = spl_blob.ok_or_else(|| {
                AutoEqError::EmptyData(format!(
                    "Measurement for '{brand} {model}' has no stored spl_blob data in SQLite"
                ))
            })?;

            let points: Vec<crate::fetcher::MeasurementPoint> = serde_json::from_slice(&blob)?;
            let mut measurement = Self::from_points(&brand, &model, &points)?;
            measurement.form_factor = form_factor;
            measurement.rig = rig;
            measurement.file_path = file_path;
            Ok(measurement)
        } else {
            Err(AutoEqError::MeasurementNotFound(query.to_string()))
        }
    }

    /// Loads a measurement from SQLite by file path.
    pub fn load_by_file_path(conn: &Connection, file_path: &str) -> Result<Self, AutoEqError> {
        let mut stmt = conn.prepare(
            "SELECT brand, model, form_factor, rig, file_path, spl_blob
             FROM measurements
             WHERE file_path = ?1
             LIMIT 1",
        )?;

        let mut rows = stmt.query([file_path])?;
        if let Some(row) = rows.next()? {
            let brand: String = row.get(0)?;
            let model: String = row.get(1)?;
            let form_factor: Option<String> = row.get(2)?;
            let rig: Option<String> = row.get(3)?;
            let db_file_path: Option<String> = row.get(4)?;
            let spl_blob: Option<Vec<u8>> = row.get(5)?;

            let blob = spl_blob.ok_or_else(|| {
                AutoEqError::EmptyData(format!(
                    "Measurement '{file_path}' has no stored spl_blob data in SQLite"
                ))
            })?;

            let points: Vec<crate::fetcher::MeasurementPoint> = serde_json::from_slice(&blob)?;
            let mut measurement = Self::from_points(&brand, &model, &points)?;
            measurement.form_factor = form_factor;
            measurement.rig = rig;
            measurement.file_path = db_file_path;
            Ok(measurement)
        } else {
            Err(AutoEqError::MeasurementNotFound(file_path.to_string()))
        }
    }
}

/// Standard target curve presets recognized by AutoEq.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum TargetPreset {
    HarmanOverEar2018,
    HarmanInEar2019,
    DiffuseField5128,
    DiffuseField,
    FreeField,
    Etymotic,
    Custom(String),
}

impl TargetPreset {
    /// Human-friendly display name.
    pub fn display_name(&self) -> &str {
        match self {
            Self::HarmanOverEar2018 => "Harman Over-Ear 2018",
            Self::HarmanInEar2019 => "Harman In-Ear 2019",
            Self::DiffuseField5128 => "Diffuse Field 5128",
            Self::DiffuseField => "Diffuse Field",
            Self::FreeField => "Free Field",
            Self::Etymotic => "Etymotic",
            Self::Custom(name) => name.as_str(),
        }
    }

    /// SQL LIKE pattern for searching the `targets` table.
    pub fn sqlite_pattern(&self) -> &str {
        match self {
            Self::HarmanOverEar2018 => "%harman%over-ear%",
            Self::HarmanInEar2019 => "%harman%in-ear%",
            Self::DiffuseField5128 => "%5128%diffuse%",
            Self::DiffuseField => "%diffuse%field%",
            Self::FreeField => "%free%field%",
            Self::Etymotic => "%etymotic%",
            Self::Custom(name) => name.as_str(),
        }
    }

    /// Parse preset from string name (case-insensitive fuzzy match).
    pub fn from_name(name: &str) -> Self {
        let lower = name.to_lowercase();
        if lower.contains("harman") && (lower.contains("over") || lower.contains("oe")) {
            Self::HarmanOverEar2018
        } else if lower.contains("harman") && (lower.contains("in") || lower.contains("ie")) {
            Self::HarmanInEar2019
        } else if lower.contains("5128") && lower.contains("diffuse") {
            Self::DiffuseField5128
        } else if lower.contains("diffuse") {
            Self::DiffuseField
        } else if lower.contains("free") {
            Self::FreeField
        } else if lower.contains("etymotic") {
            Self::Etymotic
        } else {
            Self::Custom(name.to_string())
        }
    }
}

/// Target frequency response curve (target SPL in dB).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TargetCurve {
    pub name: String,
    pub preset: Option<TargetPreset>,
    pub frequencies: Vec<f64>,
    pub target_db: Vec<f64>,
}

impl TargetCurve {
    /// Creates a new `TargetCurve` with validation.
    pub fn new(
        name: impl Into<String>,
        frequencies: Vec<f64>,
        target_db: Vec<f64>,
    ) -> Result<Self, AutoEqError> {
        let name_str = name.into();
        let preset = Some(TargetPreset::from_name(&name_str));
        let curve = Self {
            name: name_str,
            preset,
            frequencies,
            target_db,
        };
        curve.validate()?;
        Ok(curve)
    }

    /// Validates data integrity.
    pub fn validate(&self) -> Result<(), AutoEqError> {
        if self.frequencies.is_empty() {
            return Err(AutoEqError::EmptyData("Target frequencies vector is empty".into()));
        }
        if self.frequencies.len() != self.target_db.len() {
            return Err(AutoEqError::MismatchedLengths {
                freq_len: self.frequencies.len(),
                db_len: self.target_db.len(),
            });
        }
        for (i, &f) in self.frequencies.iter().enumerate() {
            if f <= 0.0 || !f.is_finite() {
                return Err(AutoEqError::InvalidFrequency(format!(
                    "Target frequency at index {i} is invalid ({f})"
                )));
            }
            if i > 0 && f <= self.frequencies[i - 1] {
                return Err(AutoEqError::InvalidFrequency(format!(
                    "Target frequencies must be strictly ascending: index {i} ({f}) <= index {} ({})",
                    i - 1,
                    self.frequencies[i - 1]
                )));
            }
        }
        Ok(())
    }

    /// Interpolates target dB at frequency `freq`.
    pub fn interpolate_at(&self, freq: f64) -> f64 {
        interpolate_log_scale(&self.frequencies, &self.target_db, freq)
    }

    /// Interpolates target dB onto a target frequency grid.
    pub fn interpolate_grid(&self, target_grid: &[f64]) -> Vec<f64> {
        target_grid.iter().map(|&f| self.interpolate_at(f)).collect()
    }

    /// Normalizes the target curve so that magnitude at `center_freq` is 0.0 dB.
    pub fn normalize_at(&mut self, center_freq: f64) {
        let offset = self.interpolate_at(center_freq);
        for db in &mut self.target_db {
            *db -= offset;
        }
    }

    /// Constructs from `MeasurementPoint` slice.
    pub fn from_points(
        name: &str,
        points: &[crate::fetcher::MeasurementPoint],
    ) -> Result<Self, AutoEqError> {
        if points.is_empty() {
            return Err(AutoEqError::EmptyData("Points slice is empty".into()));
        }
        let mut frequencies = Vec::with_capacity(points.len());
        let mut target_db = Vec::with_capacity(points.len());

        for pt in points {
            frequencies.push(pt.frequency as f64);
            // In target CSVs, the target SPL is in 'raw'
            target_db.push(pt.raw as f64);
        }

        Self::new(name, frequencies, target_db)
    }

    /// Loads a target curve from SQLite matching name or query pattern.
    pub fn load_from_db(conn: &Connection, query: &str) -> Result<Self, AutoEqError> {
        let pattern = format!("%{query}%");
        let mut stmt = conn.prepare(
            "SELECT name, points_blob FROM targets WHERE name LIKE ?1 OR name = ?2 LIMIT 1",
        )?;

        let mut rows = stmt.query([&pattern, query])?;
        if let Some(row) = rows.next()? {
            let name: String = row.get(0)?;
            let blob: Vec<u8> = row.get(1)?;
            let points: Vec<crate::fetcher::MeasurementPoint> = serde_json::from_slice(&blob)?;
            Self::from_points(&name, &points)
        } else {
            Err(AutoEqError::TargetNotFound(query.to_string()))
        }
    }

    /// Loads a target curve by predefined `TargetPreset`.
    pub fn load_by_preset(conn: &Connection, preset: TargetPreset) -> Result<Self, AutoEqError> {
        Self::load_from_db(conn, preset.sqlite_pattern())
    }

    /// Lists all target curve names available in the SQLite database.
    pub fn list_available_targets(conn: &Connection) -> Result<Vec<String>, AutoEqError> {
        let mut stmt = conn.prepare("SELECT name FROM targets ORDER BY name ASC")?;
        let rows = stmt.query_map([], |row| row.get(0))?;
        let mut names = Vec::new();
        for r in rows {
            names.push(r?);
        }
        Ok(names)
    }
}

/// Supported IIR biquad filter topologies.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum BiquadFilterType {
    Peaking,
    LowShelf,
    HighShelf,
}

/// Second-order IIR parametric biquad filter.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct BiquadFilter {
    pub filter_type: BiquadFilterType,
    pub freq: f64,
    pub gain_db: f64,
    pub q: f64,
}

impl BiquadFilter {
    /// Creates a generic biquad filter.
    pub fn new(filter_type: BiquadFilterType, freq: f64, gain_db: f64, q: f64) -> Self {
        Self {
            filter_type,
            freq,
            gain_db,
            q,
        }
    }

    /// Convenience constructor for Peaking EQ (bell filter).
    pub fn new_peaking(freq: f64, gain_db: f64, q: f64) -> Self {
        Self::new(BiquadFilterType::Peaking, freq, gain_db, q)
    }

    /// Convenience constructor for Low Shelf filter.
    pub fn new_low_shelf(freq: f64, gain_db: f64, q: f64) -> Self {
        Self::new(BiquadFilterType::LowShelf, freq, gain_db, q)
    }

    /// Convenience constructor for High Shelf filter.
    pub fn new_high_shelf(freq: f64, gain_db: f64, q: f64) -> Self {
        Self::new(BiquadFilterType::HighShelf, freq, gain_db, q)
    }

    /// Computes normalized digital biquad coefficients (b0, b1, b2, a1, a2)
    /// following Robert Bristow-Johnson's Audio EQ Cookbook in `f64`.
    pub fn rbj_coefficients(&self, sample_rate: f64) -> (f64, f64, f64, f64, f64) {
        let f0 = self.freq.clamp(1.0, sample_rate * 0.499);
        let q = self.q.max(0.01);
        let a = 10.0_f64.powf(self.gain_db / 40.0);
        let w0 = 2.0 * PI * f0 / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * q);

        let (b0, b1, b2, a0, a1, a2) = match self.filter_type {
            BiquadFilterType::Peaking => {
                let b0 = 1.0 + alpha * a;
                let b1 = -2.0 * cos_w0;
                let b2 = 1.0 - alpha * a;
                let a0 = 1.0 + alpha / a;
                let a1 = -2.0 * cos_w0;
                let a2 = 1.0 - alpha / a;
                (b0, b1, b2, a0, a1, a2)
            }
            BiquadFilterType::LowShelf => {
                let beta = 2.0 * a.sqrt() * alpha;
                let b0 = a * ((a + 1.0) - (a - 1.0) * cos_w0 + beta);
                let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w0);
                let b2 = a * ((a + 1.0) - (a - 1.0) * cos_w0 - beta);
                let a0 = (a + 1.0) + (a - 1.0) * cos_w0 + beta;
                let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cos_w0);
                let a2 = (a + 1.0) + (a - 1.0) * cos_w0 - beta;
                (b0, b1, b2, a0, a1, a2)
            }
            BiquadFilterType::HighShelf => {
                let beta = 2.0 * a.sqrt() * alpha;
                let b0 = a * ((a + 1.0) + (a - 1.0) * cos_w0 + beta);
                let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w0);
                let b2 = a * ((a + 1.0) + (a - 1.0) * cos_w0 - beta);
                let a0 = (a + 1.0) - (a - 1.0) * cos_w0 + beta;
                let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cos_w0);
                let a2 = (a + 1.0) - (a - 1.0) * cos_w0 - beta;
                (b0, b1, b2, a0, a1, a2)
            }
        };

        // Normalize by a0
        (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }

    /// Evaluates the exact frequency response magnitude in dB at `freq` (Hz).
    /// Uses the digital transfer function H(e^{j\omega}) evaluated on the unit circle.
    pub fn magnitude_db_at(&self, freq: f64, sample_rate: f64) -> f64 {
        if freq <= 0.0 || !freq.is_finite() {
            return 0.0;
        }
        let nyquist = sample_rate * 0.5;
        let f = freq.min(nyquist - 1e-4);
        let w = 2.0 * PI * f / sample_rate;

        let (b0, b1, b2, a1, a2) = self.rbj_coefficients(sample_rate);

        let cos_w = w.cos();
        let sin_w = w.sin();
        let cos_2w = (2.0 * w).cos();
        let sin_2w = (2.0 * w).sin();

        // Numerator N(e^{j\omega}) = b0 + b1*e^{-j\omega} + b2*e^{-2j\omega}
        let num_re = b0 + b1 * cos_w + b2 * cos_2w;
        let num_im = -b1 * sin_w - b2 * sin_2w;

        // Denominator D(e^{j\omega}) = 1 + a1*e^{-j\omega} + a2*e^{-2j\omega}
        let den_re = 1.0 + a1 * cos_w + a2 * cos_2w;
        let den_im = -a1 * sin_w - a2 * sin_2w;

        let num_mag_sq = num_re * num_re + num_im * num_im;
        let den_mag_sq = den_re * den_re + den_im * den_im;

        if den_mag_sq <= 1e-20 {
            return 0.0;
        }

        let mag_sq = num_mag_sq / den_mag_sq;
        if mag_sq <= 1e-20 {
            return -200.0;
        }

        10.0 * mag_sq.log10()
    }

    /// Converts this filter to the FFI `ActiveFilter` structure used by Flutter.
    pub fn to_active_filter(&self) -> crate::api::simple::ActiveFilter {
        let filter_type = match self.filter_type {
            BiquadFilterType::Peaking => crate::api::simple::FilterType::Peaking,
            BiquadFilterType::LowShelf => crate::api::simple::FilterType::LowShelf,
            BiquadFilterType::HighShelf => crate::api::simple::FilterType::HighShelf,
        };
        crate::api::simple::ActiveFilter {
            filter_type,
            freq: self.freq as f32,
            gain: self.gain_db as f32,
            q: self.q as f32,
        }
    }

    /// Converts from the FFI `ActiveFilter` structure.
    pub fn from_active_filter(f: &crate::api::simple::ActiveFilter) -> Self {
        let filter_type = match f.filter_type {
            crate::api::simple::FilterType::Peaking => BiquadFilterType::Peaking,
            crate::api::simple::FilterType::LowShelf => BiquadFilterType::LowShelf,
            crate::api::simple::FilterType::HighShelf => BiquadFilterType::HighShelf,
        };
        Self {
            filter_type,
            freq: f.freq as f64,
            gain_db: f.gain as f64,
            q: f.q as f64,
        }
    }
}

/// Equalizer profile container resulting from the AutoEq optimization.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EqProfile {
    pub filters: Vec<BiquadFilter>,
    pub preamp_gain_db: f64,
    pub mse_score: f64,
}

impl EqProfile {
    /// Creates a new `EqProfile`.
    pub fn new(filters: Vec<BiquadFilter>, preamp_gain_db: f64, mse_score: f64) -> Self {
        Self {
            filters,
            preamp_gain_db,
            mse_score,
        }
    }

    /// Creates an empty profile with neutral 0 dB settings.
    pub fn empty() -> Self {
        Self {
            filters: Vec::new(),
            preamp_gain_db: 0.0,
            mse_score: 0.0,
        }
    }

    /// Combined magnitude in dB of all cascaded biquads at frequency `freq`.
    pub fn combined_magnitude_db_at(&self, freq: f64, sample_rate: f64) -> f64 {
        let mut total = 0.0;
        for filter in &self.filters {
            total += filter.magnitude_db_at(freq, sample_rate);
        }
        total
    }

    /// Evaluates the total equalizer response curve across an array of frequencies.
    pub fn evaluate_curve(&self, frequencies: &[f64], sample_rate: f64) -> Vec<f64> {
        frequencies
            .iter()
            .map(|&f| self.combined_magnitude_db_at(f, sample_rate) + self.preamp_gain_db)
            .collect()
    }

    /// Computes and sets the anti-clipping preamp gain.
    /// Finds the maximum gain across [20 Hz, 20000 Hz] and applies negative preamp
    /// if peak > 0 dB, including a headroom margin (e.g., 0.2 dB).
    /// Mathematically guarantees that total combined gain + preamp_gain_db <= 0.0 dBFS.
    pub fn compute_anti_clipping_preamp(&mut self, sample_rate: f64, headroom_db: f64) {
        if self.filters.is_empty() {
            self.preamp_gain_db = 0.0;
            return;
        }

        // Dense evaluation grid between 20 Hz and 20 kHz
        let steps = 1000;
        let min_f = 20.0_f64;
        let max_f = 20000.0_f64;
        let mut max_gain = 0.0_f64;
        let mut best_f = min_f;

        for i in 0..=steps {
            let f = min_f * (max_f / min_f).powf(i as f64 / steps as f64);
            let gain = self.combined_magnitude_db_at(f, sample_rate);
            if gain > max_gain {
                max_gain = gain;
                best_f = f;
            }
        }

        // Also evaluate at the center frequencies of all peaking/shelf filters and close neighbors
        for flt in &self.filters {
            for &factor in &[0.95, 0.98, 0.99, 1.0, 1.01, 1.02, 1.05] {
                let f = (flt.freq * factor).clamp(min_f, max_f);
                let gain = self.combined_magnitude_db_at(f, sample_rate);
                if gain > max_gain {
                    max_gain = gain;
                    best_f = f;
                }
            }
        }

        // Refine peak to continuous precision with golden section search around best_f
        if max_gain > 0.0 {
            let f_a = (best_f / 1.05).max(min_f);
            let f_b = (best_f * 1.05).min(max_f);
            let peak_f = golden_section_search(f_a, f_b, 16, |f| {
                -self.combined_magnitude_db_at(f, sample_rate)
            });
            let refined_gain = self.combined_magnitude_db_at(peak_f, sample_rate);
            if refined_gain > max_gain {
                max_gain = refined_gain;
            }
        }

        if max_gain > 0.0 {
            self.preamp_gain_db = -(max_gain + headroom_db.max(0.0));
        } else {
            self.preamp_gain_db = 0.0;
        }
    }

    /// Converts filters to FFI `ActiveFilter` objects.
    pub fn to_active_filters(&self) -> Vec<crate::api::simple::ActiveFilter> {
        self.filters.iter().map(|f| f.to_active_filter()).collect()
    }
}

/// Configuration settings for the AutoEq optimization engine.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AutoEqConfig {
    pub max_peaking_filters: usize,
    pub sample_rate: f64,
    pub min_freq: f64,
    pub max_freq: f64,
    pub optimization_points: usize,
    pub headroom_db: f64,
    pub max_gain_db: f64,
    pub min_gain_db: f64,
    pub min_q: f64,
    pub max_q: f64,
}

impl Default for AutoEqConfig {
    fn default() -> Self {
        Self {
            max_peaking_filters: 10,
            sample_rate: 48000.0,
            min_freq: 35.0, // Clean sub-bass threshold: prevents sub-35Hz ripples
            max_freq: 12000.0,
            optimization_points: 200,
            headroom_db: 0.2,
            max_gain_db: 12.0,
            min_gain_db: -12.0,
            min_q: 0.4,
            max_q: 9.0,
        }
    }
}

/// AutoEq Optimization Engine.
///
/// Implements a 2-phase numerical optimizer:
/// 1. Residual Matching Pursuit: greedily places peaking filters at maximum weighted residual peaks.
/// 2. Joint Cyclic Coordinate Descent: iteratively refines (f0, Gain, Q) across all filters
///    to monotonically minimize weighted Mean Squared Error (MSE).
pub struct AutoEqEngine {
    pub config: AutoEqConfig,
}

impl Default for AutoEqEngine {
    fn default() -> Self {
        Self::new(AutoEqConfig::default())
    }
}

impl AutoEqEngine {
    /// Creates a new engine with the specified configuration.
    pub fn new(config: AutoEqConfig) -> Self {
        Self { config }
    }

    /// Generates the logarithmically spaced evaluation grid.
    pub fn generate_log_grid(&self) -> Vec<f64> {
        let n = self.config.optimization_points.max(20);
        let min_f = self.config.min_freq.max(1.0);
        let max_f = self.config.max_freq.max(min_f * 2.0);
        (0..n)
            .map(|i| min_f * (max_f / min_f).powf(i as f64 / (n - 1) as f64))
            .collect()
    }

    /// Computes the normalized error curve Error(f) = Measured_norm(f) - Target_norm(f)
    /// on the engine's logarithmic evaluation grid.
    pub fn compute_error_curve(
        &self,
        measurement: &EarphoneMeasurement,
        target: &TargetCurve,
    ) -> Vec<(f64, f64)> {
        let grid = self.generate_log_grid();
        let m_grid = measurement.interpolate_grid(&grid);
        let t_grid = target.interpolate_grid(&grid);

        // Normalize curves at 1000 Hz reference anchor
        let m_1k = measurement.interpolate_at(1000.0);
        let t_1k = target.interpolate_at(1000.0);

        grid.into_iter()
            .zip(m_grid.into_iter().zip(t_grid))
            .map(|(f, (m, t))| {
                let m_norm = m - m_1k;
                let t_norm = t - t_1k;
                let error = m_norm - t_norm;
                (f, error)
            })
            .collect()
    }

    /// Computes the target correction curve C(f) = -Error(f) = Target_norm(f) - Measured_norm(f)
    /// on the engine's logarithmic evaluation grid.
    pub fn compute_correction_curve(
        &self,
        measurement: &EarphoneMeasurement,
        target: &TargetCurve,
    ) -> Vec<(f64, f64)> {
        self.compute_error_curve(measurement, target)
            .into_iter()
            .map(|(f, err)| (f, -err))
            .collect()
    }

    /// Computes the psychoacoustically weighted Mean Squared Error (MSE) between
    /// target correction and the active filter cascade.
    pub fn compute_mse(
        &self,
        correction: &[(f64, f64)],
        filters: &[BiquadFilter],
    ) -> f64 {
        if correction.is_empty() {
            return 0.0;
        }

        let mut sum_weighted_sq_err = 0.0;
        let mut sum_weights = 0.0;

        for &(f, target_gain) in correction {
            let mut filter_gain = 0.0;
            for flt in filters {
                filter_gain += flt.magnitude_db_at(f, self.config.sample_rate);
            }
            let err = target_gain - filter_gain;
            let weight = psychoacoustic_weight(f);
            sum_weighted_sq_err += weight * err * err;
            sum_weights += weight;
        }

        if sum_weights > 0.0 {
            sum_weighted_sq_err / sum_weights
        } else {
            0.0
        }
    }

    /// Primary optimization method.
    ///
    /// Generates an `EqProfile` containing up to `config.max_peaking_filters` Peaking EQs,
    /// calibrated anti-clipping preamp, and residual MSE score.
    pub fn optimize(
        &self,
        measurement: &EarphoneMeasurement,
        target: &TargetCurve,
    ) -> Result<EqProfile, AutoEqError> {
        let correction = self.compute_correction_curve(measurement, target);
        self.optimize_correction_curve(&correction)
    }

    /// Optimizes an equalizer profile directly from a correction curve `[(freq, target_gain_db)]`.
    #[allow(clippy::needless_range_loop)]
    pub fn optimize_correction_curve(
        &self,
        correction: &[(f64, f64)],
    ) -> Result<EqProfile, AutoEqError> {
        if correction.is_empty() {
            return Err(AutoEqError::EmptyData("Empty correction curve".into()));
        }

        let freqs: Vec<f64> = correction.iter().map(|&(f, _)| f).collect();
        let c_vals: Vec<f64> = correction.iter().map(|&(_, c)| c).collect();
        let ctx = GridContext::new(&freqs, self.config.sample_rate);

        let n = freqs.len();
        let max_filters = self.config.max_peaking_filters.clamp(1, 10);
        let f_min = self.config.min_freq.max(20.0);
        let f_max = self.config.max_freq.min(18000.0);
        let min_gain = self.config.min_gain_db;
        let max_gain = self.config.max_gain_db;
        let min_q = self.config.min_q.max(0.4);
        let max_q = self.config.max_q.min(9.0);

        let mut current_total = vec![0.0; n];
        let mut filters: Vec<BiquadFilter> = Vec::with_capacity(max_filters);

        // -------------------------------------------------------------
        // Step 1: Bass Shelf Evaluation (Low Shelf)
        // -------------------------------------------------------------
        // Target curves with bass elevation (e.g. Harman target shelf) cannot be physically
        // matched by a peaking filter without rolling off towards 0 dB at DC.
        // A Low Shelf filter maintains flat asymptotic gain down to 0 Hz with zero ripples.
        let mut sub_bass_sum = 0.0;
        let mut sub_bass_cnt = 0.0;
        let mut mid_bass_sum = 0.0;
        let mut mid_bass_cnt = 0.0;

        for i in 0..n {
            if freqs[i] >= 20.0 && freqs[i] <= 50.0 {
                sub_bass_sum += c_vals[i];
                sub_bass_cnt += 1.0;
            } else if freqs[i] >= 200.0 && freqs[i] <= 350.0 {
                mid_bass_sum += c_vals[i];
                mid_bass_cnt += 1.0;
            }
        }

        let bass_shelf_needed = if sub_bass_cnt > 0.0 && mid_bass_cnt > 0.0 {
            (sub_bass_sum / sub_bass_cnt) - (mid_bass_sum / mid_bass_cnt)
        } else {
            0.0
        };

        // Mathematical JND Criterion: Only allocate Low Shelf if bass shelf step >= 1.0 dB
        if bass_shelf_needed.abs() >= 1.0 && filters.len() < max_filters {
            let init_shelf = BiquadFilter::new_low_shelf(105.0, bass_shelf_needed.clamp(min_gain, max_gain), 0.71);
            let refined_shelf = optimize_single_low_shelf(&ctx, &c_vals, init_shelf, min_gain, max_gain);
            let baseline_mse = ctx.evaluate_total_mse_zero(&c_vals);
            let shelf_mse = ctx.evaluate_filter_mse(&c_vals, &refined_shelf);

            // Marginal improvement: ensure shelf reduces baseline MSE significantly
            if shelf_mse < baseline_mse * 0.96 && refined_shelf.gain_db.abs() >= 0.8 {
                let mut h_buf = vec![0.0; n];
                ctx.evaluate_biquad(&refined_shelf, &mut h_buf);
                for i in 0..n {
                    current_total[i] += h_buf[i];
                }
                filters.push(refined_shelf);
            }
        }

        // -------------------------------------------------------------
        // Step 2: Peaking Filters - Allocated strictly when mathematically necessary
        // -------------------------------------------------------------
        while filters.len() < max_filters {
            let mut r = vec![0.0; n];
            for i in 0..n {
                r[i] = c_vals[i] - current_total[i];
            }
            let current_mse = ctx.evaluate_total_mse_zero(&r);

            let mut max_weighted_residual = -1.0_f64;
            let mut peak_idx = None;

            for i in 0..n {
                let f_i = freqs[i];
                if f_i < f_min || f_i > f_max {
                    continue;
                }

                // Critical Band Separation (Bark/ERB): Do not crowd filters
                let too_close = filters.iter().any(|flt| {
                    let ratio = (f_i / flt.freq).max(flt.freq / f_i);
                    if flt.filter_type == BiquadFilterType::LowShelf {
                        ratio < 1.85 || f_i < flt.freq * 1.3
                    } else if flt.filter_type == BiquadFilterType::HighShelf {
                        ratio < 1.85 || f_i > flt.freq / 1.3
                    } else {
                        ratio < 1.55
                    }
                });
                if too_close {
                    continue;
                }

                let weighted_res = ctx.weights[i] * r[i].abs();
                if weighted_res > max_weighted_residual {
                    max_weighted_residual = weighted_res;
                    peak_idx = Some(i);
                }
            }

            let peak_idx = match peak_idx {
                Some(idx) => idx,
                None => break,
            };

            // Mathematical Criterion 1: Just Noticeable Difference (JND)
            // If the maximum residual peak is under 1.0 dB, human hearing cannot distinguish it. Stop!
            if r[peak_idx].abs() < 1.0 {
                break;
            }

            let f_peak = freqs[peak_idx].clamp(f_min, f_max);
            let g_init = r[peak_idx].clamp(min_gain, max_gain);

            // Psychoacoustic candidate Qs based on ERB critical bands
            let candidate_qs: &[f64] = if f_peak < 200.0 {
                &[0.6, 0.9, 1.2]
            } else if f_peak > 6000.0 {
                &[1.0, 1.414, 2.0]
            } else {
                &[0.8, 1.2, 1.8, 2.5]
            };
            let mut best_q = 1.414;
            let mut best_initial_mse = f64::MAX;

            for &q in candidate_qs {
                let flt = BiquadFilter::new_peaking(f_peak, g_init, q);
                let mse = ctx.evaluate_filter_mse(&r, &flt);
                if mse < best_initial_mse {
                    best_initial_mse = mse;
                    best_q = q;
                }
            }

            let initial_flt = BiquadFilter::new_peaking(f_peak, g_init, best_q);

            let filter_min_q = if f_peak < 200.0 { 0.4 } else { min_q };
            let filter_max_q = if f_peak < 200.0 { 1.4 } else if f_peak > 8000.0 { 2.5 } else { max_q };
            let filter_f_min = if f_peak < 200.0 { f_min.max(35.0) } else { 80.0 };

            // Local refinement with coordinate descent
            let refined = optimize_single_peaking(
                &ctx,
                &r,
                initial_flt,
                filter_f_min,
                f_max,
                min_gain,
                max_gain,
                filter_min_q,
                filter_max_q,
                3,
            );

            let refined_mse = ctx.evaluate_filter_mse(&r, &refined);

            // Mathematical Criterion 2: Marginal MSE Reduction (Occam's Razor)
            // A filter is only retained if it reduces the remaining error by >= 3.5%
            // and has an audible gain >= 0.8 dB.
            let relative_improvement = (current_mse - refined_mse) / current_mse.max(1e-9);
            if relative_improvement >= 0.035 && refined.gain_db.abs() >= 0.8 {
                let mut h_buf = vec![0.0; n];
                ctx.evaluate_biquad(&refined, &mut h_buf);
                for i in 0..n {
                    current_total[i] += h_buf[i];
                }
                filters.push(refined);
            } else {
                break;
            }
        }

        // -------------------------------------------------------------
        // Step 3: Joint Cyclic Coordinate Descent (Refinamiento Cíclico)
        // -------------------------------------------------------------
        if filters.len() > 1 {
            let passes = 3;
            for _pass in 0..passes {
                let mut any_improved = false;

                for k in 0..filters.len() {
                    let mut old_h = vec![0.0; n];
                    ctx.evaluate_biquad(&filters[k], &mut old_h);

                    let mut r_partial = vec![0.0; n];
                    for i in 0..n {
                        r_partial[i] = c_vals[i] - (current_total[i] - old_h[i]);
                    }

                    let old_mse = ctx.evaluate_filter_mse(&r_partial, &filters[k]);

                    let refined = if filters[k].filter_type == BiquadFilterType::LowShelf {
                        optimize_single_low_shelf(&ctx, &r_partial, filters[k], min_gain, max_gain)
                    } else {
                        let f_curr = filters[k].freq;
                        let k_min_q = if f_curr < 200.0 { 0.4 } else { min_q };
                        let k_max_q = if f_curr < 200.0 { 1.4 } else if f_curr > 8000.0 { 2.5 } else { max_q };
                        let k_f_min = if f_curr < 200.0 { f_min.max(35.0) } else { 80.0 };

                        optimize_single_peaking(
                            &ctx,
                            &r_partial,
                            filters[k],
                            k_f_min,
                            f_max,
                            min_gain,
                            max_gain,
                            k_min_q,
                            k_max_q,
                            2,
                        )
                    };

                    let new_mse = ctx.evaluate_filter_mse(&r_partial, &refined);
                    if new_mse < old_mse - 1e-6 {
                        let mut new_h = vec![0.0; n];
                        ctx.evaluate_biquad(&refined, &mut new_h);
                        for i in 0..n {
                            current_total[i] += new_h[i] - old_h[i];
                        }
                        filters[k] = refined;
                        any_improved = true;
                    }
                }

                if !any_improved {
                    break;
                }
            }
        }

        // Prune filters with negligible gain (< 0.15 dB)
        filters.retain(|f| f.gain_db.abs() >= 0.15);

        // Sort filters by center frequency for clean order
        filters.sort_by(|a, b| a.freq.partial_cmp(&b.freq).unwrap_or(std::cmp::Ordering::Equal));

        let final_mse = self.compute_mse(correction, &filters);
        let mut profile = EqProfile::new(filters, 0.0, final_mse);
        profile.compute_anti_clipping_preamp(self.config.sample_rate, self.config.headroom_db);

        Ok(profile)
    }
}

/// Backward compatibility struct for legacy `AutoEqOptimizer`.
pub struct AutoEqOptimizer {
    pub target_curve: Vec<f32>,
    pub measured_curve: Vec<f32>,
    pub frequencies: Vec<f32>,
}

impl AutoEqOptimizer {
    pub fn new(frequencies: Vec<f32>, target: Vec<f32>, measured: Vec<f32>) -> Self {
        Self {
            frequencies,
            target_curve: target,
            measured_curve: measured,
        }
    }

    pub fn calculate_error_curve(&self) -> Vec<f32> {
        self.measured_curve
            .iter()
            .zip(self.target_curve.iter())
            .map(|(m, t)| m - t)
            .collect()
    }

    pub fn optimize(
        &self,
        num_peaking: usize,
        _num_low_shelf: usize,
        _num_high_shelf: usize,
    ) -> Vec<crate::api::simple::ActiveFilter> {
        let f64_freqs: Vec<f64> = self.frequencies.iter().map(|&f| f as f64).collect();
        let f64_meas: Vec<f64> = self.measured_curve.iter().map(|&m| m as f64).collect();
        let f64_targ: Vec<f64> = self.target_curve.iter().map(|&t| t as f64).collect();

        if let (Ok(meas), Ok(targ)) = (
            EarphoneMeasurement::new("AutoEq", "Headphone", f64_freqs.clone(), f64_meas),
            TargetCurve::new("Target", f64_freqs, f64_targ),
        ) {
            let config = AutoEqConfig {
                max_peaking_filters: num_peaking,
                ..Default::default()
            };
            let engine = AutoEqEngine::new(config);
            if let Ok(profile) = engine.optimize(&meas, &targ) {
                return profile.to_active_filters();
            }
        }

        Vec::new()
    }
}

// -----------------------------------------------------------------------------
// Numerical Optimizer Helper Structures and Functions
// -----------------------------------------------------------------------------

/// Precomputed grid context for evaluating filters and residuals with high performance.
struct GridContext {
    freqs: Vec<f64>,
    weights: Vec<f64>,
    sum_weights: f64,
    cos_w: Vec<f64>,
    sin_w: Vec<f64>,
    cos_2w: Vec<f64>,
    sin_2w: Vec<f64>,
    sample_rate: f64,
}

#[allow(clippy::needless_range_loop)]
impl GridContext {
    fn new(freqs: &[f64], sample_rate: f64) -> Self {
        let n = freqs.len();
        let mut weights = Vec::with_capacity(n);
        let mut cos_w = Vec::with_capacity(n);
        let mut sin_w = Vec::with_capacity(n);
        let mut cos_2w = Vec::with_capacity(n);
        let mut sin_2w = Vec::with_capacity(n);
        let mut sum_weights = 0.0;

        let nyquist = sample_rate * 0.5;
        for &f in freqs {
            let clamped_f = f.clamp(1.0, nyquist - 1e-4);
            let w = 2.0 * PI * clamped_f / sample_rate;
            let weight = psychoacoustic_weight(f);
            weights.push(weight);
            sum_weights += weight;
            cos_w.push(w.cos());
            sin_w.push(w.sin());
            cos_2w.push((2.0 * w).cos());
            sin_2w.push((2.0 * w).sin());
        }

        Self {
            freqs: freqs.to_vec(),
            weights,
            sum_weights: if sum_weights > 0.0 { sum_weights } else { 1.0 },
            cos_w,
            sin_w,
            cos_2w,
            sin_2w,
            sample_rate,
        }
    }

    /// Evaluates the magnitude in dB of a single biquad across the grid into `out`.
    #[inline]
    fn evaluate_biquad(&self, filter: &BiquadFilter, out: &mut [f64]) {
        let (b0, b1, b2, a1, a2) = filter.rbj_coefficients(self.sample_rate);
        for i in 0..self.freqs.len() {
            let num_re = b0 + b1 * self.cos_w[i] + b2 * self.cos_2w[i];
            let num_im = -b1 * self.sin_w[i] - b2 * self.sin_2w[i];
            let den_re = 1.0 + a1 * self.cos_w[i] + a2 * self.cos_2w[i];
            let den_im = -a1 * self.sin_w[i] - a2 * self.sin_2w[i];

            let num_mag_sq = num_re * num_re + num_im * num_im;
            let den_mag_sq = den_re * den_re + den_im * den_im;

            if den_mag_sq <= 1e-20 {
                out[i] = 0.0;
            } else {
                let mag_sq = num_mag_sq / den_mag_sq;
                if mag_sq <= 1e-20 {
                    out[i] = -200.0;
                } else {
                    out[i] = 10.0 * mag_sq.log10();
                }
            }
        }
    }

    /// Computes the weighted MSE between a target residual R and a candidate biquad filter.
    #[inline]
    fn evaluate_filter_mse(&self, target_residual: &[f64], filter: &BiquadFilter) -> f64 {
        let (b0, b1, b2, a1, a2) = filter.rbj_coefficients(self.sample_rate);
        let mut sum_err = 0.0;

        for i in 0..self.freqs.len() {
            let num_re = b0 + b1 * self.cos_w[i] + b2 * self.cos_2w[i];
            let num_im = -b1 * self.sin_w[i] - b2 * self.sin_2w[i];
            let den_re = 1.0 + a1 * self.cos_w[i] + a2 * self.cos_2w[i];
            let den_im = -a1 * self.sin_w[i] - a2 * self.sin_2w[i];

            let num_mag_sq = num_re * num_re + num_im * num_im;
            let den_mag_sq = den_re * den_re + den_im * den_im;

            let h_db = if den_mag_sq <= 1e-20 {
                0.0
            } else {
                let mag_sq = num_mag_sq / den_mag_sq;
                if mag_sq <= 1e-20 {
                    -200.0
                } else {
                    10.0 * mag_sq.log10()
                }
            };

            let diff = target_residual[i] - h_db;
            sum_err += self.weights[i] * diff * diff;
        }

        sum_err / self.sum_weights
    }

    /// Computes the weighted MSE of a target residual with 0 dB filter (baseline).
    #[inline]
    fn evaluate_total_mse_zero(&self, target_residual: &[f64]) -> f64 {
        let mut sum_err = 0.0;
        for i in 0..self.freqs.len() {
            let diff = target_residual[i];
            sum_err += self.weights[i] * diff * diff;
        }
        sum_err / self.sum_weights
    }
}

/// 1D Golden Section Search for bounded unimodal / local optimization.
fn golden_section_search<F>(mut a: f64, mut b: f64, iterations: usize, mut cost_fn: F) -> f64
where
    F: FnMut(f64) -> f64,
{
    if a > b {
        std::mem::swap(&mut a, &mut b);
    }
    if (b - a).abs() < 1e-9 {
        return a;
    }

    const PHI: f64 = 0.6180339887498949; // (sqrt(5) - 1) / 2
    let mut c = b - PHI * (b - a);
    let mut d = a + PHI * (b - a);
    let mut fc = cost_fn(c);
    let mut fd = cost_fn(d);

    for _ in 0..iterations {
        if fc < fd {
            b = d;
            d = c;
            fd = fc;
            c = b - PHI * (b - a);
            fc = cost_fn(c);
        } else {
            a = c;
            c = d;
            fc = fd;
            d = a + PHI * (b - a);
            fd = cost_fn(d);
        }
    }

    (a + b) * 0.5
}

/// Optimizes a single peaking filter (f0, Gain, Q) against a target residual curve.
#[allow(clippy::too_many_arguments)]
fn optimize_single_peaking(
    ctx: &GridContext,
    target_residual: &[f64],
    initial_filter: BiquadFilter,
    min_f: f64,
    max_f: f64,
    min_gain: f64,
    max_gain: f64,
    min_q: f64,
    max_q: f64,
    num_cycles: usize,
) -> BiquadFilter {
    let mut current = initial_filter;
    let initial_mse = ctx.evaluate_filter_mse(target_residual, &initial_filter);

    for _ in 0..num_cycles {
        // 1. Optimize Gain in [min_gain, max_gain]
        let f0 = current.freq;
        let q = current.q;
        let best_g = golden_section_search(min_gain, max_gain, 12, |g| {
            let flt = BiquadFilter::new_peaking(f0, g, q);
            ctx.evaluate_filter_mse(target_residual, &flt)
        });
        current.gain_db = best_g;

        // 2. Optimize Frequency (log domain) in [f0 / 1.6, f0 * 1.6] clamped to [min_f, max_f]
        let g = current.gain_db;
        let f_low = (current.freq / 1.6).max(min_f);
        let f_high = (current.freq * 1.6).min(max_f);
        if f_low < f_high {
            let best_log_f = golden_section_search(f_low.ln(), f_high.ln(), 12, |log_f| {
                let f = log_f.exp();
                let flt = BiquadFilter::new_peaking(f, g, q);
                ctx.evaluate_filter_mse(target_residual, &flt)
            });
            current.freq = best_log_f.exp();
        }

        // 3. Optimize Q (log domain) in [min_q, max_q]
        let f0 = current.freq;
        let q_low = (current.q / 2.0).max(min_q);
        let q_high = (current.q * 2.0).min(max_q);
        if q_low < q_high {
            let best_log_q = golden_section_search(q_low.ln(), q_high.ln(), 12, |log_q| {
                let q_val = log_q.exp();
                let flt = BiquadFilter::new_peaking(f0, g, q_val);
                ctx.evaluate_filter_mse(target_residual, &flt)
            });
            current.q = best_log_q.exp();
        }
    }

    let final_mse = ctx.evaluate_filter_mse(target_residual, &current);
    if final_mse <= initial_mse {
        current
    } else {
        initial_filter
    }
}

/// Optimizes a single Low Shelf filter (f0, Gain, Q) against a target residual curve.
fn optimize_single_low_shelf(
    ctx: &GridContext,
    target_residual: &[f64],
    initial_filter: BiquadFilter,
    min_gain: f64,
    max_gain: f64,
) -> BiquadFilter {
    let mut current = initial_filter;
    let initial_mse = ctx.evaluate_filter_mse(target_residual, &initial_filter);

    for _ in 0..3 {
        // 1. Optimize Gain in [min_gain, max_gain]
        let f0 = current.freq;
        let q = current.q;
        let best_g = golden_section_search(min_gain, max_gain, 14, |g| {
            let flt = BiquadFilter::new_low_shelf(f0, g, q);
            ctx.evaluate_filter_mse(target_residual, &flt)
        });
        current.gain_db = best_g;

        // 2. Optimize corner frequency in [60.0, 160.0] Hz
        let g = current.gain_db;
        let best_log_f = golden_section_search((60.0_f64).ln(), (160.0_f64).ln(), 14, |log_f| {
            let f = log_f.exp();
            let flt = BiquadFilter::new_low_shelf(f, g, q);
            ctx.evaluate_filter_mse(target_residual, &flt)
        });
        current.freq = best_log_f.exp();

        // 3. Optimize Q in [0.5, 1.1]
        let f0 = current.freq;
        let best_q = golden_section_search(0.5, 1.1, 12, |q_val| {
            let flt = BiquadFilter::new_low_shelf(f0, g, q_val);
            ctx.evaluate_filter_mse(target_residual, &flt)
        });
        current.q = best_q;
    }

    let final_mse = ctx.evaluate_filter_mse(target_residual, &current);
    if final_mse <= initial_mse {
        current
    } else {
        initial_filter
    }
}

// -----------------------------------------------------------------------------
// Helper Functions
// -----------------------------------------------------------------------------

/// Piecewise linear interpolation on a logarithmic frequency axis.
fn interpolate_log_scale(frequencies: &[f64], values: &[f64], freq: f64) -> f64 {
    if frequencies.is_empty() || values.is_empty() || !freq.is_finite() {
        return 0.0;
    }
    if frequencies.len() == 1 || freq <= frequencies[0] {
        return values[0];
    }
    if freq >= *frequencies.last().unwrap() {
        return *values.last().unwrap();
    }
    if freq <= 0.0 {
        return values[0];
    }

    let idx = match frequencies.binary_search_by(|f| f.partial_cmp(&freq).unwrap()) {
        Ok(i) => return values[i],
        Err(i) => i,
    };

    let f1 = frequencies[idx - 1];
    let f2 = frequencies[idx];
    let v1 = values[idx - 1];
    let v2 = values[idx];

    if f1 <= 0.0 || f2 <= 0.0 {
        return v1;
    }

    let log_f = freq.log10();
    let log_f1 = f1.log10();
    let log_f2 = f2.log10();

    if (log_f2 - log_f1).abs() < 1e-12 {
        return v1;
    }

    let t = (log_f - log_f1) / (log_f2 - log_f1);
    v1 + t * (v2 - v1)
}

/// Psychoacoustic error weighting function: prioritizes mid-frequencies (100 Hz - 6 kHz)
/// and attenuates high frequencies (> 10 kHz) to avoid ringing on measurement artifacts.
fn psychoacoustic_weight(freq: f64) -> f64 {
    if freq < 60.0 {
        0.8
    } else if freq <= 6000.0 {
        1.0
    } else if freq <= 10000.0 {
        0.7
    } else {
        0.3
    }
}

/// Result of raw channel matching calculation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChannelMatchResultData {
    pub left_filters: Vec<BiquadFilter>,
    pub right_filters: Vec<BiquadFilter>,
    pub matched_l: Vec<(f64, f64)>,
    pub matched_r: Vec<(f64, f64)>,
    pub residual_imbalance_db: f64,
}

/// Computes symmetric raw channel matching:
/// Fits peaking filters to match Raw L and Raw R to their midline average M(f) = (L(f) + R(f))/2.
/// Protects against coupler resonance by tapering correction to 0 dB above 8 kHz.
pub fn compute_symmetric_channel_match(
    l_freqs: &[f64],
    l_dbs: &[f64],
    r_freqs: &[f64],
    r_dbs: &[f64],
    max_bands: usize,
) -> ChannelMatchResultData {
    if l_freqs.is_empty() || r_freqs.is_empty() {
        return ChannelMatchResultData {
            left_filters: Vec::new(),
            right_filters: Vec::new(),
            matched_l: Vec::new(),
            matched_r: Vec::new(),
            residual_imbalance_db: 0.0,
        };
    }

    let n = 200;
    let min_f = 20.0_f64;
    let max_f = 20000.0_f64;
    let grid: Vec<f64> = (0..n)
        .map(|i| min_f * (max_f / min_f).powf(i as f64 / (n - 1) as f64))
        .collect();

    let mut l_vals = Vec::with_capacity(n);
    let mut r_vals = Vec::with_capacity(n);
    let mut target_l = Vec::with_capacity(n);

    for &f in &grid {
        let l = interpolate_log_scale(l_freqs, l_dbs, f);
        let r = interpolate_log_scale(r_freqs, r_dbs, f);
        l_vals.push(l);
        r_vals.push(r);

        let delta = l - r;
        let raw_t_l = -delta * 0.5; // (Mid - L) = -Delta / 2

        // Safety tapering above 8 kHz to avoid coupler insertion depth resonance artifacts
        let w = if f <= 8000.0 {
            1.0
        } else if f < 12000.0 {
            0.5 * (1.0 + ((f - 8000.0) / 4000.0 * PI).cos())
        } else {
            0.0
        };

        target_l.push(raw_t_l * w);
    }

    // Fit peaking filters to target_l
    let bands = max_bands.clamp(1, 8);
    let mut residual = target_l.clone();
    let mut left_filters: Vec<BiquadFilter> = Vec::new();
    let sample_rate = 48000.0;

    for _ in 0..bands {
        // Find index of max absolute residual in 40 Hz - 8500 Hz
        let mut max_abs = 0.0;
        let mut best_idx = 0;
        for (i, &f) in grid.iter().enumerate() {
            if f >= 40.0 && f <= 8500.0 {
                let r_abs = residual[i].abs();
                if r_abs > max_abs {
                    max_abs = r_abs;
                    best_idx = i;
                }
            }
        }

        // Psychoacoustic JND threshold: if remaining error < 0.30 dB, stop adding bands
        if max_abs < 0.30 {
            break;
        }

        let f0 = grid[best_idx];
        let initial_gain = residual[best_idx].clamp(-6.0, 6.0);
        let initial_q = 1.414;

        // Local refine (f0, Gain, Q)
        let f_candidates = [f0 * 0.92, f0 * 0.96, f0, f0 * 1.04, f0 * 1.08];
        let gain_candidates = [
            initial_gain * 0.8,
            initial_gain * 0.9,
            initial_gain,
            initial_gain * 1.1,
            initial_gain * 1.2,
        ];
        let q_candidates = [0.8, 1.1, 1.414, 2.0, 2.8];

        let mut best_f = f0;
        let mut best_g = initial_gain;
        let mut best_q = initial_q;
        let mut best_cost = f64::MAX;

        for &cf in &f_candidates {
            if cf < 35.0 || cf > 8500.0 {
                continue;
            }
            for &cg in &gain_candidates {
                let g = cg.clamp(-6.0, 6.0);
                for &cq in &q_candidates {
                    let test_filter = BiquadFilter::new_peaking(cf, g, cq);
                    let mut cost = 0.0;
                    for (i, &f) in grid.iter().enumerate() {
                        if f >= 35.0 && f <= 9000.0 {
                            let resp = test_filter.magnitude_db_at(f, sample_rate);
                            let diff = residual[i] - resp;
                            cost += diff * diff;
                        }
                    }
                    if cost < best_cost {
                        best_cost = cost;
                        best_f = cf;
                        best_g = g;
                        best_q = cq;
                    }
                }
            }
        }

        let filter = BiquadFilter::new_peaking(best_f, best_g, best_q);
        for (i, &f) in grid.iter().enumerate() {
            residual[i] -= filter.magnitude_db_at(f, sample_rate);
        }
        left_filters.push(filter);
    }

    // Cyclic coordinate descent refine pass
    for _pass in 0..2 {
        for idx in 0..left_filters.len() {
            let current = &left_filters[idx];
            let mut partial_res = Vec::with_capacity(n);
            for (i, &f) in grid.iter().enumerate() {
                let mut sum_other = 0.0;
                for (j, flt) in left_filters.iter().enumerate() {
                    if j != idx {
                        sum_other += flt.magnitude_db_at(f, sample_rate);
                    }
                }
                partial_res.push(target_l[i] - sum_other);
            }

            let f0 = current.freq;
            let g0 = current.gain_db;
            let q0 = current.q;

            let f_candidates = [f0 * 0.95, f0, f0 * 1.05];
            let g_candidates = [g0 - 0.4, g0, g0 + 0.4];
            let q_candidates = [q0 * 0.85, q0, q0 * 1.15];

            let mut best_f = f0;
            let mut best_g = g0;
            let mut best_q = q0;
            let mut best_cost = f64::MAX;

            for &cf in &f_candidates {
                if cf < 35.0 || cf > 8500.0 {
                    continue;
                }
                for &cg in &g_candidates {
                    let g = cg.clamp(-6.0, 6.0);
                    for &cq in &q_candidates {
                        let q = cq.clamp(0.6, 4.0);
                        let test_flt = BiquadFilter::new_peaking(cf, g, q);
                        let mut cost = 0.0;
                        for (i, &f) in grid.iter().enumerate() {
                            if f >= 35.0 && f <= 9000.0 {
                                let resp = test_flt.magnitude_db_at(f, sample_rate);
                                let diff = partial_res[i] - resp;
                                cost += diff * diff;
                            }
                        }
                        if cost < best_cost {
                            best_cost = cost;
                            best_f = cf;
                            best_g = g;
                            best_q = q;
                        }
                    }
                }
            }

            left_filters[idx] = BiquadFilter::new_peaking(best_f, best_g, best_q);
        }
    }

    // Right filters are exact inverted anti-symmetric twins
    let right_filters: Vec<BiquadFilter> = left_filters
        .iter()
        .map(|f| BiquadFilter::new_peaking(f.freq, -f.gain_db, f.q))
        .collect();

    // Compute matched curves and residual imbalance
    let mut matched_l = Vec::with_capacity(n);
    let mut matched_r = Vec::with_capacity(n);
    let mut max_residual = 0.0;

    for (i, &f) in grid.iter().enumerate() {
        let mut l_eq = 0.0;
        let mut r_eq = 0.0;
        for flt in &left_filters {
            l_eq += flt.magnitude_db_at(f, sample_rate);
        }
        for flt in &right_filters {
            r_eq += flt.magnitude_db_at(f, sample_rate);
        }

        let ml = l_vals[i] + l_eq;
        let mr = r_vals[i] + r_eq;
        matched_l.push((f, ml));
        matched_r.push((f, mr));

        if f >= 50.0 && f <= 8000.0 {
            let diff = (ml - mr).abs();
            if diff > max_residual {
                max_residual = diff;
            }
        }
    }

    ChannelMatchResultData {
        left_filters,
        right_filters,
        matched_l,
        matched_r,
        residual_imbalance_db: max_residual,
    }
}

// -----------------------------------------------------------------------------
// Unit and Integration Tests
// -----------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_and_correction_curves_relationship() {
        let freqs = vec![20.0, 100.0, 500.0, 1000.0, 5000.0, 10000.0, 20000.0];
        // Measurement has a 4 dB bump at 500 Hz, reference at 1000 Hz is 0 dB
        let meas_db = vec![0.0, 0.0, 4.0, 0.0, -2.0, 0.0, 0.0];
        let target_db = vec![0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];

        let meas = EarphoneMeasurement::new("TestBrand", "TestModel", freqs.clone(), meas_db).unwrap();
        let target = TargetCurve::new("FlatTarget", freqs, target_db).unwrap();

        let engine = AutoEqEngine::new(AutoEqConfig::default());
        let error_curve = engine.compute_error_curve(&meas, &target);
        let correction_curve = engine.compute_correction_curve(&meas, &target);

        assert_eq!(error_curve.len(), correction_curve.len());
        assert!(!error_curve.is_empty());

        for ((f_err, err), (f_corr, corr)) in error_curve.iter().zip(correction_curve.iter()) {
            assert_eq!(f_err, f_corr);
            // Algebraic relationship: Correction(f) == -Error(f)
            assert!(
                (corr + err).abs() < 1e-12,
                "Failed at frequency {f_err}: corr ({corr}) + err ({err}) != 0"
            );
        }

        // At 500 Hz, error should be positive (~ +4 dB) and correction negative (~ -4 dB)
        let corr_at_500 = correction_curve.iter().find(|(f, _)| (f - 500.0).abs() < 30.0).unwrap();
        assert!(
            corr_at_500.1 < -3.5,
            "Expected correction around -4 dB at 500 Hz, got {}",
            corr_at_500.1
        );
    }

    #[test]
    fn test_logarithmic_interpolation_edge_cases() {
        let freqs = vec![100.0, 1000.0, 10000.0];
        let values = vec![0.0, 10.0, 20.0];

        // 1. Below min frequency clamp
        let val_below = interpolate_log_scale(&freqs, &values, 20.0);
        assert_eq!(val_below, 0.0);
        let val_zero = interpolate_log_scale(&freqs, &values, 0.0);
        assert_eq!(val_zero, 0.0);
        let val_neg = interpolate_log_scale(&freqs, &values, -100.0);
        assert_eq!(val_neg, 0.0);

        // 2. Above max frequency clamp
        let val_above = interpolate_log_scale(&freqs, &values, 25000.0);
        assert_eq!(val_above, 20.0);

        // 3. Single point slice
        let single_f = vec![1000.0];
        let single_v = vec![42.0];
        assert_eq!(interpolate_log_scale(&single_f, &single_v, 20.0), 42.0);
        assert_eq!(interpolate_log_scale(&single_f, &single_v, 1000.0), 42.0);
        assert_eq!(interpolate_log_scale(&single_f, &single_v, 20000.0), 42.0);

        // 4. Empty slice
        assert_eq!(interpolate_log_scale(&[], &[], 1000.0), 0.0);

        // 5. Geometric midpoint interpolation:
        // Midpoint between 100 Hz and 1000 Hz is sqrt(100 * 1000) = 316.227766 Hz -> 5.0 dB
        let geom_mid_1 = (100.0_f64 * 1000.0_f64).sqrt();
        let val_mid_1 = interpolate_log_scale(&freqs, &values, geom_mid_1);
        assert!((val_mid_1 - 5.0).abs() < 1e-6);

        // Midpoint between 1000 Hz and 10000 Hz is sqrt(1000 * 10000) = 3162.27766 Hz -> 15.0 dB
        let geom_mid_2 = (1000.0_f64 * 10000.0_f64).sqrt();
        let val_mid_2 = interpolate_log_scale(&freqs, &values, geom_mid_2);
        assert!((val_mid_2 - 15.0).abs() < 1e-6);

        // Exact match at node
        let val_node = interpolate_log_scale(&freqs, &values, 1000.0);
        assert_eq!(val_node, 10.0);
    }

    #[test]
    fn test_peaking_filter_transfer_function() {
        let sample_rate = 48000.0;

        // Positive gain peaking filter
        let f0 = 1000.0;
        let gain = 6.0;
        let q = 1.414;
        let filter_boost = BiquadFilter::new_peaking(f0, gain, q);

        let mag_f0 = filter_boost.magnitude_db_at(f0, sample_rate);
        assert!(
            (mag_f0 - gain).abs() < 0.05,
            "Expected ~{gain} dB at f0, got {mag_f0}"
        );

        // Distant frequencies must tend to 0 dB
        let mag_far_low = filter_boost.magnitude_db_at(20.0, sample_rate);
        assert!(
            mag_far_low.abs() < 0.1,
            "Expected ~0 dB at 20 Hz, got {mag_far_low}"
        );
        let mag_far_high = filter_boost.magnitude_db_at(20000.0, sample_rate);
        assert!(
            mag_far_high.abs() < 0.1,
            "Expected ~0 dB at 20 kHz, got {mag_far_high}"
        );

        // Negative gain (cut) peaking filter
        let f0_cut = 2500.0;
        let gain_cut = -9.0;
        let q_cut = 2.5;
        let filter_cut = BiquadFilter::new_peaking(f0_cut, gain_cut, q_cut);

        let mag_cut_f0 = filter_cut.magnitude_db_at(f0_cut, sample_rate);
        assert!(
            (mag_cut_f0 - gain_cut).abs() < 0.05,
            "Expected ~{gain_cut} dB at f0, got {mag_cut_f0}"
        );

        // Shelf filters
        let low_shelf = BiquadFilter::new_low_shelf(100.0, 5.0, 0.707);
        let ls_dc = low_shelf.magnitude_db_at(20.0, sample_rate);
        assert!((ls_dc - 5.0).abs() < 0.5);
        let ls_hf = low_shelf.magnitude_db_at(10000.0, sample_rate);
        assert!(ls_hf.abs() < 0.1);

        let high_shelf = BiquadFilter::new_high_shelf(8000.0, 4.0, 0.707);
        let hs_hf = high_shelf.magnitude_db_at(18000.0, sample_rate);
        assert!((hs_hf - 4.0).abs() < 0.5);
        let hs_lf = high_shelf.magnitude_db_at(100.0, sample_rate);
        assert!(hs_lf.abs() < 0.1);
    }

    #[test]
    fn test_autoeq_optimization_reduces_mse() {
        // Create synthetic measurement with peaks and dips
        let n = 200;
        let min_f = 20.0_f64;
        let max_f = 20000.0_f64;
        let mut freqs = Vec::with_capacity(n);
        let mut meas_db = Vec::with_capacity(n);
        let mut target_db = Vec::with_capacity(n);

        for i in 0..n {
            let f = min_f * (max_f / min_f).powf(i as f64 / (n - 1) as f64);
            freqs.push(f);
            target_db.push(0.0); // Flat target

            // Synthetic headphone with:
            // 1. +5 dB bass resonance around 150 Hz
            // 2. -6 dB midrange dip around 1200 Hz
            // 3. +7 dB treble ear canal peak around 4500 Hz
            let d_bass = (f.ln() - 150.0_f64.ln()) / 0.5;
            let d_mid = (f.ln() - 1200.0_f64.ln()) / 0.4;
            let d_treble = (f.ln() - 4500.0_f64.ln()) / 0.3;

            let db = 5.0 * (-0.5 * d_bass * d_bass).exp()
                - 6.0 * (-0.5 * d_mid * d_mid).exp()
                + 7.0 * (-0.5 * d_treble * d_treble).exp();
            meas_db.push(db);
        }

        let meas = EarphoneMeasurement::new("Synthetic", "Headphone X", freqs.clone(), meas_db).unwrap();
        let target = TargetCurve::new("Flat", freqs, target_db).unwrap();

        let mut config = AutoEqConfig::default();
        config.max_peaking_filters = 10;
        let engine = AutoEqEngine::new(config);

        let correction = engine.compute_correction_curve(&meas, &target);
        let initial_mse = engine.compute_mse(&correction, &[]);

        let profile = engine.optimize(&meas, &target).unwrap();
        let final_mse = profile.mse_score;

        let reduction = (initial_mse - final_mse) / initial_mse;
        assert!(
            reduction > 0.70,
            "Expected MSE reduction > 70%, but achieved {:.2}% (initial: {initial_mse}, final: {final_mse})",
            reduction * 100.0
        );
        assert!(!profile.filters.is_empty(), "Should have fitted at least one filter");
        assert!(profile.filters.len() <= 10, "Should not exceed max peaking filters");
    }

    #[test]
    fn test_anti_clipping_preamp_guarantee() {
        let sample_rate = 48000.0;
        let headroom = 0.2;

        // Profile with high positive boost filters (+9 dB at 1kHz, +6 dB at 3kHz)
        let filter1 = BiquadFilter::new_peaking(1000.0, 9.0, 1.414);
        let filter2 = BiquadFilter::new_peaking(3000.0, 6.0, 2.0);

        let mut profile = EqProfile::new(vec![filter1, filter2], 0.0, 0.5);
        profile.compute_anti_clipping_preamp(sample_rate, headroom);

        // Preamp must be strictly negative and at least -(9.0 + headroom)
        assert!(
            profile.preamp_gain_db <= -(9.0 + headroom - 1e-4),
            "Preamp gain ({}) must be <= -9.2 dB",
            profile.preamp_gain_db
        );

        // Mathematical guarantee: across [20 Hz, 20000 Hz],
        // H_total(f) + preamp_gain_db must be <= 0.0 dB
        let test_points = 1000;
        let min_f = 20.0_f64;
        let max_f = 20000.0_f64;
        for i in 0..=test_points {
            let f = min_f * (max_f / min_f).powf(i as f64 / test_points as f64);
            let total = profile.combined_magnitude_db_at(f, sample_rate) + profile.preamp_gain_db;
            assert!(
                total <= 1e-5,
                "Clipping violation at {f:.1} Hz: total gain is {total:.4} dB > 0.0 dB"
            );
            assert!(
                total <= -headroom + 1e-4,
                "Headroom violation at {f:.1} Hz: total gain is {total:.4} dB > -{headroom} dB"
            );
        }

        // Only cut filters (all negative gains): preamp must be 0.0
        let cut_filter = BiquadFilter::new_peaking(1000.0, -6.0, 1.0);
        let mut cut_profile = EqProfile::new(vec![cut_filter], 0.0, 0.1);
        cut_profile.compute_anti_clipping_preamp(sample_rate, headroom);
        assert_eq!(cut_profile.preamp_gain_db, 0.0, "Preamp should be 0.0 when no boost exists");
    }

    #[test]
    fn test_sqlite_target_and_measurement_integration() {
        let conn = Connection::open_in_memory().unwrap();
        crate::database::setup_database(&conn).unwrap();

        // 1. Insert Target Curve into SQLite ("Harman Over-Ear 2018")
        let target_freqs = [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0];
        let target_dbs = [5.0, 4.5, 3.0, 1.0, 0.0, 0.0, 2.5, 3.0, -1.0, -5.0];
        let target_points: Vec<crate::fetcher::MeasurementPoint> = target_freqs
            .iter()
            .zip(target_dbs.iter())
            .map(|(&f, &db)| crate::fetcher::MeasurementPoint {
                frequency: f as f32,
                raw: db as f32,
                target: None,
            })
            .collect();
        let target_blob = serde_json::to_vec(&target_points).unwrap();
        crate::database::insert_target(&conn, "Harman Over-Ear 2018", &target_blob).unwrap();

        // 2. Insert Measurement into SQLite ("Sennheiser HD600")
        let meas_freqs = [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0];
        let meas_dbs = [-2.0, 0.0, 2.0, 2.5, 1.0, 0.0, 1.0, 8.0, 1.0, -8.0];
        let meas_points: Vec<crate::fetcher::MeasurementPoint> = meas_freqs
            .iter()
            .zip(meas_dbs.iter())
            .map(|(&f, &db)| crate::fetcher::MeasurementPoint {
                frequency: f as f32,
                raw: db as f32,
                target: None,
            })
            .collect();
        let meas_blob = serde_json::to_vec(&meas_points).unwrap();
        crate::database::insert_measurement(
            &conn,
            "Sennheiser",
            "HD600",
            Some("Over-Ear"),
            Some("Gras 43AG"),
            Some("data/sennheiser_hd600.csv"),
            Some(&meas_blob),
        )
        .unwrap();

        // 3. Test list_available_targets
        let targets_list = TargetCurve::list_available_targets(&conn).unwrap();
        assert_eq!(targets_list, vec!["Harman Over-Ear 2018".to_string()]);

        // 4. Test TargetCurve::load_by_preset with HarmanOverEar2018
        let loaded_target = TargetCurve::load_by_preset(&conn, TargetPreset::HarmanOverEar2018).unwrap();
        assert_eq!(loaded_target.name, "Harman Over-Ear 2018");
        assert_eq!(loaded_target.frequencies.len(), target_freqs.len());

        // 5. Test EarphoneMeasurement::load_from_db
        let loaded_meas = EarphoneMeasurement::load_from_db(&conn, "HD600").unwrap();
        assert_eq!(loaded_meas.brand, "Sennheiser");
        assert_eq!(loaded_meas.model, "HD600");

        // Also test query with full brand and model
        let loaded_meas_full = EarphoneMeasurement::load_from_db(&conn, "Sennheiser HD600").unwrap();
        assert_eq!(loaded_meas_full.model, "HD600");

        // 6. Test EarphoneMeasurement::load_by_file_path
        let loaded_by_path = EarphoneMeasurement::load_by_file_path(&conn, "data/sennheiser_hd600.csv").unwrap();
        assert_eq!(loaded_by_path.model, "HD600");

        // 7. Run AutoEq optimization on the loaded measurement and target
        let engine = AutoEqEngine::new(AutoEqConfig::default());
        let profile = engine.optimize(&loaded_meas, &loaded_target).unwrap();

        assert!(!profile.filters.is_empty(), "Should generate filters for HD600");
        assert!(profile.mse_score >= 0.0);
        assert!(profile.preamp_gain_db <= 0.0);

        // Verify conversion to active filters for Flutter / FFI bridge
        let active_filters = profile.to_active_filters();
        assert_eq!(active_filters.len(), profile.filters.len());
        for af in &active_filters {
            assert!(af.freq >= 20.0 && af.freq <= 18000.0);
            assert!(af.q >= 0.4 && af.q <= 9.0);
        }
    }

    #[test]
    fn test_clean_bass_response_no_wobbles() {
        // Measurement with rolled-off sub-bass (typical open-back or neutral IEM)
        let m_freqs = vec![20.0, 30.0, 40.0, 60.0, 80.0, 100.0, 200.0, 1000.0, 3000.0, 10000.0];
        let m_dbs = vec![-6.0, -4.5, -3.0, -1.0, 0.0, 0.5, 0.0, 0.0, 2.0, 0.0];
        let meas = EarphoneMeasurement::new("Test", "BassRolloff", m_freqs, m_dbs).unwrap();

        // Target with Harman-style smooth elevated bass (+5 dB in sub-bass, 0 dB at 200 Hz)
        let t_freqs = vec![20.0, 30.0, 40.0, 60.0, 80.0, 100.0, 200.0, 1000.0, 3000.0, 10000.0];
        let t_dbs = vec![5.0, 5.0, 4.8, 4.0, 2.5, 1.2, 0.0, 0.0, 2.0, 0.0];
        let targ = TargetCurve::new("HarmanBass", t_freqs, t_dbs).unwrap();

        let config = AutoEqConfig::default();
        let engine = AutoEqEngine::new(config);
        let profile = engine.optimize(&meas, &targ).unwrap();

        // Check bass filters below 120 Hz:
        let bass_filters: Vec<_> = profile.filters.iter().filter(|f| f.freq < 120.0).collect();
        // Should not have more than 2 filters in the sub-120 Hz band
        assert!(bass_filters.len() <= 2, "Bass filters count ({}) should be <= 2", bass_filters.len());

        for bf in &bass_filters {
            // Must have clean, broad Q (<= 1.4)
            assert!(bf.q <= 1.4, "Bass filter at {} Hz had excessively sharp Q: {}", bf.freq, bf.q);
            assert!(bf.freq >= 35.0, "Bass filter should not be placed below 35 Hz: {}", bf.freq);
        }

        // Verify compensated response curve from 20 Hz to 100 Hz is smooth
        let sub_bass_eval_freqs = [20.0, 25.0, 30.0, 40.0, 50.0, 60.0, 80.0, 100.0];
        let mut compensated = Vec::new();
        for &f in &sub_bass_eval_freqs {
            let m_val = meas.interpolate_at(f);
            let eq_gain = profile.combined_magnitude_db_at(f, 48000.0);
            compensated.push(m_val + eq_gain);
        }

        // Ensure no wild ripples or local dips in sub-bass (difference between consecutive points is smooth)
        for i in 1..compensated.len() {
            let step = (compensated[i] - compensated[i - 1]).abs();
            assert!(step < 3.5, "Excessive jump in sub-bass between step {} and {}: {} dB", i - 1, i, step);
        }
    }

    #[test]
    fn test_symmetric_channel_matching_reduces_imbalance() {
        let freqs = vec![20.0, 50.0, 100.0, 300.0, 1000.0, 3000.0, 6000.0, 10000.0, 20000.0];
        // Channel L has a +2.5 dB bump at 3000 Hz, Channel R has a -1.5 dB dip at 3000 Hz (4.0 dB imbalance)
        let l_dbs = vec![0.0, 0.0, 0.5, 0.0, 0.0, 2.5, 0.0, 0.0, 0.0];
        let r_dbs = vec![0.0, 0.0, -0.5, 0.0, 0.0, -1.5, 0.0, 0.0, 0.0];

        let res = compute_symmetric_channel_match(&freqs, &l_dbs, &freqs, &r_dbs, 6);

        assert!(!res.left_filters.is_empty(), "Should generate left correction filters");
        assert_eq!(res.left_filters.len(), res.right_filters.len(), "L and R must have paired filter counts");

        // Verify anti-symmetry: R gain = -L gain, with matching f0 and Q
        for (lf, rf) in res.left_filters.iter().zip(res.right_filters.iter()) {
            assert_eq!(lf.freq, rf.freq);
            assert_eq!(lf.q, rf.q);
            assert!((lf.gain_db + rf.gain_db).abs() < 1e-10, "Gains must be opposite: {} vs {}", lf.gain_db, rf.gain_db);
        }

        // The residual imbalance in the 50-8000 Hz range should be significantly reduced from 4.0 dB to < 0.8 dB
        assert!(
            res.residual_imbalance_db < 0.8,
            "Residual imbalance {} dB should be < 0.8 dB",
            res.residual_imbalance_db
        );
    }
}

