import Foundation
import AppKit
import Combine

@MainActor final class DeskModel: ObservableObject {
    let preferences: Preferences
    let auth: MicrosoftAuth
    let graph: GraphService
    @Published var connectingExchange = false
    @Published var exchangeIdentity: String?
    @Published var exchangeError: String?
    private var exchangeService: ExchangeService?
    var exchangeSettings: ExchangeSettings { config.exchange ?? ExchangeSettings() }
    var usesExchange: Bool { exchangeSettings.enabled }
    var exchangeConnected: Bool { exchangeService != nil && exchangeIdentity == exchangeSettings.identityKey }
    var mailConnected: Bool { usesExchange ? exchangeConnected : auth.connected }
    var mailEnabled: Bool { usesExchange ? exchangeSettings.mail : config.microsoft.mail }
    var calendarEnabled: Bool { usesExchange ? exchangeSettings.calendar : config.microsoft.calendar }
    var usesRemoteTasks: Bool { !usesExchange && config.microsoft.tasks }
    var mailURL: String { usesExchange ? exchangeSettings.webmail : "https://outlook.office.com/mail/" }
    var calendarURL: String { usesExchange ? exchangeSettings.webmail : "https://outlook.office.com/calendar/" }
    @Published var messages: [MailMessage] = []
    @Published var events: [CalendarEvent] = []
    @Published var tasks: [RemoteTask] = []
    @Published var lists: [TodoList] = []
    @Published var profile: Profile?
    @Published var unread: Int?
    @Published var detectedLocation: WeatherLocation?
    @Published var locationNotice: String?
    @Published var weather: WeatherReport?
    private let currentLocation = CurrentLocationService()
    private var weatherEpoch = 0
    @Published var articles: [Article] = []
    @Published var metrics = MetricSample()
    @Published var history: [Double] = []
    @Published var errors: [String: String] = [:]
    @Published var updated: [String: Date] = [:]
    @Published var loading = Set<String>()
    @Published var mailFilter = "all"
    @Published var category = "Vše"
    @Published var search = ""
    @Published var settingsOpen = false
    @Published var section = "Přehled"
    @Published var calendarUpcoming = false
    @Published var alert: String?
    private let sampler = SystemMetrics()
    private var timer: Timer?
    private var busy = Set<String>()
    private var lastAttempt: [String: Date] = [:]
    private var epoch = 0
    private var subscriptions = Set<AnyCancellable>()
    private var lastConfig: Configuration
    init(preferences: Preferences, auth: MicrosoftAuth) {
        self.preferences = preferences; self.auth = auth; graph = GraphService(auth: auth)
        lastConfig = preferences.config
        do {
            if let credential = try ExchangeKeychain.read(), credential.identity == exchangeSettings.identityKey {
                exchangeService = try ExchangeService(settings: exchangeSettings, password: credential.password)
                exchangeIdentity = credential.identity
            }
        } catch { exchangeError = error.localizedDescription }
        preferences.$config.dropFirst().debounce(for: .milliseconds(600), scheduler: RunLoop.main).sink { [weak self] config in
            guard let self else { return }
            let old = self.lastConfig; self.lastConfig = config
            if old.microsoft != config.microsoft || old.exchange != config.exchange {
                self.epoch += 1; self.clearMicrosoft()
                for key in ["mail", "calendar", "tasks", "profile"] { self.lastAttempt[key] = nil }
            }
            if old.locations != config.locations || old.selectedLocation != config.selectedLocation || old.weatherFollowsLocation != config.weatherFollowsLocation {
                self.weatherEpoch += 1; self.detectedLocation = nil; self.locationNotice = nil
                self.weather = nil; self.lastAttempt["weather"] = nil
            }
            if old.newsSources != config.newsSources { self.articles = []; self.lastAttempt["news"] = nil }
            Task { await self.tick() }
        }.store(in: &subscriptions)
    }
    var config: Configuration { preferences.config }
    var location: WeatherLocation? {
        if config.weatherFollowsLocation == true, let detectedLocation { return detectedLocation }
        return config.locations.first { $0.id == config.selectedLocation } ?? config.locations.first
    }
    var taskListID: String { lists.first { $0.id == config.microsoft.taskList }?.id ?? lists.first { $0.wellknownListName == "defaultList" }?.id ?? lists.first?.id ?? "" }
    var filteredMail: [MailMessage] { messages.filter { search.isEmpty || [$0.subject, $0.bodyPreview, $0.from?.emailAddress.name].compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(search) } }
    var filteredArticles: [Article] { articles.filter { (category == "Vše" || $0.category == category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) } }
    var shownEvents: [CalendarEvent] {
        events.filter {
            guard let start = Date.graph($0.start.dateTime), let end = Date.graph($0.end.dateTime) else { return false }
            return (calendarUpcoming ? end > Date() : Calendar.current.isDateInToday(start) || (start < Calendar.current.startOfDay(for: Date()) && end > Date())) &&
                (search.isEmpty || ($0.subject ?? "").localizedCaseInsensitiveContains(search))
        }
    }
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in await self?.tick() } }
        Task { await tick() }
    }
    private func due(_ key: String, _ seconds: Int) -> Bool { Date().timeIntervalSince(lastAttempt[key] ?? .distantPast) >= Double(seconds) }
    func tick() async {
        // Network refresh is suspended when the dashboard is hidden. Tokens renew on demand.
        guard NSApp.windows.contains(where: { $0.isVisible && !$0.isMiniaturized }) else { return }
        if config.visibleWidgets.contains("system"), due("metrics", max(5, config.metricsSeconds)) {
            lastAttempt["metrics"] = Date(); metrics = sampler.sample()
            if let cpu = metrics.cpu { history.append(cpu); if history.count > 40 { history.removeFirst() } }
        }
        async let w: Void = refreshWeather()
        async let n: Void = refreshNews()
        async let m: Void = refreshMicrosoft()
        _ = await (w, n, m)
    }
    func refreshAll() async {
        lastAttempt = [:]
        await tick()
    }
    func refreshWeather(force: Bool = false) async {
        guard config.visibleWidgets.contains("weather"), !busy.contains("weather"), force || due("weather", max(10, config.weatherMinutes) * 60) else { return }
        busy.insert("weather"); loading.insert("weather"); lastAttempt["weather"] = Date()
        let generation = weatherEpoch
        defer { busy.remove("weather"); loading.remove("weather") }
        if config.weatherFollowsLocation == true {
            do {
                let found = try await currentLocation.locate()
                guard generation == weatherEpoch else { return }
                detectedLocation = found; locationNotice = nil
            } catch {
                guard generation == weatherEpoch else { return }
                detectedLocation = nil
                locationNotice = error.localizedDescription + " Zobrazuji uložené město."
            }
        }
        guard let location else { errors["weather"] = "Přidej lokalitu v nastavení."; return }
        do {
            let report = try await WeatherService.load(location)
            guard generation == weatherEpoch, self.location?.id == location.id else { return }
            weather = report; errors["weather"] = nil; updated["weather"] = Date()
        } catch { if generation == weatherEpoch { errors["weather"] = error.localizedDescription } }
    }
    func refreshNews(force: Bool = false) async {
        guard config.visibleWidgets.contains("news"), !busy.contains("news"), force || due("news", max(10, config.newsMinutes) * 60) else { return }
        busy.insert("news"); loading.insert("news"); lastAttempt["news"] = Date()
        defer { busy.remove("news"); loading.remove("news") }
        let sources = config.newsSources
        let result = await NewsService.load(sources)
        guard sources == config.newsSources else { return }
        articles = result.articles; errors["news"] = result.errors.isEmpty ? nil : result.errors.joined(separator: "\n")
        updated["news"] = Date()
    }
    private func module(_ key: String, force: Bool, action: () async throws -> Void) async {
        guard !busy.contains(key), force || due(key, max(60, config.refreshSeconds)) else { return }
        busy.insert(key); loading.insert(key); lastAttempt[key] = Date()
        let generation = epoch
        defer { busy.remove(key); loading.remove(key) }
        do { try await action(); if generation == epoch { errors[key] = nil; updated[key] = Date() } }
        catch { if generation == epoch { errors[key] = error.localizedDescription } }
    }
    func refreshMicrosoft(force: Bool = false) async {
        if usesExchange { await refreshExchange(force: force); return }
        guard auth.connected else { return }
        let settings = config.microsoft, generation = epoch
        await module("profile", force: force) {
            let p = try await graph.profile(settings)
            if generation == epoch { profile = p }
        }
        if settings.mail, config.visibleWidgets.contains("mail") {
            let filter = mailFilter
            await module("mail", force: force) {
                let m = try await graph.messages(settings, filter: filter)
                let count = try await graph.unreadCount(settings)
                if generation == epoch, filter == mailFilter { messages = m; unread = count }
            }
        }
        if settings.calendar, config.visibleWidgets.contains("calendar") {
            await module("calendar", force: force) {
                let e = try await graph.events(settings)
                if generation == epoch { events = e }
            }
        }
        if settings.tasks, config.visibleWidgets.contains("tasks") {
            await module("tasks", force: force) {
                let l = try await graph.lists(settings)
                guard generation == epoch else { return }; lists = l
                if !taskListID.isEmpty {
                    let t = try await graph.tasks(settings, list: taskListID)
                    if generation == epoch { tasks = t }
                }
            }
        }
    }
    func connectExchange(_ settings: ExchangeSettings, password: String) async {
        guard !connectingExchange else { return }
        connectingExchange = true; exchangeError = nil
        defer { connectingExchange = false }
        let generation = epoch
        do {
            let service = try ExchangeService(settings: settings, password: password)
            _ = try await service.unreadCount()
            guard generation == epoch else { throw DeskError("Nastavení se během přihlašování změnilo. Připoj účet znovu.") }
            try ExchangeKeychain.write(.init(identity: settings.identityKey, password: password))
            var saved = settings; saved.enabled = true
            preferences.config.exchange = saved
            // Update immediately, avoiding a delayed settings callback clearing new results.
            lastConfig = preferences.config
            epoch += 1; clearMicrosoft()
            exchangeService = service; exchangeIdentity = saved.identityKey
            await refreshExchange(force: true)
        } catch { exchangeError = error.localizedDescription }
    }
    func disconnectExchange() {
        do {
            try ExchangeKeychain.delete()
            exchangeService = nil; exchangeIdentity = nil; exchangeError = nil
            epoch += 1; clearMicrosoft()
        } catch { exchangeError = error.localizedDescription }
    }
    private func refreshExchange(force: Bool = false) async {
        guard exchangeConnected, let service = exchangeService else { return }
        let settings = exchangeSettings, generation = epoch
        profile = Profile(displayName: settings.email.isEmpty ? settings.username : settings.email,
                          userPrincipalName: settings.username, mail: settings.email)
        if settings.mail, config.visibleWidgets.contains("mail") {
            let filter = mailFilter
            await module("mail", force: force) {
                let m = try await service.messages(filter: filter)
                let count = try await service.unreadCount()
                if generation == epoch, filter == mailFilter { messages = m; unread = count }
            }
        }
        if settings.calendar, config.visibleWidgets.contains("calendar") {
            await module("calendar", force: force) {
                let e = try await service.events()
                if generation == epoch { events = e }
            }
        }
    }
    func changeFilter(_ value: String) {
        mailFilter = value; messages = []; lastAttempt["mail"] = nil
        Task {
            // Wait for any older request to finish; it cannot overwrite another filter.
            while busy.contains("mail") { try? await Task.sleep(nanoseconds: 100_000_000) }
            await refreshMicrosoft(force: true)
        }
    }
    func signIn() async {
        epoch += 1; clearMicrosoft()
        await auth.signIn(config.microsoft)
        if auth.connected { await refreshMicrosoft(force: true) }
    }
    func disconnect() { epoch += 1; auth.disconnect(); clearMicrosoft() }
    private func clearMicrosoft() {
        messages = []; events = []; tasks = []; lists = []; profile = nil; unread = nil
        for key in ["mail", "calendar", "tasks", "profile"] { updated[key] = nil; errors[key] = nil; lastAttempt[key] = nil }
    }
    func addTask(_ title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if usesRemoteTasks {
            guard auth.connected, !taskListID.isEmpty else { alert = "Připoj Microsoft účet a vyber dostupný seznam úkolů."; return }
            do { try await graph.createTask(title, settings: config.microsoft, list: taskListID); await refreshMicrosoft(force: true) }
            catch { alert = error.localizedDescription }
        } else { preferences.config.localTasks.append(.init(title: title)) }
    }
    func complete(_ task: RemoteTask) async {
        do { try await graph.completeTask(task.id, settings: config.microsoft, list: taskListID); await refreshMicrosoft(force: true) }
        catch { alert = error.localizedDescription }
    }
    func open(_ target: String) { do { try Launcher.open(target) } catch { alert = error.localizedDescription } }
    func launch(_ app: LaunchItem) {
        if app.name == "ESO9" && app.path.isEmpty && app.bundleID.isEmpty { section = "ESO9"; return }
        do { try Launcher.launch(app) } catch { alert = error.localizedDescription }
    }
}
