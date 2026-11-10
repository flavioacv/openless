use std::collections::HashSet;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::time::Duration;

use openless_core::llm_gemini::{GeminiConfig, GeminiProvider};
use openless_core::meetings::processing::{admit_summary, SUMMARY_INSTRUCTIONS};
use serde_json::{json, Value};
use uuid::Uuid;

#[tokio::test]
#[ignore = "requires permission to open a loopback socket; run explicitly with --ignored"]
async fn gemini_meeting_summary_uses_native_auth_prompt_and_structured_json() {
    // A local HTTP fixture exercises the actual provider, without cloud credentials.
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let segment = Uuid::new_v4();
    let response = json!({"text":"Revisar proposta", "decisions":[], "tasks":[{
        "description":"Revisar proposta", "owner":null,"deadline":null,"sourceSegmentIds":[segment]
    }]}).to_string();
    let expected = response.clone();
    let server = std::thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap();
        socket.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
        let mut bytes = Vec::new();
        let mut buffer = [0u8; 4096];
        let headers_end = loop {
            let count = socket.read(&mut buffer).unwrap();
            assert!(count > 0);
            bytes.extend_from_slice(&buffer[..count]);
            if let Some(position) = bytes.windows(4).position(|value| value == b"\r\n\r\n") {
                break position + 4;
            }
        };
        let headers = String::from_utf8(bytes[..headers_end].to_vec()).unwrap().to_lowercase();
        let length: usize = headers.lines().find_map(|line| line.strip_prefix("content-length:")
            .map(|value| value.trim().parse().unwrap())).unwrap();
        while bytes.len() < headers_end + length {
            let count = socket.read(&mut buffer).unwrap();
            assert!(count > 0);
            bytes.extend_from_slice(&buffer[..count]);
        }
        assert!(headers.starts_with("post /v1beta/models/gemini-test:generatecontent "));
        assert!(headers.contains("x-goog-api-key: fixture-key"));
        assert!(!headers.contains("authorization: bearer"));
        let body: Value = serde_json::from_slice(&bytes[headers_end..headers_end + length]).unwrap();
        assert_eq!(body["systemInstruction"]["parts"][0]["text"], SUMMARY_INSTRUCTIONS);
        assert_eq!(body["contents"][0]["parts"][0]["text"], "Trecho da reunião");
        assert_eq!(body["generationConfig"]["responseMimeType"], "application/json");
        assert!(body.get("messages").is_none());
        let body = json!({"candidates":[{"content":{"parts":[{"text":response}]}}]}).to_string();
        write!(socket, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
    });
    let mut config = GeminiConfig::new("fixture-key", "gemini-test", format!("http://{address}/v1beta"));
    config.request_timeout_secs = 10;
    let provider = GeminiProvider::new(config);
    let result = provider.summarize_meeting(SUMMARY_INSTRUCTIONS, "Trecho da reunião").await.unwrap();
    server.join().unwrap();
    assert_eq!(result, expected);
    let summary = admit_summary(&result, &HashSet::from([segment])).unwrap();
    assert_eq!(summary.tasks[0].owner, None);
    assert_eq!(summary.tasks[0].deadline, None);
}
