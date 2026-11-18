import XCTest
import Foundation
@testable import MyDesk

final class ExchangeTests: XCTestCase {
    func settings() -> ExchangeSettings {
        var s = ExchangeSettings(); s.endpoint = "https://mail.example.test/EWS/Exchange.asmx"
        s.username = "test@example.test"; s.email = s.username
        return s
    }
    func testExistingSettingsMigrateWithoutLosingUserData() throws {
        var c = Configuration(); c.displayName = "Původní uživatel"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
        json.removeValue(forKey: "exchange")
        let migrated = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(migrated.exchange); XCTAssertEqual(migrated.displayName, c.displayName)
        c.exchange = settings()
        let saved = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertFalse(saved.contains("password"))
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: Data(saved.utf8)).exchange, c.exchange)
    }
    func testEndpointValidationAndWebmailLinksDoNotLeakCredentials() throws {
        var s = settings()
        XCTAssertEqual(try s.validatedURL().host, "mail.example.test")
        for raw in ["http://mail.example.test/EWS", "https://u:p@mail.example.test/EWS", "https://mail.example.test/EWS?password=x", "https://mail.example.test/EWS#x", "file:///EWS"] {
            s.endpoint = raw; XCTAssertThrowsError(try s.validatedURL())
        }
        let id = "A+B/= &?é"
        let url = try XCTUnwrap(URLComponents(string: EWSResponse.link(webmail: settings().webmail, id: id)!))
        XCTAssertEqual(url.host, "mail.example.test")
        XCTAssertEqual(url.queryItems?.first(where: { $0.name == "ItemID" })?.value, id)
    }
    func testNamespacedMailAndCalendarResponses() throws {
        let xml = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages" xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"><s:Body><m:FindItemResponse><m:ResponseMessages><m:FindItemResponseMessage ResponseClass="Success"><m:ResponseCode>NoError</m:ResponseCode><m:RootFolder><t:Items>
        <t:Message><t:ItemId Id="A+B/="/><t:Subject>Zakázka &amp; servis</t:Subject><t:DateTimeReceived>2026-11-18T08:00:00Z</t:DateTimeReceived><t:From><t:Mailbox><t:Name>Žluťoučký</t:Name><t:EmailAddress>sender@example.test</t:EmailAddress></t:Mailbox></t:From><t:Preview>Český náhled</t:Preview><t:IsRead>false</t:IsRead><t:Flag><t:FlagStatus>Flagged</t:FlagStatus></t:Flag></t:Message>
        <t:CalendarItem><t:ItemId Id="event1"/><t:Subject>Schůzka</t:Subject><t:Start>2026-11-18T09:00:00Z</t:Start><t:End>2026-11-18T10:00:00Z</t:End><t:IsAllDayEvent>false</t:IsAllDayEvent></t:CalendarItem>
        </t:Items></m:RootFolder></m:FindItemResponseMessage></m:ResponseMessages></m:FindItemResponse></s:Body></s:Envelope>
        """
        let response = try EWSResponse(Data(xml.utf8)); try response.check()
        let message = try XCTUnwrap(response.messages(webmail: settings().webmail).first)
        XCTAssertEqual(message.subject, "Zakázka & servis"); XCTAssertFalse(message.isRead)
        XCTAssertEqual(message.flag?.flagStatus, "flagged"); XCTAssertEqual(message.from?.emailAddress.name, "Žluťoučký")
        XCTAssertEqual(message.bodyPreview, "Český náhled")
        let event = try XCTUnwrap(response.events(webmail: settings().webmail).first)
        XCTAssertNotNil(Date.graph(event.start.dateTime)); XCTAssertEqual(event.subject, "Schůzka")
        XCTAssertEqual(event.isAllDay, false)
    }
    func testSOAPErrorsAndHTMLAreNotReportedAsSuccessfulEmptyMailbox() throws {
        for xml in ["<html><body>Login</body></html>", "<Response><ResponseCode>ErrorAccessDenied</ResponseCode></Response>", "<Envelope><Fault><faultstring>Internal failure</faultstring></Fault></Envelope>"] {
            let response = try EWSResponse(Data(xml.utf8)); XCTAssertThrowsError(try response.check())
        }
        XCTAssertThrowsError(try EWSResponse(Data("<!DOCTYPE x [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><x>&secret;</x>".utf8)))
        XCTAssertThrowsError(try EWSResponse(Data("<broken>".utf8)))
    }
    func testFiltersAndRecurrenceWindowAreIncludedInSOAP() throws {
        let unread = String(decoding: ExchangeService.envelope(ExchangeService.mailOperation(filter: "unread")), as: UTF8.self)
        XCTAssertTrue(unread.contains("message:IsRead")); XCTAssertTrue(unread.contains("Value=\"false\""))
        XCTAssertTrue(unread.contains("MaxEntriesReturned=\"30\""))
        let flagged = ExchangeService.mailOperation(filter: "flagged")
        XCTAssertTrue(flagged.contains("0x1090")); XCTAssertTrue(flagged.contains("Value=\"2\""))
        let start = try XCTUnwrap(Date.graph("2026-11-18T00:00:00Z"))
        let calendar = ExchangeService.calendarOperation(start: start, end: start.addingTimeInterval(604800))
        XCTAssertTrue(calendar.contains("CalendarView")); XCTAssertTrue(calendar.contains("2026-11-25T00:00:00Z"))
    }
    func testTransportRejectsRedirectEvenToSameHost() throws {
        let url = try settings().validatedURL()
        let transport = ExchangeTransport(endpoint: url, username: "test", password: "test-only", authentication: "basic")
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://other.example.test/"]))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        var called = false
        transport.urlSession(session, task: task, willPerformHTTPRedirection: response,
                             newRequest: URLRequest(url: URL(string: "https://other.example.test/")!)) { redirected in
            called = true; XCTAssertNil(redirected)
        }
        XCTAssertTrue(called)
    }
    func testFailedAuthenticationStopsAutomaticRetries() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeniedExchangeProtocol.self]
        let service = try ExchangeService(settings: settings(), password: "test-only", configuration: configuration)
        DeniedExchangeProtocol.requests = 0
        for _ in 0..<2 {
            do { _ = try await service.unreadCount(); XCTFail("401 must fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains("přihlášení")) }
        }
        XCTAssertEqual(DeniedExchangeProtocol.requests, 1)
    }
}
private final class DeniedExchangeProtocol: URLProtocol {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("test@example.test:test-only".utf8).base64EncodedString())
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
