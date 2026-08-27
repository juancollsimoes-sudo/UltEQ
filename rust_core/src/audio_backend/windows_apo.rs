use super::{Filter, FilterType};

pub fn write_apo_config(preamp: f32, filters: &[Filter]) -> String {
    let mut config = format!("Preamp: {:.1} dB\n", preamp);
    
    for (i, filter) in filters.iter().enumerate() {
        let type_str = match filter.filter_type {
            FilterType::Peaking => "PK",
            FilterType::LowShelf => "LS",
            FilterType::HighShelf => "HS",
        };
        
        config.push_str(&format!(
            "Filter {}: ON {} Fc {:.1} Hz Gain {:.1} Q {:.2}\n",
            i + 1, type_str, filter.fc, filter.gain, filter.q
        ));
    }
    
    config
}
