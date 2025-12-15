import Foundation

class LaunchAgentService {
    static let shared = LaunchAgentService()
    
    private let launchAgentLabel = "com.wedpi.spoofdpi"
    private let launchAgentsPath: String
    private let plistPath: String
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        launchAgentsPath = "\(homeDir)/Library/LaunchAgents"
        plistPath = "\(launchAgentsPath)/\(launchAgentLabel).plist"
    }
    
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }
    
    func install(spoofDPIPath: String, port: Int = 8080) throws {
        if !FileManager.default.fileExists(atPath: launchAgentsPath) {
            try FileManager.default.createDirectory(
                atPath: launchAgentsPath,
                withIntermediateDirectories: true
            )
        }
        
        let programArguments = SpoofDPIArguments.programArguments(spoofDPIPath: spoofDPIPath, port: port)
        
        let plistContent = createPlist(programArguments: programArguments)
        
        try plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
        
        try loadAgent()
    }
    
    func uninstall() throws {
        if isInstalled {
            try? unloadAgent()
        }
        
        if FileManager.default.fileExists(atPath: plistPath) {
            try FileManager.default.removeItem(atPath: plistPath)
        }
    }
    
    private func loadAgent() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", plistPath]
        try task.run()
        task.waitUntilExit()
    }
    
    private func unloadAgent() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", plistPath]
        try task.run()
        task.waitUntilExit()
    }
    
    private func createPlist(programArguments: [String]) -> String {
        let argsXML = programArguments.map { "        <string>\($0)</string>" }.joined(separator: "\n")
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
        \(argsXML)
            </array>
            <key>RunAtLoad</key>
            <false/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
    }
}
