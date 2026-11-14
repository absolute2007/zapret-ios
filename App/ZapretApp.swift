import SwiftUI

@main
struct ZapretApp: App {
    @StateObject private var tunnel = TunnelManager()
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateChecker()
    @StateObject private var tester = StrategyTester()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(tunnel)
                .environmentObject(model)
                .environmentObject(updates)
                .environmentObject(tester)
                .onAppear { model.tunnel = tunnel }
                .task { await updates.checkIfNeeded() }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task {
                        await tunnel.refreshStatus()
                        await updates.checkIfNeeded()
                        if model.config.listsAutoUpdate, ListStore.isStale, !tunnel.isConnected {
                            await model.updateLists()
                        }
                    }
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Главная", systemImage: "power") }
            StrategiesView()
                .tabItem { Label("Стратегии", systemImage: "slider.horizontal.3") }
            TesterView()
                .tabItem { Label("Подбор", systemImage: "stethoscope") }
            ListsView()
                .tabItem { Label("Списки", systemImage: "list.bullet.rectangle") }
            SettingsView()
                .tabItem { Label("Ещё", systemImage: "gearshape") }
        }
    }
}
