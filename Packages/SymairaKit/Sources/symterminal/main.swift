import ControlKit
import Foundation

// MARK: - Entry point

let cli = SymterminalCLI(arguments: Array(CommandLine.arguments.dropFirst()))
await cli.run()
