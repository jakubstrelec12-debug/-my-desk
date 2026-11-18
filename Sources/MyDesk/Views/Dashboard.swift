import SwiftUI
import AppKit

@MainActor struct Dashboard: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var auth: MicrosoftAuth
    var body: some View {
        ZStack {
            DeskBackground()
            VStack(spacing: 14) {
                header.padding(.horizontal, 24).padding(.top, 12)
                GeometryReader { geo in
                    ScrollView([.vertical, .horizontal]) {
                        let width = max(1200, geo.size.width - 48)
                        HStack(alignment: .top, spacing: 14) {
                            leftColumn.frame(width: (width - 28) * 0.245)
                            centerColumn.frame(width: (width - 28) * 0.485)
                            rightColumn.frame(width: (width - 28) * 0.270)
                        }.frame(width: width, alignment: .topLeading).padding(.horizontal, 24).padding(.bottom, 24)
                    }
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 730)
        .tint(.orange)
        .onAppear { model.start() }
        .sheet(isPresented: $model.settingsOpen) { SettingsView().frame(width: 950, height: 690) }
        .alert("MY DESK", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) { Button("Rozumím") { model.alert = nil } } message: { Text(model.alert ?? "") }
        .overlay(alignment: .bottom) {
            if let error = prefs.persistenceError { Text(error).padding().background(.red, in: RoundedRectangle(cornerRadius: 12)).padding() }
        }
    }
    private func visible(_ key: String) -> Bool { prefs.config.visibleWidgets.contains(key) }
    private var header: some View {
        HStack(spacing: 21) {
            HStack(spacing: 11) {
                Image(systemName: "cube.transparent").font(.system(size: 30, weight: .light)).foregroundStyle(.cyan).shadow(color: .purple, radius: 5)
                Text("MY DESK").font(.system(size: 25, weight: .bold)).tracking(0.5).foregroundStyle(.white)
            }.padding(.trailing, 20)
            ForEach([("Přehled", "house.fill"), ("ESO9", "square.3.layers.3d"), ("Projekty", "folder"), ("Kalendář", "calendar"), ("Nástroje", "square.grid.2x2")], id: \.0) { tab in
                Button { model.section = tab.0 } label: {
                    Label(tab.0, systemImage: tab.1).font(.system(size: 14, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 11)
                        .background(model.section == tab.0 ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Hledat v aplikacích, e-mailech, projektech…", text: $model.search).textFieldStyle(.plain).font(.system(size: 12))
            }.foregroundStyle(.white.opacity(0.9)).padding(10).frame(minWidth: 140, maxWidth: 300).background(.white.opacity(0.12), in: Capsule())
            Button { Task { await model.refreshAll() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 20)) }.help("Obnovit všechny widgety")
            Button { model.settingsOpen = true } label: { Image(systemName: "gearshape").font(.system(size: 23)) }.help("Nastavení ⌘,")
            Menu {
                Text(model.profile?.displayName ?? "Microsoft není připojen")
                Button("Nastavení účtu") { model.settingsOpen = true }
                Button("Skrýt do menu baru") { NSApp.hide(nil) }
                Button("Celá obrazovka") { NSApp.keyWindow?.toggleFullScreen(nil) }
            } label: { Image(systemName: "person.crop.circle.fill").font(.system(size: 31)) }.menuStyle(.borderlessButton).fixedSize()
        }.buttonStyle(.plain).foregroundStyle(.white)
    }
    @ViewBuilder private var leftColumn: some View {
        VStack(spacing: 14) {
            if visible("greeting") { GreetingWidget().frame(height: 120) }
            if visible("launcher") {
                GlassPanel(title: "Rychlé spuštění", icon: "paperplane", action: { model.settingsOpen = true }, actionTitle: "Upravit") {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                            ForEach(prefs.config.apps.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) }) { AppTile(app: $0) }
                            Button { prefs.chooseApp() } label: { VStack(spacing: 6) { Image(systemName: "plus.app.fill").font(.system(size: 35)); Text("Přidat").font(.system(size: 11)) }.frame(maxWidth: .infinity) }.buttonStyle(.plain)
                        }
                    }
                }.frame(height: 198)
            }
            if visible("eso9") { ESO9Widget().frame(height: 225) }
            if visible("projects") { ProjectsWidget().frame(height: 190) }
        }
    }
    @ViewBuilder private var centerColumn: some View {
        switch model.section {
        case "ESO9": CustomerCenter().frame(height: 775)
        case "Projekty": ProjectsCenter().frame(height: 775)
        case "Nástroje": ToolsCenter().frame(height: 775)
        default:
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    if visible("calendar") { CalendarWidget().frame(maxWidth: .infinity).frame(height: model.section == "Kalendář" ? 525 : 330) }
                    if visible("tasks") { TasksWidget().frame(maxWidth: .infinity).frame(height: model.section == "Kalendář" ? 525 : 330) }
                }
                if visible("mail") { MailWidget().frame(height: model.section == "Kalendář" ? 236 : 431) }
            }
        }
    }
    private var rightColumn: some View {
        VStack(spacing: 14) {
            if visible("weather") { WeatherWidget().frame(height: 230) }
            if visible("news") { NewsWidget().frame(height: 285) }
            if visible("system") { SystemWidget().frame(height: 232) }
        }
    }
}
@MainActor struct GreetingWidget: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var model: DeskModel
    var body: some View {
        HStack(spacing: 14) {
            Image("Mountains", bundle: .deskResources).resizable().scaledToFill().frame(width: 83, height: 89).clipShape(Circle()).overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(salutation(context.date)), \(prefs.config.displayName)!").font(.system(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(context.date.czech("EEEE d. MMMM yyyy")).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Text(context.date.czech("HH:mm")).font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                        Spacer(minLength: 0)
                        if let w = model.weather {
                            Image(systemName: WeatherReport.symbol(w.current.weather_code, day: w.current.is_day == 1)).foregroundStyle(.yellow)
                            Text("\(Int(w.current.temperature_2m.rounded()))°").font(.system(size: 15))
                        }
                    }
                }
            }
        }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.3), lineWidth: 0.8))
    }
    func salutation(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) { case 5..<11: return "Dobré ráno"; case 11..<18: return "Dobrý den"; default: return "Dobrý večer" }
    }
}
