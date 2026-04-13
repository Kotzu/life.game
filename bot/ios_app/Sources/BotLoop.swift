import SwiftUI
import ActivityKit
import Combine

/// Orchestreaza: captura -> Claude -> Dynamic Island -> (optional) touch
@MainActor
class BotLoop: ObservableObject {
    @Published var isRunning    = false
    @Published var lastAction:    BotAction?
    @Published var logLines:     [LogLine]  = []

    private let capture = ScreenCapture.shared
    private var claude:   ClaudeAPI?
    private var activity: Activity<BotActivityAttributes>?
    private var task:     Task<Void, Never>?
    private var knowledge = ""          // din KnowledgeBase JSON local
    private var game      = "dota_underlords"

    // ── Public API ──────────────────────────────────────────────────────────

    func start(apiKey: String, game: String) async {
        guard !isRunning else { return }
        self.game  = game
        self.claude = ClaudeAPI(apiKey: apiKey)

        // Incarca knowledge base local (din Documents)
        knowledge = loadKnowledge(game: game)

        // Cere permisiune screen capture
        do {
            try await capture.start(fps: 2)
        } catch {
            log("Screen capture eroare: \(error.localizedDescription)", level: "error")
            return
        }

        // Porneste Live Activity (Dynamic Island)
        startLiveActivity()
        isRunning = true
        log("Bot pornit pentru \(game)", level: "success")

        // Loop principal: primeste frames din ScreenCapture
        task = Task { [weak self] in
            guard let self else { return }
            for await jpeg in self.frameStream() {
                guard !Task.isCancelled else { break }
                await self.processFrame(jpeg)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        capture.stop()
        endLiveActivity()
        isRunning = false
        log("Bot oprit", level: "info")
    }

    // ── Frame processing ─────────────────────────────────────────────────────

    private func processFrame(_ jpeg: Data) async {
        guard let claude else { return }
        do {
            let action = try await claude.analyze(jpeg: jpeg, game: game, knowledge: knowledge)
            lastAction = action

            // Actualizeaza Dynamic Island
            await updateLiveActivity(action: action)

            log("[\(action.action.uppercased())] \(action.displayText) (\(Int(action.confidence * 100))%)")

            // Salveaza experienta in KB
            saveExperience(action: action)

        } catch {
            log("Eroare analiza: \(error.localizedDescription)", level: "error")
        }
    }

    // ── AsyncStream din callback-ul ScreenCapture ────────────────────────────

    private func frameStream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            ScreenCapture.shared.onFrame = { jpeg in
                continuation.yield(jpeg)
            }
            continuation.onTermination = { _ in
                ScreenCapture.shared.onFrame = nil
            }
        }
    }

    // ── Live Activity / Dynamic Island ───────────────────────────────────────

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("Live Activities dezactivate in Settings", level: "error")
            return
        }
        let attrs = BotActivityAttributes(game: game)
        let state = BotActivityAttributes.Status(
            action: "wait",
            displayText: "Bot pornit...",
            gold: nil, hp: nil,
            confidence: 0,
            isAnalyzing: true
        )
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            log("Dynamic Island activ", level: "success")
        } catch {
            log("Live Activity eroare: \(error.localizedDescription)", level: "error")
        }
    }

    private func updateLiveActivity(action: BotAction) async {
        let state = BotActivityAttributes.Status(
            action:      action.action,
            displayText: action.displayText.isEmpty ? action.reason : action.displayText,
            gold:        action.gold,
            hp:          action.hp,
            confidence:  action.confidence,
            isAnalyzing: false
        )
        await activity?.update(.init(state: state, staleDate: nil))
    }

    private func endLiveActivity() {
        Task {
            let state = BotActivityAttributes.Status(
                action: "stop", displayText: "Bot oprit",
                gold: nil, hp: nil, confidence: 0, isAnalyzing: false
            )
            await activity?.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
            activity = nil
        }
    }

    // ── Knowledge Base (JSON local in Documents) ─────────────────────────────

    private func loadKnowledge(game: String) -> String {
        let path = knowledgePath()
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        var parts: [String] = []
        if let yt = (json["youtube_knowledge"] as? [String: [[String: Any]]])?[game] {
            for item in yt.prefix(3) {
                if let text = item["text"] as? String { parts.append(text.prefix(800).description) }
            }
        }
        if let st = (json["strategies"] as? [String: [[String: Any]]])?[game] {
            for item in st.prefix(5) {
                if let text = item["text"] as? String { parts.append("• \(text)") }
            }
        }
        let result = parts.joined(separator: "\n\n")
        if !result.isEmpty { log("KB incarcat: \(result.count) chars") }
        return result
    }

    private func saveExperience(action: BotAction) {
        // Adauga experienta in JSON local (pentru Juno sau bot PC sa le citeasca)
        guard action.confidence > 0.7 else { return }
        let path = experiencesPath()
        var exps = (try? JSONDecoder().decode([StoredExperience].self,
                                              from: (try? Data(contentsOf: path)) ?? Data())) ?? []
        exps.append(StoredExperience(
            action: action.action,
            reason: action.reason,
            confidence: action.confidence,
            timestamp: Date().timeIntervalSince1970
        ))
        if exps.count > 200 { exps = Array(exps.suffix(200)) }
        if let encoded = try? JSONEncoder().encode(exps) {
            try? encoded.write(to: path)
        }
    }

    private func knowledgePath() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("knowledge_base.json")
    }
    private func experiencesPath() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("experiences.json")
    }

    // ── Logging ───────────────────────────────────────────────────────────────

    func log(_ msg: String, level: String = "info") {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        let line = LogLine(time: fmt.string(from: Date()), level: level, message: msg)
        logLines.append(line)
        if logLines.count > 200 { logLines.removeFirst() }
    }
}

// MARK: – Stored types

private struct StoredExperience: Codable {
    let action:     String
    let reason:     String
    let confidence: Double
    let timestamp:  Double
}
