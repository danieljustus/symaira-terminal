# Browser-Pane Design Document

## Overview

Embedded browser pane using WKWebView with a Browser-MCP bridge for CLI agents to interact with web content without leaving the terminal window.

## Architecture

### Core Components
- **WKWebView**: Renders web content in a split pane
- **Browser-MCP Bridge**: Exposes DOM to CLI agents as an MCP server
- **Swift ↔ JS Bridge**: Message passing between Swift and JavaScript

### Node Types
- **URL Navigation**: Load a URL in the browser pane
- **DOM Query**: Read DOM elements via CSS selectors
- **Form Interaction**: Fill forms, click buttons
- **Screenshot**: Capture page screenshot as image

## Implementation Phases

### Phase 1: Basic Browser
- WKWebView host in SwiftUI split pane
- URL bar with navigation controls
- Basic DOM inspection via JavaScript

### Phase 2: MCP Bridge
- Expose DOM as MCP server
- CLI agents can query and interact with page
- Support for form filling and button clicking

### Phase 3: Advanced Features
- Screenshot capture and annotation
- Network request interception
- Cookie and session management

## Integration Points

### Swift ↔ WKWebView Bridge
```swift
// Send message to WKWebView
webView.evaluateJavaScript("window.handleMCPRequest(\(jsonData))")

// Receive message from WKWebView
func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    // Handle MCP requests from agents
}
```

### MCP Server Interface
```json
{
  "method": "browser.navigate",
  "params": {
    "url": "https://example.com"
  }
}

{
  "method": "browser.query",
  "params": {
    "selector": "h1",
    "attribute": "textContent"
  }
}

{
  "method": "browser.fillForm",
  "params": {
    "selector": "form#login",
    "data": {
      "username": "user",
      "password": "pass"
    }
  }
}
```

### Terminal Integration
- Detect URLs in terminal output and offer to open in browser pane
- Cmd+Shift+B shortcut to toggle browser pane
- Share cookies with terminal sessions for seamless auth

## UI Layout

```
┌─────────────────────────────────────────┐
│  Terminal Pane  │  Browser Pane         │
│  $ curl https://│  ┌─────────────────┐  │
│  example.com    │  │ https://example │  │
│  <html>...</html>│  │ ┌─────────────┐ │  │
│                 │  │ │ Example     │ │  │
│                 │  │ │ Domain      │ │  │
│                 │  │ └─────────────┘ │  │
│                 │  └─────────────────┘  │
└─────────────────────────────────────────┘
```

## Success Criteria

- [ ] WKWebView renders in split pane
- [ ] URL bar with navigation controls
- [ ] DOM inspection via JavaScript
- [ ] MCP server exposes DOM to agents
- [ ] Form filling and button clicking
- [ ] Screenshot capture
- [ ] URL detection from terminal output
