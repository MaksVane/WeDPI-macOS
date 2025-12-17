import Foundation
import AppKit

class SpoofDPIService: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var logs: [String] = []
    
    private var process: Process?
    private var outputPipe: Pipe?
    private let proxyService = ProxyService()
    private var bypassDomainsApplied = false
    
    private var partialLineBuffer: String = ""
    private var lastLogLine: String?
    private var lastLogLineCount: Int = 0
    
    func setBypassDomains(_ domains: [String]) {
        guard isRunning else { return }
        
        let shouldApply = !domains.isEmpty
        if shouldApply == bypassDomainsApplied && !shouldApply {
            return
        }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            if shouldApply {
                do {
                    try self.proxyService.applyBypassDomains(domains)
                    self.bypassDomainsApplied = true
                    DispatchQueue.main.async {
                        self.addLog("Обход (DIRECT) применён")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.addLog("WARN: не удалось применить обход: \(error.localizedDescription)")
                    }
                }
            } else {
                self.proxyService.restoreBypassDomainsIfNeeded()
                self.bypassDomainsApplied = false
                DispatchQueue.main.async {
                    self.addLog("Обход (DIRECT) отключён")
                }
            }
        }
    }
    
    func setDiscordBypassEnabled(_ enabled: Bool) {
        setBypassDomains(enabled ? ProxyService.discordBypassDomains : [])
    }
    
    var spoofDPIPath: String {
        let possiblePaths = [
            "/opt/homebrew/bin/spoofdpi",
            "/usr/local/bin/spoofdpi",
            "\(NSHomeDirectory())/go/bin/spoofdpi",
            "\(NSHomeDirectory())/.local/bin/spoofdpi"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        if let bundlePath = Bundle.main.path(forResource: "spoofdpi", ofType: nil) {
            return bundlePath
        }
        
        return "/opt/homebrew/bin/spoofdpi"
    }
    
    func isSpoofDPIAvailable() -> Bool {
        return FileManager.default.fileExists(atPath: spoofDPIPath)
    }
    
    func isBPFAccessible() -> Bool {
        let bpf0 = "/dev/bpf0"
        return FileManager.default.isReadableFile(atPath: bpf0) && 
               FileManager.default.isWritableFile(atPath: bpf0)
    }
    
    func setupBPFPermissions(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            do shell script "chmod 666 /dev/bpf*" with administrator privileges
            """

            var error: NSDictionary?
            let success: Bool

            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if error == nil {
                    success = true
                } else {
                    print("BPF setup error: \(error ?? [:])")
                    success = false
                }
            } else {
                success = false
            }

            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func start(port: Int = 8080, bypassDomains: [String] = []) throws {
        guard !isRunning else {
            print("SpoofDPI уже запущен")
            return
        }
        
        let path = spoofDPIPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw SpoofDPIError.binaryNotFound
        }
        
        process = Process()
        process?.executableURL = URL(fileURLWithPath: path)
        
        let arguments = SpoofDPIArguments.arguments(port: port)
        
        process?.arguments = arguments
        
        DispatchQueue.main.async {
            self.addLog("Запуск: spoofdpi \(arguments.joined(separator: " "))")
        }
        
        outputPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = outputPipe
        
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            DispatchQueue.main.async {
                self.ingestLogChunk(chunk)
            }
        }
        
        try process?.run()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        if process?.isRunning == true {
            do {
                try proxyService.enableProxy(port: port)
                DispatchQueue.main.async {
                    self.addLog("Системный прокси включён: 127.0.0.1:\(port)")
                }
            } catch {
                self.process?.terminate()
                self.process?.waitUntilExit()
                self.process = nil
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.outputPipe = nil
                
                DispatchQueue.main.async {
                    self.addLog("ERROR: не удалось включить системный прокси: \(error.localizedDescription)")
                }
                throw error
            }
            
            DispatchQueue.main.async {
                self.isRunning = true
                self.addLog("SpoofDPI запущен на порту \(port)")
            }
            print("SpoofDPI успешно запущен, PID: \(process?.processIdentifier ?? 0)")
            
            if !bypassDomains.isEmpty {
                do {
                    try proxyService.applyBypassDomains(bypassDomains)
                    bypassDomainsApplied = true
                    DispatchQueue.main.async {
                        self.addLog("Обход (DIRECT) применён")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.addLog("WARN: не удалось применить обход: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            throw SpoofDPIError.failedToStart("Процесс завершился сразу после запуска")
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        DispatchQueue.main.async {
            self.addLog("Остановка SpoofDPI...")
        }
        
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        
        if process?.isRunning == true {
            process?.terminate()
            process?.waitUntilExit()
        }
        
        process = nil
        outputPipe = nil
        partialLineBuffer = ""
        lastLogLine = nil
        lastLogLineCount = 0
        
        if bypassDomainsApplied {
            proxyService.restoreBypassDomainsIfNeeded()
            bypassDomainsApplied = false
        }

        do {
            try proxyService.disableProxy()
            DispatchQueue.main.async {
                self.addLog("Системный прокси выключен")
            }
        } catch {
            DispatchQueue.main.async {
                self.addLog("WARN: не удалось выключить системный прокси: \(error.localizedDescription)")
            }
        }
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.addLog("SpoofDPI остановлен")
        }
        
        print("SpoofDPI остановлен")
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    private func ingestLogChunk(_ chunk: String) {
        let sanitizedChunk = stripANSIEscapes(from: chunk)
        
        partialLineBuffer += sanitizedChunk
        partialLineBuffer = partialLineBuffer.replacingOccurrences(of: "\r\n", with: "\n")
        partialLineBuffer = partialLineBuffer.replacingOccurrences(of: "\r", with: "\n")
        
        let parts = partialLineBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return }
        
        let endsWithNewline = partialLineBuffer.hasSuffix("\n")
        
        let linesToEmit: ArraySlice<Substring>
        if endsWithNewline {
            linesToEmit = parts[0..<parts.count]
            partialLineBuffer = ""
        } else if parts.count >= 2 {
            linesToEmit = parts[0..<(parts.count - 1)]
            partialLineBuffer = String(parts.last ?? "")
        } else {
            return
        }
        
        for raw in linesToEmit {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            appendLogLineWithDedup(line)
        }
        
        if logs.count > 800 {
            logs.removeFirst(logs.count - 600)
        }
    }
    
    private func appendLogLineWithDedup(_ line: String) {
        if let last = lastLogLine, last == line, !logs.isEmpty {
            lastLogLineCount += 1
            logs[logs.count - 1] = "\(line) (×\(lastLogLineCount))"
            return
        }
        
        lastLogLine = line
        lastLogLineCount = 1
        logs.append(line)
        
        if logs.count > 500 {
            logs.removeFirst(100)
        }
    }
    
    private func stripANSIEscapes(from s: String) -> String {
        let pattern = #"\u{001B}\[[0-9;]*[A-Za-z]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
    }
}

enum SpoofDPIError: LocalizedError {
    case binaryNotFound
    case failedToStart(String)
    
    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "SpoofDPI не найден. Установите: brew install spoofdpi"
        case .failedToStart(let reason):
            return "Не удалось запустить: \(reason)"
        }
    }
}
