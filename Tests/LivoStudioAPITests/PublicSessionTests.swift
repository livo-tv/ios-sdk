import Foundation
import Testing
@testable import LivoStudioAPI

@Suite(.serialized)
struct StudioAPITests {
struct PublicSessionTests {
    private let api = URL(string: "https://media-svc.example.test")!

    @Test func redeemHostDecodesSession() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub(
            "/public/studio/host/",
            json: """
            {
              "authToken": "rtk-token",
              "meetingId": "mtg_1",
              "role": "moderator",
              "guestUrl": "https://app.livo.tv/studio/join/abc",
              "studioControlToken": "sc_aaa",
              "expiresAt": 1700000000000,
              "stream": { "id": "stm_1", "title": "Night", "status": "preview" }
            }
            """
        )
        let session = try await redeemStudioHost(
            token: "host-token",
            apiURL: api,
            session: MockURLProtocol.session()
        )
        #expect(session.role == .moderator)
        #expect(session.authToken == "rtk-token")
        #expect(session.stream.id == "stm_1")
        #expect(session.studioControlToken == "sc_aaa")
        let path = MockURLProtocol.requests.first?.url?.path ?? ""
        #expect(path.hasSuffix("/public/studio/host/host-token"))
    }

    @Test func joinGuestPostsName() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub(
            "/public/studio/join/",
            json: """
            {
              "authToken": "g",
              "meetingId": "m",
              "role": "guest",
              "stream": { "id": "s", "title": "T", "status": "public" }
            }
            """
        )
        _ = try await joinStudioGuest(
            token: "gtok",
            displayName: "Ada",
            guestId: "guest-1",
            apiURL: api,
            session: MockURLProtocol.session()
        )
        let body = MockURLProtocol.requests.first?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(body.contains("Ada"))
        #expect(body.contains("guest-1"))
    }

    @Test func joinStatusMaps404ToEnded() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub("/public/studio/join/missing/status", status: 404, json: #"{"error":"gone"}"#)
        let result = try await getStudioJoinStatus(
            token: "missing",
            apiURL: api,
            session: MockURLProtocol.session()
        )
        #expect(result == .ended)
    }

    @Test func publicStreamStatusReadsNestedStream() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub(
            "/public/streams/stm_1",
            json: #"{"stream":{"id":"stm_1","status":"public","title":"Live"}}"#
        )
        let status = try await getPublicStreamStatus(
            streamId: "stm_1",
            apiURL: api,
            session: MockURLProtocol.session()
        )
        #expect(status == "public")
    }

    @Test func hostSessionFallsBackToURLTokens() {
        let minted = StudioHostSession(
            hostUrl: "https://app.livo.tv/studio/host/aa",
            guestUrl: "https://app.livo.tv/studio/join/bb",
            expiresAt: 1
        )
        #expect(minted.resolvedHostToken == "aa")
        #expect(minted.resolvedGuestToken == "bb")
    }
}

struct ControlClientTests {
    private let api = URL(string: "https://media-svc.example.test")!

    @Test func livestreamAndRefreshRotateToken() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub(
            "/livestream",
            json: #"{"ok":true,"egress":"starting"}"#
        )
        MockURLProtocol.stub(
            "/refresh",
            json: #"{"studioControlToken":"sc_new","expiresAt":2}"#
        )
        MockURLProtocol.stub(
            "/state",
            json: #"{"stream":{"id":"s","title":"T","status":"preview"}}"#
        )
        let client = StudioControlClient(
            token: "sc_old",
            apiURL: api,
            session: MockURLProtocol.session()
        )
        let egress = try await client.livestream()
        #expect(egress == .starting)
        let refreshed = try await client.refresh()
        #expect(refreshed.studioControlToken == "sc_new")
        #expect(client.currentToken == "sc_new")
        let state = try await client.state()
        #expect(state.stream.status == "preview")
    }

    @Test func controlSurfacesAPIError() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub("/publish", status: 409, json: #"{"error":"not_preview"}"#)
        let client = StudioControlClient(
            token: "sc_old",
            apiURL: api,
            session: MockURLProtocol.session()
        )
        await #expect(throws: StudioAPIError.self) {
            _ = try await client.publish()
        }
    }
}
}
