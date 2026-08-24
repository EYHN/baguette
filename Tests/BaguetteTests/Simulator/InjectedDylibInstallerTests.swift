import Testing
import Foundation
@testable import BaguetteCore

/// Coverage for the install layout shared by every dylib baguette injects.
///
/// Generalised from the camera's installer once motion became a second
/// consumer: the layout, the sha-keying and the idempotence rule are
/// identical, and only the dylib's name differs.
@Suite("InjectedDylibInstallPlan")
struct InjectedDylibInstallPlanTests {

    @Test func `dest path is supportDir + builds + first 12 sha256 hex chars`() {
        let plan = InjectedDylibInstallPlan.compute(
            bytes: Data("hello".utf8), supportDir: "/tmp/baguette-test", dylib: .camera)
        // sha256("hello") prefix = "2cf24dba5fb0".
        #expect(plan.sha12 == "2cf24dba5fb0")
        #expect(plan.buildDir == "/tmp/baguette-test/builds/2cf24dba5fb0")
        #expect(plan.destPath == "/tmp/baguette-test/builds/2cf24dba5fb0/VirtualCamera.dylib")
    }

    @Test func `each dylib keeps its own file name`() {
        let plan = InjectedDylibInstallPlan.compute(
            bytes: Data("hello".utf8), supportDir: "/s", dylib: .motion)
        #expect(plan.destPath == "/s/builds/2cf24dba5fb0/VirtualMotion.dylib")
    }

    @Test func `different bytes produce different per-hash dirs`() {
        // The sha-keyed directory is what dodges iOS 26's dyld page-hash
        // cache rejecting a replaced dylib at a path it has already seen.
        let a = InjectedDylibInstallPlan.compute(bytes: Data([0x01]), supportDir: "/s",
                                                 dylib: .camera)
        let b = InjectedDylibInstallPlan.compute(bytes: Data([0x02]), supportDir: "/s",
                                                 dylib: .camera)
        #expect(a.buildDir != b.buildDir)
    }

    @Test func `every dylib of the same build lands beside the others`() {
        // Same bytes, different dylibs: the directory is shared, the file
        // names differ. All of them can be armed at once, which is the
        // whole point of `InjectedDylibs` merging by file name.
        let plans = [InjectedDylib.camera, .motion, .network].map {
            InjectedDylibInstallPlan.compute(bytes: Data([0x01]), supportDir: "/s", dylib: $0)
        }
        #expect(Set(plans.map(\.buildDir)).count == 1)
        #expect(Set(plans.map(\.destPath)).count == plans.count)
    }

    @Test func `each dylib has its own environment override`() {
        #expect(InjectedDylib.camera.environmentOverride == "BAGUETTE_VIRTUALCAMERA_DYLIB")
        #expect(InjectedDylib.motion.environmentOverride == "BAGUETTE_VIRTUALMOTION_DYLIB")
        #expect(InjectedDylib.network.environmentOverride == "BAGUETTE_VIRTUALNETWORK_DYLIB")
    }

    @Test func `each dylib knows where it sits in the source tree`() {
        // The dev-build fallback walks up from the executable looking for
        // this path. All three live under one `Injected/` folder, so the
        // lookup has to name it — a bare `<Name>/<Name>.dylib` stopped
        // resolving the moment they moved.
        #expect(InjectedDylib.camera.sourceTreePath == "Injected/VirtualCamera/VirtualCamera.dylib")
        #expect(InjectedDylib.motion.sourceTreePath == "Injected/VirtualMotion/VirtualMotion.dylib")
        #expect(InjectedDylib.network.sourceTreePath
                    == "Injected/VirtualNetwork/VirtualNetwork.dylib")
    }

    @Test func `the network dylib installs under its own file name`() {
        let plan = InjectedDylibInstallPlan.compute(
            bytes: Data("hello".utf8), supportDir: "/s", dylib: .network)
        #expect(plan.destPath == "/s/builds/2cf24dba5fb0/VirtualNetwork.dylib")
    }
}

@Suite("InjectedDylibInstaller — applies the plan to disk")
struct InjectedDylibInstallerApplyTests {

    @Test func `writes the dylib bytes to the computed destPath`() throws {
        let scratch = NSTemporaryDirectory() + "baguette-installer-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let bytes = Data([0xAA, 0xBB, 0xCC])
        let plan = InjectedDylibInstallPlan.compute(bytes: bytes, supportDir: scratch,
                                                    dylib: .motion)
        try InjectedDylibInstaller.apply(plan: plan, bytes: bytes)

        #expect(try Data(contentsOf: URL(fileURLWithPath: plan.destPath)) == bytes)
    }

    @Test func `apply is idempotent — second call is a no-op when the file already exists`() throws {
        // Rewriting would replace the linker's adhoc signature, which iOS 26's
        // simulator dyld rejects after any post-build re-sign.
        let scratch = NSTemporaryDirectory() + "baguette-installer-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let bytes = Data([0x01, 0x02, 0x03])
        let plan = InjectedDylibInstallPlan.compute(bytes: bytes, supportDir: scratch,
                                                    dylib: .camera)
        try InjectedDylibInstaller.apply(plan: plan, bytes: bytes)
        let url = URL(fileURLWithPath: plan.destPath)
        let before = try url.resourceValues(forKeys: [.contentModificationDateKey])
        Thread.sleep(forTimeInterval: 0.05)
        try InjectedDylibInstaller.apply(plan: plan, bytes: bytes)
        let after = try url.resourceValues(forKeys: [.contentModificationDateKey])

        #expect(before.contentModificationDate == after.contentModificationDate)
    }
}
