import ArgumentParser
import Foundation

struct InputCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "input",
        abstract: "Read newline-delimited JSON gestures from stdin, ack each on stdout"
    )

    @OptionGroup var options: DeviceOption

    func run() async {
        let simulators = CoreSimulators(deviceSetPath: options.deviceSet)
        guard let simulator = simulators.find(udid: options.udid) else {
            log("Device \(options.udid) not found")
            Foundation.exit(1)
        }
        let input = simulator.input()
        let pasteboard = simulator.pasteboard()
        let dispatcher = GestureDispatcher(input: input)
        log("Input session started, reading from stdin")
        while let line = readLine() {
            // `paste` / `copy` need the async pasteboard surface, so
            // they are intercepted ahead of the sync gesture pipeline
            // — same shape as `describe_ui` on the WS path. Awaiting
            // in-line preserves the one-line-in/one-ack-out order.
            if let ack = await PasteDispatch.dispatch(
                line: line, pasteboard: pasteboard, input: input
            ).ackJSON {
                print(ack)
            } else if let ack = await CopyDispatch.dispatch(
                line: line, pasteboard: pasteboard, input: input
            ).ackJSON {
                print(ack)
            } else {
                print(dispatcher.dispatch(line: line))
            }
            fflush(stdout)
        }
        log("stdin closed, input session ending")
    }
}
