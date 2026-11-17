import Foundation

@MainActor final class GraphService {
    let auth: MicrosoftAuth
    init(auth: MicrosoftAuth) { self.auth = auth }
    static func segment(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
    private var blockedUntil = Date.distantPast
    func request(_ path: String, settings: MicrosoftSettings, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil, retry: Bool = true) async throws -> Data {
        guard blockedUntil <= Date() else { throw DeskError("Microsoft omezil požadavky. Další pokus bude možný za \(Int(blockedUntil.timeIntervalSinceNow) + 1) s.") }
        var c = URLComponents(string: "https://graph.microsoft.com/v1.0/" + path)!
        if !query.isEmpty { c.queryItems = query }
        var r = URLRequest(url: c.url!); r.httpMethod = method
        r.setValue("Bearer \(try await auth.accessToken(settings))", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await Network.shared.data(r)
        if response.statusCode == 401 && retry {
            _ = try await auth.accessToken(settings, force: true)
            return try await request(path, settings: settings, query: query, method: method, body: body, retry: false)
        }
        if response.statusCode == 429 || response.statusCode == 503 {
            let delay = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            blockedUntil = Date().addingTimeInterval(max(30, delay))
            throw DeskError("Microsoft dočasně omezuje požadavky. Počkej alespoň \(Int(max(30, delay))) s.")
        }
        guard (200..<300).contains(response.statusCode) else {
            switch response.statusCode {
            case 403: throw DeskError("Microsoft nepovolil přístup. Ověř oprávnění a souhlas správce; pro sdílenou schránku také delegaci.")
            case 404: throw DeskError("Schránka nebo seznam nebyl nalezen. Graph vyžaduje Exchange Online; ověř nastavenou adresu.")
            default: throw DeskError("Microsoft Graph: HTTP \(response.statusCode). Zkus obnovit data nebo se přihlásit znovu.")
            }
        }
        return data
    }
    func page<T: Decodable>(_ type: T.Type, path: String, settings: MicrosoftSettings, query: [URLQueryItem] = []) async throws -> [T] {
        try JSONDecoder().decode(GraphPage<T>.self, from: await request(path, settings: settings, query: query)).value
    }
    func profile(_ settings: MicrosoftSettings) async throws -> Profile {
        try JSONDecoder().decode(Profile.self, from: await request("me", settings: settings,
            query: [.init(name: "$select", value: "displayName,mail,userPrincipalName")]))
    }
    func messages(_ settings: MicrosoftSettings, filter: String) async throws -> [MailMessage] {
        let base = settings.mailbox.isEmpty ? "me" : "users/\(Self.segment(settings.mailbox))"
        var q = [URLQueryItem(name: "$top", value: "30"), .init(name: "$select", value: "id,subject,from,bodyPreview,isRead,receivedDateTime,webLink,flag")]
        if filter == "unread" { q.append(.init(name: "$filter", value: "receivedDateTime ge 1900-01-01T00:00:00Z and isRead eq false")); q.append(.init(name: "$orderby", value: "receivedDateTime desc")) }
        else if filter == "flagged" { q.append(.init(name: "$filter", value: "receivedDateTime ge 1900-01-01T00:00:00Z and flag/flagStatus eq 'flagged'")); q.append(.init(name: "$orderby", value: "receivedDateTime desc")) }
        else { q.append(.init(name: "$orderby", value: "receivedDateTime desc")) }
        let path = base + (filter == "flagged" ? "/messages" : "/mailFolders/inbox/messages")
        return try await page(MailMessage.self, path: path, settings: settings, query: q)
            .sorted { $0.receivedDateTime > $1.receivedDateTime }
    }
    func unreadCount(_ settings: MicrosoftSettings) async throws -> Int {
        struct Folder: Decodable { let unreadItemCount: Int }
        let base = settings.mailbox.isEmpty ? "me" : "users/\(Self.segment(settings.mailbox))"
        return try JSONDecoder().decode(Folder.self, from: await request(base + "/mailFolders/inbox", settings: settings,
            query: [.init(name: "$select", value: "unreadItemCount")])).unreadItemCount
    }
    func events(_ settings: MicrosoftSettings) async throws -> [CalendarEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let f = ISO8601DateFormatter()
        return try await page(CalendarEvent.self, path: "me/calendarView", settings: settings, query: [
            .init(name: "startDateTime", value: f.string(from: start)), .init(name: "endDateTime", value: f.string(from: end)),
            .init(name: "$orderby", value: "start/dateTime"), .init(name: "$top", value: "60"),
            .init(name: "$select", value: "id,subject,start,end,webLink,isAllDay,onlineMeeting")])
    }
    func lists(_ settings: MicrosoftSettings) async throws -> [TodoList] {
        try await page(TodoList.self, path: "me/todo/lists", settings: settings, query: [.init(name: "$top", value: "100")])
    }
    func tasks(_ settings: MicrosoftSettings, list: String) async throws -> [RemoteTask] {
        try await page(RemoteTask.self, path: "me/todo/lists/\(Self.segment(list))/tasks", settings: settings,
            query: [.init(name: "$top", value: "100"), .init(name: "$filter", value: "status ne 'completed'")])
    }
    func createTask(_ title: String, settings: MicrosoftSettings, list: String) async throws {
        _ = try await request("me/todo/lists/\(Self.segment(list))/tasks", settings: settings, method: "POST", body: ["title": title])
    }
    func completeTask(_ id: String, settings: MicrosoftSettings, list: String) async throws {
        _ = try await request("me/todo/lists/\(Self.segment(list))/tasks/\(Self.segment(id))", settings: settings,
                              method: "PATCH", body: ["status": "completed"])
    }
}
