import Foundation

public final class StudioControlClient: @unchecked Sendable {
    public private(set) var token: String
    public let apiURL: URL
    private let session: URLSession

    public init(
        token: String,
        apiURL: URL = LivoAPIConfiguration.productionAPIURL,
        session: URLSession = .shared
    ) {
        self.token = token
        self.apiURL = LivoAPIConfiguration.normalizeAPIURL(apiURL)
        self.session = session
    }

    public var currentToken: String { token }

    public func livestream() async throws -> StudioLivestreamEgress {
        let body: LivestreamDTO = try await request("/livestream", method: "POST")
        return body.egress ?? .starting
    }

    public func publish() async throws -> StudioControlState {
        try await request("/publish", method: "POST")
    }

    public func stop() async throws -> StudioControlState {
        try await request("/stop", method: "POST")
    }

    public func state() async throws -> StudioControlState {
        try await request("/state", method: "GET")
    }

    @discardableResult
    public func refresh() async throws -> StudioControlRefresh {
        let next: StudioControlRefresh = try await request("/refresh", method: "POST")
        token = next.studioControlToken
        return next
    }

    private func request<T: Decodable>(_ suffix: String, method: String) async throws -> T {
        let http = StudioHTTP(apiURL: apiURL, session: session)
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        return try await http.json(method, path: "public/studio/control/\(encoded)\(suffix)")
    }
}

public func createStudioControlClient(
    token: String,
    apiURL: URL = LivoAPIConfiguration.productionAPIURL,
    session: URLSession = .shared
) -> StudioControlClient {
    StudioControlClient(token: token, apiURL: apiURL, session: session)
}

private struct LivestreamDTO: Decodable {
    var ok: Bool?
    var egress: StudioLivestreamEgress?
}
