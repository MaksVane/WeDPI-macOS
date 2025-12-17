import Foundation
import SystemConfiguration

class ProxyService {
    private let proxyHost = "127.0.0.1"
    private var savedBypassDomains: [String]?
    private var savedBypassService: String?
    
    static let discordBypassDomains: [String] = [
        "discord.com",
        ".discord.com",
        "ptb.discord.com",
        ".ptb.discord.com",
        "static.discord.com",
        ".static.discord.com",
        "discord.new",
        ".discord.new",
        "discordapp.com",
        ".discordapp.com",
        "cdn.discordapp.com",
        ".cdn.discordapp.com",
        "discord.gg",
        ".discord.gg",
        "dis.gd",
        ".dis.gd",
        "discordapp.net",
        ".discordapp.net",
        "media.discordapp.net",
        ".media.discordapp.net",
        "images-ext-1.discordapp.net",
        ".images-ext-1.discordapp.net",
        "images-ext-2.discordapp.net",
        ".images-ext-2.discordapp.net",
        "discord.media",
        ".discord.media",
        "discordcdn.com",
        ".discordcdn.com",
        "gateway.discord.gg",
        ".gateway.discord.gg"
    ]
    
    private func getActiveNetworkService() -> String {
        let services = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        
        for service in services {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            task.arguments = ["-getinfo", service]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8),
                   output.contains("IP address:") && !output.contains("IP address: none") {
                    print("Найден активный интерфейс: \(service)")
                    return service
                }
            } catch {
                continue
            }
        }
        
        print("Активный интерфейс не найден, используем Wi-Fi")
        return "Wi-Fi"
    }
    
    func enableProxy(port: Int) throws {
        let service = getActiveNetworkService()
        print("Настройка прокси для: \(service) на порту \(port)")
        
        try runNetworkSetup(["-setwebproxy", service, proxyHost, String(port)])
        try runNetworkSetup(["-setwebproxystate", service, "on"])
        
        try runNetworkSetup(["-setsecurewebproxy", service, proxyHost, String(port)])
        try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
        
        print("Прокси включен: \(proxyHost):\(port)")
    }
    
    func disableProxy() throws {
        let service = getActiveNetworkService()
        print("Отключение прокси для: \(service)")
        
        try? runNetworkSetup(["-setwebproxystate", service, "off"])
        try? runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        
        print("Прокси отключен")
    }
    
    func applyBypassDomains(_ domains: [String]) throws {
        let service = getActiveNetworkService()
        if savedBypassDomains == nil || savedBypassService != service {
            savedBypassDomains = try getProxyBypassDomains(service: service)
            savedBypassService = service
        }
        
        let base = savedBypassDomains ?? []
        var merged: [String] = base
        for d in domains where !merged.contains(d) {
            merged.append(d)
        }
        
        try runNetworkSetup(["-setproxybypassdomains", service] + merged)
        print("Proxy bypass domains обновлены для \(service): \(merged.joined(separator: ", "))")
    }
    
    func restoreBypassDomainsIfNeeded() {
        guard let service = savedBypassService, let domains = savedBypassDomains else { return }
        do {
            try runNetworkSetup(["-setproxybypassdomains", service] + domains)
            print("Proxy bypass domains восстановлены для \(service)")
        } catch {
            print("Не удалось восстановить bypass domains: \(error)")
        }
        
        savedBypassDomains = nil
        savedBypassService = nil
    }
    
    private func getProxyBypassDomains(service: String) throws -> [String] {
        let output = try runNetworkSetupCaptureStdout(["-getproxybypassdomains", service])
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func runNetworkSetup(_ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = arguments
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: errData, encoding: .utf8) ?? "Unknown error"
            if error.localizedCaseInsensitiveContains("root") || error.localizedCaseInsensitiveContains("privilege") || error.localizedCaseInsensitiveContains("not permitted") {
                try runNetworkSetupWithPrivileges(arguments)
                return
            }
            
            print("networksetup ошибка: \(error)")
            throw ProxyError.commandFailed(error)
        }
    }
    
    private func runNetworkSetupCaptureStdout(_ arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = arguments
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        
        try task.run()
        task.waitUntilExit()
        
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        
        if task.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw ProxyError.commandFailed(err)
        }
        
        return out
    }
    
    private func runNetworkSetupWithPrivileges(_ arguments: [String]) throws {
        let escaped = arguments
            .map { $0.replacingOccurrences(of: "\"", with: "\\\"") }
            .joined(separator: " ")
        
        let script = """
        do shell script "/usr/sbin/networksetup \(escaped)" with administrator privileges
        """
        
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        _ = appleScript?.executeAndReturnError(&error)
        if let error {
            throw ProxyError.commandFailed("\(error)")
        }
    }
}

enum ProxyError: LocalizedError {
    case commandFailed(String)
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Ошибка настройки прокси: \(message)"
        case .permissionDenied:
            return "Недостаточно прав для изменения настроек сети"
        }
    }
}
