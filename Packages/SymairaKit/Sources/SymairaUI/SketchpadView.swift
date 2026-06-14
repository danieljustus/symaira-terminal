import AppKit
import SwiftUI

// MARK: - Drawing Canvas (NSView)

@MainActor
final class SketchpadCanvas: NSView {
    private var currentPath: NSBezierPath?
    private var paths: [NSBezierPath] = []
    private var strokeColor: NSColor = .black
    private var lineWidth: CGFloat = 2.0

    var onImageChanged: ((NSImage?) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPath = NSBezierPath()
        currentPath?.lineWidth = lineWidth
        currentPath?.lineCapStyle = .round
        currentPath?.lineJoinStyle = .round
        currentPath?.move(to: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPath?.line(to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let path = currentPath {
            path.stroke()
            paths.append(path)
            currentPath = nil
            notifyImageChanged()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()

        strokeColor.setStroke()
        for path in paths {
            path.stroke()
        }
        currentPath?.stroke()
    }

    func clear() {
        paths.removeAll()
        currentPath = nil
        needsDisplay = true
        notifyImageChanged()
    }

    func captureImage() -> NSImage? {
        guard !bounds.isEmpty else { return nil }
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor.white.setFill()
        bounds.fill()
        strokeColor.setStroke()
        for path in paths {
            path.stroke()
        }
        image.unlockFocus()
        return image
    }

    private func notifyImageChanged() {
        let image = captureImage()
        onImageChanged?(image)
    }
}

// MARK: - SketchpadViewModel

@MainActor
public final class SketchpadViewModel: ObservableObject {
    @Published public var lastImage: NSImage?

    let canvas = SketchpadCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

    public init() {
        canvas.onImageChanged = { [weak self] image in
            self?.lastImage = image
        }
    }

    public func clear() {
        canvas.clear()
        lastImage = nil
    }

    public func capturePNG() -> Data? {
        guard let image = canvas.captureImage(),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - SwiftUI Wrapper

public struct SketchpadCanvasView: NSViewRepresentable {
    let canvas: SketchpadCanvas

    public init(canvas: SketchpadCanvas) {
        self.canvas = canvas
    }

    public func makeNSView(context: Context) -> NSView {
        canvas
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Full Sketchpad Panel

public struct SketchpadView: View {
    @StateObject private var viewModel = SketchpadViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SketchpadCanvasView(canvas: viewModel.canvas)
                .frame(minWidth: 300, minHeight: 200)
                .border(Color.gray.opacity(0.3))

            HStack(spacing: 12) {
                Button("Clear") {
                    viewModel.clear()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    if let data = viewModel.capturePNG() {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setData(data, forType: .png)
                    }
                } label: {
                    Label("Copy PNG", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    savePNGToDisk()
                } label: {
                    Label("Save PNG", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func savePNGToDisk() {
        guard let data = viewModel.capturePNG() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "sketch.png"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}

#if DEBUG
struct SketchpadPreview: View {
    var body: some View {
        SketchpadView()
            .frame(width: 400, height: 300)
    }
}
#endif
