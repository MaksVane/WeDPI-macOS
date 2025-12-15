import Foundation
import SystemConfiguration

class ProxyService {
    private let proxyHost = "127.0.0.1"
    
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
            print("networksetup ошибка: \(error)")
            throw ProxyError.commandFailed(error)
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
