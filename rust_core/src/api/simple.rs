#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

pub struct Point {
    pub x: f32,
    pub y: f32,
}

pub enum FilterType {
    Peaking,
    LowShelf,
    HighShelf,
}

pub struct ActiveFilter {
    pub filter_type: FilterType,
    pub freq: f32,
    pub gain: f32,
    pub q: f32,
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

#[flutter_rust_bridge::frb(sync)]
pub fn get_headphone_models(db_path: String) -> Vec<HeadphoneModel> {
    let mut models = Vec::new();
    
    if let Ok(conn) = rusqlite::Connection::open(&db_path) {
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
    
    if let Ok(conn) = rusqlite::Connection::open(&db_path) {
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
    crate::fetcher::initialize_autoeq_metadata(&db_path)
        .await
        .map_err(|e| e.to_string())
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_target_curve(db_path: String, target_name: String) -> Vec<Point> {
    use rusqlite::Connection;
    
    let mut points = Vec::new();
    if let Ok(conn) = Connection::open(&db_path) {
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
pub fn get_headphone_curve(file_path: String) -> Vec<Point> {
    let url = format!("https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/measurements/{}", file_path.replace(" ", "%20"));
    
    // We must block on the async fetch since this is a sync FFI function
    let handle = std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let mut points = Vec::new();
            if let Ok(client) = reqwest::Client::builder().user_agent("UltEQ").build() {
                if let Ok(response) = client.get(&url).send().await {
                    if let Ok(text) = response.text().await {
                        let mut rdr = csv::ReaderBuilder::new().flexible(true).from_reader(text.as_bytes());
                        if let Ok(headers) = rdr.headers() {
                            let freq_idx = headers.iter().position(|h| h == "frequency").unwrap_or(0);
                            let raw_idx = headers.iter().position(|h| h == "raw").unwrap_or(1);
                            
                            for result in rdr.records() {
                                if let Ok(record) = result {
                                    let frequency = record.get(freq_idx).unwrap_or("0.0").parse::<f32>().unwrap_or(0.0);
                                    let raw = record.get(raw_idx).unwrap_or("0.0").parse::<f32>().unwrap_or(0.0);
                                    points.push(Point { x: frequency, y: raw });
                                }
                            }
                        }
                    }
                }
            }
            points
        })
    });
    
    handle.join().unwrap_or_default()
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_audio_devices() -> Vec<String> {
    let mut devices = Vec::new();
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
    devices
}

#[flutter_rust_bridge::frb(sync)]
pub fn apply_eq_to_device(device_name: String, filters: Vec<ActiveFilter>) {
    use std::fs::File;
    use std::io::Write;
    use std::process::Command;

    // Kill any existing instance
    let _ = Command::new("pkill").arg("-f").arg("ulteq_eq.conf").output();
    
    let config_path = "/tmp/ulteq_eq.conf";
    
    let mut nodes = String::new();
    let mut links = String::new();
    
    for (i, filter) in filters.iter().enumerate() {
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
    
    let config_content = format!(r#"
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
                nodes = [{}
                ]
                links = [{}
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
                node.target = "{}"
            }}
        }}
    }}
]
"#, nodes, links, device_name);

    if let Ok(mut file) = File::create(config_path) {
        let _ = file.write_all(config_content.as_bytes());
    }
    
    // Launch as background process
    Command::new("pipewire")
        .arg("-c")
        .arg(config_path)
        .spawn()
        .unwrap_or_else(|e| {
            eprintln!("Failed to start PipeWire EQ: {}", e);
            // Return dummy child so it typechecks if we wanted to
            // For now, spawn returns Result<Child, Error>. We just log error.
            panic!("Failed to start PipeWire EQ: {}", e);
        });
}
