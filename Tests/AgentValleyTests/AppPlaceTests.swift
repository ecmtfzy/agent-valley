import XCTest
@testable import AgentValley

final class AppPlaceTests: XCTestCase {
    // Opened from the mounted dmg, or from a folder macOS runs it out of at random: there it
    // cannot update itself, and the plugin's path goes when the app quits.
    func testNeedsMove() {
        XCTAssertTrue(AppPlace.needsMove("/Volumes/AgentValley/AgentValley.app", readOnlyVolume: true))
        XCTAssertTrue(AppPlace.needsMove("/private/var/folders/x/AppTranslocation/1234/d/AgentValley.app", readOnlyVolume: true))
        XCTAssertFalse(AppPlace.needsMove("/Applications/AgentValley.app", readOnlyVolume: false))
        XCTAssertFalse(AppPlace.needsMove("/Users/me/Applications/AgentValley.app", readOnlyVolume: false))
        XCTAssertFalse(AppPlace.needsMove("/Users/me/src/agent-valley/build/AgentValley.app", readOnlyVolume: false))
        XCTAssertFalse(AppPlace.needsMove("/Users/me/Volumes/AgentValley.app", readOnlyVolume: false))
        // A build to work on, on a disk of its own: it stays where it was built.
        XCTAssertFalse(AppPlace.needsMove("/Volumes/Work/agent-valley/build/AgentValley.app", readOnlyVolume: false))
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func app(in folder: URL, marked mark: String) throws -> URL {
        let app = folder.appendingPathComponent("AgentValley.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data().write(to: app.appendingPathComponent("Contents/\(mark)"))
        return app
    }

    // A copy that fails halfway (a full disk, a dmg ejected under it) leaves the old app where
    // it was: the old one goes to the Bin only once the new one is whole beside it.
    func testAFailedCopyLeavesTheOldOneInPlace() throws {
        let volume = try folder(), applications = try folder()
        let gone = volume.appendingPathComponent("AgentValley.app")
        let old = try app(in: applications, marked: "old")
        var trashed: [URL] = []
        XCTAssertThrowsError(try AppPlace.move(gone, into: applications) { trashed.append($0); try FileManager.default.removeItem(at: $0) })
        XCTAssertEqual(trashed, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("Contents/old").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: applications.path), ["AgentValley.app"])
    }

    // The new copy takes the old one's place whole; the old one goes to the Bin, not under it.
    func testMoveReplacesAnOlderCopy() throws {
        let volume = try folder(), applications = try folder()
        let new = try app(in: volume, marked: "new")
        let old = try app(in: applications, marked: "old")
        var trashed: [URL] = []
        let moved = try AppPlace.move(new, into: applications) { trashed.append($0); try FileManager.default.removeItem(at: $0) }
        XCTAssertEqual(moved.path, old.path)
        XCTAssertEqual(trashed.map(\.path), [old.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent("Contents/new").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.appendingPathComponent("Contents/old").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path), "the dmg's copy is left as it was")
    }

    // The copy from a downloaded dmg keeps its quarantine flag. Left on the copy in Applications,
    // macOS asks about it a second time and runs it from a random folder again, which offers
    // the move once more, round and round (screen test, 2026-10-20).
    func testTheMovedCopyIsNoLongerQuarantined() throws {
        let volume = try folder(), applications = try folder()
        let new = try app(in: volume, marked: "new")
        let flag = "0081;6ad728d4;Safari;"
        for path in [new.path, new.appendingPathComponent("Contents/new").path] {
            XCTAssertEqual(setxattr(path, "com.apple.quarantine", flag, flag.utf8.count, 0, XATTR_NOFOLLOW), 0)
        }
        let moved = try AppPlace.move(new, into: applications) { _ in }
        for path in [moved.path, moved.appendingPathComponent("Contents").path, moved.appendingPathComponent("Contents/new").path] {
            XCTAssertEqual(getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW), -1, path)
        }
    }

    func testMoveIntoEmptyFolder() throws {
        let volume = try folder(), applications = try folder()
        let new = try app(in: volume, marked: "new")
        let moved = try AppPlace.move(new, into: applications) { _ in XCTFail("nothing to put in the Bin") }
        XCTAssertEqual(moved.path, applications.appendingPathComponent("AgentValley.app").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent("Contents/new").path))
    }

    func testMoveLines() {
        XCTAssertEqual(Format.moveTitle, "Move AgentValley to Applications?")
        XCTAssertEqual(Format.moveMessage, "Out here we can't update ourselves, and the plugin loses track of us when you quit.")
        XCTAssertEqual(Format.moveButton, "Move to Applications")
        XCTAssertEqual(Format.notNow, "Not now")
        XCTAssertEqual(Format.moveFailed, "We couldn't make the move. Drag AgentValley into Applications yourself and open it from there.")
        XCTAssertEqual(Format.movedNotOpened, "We made it to Applications but didn't wake up. Open AgentValley from there.")
    }

    // Every copy quits the others as it starts, before the move offer or the socket: an older
    // version, one opened from the dmg, or one whose files brew took away would hold the panel and
    // the answers socket, and Allow and Deny would stop with nothing said.
    func testEachLaunchQuitsTheOtherCopiesFirst() throws {
        let main = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AgentValley/main.swift")
        let text = try String(contentsOf: main, encoding: .utf8)
        let launch = try XCTUnwrap(text.range(of: "func applicationDidFinishLaunching"))
        let body = text[launch.upperBound...]
        let quit = try XCTUnwrap(body.range(of: "AppPlace.quitOtherCopies()"))
        XCTAssertLessThan(quit.lowerBound, try XCTUnwrap(body.range(of: "AppPlace.needsMove()")).lowerBound)
        XCTAssertLessThan(quit.lowerBound, try XCTUnwrap(body.range(of: "answers.setEnabled")).lowerBound)
    }

    // Kept running from the dmg ("Not now"), it must not hand Open at login a path that goes
    // when the dmg is ejected.
    func testAMisplacedCopyLeavesOpenAtLoginAlone() throws {
        let main = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AgentValley/main.swift")
        let text = try String(contentsOf: main, encoding: .utf8)
        XCTAssertTrue(text.contains("if !misplaced { LoginItem.follow(settings) }"))
        XCTAssertEqual(text.components(separatedBy: "LoginItem.follow(").count, 2)
    }
}
