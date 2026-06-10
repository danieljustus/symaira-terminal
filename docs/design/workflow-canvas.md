# Workflow-Canvas Design Document

## Overview

Visual agent workflow editor using WKWebView with a React Flow canvas for connecting agent tasks, reviewing outputs, and wiring agentic pipelines.

## Architecture

### Node Types
- **Terminal Pane**: Spawn a shell session and capture output
- **AI Action**: Call an AI provider with a prompt
- **File Input**: Read file contents as input
- **Condition**: Branch based on output content
- **Merge**: Combine multiple outputs

### Edges
- Carry stdout/diff/structured output between nodes
- Support conditional branching
- Enable parallel execution paths

### Technology Stack
- **Frontend**: React Flow (via WKWebView)
- **Bridge**: Swift ↔ WKWebView message passing
- **Native**: PTY sessions, file I/O stay in Swift

## Implementation Phases

### Phase 1: Basic Canvas
- WKWebView host in SwiftUI overlay
- React Flow canvas with drag-and-drop nodes
- Basic node types (Terminal, AI Action, File Input)

### Phase 2: Execution Engine
- Sequential node execution
- Output passing between nodes
- Error handling and retry logic

### Phase 3: Advanced Features
- Parallel execution
- Conditional branching
- Visual debugging and step-through

## Integration Points

### Swift ↔ WKWebView Bridge
```swift
// Send message to WKWebView
webView.evaluateJavaScript("window.handleNodeData(\(jsonData))")

// Receive message from WKWebView
func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    // Handle node execution requests
}
```

### PTY Integration
- Terminal Pane nodes spawn PTY sessions via GhosttyBridge
- Capture stdout/stderr for downstream nodes
- Support interactive sessions

### File I/O Integration
- File Input nodes read via Foundation
- File Output nodes write via Foundation
- Support relative paths within worktree

## UI Layout

```
┌─────────────────────────────────────────┐
│  Workflow Canvas (React Flow)           │
│  ┌─────┐    ┌─────┐    ┌─────┐         │
│  │File │───▶│ AI  │───▶│Term │         │
│  │Input│    │Action│    │Pane │         │
│  └─────┘    └─────┘    └─────┘         │
│                                         │
│  ┌─────┐    ┌─────┐                    │
│  │Cond │───▶│Merge│                    │
│  └─────┘    └─────┘                    │
└─────────────────────────────────────────┘
│  Properties Panel (Node Details)        │
└─────────────────────────────────────────┘
```

## Success Criteria

- [ ] WKWebView renders React Flow canvas
- [ ] Nodes can be dragged and connected
- [ ] Terminal Pane nodes spawn PTY sessions
- [ ] AI Action nodes call providers
- [ ] Output passes between connected nodes
- [ ] Workflow can be saved/loaded as JSON
