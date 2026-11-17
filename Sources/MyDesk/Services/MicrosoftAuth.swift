import Foundation
import AuthenticationServices
import Security
import CryptoKit
import AppKit

struct TokenRecord: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var identity: String
}
enum KeychainStore {
    static let service = "cz.mydesk.microsoft"
    static func read() throws -> TokenRecord? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "primary",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw DeskError("Klíčenka není dostupná (\(status)).") }
        return try JSONDecoder().decode(TokenRecord.self, from: data)
    }
    static func write(_ record: TokenRecord) throws {
        let data = try JSONEncoder().encode(record)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "primary"]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query; attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw DeskError("Token se nepodařilo bezpečně uložit do Klíčenky (\(status)).") }
    }
    static func delete() throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "primary"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DeskError("Odpojení z Klíčenky selhalo (\(status)).") }
    }
}
@MainActor final class MicrosoftAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var connected = false
    @Published var busy = false
    @Published var error: String?
    private var session: ASWebAuthenticationSession?
    private var record: TokenRecord?
    private var refreshTask: Task<String, Error>?
    private var generation = 0
    static let redirect = "mydesk://oauth"
    override init() {
        super.init()
        do { record = try KeychainStore.read(); connected = record != nil }
        catch { self.error = error.localizedDescription }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw DeskError("Nelze vytvořit bezpečný přihlašovací požadavek.") }
        return Self.base64(Data(bytes))
    }
    static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private func endpoint(_ settings: MicrosoftSettings, suffix: String) throws -> URL {
        guard UUID(uuidString: settings.clientID) != nil else { throw DeskError("V Nastavení → Microsoft zadej platné Application (client) ID.") }
        let tenant = settings.tenant
        guard !tenant.isEmpty, tenant.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else { throw DeskError("Neplatný tenant Microsoft Entra.") }
        return URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/\(suffix)")!
    }
    func signIn(_ settings: MicrosoftSettings) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false; session = nil }
        do {
            let epoch = generation
            let verifier = try random(), state = try random()
            let challenge = Self.base64(Data(SHA256.hash(data: Data(verifier.utf8))))
            var components = URLComponents(url: try endpoint(settings, suffix: "authorize"), resolvingAgainstBaseURL: false)!
            components.queryItems = ["client_id": settings.clientID, "response_type": "code",
                "redirect_uri": Self.redirect, "response_mode": "query", "scope": settings.scopes.joined(separator: " "),
                "state": state, "code_challenge": challenge, "code_challenge_method": "S256", "prompt": "select_account"]
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let authSession = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "mydesk") { url, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: DeskError("Přihlášení nevrátilo odpověď.")) }
                }
                authSession.presentationContextProvider = self
                authSession.prefersEphemeralWebBrowserSession = true
                session = authSession
                if !authSession.start() { continuation.resume(throwing: DeskError("Nelze otevřít přihlašovací okno.")) }
            }
            let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
            guard callback.scheme == "mydesk", callback.host == "oauth", value("state") == state else { throw DeskError("Ověření odpovědi přihlášení selhalo.") }
            guard let code = value("code") else { throw DeskError("Microsoft přihlášení odmítl. Ověř souhlas správce a registraci aplikace.") }
            let result = try await exchange(settings, fields: ["grant_type": "authorization_code", "code": code,
                "code_verifier": verifier, "redirect_uri": Self.redirect])
            guard epoch == generation else { throw CancellationError() }
            try KeychainStore.write(result); record = result; connected = true
        } catch { self.error = error.localizedDescription }
    }
    private struct TokenResponse: Decodable {
        let access_token: String; let refresh_token: String?; let expires_in: Int
    }
    private func exchange(_ settings: MicrosoftSettings, fields: [String: String]) async throws -> TokenRecord {
        var fields = fields
        fields["client_id"] = settings.clientID; fields["scope"] = settings.scopes.joined(separator: " ")
        var body = URLComponents(); body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: try endpoint(settings, suffix: "token"))
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await Network.shared.data(request)
        guard response.statusCode == 200 else {
            if response.statusCode == 400 || response.statusCode == 401 { throw DeskError("Microsoft vyžaduje nové přihlášení. Ověř registraci, oprávnění a firemní zásady.") }
            throw DeskError("Přihlášení není dostupné (HTTP \(response.statusCode)).")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TokenRecord(accessToken: token.access_token, refreshToken: token.refresh_token ?? (fields["grant_type"] == "refresh_token" ? record?.refreshToken : nil),
                           expiresAt: Date().addingTimeInterval(Double(token.expires_in)), identity: settings.identityKey)
    }
    func accessToken(_ settings: MicrosoftSettings, force: Bool = false) async throws -> String {
        guard let record, record.identity == settings.identityKey else { throw DeskError("Připoj Microsoft účet v nastavení. Po změně oprávnění je nutné nové přihlášení.") }
        if !force, record.expiresAt.timeIntervalSinceNow > 120 { return record.accessToken }
        if let refreshTask { return try await refreshTask.value }
        guard let refresh = record.refreshToken else { throw DeskError("Přihlas se znovu k Microsoft účtu.") }
        let epoch = generation
        let task = Task { @MainActor in
            let updated = try await self.exchange(settings, fields: ["grant_type": "refresh_token", "refresh_token": refresh])
            guard epoch == self.generation else { throw CancellationError() }
            try KeychainStore.write(updated); self.record = updated
            return updated.accessToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
    func disconnect() {
        session?.cancel(); generation += 1; refreshTask?.cancel(); refreshTask = nil
        do { try KeychainStore.delete(); record = nil; connected = false; error = nil }
        catch { self.error = error.localizedDescription }
    }
}
