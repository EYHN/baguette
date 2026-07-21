import Foundation

/// Single-line stderr log. Stdout is reserved for stream output / acks;
/// every other message goes here so it doesn't corrupt the wire.
func log(_ message: String) {
    fputs("[baguette] \(message)\n", stderr)
}

/// Like `log`, but marked as a warning — tinted yellow when stderr is a
/// terminal, plain (and still marked) when it's redirected.
func warn(_ message: String) {
    let styled = TerminalStyle.warning(message, colored: terminalColorized(STDERR_FILENO))
    fputs("[baguette] \(styled)\n", stderr)
}

/// Whether the given file descriptor should carry ANSI colour.
///
/// The `isatty` probe and the environment read are the only impure
/// parts; the decision itself lives in `TerminalStyle` and is covered.
func terminalColorized(_ fileDescriptor: Int32) -> Bool {
    TerminalStyle.shouldColorize(
        isTTY: isatty(fileDescriptor) == 1,
        environment: ProcessInfo.processInfo.environment
    )
}
