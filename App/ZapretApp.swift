import SwiftUI

@main
struct ZapretApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.updates.checkIfNeeded() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await model.tunnel.refreshStatus()
                        await model.updates.checkIfNeeded()
                        if model.config.listsAutoUpdate, ListStore.isStale {
                            await model.updateLists()
                        }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("Главная", systemImage: "power") {
                HomeView()
            }
            Tab("Стратегии", systemImage: "slider.horizontal.3") {
                NavigationStack { StrategiesView() }
            }
            Tab("Подбор", systemImage: "stethoscope") {
                TesterView()
            }
            Tab("Списки", systemImage: "list.bullet.rectangle") {
                ListsView()
            }
            Tab("Ещё", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .modernTabBar {
            StatusAccessory()
        }
    }
}

/// Compact status + quick toggle above the tab bar (iOS 26).
private struct StatusAccessory: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: model.isOn ? .green : (model.isTransitioning ? .orange : .secondary))
            VStack(alignment: .leading, spacing: 0) {
                Text(model.isOn ? "Обход включён" : "Обход выключен")
                    .font(.subheadline.weight(.semibold))
                Text(StrategyCatalog.name(for: model.activeStrategyID) + " · " + model.currentNetwork.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await model.toggle() }
            } label: {
                Image(systemName: model.isOn ? "stop.fill" : "play.fill")
            }
            .disabled(model.isTransitioning)
        }
        .padding(.horizontal, 16)
    }
}
