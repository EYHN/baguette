import Testing
import Foundation
@testable import BaguetteCore

/// `SimulatorLifetime` is the value-typed reading of Simulator.app's
/// device lifetime policy — the two preferences Apple groups under
/// "Simulator lifetime" in `Simulator.app/Contents/Resources/
/// Settings.bundle/Root.plist`:
///
///   DetachOnWindowClose — "When closing a simulator's window leave it running"
///   DetachOnAppQuit     — "When quitting leave simulators running"
///
/// Both default to `false`, which is why a device booted headlessly by
/// baguette dies the moment someone closes its window in Simulator.app.
///
/// This is CLAUDE.md's one-shot-fetch split: the irreducible call is a
/// pair of `CFPreferences` reads/writes in Infrastructure, and
/// everything downstream of the fetched plist lives here as a pure
/// factory — so no `@Mockable` collaborator is needed.
@Suite("SimulatorLifetime")
struct SimulatorLifetimeTests {

    // MARK: - Reading

    @Test func `an absent preference reads as Apple's shutdown default`() {
        // A machine that has never touched these keys has no entry at
        // all — not `false`. Absence must read as shutdown, because
        // that is what Simulator.app actually does.
        let lifetime = SimulatorLifetime.from(plist: [:])
        #expect(lifetime == .appleDefault)
        #expect(lifetime.detachOnWindowClose == false)
        #expect(lifetime.detachOnAppQuit == false)
    }

    @Test func `both keys set reads as fully detached`() {
        let lifetime = SimulatorLifetime.from(plist: [
            "DetachOnWindowClose": NSNumber(value: true),
            "DetachOnAppQuit": NSNumber(value: true),
        ])
        #expect(lifetime == .detached)
    }

    @Test func `defaults-write booleans arrive as NSNumber and parse either way`() {
        // `defaults write … -bool YES` stores a CFBoolean, which bridges
        // to NSNumber on the way back out of CFPreferences.
        let on = SimulatorLifetime.from(plist: ["DetachOnWindowClose": NSNumber(value: true)])
        #expect(on.detachOnWindowClose == true)

        let off = SimulatorLifetime.from(plist: ["DetachOnWindowClose": NSNumber(value: false)])
        #expect(off.detachOnWindowClose == false)
    }

    @Test func `a string written without -bool parses the way NSUserDefaults would`() {
        // `defaults write … DetachOnAppQuit YES` (no -bool) stores the
        // *string* "YES". `-[NSUserDefaults boolForKey:]` still reads
        // that as true, so reporting it as false would misdescribe what
        // Simulator.app is going to do.
        for truthy in ["YES", "true", "1"] {
            #expect(SimulatorLifetime.from(plist: ["DetachOnAppQuit": truthy]).detachOnAppQuit == true,
                    "expected \(truthy) to read as true")
        }
        for falsy in ["NO", "false", "0"] {
            #expect(SimulatorLifetime.from(plist: ["DetachOnAppQuit": falsy]).detachOnAppQuit == false,
                    "expected \(falsy) to read as false")
        }
    }

    @Test func `a value of an unreadable type falls back to shutdown`() {
        // Garbage in the domain shouldn't be reported as "you're safe".
        let lifetime = SimulatorLifetime.from(plist: ["DetachOnWindowClose": ["nested": 1]])
        #expect(lifetime.detachOnWindowClose == false)
    }

    @Test func `each key is read independently`() {
        let lifetime = SimulatorLifetime.from(plist: ["DetachOnWindowClose": NSNumber(value: true)])
        #expect(lifetime.detachOnWindowClose == true)
        #expect(lifetime.detachOnAppQuit == false)
    }

    // MARK: - Surviving Simulator.app

    @Test func `a device survives Simulator app only when both routes detach`() {
        #expect(SimulatorLifetime.detached.survivesSimulatorApp == true)
        #expect(SimulatorLifetime.appleDefault.survivesSimulatorApp == false)

        // Detaching on one route alone still loses the device by the
        // other — closing the window and quitting the app are separate
        // ways to lose a booted simulator.
        let closeOnly = SimulatorLifetime(detachOnWindowClose: true, detachOnAppQuit: false)
        #expect(closeOnly.survivesSimulatorApp == false)

        let quitOnly = SimulatorLifetime(detachOnWindowClose: false, detachOnAppQuit: true)
        #expect(quitOnly.survivesSimulatorApp == false)
    }

    // MARK: - Writing

    @Test func `the patch carries both keys under Simulator app's own names`() {
        // These spellings are the contract with Simulator.app; a typo
        // here writes a key nothing reads.
        let patch = SimulatorLifetime.detached.plistPatch
        #expect(patch["DetachOnWindowClose"] == true)
        #expect(patch["DetachOnAppQuit"] == true)
        #expect(patch.count == 2)
    }

    @Test func `the patch writes both keys explicitly when reverting`() {
        // Reverting must write `false`, not remove the keys — a user who
        // opted in should see the revert land in `defaults read`.
        let patch = SimulatorLifetime.appleDefault.plistPatch
        #expect(patch["DetachOnWindowClose"] == false)
        #expect(patch["DetachOnAppQuit"] == false)
    }

    @Test func `a patch round-trips back through the reader`() {
        for lifetime in [SimulatorLifetime.detached,
                         .appleDefault,
                         SimulatorLifetime(detachOnWindowClose: true, detachOnAppQuit: false)] {
            let round = SimulatorLifetime.from(plist: lifetime.plistPatch)
            #expect(round == lifetime)
        }
    }

    // MARK: - Changing the policy

    @Test func `asking for the policy already in place writes nothing`() {
        let change = SimulatorLifetime.detached.change(
            to: .detached,
            simulatorAppRunning: false
        )
        #expect(change == .unchanged)
    }

    @Test func `asking for a different policy applies it`() {
        let change = SimulatorLifetime.appleDefault.change(
            to: .detached,
            simulatorAppRunning: false
        )
        #expect(change == .applied(restartSimulatorApp: false))
    }

    @Test func `applying while Simulator app runs asks for a restart`() {
        // A running Simulator.app may hold a cached copy of these keys
        // and flush it back over the write when it quits, so the user
        // has to be told the change isn't reliably live yet.
        let change = SimulatorLifetime.appleDefault.change(
            to: .detached,
            simulatorAppRunning: true
        )
        #expect(change == .applied(restartSimulatorApp: true))
    }

    @Test func `a no-op change never asks for a restart`() {
        // Nothing was written, so there is nothing for a running
        // Simulator.app to clobber.
        let change = SimulatorLifetime.detached.change(
            to: .detached,
            simulatorAppRunning: true
        )
        #expect(change == .unchanged)
    }

    @Test func `reverting to Apple's default is an ordinary change`() {
        let change = SimulatorLifetime.detached.change(
            to: .appleDefault,
            simulatorAppRunning: false
        )
        #expect(change == .applied(restartSimulatorApp: false))
    }

    @Test func `a partial policy still counts as a change toward detached`() {
        let partial = SimulatorLifetime(detachOnWindowClose: true, detachOnAppQuit: false)
        let change = partial.change(to: .detached, simulatorAppRunning: false)
        #expect(change == .applied(restartSimulatorApp: false))
    }

    // MARK: - Advising the user

    @Test func `a policy that loses devices advises the fix by name`() throws {
        // `serve` prints this at startup; it has to name the command
        // that fixes it, or it is just noise.
        let advisory = try #require(SimulatorLifetime.appleDefault.advisory)
        #expect(advisory.contains("baguette lifetime --detach"))
    }

    @Test func `Apple's default names both routes because both shut down`() throws {
        let advisory = try #require(SimulatorLifetime.appleDefault.advisory)
        #expect(advisory.contains("window"))
        #expect(advisory.contains("quits"))
    }

    @Test func `detaching on window close leaves only the quit route named`() throws {
        // Closing the window no longer shuts this device down, so saying
        // it does would misdescribe what Simulator.app will actually do.
        // Reachable from Simulator → Settings, where the two keys are
        // independent checkboxes.
        let partial = SimulatorLifetime(detachOnWindowClose: true, detachOnAppQuit: false)
        let advisory = try #require(partial.advisory)
        #expect(advisory.contains("quits"))
        #expect(!advisory.contains("window"))
    }

    @Test func `detaching on quit leaves only the window route named`() throws {
        let partial = SimulatorLifetime(detachOnWindowClose: false, detachOnAppQuit: true)
        let advisory = try #require(partial.advisory)
        #expect(advisory.contains("window"))
        #expect(!advisory.contains("quits"))
    }

    @Test func `every advising policy still names the fix`() throws {
        // Whichever routes are live, the advisory has to stay actionable.
        for lifetime in [SimulatorLifetime.appleDefault,
                         SimulatorLifetime(detachOnWindowClose: true, detachOnAppQuit: false),
                         SimulatorLifetime(detachOnWindowClose: false, detachOnAppQuit: true)] {
            let advisory = try #require(lifetime.advisory)
            #expect(advisory.contains("baguette lifetime --detach"))
        }
    }

    @Test func `a policy that survives Simulator app says nothing`() {
        #expect(SimulatorLifetime.detached.advisory == nil)
    }
}
