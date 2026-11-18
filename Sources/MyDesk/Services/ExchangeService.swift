import Foundation
import FoundationXML
import Security

struct ExchangeCredential: Codable {
    let identity: String
    let password: String
}
enum ExchangeKeychain {
    private static let service = "cz.mydesk.exchange"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "primary"]
    }
    static func read() throws -> ExchangeCredential? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw DeskError("Klíčenka Exchange není dostupná (\(status)).") }
        return try JSONDecoder().decode(ExchangeCredential.self, from: data)
    }
    static func write(_ credential: ExchangeCredential) throws {
        let data = try JSONEncoder().encode(credential)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw DeskError("Heslo Exchange se nepodařilo uložit do Klíčenky (\(status)).") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DeskError("Odpojení Exchange selhalo (\(status)).") }
    }
}

/// Credentials are scoped to this session, this HTTPS origin and one auth method.
/// Redirects are rejected, so a server cannot forward credentials to another URL.
final class ExchangeTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let endpoint: URL
    let username: String
    let password: String
    let authentication: String
    init(endpoint: URL, username: String, password: String, authentication: String) {
        self.endpoint = endpoint; self.username = username; self.password = password; self.authentication = authentication
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil); return
        }
        let expected = authentication == "ntlm" ? NSURLAuthenticationMethodNTLM : NSURLAuthenticationMethodHTTPBasic
        guard space.host.lowercased() == endpoint.host?.lowercased(),
              space.port == (endpoint.port ?? 443), space.protocol?.lowercased() == "https",
              space.authenticationMethod == expected, challenge.previousFailureCount == 0 else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(user: username, password: password, persistence: .none))
    }
}

final class ExchangeService {
    let settings: ExchangeSettings
    private let session: URLSession
    private let transport: ExchangeTransport
    private var blockedUntil = Date.distantPast
    private var authenticationFailed = false
    init(settings: ExchangeSettings, password: String, configuration: URLSessionConfiguration = .ephemeral) throws {
        let endpoint = try settings.validatedURL()
        guard !password.isEmpty else { throw DeskError("Zadej heslo k firemnímu Exchange.") }
        self.settings = settings
        transport = ExchangeTransport(endpoint: endpoint, username: settings.username, password: password, authentication: settings.authentication)
        configuration.timeoutIntervalForRequest = 25; configuration.timeoutIntervalForResource = 40
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: transport, delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    static func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    static func envelope(_ operation: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages" xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
        <s:Header><t:RequestServerVersion Version="Exchange2013"/></s:Header><s:Body>\(operation)</s:Body></s:Envelope>
        """.utf8)
    }
    func request(_ operation: String) async throws -> EWSResponse {
        guard !authenticationFailed else { throw DeskError("Exchange odmítl přihlášení. Zkontroluj jméno a heslo v Nastavení → Exchange a znovu se připoj.") }
        guard blockedUntil <= Date() else { throw DeskError("Exchange omezuje požadavky. Zkus obnovit data za několik minut.") }
        var request = URLRequest(url: transport.endpoint)
        request.httpMethod = "POST"; request.httpBody = Self.envelope(operation)
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/xml", forHTTPHeaderField: "Accept")
        let action = operation.dropFirst(3).prefix { $0.isLetter }
        request.setValue("\"http://schemas.microsoft.com/exchange/services/2006/messages/\(action)\"", forHTTPHeaderField: "SOAPAction")
        if settings.authentication == "basic" {
            let value = Data("\(settings.username):\(transport.password)".utf8).base64EncodedString()
            request.setValue("Basic " + value, forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            let code = (error as NSError).code
            if [NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication].contains(code) {
                authenticationFailed = true
                throw DeskError("Exchange odmítl přihlášení. Ověř stejné jméno a heslo jako ve webmailu; případně vyzkoušej NTLM.")
            }
            if code == NSURLErrorCancelled { throw CancellationError() }
            throw DeskError("Připojení k Exchange selhalo. Ověř internet, VPN a adresu serveru. \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { throw DeskError("Exchange nevrátil HTTP odpověď.") }
        if http.statusCode == 401 {
            authenticationFailed = true
            throw DeskError("Exchange odmítl přihlášení (401). Použij stejné jméno a heslo jako ve webmailu; případně vyzkoušej NTLM.")
        }
        if [429, 503].contains(http.statusCode) {
            blockedUntil = Date().addingTimeInterval(min(3600, max(60, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "300") ?? 300)))
            throw DeskError("Exchange je dočasně vytížený. Další požadavky jsou na chvíli pozastavené.")
        }
        guard http.statusCode == 200 || http.statusCode == 500 else {
            if http.statusCode == 403 { throw DeskError("Server nepovolil přístup přes EWS (403). Tento účet nebo způsob přihlášení může být omezený.") }
            if (300..<400).contains(http.statusCode) { throw DeskError("EWS přesměrovává na jinou adresu. Zadej konečnou HTTPS adresu serveru; přihlašovací údaje se nepřeposílají.") }
            throw DeskError("Exchange odpověděl HTTP \(http.statusCode). Ověř adresu EWS.")
        }
        let result = try EWSResponse(data)
        if result.codes.contains("ErrorServerBusy") { blockedUntil = Date().addingTimeInterval(300) }
        try result.check()
        return result
    }
    func unreadCount() async throws -> Int {
        let response = try await request("""
        <m:GetFolder><m:FolderShape><t:BaseShape>IdOnly</t:BaseShape><t:AdditionalProperties><t:FieldURI FieldURI="folder:UnreadCount"/></t:AdditionalProperties></m:FolderShape><m:FolderIds><t:DistinguishedFolderId Id="inbox"/></m:FolderIds></m:GetFolder>
        """)
        guard let value = response.first("UnreadCount"), let count = Int(value) else { throw DeskError("Exchange nevrátil počet nepřečtených zpráv.") }
        return count
    }
    static func mailOperation(filter: String) -> String {
        var restriction = ""
        if filter == "unread" { restriction = "<m:Restriction><t:IsEqualTo><t:FieldURI FieldURI=\"message:IsRead\"/><t:FieldURIOrConstant><t:Constant Value=\"false\"/></t:FieldURIOrConstant></t:IsEqualTo></m:Restriction>" }
        if filter == "flagged" { restriction = "<m:Restriction><t:IsEqualTo><t:ExtendedFieldURI PropertyTag=\"0x1090\" PropertyType=\"Integer\"/><t:FieldURIOrConstant><t:Constant Value=\"2\"/></t:FieldURIOrConstant></t:IsEqualTo></m:Restriction>" }
        let fields = ["item:Subject", "item:DateTimeReceived", "item:Preview", "item:Flag", "message:From", "message:IsRead"]
            .map { "<t:FieldURI FieldURI=\"\($0)\"/>" }.joined()
        return """
        <m:FindItem Traversal="Shallow"><m:ItemShape><t:BaseShape>IdOnly</t:BaseShape><t:AdditionalProperties>\(fields)</t:AdditionalProperties></m:ItemShape><m:IndexedPageItemView MaxEntriesReturned="30" Offset="0" BasePoint="Beginning"/>\(restriction)<m:SortOrder><t:FieldOrder Order="Descending"><t:FieldURI FieldURI="item:DateTimeReceived"/></t:FieldOrder></m:SortOrder><m:ParentFolderIds><t:DistinguishedFolderId Id="inbox"/></m:ParentFolderIds></m:FindItem>
        """
    }
    func messages(filter: String) async throws -> [MailMessage] {
        try await request(Self.mailOperation(filter: filter)).messages(webmail: settings.webmail)
    }
    static func calendarOperation(start: Date, end: Date) -> String {
        let f = ISO8601DateFormatter()
        let fields = ["item:Subject", "calendar:Start", "calendar:End", "calendar:IsAllDayEvent"]
            .map { "<t:FieldURI FieldURI=\"\($0)\"/>" }.joined()
        return """
        <m:FindItem Traversal="Shallow"><m:ItemShape><t:BaseShape>IdOnly</t:BaseShape><t:AdditionalProperties>\(fields)</t:AdditionalProperties></m:ItemShape><m:CalendarView MaxEntriesReturned="60" StartDate="\(f.string(from: start))" EndDate="\(f.string(from: end))"/><m:ParentFolderIds><t:DistinguishedFolderId Id="calendar"/></m:ParentFolderIds></m:FindItem>
        """
    }
    func events() async throws -> [CalendarEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return [] }
        return try await request(Self.calendarOperation(start: start, end: end)).events(webmail: settings.webmail)
    }
}

struct EWSResponse {
    let document: XMLDocument
    init(_ data: Data) throws {
        guard data.count <= 4 * 1024 * 1024,
              !String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("<!DOCTYPE") else {
            throw DeskError("Odpověď Exchange je příliš velká nebo obsahuje nepovolené XML.")
        }
        do { document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]) }
        catch { throw DeskError("Server nevrátil platnou EWS odpověď. Zkontroluj adresu /EWS/Exchange.asmx.") }
    }
    var codes: [String] { ((try? document.nodes(forXPath: "//*[local-name()='ResponseCode']")) ?? []).compactMap(\.stringValue) }
    func first(_ name: String) -> String? { (try? document.nodes(forXPath: "//*[local-name()='\(name)']"))?.first?.stringValue }
    func check() throws {
        if first("Fault") != nil { throw DeskError("Exchange vrátil chybu SOAP. Ověř nastavení EWS a způsob přihlášení.") }
        guard !codes.isEmpty else { throw DeskError("Server nevrátil očekávanou EWS odpověď. Ověř adresu serveru.") }
        if let code = codes.first(where: { $0 != "NoError" }) {
            let safeCode = String(code.filter { $0.isLetter || $0.isNumber }.prefix(80))
            throw DeskError("Exchange: \(safeCode). Ověř oprávnění schránky a dostupnost služby EWS.")
        }
    }
    static func text(_ element: XMLNode, _ name: String) -> String? {
        (try? element.nodes(forXPath: "./*[local-name()='\(name)']"))?.first?.stringValue
    }
    static func id(_ element: XMLNode) -> String? {
        ((try? element.nodes(forXPath: "./*[local-name()='ItemId']"))?.first as? XMLElement)?.attribute(forName: "Id")?.stringValue
    }
    static func link(webmail: String, id: String, calendar: Bool = false) -> String? {
        guard let url = URL(string: webmail), url.scheme == "https", url.host != nil else { return nil }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.queryItems = [.init(name: "ItemID", value: id), .init(name: "exvsurl", value: "1"), .init(name: "viewmodel", value: calendar ? "ICalendarItemDetailsViewModelPopOut" : "ReadMessageItem")]
        return c?.url?.absoluteString
    }
    func messages(webmail: String) -> [MailMessage] {
        let nodes = (try? document.nodes(forXPath: "//*[local-name()='Items']/*")) ?? []
        return nodes.compactMap { node in
            guard let id = Self.id(node), let received = Self.text(node, "DateTimeReceived") else { return nil }
            let sender = (try? node.nodes(forXPath: "./*[local-name()='From']/*[local-name()='Mailbox']"))?.first
            let flag = (try? node.nodes(forXPath: "./*[local-name()='Flag']/*[local-name()='FlagStatus']"))?.first?.stringValue
            let mappedFlag = flag == "Flagged" ? "flagged" : flag == "Complete" ? "complete" : "notFlagged"
            return MailMessage(id: id, subject: Self.text(node, "Subject"),
                from: sender.map { .init(emailAddress: .init(name: Self.text($0, "Name"), address: Self.text($0, "EmailAddress"))) },
                bodyPreview: Self.text(node, "Preview"), isRead: Self.text(node, "IsRead") == "true",
                receivedDateTime: received, webLink: Self.link(webmail: webmail, id: id), flag: .init(flagStatus: mappedFlag))
        }
    }
    func events(webmail: String) -> [CalendarEvent] {
        let nodes = (try? document.nodes(forXPath: "//*[local-name()='Items']/*[local-name()='CalendarItem']")) ?? []
        return nodes.compactMap { node in
            guard let id = Self.id(node), let start = Self.text(node, "Start"), let end = Self.text(node, "End") else { return nil }
            return CalendarEvent(id: id, subject: Self.text(node, "Subject"), start: .init(dateTime: start, timeZone: "UTC"),
                end: .init(dateTime: end, timeZone: "UTC"), webLink: Self.link(webmail: webmail, id: id, calendar: true),
                isAllDay: Self.text(node, "IsAllDayEvent") == "true", onlineMeeting: nil)
        }.sorted { $0.start.dateTime < $1.start.dateTime }
    }
}
