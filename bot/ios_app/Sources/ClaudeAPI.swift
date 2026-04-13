import Foundation
import UIKit

// MARK: – Model

struct BotAction: Codable {
    var action:      String = "wait"
    var target:      String = ""
    var reason:      String = ""
    var confidence:  Double = 0
    var displayText: String = ""   // text scurt pt Dynamic Island
    var gold:        Int?
    var hp:          Int?
    var round:       Int?
}

struct LogLine: Identifiable {
    let id   = UUID()
    let time: String
    let level: String     // info | error | success
    let message: String
}

// MARK: – Claude API

class ClaudeAPI {
    var apiKey: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model    = "claude-opus-4-6"

    init(apiKey: String) { self.apiKey = apiKey }

    /// Analizeaza un JPEG frame si returneaza actiunea recomandata.
    func analyze(jpeg: Data, game: String, knowledge: String) async throws -> BotAction {
        let b64 = jpeg.base64EncodedString()

        let system = """
        Esti un expert la \(game). Primesti un screenshot si cunostinte acumulate.
        Raspunde EXCLUSIV cu un JSON pe o singura linie, fara text extra:
        {"action":"buy|sell|reroll|level_up|place|wait","target":"ce anume","reason":"de ce scurt","confidence":0.85,"displayText":"SCURT max 30 chars","gold":8,"hp":74,"round":12}
        """

        let userText = knowledge.isEmpty
            ? "Analizeaza screenshot-ul si da recomandarea."
            : "Cunostinte:\n\(knowledge.prefix(2000))\n\nAnalizeaza si da recomandarea."

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            "system": system,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": b64
                        ]
                    ],
                    ["type": "text", "text": userText]
                ]
            ]]
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod  = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw APIError.httpError(msg)
        }

        // Extrage JSON din raspuns
        let raw = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = raw.content.first?.text ?? "{}"

        // Gaseste primul { ... } din text
        if let jsonData = extractJSON(from: text) {
            if let action = try? JSONDecoder().decode(BotAction.self, from: jsonData) {
                return action
            }
        }
        return BotAction(action: "wait", reason: "Nu s-a putut parsa raspunsul")
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private func extractJSON(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}") else { return nil }
        return Data(text[start...end].utf8)
    }

    enum APIError: Error, LocalizedError {
        case httpError(String)
        var errorDescription: String? {
            if case .httpError(let msg) = self { return "Claude API error: \(msg)" }
            return nil
        }
    }
}

// MARK: – Anthropic response shape

private struct AnthropicResponse: Codable {
    let content: [ContentBlock]
    struct ContentBlock: Codable {
        let text: String
    }
}
