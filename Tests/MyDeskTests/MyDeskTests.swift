import XCTest
import CryptoKit
@testable import MyDesk

final class MyDeskTests: XCTestCase {
    func testConfigurationRoundtripPreservesCustomerAndWidgetChoices() throws {
        var c = Configuration()
        c.customers[0].production = "https://erp.example.cz/srnin"
        c.customers[0].note = "VPN před přihlášením"
        c.visibleWidgets.remove("news")
        c.microsoft.sharedMail = true
        c.microsoft.mailboxes = ["shared@example.cz"]
        c.localTasks.append(.init(title: "Ověřit zálohu", completed: true))
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(restored.customers, c.customers)
        XCTAssertFalse(restored.visibleWidgets.contains("news"))
        XCTAssertTrue(restored.localTasks[0].completed)
        XCTAssertEqual(restored.microsoft.mailboxes, c.microsoft.mailboxes)
    }
    func testUnconfiguredCustomerURLsRemainEmpty() {
        XCTAssertTrue(Configuration().customers.allSatisfy { $0.production.isEmpty && $0.test.isEmpty })
        XCTAssertTrue(Configuration().projects.allSatisfy { $0.target.isEmpty })
    }
    func testRSSAndAtomMetadataAndUnsafeLinks() throws {
        let source = NewsSource(name: "Test", category: "Technologie", url: "https://example.cz/rss")
        let rss = """
        <rss version="2.0"><channel><item><title><![CDATA[Novinka & test]]></title>
        <link>https://example.cz/a?x=1&amp;y=2</link><pubDate>Tue, 17 Nov 2026 10:00:00 +0100</pubDate></item>
        <item><title>Spustit příkaz</title><link>javascript:alert(1)</link></item></channel></rss>
        """
        let items = try FeedParser(source: source).parse(Data(rss.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Novinka & test")
        XCTAssertEqual(items[0].url, "https://example.cz/a?x=1&y=2")
        XCTAssertNotNil(items[0].date)
        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Atom</title>
        <link rel="self" href="https://example.cz/metadata"/><link rel="alternate" href="https://example.cz/article"/>
        <updated>2026-11-17T09:00:00Z</updated></entry></feed>
        """
        let entries = try FeedParser(source: source).parse(Data(atom.utf8))
        XCTAssertEqual(entries.first?.url, "https://example.cz/article")
        XCTAssertEqual(entries.first?.category, "Technologie")
    }
    func testFeedLimitDoesNotReportValidLargeFeedAsError() throws {
        let source = NewsSource(name: "Test", category: "Sport", url: "https://example.cz/rss")
        let items = (0..<45).map { "<item><title>Článek \($0)</title><link>https://example.cz/\($0)</link></item>" }.joined()
        XCTAssertEqual(try FeedParser(source: source).parse(Data("<rss><channel>\(items)</channel></rss>".utf8)).count, 30)
        XCTAssertThrowsError(try FeedParser(source: source).parse(Data("<rss><item>".utf8)))
    }
    func testGraphUTCDateWithoutZoneAndSubseconds() throws {
        let expected = try XCTUnwrap(Date.graph("2026-11-17T08:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(Date.graph("2026-11-17T08:00:00.0000000")).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(Date.graph("2026-11-17T09:00:00+01:00")).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(Date.graph("není datum"))
    }
    func testURLValidationRejectsCredentialsAndExecutableSchemes() {
        for raw in ["javascript:alert(1)", "file:///etc/passwd", "https://user:pass@example.cz", "not a URL", "ms-excel:run"] { XCTAssertNil(SafeURL.web(raw)) }
        XCTAssertNotNil(SafeURL.web("http://intranet.local/eso9"))
        XCTAssertNil(SafeURL.secure("http://example.cz/rss"))
        XCTAssertNotNil(SafeURL.secure("https://example.cz/rss"))
    }
    @MainActor func testPKCEChallengeRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = MicrosoftAuth.base64(Data(SHA256.hash(data: Data(verifier.utf8))))
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testScopesRespectDisabledIntegrations() {
        var s = MicrosoftSettings(); s.mail = false; s.calendar = false
        XCTAssertEqual(s.scopes, ["offline_access", "User.Read"])
        s.tasks = true; s.mail = true; s.sharedMail = true
        XCTAssertTrue(s.scopes.contains("Tasks.ReadWrite"))
        XCTAssertTrue(s.scopes.contains("Mail.Read.Shared"))
        XCTAssertFalse(s.scopes.contains("Mail.Read"))
    }
    func testWeatherDecodesActualAPIShape() throws {
        let json = """
        {"current":{"temperature_2m":4.2,"weather_code":2,"is_day":1},"daily":{"time":["2026-11-17"],"weather_code":[2],"temperature_2m_max":[6.1],"temperature_2m_min":[0.4]}}
        """
        let report = try JSONDecoder().decode(WeatherReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.current.temperature_2m, 4.2)
        XCTAssertEqual(WeatherReport.description(report.current.weather_code), "Polojasno")
    }
}
