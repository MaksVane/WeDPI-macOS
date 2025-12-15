import Foundation
import AppKit

class SpoofDPIService: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var logs: [String] = []
    
    private var process: Process?
    private var outputPipe: Pipe?
    
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
    
    func start(port: Int = 8080) throws {
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
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self?.logs.append(trimmed)
                        print("SpoofDPI: \(trimmed)")
                    }
                    if (self?.logs.count ?? 0) > 500 {
                        self?.logs.removeFirst(100)
                    }
                }
            }
        }
        
        try process?.run()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        if process?.isRunning == true {
            DispatchQueue.main.async {
                self.isRunning = true
                self.addLog("SpoofDPI запущен на порту \(port)")
            }
            print("SpoofDPI успешно запущен, PID: \(process?.processIdentifier ?? 0)")
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
