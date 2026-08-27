use biquad::{Biquad, Coefficients, DirectForm1, ToHertz, Type};
fn main() {
    let fs = 48000.hz();
    let f0 = 1000.hz();
    let c = Coefficients::<f32>::from_params(Type::PeakingEQ(3.0), fs, f0, 0.707).unwrap();
    println!("{:?}", c);
}
