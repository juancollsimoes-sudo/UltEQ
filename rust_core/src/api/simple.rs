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
