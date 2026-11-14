import SwiftUI

struct ListsView: View {
    @Environment(AppModel.self) private var model
    @State private var refreshID = UUID()

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            await model.updateLists()
                            refreshID = UUID()
                        }
                    } label: {
                        HStack {
                            Label("Обновить из репозитория Flowseal", systemImage: "arrow.clockwise")
                            if model.updatingLists {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.updatingLists)

                    Toggle("Автообновление (раз в сутки)", isOn: $model.config.listsAutoUpdate)

                    if let date = model.listsMeta.lastUpdate {
                        LabeledContent("Последнее обновление") {
                            Text(date, format: .dateTime.day().month().hour().minute())
                        }
                    } else {
                        LabeledContent("Последнее обновление", value: "встроенные списки")
                    }
                    if let message = model.listsMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Источник: github.com/Flowseal/zapret-discord-youtube (lists/ и .service/ipset-service.txt).")
                }

                Section("Списки") {
                    ForEach(ListKind.allCases) { kind in
                        NavigationLink {
                            ListEditorView(kind: kind)
                        } label: {
                            LabeledContent(kind.title) {
                                Text("\(ListStore.count(kind))")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .id(refreshID)

                Section {
                    Picker("Режим ipset", selection: $model.config.ipsetMode) {
                        ForEach(IpsetMode.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("Как переключатель ipset в service.bat: при включении обход применяется и к IP-адресам из ipset-all, даже если домен неизвестен (нужно для игр и некоторых приложений).")
                }
            }
            .navigationTitle("Списки")
            .onAppear { refreshID = UUID() }
        }
    }
}

struct ListEditorView: View {
    @Environment(AppModel.self) private var model
    let kind: ListKind
    @State private var userText = ""
    @State private var showUpstream = false

    init(kind: ListKind) {
        self.kind = kind
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $userText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 220)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Ваши записи (\(kind.userFileName))")
            } footer: {
                Text(kind.isIPSet
                     ? "По одному IP или подсети в строке, например 203.0.113.0/24."
                     : "По одному домену в строке. Поддомены включаются автоматически.")
            }

            Section {
                DisclosureGroup("Записи из репозитория", isExpanded: $showUpstream) {
                    let entries = ListStore.entries(ListStore.read(kind), ipset: kind.isIPSet)
                    Text(entries.prefix(500).joined(separator: "\n") + (entries.count > 500 ? "\n… ещё \(entries.count - 500)" : ""))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { userText = ListStore.read(kind, user: true) }
        .onDisappear {
            if userText != ListStore.read(kind, user: true) {
                ListStore.writeUser(kind, text: userText)
                model.userListChanged()
            }
        }
    }
}
