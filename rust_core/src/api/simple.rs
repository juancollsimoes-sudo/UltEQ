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

#[flutter_rust_bridge::frb(sync)]
pub fn calculate_biquad_response(freq: f32, gain: f32, q: f32) -> Vec<Point> {
    use biquad::{Coefficients, ToHertz, Type};
    
    let fs = 48000.0;
    
    let coeffs = match Coefficients::<f32>::from_params(Type::PeakingEQ(gain), fs.hz(), freq.hz(), q) {
        Ok(c) => c,
        Err(_) => return vec![],
    };
    
    let mut points = Vec::new();
    let min_f: f32 = 20.0;
    let max_f: f32 = 20000.0;
    let steps = 200;
    
    for i in 0..=steps {
        let f = min_f * (max_f / min_f).powf(i as f32 / steps as f32);
        
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
        
        points.push(Point { x: f, y: mag_db });
    }
    
    points
}
