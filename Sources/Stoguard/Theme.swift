import SwiftUI

/// Navy + neutral system — accent is deep navy, not system blue or rainbow.
enum Theme {
    static let navy = Color(red: 0.08, green: 0.12, blue: 0.26)
    static let navyMid = Color(red: 0.12, green: 0.18, blue: 0.36)
    static let accent = navy

    static let bg = Color(nsColor: .windowBackgroundColor)
    static let elevated = Color(nsColor: .controlBackgroundColor)
    static let card = Color(nsColor: .textBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    static let heroTop = Color(red: 0.06, green: 0.09, blue: 0.18)
    static let heroBottom = Color(red: 0.04, green: 0.06, blue: 0.12)
    static let heroText = Color.white
    static let heroSubtext = Color.white.opacity(0.58)

    static let safeGreen = Color(red: 0.20, green: 0.62, blue: 0.38)
    static let checkAmber = Color(red: 0.85, green: 0.55, blue: 0.12)
    static let dangerRed = Color(red: 0.78, green: 0.17, blue: 0.15)

    // Motion tokens (Emil-style — ease-out, under 300ms)
    static let easeOut = Animation.easeOut(duration: 0.16)
    static let easeDrawer = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)

    static func tint(for safety: Safety) -> Color {
        switch safety {
        case .safe: return safeGreen
        case .check, .command: return secondaryText
        case .never: return tertiaryText
        }
    }

    static func sectionAccent(_ section: AppSection) -> Color { navy }
}

// MARK: - Button styles

struct PrimaryPillButtonStyle: ButtonStyle {
    var inverted = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(inverted ? Theme.navy : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                (inverted ? Color.white : Theme.navy)
                    .opacity(configuration.isPressed ? 0.85 : 1),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.easeOut, value: configuration.isPressed)
    }
}

struct SecondaryOutlineButtonStyle: ButtonStyle {
    var lightOnDark = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(lightOnDark ? Color.white.opacity(0.92) : Theme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .strokeBorder(
                        lightOnDark ? Color.white.opacity(0.30) : Theme.hairline,
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.easeOut, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.navy : Theme.secondaryText)
    }
}

struct DestructivePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.navy.opacity(configuration.isPressed ? 0.82 : 0.92), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.easeOut, value: configuration.isPressed)
    }
}

/// Red pill for uninstall — distinct from move-to-trash actions.
struct UninstallPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.dangerRed.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.easeOut, value: configuration.isPressed)
    }
}

struct NavRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(Theme.easeOut, value: configuration.isPressed)
    }
}

/// Sidebar nav — instant press feedback, selected + hover states (Purge-style).
struct SidebarNavButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Theme.navy)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 5)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Theme.easeOut, value: configuration.isPressed)
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isSelected { return Theme.navy.opacity(0.11) }
        if isPressed { return Theme.navy.opacity(0.07) }
        return Color.clear
    }
}

// MARK: - Modifiers

struct ElevatedCard: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

struct SoftTintCard: ViewModifier {
    var radius: CGFloat = 12
    var selected = false
    func body(content: Content) -> some View {
        content
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        selected ? Theme.navy.opacity(0.45) : Theme.hairline.opacity(0.72),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

extension View {
    func elevatedCard(radius: CGFloat = 12) -> some View { modifier(ElevatedCard(radius: radius)) }
    func softTintCard(radius: CGFloat = 12, selected: Bool = false) -> some View {
        modifier(SoftTintCard(radius: radius, selected: selected))
    }
    func displayTitle() -> some View { tracking(-0.02) }

    /// Detail panel enter — occasional, 180ms ease-out only.
    func detailTransition(active: Bool) -> some View {
        self
            .opacity(active ? 1 : 0)
            .offset(x: active ? 0 : 12)
            .animation(Theme.easeDrawer, value: active)
    }
}

struct SectionIconBadge: View {
    let section: AppSection
    var size: CGFloat = 32
    var filled = false

    var body: some View {
        Image(systemName: section.icon)
            .font(.system(size: size * 0.42, weight: .medium))
            .symbolVariant(filled && !section.icon.hasSuffix(".fill") ? .fill : .none)
            .foregroundStyle(filled ? .white : Theme.navy)
            .frame(width: size, height: size)
            .background(
                filled ? Theme.navy : Theme.navy.opacity(0.08),
                in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            )
    }
}

struct SafetyChip: View {
    let safety: Safety
    /// Stronger warning for Library / Application Support profile risks.
    var libraryRisk: Bool = false

    private var color: Color {
        switch safety {
        case .safe: return Theme.safeGreen
        case .check: return libraryRisk ? Theme.dangerRed : Theme.checkAmber
        case .command: return Theme.navy
        case .never: return Theme.dangerRed
        }
    }

    var body: some View {
        Text(libraryRisk && safety == .check ? "REVIEW — PROFILE RISK" : safety.label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
