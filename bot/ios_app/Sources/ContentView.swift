import SwiftUI
import ActivityKit

struct ContentView: View {
    @EnvironmentObject var bot: BotLoop
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("game")   private var game   = "dota_underlords"
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0a0a0f").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // ─── Header ───────────────────────────────────────
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Game Bot")
                                    .font(.title2.bold())
                                    .foregroundStyle(
                                        LinearGradient(colors: [.purple, .cyan],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                Text(bot.isRunning ? "Rulează" : "Oprit")
                                    .font(.caption)
                                    .foregroundColor(bot.isRunning ? .green : .gray)
                            }
                            Spacer()
                            Circle()
                                .fill(bot.isRunning ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 12, height: 12)
                                .shadow(color: bot.isRunning ? .green : .clear, radius: 4)
                        }
                        .padding()
                        .background(Color(hex: "12121a"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // ─── API Key ───────────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Anthropic API Key", systemImage: "key.fill")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            HStack {
                                Group {
                                    if showKey {
                                        TextField("sk-ant-api03-...", text: $apiKey)
                                    } else {
                                        SecureField("sk-ant-api03-...", text: $apiKey)
                                    }
                                }
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                Button { showKey.toggle() } label: {
                                    Image(systemName: showKey ? "eye.slash" : "eye")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(12)
                            .background(Color(hex: "0a0a0f"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "1e1e2e")))
                        }
                        .padding()
                        .background(Color(hex: "12121a"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // ─── Game Selector ────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Joc", systemImage: "gamecontroller.fill")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            Picker("Joc", selection: $game) {
                                Text("Dota Underlords").tag("dota_underlords")
                            }
                            .pickerStyle(.menu)
                            .tint(.purple)
                        }
                        .padding()
                        .background(Color(hex: "12121a"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // ─── Live Game Stats ──────────────────────────────
                        if bot.isRunning {
                            GameStatsCard(action: bot.lastAction)
                        }

                        // ─── Start / Stop ─────────────────────────────────
                        HStack(spacing: 12) {
                            Button {
                                Task { await bot.start(apiKey: apiKey, game: game) }
                            } label: {
                                Label("Pornește", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(colors: [.purple, .cyan],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(bot.isRunning || apiKey.isEmpty)
                            .opacity(bot.isRunning || apiKey.isEmpty ? 0.5 : 1)

                            Button {
                                bot.stop()
                            } label: {
                                Label("Oprește", systemImage: "stop.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(hex: "1e1e2e"))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red, lineWidth: 1))
                                    .foregroundColor(.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(!bot.isRunning)
                            .opacity(!bot.isRunning ? 0.4 : 1)
                        }

                        // ─── Permissions Status ───────────────────────────
                        PermissionsCard()

                        // ─── Log ──────────────────────────────────────────
                        LogCard(lines: bot.logLines)

                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: – Subviews

struct GameStatsCard: View {
    let action: BotAction?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Stare Joc", systemImage: "chart.bar.fill")
                .font(.caption.bold()).foregroundColor(.gray)
            if let a = action {
                HStack {
                    StatPill(label: "Gold",  value: a.gold.map { "\($0)" } ?? "—", color: .yellow)
                    StatPill(label: "HP",    value: a.hp.map   { "\($0)" } ?? "—", color: .green)
                    StatPill(label: "Round", value: a.round.map{ "\($0)" } ?? "—", color: .purple)
                }
                HStack(alignment: .top) {
                    Text(a.action.uppercased())
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                    Text(a.reason)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                ProgressView(value: a.confidence)
                    .tint(.purple)
            }
        }
        .padding()
        .background(Color(hex: "12121a"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StatPill: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(hex: "0a0a0f"))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PermissionsCard: View {
    @State private var hasScreenCapture = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permisiuni", systemImage: "checkmark.shield.fill")
                .font(.caption.bold()).foregroundColor(.gray)
            PermRow(label: "Screen Recording",
                    granted: hasScreenCapture,
                    action: { hasScreenCapture = true })
            PermRow(label: "Live Activities (Dynamic Island)",
                    granted: ActivityAuthorizationInfo().areActivitiesEnabled,
                    action: nil)
        }
        .padding()
        .background(Color(hex: "12121a"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct PermRow: View {
    let label: String
    let granted: Bool
    let action: (() -> Void)?
    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            Text(label).font(.caption).foregroundColor(.gray)
            Spacer()
            if !granted, let action {
                Button("Acordă") { action() }
                    .font(.caption.bold()).foregroundColor(.purple)
            }
        }
    }
}

struct LogCard: View {
    let lines: [LogLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Log", systemImage: "terminal.fill")
                .font(.caption.bold()).foregroundColor(.gray)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines.suffix(30)) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.time).font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                            Text(line.message).font(.system(size: 11, design: .monospaced))
                                .foregroundColor(line.level == "error" ? .red : line.level == "success" ? .green : Color(hex: "9ca3af"))
                                .lineLimit(2)
                        }
                    }
                }
            }
            .frame(maxHeight: 130)
        }
        .padding()
        .background(Color(hex: "12121a"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: – Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}
