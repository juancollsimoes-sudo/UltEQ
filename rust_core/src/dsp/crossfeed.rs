//! Bauer stereophonic-to-binaural (BS2B) crossfeed DSP module.
//!
//! Simulates loudspeaker acoustic crosstalk when listening via headphones,
//! reducing listening fatigue and narrowing unnatural stereo separation.

use std::f64::consts::PI;

/// BS2B crossfeed filter coefficients.
#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct CrossfeedCoefficients {
    pub a0_lo: f64,
    pub b1_lo: f64,
    pub a0_hi: f64,
    pub a1_hi: f64,
    pub b1_hi: f64,
    pub gain: f64,
    pub f_cut: f64,
    pub feed_db: f64,
    pub sample_rate: f64,
}

impl CrossfeedCoefficients {
    /// Returns coefficients for bypass (flat passthrough, no crossfeed effect).
    pub fn bypass(sample_rate: f64) -> Self {
        Self {
            a0_lo: 0.0,
            b1_lo: 0.0,
            a0_hi: 1.0,
            a1_hi: 0.0,
            b1_hi: 0.0,
            gain: 1.0,
            f_cut: 0.0,
            feed_db: 0.0,
            sample_rate: if sample_rate > 0.0 { sample_rate } else { 48000.0 },
        }
    }
}

/// Calculate Bauer BS2B crossfeed filter coefficients.
///
/// - `sample_rate`: Audio sampling frequency (e.g. 44100.0, 48000.0, 96000.0).
/// - `f_cut`: Low-pass filter cutoff frequency in Hz (e.g. 700.0 for Default, 650.0 for Studio).
/// - `feed_db`: Feeding level in dB (e.g. 4.5 for Default, 9.5 for Studio).
pub fn calculate_crossfeed_coefficients(sample_rate: f64, f_cut: f64, feed_db: f64) -> CrossfeedCoefficients {
    if sample_rate <= 0.0 || f_cut <= 0.0 || feed_db <= 0.0 {
        return CrossfeedCoefficients::bypass(sample_rate);
    }

    let level = feed_db;
    let gb_lo = level * -5.0 / 6.0 - 3.0;
    let gb_hi = level / 6.0 - 3.0;

    let g_lo = 10.0_f64.powf(gb_lo / 20.0);
    let g_hi = 1.0 - 10.0_f64.powf(gb_hi / 20.0);

    let g_hi_clamped = g_hi.max(1e-9);
    let fc_hi = f_cut * 2.0_f64.powf((gb_lo - 20.0 * g_hi_clamped.log10()) / 12.0);

    let x_lo = (-2.0 * PI * f_cut / sample_rate).exp();
    let b1_lo = x_lo;
    let a0_lo = g_lo * (1.0 - x_lo);

    let x_hi = (-2.0 * PI * fc_hi / sample_rate).exp();
    let b1_hi = x_hi;
    let a0_hi = 1.0 - g_hi * (1.0 - x_hi);
    let a1_hi = -x_hi;

    let gain = 1.0 / (1.0 - g_hi + g_lo);

    CrossfeedCoefficients {
        a0_lo,
        b1_lo,
        a0_hi,
        a1_hi,
        b1_hi,
        gain,
        f_cut,
        feed_db,
        sample_rate,
    }
}

/// State of a Bauer BS2B filter processor.
#[derive(Debug, Clone)]
pub struct Bs2bFilter {
    pub coeffs: CrossfeedCoefficients,
    asis: [f64; 2],
    lo: [f64; 2],
    hi: [f64; 2],
}

impl Bs2bFilter {
    pub fn new(coeffs: CrossfeedCoefficients) -> Self {
        Self {
            coeffs,
            asis: [0.0; 2],
            lo: [0.0; 2],
            hi: [0.0; 2],
        }
    }

    pub fn reset(&mut self) {
        self.asis = [0.0; 2];
        self.lo = [0.0; 2];
        self.hi = [0.0; 2];
    }

    /// Process a stereo sample pair (left, right) -> (out_left, out_right).
    pub fn process_sample(&mut self, left: f64, right: f64) -> (f64, f64) {
        if self.coeffs.f_cut <= 0.0 || self.coeffs.feed_db <= 0.0 {
            return (left, right);
        }

        let s = [left, right];

        // Lowpass filter
        self.lo[0] = self.coeffs.a0_lo * s[0] + self.coeffs.b1_lo * self.lo[0];
        self.lo[1] = self.coeffs.a0_lo * s[1] + self.coeffs.b1_lo * self.lo[1];

        // Highboost filter
        self.hi[0] = self.coeffs.a0_hi * s[0] + self.coeffs.a1_hi * self.asis[0] + self.coeffs.b1_hi * self.hi[0];
        self.hi[1] = self.coeffs.a0_hi * s[1] + self.coeffs.a1_hi * self.asis[1] + self.coeffs.b1_hi * self.hi[1];

        self.asis[0] = s[0];
        self.asis[1] = s[1];

        // Crossfeed mixing
        let out_l = (self.hi[0] + self.lo[1]) * self.coeffs.gain;
        let out_r = (self.hi[1] + self.lo[0]) * self.coeffs.gain;

        (out_l, out_r)
    }

    /// Process interleaved stereo samples [L, R, L, R, ...] in-place.
    pub fn process_interleaved(&mut self, samples: &mut [f64]) {
        for chunk in samples.chunks_exact_mut(2) {
            let (l, r) = self.process_sample(chunk[0], chunk[1]);
            chunk[0] = l;
            chunk[1] = r;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_crossfeed_coefficients_default() {
        let coeffs = calculate_crossfeed_coefficients(48000.0, 700.0, 4.5);
        assert!(coeffs.gain > 0.0 && coeffs.gain < 2.0);
        assert!(coeffs.b1_lo > 0.8 && coeffs.b1_lo < 1.0);
        assert!(coeffs.b1_hi > 0.7 && coeffs.b1_hi < 1.0);
        assert!(coeffs.a0_lo > 0.0);
        assert_eq!(coeffs.f_cut, 700.0);
        assert_eq!(coeffs.feed_db, 4.5);
    }

    #[test]
    fn test_crossfeed_coefficients_studio() {
        let coeffs = calculate_crossfeed_coefficients(44100.0, 650.0, 9.5);
        assert!(coeffs.gain > 0.0);
        assert!(coeffs.b1_lo > 0.8);
        assert_eq!(coeffs.f_cut, 650.0);
        assert_eq!(coeffs.feed_db, 9.5);
    }

    #[test]
    fn test_crossfeed_bypass() {
        let coeffs = calculate_crossfeed_coefficients(48000.0, 0.0, 0.0);
        let mut filter = Bs2bFilter::new(coeffs);
        let (out_l, out_r) = filter.process_sample(0.5, -0.25);
        assert_eq!(out_l, 0.5);
        assert_eq!(out_r, -0.25);
    }

    #[test]
    fn test_crossfeed_mono_preservation() {
        let coeffs = calculate_crossfeed_coefficients(48000.0, 700.0, 4.5);
        let mut filter = Bs2bFilter::new(coeffs);
        
        let mut last_l = 0.0;
        let mut last_r = 0.0;
        // Run steady DC mono signal to verify unit gain
        for _ in 0..500 {
            let (l, r) = filter.process_sample(1.0, 1.0);
            last_l = l;
            last_r = r;
        }

        assert!((last_l - 1.0).abs() < 1e-4, "Mono L should converge to 1.0, got {}", last_l);
        assert!((last_r - 1.0).abs() < 1e-4, "Mono R should converge to 1.0, got {}", last_r);
    }

    #[test]
    fn test_crossfeed_hard_panning_crosstalk() {
        let coeffs = calculate_crossfeed_coefficients(48000.0, 700.0, 4.5);
        let mut filter = Bs2bFilter::new(coeffs);
        
        let mut last_l = 0.0;
        let mut last_r = 0.0;
        // Hard-panned signal on Left channel
        for _ in 0..500 {
            let (l, r) = filter.process_sample(1.0, 0.0);
            last_l = l;
            last_r = r;
        }

        // Left channel should be reduced somewhat due to gain normalization,
        // and Right channel must have crosstalk > 0
        assert!(last_l > 0.5 && last_l < 1.0, "Panned L should be between 0.5 and 1.0, got {}", last_l);
        assert!(last_r > 0.2 && last_r < 0.6, "Crosstalk on R should be present, got {}", last_r);
    }
}
