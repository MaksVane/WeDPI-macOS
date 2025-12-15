import Foundation

enum SpoofDPIArguments {
    static let listenAddr = "127.0.0.1"
    static let dnsAddr = "8.8.8.8"

    static let windowSize = "1"
    static let fakeHttpsPackets = "1"
    static let timeoutMs = "5000"

    static func arguments(port: Int) -> [String] {
        [
            "--listen-addr", listenAddr,
            "--listen-port", String(port),
            "--dns-addr", dnsAddr,
            "--enable-doh",
            "--window-size", windowSize,
            "--fake-https-packets", fakeHttpsPackets,
            "--timeout", timeoutMs,
            "--system-proxy"
        ]
    }

    static func programArguments(spoofDPIPath: String, port: Int) -> [String] {
        [spoofDPIPath] + arguments(port: port)
    }
}


