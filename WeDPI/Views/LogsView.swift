import SwiftUI

struct LogsView: View {
    @EnvironmentObject var spoofDPIService: SpoofDPIService
    @State private var autoScroll = true
    @State private var searchText = ""
    
    var filteredLogs: [String] {
        if searchText.isEmpty {
            return spoofDPIService.logs
        }
        return spoofDPIService.logs.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Поиск в логах...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                Spacer()
                
                Toggle(isOn: $autoScroll) {
                    Label("Автопрокрутка", systemImage: "arrow.down.to.line")
                        .labelStyle(.iconOnly)
                }
                .toggleStyle(.button)
                .help("Автопрокрутка к новым сообщениям")
                
                Button(action: {
                    spoofDPIService.clearLogs()
                }) {
                    Label("Очистить", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Очистить логи")
                
                Button(action: copyLogs) {
                    Label("Копировать", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Копировать логи в буфер обмена")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if filteredLogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "Логи пусты" : "Ничего не найдено")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if !searchText.isEmpty {
                        Text("Попробуйте другой поисковый запрос")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, log in
                                LogEntryView(log: log, index: index)
                                    .id(index)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: filteredLogs.count) { newCount in
                        if autoScroll && newCount > 0 {
                            withAnimation {
                                proxy.scrollTo(newCount - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }
    
    private func copyLogs() {
        let logsText = spoofDPIService.logs.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logsText, forType: .string)
    }
}

struct LogEntryView: View {
    let log: String
    let index: Int
    
    var logType: LogType {
        if log.contains("ERROR") || log.contains("error") || log.contains("Ошибка") {
            return .error
        } else if log.contains("WARN") || log.contains("warning") {
            return .warning
        } else if log.contains("запущен") || log.contains("started") || log.contains("connected") {
            return .success
        }
        return .info
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
            
            Circle()
                .fill(logType.color)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            
            Text(log)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(logType.textColor)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.5)
        )
    }
}

enum LogType {
    case info
    case warning
    case error
    case success
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
    
    var textColor: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        default: return .primary
        }
    }
}

#Preview {
    LogsView()
        .environmentObject(SpoofDPIService())
}

