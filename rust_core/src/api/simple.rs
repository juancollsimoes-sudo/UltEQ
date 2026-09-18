#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

#[derive(Clone, Copy, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

#[derive(Clone, Copy, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum FilterType {
    Peaking,
    LowShelf,
    HighShelf,
}

#[derive(Clone, Copy, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ActiveFilter {
    pub filter_type: FilterType,
    pub freq: f32,
    pub gain: f32,
    pub q: f32,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct DualMeasurementResult {
    pub is_dual_channel: bool,
    pub raw_l: Vec<Point>,
    pub raw_r: Vec<Point>,
    pub raw_mid: Vec<Point>,
    pub avg_imbalance_db: f32,
    pub max_imbalance_db: f32,
    pub max_imbalance_freq: f32,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ChannelMatchResult {
    pub left_filters: Vec<ActiveFilter>,
    pub right_filters: Vec<ActiveFilter>,
    pub matched_l: Vec<Point>,
    pub matched_r: Vec<Point>,
    pub residual_imbalance_db: f32,
}

#[flutter_rust_bridge::frb(sync)]
pub fn calculate_biquad_response(filters: Vec<ActiveFilter>) -> Vec<Point> {
    use biquad::{Coefficients, ToHertz, Type};
    
    let fs = 48000.0;
    
    let mut points = Vec::new();
    let min_f: f32 = 20.0;
    let max_f: f32 = 20000.0;
    let steps = 200;
    
    for i in 0..=steps {
        let f = min_f * (max_f / min_f).powf(i as f32 / steps as f32);
        points.push(Point { x: f, y: 0.0 });
    }
    
    for filter in filters {
        let biquad_type = match filter.filter_type {
            FilterType::Peaking => Type::PeakingEQ(filter.gain),
            FilterType::LowShelf => Type::LowShelf(filter.gain),
            FilterType::HighShelf => Type::HighShelf(filter.gain),
        };
        
        let coeffs = match Coefficients::<f32>::from_params(biquad_type, fs.hz(), filter.freq.hz(), filter.q) {
            Ok(c) => c,
            Err(_) => continue,
        };
        
        for i in 0..=steps {
            let f = points[i].x;
            
            let omega = 2.0 * std::f32::consts::PI * f / fs;
            let cos_omega = omega.cos();
            let sin_omega = omega.sin();
            let cos_2omega = (2.0 * omega).cos();
            let sin_2omega = (2.0 * omega).sin();
            
            let num_real = coeffs.b0 + coeffs.b1 * cos_omega + coeffs.b2 * cos_2omega;
            let num_imag = -(coeffs.b1 * sin_omega + coeffs.b2 * sin_2omega);
            
            let den_real = 1.0 + coeffs.a1 * cos_omega + coeffs.a2 * cos_2omega;
            let den_imag = -(coeffs.a1 * sin_omega + coeffs.a2 * sin_2omega);
            
            let mag_sq = (num_real * num_real + num_imag * num_imag) / (den_real * den_real + den_imag * den_imag);
            let mag_db = 10.0 * mag_sq.log10();
            
            points[i].y += mag_db;
        }
    }
    
    points
}

pub struct HeadphoneModel {
    pub brand: String,
    pub model: String,
    pub form_factor: Option<String>,
    pub rig: Option<String>,
    pub file_path: Option<String>,
}

fn resolve_db_path(db_path: &str) -> std::path::PathBuf {
    let p = std::path::PathBuf::from(db_path);
    if p.exists() {
        return p;
    }
    let flutter_app_db = std::path::PathBuf::from("flutter_app").join(db_path);
    if flutter_app_db.exists() {
        return flutter_app_db;
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let next_to_exe = dir.join(db_path);
            if next_to_exe.exists() {
                return next_to_exe;
            }
            let in_data = dir.join("data").join(db_path);
            if in_data.exists() {
                return in_data;
            }
        }
    }
    p
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_headphone_models(db_path: String) -> Vec<HeadphoneModel> {
    let mut models = Vec::new();
    let resolved = resolve_db_path(&db_path);
    if let Ok(conn) = rusqlite::Connection::open(&resolved) {
        if let Ok(mut stmt) = conn.prepare("SELECT brand, model, form_factor, rig, file_path FROM measurements ORDER BY brand, model") {
            let model_iter = stmt.query_map([], |row| {
                Ok(HeadphoneModel {
                    brand: row.get(0)?,
                    model: row.get(1)?,
                    form_factor: row.get(2)?,
                    rig: row.get(3)?,
                    file_path: row.get(4)?,
                })
            });
            
            if let Ok(iter) = model_iter {
                for model in iter.flatten() {
                    models.push(model);
                }
            }
        }
    }
    
    models
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_targets(db_path: String) -> Vec<String> {
    let mut targets = Vec::new();
    let resolved = resolve_db_path(&db_path);
    if let Ok(conn) = rusqlite::Connection::open(&resolved) {
        if let Ok(mut stmt) = conn.prepare("SELECT name FROM targets ORDER BY name") {
            let target_iter = stmt.query_map([], |row| {
                let name: String = row.get(0)?;
                Ok(name)
            });
            
            if let Ok(iter) = target_iter {
                for target in iter.flatten() {
                    targets.push(target);
                }
            }
        }
    }
    
    targets
}

#[flutter_rust_bridge::frb]
pub async fn sync_database(db_path: String) -> Result<(), String> {
    let resolved = resolve_db_path(&db_path);
    crate::fetcher::initialize_autoeq_metadata(resolved.to_str().unwrap_or(&db_path))
        .await
        .map_err(|e| e.to_string())
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_target_curve(db_path: String, target_name: String) -> Vec<Point> {
    use rusqlite::Connection;
    
    let mut points = Vec::new();
    let resolved = resolve_db_path(&db_path);
    if let Ok(conn) = Connection::open(&resolved) {
        if let Ok(mut stmt) = conn.prepare("SELECT points_blob FROM targets WHERE name = ?") {
            if let Ok(mut rows) = stmt.query([&target_name]) {
                if let Ok(Some(row)) = rows.next() {
                    if let Ok(blob) = row.get::<_, Vec<u8>>(0) {
                        if let Ok(parsed_points) = serde_json::from_slice::<Vec<crate::fetcher::MeasurementPoint>>(&blob) {
                            for p in parsed_points {
                                points.push(Point { x: p.frequency, y: p.raw });
                            }
                        }
                    }
                }
            }
        }
    }
    points
}

#[flutter_rust_bridge::frb(sync)]
pub fn parse_csv_measurement(csv_content: String) -> DualMeasurementResult {
    let mut rdr = csv::ReaderBuilder::new()
        .flexible(true)
        .from_reader(csv_content.as_bytes());

    let headers = match rdr.headers() {
        Ok(h) => h.clone(),
        Err(_) => {
            return DualMeasurementResult {
                is_dual_channel: false,
                raw_l: Vec::new(),
                raw_r: Vec::new(),
                raw_mid: Vec::new(),
                avg_imbalance_db: 0.0,
                max_imbalance_db: 0.0,
                max_imbalance_freq: 0.0,
            };
        }
    };

    let mut freq_idx: Option<usize> = None;
    let mut left_idx: Option<usize> = None;
    let mut right_idx: Option<usize> = None;
    let mut raw_idx: Option<usize> = None;

    for (i, h) in headers.iter().enumerate() {
        let clean = h.trim().to_lowercase();
        if clean == "frequency" || clean == "freq" || clean == "hz" || clean.contains("freq") {
            freq_idx = Some(i);
        } else if clean == "raw_l" || clean == "left" || clean == "spl_left" || clean == "spl l" || clean == "l" || clean == "raw (l)" || clean == "ch1" {
            left_idx = Some(i);
        } else if clean == "raw_r" || clean == "right" || clean == "spl_right" || clean == "spl r" || clean == "r" || clean == "raw (r)" || clean == "ch2" {
            right_idx = Some(i);
        } else if clean == "raw" || clean == "spl" || clean == "db" {
            raw_idx = Some(i);
        }
    }

    let f_idx = freq_idx.unwrap_or(0);
    let mut pts_l = Vec::new();
    let mut pts_r = Vec::new();
    let mut pts_mid = Vec::new();

    let has_stereo = left_idx.is_some() && right_idx.is_some();

    for result in rdr.records() {
        if let Ok(rec) = result {
            let f = rec.get(f_idx).unwrap_or("0").trim().parse::<f32>().unwrap_or(0.0);
            if f <= 0.0 || !f.is_finite() { continue; }

            if has_stereo {
                let l = rec.get(left_idx.unwrap()).unwrap_or("0").trim().parse::<f32>().unwrap_or(0.0);
                let r = rec.get(right_idx.unwrap()).unwrap_or("0").trim().parse::<f32>().unwrap_or(0.0);
                pts_l.push(Point { x: f, y: l });
                pts_r.push(Point { x: f, y: r });
                pts_mid.push(Point { x: f, y: (l + r) * 0.5 });
            } else {
                let r_idx = left_idx.or(raw_idx).unwrap_or(1);
                let val = rec.get(r_idx).unwrap_or("0").trim().parse::<f32>().unwrap_or(0.0);
                pts_l.push(Point { x: f, y: val });
                pts_mid.push(Point { x: f, y: val });
            }
        }
    }

    pts_l.sort_by(|a, b| a.x.partial_cmp(&b.x).unwrap_or(std::cmp::Ordering::Equal));
    pts_r.sort_by(|a, b| a.x.partial_cmp(&b.x).unwrap_or(std::cmp::Ordering::Equal));
    pts_mid.sort_by(|a, b| a.x.partial_cmp(&b.x).unwrap_or(std::cmp::Ordering::Equal));

    if has_stereo && !pts_l.is_empty() && pts_l.len() == pts_r.len() {
        let mut sum_imb = 0.0;
        let mut count = 0;
        let mut max_imb = 0.0;
        let mut max_freq = 0.0;

        for (p_l, p_r) in pts_l.iter().zip(pts_r.iter()) {
            if p_l.x >= 50.0 && p_l.x <= 8000.0 {
                let diff = (p_l.y - p_r.y).abs();
                sum_imb += diff;
                count += 1;
                if diff > max_imb {
                    max_imb = diff;
                    max_freq = p_l.x;
                }
            }
        }

        let avg_imb = if count > 0 { sum_imb / count as f32 } else { 0.0 };

        DualMeasurementResult {
            is_dual_channel: true,
            raw_l: pts_l,
            raw_r: pts_r,
            raw_mid: pts_mid,
            avg_imbalance_db: avg_imb,
            max_imbalance_db: max_imb,
            max_imbalance_freq: max_freq,
        }
    } else {
        DualMeasurementResult {
            is_dual_channel: false,
            raw_l: pts_l,
            raw_r: Vec::new(),
            raw_mid: pts_mid,
            avg_imbalance_db: 0.0,
            max_imbalance_db: 0.0,
            max_imbalance_freq: 0.0,
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_dual_headphone_curve(file_path: String) -> DualMeasurementResult {
    let url = format!("https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/measurements/{}", file_path.replace(" ", "%20"));
    
    let handle = std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            if let Ok(client) = reqwest::Client::builder().user_agent("UltEQ").build() {
                if let Ok(response) = client.get(&url).send().await {
                    if let Ok(text) = response.text().await {
                        return parse_csv_measurement(text);
                    }
                }
            }
            DualMeasurementResult {
                is_dual_channel: false,
                raw_l: Vec::new(),
                raw_r: Vec::new(),
                raw_mid: Vec::new(),
                avg_imbalance_db: 0.0,
                max_imbalance_db: 0.0,
                max_imbalance_freq: 0.0,
            }
        })
    });

    handle.join().unwrap_or_else(|_| DualMeasurementResult {
        is_dual_channel: false,
        raw_l: Vec::new(),
        raw_r: Vec::new(),
        raw_mid: Vec::new(),
        avg_imbalance_db: 0.0,
        max_imbalance_db: 0.0,
        max_imbalance_freq: 0.0,
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_headphone_curve(file_path: String) -> Vec<Point> {
    let dual = get_dual_headphone_curve(file_path);
    if !dual.raw_mid.is_empty() {
        dual.raw_mid
    } else {
        dual.raw_l
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn simulate_dual_channel_imbalance(base_curve: Vec<Point>, _seed: u32) -> DualMeasurementResult {
    if base_curve.is_empty() {
        return DualMeasurementResult {
            is_dual_channel: false,
            raw_l: Vec::new(),
            raw_r: Vec::new(),
            raw_mid: Vec::new(),
            avg_imbalance_db: 0.0,
            max_imbalance_db: 0.0,
            max_imbalance_freq: 0.0,
        };
    }

    let mut raw_l = Vec::with_capacity(base_curve.len());
    let mut raw_r = Vec::with_capacity(base_curve.len());
    let mut raw_mid = Vec::with_capacity(base_curve.len());

    let mut sum_imb = 0.0;
    let mut count = 0;
    let mut max_imb = 0.0;
    let mut max_freq = 0.0;

    for p in &base_curve {
        let f = p.x;
        // Bell 1: 2400 Hz ear canal transition (+1.35 dB on L, -1.35 dB on R)
        let log_dist1 = (f / 2400.0).ln() * 1.2;
        let delta1 = 1.35 * (-0.5 * log_dist1 * log_dist1).exp();

        // Bell 2: 4800 Hz (-1.1 dB on L, +1.1 dB on R)
        let log_dist2 = (f / 4800.0).ln() * 1.8;
        let delta2 = -1.10 * (-0.5 * log_dist2 * log_dist2).exp();

        // Bell 3: 400 Hz gentle warm skew: +0.6 dB
        let log_dist3 = (f / 400.0).ln() * 0.8;
        let delta3 = 0.60 * (-0.5 * log_dist3 * log_dist3).exp();

        let total_delta = delta1 + delta2 + delta3;

        let y_l = p.y + total_delta;
        let y_r = p.y - total_delta;
        let y_m = p.y;

        raw_l.push(Point { x: f, y: y_l });
        raw_r.push(Point { x: f, y: y_r });
        raw_mid.push(Point { x: f, y: y_m });

        if f >= 50.0 && f <= 8000.0 {
            let diff = (y_l - y_r).abs();
            sum_imb += diff;
            count += 1;
            if diff > max_imb {
                max_imb = diff;
                max_freq = f;
            }
        }
    }

    let avg_imb = if count > 0 { sum_imb / count as f32 } else { 0.0 };

    DualMeasurementResult {
        is_dual_channel: true,
        raw_l,
        raw_r,
        raw_mid,
        avg_imbalance_db: avg_imb,
        max_imbalance_db: max_imb,
        max_imbalance_freq: max_freq,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn match_raw_channels(raw_l: Vec<Point>, raw_r: Vec<Point>, max_bands: usize) -> ChannelMatchResult {
    if raw_l.is_empty() || raw_r.is_empty() {
        return ChannelMatchResult {
            left_filters: Vec::new(),
            right_filters: Vec::new(),
            matched_l: raw_l,
            matched_r: raw_r,
            residual_imbalance_db: 0.0,
        };
    }

    let l_freqs: Vec<f64> = raw_l.iter().map(|p| p.x as f64).collect();
    let l_dbs: Vec<f64> = raw_l.iter().map(|p| p.y as f64).collect();
    let r_freqs: Vec<f64> = raw_r.iter().map(|p| p.x as f64).collect();
    let r_dbs: Vec<f64> = raw_r.iter().map(|p| p.y as f64).collect();

    let dsp_result = crate::dsp::autoeq::compute_symmetric_channel_match(
        &l_freqs,
        &l_dbs,
        &r_freqs,
        &r_dbs,
        max_bands,
    );

    let left_filters: Vec<ActiveFilter> = dsp_result
        .left_filters
        .iter()
        .map(|f| f.to_active_filter())
        .collect();

    let right_filters: Vec<ActiveFilter> = dsp_result
        .right_filters
        .iter()
        .map(|f| f.to_active_filter())
        .collect();

    let matched_l: Vec<Point> = dsp_result
        .matched_l
        .into_iter()
        .map(|(f, y)| Point { x: f as f32, y: y as f32 })
        .collect();

    let matched_r: Vec<Point> = dsp_result
        .matched_r
        .into_iter()
        .map(|(f, y)| Point { x: f as f32, y: y as f32 })
        .collect();

    ChannelMatchResult {
        left_filters,
        right_filters,
        matched_l,
        matched_r,
        residual_imbalance_db: dsp_result.residual_imbalance_db as f32,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_audio_devices() -> Vec<String> {
    let mut devices = Vec::new();
    #[cfg(target_os = "windows")]
    {
        devices.push("Default Playback Device (Equalizer APO)".to_string());
    }
    #[cfg(not(target_os = "windows"))]
    {
        if let Ok(output) = std::process::Command::new("pactl")
            .args(&["list", "sinks", "short"])
            .output() {
            let text = String::from_utf8_lossy(&output.stdout);
            for line in text.lines() {
                let parts: Vec<&str> = line.split('\t').collect();
                if parts.len() >= 2 {
                    let dev = parts[1].trim().to_string();
                    if !dev.is_empty() && !devices.contains(&dev) {
                        devices.push(dev);
                    }
                }
            }
        }
    }
    if devices.is_empty() {
        devices.push("Default Output Device".to_string());
    }
    devices
}

#[flutter_rust_bridge::frb(sync)]
pub fn apply_stereo_eq_to_device(
    device_name: String,
    left_filters: Vec<ActiveFilter>,
    right_filters: Vec<ActiveFilter>,
) {
    #[cfg(target_os = "windows")]
    {
        let is_stereo_split = !left_filters.is_empty() && !right_filters.is_empty();
        let mut apo_text = String::new();
        apo_text.push_str("# UltEQ Equalizer APO / Peace Configuration\n");
        
        let all_filters = if is_stereo_split {
            left_filters.iter().chain(right_filters.iter()).collect::<Vec<_>>()
        } else if !left_filters.is_empty() {
            left_filters.iter().collect::<Vec<_>>()
        } else {
            right_filters.iter().collect::<Vec<_>>()
        };

        let max_gain = all_filters.iter()
            .map(|f| f.gain)
            .fold(0.0f32, |acc, g| if g > acc { g } else { acc });
        let preamp = if max_gain > 0.0 { -max_gain } else { 0.0 };
        apo_text.push_str(&format!("Preamp: {:.1} dB\n\n", preamp));

        if is_stereo_split {
            apo_text.push_str("Channel: L\n");
            for (i, filter) in left_filters.iter().enumerate() {
                let label = match filter.filter_type {
                    FilterType::Peaking => "PK",
                    FilterType::LowShelf => "LSC",
                    FilterType::HighShelf => "HSC",
                };
                apo_text.push_str(&format!(
                    "Filter {}: ON {} Fc {:.1} Hz Gain {:.1} dB Q {:.2}\n",
                    i + 1, label, filter.freq, filter.gain, filter.q
                ));
            }

            apo_text.push_str("\nChannel: R\n");
            for (i, filter) in right_filters.iter().enumerate() {
                let label = match filter.filter_type {
                    FilterType::Peaking => "PK",
                    FilterType::LowShelf => "LSC",
                    FilterType::HighShelf => "HSC",
                };
                apo_text.push_str(&format!(
                    "Filter {}: ON {} Fc {:.1} Hz Gain {:.1} dB Q {:.2}\n",
                    i + 1, label, filter.freq, filter.gain, filter.q
                ));
            }
        } else {
            apo_text.push_str("Channel: all\n");
            for (i, filter) in all_filters.iter().enumerate() {
                let label = match filter.filter_type {
                    FilterType::Peaking => "PK",
                    FilterType::LowShelf => "LSC",
                    FilterType::HighShelf => "HSC",
                };
                apo_text.push_str(&format!(
                    "Filter {}: ON {} Fc {:.1} Hz Gain {:.1} dB Q {:.2}\n",
                    i + 1, label, filter.freq, filter.gain, filter.q
                ));
            }
        }

        let cf_mode = get_active_crossfeed_mode();
        let is_crossfeed_active = cf_mode != CrossfeedPresetMode::Off;
        if is_crossfeed_active {
            let (cf_g_direct, cf_g_cross) = match cf_mode {
                CrossfeedPresetMode::Studio => (0.75, 0.50),
                _ => (0.85, 0.35),
            };
            apo_text.push_str(&format!(
                "\n# Bauer BS2B Crossfeed\nCopy: L={:.2}*L+{:.2}*R R={:.2}*R+{:.2}*L\n",
                cf_g_direct, cf_g_cross, cf_g_direct, cf_g_cross
            ));
        }

        // Potential Equalizer APO directory paths
        let apo_dirs = [
            r"C:\Program Files\EqualizerAPO\config",
            r"C:\Program Files (x86)\EqualizerAPO\config",
        ];

        let mut written = false;
        for dir in &apo_dirs {
            let config_dir = std::path::Path::new(dir);
            if config_dir.exists() {
                // Write directly to config.txt
                let config_file = config_dir.join("config.txt");
                if let Err(e) = std::fs::write(&config_file, &apo_text) {
                    eprintln!("Failed to write to {:?}: {}", config_file, e);
                } else {
                    written = true;
                }

                // Also write to peace.txt since user has Peace GUI
                let peace_file = config_dir.join("peace.txt");
                let _ = std::fs::write(&peace_file, &apo_text);

                // Also write to dedicated ulteq.txt
                let ulteq_file = config_dir.join("ulteq.txt");
                let _ = std::fs::write(&ulteq_file, &apo_text);
            }
        }

        // Save convenient copies for Peace manual import
        if let Ok(user_profile) = std::env::var("USERPROFILE") {
            let desktop_path = format!(r"{}\Desktop\ulteq_peace_import.txt", user_profile);
            let _ = std::fs::write(&desktop_path, &apo_text);
        }

        // Also write in current working directory and temp
        let _ = std::fs::write("ulteq_apo_config.txt", &apo_text);
        if let Ok(temp_dir) = std::env::var("TEMP") {
            let temp_apo = format!(r"{}\ulteq_apo_config.txt", temp_dir);
            let _ = std::fs::write(&temp_apo, &apo_text);
        }

        if !written {
            eprintln!("Warning: Equalizer APO config folder not found or write access denied.");
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        use std::fs::File;
        use std::io::Write;
        use std::process::Command;

        let cf_mode = get_active_crossfeed_mode();
        let is_crossfeed_active = cf_mode != CrossfeedPresetMode::Off;

        // Kill any existing instance
        let _ = Command::new("pkill").arg("-f").arg("ulteq_eq.conf").output();
        
        // If no filters are provided and crossfeed is disabled, EQ is bypassed/disabled. Just exit cleanly.
        if !is_crossfeed_active && left_filters.is_empty() && right_filters.is_empty() {
            return;
        }
        
        let config_path = "/tmp/ulteq_eq.conf";
        let is_stereo_split = !left_filters.is_empty() && !right_filters.is_empty();

        let config_content = if is_crossfeed_active {
            let (cf_fcut, cf_g_direct, cf_g_cross) = match cf_mode {
                CrossfeedPresetMode::Studio => (650.0, 0.75, 0.50),
                _ => (700.0, 0.85, 0.35),
            };

            let left_to_use = if !left_filters.is_empty() {
                &left_filters
            } else if !right_filters.is_empty() {
                &right_filters
            } else {
                &left_filters
            };

            let right_to_use = if !right_filters.is_empty() {
                &right_filters
            } else if !left_filters.is_empty() {
                &left_filters
            } else {
                &right_filters
            };

            let mut nodes = String::new();
            let mut links = String::new();

            let first_l;
            let last_l;
            if left_to_use.is_empty() {
                nodes.push_str(r#"
                        {
                            type = builtin
                            name = eq_l_pass
                            label = bq_peaking
                            control = { "Freq" = 1000.0 "Q" = 1.0 "Gain" = 0.0 }
                        }"#);
                first_l = "eq_l_pass:In".to_string();
                last_l = "eq_l_pass:Out".to_string();
            } else {
                for (i, filter) in left_to_use.iter().enumerate() {
                    let label = match filter.filter_type {
                        FilterType::Peaking => "bq_peaking",
                        FilterType::LowShelf => "bq_lowshelf",
                        FilterType::HighShelf => "bq_highshelf",
                    };
                    nodes.push_str(&format!(r#"
                        {{
                            type = builtin
                            name = eq_l_{}
                            label = {}
                            control = {{ "Freq" = {:.1} "Q" = {:.2} "Gain" = {:.1} }}
                        }}"#, i + 1, label, filter.freq, filter.q, filter.gain));
                    if i > 0 {
                        links.push_str(&format!(r#"
                        {{ output = "eq_l_{}:Out" input = "eq_l_{}:In" }}"#, i, i + 1));
                    }
                }
                first_l = "eq_l_1:In".to_string();
                last_l = format!("eq_l_{}:Out", left_to_use.len());
            }

            let first_r;
            let last_r;
            if right_to_use.is_empty() {
                nodes.push_str(r#"
                        {
                            type = builtin
                            name = eq_r_pass
                            label = bq_peaking
                            control = { "Freq" = 1000.0 "Q" = 1.0 "Gain" = 0.0 }
                        }"#);
                first_r = "eq_r_pass:In".to_string();
                last_r = "eq_r_pass:Out".to_string();
            } else {
                for (i, filter) in right_to_use.iter().enumerate() {
                    let label = match filter.filter_type {
                        FilterType::Peaking => "bq_peaking",
                        FilterType::LowShelf => "bq_lowshelf",
                        FilterType::HighShelf => "bq_highshelf",
                    };
                    nodes.push_str(&format!(r#"
                        {{
                            type = builtin
                            name = eq_r_{}
                            label = {}
                            control = {{ "Freq" = {:.1} "Q" = {:.2} "Gain" = {:.1} }}
                        }}"#, i + 1, label, filter.freq, filter.q, filter.gain));
                    if i > 0 {
                        links.push_str(&format!(r#"
                        {{ output = "eq_r_{}:Out" input = "eq_r_{}:In" }}"#, i, i + 1));
                    }
                }
                first_r = "eq_r_1:In".to_string();
                last_r = format!("eq_r_{}:Out", right_to_use.len());
            }

            // Crossfeed nodes and links
            nodes.push_str(&format!(r#"
                        {{
                            type = builtin
                            name = xfeed_lp_l
                            label = bq_lowpass
                            control = {{ "Freq" = {:.1} "Q" = 0.5 }}
                        }}
                        {{
                            type = builtin
                            name = xfeed_lp_r
                            label = bq_lowpass
                            control = {{ "Freq" = {:.1} "Q" = 0.5 }}
                        }}
                        {{
                            type = builtin
                            name = mix_l
                            label = mixer
                            control = {{ "Gain 1" = {:.2} "Gain 2" = {:.2} }}
                        }}
                        {{
                            type = builtin
                            name = mix_r
                            label = mixer
                            control = {{ "Gain 1" = {:.2} "Gain 2" = {:.2} }}
                        }}"#, cf_fcut, cf_fcut, cf_g_direct, cf_g_cross, cf_g_direct, cf_g_cross));

            links.push_str(&format!(r#"
                        {{ output = "{last_l}" input = "mix_l:In 1" }}
                        {{ output = "{last_l}" input = "xfeed_lp_l:In" }}
                        {{ output = "xfeed_lp_l:Out" input = "mix_r:In 2" }}

                        {{ output = "{last_r}" input = "mix_r:In 1" }}
                        {{ output = "{last_r}" input = "xfeed_lp_r:In" }}
                        {{ output = "xfeed_lp_r:Out" input = "mix_l:In 2" }}"#));

            format!(r#"
context.spa-libs = {{
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}}
context.modules = [
    {{ name = libpipewire-module-rt flags = [ ifexists nofail ] }}
    {{ name = libpipewire-module-protocol-native }}
    {{ name = libpipewire-module-client-node }}
    {{ name = libpipewire-module-adapter }}
    {{ name = libpipewire-module-filter-chain
        args = {{
            node.description = "UltEQ Effect (BS2B Crossfeed)"
            media.name       = "UltEQ Effect (BS2B Crossfeed)"
            filter.graph = {{
                nodes = [{nodes}
                ]
                links = [{links}
                ]
                inputs  = [ "{first_l}" "{first_r}" ]
                outputs = [ "mix_l:Out" "mix_r:Out" ]
            }}
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props = {{
                node.name = "effect_input.ulteq"
                media.class = Audio/Sink
            }}
            playback.props = {{
                node.name = "effect_output.ulteq"
                node.target = "{device_name}"
            }}
        }}
    }}
]
"#)
        } else if is_stereo_split {
            let mut nodes = String::new();
            let mut links = String::new();

            for (i, filter) in left_filters.iter().enumerate() {
                let label = match filter.filter_type {
                    FilterType::Peaking => "bq_peaking",
                    FilterType::LowShelf => "bq_lowshelf",
                    FilterType::HighShelf => "bq_highshelf",
                };
                nodes.push_str(&format!(r#"
                        {{
                            type = builtin
                            name = eq_l_{}
                            label = {}
                            control = {{ "Freq" = {:.1} "Q" = {:.2} "Gain" = {:.1} }}
                        }}"#, i + 1, label, filter.freq, filter.q, filter.gain));
                if i > 0 {
                    links.push_str(&format!(r#"
                        {{ output = "eq_l_{}:Out" input = "eq_l_{}:In" }}"#, i, i + 1));
                }
            }

            for (i, filter) in right_filters.iter().enumerate() {
                let label = match filter.filter_type {
                    FilterType::Peaking => "bq_peaking",
                    FilterType::LowShelf => "bq_lowshelf",
                    FilterType::HighShelf => "bq_highshelf",
                };
                nodes.push_str(&format!(r#"
                        {{
                            type = builtin
                            name = eq_r_{}
                            label = {}
                            control = {{ "Freq" = {:.1} "Q" = {:.2} "Gain" = {:.1} }}
                        }}"#, i + 1, label, filter.freq, filter.q, filter.gain));
                if i > 0 {
                    links.push_str(&format!(r#"
                        {{ output = "eq_r_{}:Out" input = "eq_r_{}:In" }}"#, i, i + 1));
                }
            }

            let l_last = left_filters.len();
            let r_last = right_filters.len();

            format!(r#"
context.spa-libs = {{
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}}
context.modules = [
    {{ name = libpipewire-module-rt flags = [ ifexists nofail ] }}
    {{ name = libpipewire-module-protocol-native }}
    {{ name = libpipewire-module-client-node }}
    {{ name = libpipewire-module-adapter }}
    {{ name = libpipewire-module-filter-chain
        args = {{
            node.description = "UltEQ Stereo Calibrated Effect"
            media.name       = "UltEQ Stereo Calibrated Effect"
            filter.graph = {{
                nodes = [{nodes}
                ]
                links = [{links}
                ]
                inputs  = [ "eq_l_1:In" "eq_r_1:In" ]
                outputs = [ "eq_l_{l_last}:Out" "eq_r_{r_last}:Out" ]
            }}
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props = {{
                node.name = "effect_input.ulteq"
                media.class = Audio/Sink
            }}
            playback.props = {{
                node.name = "effect_output.ulteq"
                node.target = "{device_name}"
            }}
        }}
    }}
]
"#)
        } else {
            let active = if !left_filters.is_empty() { &left_filters } else { &right_filters };
            let mut nodes = String::new();
            let mut links = String::new();
            for (i, filter) in active.iter().enumerate() {
                let label = match filter.filter_type {
                    FilterType::Peaking => "bq_peaking",
                    FilterType::LowShelf => "bq_lowshelf",
                    FilterType::HighShelf => "bq_highshelf",
                };
                nodes.push_str(&format!(r#"
                        {{
                            type = builtin
                            name = eq_band_{}
                            label = {}
                            control = {{ "Freq" = {:.1} "Q" = {:.2} "Gain" = {:.1} }}
                        }}"#, i + 1, label, filter.freq, filter.q, filter.gain));
                if i > 0 {
                    links.push_str(&format!(r#"
                        {{ output = "eq_band_{}:Out" input = "eq_band_{}:In" }}"#, i, i + 1));
                }
            }

            format!(r#"
context.spa-libs = {{
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}}
context.modules = [
    {{ name = libpipewire-module-rt flags = [ ifexists nofail ] }}
    {{ name = libpipewire-module-protocol-native }}
    {{ name = libpipewire-module-client-node }}
    {{ name = libpipewire-module-adapter }}
    {{ name = libpipewire-module-filter-chain
        args = {{
            node.description = "UltEQ Effect"
            media.name       = "UltEQ Effect"
            filter.graph = {{
                nodes = [{nodes}
                ]
                links = [{links}
                ]
            }}
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props = {{
                node.name = "effect_input.ulteq"
                media.class = Audio/Sink
            }}
            playback.props = {{
                node.name = "effect_output.ulteq"
                node.target = "{device_name}"
            }}
        }}
    }}
]
"#)
        };

        if let Ok(mut file) = File::create(config_path) {
            let _ = file.write_all(config_content.as_bytes());
        }

        if let Err(e) = Command::new("pipewire")
            .arg("-c")
            .arg(config_path)
            .spawn() {
            eprintln!("Failed to spawn PipeWire filter chain: {}", e);
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn apply_eq_to_device(device_name: String, filters: Vec<ActiveFilter>) {
    apply_stereo_eq_to_device(device_name, filters, Vec::new())
}

fn interpolate_points(points: &[Point], f: f32) -> f32 {
    if points.is_empty() { return 0.0; }
    if points.len() == 1 { return points[0].y; }
    if f <= points[0].x { return points[0].y; }
    if f >= points.last().unwrap().x { return points.last().unwrap().y; }
    
    let idx = points.partition_point(|p| p.x <= f);
    if idx == 0 { return points[0].y; }
    let p1 = &points[idx - 1];
    let p2 = &points[idx];
    
    let log_f = f.log10();
    let log_x1 = p1.x.log10();
    let log_x2 = p2.x.log10();
    
    if log_x1 == log_x2 { return p1.y; }
    
    let t = (log_f - log_x1) / (log_x2 - log_x1);
    p1.y + t * (p2.y - p1.y)
}

#[flutter_rust_bridge::frb(sync)]
pub fn generate_autoeq(headphone: Vec<Point>, target: Vec<Point>, bands: usize) -> Vec<ActiveFilter> {
    use crate::dsp::autoeq::{AutoEqConfig, AutoEqEngine, EarphoneMeasurement, TargetCurve};

    if headphone.is_empty() || target.is_empty() {
        return Vec::new();
    }

    let mut h_pts: Vec<(f64, f64)> = headphone
        .iter()
        .filter(|p| p.x > 0.0 && p.x.is_finite() && p.y.is_finite())
        .map(|p| (p.x as f64, p.y as f64))
        .collect();
    h_pts.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    h_pts.dedup_by(|a, b| (a.0 - b.0).abs() < 1e-5);

    let mut t_pts: Vec<(f64, f64)> = target
        .iter()
        .filter(|p| p.x > 0.0 && p.x.is_finite() && p.y.is_finite())
        .map(|p| (p.x as f64, p.y as f64))
        .collect();
    t_pts.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    t_pts.dedup_by(|a, b| (a.0 - b.0).abs() < 1e-5);

    if h_pts.len() < 2 || t_pts.len() < 2 {
        return Vec::new();
    }

    let (h_freqs, h_dbs): (Vec<f64>, Vec<f64>) = h_pts.into_iter().unzip();
    let (t_freqs, t_dbs): (Vec<f64>, Vec<f64>) = t_pts.into_iter().unzip();

    let meas = match EarphoneMeasurement::new("AutoEq", "Headphone", h_freqs, h_dbs) {
        Ok(m) => m,
        Err(_) => return Vec::new(),
    };

    let targ = match TargetCurve::new("Target", t_freqs, t_dbs) {
        Ok(t) => t,
        Err(_) => return Vec::new(),
    };

    let mut config = AutoEqConfig::default();
    config.max_peaking_filters = bands.clamp(1, 10);
    config.min_freq = 35.0; // Clean bass threshold to eliminate sub-bass ripples

    let engine = AutoEqEngine::new(config);
    match engine.optimize(&meas, &targ) {
        Ok(profile) => profile.to_active_filters(),
        Err(_) => Vec::new(),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn modify_target(base_target: Vec<Point>, tilt: f32, bass: f32, treble: f32, ear_gain: f32) -> Vec<Point> {
    let mut filters = Vec::new();
    
    if bass != 0.0 {
        filters.push(ActiveFilter {
            filter_type: FilterType::LowShelf,
            freq: 105.0,
            gain: bass,
            q: 0.71, // roughly standard Q for shelf
        });
    }
    
    if treble != 0.0 {
        filters.push(ActiveFilter {
            filter_type: FilterType::HighShelf,
            freq: 10000.0,
            gain: treble,
            q: 0.71,
        });
    }
    
    if ear_gain != 0.0 {
        filters.push(ActiveFilter {
            filter_type: FilterType::Peaking,
            freq: 3000.0, // standard ear gain region
            gain: ear_gain,
            q: 0.5, // wide q for ear gain
        });
    }
    
    let response = calculate_biquad_response(filters);
    
    let mut new_target = Vec::new();
    for p in base_target.iter() {
        let f = p.x;
        let mut y = p.y;
        
        // Tilt: applied relative to 1kHz
        if tilt != 0.0 {
            let octaves_from_1k = (f / 1000.0).log2();
            y += octaves_from_1k * tilt;
        }
        
        // Add digital biquad response
        y += interpolate_points(&response, f);
        
        new_target.push(Point { x: f, y });
    }
    
    new_target
}

// =========================================================================
// Universal EQ Export Formatters
// =========================================================================

#[flutter_rust_bridge::frb(sync)]
pub fn export_preset_equalizer_apo(
    left_filters: Vec<ActiveFilter>,
    right_filters: Vec<ActiveFilter>,
    preamp: f32,
) -> String {
    let mut out = String::new();
    out.push_str(&format!("Preamp: {:.1} dB\n", preamp));

    let is_stereo_split = !left_filters.is_empty() && !right_filters.is_empty();

    if is_stereo_split {
        out.push_str("Channel: L\n");
        for (i, filter) in left_filters.iter().enumerate() {
            let label = match filter.filter_type {
                FilterType::Peaking => "PK",
                FilterType::LowShelf => "LSC",
                FilterType::HighShelf => "HSC",
            };
            out.push_str(&format!(
                "Filter {}: ON {} Fc {:.1} Hz Gain {:.1} dB Q {:.2}\n",
                i + 1, label, filter.freq, filter.gain, filter.q
            ));
        }

        out.push_str("\nChannel: R\n");
        for (i, filter) in right_filters.iter().enumerate() {
            let label = match filter.filter_type {
                FilterType::Peaking => "PK",
                FilterType::LowShelf => "LSC",
                FilterType::HighShelf => "HSC",
            };
            out.push_str(&format!(
                "Filter {}: ON {} Fc {:.1} Hz Gain {:.1} dB Q {:.2}\n",
                i + 1, label, filter.freq, filter.gain, filter.q
            ));
        }
    } else {
        out.push_str("Channel: all\n");
        let active = if !left_filters.is_empty() {
            &left_filters
        } else {
            &right_filters
        };
        for (i, filter) in active.iter().enumerate() {
            let label = match filter.filter_type {
                FilterType::Peaking => "PK",
                FilterType::LowShelf => "LSC",
                FilterType::HighShelf => "HSC",
            };
            out.push_str(&format!(
                "Filter {}: ON {} Fc {:.1} Hz Gain {:.1} dB Q {:.2}\n",
                i + 1, label, filter.freq, filter.gain, filter.q
            ));
        }
    }

    out
}

#[flutter_rust_bridge::frb(sync)]
pub fn export_preset_qudelix(filters: Vec<ActiveFilter>, preamp: f32) -> String {
    let mut out = String::new();
    out.push_str(&format!("Preamp: {:.1} dB\n", preamp));

    for (i, filter) in filters.iter().take(10).enumerate() {
        let label = match filter.filter_type {
            FilterType::Peaking => "PK",
            FilterType::LowShelf => "LS",
            FilterType::HighShelf => "HS",
        };
        out.push_str(&format!(
            "Filter {}: ON {} Fc {:.0} Hz Gain {:.1} dB Q {:.3}\n",
            i + 1, label, filter.freq, filter.gain, filter.q
        ));
    }

    out
}

fn calculate_filter_gain_at_freq(filters: &[ActiveFilter], f: f32) -> f32 {
    use biquad::{Coefficients, ToHertz, Type};
    let fs = 48000.0;
    let mut total_db = 0.0;

    for filter in filters {
        let biquad_type = match filter.filter_type {
            FilterType::Peaking => Type::PeakingEQ(filter.gain),
            FilterType::LowShelf => Type::LowShelf(filter.gain),
            FilterType::HighShelf => Type::HighShelf(filter.gain),
        };

        let coeffs = match Coefficients::<f32>::from_params(biquad_type, fs.hz(), filter.freq.hz(), filter.q) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let omega = 2.0 * std::f32::consts::PI * f / fs;
        let cos_omega = omega.cos();
        let sin_omega = omega.sin();
        let cos_2omega = (2.0 * omega).cos();
        let sin_2omega = (2.0 * omega).sin();

        let num_real = coeffs.b0 + coeffs.b1 * cos_omega + coeffs.b2 * cos_2omega;
        let num_imag = -(coeffs.b1 * sin_omega + coeffs.b2 * sin_2omega);

        let den_real = 1.0 + coeffs.a1 * cos_omega + coeffs.a2 * cos_2omega;
        let den_imag = -(coeffs.a1 * sin_omega + coeffs.a2 * sin_2omega);

        let mag_sq = (num_real * num_real + num_imag * num_imag) / (den_real * den_real + den_imag * den_imag);
        if mag_sq > 0.0 {
            total_db += 10.0 * mag_sq.log10();
        }
    }

    total_db
}

#[flutter_rust_bridge::frb(sync)]
pub fn export_preset_wavelet(filters: Vec<ActiveFilter>) -> String {
    let n_points = 127;
    let min_f: f32 = 20.0;
    let max_f: f32 = 20000.0;

    let mut entries = Vec::with_capacity(n_points);

    for i in 0..n_points {
        let f = min_f * (max_f / min_f).powf(i as f32 / (n_points - 1) as f32);
        let gain = calculate_filter_gain_at_freq(&filters, f);
        let f_str = if f >= 100.0 {
            format!("{:.0}", f)
        } else {
            format!("{:.1}", f)
        };
        entries.push(format!("{} {:.1}", f_str, gain));
    }

    format!("GraphicEQ: {}", entries.join("; "))
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RoonBandExport {
    #[serde(rename = "type")]
    pub band_type: String,
    pub frequency: f32,
    pub gain_db: f32,
    pub q: f32,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RoonPresetExport {
    #[serde(rename = "type")]
    pub preset_type: String,
    pub name: String,
    pub preamp_db: f32,
    pub bands: Vec<RoonBandExport>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn export_preset_roon(filters: Vec<ActiveFilter>, preamp: f32) -> String {
    let bands = filters
        .iter()
        .map(|f| {
            let band_type = match f.filter_type {
                FilterType::Peaking => "Peak",
                FilterType::LowShelf => "LowShelf",
                FilterType::HighShelf => "HighShelf",
            };
            RoonBandExport {
                band_type: band_type.to_string(),
                frequency: (f.freq * 10.0).round() / 10.0,
                gain_db: (f.gain * 100.0).round() / 100.0,
                q: (f.q * 1000.0).round() / 1000.0,
            }
        })
        .collect();

    let preset = RoonPresetExport {
        preset_type: "parametric_equalizer".to_string(),
        name: "UltEQ Preset".to_string(),
        preamp_db: (preamp * 10.0).round() / 10.0,
        bands,
    };

    serde_json::to_string_pretty(&preset).unwrap_or_else(|_| "{}".to_string())
}

// =========================================================================
// User Presets System (SQLite)
// =========================================================================

#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct UserPresetModel {
    pub id: i64,
    pub name: String,
    pub created_at: String,
    pub filters: Vec<ActiveFilter>,
    pub preamp: f32,
    pub headphone_name: Option<String>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn save_user_preset(
    db_path: String,
    name: String,
    filters: Vec<ActiveFilter>,
    preamp: f32,
    headphone_name: Option<String>,
) -> Result<i64, String> {
    let resolved = resolve_db_path(&db_path);
    let conn = rusqlite::Connection::open(&resolved).map_err(|e| e.to_string())?;
    crate::database::setup_database(&conn).map_err(|e| e.to_string())?;

    let created_at: String = conn
        .query_row("SELECT datetime('now', 'localtime')", [], |r| r.get(0))
        .unwrap_or_else(|_| "1970-01-01 00:00:00".to_string());

    let filters_json = serde_json::to_string(&filters).map_err(|e| e.to_string())?;

    conn.execute(
        "INSERT INTO user_presets (name, created_at, filters_json, preamp, headphone_name) VALUES (?1, ?2, ?3, ?4, ?5)",
        rusqlite::params![&name, &created_at, &filters_json, preamp as f64, &headphone_name],
    ).map_err(|e| e.to_string())?;

    Ok(conn.last_insert_rowid())
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_user_presets(db_path: String) -> Vec<UserPresetModel> {
    let mut presets = Vec::new();
    let resolved = resolve_db_path(&db_path);
    if let Ok(conn) = rusqlite::Connection::open(&resolved) {
        let _ = crate::database::setup_database(&conn);
        if let Ok(mut stmt) = conn.prepare(
            "SELECT id, name, created_at, filters_json, preamp, headphone_name FROM user_presets ORDER BY id DESC"
        ) {
            let rows = stmt.query_map([], |row| {
                let id: i64 = row.get(0)?;
                let name: String = row.get(1)?;
                let created_at: String = row.get(2)?;
                let filters_json: String = row.get(3)?;
                let preamp: f64 = row.get(4)?;
                let headphone_name: Option<String> = row.get(5)?;
                Ok((id, name, created_at, filters_json, preamp, headphone_name))
            });

            if let Ok(iter) = rows {
                for item in iter.flatten() {
                    let filters: Vec<ActiveFilter> = serde_json::from_str(&item.3).unwrap_or_default();
                    presets.push(UserPresetModel {
                        id: item.0,
                        name: item.1,
                        created_at: item.2,
                        filters,
                        preamp: item.4 as f32,
                        headphone_name: item.5,
                    });
                }
            }
        }
    }
    presets
}

#[flutter_rust_bridge::frb(sync)]
pub fn delete_user_preset(db_path: String, id: i64) -> Result<(), String> {
    let resolved = resolve_db_path(&db_path);
    let conn = rusqlite::Connection::open(&resolved).map_err(|e| e.to_string())?;
    let _ = crate::database::setup_database(&conn);
    conn.execute("DELETE FROM user_presets WHERE id = ?1", rusqlite::params![id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

// =========================================================================
// Crossfeed Audiophile Module (Bauer BS2B)
// =========================================================================

pub use crate::dsp::crossfeed::CrossfeedCoefficients;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum CrossfeedPresetMode {
    Off,
    Default,
    Studio,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct CrossfeedConfig {
    pub enabled: bool,
    pub f_cut: f64,
    pub feed_db: f64,
    pub name: String,
}

static ACTIVE_CROSSFEED: std::sync::Mutex<CrossfeedPresetMode> = std::sync::Mutex::new(CrossfeedPresetMode::Off);

pub fn get_active_crossfeed_mode() -> CrossfeedPresetMode {
    ACTIVE_CROSSFEED.lock().map(|l| *l).unwrap_or(CrossfeedPresetMode::Off)
}

#[flutter_rust_bridge::frb(sync)]
pub fn apply_crossfeed_coefficients(sample_rate: f64, f_cut: f64, feed_db: f64) -> CrossfeedCoefficients {
    crate::dsp::crossfeed::calculate_crossfeed_coefficients(sample_rate, f_cut, feed_db)
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_crossfeed_preset(mode: CrossfeedPresetMode) -> CrossfeedConfig {
    if let Ok(mut lock) = ACTIVE_CROSSFEED.lock() {
        *lock = mode;
    }
    match mode {
        CrossfeedPresetMode::Default => CrossfeedConfig {
            enabled: true,
            f_cut: 700.0,
            feed_db: 4.5,
            name: "Default".to_string(),
        },
        CrossfeedPresetMode::Studio => CrossfeedConfig {
            enabled: true,
            f_cut: 650.0,
            feed_db: 9.5,
            name: "Studio".to_string(),
        },
        CrossfeedPresetMode::Off => CrossfeedConfig {
            enabled: false,
            f_cut: 0.0,
            feed_db: 0.0,
            name: "Off".to_string(),
        },
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_crossfeed_preset_by_name(mode_name: String) -> CrossfeedConfig {
    let mode = match mode_name.trim().to_lowercase().as_str() {
        "default" | "subtle" | "high" => CrossfeedPresetMode::Default,
        "studio" | "jmeier" | "low" => CrossfeedPresetMode::Studio,
        _ => CrossfeedPresetMode::Off,
    };
    get_crossfeed_preset(mode)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_export_equalizer_apo_single_and_stereo() {
        let filters = vec![
            ActiveFilter {
                filter_type: FilterType::Peaking,
                freq: 1000.0,
                gain: -2.5,
                q: 1.41,
            },
            ActiveFilter {
                filter_type: FilterType::LowShelf,
                freq: 105.0,
                gain: 4.0,
                q: 0.71,
            },
        ];

        let single_apo = export_preset_equalizer_apo(filters.clone(), Vec::new(), -4.0);
        assert!(single_apo.contains("Preamp: -4.0 dB"));
        assert!(single_apo.contains("Channel: all"));
        assert!(single_apo.contains("Filter 1: ON PK Fc 1000.0 Hz Gain -2.5 dB Q 1.41"));
        assert!(single_apo.contains("Filter 2: ON LSC Fc 105.0 Hz Gain 4.0 dB Q 0.71"));

        let stereo_apo = export_preset_equalizer_apo(filters.clone(), filters.clone(), -4.0);
        assert!(stereo_apo.contains("Channel: L"));
        assert!(stereo_apo.contains("Channel: R"));
    }

    #[test]
    fn test_export_qudelix_format() {
        let filters = vec![
            ActiveFilter {
                filter_type: FilterType::Peaking,
                freq: 32.0,
                gain: 2.0,
                q: 1.0,
            },
            ActiveFilter {
                filter_type: FilterType::Peaking,
                freq: 1000.0,
                gain: -1.5,
                q: 1.414,
            },
        ];

        let out = export_preset_qudelix(filters, -2.0);
        assert!(out.contains("Preamp: -2.0 dB"));
        assert!(out.contains("Filter 1: ON PK Fc 32 Hz Gain 2.0 dB Q 1.000"));
        assert!(out.contains("Filter 2: ON PK Fc 1000 Hz Gain -1.5 dB Q 1.414"));
    }

    #[test]
    fn test_export_wavelet_format() {
        let filters = vec![
            ActiveFilter {
                filter_type: FilterType::Peaking,
                freq: 1000.0,
                gain: 3.0,
                q: 1.0,
            }
        ];

        let out = export_preset_wavelet(filters);
        assert!(out.starts_with("GraphicEQ: "));
        let count = out.split(';').count();
        assert_eq!(count, 127);
    }

    #[test]
    fn test_export_roon_format() {
        let filters = vec![
            ActiveFilter {
                filter_type: FilterType::Peaking,
                freq: 1000.0,
                gain: -2.0,
                q: 1.41,
            }
        ];

        let json_str = export_preset_roon(filters, -2.0);
        assert!(json_str.contains("\"type\": \"parametric_equalizer\""));
        assert!(json_str.contains("\"preamp_db\": -2.0"));
        assert!(json_str.contains("\"type\": \"Peak\""));
    }

    #[test]
    fn test_user_presets_sqlite_crud() {
        // Use a temporary database
        let temp_dir = std::env::temp_dir();
        let db_path = temp_dir.join("test_ulteq_user_presets.db").to_str().unwrap().to_string();
        let _ = std::fs::remove_file(&db_path);

        let filters = vec![
            ActiveFilter {
                filter_type: FilterType::Peaking,
                freq: 2400.0,
                gain: -3.0,
                q: 2.0,
            }
        ];

        let preset_id = save_user_preset(
            db_path.clone(),
            "My Sennheiser Preset".to_string(),
            filters.clone(),
            -3.0,
            Some("HD600".to_string()),
        ).expect("Failed to save user preset");

        assert!(preset_id > 0);

        let presets = get_user_presets(db_path.clone());
        assert_eq!(presets.len(), 1);
        assert_eq!(presets[0].name, "My Sennheiser Preset");
        assert_eq!(presets[0].headphone_name, Some("HD600".to_string()));
        assert_eq!(presets[0].filters.len(), 1);
        assert_eq!(presets[0].filters[0].freq, 2400.0);
        assert_eq!(presets[0].preamp, -3.0);

        delete_user_preset(db_path.clone(), preset_id).expect("Failed to delete user preset");
        let presets_after = get_user_presets(db_path.clone());
        assert_eq!(presets_after.len(), 0);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn test_crossfeed_presets() {
        let def = get_crossfeed_preset(CrossfeedPresetMode::Default);
        assert!(def.enabled);
        assert_eq!(def.f_cut, 700.0);
        assert_eq!(def.feed_db, 4.5);

        let stu = get_crossfeed_preset(CrossfeedPresetMode::Studio);
        assert!(stu.enabled);
        assert_eq!(stu.f_cut, 650.0);
        assert_eq!(stu.feed_db, 9.5);

        let off = get_crossfeed_preset(CrossfeedPresetMode::Off);
        assert!(!off.enabled);
    }
}
