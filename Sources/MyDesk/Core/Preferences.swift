import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor final class Preferences: ObservableObject {
    @Published var config: Configuration { didSet { save() } }
    @Published var persistenceError: String?
    private let url: URL
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MY DESK", isDirectory: true)
        url = base.appendingPathComponent("settings-v1.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do { config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url)) }
            catch {
                config = Configuration()
                persistenceError = "Nastavení se nepodařilo načíst. Původní soubor zůstává zachovaný; ukonči aplikaci a obnov jej ze zálohy."
            }
        } else { config = Configuration() }
    }
    func save() {
        // Do not overwrite unreadable user data without an explicit recovery decision.
        guard persistenceError == nil else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(config)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { persistenceError = "Nastavení se nepodařilo uložit: \(error.localizedDescription)" }
    }
    func chooseApp() {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            config.apps.append(.init(name: url.deletingPathExtension().lastPathComponent,
                                     bundleID: Bundle(url: url)?.bundleIdentifier ?? "", path: url.path))
        }
    }
    func chooseFile(directory: Bool = false) -> String? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
    func moveApp(_ id: UUID, by delta: Int) {
        guard let i = config.apps.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard config.apps.indices.contains(j) else { return }
        config.apps.swapAt(i, j)
    }
}

enum SafeURL {
    static func web(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func secure(_ raw: String) -> URL? {
        guard let u = web(raw), u.scheme?.lowercased() == "https" else { return nil }; return u
    }
}
@MainActor enum Launcher {
    static func appURL(_ item: LaunchItem) -> URL? {
        if !item.path.isEmpty, FileManager.default.fileExists(atPath: item.path) { return URL(fileURLWithPath: item.path) }
        return item.bundleID.isEmpty ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID)
    }
    static func launch(_ item: LaunchItem) throws {
        guard let url = appURL(item) else { throw DeskError("\(item.name) není nastavená nebo nainstalovaná. Vyber ji v Nastavení → Aplikace.") }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error { Task { @MainActor in
                let alert = NSAlert(); alert.messageText = "Aplikaci nelze otevřít"; alert.informativeText = error.localizedDescription; alert.runModal()
            } }
        }
    }
    static func open(_ target: String) throws {
        let url: URL
        if target.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: target) else { throw DeskError("Vybraný soubor nebo složka neexistuje.") }
            url = URL(fileURLWithPath: target)
        } else if let value = SafeURL.web(target) { url = value }
        else { throw DeskError("Doplň platnou adresu http(s) nebo vyber existující místní soubor v nastavení.") }
        guard NSWorkspace.shared.open(url) else { throw DeskError("Pro tento soubor nebo odkaz není dostupná aplikace.") }
    }
}
