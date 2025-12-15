import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spoofDPIService: SpoofDPIService
    @Binding var isPresented: Bool
    
    @State private var currentStep = 0
    @State private var isInstalling = false
    @State private var installError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Добро пожаловать в WeDPI")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Настройка займёт несколько секунд")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
            
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep()
                case 1:
                    SpoofDPICheckStep(isInstalling: $isInstalling, installError: $installError)
                case 2:
                    PermissionsStep()
                case 3:
                    CompletionStep()
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            HStack {
                if currentStep > 0 {
                    Button("Назад") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    ForEach(0..<4) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                if currentStep < 3 {
                    Button("Далее") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 1 && !spoofDPIService.isSpoofDPIAvailable())
                } else {
                    Button("Готово") {
                        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 400, height: 450)
    }
}
struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            FeatureRow(
                icon: "globe",
                title: "Обход блокировок",
                description: "Доступ к YouTube, Discord и другим сервисам"
            )
            
            FeatureRow(
                icon: "bolt.fill",
                title: "Простое управление",
                description: "Включение одной кнопкой из menubar"
            )
            
            FeatureRow(
                icon: "lock.shield",
                title: "Безопасность",
                description: "Не собирает и не передаёт данные"
            )
            
            FeatureRow(
                icon: "gear",
                title: "Гибкие настройки",
                description: "Разные стратегии для разных провайдеров"
            )
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
    }
}
struct SpoofDPICheckStep: View {
    @EnvironmentObject var spoofDPIService: SpoofDPIService
    @Binding var isInstalling: Bool
    @Binding var installError: String?
    @State private var refreshToken = UUID()
    
    var isAvailable: Bool {
        spoofDPIService.isSpoofDPIAvailable()
    }
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(isAvailable ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(isAvailable ? .green : .orange)
            }
            
            VStack(spacing: 8) {
                Text(isAvailable ? "SpoofDPI найден" : "SpoofDPI не установлен")
                    .font(.headline)
                
                Text(isAvailable 
                    ? "Всё готово для работы"
                    : "Необходимо установить SpoofDPI для работы приложения")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if !isAvailable {
                VStack(spacing: 12) {
                    Button(action: openInstallInstructions) {
                        Label("Инструкция по установке", systemImage: "book")
                    }
                    .buttonStyle(.bordered)
                    
                    Text("или выполните в терминале:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("go install github.com/xvzc/SpoofDPI/cmd/spoofdpi@latest")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                    
                    Button("Проверить снова") {
                        refreshToken = UUID()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            
            if let error = installError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .id(refreshToken)
    }
    
    private func openInstallInstructions() {
        if let url = URL(string: "https://github.com/xvzc/SpoofDPI#installation") {
            NSWorkspace.shared.open(url)
        }
    }
}
struct PermissionsStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Разрешения")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                PermissionRow(
                    icon: "network",
                    title: "Настройка сети",
                    description: "Для автоматической настройки системного прокси может потребоваться пароль администратора",
                    status: .required
                )
                
                PermissionRow(
                    icon: "arrow.clockwise",
                    title: "Автозапуск",
                    description: "Опционально: запуск приложения при входе в систему",
                    status: .optional
                )
            }
            .padding()
            
            Text("WeDPI не требует полного доступа к диску или других опасных разрешений")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    
    enum PermissionStatus {
        case required
        case optional
        case granted
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    var statusText: String {
        switch status {
        case .required: return "Необходимо"
        case .optional: return "Опционально"
        case .granted: return "Разрешено"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .required: return .orange
        case .optional: return .blue
        case .granted: return .green
        }
    }
}
struct CompletionStep: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("Всё готово!")
                    .font(.headline)
                
                Text("WeDPI настроен и готов к работе")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Нажмите на иконку в menubar")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Нажмите «Подключить»")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "3.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Готово! Наслаждайтесь свободным интернетом")
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .padding()
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
        .environmentObject(AppState())
        .environmentObject(SpoofDPIService())
}

