use rusqlite::{Connection, Result};

pub fn setup_database(conn: &Connection) -> Result<()> {
    conn.execute(
        "CREATE TABLE IF NOT EXISTS measurements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            brand TEXT NOT NULL,
            model TEXT NOT NULL,
            form_factor TEXT,
            rig TEXT,
            spl_blob BLOB
        )",
        [],
    )?;
    Ok(())
}

pub fn insert_measurement(
    conn: &Connection,
    brand: &str,
    model: &str,
    form_factor: Option<&str>,
    rig: Option<&str>,
    spl_blob: Option<&[u8]>,
) -> Result<()> {
    conn.execute(
        "INSERT INTO measurements (brand, model, form_factor, rig, spl_blob)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        (brand, model, form_factor, rig, spl_blob),
    )?;
    Ok(())
}
