// Compile the production permission resolver and its regression tests without Tauri.
// No test requests permissions or starts audio capture.
#[cfg(target_os = "macos")]
#[allow(dead_code, unused_imports)]
#[path = "../../src/permissions.rs"]
mod permissions;
