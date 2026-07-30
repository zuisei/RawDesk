import SwiftUI
import AppKit

/// AppKit bridge for arrow-key navigation and rating shortcuts.
/// SwiftUI's keyboard shortcut API does not cleanly handle bare arrow keys
/// or unmodified digit keys at the scene level, so we install a local monitor.
struct KeyboardHandler: NSViewRepresentable {
    var onPrev: () -> Void
    var onNext: () -> Void
    var onSelectAll: () -> Void
    var onRating: (Int) -> Void
    var onColorLabel: (PhotoColorLabel, Bool) -> Void
    var onFlag: () -> Void
    var onPickStatus: (PhotoPickStatus) -> Void
    var onToggleQuickCollection: () -> Void
    var onToggleSoftProofing: () -> Void
    var onShowGrid: () -> Void
    var onShowLoupe: () -> Void
    var canToggleLoupe: Bool
    var onToggleLoupe: () -> Void
    var onShowDevelop: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = MonitorView()
        v.handler = self
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MonitorView)?.handler = self
    }

    final class MonitorView: NSView {
        var handler: KeyboardHandler?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let h = self.handler else { return event }
                    // A SwiftUI sheet owns a different NSWindow from this
                    // representable's host view. Inspect the event/key window,
                    // not only the underlying library window, or bare photo
                    // shortcuts such as P, U, F, X, and 0...9 will consume
                    // characters typed into sheet text fields.
                    let eventWindow =
                        event.window
                        ?? NSApp.keyWindow
                        ?? self.window
                    if Self.isEditingText(in: eventWindow) {
                        return event
                    }
                    if Self.isAdjustingValue(in: eventWindow) {
                        return event
                    }

                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if mods == [.command],
                       event.charactersIgnoringModifiers?
                        .lowercased() == "a" {
                        h.onSelectAll()
                        return nil
                    }
                    if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
                        return event
                    }
                    if mods.contains(.shift),
                       [123, 124, 125, 126].contains(
                           Int(event.keyCode)
                       ) {
                        // Shift-arrow is reserved for coarse value
                        // adjustment in focused sliders.
                        return event
                    }
                    if Self.shouldHandleLoupeToggle(
                        keyCode: event.keyCode,
                        canToggleLoupe:
                            h.canToggleLoupe
                    ),
                       eventWindow === self.window,
                       !Self.isActivatingControl(
                            in: eventWindow
                       ) {
                        h.onToggleLoupe()
                        return nil
                    }
                    switch event.keyCode {
                    case 123, 126: // left, up
                        h.onPrev(); return nil
                    case 124, 125: // right, down
                        h.onNext(); return nil
                    default: break
                    }
                    if let chars = event.charactersIgnoringModifiers {
                        switch chars {
                        case "0": h.onRating(0); return nil
                        case "1": h.onRating(1); return nil
                        case "2": h.onRating(2); return nil
                        case "3": h.onRating(3); return nil
                        case "4": h.onRating(4); return nil
                        case "5": h.onRating(5); return nil
                        case "6":
                            h.onColorLabel(
                                .red,
                                mods.contains(.shift)
                            )
                            return nil
                        case "7":
                            h.onColorLabel(
                                .yellow,
                                mods.contains(.shift)
                            )
                            return nil
                        case "8":
                            h.onColorLabel(
                                .green,
                                mods.contains(.shift)
                            )
                            return nil
                        case "9":
                            h.onColorLabel(
                                .blue,
                                mods.contains(.shift)
                            )
                            return nil
                        case "f", "F": h.onFlag(); return nil
                        case "p", "P": h.onPickStatus(.picked); return nil
                        case "u", "U": h.onPickStatus(.unflagged); return nil
                        case "x", "X": h.onPickStatus(.rejected); return nil
                        case "b", "B":
                            h.onToggleQuickCollection()
                            return nil
                        case "s", "S":
                            h.onToggleSoftProofing()
                            return nil
                        case "g", "G":
                            h.onShowGrid()
                            return nil
                        case "e", "E":
                            h.onShowLoupe()
                            return nil
                        case "d", "D":
                            h.onShowDevelop()
                            return nil
                        default: break
                        }
                    }
                    return event
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }

        static func isEditingText(in window: NSWindow?) -> Bool {
            guard let window,
                  let responder = window.firstResponder else {
                return false
            }
            if responder is NSText
                || responder is NSTextField
                || responder is NSSearchField {
                return true
            }
            if let control = responder as? NSControl,
               control.currentEditor() != nil {
                return true
            }
            var ancestor = responder.nextResponder
            for _ in 0..<8 {
                guard let current = ancestor else { break }
                if current is NSText
                    || current is NSTextField
                    || current is NSSearchField {
                    return true
                }
                ancestor = current.nextResponder
            }
            return false
        }

        static func isLoupeToggleKeyCode(
            _ keyCode: UInt16
        ) -> Bool {
            // Return, Space, and the numeric-keypad Enter key.
            [36, 49, 76].contains(Int(keyCode))
        }

        static func shouldHandleLoupeToggle(
            keyCode: UInt16,
            canToggleLoupe: Bool
        ) -> Bool {
            canToggleLoupe
                && isLoupeToggleKeyCode(keyCode)
        }

        static func isActivatingControl(
            in window: NSWindow?
        ) -> Bool {
            guard let responder =
                window?.firstResponder else {
                return false
            }
            if Self.isActivatableControl(responder) {
                return true
            }
            var ancestor = responder.nextResponder
            for _ in 0..<8 {
                guard let current = ancestor else {
                    break
                }
                if Self.isActivatableControl(current) {
                    return true
                }
                ancestor = current.nextResponder
            }
            return false
        }

        private static func isActivatableControl(
            _ responder: NSResponder
        ) -> Bool {
            responder is NSButton
                || responder is NSPopUpButton
                || responder is NSSegmentedControl
                || responder is NSSwitch
        }

        /// Let focused sliders and steppers own arrow keys. Otherwise the
        /// scene-level photo navigation monitor would consume both fine and
        /// Shift-arrow coarse adjustments before SwiftUI sees them.
        static func isAdjustingValue(in window: NSWindow?) -> Bool {
            guard let responder = window?.firstResponder else {
                return false
            }
            if Self.isValueAdjuster(responder) {
                return true
            }
            var ancestor = responder.nextResponder
            for _ in 0..<8 {
                guard let current = ancestor else { break }
                if Self.isValueAdjuster(current) {
                    return true
                }
                ancestor = current.nextResponder
            }
            return false
        }

        private static func isValueAdjuster(
            _ responder: NSResponder
        ) -> Bool {
            if responder is NSSlider || responder is NSStepper {
                return true
            }
            guard let view = responder as? NSView else {
                return false
            }
            return view.accessibilityRole() == .slider
        }
    }
}
