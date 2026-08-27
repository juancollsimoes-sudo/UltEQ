use crate::database;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
pub struct MeasurementPoint {
    pub frequency: f32,
    pub raw: f32,
    pub target: Option<f32>, // Some CSVs might not have target, but we'll parse if present
}

pub async fn fetch_autoeq_measurements(url: &str, db_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    println!("Fetching AutoEq measurements from {}", url);
    
    let response = reqwest::get(url).await?;
    let text = response.text().await?;
    
    let mut rdr = csv::ReaderBuilder::new()
        .flexible(true)
        .from_reader(text.as_bytes());
        
    // Read headers to find indices
    let headers = rdr.headers()?.clone();
    let freq_idx = headers.iter().position(|h| h == "frequency").ok_or("Missing frequency column")?;
    let raw_idx = headers.iter().position(|h| h == "raw").ok_or("Missing raw column")?;
    let target_idx = headers.iter().position(|h| h == "target");
    
    let mut points = Vec::new();
    
    for result in rdr.records() {
        let record = result?;
        
        let frequency = record.get(freq_idx)
            .unwrap_or("0.0")
            .parse::<f32>()
            .unwrap_or(0.0);
            
        let raw = record.get(raw_idx)
            .unwrap_or("0.0")
            .parse::<f32>()
            .unwrap_or(0.0);
            
        let target = if let Some(idx) = target_idx {
            record.get(idx).and_then(|v| v.parse::<f32>().ok())
        } else {
            None
        };
        
        points.push(MeasurementPoint { frequency, raw, target });
    }
    
    // Serialize to JSON blob
    let spl_blob = serde_json::to_vec(&points)?;
    
    // Connect to SQLite and insert
    let conn = Connection::open(db_path)?;
    database::setup_database(&conn)?;
    
    // Extract metadata from URL as a heuristic
    let file_name = url.split('/').last().unwrap_or("unknown.csv").replace("%20", " ");
    let model = file_name.trim_end_matches(".csv");
    
    database::insert_measurement(
        &conn,
        "AutoEq", // Default brand
        model,
        Some("unknown"), // form_factor
        Some("unknown"), // rig
        Some(&spl_blob),
    )?;
    
    println!("Successfully inserted {} points for model {}", points.len(), model);
    
    Ok(())
}
