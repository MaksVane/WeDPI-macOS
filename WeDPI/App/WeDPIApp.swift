import SwiftUI
import AppKit

@main
struct WeDPIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView(isPresented: .constant(true), showHeader: false)
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.spoofDPIService)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let appState = AppState()
    let spoofDPIService = SpoofDPIService()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
        
        if appState.autoConnect && spoofDPIService.isSpoofDPIAvailable() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.autoConnect()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        spoofDPIService.stop()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            updateStatusIcon(isActive: false)
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 280)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState)
                .environmentObject(spoofDPIService)
        )
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func updateStatusIcon(isActive: Bool) {
        if let button = statusItem.button {
            let iconName = isActive ? "checkmark.shield.fill" : "shield"
            let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "WeDPI")
            image?.isTemplate = true
            button.image = image
        }
    }
    
    private func autoConnect() {
        do {
            try spoofDPIService.start(port: appState.proxyPort, bypassDomains: appState.effectiveBypassDomains)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.appState.isConnected = true
                self.appState.startTracking()
                self.updateStatusIcon(isActive: true)
            }
        } catch {
            print("Автоподключение не удалось: \(error)")
        }
    }
}
