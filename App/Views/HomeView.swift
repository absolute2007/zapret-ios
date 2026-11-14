import NetworkExtension
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updates: UpdateChecker

    var body: some View {
        NavigationStack {
            List {
                if let version = updates.available {
                    Section {
                        UpdateBanner(version: version)
                    }
                }

                if !Paths.hasSharedContainer {
                    Section {
                        Label("App Group недоступна. Приложение должно быть установлено через AltStore с правами Network Extension и App Groups.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    PowerButton()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                }

                if let error = tunnel.lastError ?? tunnel.tunnelStatus?.lastError {
                    Section {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section("Сейчас") {
                    let network = model.currentNetwork
                    LabeledContent {
                        Text(networkText(network))
                    } label: {
                        Label("Сеть", systemImage: network.symbol)
                    }
                    let activeID = tunnel.tunnelStatus?.strategyID ?? model.config.strategyID(for: network)
                    NavigationLink {
                        StrategiesView(embedded: true)
                    } label: {
                        LabeledContent {
                            Text(StrategyCatalog.name(for: activeID))
                        } label: {
                            Label("Стратегия", systemImage: "wand.and.stars")
                        }
                    }
                    LabeledContent {
                        Text(model.config.autoFallback ? "включён" : "выключен")
                    } label: {
                        Label("Автоподбор при блокировке", systemImage: "arrow.triangle.branch")
                    }
                }

                if let status = tunnel.tunnelStatus {
                    Section("Трафик") {
                        LabeledContent("Отправлено", value: ByteFormat.string(status.txBytes))
                        LabeledContent("Получено", value: ByteFormat.string(status.rxBytes))
                        LabeledContent("Работает с") {
                            Text(status.startedAt, style: .relative)
                        }
                        if status.restarts > 0 {
                            LabeledContent("Перезапусков движка", value: "\(status.restarts)")
                        }
                    }
                }

                Section {
                    Text("Трафик обрабатывается локально на устройстве: туннель не отправляет данные на сторонние серверы. Десинхронизация применяется только к доменам из списков zapret-discord-youtube.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Zapret")
        }
    }

    private func networkText(_ kind: NetworkKind) -> String {
        if kind == .cellular, let radio = tunnel.tunnelStatus?.radio {
            return "\(kind.title) · \(radio)"
        }
        return kind.title
    }
}

private struct PowerButton: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    if tunnel.isConnected || tunnel.vpnStatus == .connecting || tunnel.vpnStatus == .reasserting {
                        await tunnel.disconnect()
                    } else {
                        await tunnel.connect(config: model.config)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 168, height: 168)
                    Circle()
                        .stroke(color, lineWidth: 4)
                        .frame(width: 140, height: 140)
                    if tunnel.isTransitioning || tunnel.isBusy {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(tunnel.isBusy)
            .accessibilityLabel(tunnel.isConnected ? "Отключить" : "Подключить")

            Text(statusText)
                .font(.headline)
        }
    }

    private var color: Color {
        switch tunnel.vpnStatus {
        case .connected: return .green
        case .connecting, .reasserting, .disconnecting: return .orange
        default: return .secondary
        }
    }

    private var statusText: String {
        switch tunnel.vpnStatus {
        case .connected: return "Обход включён"
        case .connecting: return "Подключение…"
        case .reasserting: return "Переподключение…"
        case .disconnecting: return "Отключение…"
        case .invalid: return "Нажмите, чтобы создать профиль VPN"
        default: return "Обход выключен"
        }
    }
}

struct UpdateBanner: View {
    @EnvironmentObject private var updates: UpdateChecker
    let version: UpdateChecker.Version

    init(version: UpdateChecker.Version) {
        self.version = version
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Доступна версия \(version.version)", systemImage: "arrow.down.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            if let notes = version.localizedDescription, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Button("Обновить через AltStore") {
                updates.install(version)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}
