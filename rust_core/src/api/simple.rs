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
                    devices.push(parts[1].to_string());
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

        // Kill any existing instance
        let _ = Command::new("pkill").arg("-f").arg("ulteq_eq.conf").output();
        
        let config_path = "/tmp/ulteq_eq.conf";
        let is_stereo_split = !left_filters.is_empty() && !right_filters.is_empty();

        let config_content = if is_stereo_split {
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
