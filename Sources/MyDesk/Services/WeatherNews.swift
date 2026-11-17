import Foundation

struct WeatherService {
    static func load(_ location: WeatherLocation) async throws -> WeatherReport {
        guard (-90...90).contains(location.latitude), (-180...180).contains(location.longitude) else { throw DeskError("Neplatné souřadnice lokality.") }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = ["latitude": String(location.latitude), "longitude": String(location.longitude),
            "current": "temperature_2m,weather_code,is_day", "daily": "weather_code,temperature_2m_max,temperature_2m_min",
            "timezone": "auto", "forecast_days": "6"].map { URLQueryItem(name: $0.key, value: $0.value) }
        let report = try JSONDecoder().decode(WeatherReport.self, from: await Network.shared.get(c.url!))
        let count = report.daily.time.count
        guard count > 0, count <= 16, report.daily.weather_code.count == count,
              report.daily.temperature_2m_max.count == count, report.daily.temperature_2m_min.count == count else {
            throw DeskError("Meteorologický zdroj vrátil neúplnou předpověď.")
        }
        return report
    }
    struct Search: Decodable {
        struct Place: Decodable, Identifiable {
            let id: Int; let name: String; let latitude: Double; let longitude: Double; let country: String?; let admin1: String?
        }
        let results: [Place]?
    }
    static func search(_ name: String) async throws -> [Search.Place] {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "8"), .init(name: "language", value: "cs")]
        return try JSONDecoder().decode(Search.self, from: await Network.shared.get(c.url!)).results ?? []
    }
}

// RSS 2.0 and Atom. Only headlines and original links are retained; no article scraping.
final class FeedParser: NSObject, XMLParserDelegate {
    private var items: [Article] = []
    private var current: Article?
    private var element = ""
    private var textValue = ""
    private let source: NewsSource
    private var depth = 0
    private var itemDepth = 0
    init(source: NewsSource) { self.source = source }
    func parse(_ data: Data) throws -> [Article] {
        let parser = XMLParser(data: data); parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw DeskError("Zdroj \(source.name) nevrátil platný RSS/Atom dokument.") }
        return items
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        depth += 1
        let tag = elementName.lowercased()
        if tag == "item" || tag == "entry" {
            current = Article(title: "", url: "", category: source.category, source: source.name); itemDepth = depth
        }
        element = tag; textValue = ""
        if tag == "link", current != nil, let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate" {
            current?.url = href
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { textValue += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { textValue += String(data: CDATABlock, encoding: .utf8) ?? "" }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { depth -= 1 }
        guard current != nil else { return }
        let value = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Read item metadata, never image titles nested in media tags.
        if depth == itemDepth + 1 {
            switch elementName.lowercased() {
            case "title": current?.title = value
            case "link": if !value.isEmpty { current?.url = value }
            case "pubdate", "published", "updated", "dc:date": current?.date = Self.date(value)
            default: break
            }
        }
        if elementName.lowercased() == "item" || elementName.lowercased() == "entry" {
            if let item = current, !item.title.isEmpty, SafeURL.web(item.url) != nil { if items.count < 30 { items.append(item) } }
            current = nil
        }
        textValue = ""
    }
    static func date(_ raw: String) -> Date? {
        if let date = Date.graph(raw) { return date }
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z"] {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format
            if let date = f.date(from: raw) { return date }
        }
        return nil
    }
}
struct NewsResult { var articles: [Article]; var errors: [String] }
struct NewsService {
    static func load(_ sources: [NewsSource]) async -> NewsResult {
        await withTaskGroup(of: NewsResult.self) { group in
            for source in sources.filter(\.enabled).prefix(16) {
                group.addTask {
                    do {
                        guard let url = SafeURL.secure(source.url) else { throw DeskError("RSS \(source.name): nastav platnou HTTPS adresu.") }
                        let data = try await Network.shared.get(url)
                        return NewsResult(articles: try FeedParser(source: source).parse(data), errors: [])
                    } catch { return NewsResult(articles: [], errors: ["\(source.name) (\(source.category)): \(error.localizedDescription)"]) }
                }
            }
            var result = NewsResult(articles: [], errors: [])
            for await partial in group { result.articles += partial.articles; result.errors += partial.errors }
            var seen = Set<String>()
            result.articles = result.articles.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.filter { seen.insert($0.url).inserted }
            return result
        }
    }
}
