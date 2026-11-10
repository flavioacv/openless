import AVFoundation
import Foundation
import OpenLessMeetings

// Drives the actual FFI product without microphone/screen permissions or paid API keys.
@main
struct MeetingMediaProbe {
    static func invoke(_ request: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: request)
        let input = String(decoding: data, as: UTF8.self)
        let result = await Task.detached {
            input.withCString { pointer -> String in
                guard let response = openlessMeetingMedia(pointer) else { return "{\"error\":\"no result\"}" }
                defer { openlessMeetingMediaFree(response) }
                return String(cString: response)
            }
        }.value
        guard let object = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any] else {
            throw NSError(domain: "MeetingProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid native JSON"])
        }
        return object
    }

    static func printJSON(_ value: [String: Any]) throws {
        print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self))
    }

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            if arguments.count == 3, arguments[0] == "--download" {
                let model = arguments[1], root = arguments[2]
                let started = try await invoke(["command": "downloadModel", "id": model, "modelDirectory": root])
                if started["error"] is String { try printJSON(started); exit(1) }
                while true {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let status = try await invoke(["command": "modelsStatus", "modelDirectory": root])
                    try printJSON(status)
                    if !(status["downloading"] is String) { exit(status["error"] is String ? 1 : 0) }
                }
            }
            if arguments.count == 3, arguments[0] == "--transcribe" {
                let result = try await invoke(["command": "transcribeLocal", "path": arguments[1], "modelDirectory": arguments[2]])
                try printJSON(result); exit(result["error"] != nil ? 1 : 0)
            }
            guard arguments.count == 2 else {
                fputs("Usage: MeetingMediaProbe input-media output-directory | --download model model-directory | --transcribe audio model-directory\n", stderr)
                exit(2)
            }
            try FileManager.default.createDirectory(atPath: arguments[1], withIntermediateDirectories: true)
            let result = try await invoke(["command": "import", "path": arguments[0], "directory": arguments[1]])
            try printJSON(result)
            if result["error"] != nil { exit(1) }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
