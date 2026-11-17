import SwiftUI
import AppKit

@MainActor struct GlassPanel<Content: View>: View {
    @EnvironmentObject var prefs: Preferences
    @Environment(\.colorScheme) var scheme
    var title: String
    var icon: String
    var orange = false
    var action: (() -> Void)?
    var actionTitle: String = ""
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                if orange {
                    Text("eso").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 45, height: 33).background(.orange.gradient, in: RoundedRectangle(cornerRadius: 9))
                } else { Image(systemName: icon).font(.system(size: 23, weight: .regular)).foregroundStyle(icon == "star.fill" ? Color.yellow : .primary) }
                Text(title).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if let action {
                    Button(action: action) {
                        if actionTitle.isEmpty { Image(systemName: "plus.circle.fill").font(.system(size: 24)).symbolRenderingMode(.hierarchical) }
                        else { Text(actionTitle).font(.system(size: 11, weight: .medium)); Image(systemName: "chevron.right").font(.system(size: 10)) }
                    }.buttonStyle(.plain).help(actionTitle.isEmpty ? "Přidat" : actionTitle)
                }
            }
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 17).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 17).fill(
                LinearGradient(colors: scheme == .dark ? [Color(red: 0.17, green: 0.23, blue: 0.37).opacity(prefs.config.opacity), Color(red: 0.08, green: 0.13, blue: 0.23).opacity(prefs.config.opacity)] : [Color.white.opacity(0.9), Color(red: 0.85, green: 0.89, blue: 0.97).opacity(0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if orange {
                RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: [.orange.opacity(0.24), .clear, .clear], startPoint: .topTrailing, endPoint: .bottomLeading))
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(orange ? Color.orange.opacity(0.95) : Color.white.opacity(scheme == .dark ? 0.27 : 0.65), lineWidth: orange ? 1.8 : 0.8) }
        .shadow(color: orange ? .orange.opacity(0.12) : .black.opacity(0.23), radius: 14, y: 7)
    }
}
@MainActor struct EmptyWidget: View {
    var symbol = "link.badge.plus"
    let title: String
    let detail: String
    var actionTitle = "Nastavit"
    var action: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let action { Button(actionTitle, action: action).buttonStyle(.bordered).controlSize(.small) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
@MainActor struct ServiceStatus: View {
    @EnvironmentObject var model: DeskModel
    let key: String
    var retry: () -> Void
    var body: some View {
        if let error = model.errors[key] {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(3).help(error)
                Spacer(minLength: 0)
                Button(action: retry) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Zkusit znovu")
            }.font(.system(size: 11)).padding(8).background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        } else if model.loading.contains(key) {
            HStack { ProgressView().controlSize(.mini); Text("Načítám…").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
@MainActor struct LastUpdated: View {
    @EnvironmentObject var model: DeskModel
    let key: String
    var body: some View {
        if let date = model.updated[key] {
            Text("Aktualizováno \(date.czech("HH:mm"))\(model.errors[key] == nil ? "" : " · starší data")").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
@MainActor struct DeskBackground: View {
    var body: some View {
        GeometryReader { geo in
            Image("Mountains", bundle: .module).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
            LinearGradient(colors: [.black.opacity(0.05), Color(red: 0.03, green: 0.07, blue: 0.16).opacity(0.38)], startPoint: .top, endPoint: .bottom)
        }.ignoresSafeArea()
    }
}
@MainActor struct AppTile: View {
    @EnvironmentObject var model: DeskModel
    let app: LaunchItem
    var body: some View {
        Button { model.launch(app) } label: {
            VStack(spacing: 5) {
                if let url = Launcher.appURL(app) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high).frame(width: 45, height: 45)
                } else if app.name == "ESO9" {
                    Text("eso").font(.system(size: 25, weight: .bold)).foregroundStyle(.white).frame(width: 43, height: 43).background(.orange.gradient, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "app.dashed").font(.system(size: 30)).foregroundStyle(.secondary).frame(width: 45, height: 45)
                }
                Text(app.name).font(.system(size: 11)).lineLimit(1)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Spustit \(app.name)")
    }
}
