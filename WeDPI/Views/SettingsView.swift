import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spoofDPIService: SpoofDPIService
    @Environment(\.dismiss) var dismiss
    @Binding var isPresented: Bool
    let showHeader: Bool
    
    init(isPresented: Binding<Bool> = .constant(true), showHeader: Bool = true) {
        self._isPresented = isPresented
        self.showHeader = showHeader
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                HStack {
                    Text("Настройки")
                        .font(.headline)
                    Spacer()
                    Button(action: closeSettings) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            
            TabView {
                GeneralSettingsView()
                    .tabItem {
                        Label("Основные", systemImage: "gear")
                    }
                
                LogsView()
                    .environmentObject(spoofDPIService)
                    .tabItem {
                        Label("Логи", systemImage: "doc.text")
                    }
                
                AboutView()
                    .tabItem {
                        Label("О программе", systemImage: "info.circle")
                    }
            }
        }
        .frame(width: 400, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func closeSettings() {
        isPresented = false
        dismiss()
    }
}
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spoofDPIService: SpoofDPIService
    @State private var launchAtLogin = false
    @State private var portString: String = ""
    @State private var customBypassText: String = ""
    
    var body: some View {
        Form {
            Section {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
                
                Toggle("Автоподключение при запуске", isOn: $appState.autoConnect)
            } header: {
                Text("Запуск")
            }
            
            Section {
                HStack {
                    Text("Порт прокси")
                    Spacer()
                    TextField("8080", text: $portString)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: portString) { newValue in
                            if let port = Int(newValue), port > 0 && port < 65536 {
                                appState.proxyPort = port
                            }
                        }
                }
                
                Text("SpoofDPI будет работать на 127.0.0.1:\(appState.proxyPort)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Сеть")
            }
            
            Section {
                Toggle("Обход Discord (DIRECT)", isOn: $appState.bypassDiscord)
                    .onChange(of: appState.bypassDiscord) { _ in
                        spoofDPIService.setBypassDomains(appState.effectiveBypassDomains)
                    }
                Text("Полезно, если демонстрация экрана/Go Live ломается при включённом WeDPI. Discord-домены будут идти напрямую, остальной трафик — через WeDPI.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Пользовательский обход (DIRECT)", isOn: $appState.customBypassEnabled)
                    .onChange(of: appState.customBypassEnabled) { _ in
                        spoofDPIService.setBypassDomains(appState.effectiveBypassDomains)
                    }
                
                TextEditor(text: $customBypassText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .onChange(of: customBypassText) { newValue in
                        appState.customBypassDomainsRaw = newValue
                        spoofDPIService.setBypassDomains(appState.effectiveBypassDomains)
                    }
                
                Text("Список доменов/масок через запятую или с новой строки. Примеры: `youtube.com`, `.googlevideo.com`, `gateway.discord.gg`")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Совместимость")
            }
            
            Section {
                HStack {
                    Text("SpoofDPI")
                    Spacer()
                    if SpoofDPIService().isSpoofDPIAvailable() {
                        Label("Установлен", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Не найден", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text("Компоненты")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = isLaunchAtLoginEnabled()
            portString = String(appState.proxyPort)
            customBypassText = appState.customBypassDomainsRaw
        }
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Ошибка настройки автозапуска: \(error)")
        }
    }
    
    private func isLaunchAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
}
struct AboutView: View {
    @EnvironmentObject var appState: AppState
    @State private var showUpdateSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 4) {
                Text("WeDPI")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Версия \(appState.appVersionString)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("Простое приложение для обхода\nблокировок на macOS")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
            
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await appState.checkForUpdates()
                            showUpdateSheet = true
                        }
                    } label: {
                        if appState.isCheckingForUpdates {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Проверяем…")
                            }
                        } else {
                            Text("Проверить обновления")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isCheckingForUpdates)

                    Button("Открыть Releases") {
                        let repo = appState.updatesRepo.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !repo.isEmpty, let url = URL(string: "https://github.com/\(repo)/releases") else { return }
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Text("GitHub repo для обновлений")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                TextField("owner/repo", text: appState.$updatesRepo)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))

                Link(destination: URL(string: "https://github.com/xvzc/SpoofDPI")!) {
                    Label("SpoofDPI", systemImage: "link")
                        .font(.caption)
                }
            }
            
            Spacer()
            
            Text("Основано на SpoofDPI")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .sheet(isPresented: $showUpdateSheet) {
            UpdateResultView(isPresented: $showUpdateSheet)
                .environmentObject(appState)
        }
    }
}
struct UpdateResultView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Обновления")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let error = appState.lastUpdateCheckError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            } else if let update = appState.availableUpdate {
                Label("Доступна версия \(update.latestVersion)", systemImage: "arrow.down.circle.fill")
                    .foregroundColor(.accentColor)

                if let notes = update.releaseNotes, !notes.isEmpty {
                    Text("Что нового:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    ScrollView {
                        Text(notes)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                HStack {
                    if let dmg = update.dmgDownloadURL {
                        Button("Скачать DMG") {
                            NSWorkspace.shared.open(dmg)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let page = update.releasePageURL {
                        Button("Открыть страницу релиза") {
                            NSWorkspace.shared.open(page)
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }

                Text("После скачивания замените приложение в /Applications.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Label("Обновлений нет — у вас актуальная версия.", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            Spacer()
        }
        .padding()
        .frame(width: 520, height: 360)
    }
}

#Preview {
    SettingsView(isPresented: .constant(true), showHeader: true)
        .environmentObject(AppState())
        .environmentObject(SpoofDPIService())
}
