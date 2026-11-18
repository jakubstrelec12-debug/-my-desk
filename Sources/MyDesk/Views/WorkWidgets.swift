import SwiftUI

@MainActor struct ESO9Widget: View {
    @Environment(\.compactDashboard) var compact
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        GlassPanel(title: "ESO9 – pracovní centrum", icon: "square.3.layers.3d", orange: true) {
            ScrollView { VStack(spacing: 0) {
                link("Zákaznické aplikace", detail: "Instalace a prostředí ESO9", icon: "desktopcomputer") { model.section = "ESO9" }
                Divider()
                link("ESO9 Správce", detail: prefs.config.esoManager.isEmpty ? "Nastav vzdálený přístup do Windows" : "Otevřít nastavené vzdálené připojení", icon: "gearshape") {
                    if prefs.config.esoManager.isEmpty { model.settingsOpen = true } else { model.open(prefs.config.esoManager) }
                }
                Divider()
                link("Technická Wiki", detail: "wiki.eso9.cz – návody a integrace", icon: "book") { model.open("https://wiki.eso9.cz") }
                Divider()
                link("Podpora ESO9", detail: "Zákaznický portál a požadavky", icon: "headphones") { model.open(prefs.config.esoSupport) }
            } }
        }
    }
    func link(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: compact ? 8 : 13) {
                Image(systemName: icon).font(.system(size: compact ? 18 : 21)).frame(width: compact ? 22 : 26)
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 12, weight: .semibold)); Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0); Image(systemName: "arrow.up.right.square").font(.system(size: 13))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, compact ? 4 : 6).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
@MainActor struct ProjectsWidget: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        GlassPanel(title: "Oblíbené projekty", icon: "star.fill", action: { model.section = "Projekty" }, actionTitle: "Zobrazit vše") {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(prefs.config.projects.filter { $0.favorite && (model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search)) }) { project in
                        HStack {
                            Button { model.open(project.target) } label: { Label(project.name, systemImage: "folder.fill").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                            Button { if let i = prefs.config.projects.firstIndex(where: { $0.id == project.id }) { prefs.config.projects[i].favorite.toggle() } } label: { Image(systemName: "star.fill").foregroundStyle(.yellow.opacity(0.8)) }.buttonStyle(.plain).help("Odebrat z oblíbených")
                        }.padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }
}
@MainActor struct CalendarWidget: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var auth: MicrosoftAuth
    var body: some View {
        GlassPanel(title: model.calendarUpcoming ? "Nadcházející plán" : "Dnešní plán", icon: "calendar", action: { model.calendarUpcoming.toggle() }, actionTitle: model.calendarUpcoming ? "Dnes" : "7 dní") {
            VStack(alignment: .leading, spacing: 9) {
                ServiceStatus(key: "calendar") { Task { await model.refreshMicrosoft(force: true) } }
                if !model.mailConnected || !model.calendarEnabled {
                    EmptyWidget(title: "Připoj firemní kalendář", detail: "Schůzky z Microsoft 365 nebo firemního Exchange se zobrazí po přihlášení.", action: { model.settingsOpen = true })
                } else if model.shownEvents.isEmpty && !model.loading.contains("calendar") {
                    EmptyWidget(symbol: "calendar.badge.checkmark", title: "Volný prostor v plánu", detail: model.errors["calendar"] == nil ? "V načteném období nejsou žádné odpovídající události." : "Kalendář nyní není dostupný.")
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(model.shownEvents.enumerated()), id: \.element.id) { index, event in
                                Button { model.open(event.webLink ?? model.calendarURL) } label: {
                                    HStack(alignment: .top, spacing: 9) {
                                        Text(event.isAllDay == true ? "Celý\nden" : (Date.graph(event.start.dateTime)?.czech("HH:mm") ?? "—"))
                                            .font(.system(size: 11, weight: .medium)).monospacedDigit().frame(width: 37, alignment: .leading).padding(.top, 10)
                                        HStack(spacing: 10) {
                                            Image(systemName: event.onlineMeeting == nil ? "calendar" : "video.fill").font(.system(size: 21))
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(event.subject ?? "Bez názvu").font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                                Text(eventSubtitle(event)).font(.system(size: 10)).foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                            .background([Color.blue, .purple, .teal, .indigo][index % 4].opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
                                    }
                                }.buttonStyle(.plain)
                                .contextMenu {
                                    if let join = event.onlineMeeting?.joinUrl { Button("Připojit ke schůzce") { model.open(join) } }
                                    Button("Otevřít v kalendáři") { model.open(event.webLink ?? model.calendarURL) }
                                }
                            }
                        }
                    }
                }
                LastUpdated(key: "calendar")
            }
        }
    }
    func eventSubtitle(_ event: CalendarEvent) -> String {
        guard let start = Date.graph(event.start.dateTime), let end = Date.graph(event.end.dateTime) else { return "" }
        return "\(model.calendarUpcoming ? start.czech("EEE d. M. · ") : "")\(start.czech("HH:mm")) – \(end.czech("HH:mm"))"
    }
}
@MainActor struct TasksWidget: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    @State private var adding = false
    @State private var title = ""
    @State private var saving = false
    var body: some View {
        GlassPanel(title: "Úkoly", icon: "checkmark.circle", action: { adding = true }) {
            VStack(alignment: .leading, spacing: 9) {
                Text(model.usesRemoteTasks ? "Microsoft To Do" : "Místní úkoly · pouze tento Mac").font(.system(size: 10)).foregroundStyle(.secondary)
                if model.usesRemoteTasks {
                    ServiceStatus(key: "tasks") { Task { await model.refreshMicrosoft(force: true) } }
                    if model.tasks.isEmpty {
                        EmptyWidget(symbol: "checkmark.circle", title: model.auth.connected ? "Žádné otevřené úkoly" : "Připoj Microsoft To Do", detail: "Nový úkol přidáš tlačítkem +.", action: model.auth.connected ? nil : { model.settingsOpen = true })
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.tasks) { task in
                                Button { saving = true; Task { await model.complete(task); saving = false } } label: {
                                    taskRow(task.title, completed: false)
                                }.buttonStyle(.plain).disabled(saving)
                            }
                        }
                    }
                    LastUpdated(key: "tasks")
                } else {
                    if prefs.config.localTasks.isEmpty { EmptyWidget(symbol: "checkmark.circle", title: "Tvůj seznam je prázdný", detail: "Přidej vlastní úkol. Firemní synchronizaci zapneš v nastavení.") }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(prefs.config.localTasks) { task in
                                Button {
                                    if let i = prefs.config.localTasks.firstIndex(where: { $0.id == task.id }) { prefs.config.localTasks[i].completed.toggle() }
                                } label: { taskRow(task.title, completed: task.completed) }.buttonStyle(.plain)
                                    .contextMenu { Button("Odstranit", role: .destructive) { prefs.config.localTasks.removeAll { $0.id == task.id } } }
                            }
                        }
                    }
                }
            }
        }.sheet(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Nový úkol").font(.title2.bold())
                TextField("Co je potřeba udělat?", text: $title).textFieldStyle(.roundedBorder).onSubmit { save() }
                HStack { Button("Zrušit") { adding = false }; Spacer(); Button("Přidat") { save() }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving) }
            }.padding(24).frame(width: 380)
        }
    }
    func save() { guard !saving, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; saving = true; Task { await model.addTask(title); saving = false; title = ""; adding = false } }
    func taskRow(_ title: String, completed: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: completed ? "checkmark.square.fill" : "square").font(.system(size: 24, weight: .light)).foregroundStyle(completed ? Color.orange : Color.secondary)
                Text(title).font(.system(size: 12)).strikethrough(completed).foregroundStyle(completed ? .secondary : .primary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
            }.padding(.vertical, 8)
            Divider()
        }.contentShape(Rectangle())
    }
}
@MainActor struct MailWidget: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var auth: MicrosoftAuth
    var body: some View {
        GlassPanel(title: "E-maily (Outlook)", icon: "envelope", action: { model.open(model.mailURL) }, actionTitle: "Otevřít") {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    ForEach([("all", "Vše"), ("unread", "Nepřečtené\(model.unread.map { " \($0)" } ?? "")"), ("flagged", "S vlaječkou")], id: \.0) { filter in
                        Button { model.changeFilter(filter.0) } label: {
                            Text(filter.1).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6).background(model.mailFilter == filter.0 ? Color.orange : Color.white.opacity(0.08), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    if !model.usesExchange && prefs.config.microsoft.sharedMail {
                        Picker("Schránka", selection: $prefs.config.microsoft.mailbox) {
                            Text("Moje schránka").tag("")
                            ForEach(prefs.config.microsoft.mailboxes, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(maxWidth: 150)
                    }
                }
                ServiceStatus(key: "mail") { Task { await model.refreshMicrosoft(force: true) } }
                if !model.mailConnected || !model.mailEnabled {
                    EmptyWidget(symbol: "envelope.badge", title: "Připoj svůj pracovní e-mail", detail: "Microsoft 365 nebo vlastní firemní Exchange. Připojení nastavíš v příslušné záložce nastavení.", actionTitle: "Nastavit připojení", action: { model.settingsOpen = true })
                } else if model.filteredMail.isEmpty && !model.loading.contains("mail") {
                    EmptyWidget(symbol: "tray", title: model.errors["mail"] == nil ? "Žádné odpovídající zprávy" : "E-maily nyní nejsou dostupné", detail: model.usesExchange ? "Změň filtr nebo obnov data. Exchange prohledává Doručenou poštu včetně vlaječek." : "Změň filtr nebo obnov data. Vlaječky se hledají v celé schránce.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.filteredMail) { mail in
                                Button { model.open(mail.webLink ?? model.mailURL) } label: {
                                    HStack(alignment: .top, spacing: 13) {
                                        Image(systemName: mail.flag?.flagStatus == "flagged" ? "flag.fill" : "circle.fill")
                                            .font(.system(size: mail.flag?.flagStatus == "flagged" ? 17 : 10))
                                            .foregroundStyle(mail.flag?.flagStatus == "flagged" ? Color.red : mail.isRead ? Color.secondary.opacity(0.4) : Color.blue).frame(width: 18).padding(.top, 4)
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(mail.subject ?? "Bez předmětu").font(.system(size: 14, weight: mail.isRead ? .medium : .bold)).lineLimit(1)
                                                Spacer(minLength: 8)
                                                Text(Date.graph(mail.receivedDateTime)?.czech("HH:mm") ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                                            }
                                            HStack(spacing: 18) {
                                                Text(mail.from?.emailAddress.name ?? mail.from?.emailAddress.address ?? "Neznámý odesílatel").font(.system(size: 11)).lineLimit(1).frame(width: 125, alignment: .leading)
                                                Text(mail.bodyPreview ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }.padding(.vertical, 13).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
                HStack { LastUpdated(key: "mail"); Spacer(); Text(model.mailFilter == "flagged" && !model.usesExchange ? "Nejvýše 30 zpráv · celá schránka" : "Nejvýše 30 zpráv · Doručená pošta").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
        }
    }
}
