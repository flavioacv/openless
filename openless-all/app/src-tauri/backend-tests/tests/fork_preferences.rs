use openless_core::UserPreferences;

#[test]
fn existing_resource_and_agent_preferences_survive_the_new_settings_wire_format() {
    let stored = serde_json::json!({
        "lowMemoryBackgroundEnabled": true,
        "lowLatencyDictationEnabled": true,
        "testingFeaturesEnabled": true,
        "codingAgentEnabled": true,
    });
    let preferences: UserPreferences = serde_json::from_value(stored).unwrap();
    let round_trip = serde_json::to_value(preferences).unwrap();
    for field in [
        "lowMemoryBackgroundEnabled",
        "lowLatencyDictationEnabled",
        "testingFeaturesEnabled",
        "codingAgentEnabled",
    ] {
        assert_eq!(round_trip[field], true, "lost existing setting {field}");
    }
    let old: UserPreferences = serde_json::from_str("{}").unwrap();
    assert!(!old.low_memory_background_enabled);
}
