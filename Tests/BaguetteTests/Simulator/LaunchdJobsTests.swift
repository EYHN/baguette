import Testing
@testable import Baguette

/// `launchctl list` inside a simulator prints one job per line —
/// `pid<TAB>status<TAB>label`, with `-` for a job that isn't running.
/// Reclaiming the input surface restarts backboardd and needs to know
/// when SpringBoard has come back with a *new* pid, so this parses just
/// enough of that table.
@Suite("LaunchdJobs")
struct LaunchdJobsTests {

    private let listing = """
        PID\tStatus\tLabel
        42499\t0\tcom.apple.backboardd
        37293\t0\tcom.apple.SpringBoard
        -\t0\tcom.apple.coredevice.dthidd
        -\t-9\tcom.apple.Preferences
        """

    @Test func `finds the pid of a running job by label`() {
        let jobs = LaunchdJobs.parsing(listing)
        #expect(jobs.pid(of: "com.apple.SpringBoard") == 37293)
        #expect(jobs.pid(of: "com.apple.backboardd") == 42499)
    }

    @Test func `a job that is not running has no pid`() {
        #expect(LaunchdJobs.parsing(listing).pid(of: "com.apple.coredevice.dthidd") == nil)
    }

    @Test func `an unknown label has no pid`() {
        #expect(LaunchdJobs.parsing(listing).pid(of: "com.apple.nothing") == nil)
    }

    @Test func `an empty or missing listing has no jobs`() {
        #expect(LaunchdJobs.parsing(nil).pid(of: "com.apple.SpringBoard") == nil)
        #expect(LaunchdJobs.parsing("").pid(of: "com.apple.SpringBoard") == nil)
    }
}
