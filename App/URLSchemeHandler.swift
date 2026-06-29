import Foundation

enum URLSchemeCommand {
    case openDirectory(URL)
    case openTab(command: String?, workingDirectory: URL?)
}

struct URLSchemeHandler {
    func parse(_ url: URL) -> URLSchemeCommand? {
        guard url.scheme == "symaira-terminal" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        switch components.host {
        case "open":
            if let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
               !path.isEmpty {
                let fileURL = URL(fileURLWithPath: path)
                guard validatePath(fileURL) else { return nil }
                return .openDirectory(fileURL)
            }
        case "new-tab":
            let command = components.queryItems?.first(where: { $0.name == "command" })?.value
            let cwdValue = components.queryItems?.first(where: { $0.name == "cwd" })?.value
            let workingDirectory = cwdValue.flatMap { validatePath(URL(fileURLWithPath: $0)) ? URL(fileURLWithPath: $0) : nil }
            return .openTab(command: command, workingDirectory: workingDirectory)
        default:
            break
        }
        return nil
    }

    private func validatePath(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }
}
