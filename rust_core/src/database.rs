use rusqlite::{Connection, Result};

pub fn setup_database(conn: &Connection) -> Result<()> {
    conn.execute(
        "CREATE TABLE IF NOT EXISTS measurements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            brand TEXT NOT NULL,
            model TEXT NOT NULL,
            form_factor TEXT,
            rig TEXT,
            file_path TEXT UNIQUE,
            spl_blob BLOB
        )",
        [],
    )?;
    
    // Try to add file_path if table existed from before (ignore error if it already exists)
    let _ = conn.execute("ALTER TABLE measurements ADD COLUMN file_path TEXT UNIQUE", []);
    
    Ok(())
}

pub fn insert_measurement(
    conn: &Connection,
    brand: &str,
    model: &str,
    form_factor: Option<&str>,
    rig: Option<&str>,
    file_path: Option<&str>,
    spl_blob: Option<&[u8]>,
) -> Result<()> {
    conn.execute(
        "INSERT OR IGNORE INTO measurements (brand, model, form_factor, rig, file_path, spl_blob)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        (brand, model, form_factor, rig, file_path, spl_blob),
    )?;
    Ok(())
}

