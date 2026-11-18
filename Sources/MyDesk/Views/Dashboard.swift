import SwiftUI
import AppKit

@MainActor struct Dashboard: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var auth: MicrosoftAuth
    var body: some View {
        GeometryReader { geo in
            let layout = DashboardLayout(width: geo.size.width, height: geo.size.height, mode: prefs.config.dashboardLayout ?? "auto")
            ZStack {
                DeskBackground()
                VStack(spacing: layout.gap) {
                    header(layout).frame(height: layout.headerHeight)
                    ScrollView(.vertical) {
                        board(layout).padding(.bottom, 2)
                    }
                }.padding(layout.inset)
            }
            .environment(\.compactDashboard, layout.compact)
            .sheet(isPresented: $model.settingsOpen) {
                SettingsView().frame(width: min(950, max(480, geo.size.width - 32)), height: min(690, max(420, geo.size.height - 40)))
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .tint(.orange)
        .onAppear { model.start() }
        .alert("MY DESK", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) { Button("Rozumím") { model.alert = nil } } message: { Text(model.alert ?? "") }
        .overlay(alignment: .bottom) {
            if let error = prefs.persistenceError { Text(error).padding().background(.red, in: RoundedRectangle(cornerRadius: 12)).padding() }
        }
    }
    @ViewBuilder private func board(_ layout: DashboardLayout) -> some View {
        if layout.columns == 3 {
            HStack(alignment: .top, spacing: layout.gap) {
                leftColumn(layout).frame(width: layout.leftWidth)
                centerColumn(layout).frame(width: layout.centerWidth)
                rightColumn(layout).frame(width: layout.rightWidth)
            }
        } else if layout.columns == 2 {
            VStack(spacing: layout.gap) {
                HStack(alignment: .top, spacing: layout.gap) {
                    leftColumn(layout).frame(width: layout.leftWidth)
                    centerColumn(layout).frame(width: layout.centerWidth)
                }
                rightColumn(layout, horizontal: true)
            }
        } else {
            VStack(spacing: layout.gap) {
                centerColumn(layout)
                leftColumn(layout)
                rightColumn(layout)
            }
        }
    }
    private func visible(_ key: String) -> Bool { prefs.config.visibleWidgets.contains(key) }
    private func header(_ layout: DashboardLayout) -> some View {
        HStack(spacing: layout.compact ? 8 : 16) {
            HStack(spacing: layout.compact ? 6 : 11) {
                Image(systemName: "cube.transparent").font(.system(size: layout.compact ? 25 : 30, weight: .light)).foregroundStyle(.cyan).shadow(color: .purple, radius: 5)
                Text("MY DESK").font(.system(size: layout.compact ? 19 : 25, weight: .bold)).tracking(0.5).foregroundStyle(.white).lineLimit(1).fixedSize()
            }.padding(.trailing, layout.compact ? 4 : 12).fixedSize()
            if layout.width < 760 {
                Menu {
                    ForEach(navigation, id: \.0) { tab in Button { model.section = tab.0 } label: { Label(tab.0, systemImage: tab.1) } }
                } label: { Label(model.section, systemImage: "line.3.horizontal").lineLimit(1) }
                .menuStyle(.borderlessButton).frame(maxWidth: 140)
            } else {
                ForEach(navigation, id: \.0) { tab in
                    Button { model.section = tab.0 } label: {
                        Group {
                            if layout.width < 1100 { Image(systemName: tab.1).frame(width: 26) }
                            else { Label(tab.0, systemImage: tab.1) }
                        }
                        .font(.system(size: layout.compact ? 13 : 14, weight: .medium))
                        .padding(.horizontal, layout.compact ? 8 : 12).padding(.vertical, 9)
                        .background(model.section == tab.0 ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).foregroundStyle(.white).help(tab.0).accessibilityLabel(tab.0)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                TextField("Hledat…", text: $model.search).textFieldStyle(.plain).font(.system(size: 12))
            }.foregroundStyle(.white.opacity(0.9)).padding(layout.compact ? 8 : 10)
                .frame(width: layout.width < 760 ? 100 : layout.compact ? 155 : 220).background(.white.opacity(0.12), in: Capsule())
            Menu {
                Picker("Rozložení", selection: Binding(get: { prefs.config.dashboardLayout ?? "auto" }, set: { prefs.config.dashboardLayout = $0 })) {
                    Text("Automatické").tag("auto")
                    Text("Kompaktní · tablet").tag("compact")
                    Text("Prostorné").tag("comfortable")
                }
                Button("Celá obrazovka") { NSApp.keyWindow?.toggleFullScreen(nil) }
            } label: { Image(systemName: "rectangle.split.3x1").font(.system(size: 19)) }
                .menuStyle(.borderlessButton).fixedSize().help("Rozložení a celá obrazovka")
            Button { Task { await model.refreshAll() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 20)) }.help("Obnovit všechny widgety")
            Button { model.settingsOpen = true } label: { Image(systemName: "gearshape").font(.system(size: 23)) }.help("Nastavení ⌘,")
            Menu {
                Text(model.profile?.displayName ?? "E-mail není připojen")
                Button("Nastavení účtu") { model.settingsOpen = true }
                Button("Skrýt do menu baru") { NSApp.hide(nil) }
                Button("Celá obrazovka") { NSApp.keyWindow?.toggleFullScreen(nil) }
            } label: { Image(systemName: "person.crop.circle.fill").font(.system(size: 31)) }.menuStyle(.borderlessButton).fixedSize()
        }.buttonStyle(.plain).foregroundStyle(.white)
    }
    private var navigation: [(String, String)] {
        [("Přehled", "house.fill"), ("ESO9", "square.3.layers.3d"), ("Projekty", "folder"), ("Kalendář", "calendar"), ("Nástroje", "square.grid.2x2")]
    }
    @ViewBuilder private func leftColumn(_ layout: DashboardLayout) -> some View {
        let weights: [(String, CGFloat)] = [("greeting", 0.16), ("launcher", 0.25), ("eso9", 0.33), ("projects", 0.26)]
        VStack(spacing: layout.gap) {
            if visible("greeting") { GreetingWidget().frame(height: layout.panelHeight("greeting", weights: weights, visible: prefs.config.visibleWidgets)) }
            if visible("launcher") {
                GlassPanel(title: "Rychlé spuštění", icon: "paperplane", action: { model.settingsOpen = true }, actionTitle: "Upravit") {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: layout.compact ? 6 : 10) {
                            ForEach(prefs.config.apps.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) }) { AppTile(app: $0) }
                            Button { prefs.chooseApp() } label: {
                                VStack(spacing: 4) { Image(systemName: "plus.app.fill").font(.system(size: layout.compact ? 30 : 35)); Text("Přidat").font(.system(size: 10)) }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(height: layout.panelHeight("launcher", weights: weights, visible: prefs.config.visibleWidgets))
            }
            if visible("eso9") { ESO9Widget().frame(height: layout.panelHeight("eso9", weights: weights, visible: prefs.config.visibleWidgets)) }
            if visible("projects") { ProjectsWidget().frame(height: layout.panelHeight("projects", weights: weights, visible: prefs.config.visibleWidgets)) }
        }
    }
    @ViewBuilder private func centerColumn(_ layout: DashboardLayout) -> some View {
        switch model.section {
        case "ESO9": CustomerCenter().frame(height: layout.contentHeight)
        case "Projekty": ProjectsCenter().frame(height: layout.contentHeight)
        case "Nástroje": ToolsCenter().frame(height: layout.contentHeight)
        default:
            let topVisible = visible("calendar") || visible("tasks")
            let topHeight = visible("mail") ? (layout.contentHeight - layout.gap) * (model.section == "Kalendář" ? 0.66 : 0.39) : layout.contentHeight
            VStack(spacing: layout.gap) {
                if topVisible {
                    HStack(alignment: .top, spacing: layout.gap) {
                        if visible("calendar") { CalendarWidget().frame(maxWidth: .infinity).frame(height: topHeight) }
                        if visible("tasks") { TasksWidget().frame(maxWidth: .infinity).frame(height: topHeight) }
                    }
                }
                if visible("mail") { MailWidget().frame(height: topVisible ? layout.contentHeight - topHeight - layout.gap : layout.contentHeight) }
            }
        }
    }
    @ViewBuilder private func rightColumn(_ layout: DashboardLayout, horizontal: Bool = false) -> some View {
        let weights: [(String, CGFloat)] = [("weather", 0.36), ("news", 0.37), ("system", 0.27)]
        if horizontal {
            HStack(alignment: .top, spacing: layout.gap) {
                if visible("weather") { WeatherWidget().frame(maxWidth: .infinity) }
                if visible("news") { NewsWidget().frame(maxWidth: .infinity) }
                if visible("system") { SystemWidget().frame(maxWidth: .infinity) }
            }.frame(height: 240)
        } else {
            VStack(spacing: layout.gap) {
                if visible("weather") { WeatherWidget().frame(height: layout.panelHeight("weather", weights: weights, visible: prefs.config.visibleWidgets)) }
                if visible("news") { NewsWidget().frame(height: layout.panelHeight("news", weights: weights, visible: prefs.config.visibleWidgets)) }
                if visible("system") { SystemWidget().frame(height: layout.panelHeight("system", weights: weights, visible: prefs.config.visibleWidgets)) }
            }
        }
    }

}
@MainActor struct GreetingWidget: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var model: DeskModel
    @Environment(\.compactDashboard) var compact
    var body: some View {
        HStack(spacing: compact ? 8 : 14) {
            if !compact { Image("Mountains", bundle: .deskResources).resizable().scaledToFill().frame(width: 70, height: 76).clipShape(Circle()).overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1)) }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(salutation(context.date)), \(prefs.config.displayName)!").font(.system(size: compact ? 14 : 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(context.date.czech("EEEE d. MMMM yyyy")).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Text(context.date.czech("HH:mm")).font(.system(size: compact ? 29 : 36, weight: .medium, design: .rounded)).monospacedDigit()
                        Spacer(minLength: 0)
                        if let w = model.weather {
                            Image(systemName: WeatherReport.symbol(w.current.weather_code, day: w.current.is_day == 1)).foregroundStyle(.yellow)
                            Text("\(Int(w.current.temperature_2m.rounded()))°").font(.system(size: 15))
                        }
                    }
                }
            }
        }.padding(compact ? 11 : 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.3), lineWidth: 0.8))
    }
    func salutation(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) { case 5..<11: return "Dobré ráno"; case 11..<18: return "Dobrý den"; default: return "Dobrý večer" }
    }
}
