import AppKit

@MainActor
final class RegionSelector: NSObject {
    private let window: SelectionWindow
    private let selectionView: SelectionView

    init(screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), completion: completion)
        window = SelectionWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init()
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = selectionView
        selectionView.owningWindow = window
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(selectionView)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate func close() { window.close() }
}

@MainActor
private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class SelectionView: NSView {
    weak var owningWindow: NSWindow?
    private let completion: (CGRect?) -> Void
    private var anchor: CGPoint?
    private var current: CGPoint?

    init(frame: NSRect, completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()
        if let rect = selection {
            NSColor.black.withAlphaComponent(0.05).setFill()
            rect.fill()
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 2
            outline.stroke()
        }
        let hint = "Drag to select an area · Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = hint.size(withAttributes: attrs)
        hint.draw(at: NSPoint(x: 24, y: bounds.maxY - size.height - 24), withAttributes: attrs)
        let cancel = "Cancel"
        let cancelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        cancel.draw(at: NSPoint(x: bounds.maxX - 78, y: bounds.maxY - 44), withAttributes: cancelAttrs)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if cancelRect.contains(point) {
            owningWindow?.close()
            completion(nil)
            return
        }
        anchor = point
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let selection, selection.width >= 32, selection.height >= 32 else { return }
        owningWindow?.close()
        completion(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { owningWindow?.close(); completion(nil) } else { super.keyDown(with: event) }
    }

    private var selection: CGRect? {
        guard let anchor, let current else { return nil }
        return CGRect(x: min(anchor.x, current.x), y: min(anchor.y, current.y),
                      width: abs(current.x - anchor.x), height: abs(current.y - anchor.y))
    }

    private var cancelRect: CGRect { CGRect(x: bounds.maxX - 94, y: bounds.maxY - 58, width: 78, height: 38) }
}
