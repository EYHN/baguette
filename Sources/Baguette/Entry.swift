import ArgumentParser
import BaguetteCore

/// The CLI entry point. `Baguette` is an `AsyncParsableCommand` living in
/// BaguetteCore; calling its `main()` from top-level code (a `main.swift`)
/// resolves to the synchronous overload, which runs the default `run()` —
/// the help screen — for every async subcommand. A function body picks the
/// async one.
@main
enum Entry {
    static func main() async {
        await Baguette.main()
    }
}
