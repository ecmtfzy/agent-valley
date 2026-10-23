import XCTest
@testable import AgentValley

final class RosterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func card(_ session: String, in folder: String, startedAt: TimeInterval = 0) -> SessionCard {
        var info = AgentInfo()
        info.cwd = folder
        let id = "/r/proj/" + session
        return SessionCard(id: id, project: (folder as NSString).lastPathComponent, branch: "",
                           main: AgentRow(id: id + "/main", info: info, status: .working, elapsed: 0),
                           agents: [], startedAt: Date(timeIntervalSince1970: startedAt))
    }

    func look(_ roster: inout Roster, _ cards: [SessionCard], busy: Set<String> = [], at: Date? = nil, of session: String) -> LeadLook? {
        roster.seat(cards, busy: { busy.contains($0) }, now: at ?? now).first { AnswerStore.sessionID(of: $0) == session }?.look
    }

    // A project has its regular, kept across sessions and across launches.
    func testAProjectKeepsItsRegular() throws {
        var roster = Roster()
        let regular = try XCTUnwrap(look(&roster, [card("s1", in: "/work/app")], of: "s1"))
        XCTAssertEqual(roster.regulars["/work/app"], regular)
        // s1 is over: the next session of the project gets the regular.
        XCTAssertEqual(look(&roster, [card("s2", in: "/work/app")], of: "s2"), regular)
        // Kept on disk.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("roster-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try roster.save(file)
        var loaded = Roster.load(file)
        XCTAssertEqual(loaded, roster)
        XCTAssertEqual(look(&loaded, [card("s3", in: "/work/app")], of: "s3"), regular)
        // A file that can't be read is an empty roster.
        try Data("x".utf8).write(to: file)
        XCTAssertEqual(Roster.load(file), Roster())
    }

    // One person is never in two places: while the regular is at one session, another session
    // of the project gets someone else, who keeps that seat after the regular leaves.
    func testASecondSessionAtOnceGetsAHelperWhoStays() throws {
        var roster = Roster()
        let first = card("s1", in: "/work/app", startedAt: 1), second = card("s2", in: "/work/app", startedAt: 2)
        let regular = try XCTUnwrap(look(&roster, [first], busy: ["s1"], of: "s1"))
        let helper = try XCTUnwrap(look(&roster, [first, second], busy: ["s1", "s2"], of: "s2"))
        XCTAssertNotEqual(helper, regular)
        // The regular leaves: the helper stays the helper, and the regular is free for the next one.
        XCTAssertEqual(look(&roster, [second], busy: ["s2"], of: "s2"), helper)
        XCTAssertEqual(look(&roster, [second, card("s3", in: "/work/app", startedAt: 3)], busy: ["s2", "s3"], of: "s3"), regular)
    }

    // /clear: a new session at the same desk. The old one is still listed for a while, but no
    // Claude Code holds it, so the regular is free.
    func testClearKeepsTheRegular() throws {
        var roster = Roster()
        let old = card("s1", in: "/work/app", startedAt: 1)
        let regular = try XCTUnwrap(look(&roster, [old], busy: ["s1"], of: "s1"))
        XCTAssertEqual(look(&roster, [old, card("s2", in: "/work/app", startedAt: 2)], busy: ["s2"], of: "s2"), regular)
    }

    // A new worktree is a project of its own, with a regular of its own, and no two projects'
    // regulars look alike while there are faces, hair and shirts enough.
    func testEachProjectGetsARegularOfItsOwn() {
        var roster = Roster()
        let cards = (0..<Person.leadHair.count).map { card("s\($0)", in: "/work/app-\($0)", startedAt: Double($0)) }
        let looks = roster.seat(cards, busy: { _ in true }, now: now).compactMap(\.look)
        XCTAssertEqual(looks.count, cards.count)
        XCTAssertEqual(Set(looks.map(\.hair)).count, cards.count)
        XCTAssertEqual(Set(looks.map(\.shirt)).count, cards.count)
        XCTAssertEqual(Set(looks.map(\.face)).count, Person.leads.count)
        // However many there are, no beard runs into the shirt under it.
        let many = (0..<40).map { card("m\($0)", in: "/many/\($0)") }
        for look in roster.seat(many, busy: { _ in true }, now: now).compactMap(\.look) {
            XCTAssertFalse(Person.close(Person.leadHair[look.hair], Person.leadShirts[look.shirt]), "\(look)")
        }
    }

    // A seat is kept a day after its session was last listed; the regular for good. The time
    // seen is kept to the hour, so the roster is not written on every publish.
    func testSeatsGoAfterADayRegularsStay() {
        var roster = Roster()
        _ = roster.seat([card("s1", in: "/work/app")], busy: { _ in true }, now: now)
        let seated = roster
        _ = roster.seat([card("s1", in: "/work/app")], busy: { _ in true }, now: now.addingTimeInterval(60))
        XCTAssertEqual(roster, seated)
        _ = roster.seat([], busy: { _ in false }, now: now.addingTimeInterval(AgentStore.forgetAfter + 1))
        XCTAssertEqual(roster.seats, [:])
        XCTAssertEqual(roster.regulars, seated.regulars)
    }

    // What `crew status` reads is who sits where.
    func testTheTerminalGetsWhoSitsWhere() {
        var roster = Roster()
        let cards = roster.seat([card("s1", in: "/work/a"), card("s2", in: "/work/b")], busy: { _ in true }, now: now)
        let data = CrewSetup.leadLooksData(roster.looks)
        for card in cards {
            XCTAssertEqual(CrewSetup.look(for: AnswerStore.sessionID(of: card), in: data), card.look)
        }
        XCTAssertEqual(AgentStore.looks(cards)["/r/proj/s1/main"], cards.first { $0.id == "/r/proj/s1" }?.look)
    }
}
