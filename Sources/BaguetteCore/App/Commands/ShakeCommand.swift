import ArgumentParser
import Foundation

/// `baguette shake --udid <UDID>`
///
/// Delivers a motion shake to the booted simulator — the same signal as
/// Simulator.app's "Device → Shake". Backed by `simctl spawn <udid>
/// notifyutil -p com.apple.UIKit.SimulatorShake`, which posts the Darwin
/// notification UIKit's shake detection observes into the guest's notify
/// namespace. The value-domain projection lives in
/// `Domain/Shake/MotionShake.swift`; the spawn is in
/// `Infrastructure/Shake/SimctlShake.swift`.
struct ShakeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shake",
        abstract: "Shake the booted simulator (fires UIKit motionShake)"
    )

    @OptionGroup var options: DeviceOption

    func run() async throws {
        let simulators = CoreSimulators(deviceSetPath: options.deviceSet)
        guard let simulator = simulators.find(udid: options.udid) else {
            log("Device \(options.udid) not found")
            throw ExitCode.failure
        }
        guard simulator.canAcceptInput else {
            log("Device \(simulator.name) is not booted")
            throw ExitCode.failure
        }
        do {
            try await simulator.shake().shake()
        } catch {
            log("shake failed: \(error)")
            throw ExitCode.failure
        }
        log("Shook \(simulator.name)")
    }
}
