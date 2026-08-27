use super::{Filter, FilterType};

pub fn generate_pw_config(preamp: f32, filters: &[Filter]) -> String {
    let mut config = String::new();
    
    config.push_str("filter.graph = {\n");
    config.push_str("    nodes = [\n");
    
    // Add a preamp node
    config.push_str("        {\n");
    config.push_str("            type = builtin\n");
    config.push_str("            name = eq_preamp\n");
    config.push_str("            label = bq_highshelf\n"); // Using highshelf at 0 Hz as a volume control, or we could use copy node with volume, but bq is often used.
    config.push_str(&format!(
        "            control = {{ \"Freq\" = 0.0 \"Gain\" = {:.1} \"Q\" = 1.0 }}\n",
        preamp
    ));
    config.push_str("        }\n");

    for (i, filter) in filters.iter().enumerate() {
        let label = match filter.filter_type {
            FilterType::Peaking => "bq_peaking",
            FilterType::LowShelf => "bq_lowshelf",
            FilterType::HighShelf => "bq_highshelf",
        };
        
        config.push_str("        {\n");
        config.push_str("            type = builtin\n");
        config.push_str(&format!("            name = eq_band_{}\n", i + 1));
        config.push_str(&format!("            label = {}\n", label));
        config.push_str(&format!(
            "            control = {{ \"Freq\" = {:.1} \"Gain\" = {:.1} \"Q\" = {:.2} }}\n",
            filter.fc, filter.gain, filter.q
        ));
        config.push_str("        }\n");
    }
    
    config.push_str("    ]\n");
    config.push_str("}\n");
    
    config
}
