import SwiftUI
import UIKit

struct ProxySetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var exportURL: URL?
    @State private var copied = false

    private var port: Int { model.proxy.activePort ?? model.config.proxyPort }

    private let appStoreSearch = URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=sing-box")!

    var body: some View {
        List {
            Section {
                Text("sing-box — бесплатный VPN-клиент из App Store. Apple разрешает ему VPN, поэтому собственный туннель Zapret не нужен и подходит бесплатный Apple ID. sing-box отправляет трафик YouTube и Discord в Zapret, а Zapret применяет стратегию.")
                    .font(.callout)
            }

            Section("1. Установите sing-box") {
                Button {
                    openURL(appStoreSearch)
                } label: {
                    Label("Найти «sing-box VT» в App Store", systemImage: "bag")
                }
                Text("Если в вашем регионе App Store его не показывает, подойдут Karing или Hiddify: они тоже на ядре sing-box и импортируют этот профиль.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    if let url = SingBoxProfile.importURL { openURL(url) }
                } label: {
                    Label("Добавить профиль в sing-box", systemImage: "plus.circle.fill")
                }
                Button {
                    exportURL = SingBoxProfile.exportFile(config: model.config)
                } label: {
                    Label("Экспортировать с моими списками", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("2. Профиль")
            } footer: {
                Text("Профиль по ссылке обновляется сам: списки доменов подтягиваются из репозитория раз в сутки. Экспорт файлом включает ваши собственные домены, но не обновляется автоматически. Если профиль импортирован в версии 1.1.0, обновите его в sing-box: там был порт 1080.")
            }

            Section {
                Label("Включите обход в Zapret (кнопка на главной)", systemImage: "1.circle")
                Label("Включите профиль Zapret в sing-box", systemImage: "2.circle")
                Label("Не закрывайте Zapret смахиванием из переключателя приложений", systemImage: "3.circle")
            } header: {
                Text("3. Запуск")
            } footer: {
                Text("Если iOS всё же выгрузит Zapret, перестанут работать только YouTube и Discord: остальной трафик идёт мимо прокси.")
            }

            Section {
                LabeledContent("Адрес", value: "127.0.0.1")
                LabeledContent("Порт", value: "\(port)")
                LabeledContent("Тип", value: "SOCKS5")
                Button(copied ? "Скопировано" : "Скопировать адрес") {
                    UIPasteboard.general.string = "socks5://127.0.0.1:\(port)"
                    copied = true
                }
            } header: {
                Text("Другие клиенты")
            } footer: {
                Text("Подойдёт любой клиент с SOCKS5. Настройте в нём маршрутизацию так, чтобы через этот прокси шли только нужные домены, а DNS запрашивался не через него.")
            }
        }
        .navigationTitle("sing-box")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
                .presentationDetents([.medium, .large])
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
