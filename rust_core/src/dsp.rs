use biquad::{Biquad, Coefficients, DirectForm1, ToHertz, Type};

pub struct DspFilter {
    filter: DirectForm1<f32>,
}

impl DspFilter {
    pub fn new_peaking(fs: f32, f0: f32, q: f32, db_gain: f32) -> Result<Self, biquad::Errors> {
        let fs = fs.hz();
        let f0 = f0.hz();
        let coeffs = Coefficients::<f32>::from_params(Type::PeakingEQ(db_gain), fs, f0, q)?;
        Ok(Self {
            filter: DirectForm1::<f32>::new(coeffs),
        })
    }

    pub fn new_low_shelf(fs: f32, f0: f32, q: f32, db_gain: f32) -> Result<Self, biquad::Errors> {
        let fs = fs.hz();
        let f0 = f0.hz();
        let coeffs = Coefficients::<f32>::from_params(Type::LowShelf(db_gain), fs, f0, q)?;
        Ok(Self {
            filter: DirectForm1::<f32>::new(coeffs),
        })
    }

    pub fn new_high_shelf(fs: f32, f0: f32, q: f32, db_gain: f32) -> Result<Self, biquad::Errors> {
        let fs = fs.hz();
        let f0 = f0.hz();
        let coeffs = Coefficients::<f32>::from_params(Type::HighShelf(db_gain), fs, f0, q)?;
        Ok(Self {
            filter: DirectForm1::<f32>::new(coeffs),
        })
    }

    pub fn process(&mut self, sample: f32) -> f32 {
        self.filter.run(sample)
    }
}

/// Calculate the error of the curve E(f) = M(f) - T(f)
/// M(f) = Measured magnitude (e.g. in dB)
/// T(f) = Target magnitude (e.g. in dB)
pub fn calculate_error(measured: f32, target: f32) -> f32 {
    measured - target
}

pub fn calculate_error_curve(measured: &[f32], target: &[f32]) -> Vec<f32> {
    measured.iter().zip(target.iter())
        .map(|(m, t)| calculate_error(*m, *t))
        .collect()
}
