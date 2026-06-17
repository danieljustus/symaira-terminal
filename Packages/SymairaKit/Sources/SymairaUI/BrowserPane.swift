import AppKit
import WebKit

// MARK: - PaneKind

/// Distinguishes between terminal and browser panes in the pane manager.
public enum PaneKind: Sendable {
    case terminal
    case browser
}

// MARK: - BrowserPane

/// A browser pane that wraps WKWebView with an address bar and navigation controls.
/// Follows the same interface pattern as TerminalPane (`view: NSView`).
@MainActor
public final class BrowserPane: NSObject {
    public let paneID = UUID()
    public let kind: PaneKind = .browser

    /// The root view containing the address bar and web view.
    public var view: NSView { containerView }

    /// Current URL being displayed.
    public private(set) var currentURL: URL?

    /// Callback when the page title changes.
    public var onTitleChanged: ((String) -> Void)?

    /// Callback when the URL changes.
    public var onURLChanged: ((URL?) -> Void)?

    private var webView: WKWebView!
    private var urlField: NSTextField!
    private var goButton: NSButton!
    private var reloadButton: NSButton!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var loadingIndicator: NSProgressIndicator!

    private lazy var containerView: NSView = {
        let container = NSView()

        // Toolbar
        let toolbar = createToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)

        // WebView
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        self.webView = wv
        container.addSubview(wv)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 36),

            wv.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }()

    public override init() {
        super.init()
        // Eagerly create the container view
        _ = containerView
    }

    /// Navigate to a URL string. Allows any URL including localhost/loopback.
    public func navigate(to urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var url: URL?
        if trimmed.contains("://") {
            url = URL(string: trimmed)
        } else {
            // Treat bare hostnames as HTTP
            url = URL(string: "https://\(trimmed)")
        }

        guard let targetURL = url else { return }
        currentURL = targetURL
        urlField.stringValue = targetURL.absoluteString
        webView.load(URLRequest(url: targetURL))
    }

    /// Reload the current page.
    public func reload() {
        webView.reload()
    }

    /// Go back in history.
    public func goBack() {
        webView.goBack()
    }

    /// Go forward in history.
    public func goForward() {
        webView.goForward()
    }

    /// Stop loading.
    public func stop() {
        webView.stopLoading()
    }

    /// Close the browser pane and release resources.
    public func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
    }

    // MARK: - Private UI

    private func createToolbar() -> NSView {
        let toolbar = NSView()

        // Back button
        let back = NSButton(
            image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
            target: self, action: #selector(backClicked)
        )
        back.bezelStyle = .toolbar
        back.isBordered = false
        back.isEnabled = false
        self.backButton = back

        // Forward button
        let fwd = NSButton(
            image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")!,
            target: self, action: #selector(forwardClicked)
        )
        fwd.bezelStyle = .toolbar
        fwd.isBordered = false
        fwd.isEnabled = false
        self.forwardButton = fwd

        // Reload button
        let reload = NSButton(
            image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")!,
            target: self, action: #selector(reloadClicked)
        )
        reload.bezelStyle = .toolbar
        reload.isBordered = false
        self.reloadButton = reload

        // Loading indicator
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        self.loadingIndicator = indicator

        // URL field
        let url = NSTextField()
        url.placeholderString = "Enter URL (e.g., https://example.com)"
        url.font = NSFont.systemFont(ofSize: 13)
        url.lineBreakMode = .byTruncatingHead
        url.focusRingType = .exterior
        url.target = self
        url.action = #selector(goClicked)
        url.delegate = self
        self.urlField = url

        // Go button
        let go = NSButton(title: "Go", target: self, action: #selector(goClicked))
        go.bezelStyle = .toolbar
        self.goButton = go

        // Layout
        let stack = NSStackView(views: [back, fwd, reload, loadingIndicator, url, go])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            url.heightAnchor.constraint(equalToConstant: 24)
        ])

        return toolbar
    }

    @objc private func goClicked() {
        navigate(to: urlField.stringValue)
    }

    @objc private func reloadClicked() {
        reload()
    }

    @objc private func backClicked() {
        goBack()
    }

    @objc private func forwardClicked() {
        goForward()
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }
}

// MARK: - WKNavigationDelegate

extension BrowserPane: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingIndicator.startAnimation(nil)
        updateNavigationButtons()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimation(nil)
        updateNavigationButtons()

        currentURL = webView.url
        urlField.stringValue = webView.url?.absoluteString ?? ""

        webView.evaluateJavaScript("document.title") { [weak self] result, _ in
            if let title = result as? String, !title.isEmpty {
                self?.onTitleChanged?(title)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimation(nil)
        updateNavigationButtons()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimation(nil)
        updateNavigationButtons()
        urlField.stringValue = "Error: \(error.localizedDescription)"
    }

    public func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Allow all navigation including localhost/loopback — no restrictions
        decisionHandler(.allow)
    }
}

// MARK: - NSTextFieldDelegate

extension BrowserPane: NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        // Live update URL field if needed
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            goClicked()
            return true
        }
        return false
    }
}
