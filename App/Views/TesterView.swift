import SwiftUI

struct TesterView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: StrategyTester.Mode = .quick
    @State private var applyTarget: StrategyTester.Result?

    private var tester: StrategyTester { model.tester }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Режим", selection: $mode) {
                        ForEach(StrategyTester.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(tester.running)

                    if tester.running {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: tester.progress)
                            Text("Проверяется: \(tester.current ?? "…")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("Остановить", role: .destructive) { tester.cancel() }
                    } else {
                        Button {
                            Task { await model.runTester(mode: mode) }
                        } label: {
                            Label("Подобрать стратегию: \(model.currentNetwork.title)", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .prominentButton()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                } footer: {
                    Text("Каждая стратегия запускается локально и проверяет YouTube и Discord в текущей сети. Обход на время проверки выключается и включается обратно. Проверку стоит повторить отдельно на Wi-Fi и на мобильном интернете.")
                }

                if let baseline = tester.baseline {
                    Section("Без обхода") {
                        ResultRow(result: baseline, total: StrategyTester.targets.count)
                    }
                }

                if !tester.sortedResults.isEmpty {
                    Section("Результаты (нажмите, чтобы применить)") {
                        ForEach(tester.sortedResults) { result in
                            Button {
                                applyTarget = result
                            } label: {
                                ResultRow(result: result, total: StrategyTester.targets.count)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error = tester.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Подбор стратегии")
            .confirmationDialog("Применить «\(applyTarget?.name ?? "")»",
                                isPresented: Binding(get: { applyTarget != nil }, set: { if !$0 { applyTarget = nil } }),
                                titleVisibility: .visible) {
                if let result = applyTarget {
                    Button("Для Wi-Fi") { model.setStrategy(result.id, for: .wifi) }
                    Button("Для сотовой сети") {
                        model.config.separateCellularProfile = true
                        model.setStrategy(result.id, for: .cellular)
                    }
                    Button("Для всех сетей") {
                        model.config.separateCellularProfile = false
                        model.setStrategy(result.id, for: .wifi)
                    }
                }
            }
        }
    }
}

private struct ResultRow: View {
    let result: StrategyTester.Result
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.name).font(.body.weight(.semibold))
                Spacer()
                Text("\(result.passed)/\(total)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
            }
            HStack(spacing: 12) {
                Label("YouTube \(result.passed(group: "yt"))/4", systemImage: "play.rectangle")
                Label("Discord \(result.passed(group: "dc"))/4", systemImage: "message")
                if result.avgMillis > 0 {
                    Text("\(result.avgMillis) мс")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            let failed = result.targets.filter { !$0.ok }
            if !failed.isEmpty {
                Text(failed.map { "\($0.id): \($0.detail)" }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .contentShape(Rectangle())
    }

    private var color: Color {
        if result.passed == total { return .green }
        if result.passed == 0 { return .red }
        return .orange
    }
}
