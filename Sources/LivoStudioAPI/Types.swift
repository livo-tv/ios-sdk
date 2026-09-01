import Foundation

public enum StudioRole: String, Codable, Sendable {
    case moderator
    case guest
}

public enum StudioStageStatus: String, Codable, Sendable {
    case offStage = "OFF_STAGE"
    case requestedToJoinStage = "REQUESTED_TO_JOIN_STAGE"
    case acceptedToJoinStage = "ACCEPTED_TO_JOIN_STAGE"
    case onStage = "ON_STAGE"
}

public struct StudioStreamSummary: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: String
    public var encoderLostAt: Int64?

    public init(id: String, title: String, status: String, encoderLostAt: Int64? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.encoderLostAt = encoderLostAt
    }

    public var isPreview: Bool { status == "preview" }
    public var isLive: Bool { status == "public" }
    public var isActive: Bool { isPreview || isLive }
    public var isEnded: Bool { status == "ended" || status == "error" }
}

public struct StudioSession: Codable, Hashable, Sendable, Identifiable {
    public var authToken: String
    public var meetingId: String
    public var role: StudioRole
    public var guestUrl: String?
    public var studioControlToken: String?
    public var expiresAt: Int64?
    public var stream: StudioStreamSummary

    public var id: String { meetingId }

    public init(
        authToken: String,
        meetingId: String,
        role: StudioRole,
        guestUrl: String? = nil,
        studioControlToken: String? = nil,
        expiresAt: Int64? = nil,
        stream: StudioStreamSummary
    ) {
        self.authToken = authToken
        self.meetingId = meetingId
        self.role = role
        self.guestUrl = guestUrl
        self.studioControlToken = studioControlToken
        self.expiresAt = expiresAt
        self.stream = stream
    }
}

public struct StudioJoinStatus: Hashable, Sendable {
    public var ready: Bool
    public var streamStatus: String?

    public init(ready: Bool, streamStatus: String?) {
        self.ready = ready
        self.streamStatus = streamStatus
    }
}

public enum StudioJoinStatusResult: Hashable, Sendable {
    case status(StudioJoinStatus)
    case ended
}

public struct StudioWaitlistedGuest: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var userId: String?
    public var picture: String?

    public init(id: String, name: String, userId: String? = nil, picture: String? = nil) {
        self.id = id
        self.name = name
        self.userId = userId
        self.picture = picture
    }
}

public struct StudioStageRequest: Hashable, Identifiable, Sendable {
    public var userId: String
    public var peerId: String
    public var name: String

    public var id: String { peerId }

    public init(userId: String, peerId: String, name: String) {
        self.userId = userId
        self.peerId = peerId
        self.name = name
    }

    /// Same `userId || peerId` fallback as `StudioParticipant.stageId`.
    public var stageId: String {
        userId.isEmpty ? peerId : userId
    }
}

public struct StudioParticipant: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isSelf: Bool
    public var audioEnabled: Bool
    public var videoEnabled: Bool
    public var screenShareEnabled: Bool
    public var picture: String?
    public var userId: String?
    public var stageStatus: StudioStageStatus?
    public var pinned: Bool

    public init(
        id: String,
        name: String,
        isSelf: Bool,
        audioEnabled: Bool,
        videoEnabled: Bool,
        screenShareEnabled: Bool = false,
        picture: String? = nil,
        userId: String? = nil,
        stageStatus: StudioStageStatus? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isSelf = isSelf
        self.audioEnabled = audioEnabled
        self.videoEnabled = videoEnabled
        self.screenShareEnabled = screenShareEnabled
        self.picture = picture
        self.userId = userId
        self.stageStatus = stageStatus
        self.pinned = pinned
    }

    /// RTK stage APIs key on `userId`, but anonymous guests have an empty one.
    /// Mirrors the web adapter's `userId || id` truthiness fallback.
    public var stageId: String {
        if let userId, !userId.isEmpty { return userId }
        return id
    }
}

public struct StudioChatMessage: Hashable, Identifiable, Sendable {
    public var id: String
    public var userId: String
    public var name: String
    public var text: String
    public var time: TimeInterval
    public var targetUserIds: [String]
    public var pinned: Bool
    public var isEdited: Bool

    public init(
        id: String,
        userId: String,
        name: String,
        text: String,
        time: TimeInterval,
        targetUserIds: [String] = [],
        pinned: Bool = false,
        isEdited: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.text = text
        self.time = time
        self.targetUserIds = targetUserIds
        self.pinned = pinned
        self.isEdited = isEdited
    }
}

public enum StudioLivestreamEgress: String, Codable, Sendable {
    case live
    case starting
}

public struct StudioControlState: Codable, Sendable {
    public var stream: StudioStreamSummary

    public init(stream: StudioStreamSummary) {
        self.stream = stream
    }
}

public struct StudioControlRefresh: Codable, Sendable {
    public var studioControlToken: String
    public var expiresAt: Int64
}

public struct StudioHostSession: Codable, Sendable {
    public var hostUrl: String
    public var guestUrl: String
    public var hostToken: String?
    public var guestToken: String?
    public var expiresAt: Int64

    public init(
        hostUrl: String,
        guestUrl: String,
        hostToken: String? = nil,
        guestToken: String? = nil,
        expiresAt: Int64
    ) {
        self.hostUrl = hostUrl
        self.guestUrl = guestUrl
        self.hostToken = hostToken
        self.guestToken = guestToken
        self.expiresAt = expiresAt
    }

    /// Prefer the explicit token; fall back to the last path segment of the web URL.
    public var resolvedHostToken: String? {
        if let hostToken, !hostToken.isEmpty { return hostToken }
        return URL(string: hostUrl)?.lastPathComponent
    }

    public var resolvedGuestToken: String? {
        if let guestToken, !guestToken.isEmpty { return guestToken }
        return URL(string: guestUrl)?.lastPathComponent
    }
}

public enum StudioEvent: Sendable {
    case joined(streamId: String)
    case live(streamId: String)
    case ended(streamId: String)
    case left(streamId: String)
}
