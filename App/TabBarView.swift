import AppKit

@MainActor
protocol TabBarDelegate: AnyObject {
    func tabBarDidSelectTab(_ tabBar: TabBarView, index: Int)
    func tabBarDidRequestClose(_ tabBar: TabBarView, index: Int)
}

@MainActor
final class TabBarView: NSView {
    weak var delegate: TabBarDelegate?
    private var tabButtons: [TabButton] = []
    private let stackView = NSStackView()
    private let scrollView = NSScrollView()

    var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        addSubview(scrollView)

        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 28)
        ])

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor)
        ])
    }

    func updateTabs(titles: [String], selectedIndex: Int) {
        self.selectedIndex = selectedIndex

        for button in tabButtons {
            button.removeFromSuperview()
        }
        tabButtons.removeAll()

        for (index, title) in titles.enumerated() {
            let button = TabButton(index: index, title: title)
            button.onSelect = { [weak self] idx in
                guard let self else { return }
                self.delegate?.tabBarDidSelectTab(self, index: idx)
            }
            button.onClose = { [weak self] idx in
                guard let self else { return }
                self.delegate?.tabBarDidRequestClose(self, index: idx)
            }
            tabButtons.append(button)
            stackView.addArrangedSubview(button)

            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalTo: stackView.heightAnchor),
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
            ])
        }

        updateSelection()
    }

    private func updateSelection() {
        for (index, button) in tabButtons.enumerated() {
            button.isSelected = (index == selectedIndex)
        }
    }
}

@MainActor
private final class TabButton: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    let index: Int
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    init(index: Int, title: String) {
        self.index = index
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 4

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.title = "×"
        closeButton.font = .systemFont(ofSize: 12, weight: .medium)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(tabClicked))
        addGestureRecognizer(clickGesture)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor.controlAccentColor.setFill()
        } else {
            NSColor.clear.setFill()
        }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4)
        path.fill()

        super.draw(dirtyRect)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor : NSColor.clear.cgColor
    }

    @objc private func tabClicked() {
        onSelect?(index)
    }

    @objc private func closeClicked() {
        onClose?(index)
    }
}
