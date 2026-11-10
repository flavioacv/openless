use serde_json::Value;

// Serialize FFI access to Swift's capture owner, including read-only health probes.
static MEDIA_OPERATION: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn openless_meeting_media(request: *const std::ffi::c_char) -> *mut std::ffi::c_char;
    fn openless_meeting_media_free(pointer: *mut std::ffi::c_char);
    fn openless_meeting_media_cancel();
}

pub fn cancel() {
    #[cfg(target_os = "macos")]
    unsafe { openless_meeting_media_cancel() };
}

pub async fn call(request: Value) -> Result<Value, String> {
    let _operation = MEDIA_OPERATION.lock().await;
    #[cfg(target_os = "macos")]
    {
        tokio::task::spawn_blocking(move || {
            let input = std::ffi::CString::new(request.to_string()).map_err(|_| "A solicitação de mídia é inválida")?;
            // Swift returns owned UTF-8 JSON; free it through its matching allocator.
            let pointer = unsafe { openless_meeting_media(input.as_ptr()) };
            if pointer.is_null() { return Err("Falha na operação nativa de mídia".into()); }
            let text = unsafe { std::ffi::CStr::from_ptr(pointer).to_string_lossy().into_owned() };
            unsafe { openless_meeting_media_free(pointer) };
            let response: Value = serde_json::from_str(&text).map_err(|_| "A resposta nativa de mídia é inválida")?;
            if let Some(error) = response.get("error").and_then(Value::as_str) { return Err(error.to_owned()); }
            Ok(response)
        }).await.map_err(|_| "A operação nativa de mídia foi interrompida".to_string())?
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = request;
        Err("Captura e importação de reuniões estão disponíveis no macOS nesta versão.".into())
    }
}
