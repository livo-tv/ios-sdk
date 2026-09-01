import Testing
@testable import LivoStudioAPI
@testable import LivoStudioKit

struct StudioStageLayoutTests {
    private func person(
        id: String,
        isSelf: Bool = false,
        video: Bool = true,
        screen: Bool = false,
        pinned: Bool = false,
        stage: StudioStageStatus? = .onStage
    ) -> StudioParticipant {
        StudioParticipant(
            id: id,
            name: id,
            isSelf: isSelf,
            audioEnabled: true,
            videoEnabled: video,
            screenShareEnabled: screen,
            stageStatus: stage,
            pinned: pinned
        )
    }

    @Test func isOnStageTreatsNilAsVisible() {
        #expect(StudioStageLayout.isOnStage(nil))
        #expect(StudioStageLayout.isOnStage(.onStage))
        #expect(!StudioStageLayout.isOnStage(.offStage))
        #expect(!StudioStageLayout.isOnStage(.requestedToJoinStage))
        #expect(!StudioStageLayout.isOnStage(.acceptedToJoinStage))
    }

    @Test func expandAddsScreenTile() {
        let tiles = StudioStageLayout.expand([
            person(id: "a", screen: true),
            person(id: "b", video: false),
        ])
        #expect(tiles.map(\.tileId) == ["a:camera", "a:screen", "b:idle"])
    }

    @Test func screenOnlyParticipantSpotlights() {
        let tiles = StudioStageLayout.expand([
            person(id: "a", video: false, screen: true),
        ])
        #expect(tiles.map(\.tileId) == ["a:idle", "a:screen"])
        let layout = StudioStageLayout.arrange(tiles: tiles)
        #expect(layout.spotlight.map(\.tileId) == ["a:screen"])
    }

    @Test func screenShareBecomesSpotlight() {
        let tiles = StudioStageLayout.expand([
            person(id: "self", isSelf: true),
            person(id: "a", screen: true),
        ])
        let layout = StudioStageLayout.arrange(tiles: tiles)
        #expect(layout.spotlight.map(\.tileId) == ["a:screen"])
        #expect(layout.pip?.tileId == "self:camera")
        #expect(!layout.strip.contains { $0.isSelf })
    }

    @Test func pipExtractsSelfWhenOthersPresent() {
        let tiles = StudioStageLayout.expand([
            person(id: "self", isSelf: true),
            person(id: "a"),
        ])
        let layout = StudioStageLayout.arrange(tiles: tiles)
        #expect(layout.pip?.tileId == "self:camera")
        #expect(layout.spotlight.isEmpty)
        #expect(layout.strip.map(\.tileId) == ["a:camera"])
    }

    @Test func noPipWhenSelfAlone() {
        let layout = StudioStageLayout.arrange(tiles: StudioStageLayout.expand([
            person(id: "self", isSelf: true),
        ]))
        #expect(layout.pip == nil)
        #expect(layout.strip.map(\.tileId) == ["self:camera"])
    }

    @Test func noPipWhenSelfPinned() {
        let tiles = StudioStageLayout.expand([
            person(id: "self", isSelf: true, pinned: true),
            person(id: "a"),
        ])
        let layout = StudioStageLayout.arrange(tiles: tiles)
        #expect(layout.pip == nil)
        #expect(layout.spotlight.map(\.tileId) == ["self:camera"])
        #expect(layout.strip.map(\.tileId) == ["a:camera"])
    }

    @Test func selfScreenStaysOnStageWithPip() {
        let tiles = StudioStageLayout.expand([
            person(id: "self", isSelf: true, screen: true),
            person(id: "a"),
        ])
        let layout = StudioStageLayout.arrange(tiles: tiles)
        #expect(layout.spotlight.map(\.tileId) == ["self:screen"])
        #expect(layout.pip?.tileId == "self:camera")
        #expect(layout.strip.map(\.tileId) == ["a:camera"])
    }

    @Test func noPipWhenSelfAloneWithScreen() {
        let layout = StudioStageLayout.arrange(tiles: StudioStageLayout.expand([
            person(id: "self", isSelf: true, screen: true),
        ]))
        #expect(layout.pip == nil)
        #expect(layout.spotlight.map(\.tileId) == ["self:screen"])
        #expect(layout.strip.map(\.tileId) == ["self:camera"])
    }

    @Test func pinWinsSpotlightAndPrefersScreen() {
        let tiles = StudioStageLayout.expand([
            person(id: "a", screen: true, pinned: true),
            person(id: "b"),
        ])
        let layout = StudioStageLayout.arrange(tiles: tiles)
        #expect(layout.spotlight.map(\.tileId) == ["a:screen"])
        #expect(!layout.strip.contains { $0.tileId == "a:screen" })
    }

    @Test func gridColumnsMatchWebBreakpoints() {
        #expect(StudioStageLayout.gridColumns(tileCount: 1, regularWidth: false) == 1)
        #expect(StudioStageLayout.gridColumns(tileCount: 2, regularWidth: false) == 2)
        #expect(StudioStageLayout.gridColumns(tileCount: 4, regularWidth: false) == 2)
        #expect(StudioStageLayout.gridColumns(tileCount: 6, regularWidth: false) == 2)
        #expect(StudioStageLayout.gridColumns(tileCount: 6, regularWidth: true) == 3)
        #expect(StudioStageLayout.gridColumns(tileCount: 9, regularWidth: false) == 3)
        #expect(StudioStageLayout.gridColumns(tileCount: 9, regularWidth: true) == 4)
    }

    @Test func prefersRegularLayoutOnIPadOrRegularByRegular() {
        #expect(StudioStageLayout.prefersRegularLayout(regularWidth: false, regularHeight: false, isPad: true))
        #expect(StudioStageLayout.prefersRegularLayout(regularWidth: true, regularHeight: true, isPad: false))
        #expect(!StudioStageLayout.prefersRegularLayout(regularWidth: true, regularHeight: false, isPad: false))
        #expect(!StudioStageLayout.prefersRegularLayout(regularWidth: false, regularHeight: true, isPad: false))
    }

    @Test func overflowExtractsSelfToPip() {
        let people = (1 ... 10).map { person(id: "p\($0)") } + [person(id: "self", isSelf: true)]
        let layout = StudioStageLayout.arrange(tiles: StudioStageLayout.expand(people), max: 6)
        #expect(layout.pip?.isSelf == true)
        #expect(!layout.strip.contains { $0.isSelf })
        #expect(layout.strip.count == 6)
        #expect(layout.overflow == 4)
    }
}

struct StudioChatGroupingTests {
    @Test func groupsConsecutiveSameSender() {
        let messages = [
            StudioChatMessage(id: "1", userId: "a", name: "Ann", text: "hi", time: 1),
            StudioChatMessage(id: "2", userId: "a", name: "Ann", text: "there", time: 2),
            StudioChatMessage(id: "3", userId: "b", name: "Bo", text: "yo", time: 3),
        ]
        let groups = StudioChatGrouping.group(messages, selfUserId: "b")
        #expect(groups.count == 2)
        #expect(groups[0].rows.count == 2)
        #expect(groups[0].mine == false)
        #expect(groups[1].mine)
    }

    @Test func dropsTargetedMessages() {
        let messages = [
            StudioChatMessage(id: "1", userId: "a", name: "Ann", text: "hi", time: 1),
            StudioChatMessage(id: "2", userId: "a", name: "Ann", text: "secret", time: 2, targetUserIds: ["b"]),
        ]
        #expect(StudioChatGrouping.publicMessages(messages).count == 1)
    }

    @Test func initialsUseFirstLetters() {
        #expect(StudioChatGrouping.initials("Pat Cole") == "PC")
        #expect(StudioChatGrouping.initials("") == "?")
    }

    @Test func overlayPreviewExpiresAfterMaxAge() {
        let messages = [
            StudioChatMessage(id: "1", userId: "a", name: "Ann", text: "hi", time: 100),
        ]
        #expect(StudioChatGrouping.overlayPreview(messages: messages, selfUserId: "b", now: 105) != nil)
        #expect(StudioChatGrouping.overlayPreview(messages: messages, selfUserId: "b", now: 107) == nil)
    }

    @Test func overlayPreviewTrimsToThreeLines() {
        let messages = (1 ... 5).map { index in
            StudioChatMessage(
                id: "\(index)",
                userId: "a",
                name: "Ann",
                text: "m\(index)",
                time: Double(index)
            )
        }
        let preview = StudioChatGrouping.overlayPreview(messages: messages, selfUserId: "b", now: 5)
        #expect(preview?.rows.map { $0.id } == ["3", "4", "5"])
    }

    @Test func overlayPreviewDropsTargeted() {
        let messages = [
            StudioChatMessage(
                id: "1",
                userId: "a",
                name: "Ann",
                text: "secret",
                time: 10,
                targetUserIds: ["b"]
            ),
        ]
        #expect(StudioChatGrouping.overlayPreview(messages: messages, selfUserId: "b", now: 10) == nil)
    }

    @Test func overlayPreviewMarksMine() {
        let messages = [
            StudioChatMessage(id: "1", userId: "me", name: "Self", text: "yo", time: 10),
        ]
        #expect(StudioChatGrouping.overlayPreview(messages: messages, selfUserId: "me", now: 10)?.mine == true)
    }
}

struct StudioAvatarTests {
    @Test func colorIsStablePerName() {
        #expect(StudioAvatar.color(for: "Ann") == StudioAvatar.color(for: "Ann"))
        #expect(Set(StudioAvatar.palette).count == StudioAvatar.palette.count)
        let names = ["Ann", "Bo", "Cam", "Dee", "Eve", "Fay", "Gus", "Hal"]
        #expect(Set(names.map(StudioAvatar.color(for:))).count > 1)
    }

    @Test func initialsMatchChatGrouping() {
        #expect(StudioAvatar.initials("Pat Cole") == "PC")
        #expect(StudioAvatar.initials("") == "?")
    }
}
