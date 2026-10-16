import XCTest
@testable import AgentValley

final class ProjectsTests: XCTestCase {
    private let home = "/Users/me"

    // Every kind of folder sessions worked in on the owner's Mac, 2026-10-15, under made-up names.
    func testEveryKindOfFolderOnTheOwnersMac() {
        let known = Projects.known([
            "/Users/me/.superset/projects/agents-visualizer",
            "/Users/me/.superset/worktrees/mobile-app/brave-otter-d8de43d5",
        ])
        let cases: [(String, String)] = [
            ("/Users/me/.superset/projects/agents-visualizer", "agents-visualizer"),
            // A worktree of Claude Code's is its repository's.
            ("/Users/me/.superset/projects/agents-visualizer/.claude/worktrees/token-use", "agents-visualizer"),
            // A workspace of Superset's is its repository's, whatever its own made-up name.
            ("/Users/me/.superset/worktrees/shop-web/brave-otter-d8de43d5", "shop-web"),
            ("/Users/me/.superset/worktrees/shop.web/quiet-heron-01813747", "shop.web"),
            ("/Users/me/.superset/worktrees/api/tidy-lark/packages/web", "api"),
            ("/Users/me/.superset/sessions/calm-river", "Superset sessions"),
            // A session's scratch folder names its session's folder only in encoded form.
            ("/private/tmp/claude-501/-Users-me--superset-projects-agents-visualizer/6496ec8c-5e10/scratchpad/spike/proj", "agents-visualizer"),
            ("/private/tmp/claude-501/-Users-me--superset-worktrees-mobile-app-brave-otter-d8de43d5/9b5cc18a/scratchpad/eu", "mobile-app"),
            ("/tmp/claude-501/-Users-me--superset-projects-agents-visualizer/6496ec8c/scratchpad", "agents-visualizer"),
            ("/private/tmp/claude-501/-Users-me--superset-projects-gone-long-ago/0b15/scratchpad/ptest", "Scratch"),
            ("/private/tmp/claude-501", "Scratch"),
            ("/private/var/folders/ab/1cd2ef3gh4ij5kl6mn7op8qr0000gn/T/tmpab1cd2ef", "Temporary folders"),
            ("/private/tmp", "Temporary folders"),
            ("/var/folders/ab/T", "Temporary folders"),
            ("/Users/me", "~"),
            ("/Users/me/Documents/work/docs", "docs"),
            ("/Users/me/Documents/work/docs/", "docs"),
            // Its own folder name: a tool's worktree this app does not know.
            ("/Users/me/.othertool/worktrees/demo-4b2f35/run-20260927-2051/backend", "backend"),
            ("", "Unknown folder"),
        ]
        for (folder, name) in cases {
            XCTAssertEqual(Projects.name(of: folder, home: home, known: known), name, folder)
        }
    }

    func testAFolderEncodedAsClaudeCodeSpellsIt() {
        XCTAssertEqual(Projects.encoded("/Users/me/.superset/projects/agents-visualizer"), "-Users-me--superset-projects-agents-visualizer")
        XCTAssertEqual(Projects.encoded("/a/b_c.d e"), "-a-b-c-d-e")
        // Two folders spelled alike: the first is kept.
        XCTAssertEqual(Projects.known(["/a/b.c", "/a/b-c"]), ["-a-b-c": "/a/b.c"])
    }
}
