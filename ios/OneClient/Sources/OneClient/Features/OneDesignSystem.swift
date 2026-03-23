#if canImport(SwiftUI)
import SwiftUI

public enum OneTheme {
    public struct Palette {
        public let isDark: Bool
        public let background: Color
        public let backgroundTop: Color
        public let surface: Color
        public let surfaceMuted: Color
        public let surfaceStrong: Color
        public let glass: Color
        public let glassStroke: Color
        public let border: Color
        public let text: Color
        public let subtext: Color
        public let accent: Color
        public let accentSoft: Color
        public let success: Color
        public let danger: Color
        public let warning: Color
        public let highlight: Color
        public let symbol: Color
        public let shadowColor: Color
    }

    public static let radiusXL: CGFloat = 30
    public static let radiusLarge: CGFloat = 24
    public static let radiusMedium: CGFloat = 18
    public static let radiusSmall: CGFloat = 14

    public static func palette(for scheme: ColorScheme) -> Palette {
        switch scheme {
        case .dark:
            return Palette(
                isDark: true,
                background: Color(hex: 0x101215),
                backgroundTop: Color(hex: 0x14191F),
                surface: Color(hex: 0x171C23),
                surfaceMuted: Color(hex: 0x12161D),
                surfaceStrong: Color(hex: 0x202734),
                glass: Color(hex: 0x18202A, alpha: 0.98),
                glassStroke: Color.white.opacity(0.05),
                border: Color.white.opacity(0.08),
                text: Color(hex: 0xF3F5F8),
                subtext: Color(hex: 0xA2ADBC),
                accent: Color(hex: 0x7A9DBA),
                accentSoft: Color(hex: 0x7A9DBA, alpha: 0.16),
                success: Color(hex: 0x6EB082),
                danger: Color(hex: 0xD47B6D),
                warning: Color(hex: 0xD1A86A),
                highlight: Color(hex: 0xC08A56),
                symbol: Color(hex: 0xD5DEE8),
                shadowColor: Color.black.opacity(0.16)
            )
        default:
            return Palette(
                isDark: false,
                background: Color(hex: 0xF2F4F7),
                backgroundTop: Color(hex: 0xFAFBFD),
                surface: Color.white,
                surfaceMuted: Color(hex: 0xF5F7FA),
                surfaceStrong: Color(hex: 0xE9EDF3),
                glass: Color.white.opacity(0.98),
                glassStroke: Color(hex: 0x111827, alpha: 0.04),
                border: Color(hex: 0x111827, alpha: 0.07),
                text: Color(hex: 0x151B24),
                subtext: Color(hex: 0x677486),
                accent: Color(hex: 0x4D6F8C),
                accentSoft: Color(hex: 0x4D6F8C, alpha: 0.12),
                success: Color(hex: 0x4D8A62),
                danger: Color(hex: 0xC0675A),
                warning: Color(hex: 0xBB8B4B),
                highlight: Color(hex: 0xAF7440),
                symbol: Color(hex: 0x465466),
                shadowColor: Color.black.opacity(0.04)
            )
        }
    }

    public static func preferredColorScheme(from theme: Theme?) -> ColorScheme? {
        switch theme ?? .system {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }
}

enum OneSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum OneType {
    static let largeTitle = Font.largeTitle.weight(.semibold)
    static let title = Font.title2.weight(.semibold)
    static let sectionTitle = Font.headline.weight(.semibold)
    static let body = Font.body
    static let secondary = Font.subheadline
    static let label = Font.footnote.weight(.semibold)
    static let caption = Font.caption
}

public extension Color {
    init(hex: UInt, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

enum OneDockLayout {
    static let horizontalInset: CGFloat = 18
    static let tabBarLift: CGFloat = -10
    static let dockOrbSize: CGFloat = 58
    static let quickAddBubbleWidth: CGFloat = 218
    static let quickAddBubbleOverlap: CGFloat = 12
    static let overlayStackSpacing: CGFloat = 10

    static var tabScreenBottomPadding: CGFloat {
        32
    }

    static var listBottomSpacerHeight: CGFloat {
        16
    }

    static func overlayBottomInset(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom + tabBarLift
    }
}

struct OneScreenBackground: View {
    let palette: OneTheme.Palette

    var body: some View {
        LinearGradient(
            colors: [palette.backgroundTop, palette.background],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.accentSoft.opacity(palette.isDark ? 0.2 : 0.1))
                .frame(height: 132)
                .blur(radius: 34)
                .offset(y: -72)
        }
        .ignoresSafeArea()
    }
}

struct OneScrollScreen<Content: View>: View {
    let palette: OneTheme.Palette
    let bottomPadding: CGFloat
    let trackDockVisibility: Bool
    @ViewBuilder let content: Content
    @StateObject private var dockVisibility = OneDockVisibilityController.shared

    init(
        palette: OneTheme.Palette,
        bottomPadding: CGFloat = 116,
        trackDockVisibility: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.bottomPadding = bottomPadding
        self.trackDockVisibility = trackDockVisibility
        self.content = content()
    }

    var body: some View {
        ZStack {
            OneScreenBackground(palette: palette)
            ScrollView(showsIndicators: false) {
                VStack(spacing: OneSpacing.md) {
                    if trackDockVisibility {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: OneScrollOffsetPreferenceKey.self,
                                    value: proxy.frame(in: .named("one-scroll-screen")).minY
                                )
                        }
                        .frame(height: 0)
                    }
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, OneSpacing.sm)
                .padding(.bottom, bottomPadding)
            }
            .coordinateSpace(name: "one-scroll-screen")
            .onPreferenceChange(OneScrollOffsetPreferenceKey.self) { offset in
                guard trackDockVisibility else {
                    return
                }
                dockVisibility.register(offset: offset)
            }
        }
        .oneKeyboardDismissible()
    }
}

private struct OneScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct OneGlassCard<Content: View>: View {
    let palette: OneTheme.Palette
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(
        palette: OneTheme.Palette,
        padding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneSpacing.sm) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .fill(palette.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .stroke(palette.accentSoft.opacity(palette.isDark ? 0.44 : 0.72), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                .fill(palette.accent.opacity(palette.isDark ? 0.85 : 0.7))
                .frame(width: 68, height: 4)
                .padding(.leading, padding)
                .padding(.top, 10)
        }
        .shadow(color: palette.shadowColor, radius: 8, x: 0, y: 4)
    }
}

struct OneSurfaceCard<Content: View>: View {
    let palette: OneTheme.Palette
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(
        palette: OneTheme.Palette,
        padding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneSpacing.sm) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: palette.shadowColor, radius: 3, x: 0, y: 1)
    }
}

struct OneSectionHeading: View {
    let palette: OneTheme.Palette
    let title: String
    let meta: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(OneType.sectionTitle)
                .foregroundStyle(palette.text)
            Spacer()
            if let meta, !meta.isEmpty {
                Text(meta)
                    .font(OneType.label)
                    .foregroundStyle(palette.subtext)
            }
        }
    }
}

struct OneHeroHeader<Trailing: View>: View {
    let palette: OneTheme.Palette
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    init(
        palette: OneTheme.Palette,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.palette = palette
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: OneSpacing.sm) {
            VStack(alignment: .leading, spacing: OneSpacing.xs) {
                Text(title)
                    .font(OneType.largeTitle)
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

struct OneMarkBadge: View {
    let palette: OneTheme.Palette

    var body: some View {
        OneBrandMark(size: 54)
    }
}

struct OneAvatarBadge: View {
    let palette: OneTheme.Palette
    let initials: String

    var body: some View {
        Circle()
            .fill(palette.surfaceStrong)
            .frame(width: 42, height: 42)
            .overlay(
                Text(initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.text)
            )
            .overlay(
                Circle()
                    .stroke(palette.border, lineWidth: 1)
            )
    }
}

struct OneChip: View {
    enum Kind {
        case neutral
        case strong
        case success
        case danger
    }

    let palette: OneTheme.Palette
    let title: String
    let kind: Kind

    var body: some View {
        Text(title)
            .font(OneType.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }

    private var foreground: Color {
        switch kind {
        case .neutral:
            return palette.subtext
        case .strong:
            return palette.accent
        case .success:
            return palette.success
        case .danger:
            return palette.danger
        }
    }

    private var background: Color {
        switch kind {
        case .neutral:
            return palette.surfaceMuted
        case .strong:
            return palette.accentSoft
        case .success:
            return palette.success.opacity(palette.isDark ? 0.18 : 0.12)
        case .danger:
            return palette.danger.opacity(palette.isDark ? 0.18 : 0.12)
        }
    }

    private var border: Color {
        switch kind {
        case .neutral:
            return palette.border
        case .strong:
            return palette.accent.opacity(0.18)
        case .success:
            return palette.success.opacity(0.24)
        case .danger:
            return palette.danger.opacity(0.24)
        }
    }
}

struct OneProgressCluster: View {
    let palette: OneTheme.Palette
    let progress: Double
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.surfaceStrong, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    LinearGradient(
                        colors: [palette.accent.opacity(0.35), palette.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    OneMotion.animation(.stateChange, reduceMotion: reduceMotion),
                    value: progress
                )
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text)
                .contentTransition(.numericText())
                .animation(
                    OneMotion.animation(.stateChange, reduceMotion: reduceMotion),
                    value: label
                )
        }
        .frame(width: 52, height: 52)
    }
}

struct OneActivityLane: View {
    let palette: OneTheme.Palette
    let values: [Double]
    let labels: [String]
    let highlightIndex: Int?
    var onSelectIndex: ((Int) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Group {
                        if let onSelectIndex {
                            Button {
                                onSelectIndex(index)
                            } label: {
                                laneCell(index: index, value: value)
                            }
                            .onePressable(scale: 0.98)
                        } else {
                            laneCell(index: index, value: value)
                        }
                    }
                }
            }
        }
        .frame(height: 92)
        .animation(
            OneMotion.animation(.stateChange, reduceMotion: reduceMotion),
            value: values
        )
        .animation(
            OneMotion.animation(.stateChange, reduceMotion: reduceMotion),
            value: highlightIndex
        )
    }

    private func laneCell(index: Int, value: Double) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(barFill(for: index))
                .frame(height: max(16, 18 + (56 * value)))
            Text(labels[safe: index] ?? "")
                .font(.system(size: 10, weight: highlightIndex == index ? .semibold : .medium))
                .foregroundStyle(highlightIndex == index ? palette.text : palette.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private func barFill(for index: Int) -> LinearGradient {
        let accent = highlightIndex == index ? palette.accent : palette.accent.opacity(palette.isDark ? 0.62 : 0.78)
        return LinearGradient(
            colors: [accent.opacity(0.18), accent],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

struct OneSegmentedControl<Option: Hashable>: View {
    let palette: OneTheme.Palette
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(title(option))
                        .font(OneType.secondary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.vertical, 11)
                        .foregroundStyle(selection == option ? palette.text : palette.subtext)
                        .background(alignment: .center) {
                            if selection == option {
                                RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                    .fill(palette.surface)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                }
                .onePressable(scale: 0.985)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .fill(palette.surfaceStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .animation(
            OneMotion.animation(.stateChange, reduceMotion: reduceMotion),
            value: selection
        )
    }
}

struct OneActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let palette: OneTheme.Palette
    let title: String
    let style: Style
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .foregroundStyle(style == .primary ? Color.white : palette.text)
                .background(
                    RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                        .fill(style == .primary ? AnyShapeStyle(primaryFill) : AnyShapeStyle(palette.surfaceStrong))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                        .stroke(style == .primary ? palette.accent.opacity(0.14) : palette.border, lineWidth: 1)
                )
        }
        .onePressable(scale: 0.985)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private var primaryFill: LinearGradient {
        LinearGradient(
            colors: [palette.accent, palette.accent.opacity(0.86)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct PriorityTierSelector: View {
    let palette: OneTheme.Palette
    let title: String
    let subtitle: String?
    let selection: PriorityTier
    let onSelect: (PriorityTier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OneType.label)
                    .foregroundStyle(palette.subtext)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OneType.caption)
                        .foregroundStyle(palette.subtext)
                }
            }

            VStack(spacing: 8) {
                ForEach(PriorityTier.allCases, id: \.self) { tier in
                    Button {
                        OneHaptics.shared.trigger(.selectionChanged)
                        onSelect(tier)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(priorityTierColor(for: tier, palette: palette))
                                .frame(width: 12, height: 12)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tier.title)
                                    .font(OneType.body.weight(.semibold))
                                    .foregroundStyle(palette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(tier.helperText)
                                    .font(OneType.caption)
                                    .foregroundStyle(palette.subtext)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer()
                            if selection == tier {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(priorityTierColor(for: tier, palette: palette))
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 72, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                                .fill(selection == tier ? priorityTierColor(for: tier, palette: palette).opacity(0.14) : palette.surfaceMuted)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                                .stroke(selection == tier ? priorityTierColor(for: tier, palette: palette).opacity(0.45) : palette.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func priorityTierColor(for tier: PriorityTier, palette: OneTheme.Palette) -> Color {
        switch tier {
        case .low:
            return palette.subtext
        case .standard:
            return palette.accent
        case .high:
            return palette.highlight
        case .urgent:
            return palette.danger
        }
    }
}

struct OneSettingsRow: View {
    let palette: OneTheme.Palette
    let iconKey: OneIconKey
    let title: String
    let meta: String
    let tail: String?

    var body: some View {
        HStack(spacing: 12) {
            OneIconBadge(
                key: iconKey,
                palette: palette,
                size: 38,
                tint: palette.symbol,
                background: palette.surfaceStrong,
                border: palette.border,
                shape: .circle
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(meta)
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
            }
            Spacer()
            if let tail, !tail.isEmpty {
                Text(tail)
                    .font(OneType.label)
                    .foregroundStyle(palette.subtext)
            } else {
                Image(systemName: "chevron.right")
                    .font(OneType.label)
                    .foregroundStyle(palette.subtext)
            }
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum OneNavigationBarDisplayMode {
    case automatic
    case inline
    case large
}

extension ToolbarItemPlacement {
    static var oneNavigationLeading: ToolbarItemPlacement {
        #if os(iOS)
        .navigationBarLeading
        #else
        .automatic
        #endif
    }

    static var oneNavigationTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .navigationBarTrailing
        #else
        .primaryAction
        #endif
    }
}

extension View {
    @ViewBuilder
    func oneNavigationBarDisplayMode(_ displayMode: OneNavigationBarDisplayMode) -> some View {
        #if os(iOS)
        switch displayMode {
        case .automatic:
            self.navigationBarTitleDisplayMode(.automatic)
        case .inline:
            self.navigationBarTitleDisplayMode(.inline)
        case .large:
            self.navigationBarTitleDisplayMode(.large)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneInlineNavigationBarTitle() -> some View {
        #if os(iOS)
        self.oneNavigationBarDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneListRowSpacing(_ spacing: CGFloat) -> some View {
        #if os(iOS)
        self.listRowSpacing(spacing)
        #else
        self
        #endif
    }

    @ViewBuilder
    func onePlainTextInputBehavior() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneDecimalInput() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneNumberInput() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    func oneListEditing(editMode: Binding<EditMode>) -> some View {
        self.environment(\.editMode, editMode)
    }
    #endif
}
#endif
