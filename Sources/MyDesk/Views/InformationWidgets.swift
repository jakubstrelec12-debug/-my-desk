import SwiftUI

@MainActor struct WeatherWidget: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        GlassPanel(title: model.location?.name ?? "Počasí", icon: "cloud.sun.fill", action: { model.settingsOpen = true }, actionTitle: "Lokalita") {
            VStack(alignment: .leading, spacing: 8) {
                ServiceStatus(key: "weather") { Task { await model.refreshWeather(force: true) } }
                if let weather = model.weather {
                    HStack(spacing: 20) {
                        Image(systemName: WeatherReport.symbol(weather.current.weather_code, day: weather.current.is_day == 1))
                            .symbolRenderingMode(.multicolor).font(.system(size: 58)).frame(width: 90)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Int(weather.current.temperature_2m.rounded())) °C").font(.system(size: 40, weight: .semibold))
                            Text(WeatherReport.description(weather.current.weather_code)).font(.system(size: 13))
                        }
                        Spacer(minLength: 0)
                    }
                    Divider()
                    HStack(spacing: 0) {
                        ForEach(Array(weather.daily.time.indices.dropFirst().prefix(5)), id: \.self) { i in
                            VStack(spacing: 6) {
                                Text(day(weather.daily.time[i])).font(.system(size: 11, weight: .semibold))
                                Image(systemName: WeatherReport.symbol(weather.daily.weather_code[i])).symbolRenderingMode(.multicolor).font(.system(size: 22))
                                Text("\(Int(weather.daily.temperature_2m_max[i].rounded()))°/\(Int(weather.daily.temperature_2m_min[i].rounded()))°").font(.system(size: 10)).monospacedDigit()
                            }.frame(maxWidth: .infinity)
                        }
                    }
                } else if !model.loading.contains("weather") {
                    EmptyWidget(symbol: "cloud", title: "Počasí není načtené", detail: "Ověř připojení k internetu a zvolenou lokalitu.", actionTitle: "Obnovit", action: { Task { await model.refreshWeather(force: true) } })
                }
                HStack { LastUpdated(key: "weather"); Spacer(); Link("Open-Meteo · CC BY 4.0", destination: URL(string: "https://open-meteo.com/")!).font(.system(size: 9)).foregroundStyle(.secondary) }
            }
        }
    }
    func day(_ raw: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)?.czech("EE").capitalized ?? raw
    }
}
@MainActor struct NewsWidget: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        GlassPanel(title: "Aktuální zprávy", icon: "newspaper", action: { model.settingsOpen = true }, actionTitle: "Zdroje") {
            VStack(alignment: .leading, spacing: 9) {
                Picker("Kategorie", selection: $model.category) {
                    ForEach(["Vše", "Česká republika", "Ekonomika", "Technologie", "Sport"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().controlSize(.small)
                ServiceStatus(key: "news") { Task { await model.refreshNews(force: true) } }
                if model.filteredArticles.isEmpty && !model.loading.contains("news") {
                    EmptyWidget(symbol: "newspaper", title: "Žádné načtené zprávy", detail: "Vyber jinou kategorii nebo uprav RSS zdroje.", actionTitle: "Obnovit", action: { Task { await model.refreshNews(force: true) } })
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.filteredArticles.prefix(30)) { article in
                                Button { model.open(article.url) } label: {
                                    HStack(alignment: .top, spacing: 11) {
                                        Image(systemName: symbol(article.category)).font(.system(size: 25)).foregroundStyle(color(article.category)).frame(width: 54, height: 48)
                                            .background(color(article.category).opacity(0.17), in: RoundedRectangle(cornerRadius: 7))
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(article.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                            Text("\(article.source) · \(article.category)\(article.date.map { " · " + $0.czech("d. M. HH:mm") } ?? "")").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(.vertical, 8).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
                LastUpdated(key: "news")
            }
        }
    }
    func symbol(_ category: String) -> String {
        switch category { case "Česká republika": return "building.columns"; case "Ekonomika": return "chart.line.uptrend.xyaxis"; case "Technologie": return "desktopcomputer"; default: return "figure.hockey" }
    }
    func color(_ category: String) -> Color {
        switch category { case "Česká republika": return .orange; case "Ekonomika": return .green; case "Technologie": return .purple; default: return .blue }
    }
}
@MainActor struct SystemWidget: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        GlassPanel(title: SystemMetrics.hardwareModel(), icon: "laptopcomputer", action: { model.section = "Nástroje" }, actionTitle: "Stav systému") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ring(model.metrics.battery, title: "Baterie", symbol: model.metrics.charging ? "battery.100.bolt" : "battery.100", color: .green)
                    ring(model.metrics.memory, title: "RAM", symbol: "memorychip", color: .blue)
                    ring(model.metrics.cpu, title: "CPU", symbol: "cpu", color: .purple)
                    ring(model.metrics.disk, title: "Disk", symbol: "internaldrive", color: .gray)
                }
                Canvas { context, size in
                    guard model.history.count > 1 else { return }
                    var path = Path()
                    for (i, value) in model.history.enumerated() {
                        let point = CGPoint(x: Double(i) / Double(model.history.count - 1) * size.width, y: (1 - value) * (size.height - 3) + 1)
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .linearGradient(Gradient(colors: [.blue, .purple]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)), lineWidth: 1.6)
                }.frame(height: 40)
                Text(model.history.count < 2 ? "CPU: čekám na další měření…" : "CPU · posledních \(model.history.count) měření").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
    func ring(_ value: Double?, title: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(value ?? 0)).stroke(color.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(color)
            }.frame(maxWidth: 62).aspectRatio(1, contentMode: .fit)
            Text(value.map { "\(Int(($0 * 100).rounded())) %" } ?? "—").font(.system(size: 19, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 11))
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
}
@MainActor struct CustomerCenter: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        GlassPanel(title: "Zákaznická prostředí ESO9", icon: "square.3.layers.3d", orange: true, action: { model.settingsOpen = true }, actionTitle: "Spravovat") {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Přístup přes obecného klienta v prohlížeči. Produkční a testovací prostředí jsou oddělená.").font(.callout).foregroundStyle(.secondary)
                    ForEach(prefs.config.customers.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) }) { customer in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Image(systemName: "building.2").foregroundStyle(.orange); Text(customer.name).font(.headline); Spacer(); if customer.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) } }
                            HStack {
                                Button("Produkce") { model.open(customer.production) }.disabled(customer.production.isEmpty)
                                Button("Test") { model.open(customer.test) }.disabled(customer.test.isEmpty)
                                Button("Dokumentace") { model.open(customer.documentation) }.disabled(customer.documentation.isEmpty)
                            }.buttonStyle(.bordered)
                            if customer.production.isEmpty { Text("Doplň zákaznické URL v nastavení.").font(.caption).foregroundStyle(.orange) }
                            if !customer.note.isEmpty { Text(customer.note).font(.callout).textSelection(.enabled) }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("ESO9 Správce: správa probíhá ve Windows. Vyber soubor .rdp pro Windows App nebo jiný soubor vzdáleného připojení. Přihlašování obsluhuje vzdálený klient.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
@MainActor struct ProjectsCenter: View {
    @EnvironmentObject var model: DeskModel
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        GlassPanel(title: "Projekty a pracovní odkazy", icon: "folder", action: { model.settingsOpen = true }, actionTitle: "Spravovat") {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(prefs.config.projects.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) }) { project in
                        Button { model.open(project.target) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "folder.fill").foregroundStyle(.blue).font(.system(size: 30))
                                VStack(alignment: .leading, spacing: 5) { Text(project.name).font(.headline); Text(project.target.isEmpty ? "Vyber složku nebo doplň URL v nastavení" : project.target).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                Spacer(); Image(systemName: "arrow.up.right")
                            }.padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
@MainActor struct ToolsCenter: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        GlassPanel(title: "Nástroje a stav systému", icon: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(SystemMetrics.hardwareModel()) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)").font(.headline)
                Text("RAM: aktivní + zapojená + komprimovaná paměť vůči fyzické RAM. CPU: rozdíl systémových čítačů mezi měřeními. Disk: obsazenost svazku domovské složky; dostupné místo zahrnuje prostor uvolnitelný systémem.").font(.callout).foregroundStyle(.secondary)
                Text("Údaje se mohou lišit od Monitoru aktivity a Nastavení systému, které používají jiné definice paměti a dostupného úložiště.").font(.caption).foregroundStyle(.secondary)
                Button("Otevřít Monitor aktivity") { model.launch(.init(name: "Monitor aktivity", bundleID: "com.apple.ActivityMonitor")) }
                Button("Otevřít Terminál") { model.launch(.init(name: "Terminál", bundleID: "com.apple.Terminal")) }
                Button("Otevřít domovskou složku") { model.open(NSHomeDirectory()) }
                Button("Nastavení MY DESK") { model.settingsOpen = true }
                Spacer()
                Text("Přístup k síti je omezen na požadované integrace. MY DESK nespouští shellové příkazy z uložených odkazů, nevytěžuje obsah článků a neukládá poštu na disk.").font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.bordered)
        }
    }
}
