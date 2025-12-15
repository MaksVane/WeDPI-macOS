// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WeDPI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WeDPI", targets: ["WeDPI"])
    ],
    targets: [
        .executableTarget(
            name: "WeDPI",
            path: ".",
            exclude: [
                "Package.swift",
                "Info.plist"
            ],
            sources: [
                "App/WeDPIApp.swift",
                "Models/AppState.swift",
                "Services/SpoofDPIArguments.swift",
                "Services/SpoofDPIService.swift",
                "Services/ProxyService.swift",
                "Services/LaunchAgentService.swift",
                "Views/MenuBarView.swift",
                "Views/SettingsView.swift",
                "Views/LogsView.swift",
                "Views/OnboardingView.swift"
            ],
            resources: [
                .copy("Resources/lists")
            ]
        )
    ]
)
