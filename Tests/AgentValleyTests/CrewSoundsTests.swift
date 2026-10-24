import XCTest
@testable import AgentValley

final class CrewSoundsTests: XCTestCase {
    private var real: CrewSounds {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return CrewSounds(folder: repo.appendingPathComponent("sounds/crew"))
    }

    func testEveryLeadHasEveryGroup() {
        let sounds = real
        var groups = WaitTopic.allCases.map { CrewSounds.group($0) } + DoneTopic.allCases.map { CrewSounds.group($0) }
        groups += (1...3).map { CrewSounds.group(remind: $0) }
        for who in Crew.leads {
            for group in groups {
                XCTAssertFalse(sounds.lines(who, group).isEmpty, "\(who) \(group)")
            }
        }
    }

    func testJudyHasPlanAndEveryoneHasEveryScene() {
        let sounds = real
        XCTAssertFalse(sounds.lines(.judy, "plan").isEmpty)
        for who in Crew.allCases {
            for scene in CrewScene.allCases {
                XCTAssertFalse(sounds.lines(who, scene.rawValue).isEmpty, "\(who) \(scene)")
            }
        }
    }

    func testTheLoneSoundsAreThere() {
        let sounds = real
        var names = ["chime-need.m4a", "chime-done.m4a"]
        for who in Crew.leads { names += ["\(who.rawValue)-sting-need.m4a", "\(who.rawValue)-sting-done.m4a"] }
        for scene in CrewScene.allCases { names.append("bed-\(scene.rawValue).m4a") }
        for name in names { XCTAssertTrue(sounds.files.contains(name), name) }
    }

    func testAGroupIsMatchedWhole() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["walt-remind-1-1.m4a", "walt-remind-1-2.m4a", "walt-remind-10-1.m4a", "walt-need-run-x.m4a"] {
            XCTAssertTrue(FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data()))
        }
        let sounds = CrewSounds(folder: dir)
        XCTAssertEqual(sounds.lines(.walt, "remind-1"), ["walt-remind-1-1.m4a", "walt-remind-1-2.m4a"])
        XCTAssertEqual(sounds.lines(.walt, "need-run"), [])
    }

    func testRemindLevelsAreClamped() {
        XCTAssertEqual(CrewSounds.group(remind: 0), "remind-1")
        XCTAssertEqual(CrewSounds.group(remind: 7), "remind-3")
    }

    func testLeadsLineUpWithThePeopleDrawn() {
        XCTAssertEqual(Crew.leads, [.sunny, .walt, .norm, .pearl])
        let drawn = Person.leads.map { $0.rows }
        XCTAssertEqual(drawn, [Person.guru, .walrus, .engineer, .pearls].map { $0.rows })
    }

    func testLeadsFollowTheFaces() {
        XCTAssertEqual(Crew.lead(LeadLook(face: 1)), .walt)
        XCTAssertEqual(Crew.lead(LeadLook(face: 7)), .pearl)
    }
}
