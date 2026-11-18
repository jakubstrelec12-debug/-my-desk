import Foundation

struct LaunchItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var bundleID: String = ""
    var path: String = ""
    static let initial: [LaunchItem] = [
        .init(name: "Outlook", bundleID: "com.microsoft.Outlook"),
        .init(name: "Safari", bundleID: "com.apple.Safari"),
        .init(name: "VS Code", bundleID: "com.microsoft.VSCode"),
        .init(name: "Terminál", bundleID: "com.apple.Terminal"),
        .init(name: "Finder", bundleID: "com.apple.finder"),
        .init(name: "ESO9"),
        .init(name: "Teams", bundleID: "com.microsoft.teams2")
    ]
}
struct Customer: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var production = ""
    var test = ""
    var documentation = ""
    var note = ""
    var favorite = true
}
struct ProjectLink: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var target = ""
    var favorite = true
}
struct LocalTask: Identifiable, Codable {
    var id = UUID()
    var title: String
    var completed = false
}
struct NewsSource: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var category: String
    var url: String
    var enabled = true
    static let initial: [NewsSource] = [
        .init(name: "iDNES.cz", category: "Česká republika", url: "https://servis.idnes.cz/rss.aspx?c=zpravodaj"),
        .init(name: "iDNES.cz", category: "Ekonomika", url: "https://servis.idnes.cz/rss.aspx?c=ekonomika"),
        .init(name: "Root.cz", category: "Technologie", url: "https://www.root.cz/rss/clanky/"),
        .init(name: "iDNES.cz", category: "Sport", url: "https://servis.idnes.cz/rss.aspx?c=sport")
    ]
}
struct WeatherLocation: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
}
struct MicrosoftSettings: Codable, Equatable {
    var clientID = ""
    var tenant = "organizations"
    var mail = true
    var calendar = true
    var tasks = false
    var sharedMail = false
    var mailboxes: [String] = []
    var mailbox = ""
    var taskList = ""
    var identityKey: String { "\(tenant)|\(clientID)|\(scopes.joined(separator: " "))" }
    var scopes: [String] {
        var s = ["offline_access", "User.Read"]
        if mail { s.append(sharedMail ? "Mail.Read.Shared" : "Mail.Read") }
        if calendar { s.append("Calendars.Read") }
        if tasks { s.append("Tasks.ReadWrite") }
        return s
    }
}
struct Configuration: Codable {
    var version = 1
    var displayName = "Jakube"
    var appearance = "dark"
    var opacity = 0.88
    var hideOnClose = true
    var fullScreen = false
    var refreshSeconds = 300
    var weatherMinutes = 30
    var newsMinutes = 30
    var metricsSeconds = 10
    var visibleWidgets = Set(["greeting", "launcher", "eso9", "projects", "calendar", "tasks", "mail", "weather", "news", "system"])
    var apps = LaunchItem.initial
    var customers = ["Srnín", "PRECITOOL", "BATIST", "REJFOOD"].map { Customer(name: $0) }
    var projects = ["Nuviro", "ZakázkaAI", "Fluento", "ESO9 projekty"].map { ProjectLink(name: $0) }
    var localTasks: [LocalTask] = []
    var locations = [WeatherLocation(name: "Jindřichův Hradec", latitude: 49.144, longitude: 15.003)]
    var selectedLocation: UUID?
    var newsSources = NewsSource.initial
    var esoManager = ""
    var esoSupport = "https://podpora.eso.cz/"
    var microsoft = MicrosoftSettings()
    // Optional for compatibility with settings saved by version 1.0.
    var exchange: ExchangeSettings?
    var dashboardLayout: String?
    var weatherFollowsLocation: Bool?
}
struct GraphPage<T: Decodable>: Decodable {
    let value: [T]
    let nextLink: String?
    enum CodingKeys: String, CodingKey { case value; case nextLink = "@odata.nextLink" }
}
struct MailMessage: Decodable, Identifiable {
    struct Address: Decodable { let name: String?; let address: String? }
    struct Sender: Decodable { let emailAddress: Address }
    struct Flag: Decodable { let flagStatus: String }
    let id: String
    let subject: String?
    let from: Sender?
    let bodyPreview: String?
    let isRead: Bool
    let receivedDateTime: String
    let webLink: String?
    let flag: Flag?
}
struct CalendarEvent: Decodable, Identifiable {
    struct EventDate: Decodable { let dateTime: String; let timeZone: String }
    struct OnlineMeeting: Decodable { let joinUrl: String? }
    let id: String
    let subject: String?
    let start: EventDate
    let end: EventDate
    let webLink: String?
    let isAllDay: Bool?
    let onlineMeeting: OnlineMeeting?
}
struct TodoList: Decodable, Identifiable { let id: String; let displayName: String; let wellknownListName: String? }
struct RemoteTask: Decodable, Identifiable { let id: String; let title: String; let status: String }
struct Profile: Decodable { let displayName: String; let userPrincipalName: String?; let mail: String? }
struct WeatherReport: Decodable {
    struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
    struct Daily: Decodable {
        let time: [String]; let weather_code: [Int]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double]
    }
    let current: Current
    let daily: Daily
    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "Jasno"
        case 1, 2: return "Polojasno"
        case 3: return "Zataženo"
        case 45, 48: return "Mlha"
        case 51...57: return "Mrholení"
        case 61...67, 80...82: return "Déšť"
        case 71...77, 85, 86: return "Sněžení"
        case 95...99: return "Bouřky"
        default: return "Proměnlivo"
        }
    }
    static func symbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
struct Article: Identifiable {
    var id: String { url }
    var title: String
    var url: String
    var category: String
    var source: String
    var date: Date?
}
struct MetricSample {
    var battery: Double?
    var charging = false
    var memory: Double?
    var cpu: Double?
    var disk: Double?
    var date = Date()
}
struct DeskError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
extension Date {
    func czech(_ format: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "cs_CZ"); f.dateFormat = format
        return f.string(from: self)
    }
    static func graph(_ raw: String) -> Date? {
        let hasZone = raw.hasSuffix("Z") || raw.range(of: "[+-][0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil
        let value = hasZone ? raw : raw + "Z"
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: value)
    }
}

struct ExchangeSettings: Codable, Equatable {
    var enabled = false
    var endpoint = "https://webmail.eso9.cz/EWS/Exchange.asmx"
    var username = ""
    var email = ""
    var authentication = "basic"
    var mail = true
    var calendar = true
    var identityKey: String { "\(endpoint)|\(username)|\(authentication)" }
    func validatedURL() throws -> URL {
        guard let u = URL(string: endpoint), u.scheme?.lowercased() == "https",
              let host = u.host, !host.isEmpty, u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil, !u.path.isEmpty,
              ["basic", "ntlm"].contains(authentication),
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !username.contains(":"), !username.contains("\n"), !username.contains("\r") else {
            throw DeskError("Vyplň HTTPS adresu EWS a přihlašovací jméno. Adresa nesmí obsahovat heslo ani parametry.")
        }
        return u
    }
    var webmail: String {
        guard let u = URL(string: endpoint), u.scheme == "https", u.host != nil else { return "" }
        var c = URLComponents(url: u, resolvingAgainstBaseURL: false)
        c?.path = "/owa/"; c?.query = nil; c?.fragment = nil; c?.user = nil; c?.password = nil
        return c?.url?.absoluteString ?? ""
    }
}
