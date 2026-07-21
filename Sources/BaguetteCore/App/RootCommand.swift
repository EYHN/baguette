import ArgumentParser

public struct Baguette: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "baguette",
        abstract: "Headless iOS simulator control",
        version: baguetteVersion,
        subcommands: [
            ListCommand.self,
            BootCommand.self,
            ShutdownCommand.self,
            LifetimeCommand.self,
            InputCommand.self,
            StreamCommand.self,
            TapCommand.self,
            DoubleTapCommand.self,
            SwipeCommand.self,
            PinchCommand.self,
            PanCommand.self,
            PressCommand.self,
            KeyCommand.self,
            TypeCommand.self,
            PasteCommand.self,
            ClipboardCommand.self,
            ChromeCommand.self,
            ScreenshotCommand.self,
            Render3DCommand.self,
            DescribeUICommand.self,
            LogsCommand.self,
            ServeCommand.self,
            OrientationCommand.self,
            ShakeCommand.self,
            StatusBarCommand.self,
            InterfaceCommand.self,
            LocationCommand.self,
            InstallCommand.self,
            AddMediaCommand.self,
            PluginsCommand.self,
            BakeryCommand.self,
            DiagDigitizerTrackpadCommand.self,
        ]
    )
}
