import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updates: UpdateChecker

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("QUIC (UDP 443)", selection: $model.config.quicMode) {
                        ForEach(QuicMode.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Голос Discord (UDP-фейки)", isOn: $model.config.discordVoice)
                    Toggle("Game filter", isOn: $model.config.gameFilter)
                        .disabled(model.config.ipsetMode == .off)
                    Stepper("TTL UDP-фейков: \(model.config.udpFakeTTL)", value: $model.config.udpFakeTTL, in: 1...128)
                    Stepper("Повторов фейка: \(model.config.udpFakeRepeats)", value: $model.config.udpFakeRepeats, in: 1...20)
                } header: {
                    Text("UDP")
                } footer: {
                    Text("Как в zapret: перед первым пакетом QUIC/Discord отправляется поддельный (×6). TTL 64 — без «fooling», как в оригинале. Если на мобильной сети звонки Discord не соединяются, попробуйте TTL 3–8. «Блокировать QUIC» заставляет YouTube перейти на TCP, где обход надёжнее. Game filter работает только с включённым ipset.")
                }

                Section {
                    Picker("DNS", selection: $model.config.dns) {
                        ForEach(DNSPreset.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("IPv6 через туннель", isOn: $model.config.ipv6)
                    Toggle("Подключаться автоматически", isOn: $model.config.onDemand)
                } header: {
                    Text("Сеть")
                } footer: {
                    Text("DoH защищает от подмены DNS у провайдера. Многие мобильные операторы выдают IPv6 — оставьте его включённым, иначе YouTube по IPv6 пойдёт мимо обхода. Автоподключение (On Demand) поднимает туннель при любой смене сети.")
                }

                Section("Обновления") {
                    LabeledContent("Версия", value: "\(AppIdentity.appVersion) (\(AppIdentity.buildNumber))")
                    if let version = updates.available {
                        UpdateBanner(version: version)
                    }
                    Button {
                        Task { await updates.check() }
                    } label: {
                        HStack {
                            Text("Проверить обновления")
                            if updates.checking { Spacer(); ProgressView() }
                        }
                    }
                    if let message = updates.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Добавить источник в AltStore") { updates.addSource() }
                }

                Section("Диагностика") {
                    Toggle("Подробный журнал", isOn: $model.config.verboseLog)
                    NavigationLink("Журналы") { LogsView() }
                }

                Section("О приложении") {
                    Link("Исходный код", destination: Links.repo)
                    Link("zapret-discord-youtube (Flowseal)", destination: Links.upstreamRepo)
                    Link("byedpi (hufrea)", destination: URL(string: "https://github.com/hufrea/byedpi")!)
                    Link("hev-socks5-tunnel (heiher)", destination: URL(string: "https://github.com/heiher/hev-socks5-tunnel")!)
                    Text("Списки доменов и фейковые пакеты — из zapret-discord-youtube (MIT). Движок десинхронизации — byedpi (MIT), tun2socks — hev-socks5-tunnel (MIT).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
