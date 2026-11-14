import NetworkExtension
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PowerOrb()
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text(statusTitle)
                            .font(.title2.weight(.bold))
                            .contentTransition(.numericText())
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .animation(.snappy, value: statusTitle)

                    if !AppEdition.isLite {
                        Picker("Режим", selection: $model.config.mode) {
                            Text("Свой VPN").tag(RunMode.vpn)
                            Text("Прокси + sing-box").tag(RunMode.proxy)
                        }
                        .pickerStyle(.segmented)
                        .padding(6)
                        .glassCard(cornerRadius: 18)
                    }

                    if let version = model.updates.available {
                        UpdateBanner(version: version)
                    }

                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.octagon.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .glassCard(tint: .red.opacity(0.15))
                    }

                    if model.mode == .vpn && !Paths.hasSharedContainer {
                        Label("App Group недоступна, значит у подписи нет прав Network Extension. Это бывает с бесплатным Apple ID — переключитесь на режим «Прокси + sing-box».",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(16)
                            .glassCard(tint: .orange.opacity(0.15))
                    }

                    GlassGroup(spacing: 12) {
                        HStack(spacing: 12) {
                            InfoTile(title: "Сеть", value: networkText, symbol: model.currentNetwork.symbol)
                            NavigationLink {
                                StrategiesView()
                            } label: {
                                InfoTile(title: "Стратегия", value: StrategyCatalog.name(for: model.activeStrategyID),
                                         symbol: "wand.and.stars", chevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if model.mode == .proxy {
                        ProxyCard()
                    }

                    if model.mode == .vpn, let status = model.tunnel.tunnelStatus {
                        TrafficCard(status: status)
                    }

                    Text("Всё работает на устройстве: трафик не уходит на сторонние серверы. Обход применяется только к доменам из списков zapret-discord-youtube.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background { StatusBackground(color: stateColor) }
            .navigationTitle(AppEdition.name)
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    private var stateColor: Color {
        if model.isOn { return .green }
        if model.isTransitioning { return .orange }
        return .gray
    }

    private var statusTitle: String {
        if model.isTransitioning { return model.isOn ? "Отключение…" : "Подключение…" }
        return model.isOn ? "Обход включён" : "Обход выключен"
    }

    private var subtitle: String {
        if model.isOn, let since = model.startedAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return "Работает \(f.localizedString(for: since, relativeTo: Date()).replacingOccurrences(of: "назад", with: "").trimmingCharacters(in: .whitespaces))"
        }
        return model.mode == .vpn
            ? "Локальный VPN-туннель с движком byedpi"
            : "Локальный SOCKS5 127.0.0.1:\(model.proxy.activePort ?? model.config.proxyPort) для sing-box"
    }

    private var networkText: String {
        if model.currentNetwork == .cellular, let radio = model.tunnel.tunnelStatus?.radio {
            return "Сотовая · \(radio)"
        }
        return model.currentNetwork.title
    }
}

private struct PowerOrb: View {
    @Environment(AppModel.self) private var model
    @State private var pulse = false

    var body: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 236, height: 236)
                    .scaleEffect(pulse && model.isOn ? 1.06 : 1)
                    .blur(radius: 18)
                Group {
                    if model.isTransitioning {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(color)
                            .symbolEffect(.bounce, value: model.isOn)
                    }
                }
                .frame(width: 180, height: 180)
                .glassCircle(tint: model.isOn ? color.opacity(0.35) : nil)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isTransitioning)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.isOn)
        .accessibilityLabel(model.isOn ? "Выключить обход" : "Включить обход")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var color: Color {
        if model.isOn { return .green }
        if model.isTransitioning { return .orange }
        return .secondary
    }
}

private struct InfoTile: View {
    let title: String
    let value: String
    let symbol: String
    var chevron = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Spacer()
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(interactive: chevron)
    }
}

private struct ProxyCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "sing-box", symbol: "point.3.connected.trianglepath.dotted")
            Text("Режим для бесплатного Apple ID. Zapret работает как локальный прокси, а sing-box из App Store направляет в него трафик YouTube и Discord. Остальное идёт напрямую.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if model.proxy.isRunning {
                HStack(spacing: 8) {
                    StatusDot(color: .green)
                    Text("Прокси слушает 127.0.0.1:\(model.proxy.activePort ?? model.config.proxyPort)")
                    if let iface = model.proxy.interfaceName {
                        Text("· \(iface)").foregroundStyle(.secondary)
                    }
                }
                .font(.footnote.monospaced())
            }
            HStack {
                Button {
                    if let url = SingBoxProfile.importURL { openURL(url) }
                } label: {
                    Label("Добавить в sing-box", systemImage: "plus.circle.fill")
                }
                .prominentButton()
                NavigationLink {
                    ProxySetupView()
                } label: {
                    Text("Инструкция")
                }
                .secondaryButton()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct TrafficCard: View {
    let status: TunnelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Трафик через туннель", symbol: "arrow.up.arrow.down")
            HStack {
                stat("Отправлено", ByteFormat.string(status.txBytes), "arrow.up")
                Spacer()
                stat("Получено", ByteFormat.string(status.rxBytes), "arrow.down")
                if status.restarts > 0 {
                    Spacer()
                    stat("Перезапуски", "\(status.restarts)", "arrow.clockwise")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).contentTransition(.numericText())
        }
    }
}

struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    let version: UpdateChecker.Version

    init(version: UpdateChecker.Version) {
        self.version = version
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Доступна версия \(version.version)", systemImage: "arrow.down.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            if let notes = version.localizedDescription, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
            Button("Обновить через AltStore") {
                model.updates.install(version)
            }
            .prominentButton()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .blue.opacity(0.12))
    }
}
