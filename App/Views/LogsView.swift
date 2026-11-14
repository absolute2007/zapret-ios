import SwiftUI

struct LogsView: View {
    enum Source: String, CaseIterable, Identifiable {
        case tunnel, engine, tun2socks, tester
        var id: String { rawValue }
        var title: String {
            switch self {
            case .tunnel: return "Туннель"
            case .engine: return "byedpi"
            case .tun2socks: return "tun2socks"
            case .tester: return "Подбор"
            }
        }
        var url: URL {
            switch self {
            case .tunnel: return Paths.tunnelLog
            case .engine: return Paths.engineLog
            case .tun2socks: return Paths.hevLog
            case .tester: return Paths.testerLog
            }
        }
    }

    @State private var source: Source = .tunnel
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Журнал", selection: $source) {
                ForEach(Source.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                Text(text.isEmpty ? "Пусто" : text)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Журналы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                ShareLink(item: text.isEmpty ? "—" : text) { Image(systemName: "square.and.arrow.up") }
                Button {
                    Log.clear(source.url)
                    reload()
                } label: {
                    Image(systemName: "trash")
                }
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: source) { _ in reload() }
    }

    private func reload() {
        text = Log.read(source.url)
    }
}
