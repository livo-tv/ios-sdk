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

    @Test func screenShareBecomesSpotlight() {
        let tiles = StudioStageLayout.expand([
            person(id: "self", isSelf: true),
            person(id: "a", screen: true),
        ])
        let layout = StudioStageLayout.arrange(tiles: tiles)
        #expect(layout.spotlight.map(\.tileId) == ["a:screen"])
        #expect(layout.strip.contains { $0.isSelf })
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

    @Test func overflowKeepsSelf() {
        let people = (1 ... 10).map { person(id: "p\($0)") } + [person(id: "self", isSelf: true)]
        let layout = StudioStageLayout.arrange(tiles: StudioStageLayout.expand(people), max: 6)
        #expect(layout.strip.contains { $0.isSelf })
        #expect(layout.strip.count == 6)
        #expect(layout.overflow == 5)
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
}
