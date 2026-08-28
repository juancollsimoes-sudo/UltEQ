#[tokio::main]
async fn main() {
    let _ = rust_core::fetcher::initialize_autoeq_metadata("../flutter_app/ulteq.db").await;
}
