import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if !AppEdition.isLite {
                    Section {
                        Picker("Режим работы", selection: $model.config.mode) {
                            ForEach(RunMode.allCases) { Text($0.title).tag($0) }
                        }
                    } footer: {
                        Text("Свой VPN-туннель требует платного аккаунта разработчика в AltStore. «Прокси + sing-box» работает и с бесплатным Apple ID.")
                    }
                }

                if model.mode == .proxy {
                    Section {
                        NavigationLink("Настройка sing-box") { ProxySetupView() }
                        Toggle("Работать в фоне (тихое аудио)", isOn: $model.config.keepAliveAudio)
                        LabeledContent("Порт SOCKS5", value: "\(model.proxy.activePort ?? model.config.proxyPort)")
                    } header: {
                        Text("Прокси")
                    } footer: {
                        Text("iOS выгружает приложения из фона. Тихий аудиопоток (не мешает музыке) держит движок живым. Порт выбирается автоматически из 10920–10923, профиль sing-box сам находит рабочий.")
                    }
                }

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
                    Text("Как в zapret: перед первым пакетом QUIC или Discord отправляется поддельный ×6. TTL 64 соответствует оригиналу (без fooling). Если звонки Discord на мобильной сети не соединяются, попробуйте TTL 3–8. «Блокировать QUIC» переводит YouTube на TCP, где обход надёжнее.")
                }

                Section {
                    Picker("DNS", selection: $model.config.dns) {
                        ForEach(DNSPreset.allCases) { Text($0.title).tag($0) }
                    }
                    if model.mode == .vpn {
                        Toggle("IPv6 через туннель", isOn: $model.config.ipv6)
                        Toggle("Подключаться автоматически", isOn: $model.config.onDemand)
                    }
                } header: {
                    Text("Сеть")
                } footer: {
                    Text(model.mode == .vpn
                         ? "DoH защищает от подмены DNS у провайдера. Многие операторы выдают IPv6: оставьте его включённым, иначе YouTube по IPv6 пойдёт мимо обхода."
                         : "DNS используется в экспортированном профиле sing-box.")
                }

                Section("Обновления") {
                    LabeledContent("Версия", value: "\(AppIdentity.appVersion) (\(AppIdentity.buildNumber))")
                    if let version = model.updates.available {
                        UpdateBanner(version: version)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Button {
                        Task { await model.updates.check() }
                    } label: {
                        HStack {
                            Text("Проверить обновления")
                            if model.updates.checking { Spacer(); ProgressView() }
                        }
                    }
                    if let message = model.updates.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Добавить источник в AltStore") { model.updates.addSource() }
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
                    Text("Списки доменов и фейковые пакеты взяты из zapret-discord-youtube (MIT). Движок десинхронизации — byedpi (MIT), tun2socks — hev-socks5-tunnel (MIT).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
