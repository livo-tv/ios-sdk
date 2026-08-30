import Foundation

public struct StudioPublicClient: Sendable {
    public var apiURL: URL
    private let http: StudioHTTP

    public init(apiURL: URL = LivoAPIConfiguration.productionAPIURL, session: URLSession = .shared) {
        self.apiURL = LivoAPIConfiguration.normalizeAPIURL(apiURL)
        http = StudioHTTP(apiURL: self.apiURL, session: session)
    }

    public func redeemHost(token: String) async throws -> StudioSession {
        try await http.json(
            "POST",
            path: "public/studio/host/\(encoded(token))",
            as: StudioSession.self
        )
    }

    public func joinGuest(
        token: String,
        displayName: String,
        guestId: String
    ) async throws -> StudioSession {
        struct Body: Encodable {
            var displayName: String
            var guestId: String
        }
        let payload = try StudioJSON.encoder.encode(Body(displayName: displayName, guestId: guestId))
        return try await http.json(
            "POST",
            path: "public/studio/join/\(encoded(token))",
            body: payload,
            as: StudioSession.self
        )
    }

    public func joinStatus(token: String) async throws -> StudioJoinStatusResult {
        do {
            let raw: JoinStatusDTO = try await http.json(
                "GET",
                path: "public/studio/join/\(encoded(token))/status"
            )
            return .status(StudioJoinStatus(ready: raw.ready, streamStatus: raw.streamStatus))
        } catch let error as StudioAPIError where error.isEnded {
            return .ended
        }
    }

    public func publicStreamStatus(streamId: String) async throws -> String? {
        do {
            let raw: PublicStreamDTO = try await http.json(
                "GET",
                path: "public/streams/\(encoded(streamId))"
            )
            return raw.stream?.status ?? raw.status
        } catch let error as StudioAPIError where error.isEnded {
            return "ended"
        } catch {
            return nil
        }
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

public func redeemStudioHost(
    token: String,
    apiURL: URL = LivoAPIConfiguration.productionAPIURL,
    session: URLSession = .shared
) async throws -> StudioSession {
    try await StudioPublicClient(apiURL: apiURL, session: session).redeemHost(token: token)
}

public func joinStudioGuest(
    token: String,
    displayName: String,
    guestId: String,
    apiURL: URL = LivoAPIConfiguration.productionAPIURL,
    session: URLSession = .shared
) async throws -> StudioSession {
    try await StudioPublicClient(apiURL: apiURL, session: session)
        .joinGuest(token: token, displayName: displayName, guestId: guestId)
}

public func getStudioJoinStatus(
    token: String,
    apiURL: URL = LivoAPIConfiguration.productionAPIURL,
    session: URLSession = .shared
) async throws -> StudioJoinStatusResult {
    try await StudioPublicClient(apiURL: apiURL, session: session).joinStatus(token: token)
}

public func getPublicStreamStatus(
    streamId: String,
    apiURL: URL = LivoAPIConfiguration.productionAPIURL,
    session: URLSession = .shared
) async throws -> String? {
    try await StudioPublicClient(apiURL: apiURL, session: session).publicStreamStatus(streamId: streamId)
}

private struct JoinStatusDTO: Decodable {
    var ready: Bool
    var streamStatus: String?
}

private struct PublicStreamDTO: Decodable {
    var status: String?
    var stream: Nested?

    struct Nested: Decodable {
        var status: String?
    }
}
