import XCTest
@testable import BranchesKit

final class OrganizeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(_ display: DisplayStatus, quietFor: TimeInterval) -> SessionSnapshot {
        SessionSnapshot(
            id: SessionKey(.claude, UUID().uuidString), projectName: "p", projectPath: "/p", cwd: "/p", title: "t",
            status: StatusResult(display, .reported, since: now - quietFor, reason: "test"),
            lastActivityAt: now - quietFor
        )
    }

    func testWorkingOrNeedsYouIsActive() {
        XCTAssertEqual(ActivityTier.of([session(.idle, quietFor: 9000), session(.working, quietFor: 9000)], now: now), .active)
        XCTAssertEqual(ActivityTier.of([session(.needsYou, quietFor: 9000)], now: now), .active)
    }

    func testQuietWithinTheHourIsRecent() {
        XCTAssertEqual(ActivityTier.of([session(.done, quietFor: 59 * 60), session(.idle, quietFor: 9000)], now: now), .recent)
    }

    func testQuietLongerIsBackground() {
        XCTAssertEqual(ActivityTier.of([session(.done, quietFor: 61 * 60)], now: now), .background)
        XCTAssertEqual(ActivityTier.of([], now: now), .background)
    }

    func testPlainRepoResolvesToItsRoot() {
        let home = TempHome()
        home.write("code/app/.git/HEAD", "ref: refs/heads/main\n")
        let cwd = home.path("code/app/Sources/Deep").path
        try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        let r = ProjectRoot.resolve(cwd: cwd, home: home.url.path)
        XCTAssertEqual(r.root, home.path("code/app").path)
        XCTAssertNil(r.worktree)
    }

    func testWorktreeResolvesToMainRepository() {
        let home = TempHome()
        home.write("code/app/.git/worktrees/feature-x/HEAD", "ref: refs/heads/feature-x\n")
        home.write("code/app/.claude/worktrees/feature-x/.git", "gitdir: \(home.path("code/app/.git/worktrees/feature-x").path)\n")
        let r = ProjectRoot.resolve(cwd: home.path("code/app/.claude/worktrees/feature-x").path, home: home.url.path)
        XCTAssertEqual(r.root, home.path("code/app").path)
        XCTAssertEqual(r.worktree, "feature-x")
    }

    func testRelativeGitdirWorktree() {
        let home = TempHome()
        home.write("code/app/.git/worktrees/wt/HEAD", "x\n")
        home.write("code/app-wt/.git", "gitdir: ../app/.git/worktrees/wt\n")
        let r = ProjectRoot.resolve(cwd: home.path("code/app-wt").path, home: home.url.path)
        XCTAssertEqual(r.root, home.path("code/app").path)
        XCTAssertEqual(r.worktree, "app-wt")
    }

    func testSubmoduleStaysItsOwnProject() {
        let home = TempHome()
        home.write("code/app/.git/modules/lib/HEAD", "x\n")
        home.write("code/app/lib/.git", "gitdir: ../.git/modules/lib\n")
        let r = ProjectRoot.resolve(cwd: home.path("code/app/lib").path, home: home.url.path)
        XCTAssertEqual(r.root, home.path("code/app/lib").path)
        XCTAssertNil(r.worktree)
    }

    func testNoRepoFallsBackToCwd() {
        let home = TempHome()
        let cwd = home.path("scratch").path
        try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        XCTAssertEqual(ProjectRoot.resolve(cwd: cwd, home: home.url.path).root, cwd)
    }
}
