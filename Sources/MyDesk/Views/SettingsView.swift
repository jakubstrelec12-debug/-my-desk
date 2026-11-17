import SwiftUI
import ServiceManagement

@MainActor struct SettingsView: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var auth: MicrosoftAuth
    @Environment(\.dismiss) var dismiss
    @State private var tab: String? = "Obecné"
    @State private var city = ""
    @State private var places: [WeatherService.Search.Place] = []
    @State private var weatherError: String?
    @State private var searching = false
    @State private var mailbox = ""
    @State private var loginError: String?
    @State private var loginStatus = SMAppService.mainApp.status
    let tabs = ["Obecné", "Microsoft", "Aplikace", "ESO9", "Projekty", "Počasí", "Zprávy", "Widgety"]
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Nastavení MY DESK").font(.title2.bold()); Spacer(); Button("Hotovo") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Divider()
            HStack(spacing: 0) {
                List(tabs, id: \.self, selection: $tab) { Text($0).padding(.vertical, 5) }.listStyle(.sidebar).frame(width: 155)
                ScrollView {
                    Form {
                        switch tab ?? "Obecné" {
                        case "Microsoft": microsoft
                        case "Aplikace": applications
                        case "ESO9": eso9
                        case "Projekty": projects
                        case "Počasí": weather
                        case "Zprávy": news
                        case "Widgety": widgets
                        default: general
                        }
                    }.formStyle(.grouped).padding(12)
                }
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    @ViewBuilder var general: some View {
        Section("Osobní nastavení") {
            TextField("Oslovení", text: $prefs.config.displayName)
            Picker("Vzhled", selection: $prefs.config.appearance) { Text("Tmavý").tag("dark"); Text("Světlý").tag("light"); Text("Podle systému").tag("system") }
            HStack { Text("Krytí panelů"); Slider(value: $prefs.config.opacity, in: 0.75...0.98); Text("\(Int(prefs.config.opacity * 100)) %") }
            Toggle("Při zavření okna skrýt do menu baru", isOn: $prefs.config.hideOnClose)
            Toggle("Spouštět na celé obrazovce", isOn: $prefs.config.fullScreen)
            Toggle("Spouštět po přihlášení k macOS", isOn: Binding(get: { loginStatus == .enabled }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginStatus = SMAppService.mainApp.status; loginError = nil
                } catch { loginError = error.localizedDescription; loginStatus = SMAppService.mainApp.status }
            }))
            if loginStatus == .requiresApproval { Button("Povolit v Nastavení systému") { SMAppService.openSystemSettingsLoginItems() } }
            if let loginError { Text(loginError).foregroundStyle(.orange) }
            Text("Automatické spuštění vyžaduje zabalenou aplikaci v /Applications. Spuštění přímo z Xcode nebo příkazem swift run nestačí.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Obnovování") {
            Stepper("Microsoft: \(prefs.config.refreshSeconds) s", value: $prefs.config.refreshSeconds, in: 60...1800, step: 60)
            Stepper("Počasí: \(prefs.config.weatherMinutes) min", value: $prefs.config.weatherMinutes, in: 10...180, step: 10)
            Stepper("RSS: \(prefs.config.newsMinutes) min", value: $prefs.config.newsMinutes, in: 10...180, step: 10)
            Stepper("Systém: \(prefs.config.metricsSeconds) s", value: $prefs.config.metricsSeconds, in: 5...60, step: 5)
            Text("Skryté widgety se neobnovují. Při skrytém hlavním okně se automatické aktualizace pozastaví.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder var microsoft: some View {
        Section("Microsoft 365 / Exchange Online") {
            TextField("Application (client) ID", text: $prefs.config.microsoft.clientID)
            TextField("Tenant ID nebo doména", text: $prefs.config.microsoft.tenant)
            LabeledContent("Redirect URI", value: MicrosoftAuth.redirect).textSelection(.enabled)
            Toggle("Číst doručenou poštu a vlaječky", isOn: $prefs.config.microsoft.mail)
            Toggle("Číst kalendář", isOn: $prefs.config.microsoft.calendar)
            Toggle("Microsoft To Do – číst, vytvářet a dokončovat", isOn: $prefs.config.microsoft.tasks)
            Toggle("Povolit sdílené schránky", isOn: $prefs.config.microsoft.sharedMail)
            Text("Po změně ID, tenantu nebo oprávnění účet odpoj a znovu připoj. Aplikace nepoužívá client secret ani neukládá heslo.").font(.caption).foregroundStyle(.secondary)
            Text("Oprávnění: " + prefs.config.microsoft.scopes.joined(separator: ", ")).font(.caption).textSelection(.enabled)
            HStack {
                Button(auth.busy ? "Přihlašuji…" : "Připojit / změnit účet") { Task { await model.signIn() } }.disabled(auth.busy)
                if auth.connected { Button("Odpojit účet", role: .destructive) { model.disconnect() } }
            }
            if let profile = model.profile { Text("Připojeno: \(profile.displayName) · \(profile.mail ?? profile.userPrincipalName ?? "")").foregroundStyle(.green) }
            if let error = auth.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if let error = model.errors["profile"] { Text(error).foregroundStyle(.orange) }
            Text("Lokální Exchange není přes Graph podporován. V takovém případě používej Outlook; MY DESK neobchází firemní autentizaci. Firemní správce může vyžadovat schválení aplikace nebo blokovat vlastní klienty zásadami Conditional Access.").font(.caption).foregroundStyle(.secondary)
            Link("Registrace desktopové aplikace – dokumentace Microsoft", destination: URL(string: "https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-configuration")!)
        }
        if prefs.config.microsoft.sharedMail {
            Section("Sdílené schránky") {
                Text("Zadej adresy schránek, ke kterým už má přihlášený uživatel delegovaný přístup. Graph neposkytuje obecný seznam všech takových schránek.").font(.caption).foregroundStyle(.secondary)
                HStack { TextField("schranka@firma.cz", text: $mailbox); Button("Přidat") {
                    let value = mailbox.trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.contains("@"), !prefs.config.microsoft.mailboxes.contains(value) { prefs.config.microsoft.mailboxes.append(value); mailbox = "" }
                } }
                ForEach(prefs.config.microsoft.mailboxes, id: \.self) { address in
                    HStack { Text(address); Spacer(); Button("Odebrat", role: .destructive) { prefs.config.microsoft.mailboxes.removeAll { $0 == address }; if prefs.config.microsoft.mailbox == address { prefs.config.microsoft.mailbox = "" } } }
                }
            }
        }
        if prefs.config.microsoft.tasks {
            Section("Seznam To Do") {
                Picker("Ukládat nové úkoly do", selection: $prefs.config.microsoft.taskList) {
                    Text("Výchozí seznam").tag("")
                    ForEach(model.lists) { Text($0.displayName).tag($0.id) }
                }
                Button("Načíst seznamy") { Task { await model.refreshMicrosoft(force: true) } }
                Text("Zobrazuje se až 100 nedokončených úkolů z jednoho vybraného seznamu. Vypnutí To Do přepne widget na samostatné místní úkoly.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder var applications: some View {
        Section("Rychlé spuštění") {
            Button("Přidat nainstalovanou aplikaci…") { prefs.chooseApp() }
            ForEach($prefs.config.apps) { $app in
                HStack {
                    TextField("Název", text: $app.name)
                    Text(app.path.isEmpty ? app.bundleID : app.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(app.path)
                    Button { prefs.moveApp(app.id, by: -1) } label: { Image(systemName: "arrow.up") }.help("Posunout nahoru")
                    Button { prefs.moveApp(app.id, by: 1) } label: { Image(systemName: "arrow.down") }.help("Posunout dolů")
                    Button(role: .destructive) { prefs.config.apps.removeAll { $0.id == app.id } } label: { Image(systemName: "trash") }
                }
            }
            Text("ESO9 bez přiřazené aplikace otevře zákaznické centrum. Pro Teams se používá aktuální bundle ID com.microsoft.teams2; jinou verzi vyber přes Přidat aplikaci.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder var eso9: some View {
        Section("Pracovní centrum") {
            TextField("Portál podpory", text: $prefs.config.esoSupport)
            TextField("Soubor vzdáleného připojení Správce", text: $prefs.config.esoManager)
            Button("Vybrat .rdp nebo jiný soubor připojení…") { if let path = prefs.chooseFile() { prefs.config.esoManager = path } }
            Text("Správce ESO9 spouštěj na Windows stanici/serveru přes Windows App a VPN nebo firemní RD Gateway. Neukládej hesla do poznámek či URL. MY DESK otevře soubor v přiřazeném klientovi; nespouští Windows program nativně.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Zákaznická prostředí") {
            Button("Přidat zákazníka") { prefs.config.customers.append(.init(name: "Nový zákazník")) }
            ForEach($prefs.config.customers) { $customer in
                DisclosureGroup(customer.name.isEmpty ? "Zákazník" : customer.name) {
                    TextField("Název", text: $customer.name)
                    TextField("Produkční URL", text: $customer.production)
                    TextField("Testovací URL", text: $customer.test)
                    TextField("Dokumentace URL", text: $customer.documentation)
                    TextField("Poznámka (bez hesel)", text: $customer.note, axis: .vertical)
                    Toggle("Oblíbené prostředí", isOn: $customer.favorite)
                    HStack {
                        Button("Otevřít produkci") { model.open(customer.production) }.disabled(customer.production.isEmpty)
                        Button("Odebrat zákazníka", role: .destructive) { prefs.config.customers.removeAll { $0.id == customer.id } }
                    }
                }
            }
        }
    }
    @ViewBuilder var projects: some View {
        Section("Projekty, složky a odkazy") {
            Button("Přidat projekt") { prefs.config.projects.append(.init(name: "Nový projekt")) }
            ForEach($prefs.config.projects) { $project in
                DisclosureGroup(project.name) {
                    TextField("Název", text: $project.name)
                    TextField("Webová adresa nebo místní cesta", text: $project.target)
                    HStack {
                        Button("Vybrat složku…") { if let path = prefs.chooseFile(directory: true) { project.target = path } }
                        Button("Vybrat soubor…") { if let path = prefs.chooseFile() { project.target = path } }
                        Button("Otevřít") { model.open(project.target) }
                        Button("Odebrat", role: .destructive) { prefs.config.projects.removeAll { $0.id == project.id } }
                    }
                    Toggle("Oblíbený projekt", isOn: $project.favorite)
                }
            }
        }
    }
    @ViewBuilder var weather: some View {
        Section("Lokality") {
            Picker("Zobrazovat", selection: Binding(get: { prefs.config.selectedLocation ?? prefs.config.locations.first?.id }, set: { prefs.config.selectedLocation = $0 })) {
                ForEach(prefs.config.locations) { Text($0.name).tag(Optional($0.id)) }
            }
            HStack {
                TextField("Vyhledat město", text: $city).onSubmit { searchCity() }
                Button(searching ? "Hledám…" : "Vyhledat") { searchCity() }.disabled(searching || city.count < 2)
            }
            if let weatherError { Text(weatherError).foregroundStyle(.orange) }
            ForEach(places) { place in
                HStack {
                    Text("\(place.name), \(place.admin1 ?? "") · \(place.country ?? "")")
                    Spacer()
                    Button("Přidat") {
                        let location = WeatherLocation(name: place.name, latitude: place.latitude, longitude: place.longitude)
                        prefs.config.locations.append(location); prefs.config.selectedLocation = location.id; places = []
                    }
                }
            }
            ForEach($prefs.config.locations) { $location in
                DisclosureGroup(location.name) {
                    TextField("Název", text: $location.name)
                    TextField("Zeměpisná šířka", value: $location.latitude, format: .number)
                    TextField("Zeměpisná délka", value: $location.longitude, format: .number)
                    Button("Odebrat", role: .destructive) { prefs.config.locations.removeAll { $0.id == location.id } }.disabled(prefs.config.locations.count < 2)
                }
            }
            Link("Open-Meteo · zdroj dat a licence", destination: URL(string: "https://open-meteo.com/en/terms")!)
            Text("Veřejné API je pro osobní nekomerční použití. Pro placenou distribuci je potřeba před vydáním vyřešit komerční licenci a endpoint; tato verze komerční klíč neimplementuje.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder var news: some View {
        Section("RSS / Atom zdroje") {
            Text("Načítají se pouze titulky a původní odkazy. Maximálně 16 zapnutých zdrojů, 30 položek na zdroj. Používej HTTPS. Zdroje mohou své adresy nebo podmínky změnit.").font(.caption).foregroundStyle(.secondary)
            Button("Přidat zdroj") { prefs.config.newsSources.append(.init(name: "Nový zdroj", category: "Česká republika", url: "")) }
            ForEach($prefs.config.newsSources) { $source in
                DisclosureGroup("\(source.name) – \(source.category)") {
                    Toggle("Zapnuto", isOn: $source.enabled)
                    TextField("Název", text: $source.name)
                    TextField("RSS URL", text: $source.url)
                    Picker("Kategorie", selection: $source.category) { ForEach(["Česká republika", "Ekonomika", "Technologie", "Sport"], id: \.self) { Text($0).tag($0) } }
                    Button("Odebrat", role: .destructive) { prefs.config.newsSources.removeAll { $0.id == source.id } }
                }
            }
        }
    }
    var widgets: some View {
        Section("Zobrazované widgety") {
            ForEach([("greeting", "Pozdrav a čas"), ("launcher", "Rychlé spuštění"), ("eso9", "ESO9 centrum"), ("projects", "Oblíbené projekty"), ("calendar", "Kalendář"), ("tasks", "Úkoly"), ("mail", "E-maily"), ("weather", "Počasí"), ("news", "Aktuální zprávy"), ("system", "Stav Macu")], id: \.0) { item in
                Toggle(item.1, isOn: Binding(get: { prefs.config.visibleWidgets.contains(item.0) }, set: {
                    if $0 { prefs.config.visibleWidgets.insert(item.0) } else { prefs.config.visibleWidgets.remove(item.0) }
                }))
            }
        }
    }
    func searchCity() {
        guard !searching, city.count >= 2 else { return }; searching = true; weatherError = nil
        Task {
            do { places = try await WeatherService.search(city); if places.isEmpty { weatherError = "Žádná odpovídající lokalita." } }
            catch { weatherError = error.localizedDescription }
            searching = false
        }
    }
}
