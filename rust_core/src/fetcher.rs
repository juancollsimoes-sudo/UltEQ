use crate::database;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
pub struct MeasurementPoint {
    pub frequency: f32,
    pub raw: f32,
    pub target: Option<f32>,
}

#[derive(Deserialize)]
struct GithubTreeResponse {
    tree: Vec<GithubTreeItem>,
}

#[derive(Deserialize)]
struct GithubTreeItem {
    path: String,
    #[serde(rename = "type")]
    item_type: String,
    sha: String,
}

pub async fn initialize_autoeq_metadata(db_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    println!("Initializing AutoEq metadata dynamically from GitHub...");
    let client = reqwest::Client::builder()
        .user_agent("UltEQ")
        .build()?;

    // 1. Get master tree
    let master_tree_url = "https://api.github.com/repos/jaakkopasanen/AutoEq/git/trees/master";
    let master_resp: GithubTreeResponse = client.get(master_tree_url).send().await?.json().await?;

    // 2. Find "measurements" sha
    let measurements_sha = master_resp.tree.iter()
        .find(|item| item.path == "measurements")
        .ok_or("Could not find 'measurements' directory in AutoEq master")?
        .sha.clone();

    // 3. Fetch measurements tree recursively
    let measurements_tree_url = format!("https://api.github.com/repos/jaakkopasanen/AutoEq/git/trees/{}?recursive=1", measurements_sha);
    let measurements_resp: GithubTreeResponse = client.get(&measurements_tree_url).send().await?.json().await?;

    let conn = Connection::open(db_path)?;
    database::setup_database(&conn)?;

    let mut count = 0;
    for item in measurements_resp.tree {
        if item.item_type == "blob" && item.path.ends_with(".csv") {
            let parts: Vec<&str> = item.path.split('/').collect();
            // Expected format: <db>/data/<form_factor>/[rig/]<model>.csv
            if parts.len() >= 4 && parts[1] == "data" {
                let brand = parts[0];
                let form_factor = parts[2];
                let (rig, file_name) = if parts.len() == 5 {
                    (Some(parts[3]), parts[4])
                } else {
                    (None, parts[3])
                };
                let model = file_name.trim_end_matches(".csv");
                
                database::insert_measurement(
                    &conn,
                    brand,
                    model,
                    Some(form_factor),
                    rig,
                    Some(&item.path),
                    None,
                )?;
                count += 1;
            }
        }
    }

    println!("Successfully indexed {} AutoEq models into SQLite", count);
    Ok(())
}

pub async fn fetch_autoeq_measurements(url: &str, db_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    println!("Fetching AutoEq measurements from {}", url);
    
    let response = reqwest::get(url).await?;
    let text = response.text().await?;
    
    let mut rdr = csv::ReaderBuilder::new()
        .flexible(true)
        .from_reader(text.as_bytes());
        
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
    
    let spl_blob = serde_json::to_vec(&points)?;
    let conn = Connection::open(db_path)?;
    database::setup_database(&conn)?;
    
    let file_name = url.split('/').last().unwrap_or("unknown.csv").replace("%20", " ");
    let model = file_name.trim_end_matches(".csv");
    
    database::insert_measurement(
        &conn,
        "AutoEq", 
        model,
        Some("unknown"), 
        Some("unknown"), 
        None,
        Some(&spl_blob),
    )?;
    
    println!("Successfully inserted {} points for model {}", points.len(), model);
    
    Ok(())
}
