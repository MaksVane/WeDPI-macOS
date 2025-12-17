import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spoofDPIService: SpoofDPIService
    
    var isSpoofDPIAvailable: Bool {
        spoofDPIService.isSpoofDPIAvailable()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HeaderView()
            
            Divider()
            
            if !isSpoofDPIAvailable {
                SpoofDPIWarningView()
            } else {
                ConnectionView()
            }
            
            Spacer()
            
            Divider()
            
            BottomActionsView()
        }
        .padding()
        .frame(width: 300, height: isSpoofDPIAvailable ? 340 : 320)
    }
}
struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("WeDPI")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Обход блокировок")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}
struct ConnectionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spoofDPIService: SpoofDPIService
    @State private var isLoading = false
    @State private var showBPFWarning = false
    
    var body: some View {
        VStack(spacing: 16) {
            if showBPFWarning && !appState.isConnected {
                BPFWarningView(spoofDPIService: spoofDPIService) {
                    showBPFWarning = false
                }
            }
            
            HStack {
                Circle()
                    .fill(appState.isConnected ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                    .shadow(color: appState.isConnected ? .green.opacity(0.5) : .clear, radius: 4)
                
                Text(appState.isConnected ? "Подключено" : "Отключено")
                    .font(.headline)
                
                Spacer()
                
                if appState.isConnected {
                    Text(appState.formattedConnectionTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(appState.isConnected ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
            )
            
            Button(action: toggleConnection) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: appState.isConnected ? "stop.fill" : "play.fill")
                    }
                    Text(appState.isConnected ? "Отключить" : "Подключить")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(appState.isConnected ? Color.red : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            
            if appState.showError {
                Text(appState.statusMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear {
            showBPFWarning = !spoofDPIService.isBPFAccessible()
        }
    }
    
    private func toggleConnection() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            if self.appState.isConnected {
                self.disconnect()
            } else {
                self.connect()
            }
            
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
    
    private func connect() {
        print("Начинаем подключение...")
        
        do {
            try spoofDPIService.start(port: appState.proxyPort, bypassDomains: appState.effectiveBypassDomains)
            
            Thread.sleep(forTimeInterval: 0.5)
            
            DispatchQueue.main.async {
                self.appState.isConnected = true
                self.appState.statusMessage = "Подключено"
                self.appState.showError = false
                self.appState.startTracking()
                
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.updateStatusIcon(isActive: true)
                }
            }
            
            print("Подключение успешно!")
            
        } catch {
            print("Ошибка подключения: \(error)")
            
            DispatchQueue.main.async {
                self.appState.statusMessage = error.localizedDescription
                self.appState.showError = true
            }
        }
    }
    
    private func disconnect() {
        print("Отключение...")
        
        spoofDPIService.stop()
        
        DispatchQueue.main.async {
            self.appState.isConnected = false
            self.appState.statusMessage = "Отключено"
            self.appState.showError = false
            self.appState.stopTracking()
            
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.updateStatusIcon(isActive: false)
            }
        }
        
        print("Отключение завершено")
    }
}
struct BPFWarningView: View {
    let spoofDPIService: SpoofDPIService
    let onDismiss: () -> Void
    @State private var isSettingUp = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                Text("Требуются права BPF")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 8) {
                Button(action: setupBPF) {
                    if isSettingUp {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Text("Настроить")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSettingUp)
                
                Text("для Discord/Instagram")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    private func setupBPF() {
        isSettingUp = true
        spoofDPIService.setupBPFPermissions { success in
            DispatchQueue.main.async {
                isSettingUp = false
                if success {
                    onDismiss()
                }
            }
        }
    }
}
struct SpoofDPIWarningView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("SpoofDPI не установлен")
                .font(.headline)
            
            Text("Установите через Homebrew:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("brew install spoofdpi")
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .textSelection(.enabled)
            
            Button(action: openInstallInstructions) {
                Label("Инструкция", systemImage: "safari")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    private func openInstallInstructions() {
        if let url = URL(string: "https://github.com/xvzc/SpoofDPI#installation") {
            NSWorkspace.shared.open(url)
        }
    }
}
struct BottomActionsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spoofDPIService: SpoofDPIService
    @State private var showSettings = false
    
    var body: some View {
        HStack {
            Button(action: { showSettings = true }) {
                Label("Настройки", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSettings) {
                SettingsView(isPresented: $showSettings, showHeader: true)
                    .environmentObject(appState)
                    .environmentObject(spoofDPIService)
            }
            
            Spacer()
            
            Button(action: quitApp) {
                Label("Выход", systemImage: "power")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func quitApp() {
        spoofDPIService.stop()
        NSApp.terminate(nil)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
        .environmentObject(SpoofDPIService())
}
