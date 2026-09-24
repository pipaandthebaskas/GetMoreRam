import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authentication material may only leave the device for these Apple endpoints.
public final class AppleTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var transport: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public static func permits(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil &&
        (url.port == nil || url.port == 443) &&
        ["gsa.apple.com", "developerservices2.apple.com"].contains(url.host?.lowercased() ?? "")
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, Self.permits(url) else { throw AppleAPIError.invalidParameters }
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppleAPIError.badServerResponse }
        // Validate error envelopes before returning even when the HTTP status is 2xx.
        let object = (try? JSONSerialization.jsonObject(with: data)) ??
                     (try? PropertyListSerialization.propertyList(from: data, format: nil))
        try Self.validate(status: http.statusCode, body: object as? [String: Any])
        return (data, response)
    }

    public static func validate(status: Int, body: [String: Any]?) throws {
        if let errors = body?["errors"] as? [[String: Any]], !errors.isEmpty {
            // Do not echo server detail/title: they can include account data.
            let explicitlyRestricted = errors.contains { error in
                let detail = ((error["detail"] as? String ?? "") + " " + (error["title"] as? String ?? "")).lowercased()
                return detail.contains("not available for your team") ||
                       detail.contains("requires a paid") || detail.contains("not supported for free") ||
                       detail.contains("not permitted for this team")
            }
            throw AppleAPIError.customError(code: status,
                message: explicitlyRestricted
                    ? "Apple rejected this capability because of team/account restrictions. It was not enabled."
                    : "Apple rejected the API request (JSON:API errors). Capability not verified; a 403 alone does not establish a free-account restriction.")
        }
        if let code = body?["resultCode"] as? NSNumber, code.intValue != 0 {
            throw AppleAPIError.customError(code: code.intValue, message: "Apple developer service rejected the request. No success was recorded.")
        }
        guard (200..<300).contains(status) else {
            throw AppleAPIError.customError(code: status, message:
                status == 401 ? "Apple session expired. Sign in again." :
                "Apple HTTP request failed. Check the selected team and account permissions; no success was recorded.")
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                          willPerformHTTPRedirection response: HTTPURLResponse,
                          newRequest request: URLRequest,
                          completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
