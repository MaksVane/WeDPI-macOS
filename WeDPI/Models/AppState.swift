import Foundation
import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Отключено"
    @Published var showError: Bool = false

    @AppStorage("updatesRepo") var updatesRepo: String = "MaksVane/WeDPI-macOS"
    @Published var isCheckingForUpdates: Bool = false
    @Published var lastUpdateCheckError: String?
    @Published var availableUpdate: AvailableUpdate?
    
    @AppStorage("autoConnect") var autoConnect: Bool = false
    @AppStorage("proxyPort") var proxyPort: Int = 8080
    @AppStorage("bypassDiscord") var bypassDiscord: Bool = false
    @AppStorage("customBypassEnabled") var customBypassEnabled: Bool = false
    @AppStorage("customBypassDomains") var customBypassDomainsRaw: String = ""
    
    @Published var connectionTime: TimeInterval = 0
    
    private var timer: Timer?
    private var startTime: Date?
    
    func startTracking() {
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            DispatchQueue.main.async {
                self.connectionTime = Date().timeIntervalSince(start)
            }
        }
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
        startTime = nil
        connectionTime = 0
    }
    
    var formattedConnectionTime: String {
        let hours = Int(connectionTime) / 3600
        let minutes = Int(connectionTime) / 60 % 60
        let seconds = Int(connectionTime) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    var customBypassDomains: [String] {
        let raw = customBypassDomainsRaw
        let separators = CharacterSet(charactersIn: ",\n\t ")
        var seen = Set<String>()
        var result: [String] = []
        for part in raw.components(separatedBy: separators) {
            let s = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            if !seen.contains(s) {
                seen.insert(s)
                result.append(s)
            }
        }
        return result
    }
    
    var effectiveBypassDomains: [String] {
        var domains: [String] = []
        if bypassDiscord {
            domains.append(contentsOf: ProxyService.discordBypassDomains)
        }
        if customBypassEnabled {
            domains.append(contentsOf: customBypassDomains)
        }
        var seen = Set<String>()
        var result: [String] = []
        for d in domains where !seen.contains(d) {
            seen.insert(d)
            result.append(d)
        }
        return result
    }

    @MainActor
    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        lastUpdateCheckError = nil
        availableUpdate = nil

        let repo = updatesRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repo.contains("/"), repo.split(separator: "/").count == 2 else {
            lastUpdateCheckError = "Неверный репозиторий обновлений. Укажите формат owner/repo."
            return
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            lastUpdateCheckError = "Не удалось сформировать URL для проверки обновлений."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WeDPI-macOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                lastUpdateCheckError = "GitHub API вернул ошибку: \(msg)"
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
            let latestVersion = AppState.normalizeVersionString(release.tag_name)

            let comparison = AppState.compareSemver(latestVersion, currentVersion)
            let isNewer: Bool
            if let comparison {
                isNewer = comparison == .orderedDescending
            } else {
                isNewer = latestVersion != AppState.normalizeVersionString(currentVersion)
            }

            guard isNewer else { return }

            let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
            let downloadURL = dmgAsset.flatMap { URL(string: $0.browser_download_url) }
            let pageURL = URL(string: release.html_url)

            availableUpdate = AvailableUpdate(
                latestVersion: latestVersion,
                releaseNotes: release.body?.trimmingCharacters(in: .whitespacesAndNewlines),
                releasePageURL: pageURL,
                dmgDownloadURL: downloadURL
            )
        } catch {
            lastUpdateCheckError = "Не удалось проверить обновления: \(error.localizedDescription)"
        }
    }
}
extension AppState {
    struct AvailableUpdate: Identifiable {
        let id = UUID()
        let latestVersion: String
        let releaseNotes: String?
        let releasePageURL: URL?
        let dmgDownloadURL: URL?
    }

    struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    static func normalizeVersionString(_ version: String) -> String {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.lowercased().hasPrefix("v") {
            v.removeFirst()
        }
        return v
    }

    static func compareSemver(_ a: String, _ b: String) -> ComparisonResult? {
        func parse(_ s: String) -> [Int]? {
            let normalized = normalizeVersionString(s)
            let parts = normalized.split(separator: ".")
            guard parts.count >= 2 else { return nil }
            let ints = parts.compactMap { Int($0.filter(\.isNumber)) }
            guard ints.count == parts.count else { return nil }
            return ints
        }

        guard var pa = parse(a), var pb = parse(b) else { return nil }
        let n = max(pa.count, pb.count)
        if pa.count < n { pa.append(contentsOf: Array(repeating: 0, count: n - pa.count)) }
        if pb.count < n { pb.append(contentsOf: Array(repeating: 0, count: n - pb.count)) }

        for i in 0..<n {
            if pa[i] < pb[i] { return .orderedAscending }
            if pa[i] > pb[i] { return .orderedDescending }
        }
        return .orderedSame
    }
}
