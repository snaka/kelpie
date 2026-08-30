import SwiftUI
import KelpieCore

struct AgentListView: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banners
            if model.groups.isEmpty {
                Text("No agents")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.groups, id: \.status) { group in
                            section(group)
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            footer
        }
        .frame(width: 360)
    }

    @ViewBuilder
    private var banners: some View {
        if case .protocolMismatch(let version) = model.connection {
            banner("herdr speaks protocol \(version); Kelpie may need an update.")
        }
        if model.notificationsDenied {
            banner("Notifications are turned off for Kelpie in System Settings.")
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.2))
    }

    private func section(_ group: AgentGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.status.rawValue.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(group.rows, id: \.paneID) { row in
                Button {
                    model.onSelect?(row.paneID)
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Text(glyph(for: group.status))
                            .foregroundStyle(color(for: group.status))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.workspaceLabel).fontWeight(.medium)
                            if let title = row.title, !title.isEmpty {
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Toggle("Start at login", isOn: Binding(
                get: { model.startAtLogin },
                set: { model.onToggleLoginItem?($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            Button("Quit") { model.onQuit?() }
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(10)
    }

    private var statusText: String {
        switch model.connection {
        case .connecting: return "Connecting to herdr…"
        case .connected: return "Connected"
        case .disconnected: return "herdr server not running — retrying"
        case .protocolMismatch: return "Connected (protocol mismatch)"
        }
    }

    private func glyph(for status: AgentStatus) -> String {
        switch status {
        case .blocked: return "◉"
        case .working: return "⣿"
        case .done: return "✓"
        case .idle: return "○"
        case .unknown: return "·"
        }
    }

    private func color(for status: AgentStatus) -> Color {
        switch status {
        case .blocked: return .red
        case .working: return .yellow
        case .done: return .green
        case .idle, .unknown: return .secondary
        }
    }
}
