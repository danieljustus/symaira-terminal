import SwiftUI
import WebKit

@MainActor
public struct WorkflowCanvasView: View {
    @State private var webView = WKWebView()

    public init() {}

    public var body: some View {
        WorkflowCanvasWebViewRepresentable(webView: webView)
            .background(Color(red: 11/255.0, green: 13/255.0, blue: 17/255.0))
            .onAppear {
                loadLocalHTML()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.symaira.terminal.updateCanvasNodeStatus"))) { notification in
                if let userInfo = notification.userInfo,
                   let nodeID = userInfo["nodeID"] as? String,
                   let status = userInfo["status"] as? String {
                    let js = "if (window.symairaCanvasAPI) { window.symairaCanvasAPI.updateNodeStatus('\(nodeID)', '\(status)'); }"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
    }

    private func loadLocalHTML() {
        // Find index.html inside the main app bundle Resources/WorkflowCanvas
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WorkflowCanvas") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // Fallback for development if resources are loaded differently or via SPM resources
            let devPath = "/Users/daniel/Dev/Symaira Dev/symaira-terminal/Resources/WorkflowCanvas/index.html"
            let url = URL(fileURLWithPath: devPath)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}

@MainActor
struct WorkflowCanvasWebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        let config = webView.configuration
        let contentController = config.userContentController

        // Remove existing handlers to avoid duplicates
        contentController.removeScriptMessageHandler(forName: "symairaCanvas")
        contentController.add(context.coordinator, name: "symairaCanvas")

        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WorkflowCanvasWebViewRepresentable

        init(_ parent: WorkflowCanvasWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Load saved workflow on finish
            let saved = UserDefaults.standard.string(forKey: "symaira.workflow.canvas") ?? ""
            if !saved.isEmpty {
                let js = "if (window.symairaCanvasAPI) { window.symairaCanvasAPI.loadWorkflow(\(JSONStringEscape(saved))); }"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let action = dict["action"] as? String else {
                return
            }

            if action == "save", let workflow = dict["workflow"] as? String {
                UserDefaults.standard.set(workflow, forKey: "symaira.workflow.canvas")
            } else if action == "run", let workflow = dict["workflow"] as? String {
                // Trigger workflow execution via notification
                NotificationCenter.default.post(
                    name: Notification.Name("com.symaira.terminal.runWorkflow"),
                    object: nil,
                    userInfo: ["workflow": workflow]
                )
            }
        }

        private func JSONStringEscape(_ str: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [str], options: []),
                  let json = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            // Strip the enclosing brackets [ ]
            return String(json.dropFirst().dropLast())
        }
    }
}
