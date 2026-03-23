#if canImport(SwiftUI)
import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

enum OneMotionRole {
    case tap
    case stateChange
    case expand
    case dismiss
    case reorder
    case milestone
    case calmRefresh
}

enum OneMotion {
    static func animation(_ role: OneMotionRole, reduceMotion: Bool = false) -> Animation {
        if reduceMotion {
            switch role {
            case .tap:
                return .easeOut(duration: 0.08)
            case .stateChange, .dismiss, .calmRefresh:
                return .easeInOut(duration: 0.12)
            case .expand, .reorder:
                return .easeInOut(duration: 0.16)
            case .milestone:
                return .easeOut(duration: 0.2)
            }
        }

        switch role {
        case .tap:
            return .spring(duration: 0.16, bounce: 0)
        case .stateChange:
            return .snappy(duration: 0.24, extraBounce: 0.06)
        case .expand:
            return .spring(duration: 0.28, bounce: 0.12)
        case .dismiss:
            return .easeInOut(duration: 0.18)
        case .reorder:
            return .interactiveSpring(duration: 0.28, extraBounce: 0.06)
        case .milestone:
            return .spring(duration: 0.34, bounce: 0.18)
        case .calmRefresh:
            return .easeInOut(duration: 0.2)
        }
    }
}

struct OnePressButtonStyle: ButtonStyle {
    let scale: CGFloat
    let opacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(scale: CGFloat = 0.99, opacity: Double = 0.94) {
        self.scale = scale
        self.opacity = opacity
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? opacity : 1)
            .animation(
                OneMotion.animation(.tap, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

extension View {
    func onePressable(scale: CGFloat = 0.985, opacity: Double = 0.92) -> some View {
        buttonStyle(OnePressButtonStyle(scale: scale, opacity: opacity))
    }

    func oneEntranceReveal(index: Int = 0) -> some View {
        self
    }

    @ViewBuilder
    func oneKeyboardDismissible() -> some View {
        #if os(iOS)
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        OneKeyboard.dismiss()
                    }
                }
            }
        #else
        self
        #endif
    }
}

enum OneHapticEvent: String, Hashable {
    case selectionChanged
    case completionCommitted
    case destructiveConfirmed
    case periodSwitched
    case saveSucceeded
    case saveFailed
    case milestoneReached
    case sheetPresented
    case sheetDismissed
    case reorderPickup
    case reorderDrop
    case dockToggled
}

@MainActor
final class OneHaptics {
    static let shared = OneHaptics()

    private var lastFiredAt: [OneHapticEvent: Date] = [:]
    private let minimumSpacing: TimeInterval = 0.08

    private init() {}

    func trigger(_ event: OneHapticEvent) {
        let now = Date()
        if let last = lastFiredAt[event], now.timeIntervalSince(last) < minimumSpacing {
            return
        }
        lastFiredAt[event] = now

        #if os(iOS)
        switch event {
        case .selectionChanged, .periodSwitched:
            UISelectionFeedbackGenerator().selectionChanged()
        case .completionCommitted, .sheetPresented, .sheetDismissed, .dockToggled, .reorderDrop:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .reorderPickup:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .destructiveConfirmed:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .saveSucceeded, .milestoneReached:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .saveFailed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}

enum OneSyncFeedbackKind: Equatable {
    case local
    case syncing
    case synced
    case failed
}

struct OneSyncFeedback: Identifiable, Equatable {
    let id = UUID()
    let kind: OneSyncFeedbackKind
    let title: String
    let message: String
}

@MainActor
final class OneSyncFeedbackCenter: ObservableObject {
    static let shared = OneSyncFeedbackCenter()

    @Published private(set) var feedback: OneSyncFeedback?
    private var clearTask: Task<Void, Never>?

    private init() {}

    func showLocal(title: String = "Saved locally", message: String = "Will sync when connection is available.") {
        present(
            OneSyncFeedback(kind: .local, title: title, message: message),
            autoClearAfter: 2.8
        )
    }

    func showSyncing(title: String = "Syncing", message: String = "Applying your latest changes.") {
        present(
            OneSyncFeedback(kind: .syncing, title: title, message: message),
            autoClearAfter: nil
        )
    }

    func showSynced(title: String = "Synced", message: String = "Changes are up to date on this device.") {
        present(
            OneSyncFeedback(kind: .synced, title: title, message: message),
            autoClearAfter: 1.8
        )
    }

    func showFailed(title: String = "Sync issue", message: String = "Changes could not be synced yet.") {
        present(
            OneSyncFeedback(kind: .failed, title: title, message: message),
            autoClearAfter: 3.6
        )
    }

    func clear() {
        clearTask?.cancel()
        withAnimation(OneMotion.animation(.dismiss)) {
            feedback = nil
        }
    }

    private func present(_ next: OneSyncFeedback, autoClearAfter delay: TimeInterval?) {
        clearTask?.cancel()
        withAnimation(OneMotion.animation(.stateChange)) {
            feedback = next
        }

        guard let delay else {
            return
        }

        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }
            withAnimation(OneMotion.animation(.dismiss)) {
                feedback = nil
            }
        }
    }
}

@MainActor
final class OneKeyboardObserver: ObservableObject {
    @Published private(set) var isVisible = false

    private var cancellables: Set<AnyCancellable> = []

    init(center: NotificationCenter = .default) {
        #if os(iOS)
        center.publisher(for: UIResponder.keyboardWillShowNotification)
            .merge(with: center.publisher(for: UIResponder.keyboardDidShowNotification))
            .sink { [weak self] _ in
                self?.isVisible = true
            }
            .store(in: &cancellables)

        center.publisher(for: UIResponder.keyboardWillHideNotification)
            .merge(with: center.publisher(for: UIResponder.keyboardDidHideNotification))
            .sink { [weak self] _ in
                self?.isVisible = false
            }
            .store(in: &cancellables)
        #endif
    }
}

#if os(iOS)
enum OneKeyboard {
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

@MainActor
final class OneQuickActionCenter: ObservableObject {
    @Published private(set) var quickNoteRequest = 0

    func requestQuickNote() {
        quickNoteRequest += 1
    }
}

@MainActor
final class OneDockVisibilityController: ObservableObject {
    static let shared = OneDockVisibilityController()

    @Published private(set) var isHidden = false
    private var lastOffset: CGFloat?

    private init() {}

    func register(offset: CGFloat) {
        if offset > -12 {
            lastOffset = offset
            reveal()
            return
        }

        guard let lastOffset else {
            self.lastOffset = offset
            return
        }

        let delta = offset - lastOffset
        self.lastOffset = offset

        if delta < -14 {
            hide()
        } else if delta > 10 {
            reveal()
        }
    }

    func reset() {
        lastOffset = nil
        reveal()
    }

    private func hide() {
        guard !isHidden else {
            return
        }
        withAnimation(OneMotion.animation(.dismiss)) {
            isHidden = true
        }
    }

    private func reveal() {
        guard isHidden else {
            return
        }
        withAnimation(OneMotion.animation(.dismiss)) {
            isHidden = false
        }
    }
}

struct OneSyncFeedbackPill: View {
    let palette: OneTheme.Palette
    let feedback: OneSyncFeedback

    private var iconKey: OneIconKey {
        switch feedback.kind {
        case .local:
            return .offline
        case .syncing:
            return .sync
        case .synced:
            return .success
        case .failed:
            return .warning
        }
    }

    private var tint: Color {
        switch feedback.kind {
        case .local, .syncing:
            return palette.accent
        case .synced:
            return palette.success
        case .failed:
            return palette.danger
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            OneIconBadge(
                key: iconKey,
                palette: palette,
                size: 28,
                tint: tint,
                background: palette.surfaceMuted,
                border: palette.border,
                shape: .circle
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(OneType.label)
                    .foregroundStyle(palette.text)
                Text(feedback.message)
                    .font(OneType.caption)
                    .foregroundStyle(palette.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: palette.shadowColor.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}
#endif
