import AppKit
import SwiftUI

/// Trackpad swipe-right and Backspace when no text field is focused.
struct BackNavigationCapture: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.bind(model: model)
        return context.coordinator.host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.bind(model: model)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    final class Coordinator {
        let host = NSView(frame: .zero)
        private weak var model: AppModel?
        private var monitor: Any?

        func bind(model: AppModel) {
            self.model = model
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .swipe]) { [weak self] event in
                guard let self, self.model != nil else { return event }
                if event.type == .swipe, event.deltaX > 0 {
                    Task { @MainActor [weak self] in
                        guard let model = self?.model, model.canNavigateBack else { return }
                        model.navigateBack()
                    }
                    return nil
                }
                if event.type == .keyDown, event.keyCode == 51, !Self.textInputFocused {
                    Task { @MainActor [weak self] in
                        guard let model = self?.model, model.canNavigateBack else { return }
                        model.navigateBack()
                    }
                    return nil
                }
                return event
            }
        }

        func unbind() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private static var textInputFocused: Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else { return false }
            return responder is NSTextView || responder is NSTextField
        }
    }
}

struct SectionBackBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button { model.navigateBack() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.backNavigationTitle)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.navy.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Divider() }
    }
}
