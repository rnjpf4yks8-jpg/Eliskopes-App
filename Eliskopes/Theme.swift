import SwiftUI

// The eliskopes.com palette, shared with HAINTEL: navy and amber on a light slate page.
enum Theme {
    static let navy = Color(hex: 0x0B1730)
    static let navyCard = Color(hex: 0x12213F)
    static let navyRaised = Color(hex: 0x1A2C52)
    static let navyBorder = Color(hex: 0x24365C)
    static let navyOutline = Color(hex: 0x3A4C72)
    static let amber = Color(hex: 0xF2B544)
    static let ink = Color(hex: 0x0E1726)
    static let slate = Color(hex: 0x4A5568)
    static let mist = Color(hex: 0xC9D3E6)
    static let muted = Color(hex: 0x8E9BB7)
    static let page = Color(hex: 0xF5F6F8)
    static let line = Color(hex: 0xE3E7EE)
    static let blue = Color(hex: 0x1F4FD1)
    static let blueTint = Color(hex: 0xF3F6FE)
    static let green = Color(hex: 0x146C3A)
    static let greenDot = Color(hex: 0x1F9D55)
    static let orange = Color(hex: 0xB45309)
    static let red = Color(hex: 0xB42318)

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Small uppercase monospaced label, like the section eyebrows on the website.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.blue

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11, .medium))
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

/// White card with a hairline border.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

/// Navy card for the one number that matters on a screen.
struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.navy, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono = false
    var onNavy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.sans(15))
                .foregroundStyle(onNavy ? Theme.mist : Theme.slate)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? Theme.mono(15, .medium) : Theme.sans(15, .medium))
                .foregroundStyle(onNavy ? .white : Theme.ink)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

/// Green when something is done, orange when it happens later.
struct StatusBadge: View {
    let text: String
    var ready = true

    var body: some View {
        let color = ready ? Theme.green : Theme.orange
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(Theme.sans(11, .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
        .fixedSize()
    }
}

/// An icon and a sentence of explanation under a card.
struct NoteRow: View {
    let symbol: String
    let text: String
    var onNavy = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(onNavy ? Theme.amber : Theme.blue)
                .frame(width: 18)
                .padding(.top, 2)
            Text(text)
                .font(Theme.sans(14))
                .foregroundStyle(onNavy ? Theme.mist : Theme.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The amber button used for bidding and signing in.
struct AmberButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(16, .semibold))
            .foregroundStyle(Theme.navy)
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Theme.amber, in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

/// "12d 04:31:09" while bidding is open.
enum Countdown {
    static func text(to end: Date, from now: Date, long: Bool) -> String {
        var seconds = Int(end.timeIntervalSince(now))
        guard seconds > 0 else { return "Bidding closed" }
        let days = seconds / 86_400; seconds %= 86_400
        let hours = seconds / 3_600; seconds %= 3_600
        let minutes = seconds / 60; seconds %= 60
        if long {
            let clock = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            return days > 0 ? "\(days)d \(clock)" : clock
        }
        return days > 0 ? "\(days)d \(hours)h left" : String(format: "%dh %02dm left", hours, minutes)
    }
}

extension Date {
    /// "Nov 25, 3:00 PM CT": Eliskopes deadlines are always in Central Time.
    var centralText: String {
        var style = Date.FormatStyle().month(.abbreviated).day().hour().minute()
        style.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        style.locale = Money.locale
        return formatted(style) + " CT"
    }

    var shortDay: String {
        var style = Date.FormatStyle().month(.abbreviated).day()
        style.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        style.locale = Money.locale
        return formatted(style)
    }
}
