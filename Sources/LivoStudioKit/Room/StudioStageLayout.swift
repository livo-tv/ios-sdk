import Foundation
import LivoStudioAPI

public enum StudioTileKind: String, Hashable, Sendable {
    case camera
    case screen
    case idle
}

public struct StudioDisplayTile: Hashable, Identifiable, Sendable {
    public var tileId: String
    public var kind: StudioTileKind
    public var participant: StudioParticipant

    public var id: String { tileId }
    public var isSelf: Bool { participant.isSelf }
    public var pinned: Bool { participant.pinned }

    public init(tileId: String, kind: StudioTileKind, participant: StudioParticipant) {
        self.tileId = tileId
        self.kind = kind
        self.participant = participant
    }
}

public struct StudioStageArrangement: Equatable, Sendable {
    public var spotlight: [StudioDisplayTile]
    public var strip: [StudioDisplayTile]
    public var overflow: Int

    public init(
        spotlight: [StudioDisplayTile] = [],
        strip: [StudioDisplayTile] = [],
        overflow: Int = 0
    ) {
        self.spotlight = spotlight
        self.strip = strip
        self.overflow = overflow
    }
}

public enum StudioStageLayout {
    public static let stripMax = 6
    public static let gridMax = 9

    public static func isOnStage(_ status: StudioStageStatus?) -> Bool {
        status == nil || status == .onStage
    }

    public static func canTakeOffAir(
        participants: [StudioParticipant],
        participantId: String,
        isLive: Bool
    ) -> Bool {
        if !isLive { return true }
        return participants.contains { $0.id != participantId && isOnStage($0.stageStatus) }
    }

    public static func expand(_ participants: [StudioParticipant]) -> [StudioDisplayTile] {
        var tiles: [StudioDisplayTile] = []
        for participant in participants {
            if participant.videoEnabled {
                tiles.append(StudioDisplayTile(
                    tileId: "\(participant.id):camera",
                    kind: .camera,
                    participant: participant
                ))
            } else {
                tiles.append(StudioDisplayTile(
                    tileId: "\(participant.id):idle",
                    kind: .idle,
                    participant: participant
                ))
            }
            if participant.screenShareEnabled {
                tiles.append(StudioDisplayTile(
                    tileId: "\(participant.id):screen",
                    kind: .screen,
                    participant: participant
                ))
            }
        }
        return tiles
    }

    public static func arrange(
        tiles: [StudioDisplayTile],
        activeSpeakerId: String? = nil,
        max: Int? = nil
    ) -> StudioStageArrangement {
        let pinned = tiles.first(where: \.pinned)
        let spotlight: [StudioDisplayTile]
        let remaining: [StudioDisplayTile]
        if let pinned {
            let pinTiles = tiles.filter { $0.participant.id == pinned.participant.id }
            let focus = pinTiles.first(where: { $0.kind == .screen })
                ?? pinTiles.first(where: { $0.kind == .camera })
                ?? pinTiles.first
            if let focus {
                spotlight = [focus]
                remaining = tiles.filter { $0.tileId != focus.tileId }
            } else {
                spotlight = []
                remaining = tiles
            }
        } else {
            spotlight = tiles.filter { $0.kind == .screen }
            remaining = tiles.filter { $0.kind != .screen }
        }
        let cap = max ?? (spotlight.isEmpty ? gridMax : stripMax)
        let ranked = remaining.sorted { lhs, rhs in
            let diff = stripRank(lhs, activeSpeakerId: activeSpeakerId) - stripRank(rhs, activeSpeakerId: activeSpeakerId)
            if diff != 0 { return diff < 0 }
            return lhs.tileId < rhs.tileId
        }
        if ranked.count <= cap {
            return StudioStageArrangement(spotlight: spotlight, strip: ranked, overflow: 0)
        }
        let kept = takeCappedStrip(ranked, cap: cap)
        return StudioStageArrangement(
            spotlight: spotlight,
            strip: kept,
            overflow: ranked.count - kept.count
        )
    }

    private static func stripRank(_ tile: StudioDisplayTile, activeSpeakerId: String?) -> Int {
        if tile.pinned { return 0 }
        if tile.kind == .screen { return 1 }
        if tile.isSelf { return 2 }
        if let activeSpeakerId, tile.participant.id == activeSpeakerId { return 3 }
        if tile.kind == .camera { return 4 }
        return 5
    }

    private static func takeCappedStrip(_ ranked: [StudioDisplayTile], cap: Int) -> [StudioDisplayTile] {
        let selfTiles = ranked.filter(\.isSelf)
        let others = ranked.filter { !$0.isSelf }
        let reserved = min(selfTiles.count, cap)
        return Array(selfTiles) + Array(others.prefix(cap - reserved))
    }
}
