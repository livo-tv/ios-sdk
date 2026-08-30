import Foundation

struct StudioHTTP {
    var session: URLSession
    var apiURL: URL

    init(apiURL: URL = LivoAPIConfiguration.productionAPIURL, session: URLSession = .shared) {
        self.apiURL = LivoAPIConfiguration.normalizeAPIURL(apiURL)
        self.session = session
    }

    func url(for path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return trimmed.split(separator: "/").reduce(apiURL) { partial, segment in
            partial.appendingPathComponent(String(segment))
        }
    }

    func request(
        _ method: String,
        path: String,
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StudioAPIError(status: 0, message: "Invalid studio response")
        }
        return (data, http)
    }

    func json<T: Decodable>(
        _ method: String,
        path: String,
        body: Data? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        let (data, http) = try await request(method, path: path, body: body)
        guard (200 ... 299).contains(http.statusCode) else {
            throw StudioAPIError(
                status: http.statusCode,
                message: StudioJSON.errorMessage(status: http.statusCode, data: data),
                body: data
            )
        }
        do {
            return try StudioJSON.decoder.decode(T.self, from: data)
        } catch {
            throw StudioAPIError(status: 502, message: "Could not parse studio response", body: data)
        }
    }
}
