import ArgumentParser
import Foundation

struct BootCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "boot",
        abstract: "Boot a simulator headlessly"
    )

    @OptionGroup var options: DeviceOption

    @Flag(name: .customLong("no-heal"),
          help: "Leave the input surface alone even if Xcode 27's Device Hub has shadowed it (see `baguette heal`).")
    var noHeal = false

    func run() async {
        let simulators = CoreSimulators(deviceSetPath: options.deviceSet)
        guard let simulator = simulators.find(udid: options.udid) else {
            log("Device \(options.udid) not found")
            Foundation.exit(1)
        }
        do {
            try simulator.boot()
            log("Booted \(simulator.name)")
            if let advisory = SimulatorAppPreferences.lifetime().advisory {
                warn(advisory)
            }
        } catch {
            log("Boot failed: \(error)")
            Foundation.exit(1)
        }
        // Under Xcode 27, Device Hub attaches to the device as it boots
        // and — depending on a race inside backboardd — can leave the
        // legacy input surface dead for the rest of the boot. Nothing is
        // running yet, so the SpringBoard restart that fixes it is free.
        guard !noHeal else { return }
        do {
            if try await SimctlInputSurface().healAfterBoot(on: simulator) == .reclaimed {
                log(HealOutcome.reclaimed.summary)
            }
        } catch {
            warn("Input surface heal failed: \(error) — run `baguette heal --udid \(options.udid)` to retry")
        }
    }
}
