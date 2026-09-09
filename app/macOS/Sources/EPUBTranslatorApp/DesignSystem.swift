import AppKit
import SwiftUI

enum AppColors {
    static let canvas = adaptive(
        light: NSColor(calibratedRed: 0.986, green: 0.979, blue: 0.965, alpha: 1),
        dark: NSColor(calibratedRed: 0.105, green: 0.116, blue: 0.126, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(calibratedRed: 0.973, green: 0.966, blue: 0.951, alpha: 0.99),
        dark: NSColor(calibratedRed: 0.126, green: 0.139, blue: 0.151, alpha: 0.98)
    )
    static let card = adaptive(
        light: NSColor(calibratedRed: 1.000, green: 0.997, blue: 0.989, alpha: 0.91),
        dark: NSColor(calibratedRed: 0.145, green: 0.158, blue: 0.171, alpha: 0.94)
    )
    static let cardStrong = adaptive(
        light: NSColor(calibratedRed: 1.000, green: 0.998, blue: 0.992, alpha: 0.97),
        dark: NSColor(calibratedRed: 0.166, green: 0.179, blue: 0.193, alpha: 0.98)
    )
    static let primaryText = adaptive(
        light: NSColor(calibratedRed: 0.075, green: 0.145, blue: 0.210, alpha: 1),
        dark: NSColor(calibratedRed: 0.875, green: 0.894, blue: 0.908, alpha: 1)
    )
    static let secondaryText = adaptive(
        light: NSColor(calibratedRed: 0.285, green: 0.360, blue: 0.430, alpha: 1),
        dark: NSColor(calibratedRed: 0.660, green: 0.700, blue: 0.730, alpha: 1)
    )
    static let slate = adaptive(
        light: NSColor(calibratedRed: 0.275, green: 0.425, blue: 0.650, alpha: 1),
        dark: NSColor(calibratedRed: 0.485, green: 0.610, blue: 0.760, alpha: 1)
    )
    static let slateWash = adaptive(
        light: NSColor(calibratedRed: 0.825, green: 0.860, blue: 0.910, alpha: 0.72),
        dark: NSColor(calibratedRed: 0.255, green: 0.320, blue: 0.395, alpha: 0.72)
    )
    static let terracotta = adaptive(
        light: NSColor(calibratedRed: 0.770, green: 0.350, blue: 0.175, alpha: 1),
        dark: NSColor(calibratedRed: 0.820, green: 0.500, blue: 0.380, alpha: 1)
    )
    static let border = adaptive(
        light: NSColor(calibratedRed: 0.310, green: 0.390, blue: 0.455, alpha: 0.18),
        dark: NSColor(calibratedRed: 0.750, green: 0.780, blue: 0.800, alpha: 0.18)
    )
    static let linework = adaptive(
        light: NSColor(calibratedRed: 0.355, green: 0.475, blue: 0.585, alpha: 0.085),
        dark: NSColor(calibratedRed: 0.475, green: 0.585, blue: 0.675, alpha: 0.11)
    )
    static let paperGrain = adaptive(
        light: NSColor(calibratedWhite: 0.40, alpha: 0.025),
        dark: NSColor(calibratedWhite: 0.82, alpha: 0.018)
    )
    static let embossShadow = adaptive(
        light: NSColor(calibratedRed: 0.310, green: 0.390, blue: 0.455, alpha: 0.075),
        dark: NSColor(calibratedRed: 0.020, green: 0.030, blue: 0.040, alpha: 0.26)
    )
    static let embossHighlight = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.78),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.075)
    )
    static let success = adaptive(
        light: NSColor(calibratedRed: 0.285, green: 0.590, blue: 0.425, alpha: 1),
        dark: NSColor(calibratedRed: 0.390, green: 0.690, blue: 0.520, alpha: 1)
    )
    static let warning = adaptive(
        light: NSColor(calibratedRed: 0.725, green: 0.455, blue: 0.235, alpha: 1),
        dark: NSColor(calibratedRed: 0.825, green: 0.575, blue: 0.325, alpha: 1)
    )
    static let error = adaptive(
        light: NSColor(calibratedRed: 0.675, green: 0.295, blue: 0.295, alpha: 1),
        dark: NSColor(calibratedRed: 0.820, green: 0.455, blue: 0.450, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum AppTypography {
    static let pageTitle = Font.system(size: 31, weight: .semibold, design: .serif)
    static let brand = Font.system(size: 20, weight: .semibold, design: .serif)
    static let heroTitle = Font.system(size: 34, weight: .semibold, design: .serif)
    static let section = Font.system(size: 13, weight: .semibold, design: .default)
    static let cardTitle = Font.system(size: 15, weight: .semibold, design: .default)
    static let body = Font.system(size: 14, weight: .regular, design: .default)
}

enum AppSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let regular: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let page: CGFloat = 36
}

enum AppRadius {
    static let input: CGFloat = 8
    static let button: CGFloat = 9
    static let card: CGFloat = 12
    static let window: CGFloat = 18
}

enum AppShadow {
    static let color = Color.black.opacity(0.032)
    static let radius: CGFloat = 7
    static let y: CGFloat = 2
}

struct AppCardModifier: ViewModifier {
    var strong = false
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(strong ? AppColors.cardStrong : AppColors.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                            .stroke(tint?.opacity(0.28) ?? AppColors.border, lineWidth: 1)
                    }
            }
            .shadow(color: AppShadow.color, radius: AppShadow.radius, x: 0, y: AppShadow.y)
    }
}

extension View {
    func appCard(strong: Bool = false, tint: Color? = nil) -> some View {
        modifier(AppCardModifier(strong: strong, tint: tint))
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 18)
            .frame(minHeight: 38)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(AppColors.slate.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45))
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppColors.primaryText.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 15)
            .frame(minHeight: 36)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(AppColors.cardStrong.opacity(configuration.isPressed ? 0.72 : 0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    }
            }
    }
}

struct AppSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? AppColors.primaryText : AppColors.secondaryText)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? AppColors.slateWash
                          : AppColors.card.opacity(configuration.isPressed ? 0.72 : 0))
                    .overlay(alignment: .leading) {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(AppColors.terracotta)
                                .frame(width: 3, height: 22)
                                .padding(.leading, 2)
                        }
                    }
            }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.primaryText)
                .accessibilityIdentifier(accessibilityIdentifier)
            Text(subtitle)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AppSectionHeading: View {
    let title: String
    var icon: String?

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(AppColors.terracotta)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(AppTypography.section)
                .foregroundStyle(AppColors.primaryText)
        }
    }
}

struct ArchitecturalLineworkBackground: View {
    let variant: Int

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawPlan(in: &context, size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawPlan(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let stroke = GraphicsContext.Shading.color(AppColors.linework)

        drawPaperGrain(in: &context, size: size)
        drawEmbossedMark(in: &context, size: size)

        for index in 0..<12 {
            let offset = CGFloat(index) * 31 + CGFloat(variant * 9)
            var path = Path()
            path.move(to: CGPoint(x: w * 0.55 + offset, y: -20))
            path.addLine(to: CGPoint(x: w * 0.42 + offset, y: h * 0.27))
            path.addLine(to: CGPoint(x: w * 0.72 + offset, y: h * 0.46))
            context.stroke(path, with: stroke, lineWidth: index.isMultiple(of: 4) ? 0.9 : 0.55)
        }

        for row in 0..<5 {
            for column in 0..<6 {
                let x = w * 0.63 + CGFloat(column) * 52 + CGFloat(row % 2) * 13
                let y = 42 + CGFloat(row) * 49 + CGFloat(column % 3) * 4
                let width = CGFloat(26 + ((row + column + variant) % 4) * 7)
                let height = CGFloat(17 + ((row * 2 + column) % 3) * 6)
                let rect = CGRect(x: x, y: y, width: width, height: height)
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.5), with: stroke, lineWidth: 0.65)
                if (row + column).isMultiple(of: 3) {
                    var axis = Path()
                    axis.move(to: CGPoint(x: rect.midX, y: rect.minY - 9))
                    axis.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + 9))
                    context.stroke(axis, with: stroke, lineWidth: 0.45)
                }
            }
        }

        for index in 0..<9 {
            let y = h - 34 - CGFloat(index) * 25
            var path = Path()
            path.move(to: CGPoint(x: -24, y: y))
            path.addLine(to: CGPoint(x: w * 0.18 + CGFloat(index) * 9, y: y - 48))
            path.addLine(to: CGPoint(x: w * 0.29, y: y - 20))
            context.stroke(path, with: stroke, lineWidth: 0.55)
        }

        let marker = CGRect(x: w * 0.89, y: h * 0.28, width: 5, height: 5)
        context.fill(Path(ellipseIn: marker), with: .color(AppColors.terracotta.opacity(0.24)))
    }

    private func drawPaperGrain(in context: inout GraphicsContext, size: CGSize) {
        for index in 0..<180 {
            let xSeed = (index * 73 + variant * 31) % 997
            let ySeed = (index * 151 + variant * 47) % 991
            let x = CGFloat(xSeed) / 997 * size.width
            let y = CGFloat(ySeed) / 991 * size.height
            let length = CGFloat(1 + (index % 3))
            var fiber = Path()
            fiber.move(to: CGPoint(x: x, y: y))
            fiber.addLine(to: CGPoint(x: x + length, y: y + CGFloat(index % 2)))
            context.stroke(fiber, with: .color(AppColors.paperGrain), lineWidth: 0.45)
        }
    }

    private func drawEmbossedMark(in context: inout GraphicsContext, size: CGSize) {
        let markSize = min(size.width, size.height) * 0.50
        let center: CGPoint
        switch variant {
        case 0:
            center = CGPoint(x: size.width * 0.84, y: size.height * 0.66)
        case 1:
            center = CGPoint(x: size.width * 0.88, y: size.height * 0.70)
        default:
            center = CGPoint(x: size.width * 0.86, y: size.height * 0.72)
        }

        let rect = CGRect(
            x: center.x - markSize * 0.5,
            y: center.y - markSize * 0.5,
            width: markSize,
            height: markSize
        )
        let lineWidth = max(18, markSize * 0.105)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        for path in embossedMarkPaths(in: rect) {
            context.stroke(
                path.applying(CGAffineTransform(translationX: 2.2, y: 2.4)),
                with: .color(AppColors.embossShadow),
                style: style
            )
            context.stroke(
                path.applying(CGAffineTransform(translationX: -1.4, y: -1.6)),
                with: .color(AppColors.embossHighlight),
                style: style
            )
            context.stroke(
                path,
                with: .color(AppColors.canvas.opacity(0.34)),
                style: style
            )
        }
    }

    private func embossedMarkPaths(in rect: CGRect) -> [Path] {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var topArc = Path()
        topArc.move(to: point(0.31, 0.16))
        topArc.addCurve(
            to: point(0.69, 0.16),
            control1: point(0.34, 0.42),
            control2: point(0.66, 0.42)
        )

        var trunk = Path()
        trunk.move(to: point(0.23, 0.31))
        trunk.addLine(to: point(0.50, 0.56))
        trunk.addLine(to: point(0.77, 0.31))
        trunk.move(to: point(0.50, 0.56))
        trunk.addLine(to: point(0.50, 0.86))

        var leftArc = Path()
        leftArc.move(to: point(0.18, 0.51))
        leftArc.addCurve(
            to: point(0.27, 0.77),
            control1: point(0.41, 0.54),
            control2: point(0.42, 0.69)
        )

        var rightArc = Path()
        rightArc.move(to: point(0.82, 0.51))
        rightArc.addCurve(
            to: point(0.73, 0.77),
            control1: point(0.59, 0.54),
            control2: point(0.58, 0.69)
        )

        return [topArc, trunk, leftArc, rightArc]
    }
}
