import Foundation

enum SpoofDPIArguments {
    static let listenAddr = "127.0.0.1"
    
    // SpoofDPI 1.2.0+
    static let httpsFakeCount = "7"
    static let httpsSplitMode = "chunk"
    static let httpsChunkSize = "5"

    static func arguments(port: Int) -> [String] {
        [
            // SpoofDPI 1.2.0+: listen address must include port (host:port)
            "--listen-addr", "\(listenAddr):\(port)",
            "--https-disorder",
            "--https-fake-count", httpsFakeCount,
            "--https-split-mode", httpsSplitMode,
            "--https-chunk-size", httpsChunkSize,
            "--system-proxy"
        ]
    }

    static func programArguments(spoofDPIPath: String, port: Int) -> [String] {
        [spoofDPIPath] + arguments(port: port)
    }
}


