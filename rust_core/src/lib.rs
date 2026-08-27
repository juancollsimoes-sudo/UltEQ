pub mod api;
mod frb_generated;

pub mod database;
pub mod fetcher;
pub mod dsp;
pub mod audio_backend;
pub mod autoeq;

pub fn add(left: u64, right: u64) -> u64 {
    left + right
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_works() {
        let result = add(2, 2);
        assert_eq!(result, 4);
    }
}
