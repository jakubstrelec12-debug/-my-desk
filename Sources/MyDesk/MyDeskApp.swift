import SwiftUI
import AppKit

@main @MainActor struct MyDeskApp: App {
    @NSApplicationDelegateAdaptor(DeskAppDelegate.self) var delegate
    @StateObject private var preferences: Preferences
    @StateObject private var auth: MicrosoftAuth
    @StateObject private var model: DeskModel
    init() {
        let prefs = Preferences(), auth = MicrosoftAuth()
        _preferences = StateObject(wrappedValue: prefs)
        _auth = StateObject(wrappedValue: auth)
        _model = StateObject(wrappedValue: DeskModel(preferences: prefs, auth: auth))
    }
    var body: some Scene {
        WindowGroup("MY DESK", id: "dashboard") {
            Dashboard().environmentObject(preferences).environmentObject(auth).environmentObject(model)
                .preferredColorScheme(preferences.config.appearance == "system" ? nil : preferences.config.appearance == "light" ? .light : .dark)
                .background(WindowAccessor { window in delegate.attach(window, preferences: preferences) })
        }
        .defaultSize(width: 1480, height: 890)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appSettings) {
                Button("Nastavení…") { model.settingsOpen = true; delegate.show() }.keyboardShortcut(",")
            }
            CommandMenu("Dashboard") {
                Button("Obnovit data") { Task { await model.refreshAll() } }.keyboardShortcut("r")
                Button("Skrýt do menu baru") { NSApp.hide(nil) }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Celá obrazovka") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
        MenuBarExtra("MY DESK", systemImage: "cube.transparent") {
            Button("Otevřít MY DESK") { delegate.show() }
            Button("Obnovit data") { delegate.show(); Task { await model.refreshAll() } }
            Button("Nastavení…") { delegate.show(); model.settingsOpen = true }
            Divider()
            Button("Ukončit MY DESK") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
@MainActor final class DeskAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var window: NSWindow?
    weak var preferences: Preferences?
    private var didApplyFullScreen = false
    private var smokeScheduled = false
    func attach(_ window: NSWindow, preferences: Preferences) {
        guard window.identifier?.rawValue != "mydesk-main" else { return }
        self.window = window; self.preferences = preferences
        window.identifier = NSUserInterfaceItemIdentifier("mydesk-main")
        window.delegate = self; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--smoke-test"),
           ProcessInfo.processInfo.arguments.indices.contains(flag + 1), !smokeScheduled {
            smokeScheduled = true
            let output = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[flag + 1], isDirectory: true)
            let args = ProcessInfo.processInfo.arguments
            var requestedSize = NSSize(width: 1480, height: 890)
            if let index = args.firstIndex(of: "--smoke-size"), args.indices.contains(index + 1) {
                let parts = args[index + 1].split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 { requestedSize = NSSize(width: parts[0], height: parts[1]) }
            }
            window.setContentSize(requestedSize)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 18) {
                do {
                    guard Bundle.deskResources.url(forResource: "Mountains", withExtension: "png") != nil,
                          Bundle.deskResources.bundleURL.path.hasPrefix(Bundle.main.bundleURL.path + "/") else {
                        throw DeskError("Smoke test: obrázky nejsou dostupné uvnitř instalačního balíčku.")
                    }
                    guard let view = window.contentView,
                          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                        throw DeskError("Smoke test: nelze zachytit obsah okna.")
                    }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else {
                        throw DeskError("Smoke test: nelze vytvořit PNG.")
                    }
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    try png.write(to: output.appendingPathComponent("dashboard.png"))
                    guard abs(view.bounds.width - requestedSize.width) < 2, view.bounds.height >= 480, view.bounds.height <= requestedSize.height + 32 else {
                        throw DeskError("Smoke test: skutečné okno \(view.bounds.width)x\(view.bounds.height), požadováno \(requestedSize.width)x\(requestedSize.height).")
                    }
                    let report: [String: Any] = ["status": "passed", "requestedWidth": requestedSize.width, "requestedHeight": requestedSize.height, "resourceBundle": Bundle.deskResources.bundleURL.path, "windowWidth": view.bounds.width,
                        "windowHeight": view.bounds.height, "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                        "note": "Packaged native app launched and rendered; authenticated integrations are not tested."]
                    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted])
                        .write(to: output.appendingPathComponent("smoke.json"))
                    NSApp.terminate(nil)
                } catch {
                    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    try? error.localizedDescription.write(to: output.appendingPathComponent("smoke-error.txt"), atomically: true, encoding: .utf8)
                    fputs("Smoke test failed: \(error.localizedDescription)\n", stderr); exit(1)
                }
            }
        }
        if !didApplyFullScreen, preferences.config.fullScreen {
            didApplyFullScreen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { window.toggleFullScreen(nil) }
        }
    }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); window.deminiaturize(nil) }
        else { NSApp.windows.first { $0.identifier?.rawValue == "mydesk-main" }?.makeKeyAndOrderFront(nil) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if preferences?.config.hideOnClose == true { NSApp.hide(nil); return false }
        sender.orderOut(nil); return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { callback(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let window = nsView.window { callback(window) } }
    }
}
