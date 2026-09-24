import Foundation

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirects()
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum LocalAnisetteTransport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: NoRedirects.shared, delegateQueue: nil)
    }()
    static func validate(_ url: URL?) throws {
        guard let url, ["http", "https"].contains(url.scheme ?? ""),
              ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw "Privacy protection: Anisette must use a numeric loopback address (127.0.0.1 or ::1). Public servers receive provisioning secrets and are blocked. Run a local V3 service or a tunnel to your own computer."
        }
    }
    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw "Anisette provisioning HTTP request failed. No headers were accepted."
        }
    }
}
