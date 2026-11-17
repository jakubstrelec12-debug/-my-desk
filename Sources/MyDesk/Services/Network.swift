import Foundation

final class Network: NSObject, URLSessionTaskDelegate {
    static let shared = Network()
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 25; c.timeoutIntervalForResource = 45
        c.urlCache = nil; c.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()
    // Never forward a Graph bearer token through an HTTP redirect.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if task.originalRequest?.value(forHTTPHeaderField: "Authorization") != nil || !["GET", "HEAD"].contains(task.originalRequest?.httpMethod ?? "GET") { completionHandler(nil) }
        else if request.url?.scheme == "https" { completionHandler(request) }
        else { completionHandler(nil) }
    }
    func data(_ request: URLRequest, maximumBytes: Int = 6_000_000) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.scheme == "https" else { throw DeskError("Datový zdroj musí používat HTTPS.") }
        // A streamed limit also protects against unbounded RSS responses.
        let (bytes, raw) = try await session.bytes(for: request)
        guard let response = raw as? HTTPURLResponse else { throw DeskError("Služba nevrátila HTTP odpověď.") }
        if response.expectedContentLength > Int64(maximumBytes) { throw DeskError("Odpověď služby je příliš velká.") }
        var data = Data(); data.reserveCapacity(min(maximumBytes, 65536))
        for try await byte in bytes {
            if data.count >= maximumBytes { throw DeskError("Odpověď služby překročila povolenou velikost.") }
            data.append(byte)
        }
        return (data, response)
    }
    func get(_ url: URL) async throws -> Data {
        let (data, r) = try await data(URLRequest(url: url))
        guard (200..<300).contains(r.statusCode) else { throw DeskError("Služba odpověděla HTTP \(r.statusCode). Zkus aktualizaci později.") }
        return data
    }
}
