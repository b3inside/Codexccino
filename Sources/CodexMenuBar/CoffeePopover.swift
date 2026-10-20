import AppKit
import SwiftUI
import CodexQuotaCore

/// A single public AppKit surface owns both the card and its arrow. Native
/// NSPopover material cannot express the card's exact opaque coffee color.
@MainActor
final class CoffeePopover: NSObject, NSWindowDelegate {
    private var panel: CoffeePanel?
    private var card: CoffeeCardView?
    private weak var anchorButton: NSStatusBarButton?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var anchorClickInProgress = false

    var isShown: Bool { panel?.isVisible == true }

    @discardableResult
    func toggle(model: QuotaController, relativeTo button: NSStatusBarButton) -> Bool {
        anchorClickInProgress = false
        if isShown { close() } else { show(model: model, relativeTo: button) }
        return isShown
    }

    private var anchorScreenRect: NSRect? {
        guard let button = anchorButton, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Status items may receive clicks through the system's menu-bar process.
    /// Leave an anchor click to the button action, instead of closing first.
    func handleGlobalMouseDown(at point: NSPoint, primary: Bool) {
        guard NSApp.modalWindow == nil else { return }
        if primary, anchorScreenRect?.contains(point) == true {
            anchorClickInProgress = true
            return
        }
        close()
    }

    func show(model: QuotaController, relativeTo button: NSStatusBarButton) {
        guard !isShown else { return }
        anchorButton = button
        let card = CoffeeCardView(model: model)
        let panel = CoffeePanel(contentRect: card.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        panel.title = AppIdentity.name
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = card
        panel.delegate = self
        self.panel = panel
        self.card = card
        updateSize()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in self?.updateSize() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShown, NSApp.modalWindow == nil else { return event }
            if event.type == .keyDown && event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self, let panel, self.panel === panel else { return }
            self.handleGlobalMouseDown(at: NSEvent.mouseLocation, primary: event.type == .leftMouseDown)
        }
    }

    func updateSize() {
        guard let panel, let card, let button = anchorButton, let anchorWindow = button.window else { return }
        card.updateLayout()
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = anchorWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchorWindow.frame
        let width = card.bounds.width
        let x = max(visible.minX + 8, min(anchor.midX - width / 2, visible.maxX - width - 8))
        let y = anchor.minY - card.bounds.height - 2
        card.arrowX = max(28, min(anchor.midX - x, width - 28))
        panel.setFrame(NSRect(x: x, y: max(visible.minY, y), width: width, height: card.bounds.height), display: true)
    }

    func close() {
        anchorClickInProgress = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
        card = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // runModal starts its nested loop before this check executes. Keep the
        // card behind the confirmation, and restore it when the dialog ends.
        guard let resignedPanel = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self, weak resignedPanel] in
            guard let self, let resignedPanel, self.panel === resignedPanel,
                  NSApp.modalWindow == nil, !resignedPanel.isKeyWindow, !NSApp.isActive else { return }
            let mouseDownOnAnchor = NSEvent.pressedMouseButtons & 1 != 0
                && self.anchorScreenRect?.contains(NSEvent.mouseLocation) == true
            guard !self.anchorClickInProgress, !mouseDownOnAnchor else { return }
            self.close()
        }
    }
}

private final class CoffeePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Also used by offline captures, so QA includes the actual arrow and border.
@MainActor
final class CoffeeCardView: NSView {
    static let arrowHeight: CGFloat = 10
    static let background = CoffeeTheme.nsBackground
    private let hosting: NSHostingView<QuotaView>
    var arrowX: CGFloat = 180 { didSet { needsDisplay = true } }

    init(model: QuotaController) {
        hosting = NSHostingView(rootView: QuotaView(model: model))
        super.init(frame: .zero)
        addSubview(hosting)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        updateLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func updateLayout() {
        let size = hosting.fittingSize
        frame.size = NSSize(width: size.width, height: size.height + Self.arrowHeight)
        hosting.frame = NSRect(origin: .zero, size: size)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height - Self.arrowHeight
        let r: CGFloat = 12
        let x = arrowX
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0.5, y: r))
        path.curve(to: NSPoint(x: r, y: 0.5), controlPoint1: NSPoint(x: 0.5, y: 4), controlPoint2: NSPoint(x: 4, y: 0.5))
        path.line(to: NSPoint(x: w - r, y: 0.5))
        path.curve(to: NSPoint(x: w - 0.5, y: r), controlPoint1: NSPoint(x: w - 4, y: 0.5), controlPoint2: NSPoint(x: w - 0.5, y: 4))
        path.line(to: NSPoint(x: w - 0.5, y: h - r))
        path.curve(to: NSPoint(x: w - r, y: h), controlPoint1: NSPoint(x: w - 0.5, y: h - 4), controlPoint2: NSPoint(x: w - 4, y: h))
        path.line(to: NSPoint(x: x + 14, y: h))
        path.curve(to: NSPoint(x: x + 5, y: h + 6), controlPoint1: NSPoint(x: x + 9, y: h), controlPoint2: NSPoint(x: x + 8, y: h + 3))
        path.curve(to: NSPoint(x: x, y: h + 9.5), controlPoint1: NSPoint(x: x + 3, y: h + 9), controlPoint2: NSPoint(x: x + 2, y: h + 9.5))
        path.curve(to: NSPoint(x: x - 5, y: h + 6), controlPoint1: NSPoint(x: x - 2, y: h + 9.5), controlPoint2: NSPoint(x: x - 3, y: h + 9))
        path.curve(to: NSPoint(x: x - 14, y: h), controlPoint1: NSPoint(x: x - 8, y: h + 3), controlPoint2: NSPoint(x: x - 9, y: h))
        path.line(to: NSPoint(x: r, y: h))
        path.curve(to: NSPoint(x: 0.5, y: h - r), controlPoint1: NSPoint(x: 4, y: h), controlPoint2: NSPoint(x: 0.5, y: h - 4))
        path.close()
        Self.background.setFill()
        path.fill()
        NSColor(srgbRed: 0.64, green: 0.58, blue: 0.52, alpha: 0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
