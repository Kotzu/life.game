/// Widget Extension target – afiseaza Live Activity in Dynamic Island si Lock Screen.
/// Adauga acest fisier in targetul "BotBridgeWidget" din Xcode.

import ActivityKit
import SwiftUI
import WidgetKit

// ── Shared model (copy din Sources/BotActivity.swift) ──────────────────────
// (In Xcode: adauga BotActivity.swift la ambele targete in loc de duplicate)

struct BotLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BotActivityAttributes.self) { context in
            // ── Lock Screen / StandBy ────────────────────────────────────
            LockScreenView(state: context.state)

        } dynamicIsland: { context in
            // ── Dynamic Island ───────────────────────────────────────────
            DynamicIsland {
                // Expanded (tap si hold pe insula)
                DynamicIslandExpandedRegion(.leading) {
                    Label("BOT", systemImage: "brain.filled.head.profile")
                        .font(.caption2.bold())
                        .foregroundColor(.purple)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.confidence * 100))%")
                        .font(.caption2.bold())
                        .foregroundColor(confidenceColor(context.state.confidence))
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                    } else {
                        Text(context.state.displayText)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        if let gold = context.state.gold {
                            Label("\(gold)g", systemImage: "circle.fill")
                                .foregroundColor(.yellow)
                        }
                        if let hp = context.state.hp {
                            Label("\(hp)hp", systemImage: "heart.fill")
                                .foregroundColor(.green)
                        }
                        Spacer()
                        Text(context.state.action.uppercased())
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.3))
                            .clipShape(Capsule())
                    }
                    .font(.caption2)
                }
            } compactLeading: {
                // Compact left: icon animat cand analizeaza
                if context.state.isAnalyzing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .tint(.purple)
                } else {
                    Image(systemName: "brain")
                        .foregroundColor(.purple)
                        .font(.caption2)
                }
            } compactTrailing: {
                // Compact right: actiunea sau gold
                Text(context.state.action.prefix(4).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.purple)
            } minimal: {
                // Minimal (cand doua live activities active)
                Image(systemName: "brain")
                    .foregroundColor(.purple)
            }
        }
    }

    private func confidenceColor(_ c: Double) -> Color {
        c >= 0.8 ? .green : c >= 0.5 ? .yellow : .red
    }
}

// ── Lock Screen / StandBy view ────────────────────────────────────────────

struct LockScreenView: View {
    let state: BotActivityAttributes.Status

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.filled.head.profile")
                .font(.title2)
                .foregroundColor(.purple)
                .symbolEffect(.pulse, isActive: state.isAnalyzing)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.isAnalyzing ? "Analizez..." : state.displayText)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(state.action.uppercased())
                    .font(.caption)
                    .foregroundColor(.purple)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let gold = state.gold {
                    Label("\(gold)", systemImage: "circle.fill")
                        .font(.caption.bold())
                        .foregroundColor(.yellow)
                }
                if let hp = state.hp {
                    Label("\(hp)", systemImage: "heart.fill")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(.black.opacity(0.8))
    }
}
