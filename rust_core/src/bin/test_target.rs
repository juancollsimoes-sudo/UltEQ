#[tokio::main]
async fn main() {
    use rusqlite::Connection;
    if let Ok(conn) = Connection::open("../flutter_app/ulteq.db") {
        if let Ok(mut stmt) = conn.prepare("SELECT spl_blob FROM targets WHERE name = ?") {
            if let Ok(mut rows) = stmt.query(["Harman over-ear 2018"]) {
                if let Ok(Some(row)) = rows.next() {
                    let blob: Vec<u8> = row.get(0).unwrap();
                    println!("Blob length: {}", blob.len());
                    let res = serde_json::from_slice::<Vec<rust_core::fetcher::MeasurementPoint>>(&blob);
                    println!("Parsed: {:?}", res.is_ok());
                    if let Err(e) = res {
                        println!("Error: {}", e);
                    }
                }
            }
        }
    }
}
