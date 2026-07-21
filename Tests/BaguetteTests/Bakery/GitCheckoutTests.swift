import Testing
import Foundation
import Mockable
@testable import BaguetteCore

/// Orchestration coverage for `GitCheckout` — argv assembly, the
/// non-interactive / no-submodule safety flags, and the
/// clone-then-rev-parse handshake. The real `git` spawn lives in
/// `HostSubprocess` (integration-only); every branch here runs through
/// `MockSubprocess`, mirroring `SimctlLocationTests`.
@Suite("GitCheckout")
struct GitCheckoutTests {

    final class Captures: @unchecked Sendable {
        var calls: [[String]] = []          // arguments of each spawn, in order
        var environments: [[String: String]?] = []
    }

    /// A mock that answers each spawn: clone exits 0, `rev-parse`
    /// prints the commit. Matched by whether the argv contains
    /// "rev-parse".
    /// `pinnedHead` models a clone whose default branch already sits on
    /// the pinned sha, so no extra fetch is needed. Leave it nil and
    /// `rev-parse` always answers `commit`.
    private func makeCheckout(
        commit: String = "abc123", cloneExit: Int32 = 0, pinnedHead: String? = nil
    ) -> (GitCheckout, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, workingDirectory: .any,
            environment: .any, stdin: .any, onBytes: .any, onExit: .any
        ).willProduce { _, args, _, env, _, onBytes, onExit in
            captures.calls.append(args)
            captures.environments.append(env)
            if args.contains("rev-parse") {
                onBytes(Data("\(pinnedHead ?? commit)\n".utf8))
                onExit(0)
            } else {
                onExit(cloneExit)
            }
        }
        given(sub).terminate().willReturn()
        given(sub).kill().willReturn()
        return (GitCheckout(subprocess: { sub }), captures)
    }

    @Test func `clone shallow-fetches the url with no submodules`() async throws {
        let (git, captures) = makeCheckout()
        let ref = try BakeryRef.parse("acme/tools")
        let dest = URL(fileURLWithPath: "/tmp/cache/github.com/acme/tools")
        _ = try await git.clone(ref, into: dest, at: nil)

        let clone = try #require(captures.calls.first)
        #expect(clone.contains("clone"))
        #expect(clone.contains("--depth"))
        #expect(clone.contains("1"))
        #expect(clone.contains(ref.cloneURL))
        #expect(clone.contains(dest.path))
        // No submodule recursion — a bakery must not drag in arbitrary
        // submodule URLs.
        #expect(!clone.contains("--recurse-submodules"))
    }

    @Test func `clone runs git non-interactively so a bad url fails fast`() async throws {
        // GIT_TERMINAL_PROMPT=0 turns a private/missing repo into an
        // immediate failure instead of a hang on a credential prompt.
        let (git, captures) = makeCheckout()
        _ = try await git.clone(try BakeryRef.parse("acme/tools"), into: URL(fileURLWithPath: "/tmp/x"), at: nil)
        #expect(captures.environments.first??["GIT_TERMINAL_PROMPT"] == "0")
    }

    @Test func `clone reports the pinned commit via rev-parse`() async throws {
        let (git, captures) = makeCheckout(commit: "deadbeef")
        let result = try await git.clone(try BakeryRef.parse("acme/tools"), into: URL(fileURLWithPath: "/tmp/x"), at: nil)
        #expect(result.commit == "deadbeef")
        // Second call resolves HEAD in the freshly cloned dir.
        #expect(captures.calls.last?.contains("rev-parse") == true)
    }

    @Test func `a failed clone throws rather than reporting a bogus commit`() async throws {
        let (git, _) = makeCheckout(cloneExit: 128)
        await #expect(throws: (any Error).self) {
            _ = try await git.clone(try BakeryRef.parse("acme/tools"), into: URL(fileURLWithPath: "/tmp/x"), at: nil)
        }
    }

    // MARK: - pull

    @Test func `pull fast-forwards in place and reports the new commit`() async throws {
        // What `bakery update` runs. `--ff-only` so an update can never
        // produce a merge commit in a cache directory nobody looks at,
        // and `-C` so it operates on the clone rather than the cwd.
        let (git, captures) = makeCheckout(commit: "deadbee")
        let commit = try await git.pull(at: URL(fileURLWithPath: "/tmp/cache/acme/tools"))

        #expect(commit == "deadbee")
        #expect(captures.calls.first == [
            "-C", "/tmp/cache/acme/tools", "pull", "--depth", "1", "--ff-only",
        ])
        #expect(captures.calls.last == ["-C", "/tmp/cache/acme/tools", "rev-parse", "HEAD"])
    }

    @Test func `a pull that cannot fast-forward throws instead of pinning the old commit`() async throws {
        // A force-push upstream fails `--ff-only`. Reporting the stale
        // commit would record an update that didn't happen.
        let sub = MockSubprocess()
        given(sub).run(
            executable: .any, arguments: .any, workingDirectory: .any,
            environment: .any, stdin: .any, onBytes: .any, onExit: .any
        ).willProduce { _, args, _, _, _, _, onExit in
            onExit(args.contains("pull") ? 1 : 0)
        }
        given(sub).terminate().willReturn()
        let git = GitCheckout(subprocess: { sub })

        await #expect(throws: (any Error).self) {
            _ = try await git.pull(at: URL(fileURLWithPath: "/tmp/cache/acme/tools"))
        }
    }

    // MARK: - asking the remote without cloning

    @Test func `head asks ls-remote and reads the sha off the answer`() async throws {
        // `bakery outdated` needs the remote's current commit, and
        // cloning every trusted bakery to find out would be absurd.
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, workingDirectory: .any,
            environment: .any, stdin: .any, onBytes: .any, onExit: .any
        ).willProduce { _, args, _, _, _, onBytes, onExit in
            captures.calls.append(args)
            onBytes(Data("9f8e7d6c5b4a\trefs/heads/main\n".utf8))
            onExit(0)
        }
        given(sub).terminate().willReturn()
        given(sub).kill().willReturn()
        let git = GitCheckout(subprocess: { sub })

        let head = try await git.head(of: try BakeryRef.parse("acme/tools"))
        #expect(head == "9f8e7d6c5b4a")
        let call = try #require(captures.calls.first)
        #expect(call.contains("ls-remote"))
        #expect(call.contains("https://github.com/acme/tools.git"))
    }

    // MARK: - the pin

    @Test func `an unpinned clone reports whatever HEAD was`() async throws {
        // First contact with a bakery: there's nothing to demand yet, so
        // we take the default branch and record what we got. That
        // recorded sha is what every later fetch is held to.
        let (git, captures) = makeCheckout(commit: "deadbeef")
        let result = try await git.clone(
            try BakeryRef.parse("acme/tools"), into: URL(fileURLWithPath: "/tmp/x"), at: nil
        )
        #expect(result.commit == "deadbeef")
        #expect(captures.calls.allSatisfy { !$0.contains("checkout") })
    }

    @Test func `a pinned clone whose branch has moved fetches the pin by name`() async throws {
        // The recorded commit has to *constrain* what we fetch, not just
        // describe it. A shallow clone of a moving branch hands back
        // whatever HEAD is today, so the pin is asked for by name and
        // checked out.
        let captures = Captures()
        let sub = MockSubprocess()
        let revParseCount = Counter()
        given(sub).run(
            executable: .any, arguments: .any, workingDirectory: .any,
            environment: .any, stdin: .any, onBytes: .any, onExit: .any
        ).willProduce { _, args, _, _, _, onBytes, onExit in
            captures.calls.append(args)
            if args.contains("rev-parse") {
                // The branch has moved on; only after checking the pin
                // out are we standing on it.
                let landed = revParseCount.next() == 0 ? "f00d999" : "aaaa111"
                onBytes(Data("\(landed)\n".utf8))
            }
            onExit(0)
        }
        given(sub).terminate().willReturn()
        given(sub).kill().willReturn()
        let git = GitCheckout(subprocess: { sub })

        let result = try await git.clone(
            try BakeryRef.parse("acme/tools"), into: URL(fileURLWithPath: "/tmp/x"), at: "aaaa111"
        )
        #expect(result.commit == "aaaa111")
        let fetch = try #require(captures.calls.first { $0.contains("fetch") })
        #expect(fetch.contains("aaaa111"))
        #expect(captures.calls.contains { $0.contains("checkout") })
    }

    @Test func `a pinned clone already sitting on the pin fetches nothing extra`() async throws {
        // The common case — the bakery hasn't moved since it was
        // trusted. Paying for a second network round-trip to confirm
        // what the clone already told us would be waste.
        let (git, captures) = makeCheckout(commit: "aaaa111", pinnedHead: "aaaa111")
        let result = try await git.clone(
            try BakeryRef.parse("acme/tools"), into: URL(fileURLWithPath: "/tmp/x"), at: "aaaa111"
        )
        #expect(result.commit == "aaaa111")
        #expect(captures.calls.allSatisfy { !$0.contains("fetch") })
        #expect(captures.calls.allSatisfy { !$0.contains("checkout") })
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            let current = value
            value += 1
            return current
        }
    }

    @Test func `a pin the remote will not serve fails rather than silently taking HEAD`() async throws {
        // The dangerous failure: the bakery force-pushed the pinned
        // commit away, and we quietly install whatever replaced it.
        let sub = MockSubprocess()
        given(sub).run(
            executable: .any, arguments: .any, workingDirectory: .any,
            environment: .any, stdin: .any, onBytes: .any, onExit: .any
        ).willProduce { _, args, _, _, _, onBytes, onExit in
            if args.contains("rev-parse") {
                onBytes(Data("f00d999\n".utf8))   // never the pinned sha
                onExit(0)
            } else if args.contains("fetch") {
                onExit(128)                       // remote refuses the sha
            } else {
                onExit(0)
            }
        }
        given(sub).terminate().willReturn()
        given(sub).kill().willReturn()
        let git = GitCheckout(subprocess: { sub })

        await #expect(throws: GitCheckoutError.self) {
            _ = try await git.clone(
                try BakeryRef.parse("acme/tools"),
                into: URL(fileURLWithPath: "/tmp/x"), at: "aaaa111"
            )
        }
    }

    // MARK: - the deadline

    @Test func `a git that stalls past its deadline is stopped and reported`() async throws {
        // GIT_TERMINAL_PROMPT=0 only rules out a *credential* hang. A
        // remote that accepts the connection and then stops sending
        // leaves git running and this continuation unresumed — and
        // `POST /bakeries/preview` reaches clone, so one such remote
        // would hold a server task open indefinitely.
        let child = StalledChild()
        let git = GitCheckout(
            subprocess: { child },
            timeout: .milliseconds(20),
            grace: .milliseconds(20)
        )

        await #expect(throws: GitCheckoutError.self) {
            _ = try await git.pull(at: URL(fileURLWithPath: "/tmp/cache/acme/tools"))
        }
        #expect(child.terminated)
        #expect(child.killed)
    }

    /// A git that never finishes and ignores SIGTERM — the shape a
    /// stalled network fetch actually takes.
    final class StalledChild: Subprocess, @unchecked Sendable {
        private let lock = NSLock()
        private var onExit: (@Sendable (Int32) -> Void)?
        private(set) var terminated = false
        private(set) var killed = false

        func run(
            executable: URL, arguments: [String],
            onBytes: @escaping @Sendable (Data) -> Void,
            onExit: @escaping @Sendable (Int32) -> Void
        ) throws { store(onExit) }

        func run(
            executable: URL, arguments: [String], stdin: Data,
            onBytes: @escaping @Sendable (Data) -> Void,
            onExit: @escaping @Sendable (Int32) -> Void
        ) throws { store(onExit) }

        func run(
            executable: URL, arguments: [String], workingDirectory: URL,
            environment: [String: String], stdin: Data,
            onBytes: @escaping @Sendable (Data) -> Void,
            onExit: @escaping @Sendable (Int32) -> Void
        ) throws { store(onExit) }

        private func store(_ handler: @escaping @Sendable (Int32) -> Void) {
            lock.lock(); defer { lock.unlock() }
            onExit = handler
        }

        func terminate() {
            lock.lock(); defer { lock.unlock() }
            terminated = true
        }

        func kill() {
            lock.lock()
            killed = true
            let handler = onExit
            onExit = nil
            lock.unlock()
            handler?(-9)
        }
    }

    @Test func `a git that cannot be spawned surfaces its own error`() async throws {
        // Distinct from a non-zero exit — git never ran.
        struct SpawnRefused: Error {}
        let sub = MockSubprocess()
        given(sub).run(
            executable: .any, arguments: .any, workingDirectory: .any,
            environment: .any, stdin: .any, onBytes: .any, onExit: .any
        ).willThrow(SpawnRefused())
        given(sub).terminate().willReturn()
        let git = GitCheckout(subprocess: { sub })

        await #expect(throws: SpawnRefused.self) {
            _ = try await git.pull(at: URL(fileURLWithPath: "/tmp/cache/acme/tools"))
        }
    }
}
