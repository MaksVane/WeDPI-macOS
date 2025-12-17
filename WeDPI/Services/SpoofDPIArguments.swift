import Foundation

enum SpoofDPIArguments {
    static let listenAddr = "127.0.0.1"
    
    static let httpsFakeCount = "7"
    static let httpsSplitMode = "chunk"
    static let httpsChunkSize = "5"

    static func arguments(port: Int) -> [String] {
        [
            "--listen-addr", "\(listenAddr):\(port)",
            "--https-disorder",
            "--https-fake-count", httpsFakeCount,
            "--https-split-mode", httpsSplitMode,
            "--https-chunk-size", httpsChunkSize
        ]
    }

    static func programArguments(spoofDPIPath: String, port: Int) -> [String] {
        [spoofDPIPath] + arguments(port: port)
    }
}


