fn main() {
    use rusqlite::Connection;
    let conn = Connection::open("../flutter_app/ulteq.db").unwrap();
    
    // File path for Beyerdynamic DT 770 Pro (80 Ohm)
    let file_path: String = conn.query_row(
        "SELECT file_path FROM measurements WHERE model LIKE '%DT 770 Pro (80 Ohm)%' LIMIT 1",
        [],
        |r| r.get(0),
    ).unwrap();
    println!("Fetching: {}", file_path);
    let hp_vec = rust_core::api::simple::get_headphone_curve(file_path);
    println!("Headphone points: {}", hp_vec.len());

    // Load Harman in-ear 2019 (or over-ear 2018)
    let h_vec = rust_core::api::simple::get_target_curve("../flutter_app/ulteq.db".to_string(), "Harman in-ear 2019".to_string());
    println!("Harman points: {}", h_vec.len());

    // Load AutoEq in-ear
    let a_vec = rust_core::api::simple::get_target_curve("../flutter_app/ulteq.db".to_string(), "AutoEq in-ear".to_string());
    println!("AutoEq points: {}", a_vec.len());

    println!("\n=== HARMAN FILTERS ===");
    let filters_h = rust_core::api::simple::generate_autoeq(hp_vec.clone(), h_vec, 10);
    for f in &filters_h {
        println!("{:?} {:.1} Hz Gain {:.1} dB Q {:.2}", f.filter_type, f.freq, f.gain, f.q);
    }

    println!("\n=== AUTOEQ IN-EAR FILTERS ===");
    let filters_a = rust_core::api::simple::generate_autoeq(hp_vec, a_vec, 10);
    for f in &filters_a {
        println!("{:?} {:.1} Hz Gain {:.1} dB Q {:.2}", f.filter_type, f.freq, f.gain, f.q);
    }
}
