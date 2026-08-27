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

/// Target modifiers: mathematical functions to apply adjustments to a target response curve.
pub struct TargetModifiers;

impl TargetModifiers {
    /// Applies a tilt (dB/Octave) around a center frequency.
    pub fn apply_tilt(frequencies: &[f32], target_curve: &mut [f32], tilt_db_per_oct: f32, center_freq: f32) {
        for (f, m) in frequencies.iter().zip(target_curve.iter_mut()) {
            if *f > 0.0 {
                let octaves = (*f / center_freq).log2();
                *m += tilt_db_per_oct * octaves;
            }
        }
    }

    /// Applies a bass shelf filter (analog RBJ EQ magnitude response).
    pub fn apply_bass_shelf(frequencies: &[f32], target_curve: &mut [f32], gain_db: f32, f_c: f32, q: f32) {
        let a = 10.0_f32.powf(gain_db / 40.0);
        let a2 = a * a;
        let a_sqrt_over_q_sq = (a.sqrt() / q).powi(2);

        for (f, m) in frequencies.iter().zip(target_curve.iter_mut()) {
            if *f > 0.0 {
                let w = *f / f_c;
                let w2 = w * w;
                let num = (a - w2).powi(2) + a_sqrt_over_q_sq * w2;
                let den = (1.0 - a * w2).powi(2) + a_sqrt_over_q_sq * w2;
                let mag_sq = a2 * (num / den);
                *m += 10.0 * mag_sq.log10();
            }
        }
    }

    /// Applies a treble adjustment (high shelf analog RBJ EQ magnitude response).
    pub fn apply_treble(frequencies: &[f32], target_curve: &mut [f32], gain_db: f32, f_c: f32, q: f32) {
        let a = 10.0_f32.powf(gain_db / 40.0);
        let a2 = a * a;
        let a_sqrt_over_q_sq = (a.sqrt() / q).powi(2);

        for (f, m) in frequencies.iter().zip(target_curve.iter_mut()) {
            if *f > 0.0 {
                let w = *f / f_c;
                let w2 = w * w;
                let num = (1.0 - a * w2).powi(2) + a_sqrt_over_q_sq * w2;
                let den = (a - w2).powi(2) + a_sqrt_over_q_sq * w2;
                let mag_sq = a2 * (num / den);
                *m += 10.0 * mag_sq.log10();
            }
        }
    }

    /// Applies an ear gain adjustment (peaking analog RBJ EQ magnitude response, e.g., 2k-5kHz).
    pub fn apply_ear_gain(frequencies: &[f32], target_curve: &mut [f32], gain_db: f32, f_c: f32, q: f32) {
        let a = 10.0_f32.powf(gain_db / 40.0);
        
        for (f, m) in frequencies.iter().zip(target_curve.iter_mut()) {
            if *f > 0.0 {
                let w = *f / f_c;
                let w2 = w * w;
                let num = (1.0 - w2).powi(2) + (w * a / q).powi(2);
                let den = (1.0 - w2).powi(2) + (w / (q * a)).powi(2);
                let mag_sq = num / den;
                *m += 10.0 * mag_sq.log10();
            }
        }
    }
}
