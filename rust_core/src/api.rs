#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn hello_from_rust() -> String {
    "Hello from Rust!".to_string()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
