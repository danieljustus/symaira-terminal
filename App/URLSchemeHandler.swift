import Foundation

enum URLSchemeCommand {
    case openDirectory(URL)
    case openTab(command: String?)
}

struct URLSchemeHandler {
    func parse(_ url: URL) -> URLSchemeCommand? {
        guard url.scheme == "symaira-terminal" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        switch components.host {
        case "open":
            if let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
               !path.isEmpty {
                return .openDirectory(URL(fileURLWithPath: path))
            }
        case "new-tab":
            let command = components.queryItems?.first(where: { $0.name == "command" })?.value
            return .openTab(command: command)
        default:
            break
        }
        return nil
    }
}
