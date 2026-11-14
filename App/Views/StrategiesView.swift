import SwiftUI

struct StrategiesView: View {
    @Environment(AppModel.self) private var model
    @State private var profile: NetworkKind = .wifi

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Toggle("Отдельная стратегия для сотовой сети", isOn: $model.config.separateCellularProfile)
                if model.config.separateCellularProfile {
                    Picker("Профиль", selection: $profile) {
                        Text("Wi-Fi").tag(NetworkKind.wifi)
                        Text("Сотовая").tag(NetworkKind.cellular)
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Автоподбор при блокировке", isOn: $model.config.autoFallback)
            } footer: {
                Text("Мобильные операторы и домашние провайдеры используют разные DPI, поэтому стратегии хранятся раздельно и переключаются автоматически при смене сети. Автоподбор пробует запасные приёмы, если соединение сброшено, повисло или TLS-рукопожатие не завершилось, и запоминает удачный вариант для IP.")
            }

            Section("Стратегии zapret, адаптированные под iOS") {
                ForEach(StrategyCatalog.all) { strategy in
                    StrategyRow(strategy: strategy, selected: selectedID == strategy.id) {
                        model.setStrategy(strategy.id, for: effectiveProfile)
                    }
                }
            }

            Section {
                StrategyRow(strategy: StrategyCatalog.custom(model.config.customArgs),
                            selected: selectedID == StrategyCatalog.customID) {
                    model.setStrategy(StrategyCatalog.customID, for: effectiveProfile)
                }
                TextField("Параметры byedpi", text: $model.config.customArgs, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Свои параметры")
            } footer: {
                Text("Синтаксис byedpi: --split, --disorder, --oob, --disoob, --tlsrec, --mod-http, --tlsminor. Позиции вида 1, 1+s, 0+sm, -1. Применяется к доменам из списков.")
            }

            Section {
                Text("На iOS нельзя отправлять самодельные TCP-пакеты, поэтому приёмы fake с badseq/ts/md5sig и seqovl из Windows-версии заменены ближайшими по смыслу: split, disorder (сегмент с TTL=1), OOB и разбиение TLS-записи. UDP-фейки для QUIC и голоса Discord работают как в оригинале.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Стратегии")
        .onAppear {
            profile = model.currentNetwork == .cellular ? .cellular : .wifi
        }
    }

    private var effectiveProfile: NetworkKind {
        model.config.separateCellularProfile ? profile : .wifi
    }

    private var selectedID: String {
        model.strategyID(for: effectiveProfile)
    }
}

private struct StrategyRow: View {
    let strategy: Strategy
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(strategy.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(strategy.origin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(strategy.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
