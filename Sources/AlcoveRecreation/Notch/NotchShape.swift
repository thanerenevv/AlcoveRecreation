import SwiftUI

/// The notch silhouette. `.notch` hangs from the top edge with concave "ears" that blend into
/// the bezel; `.pill` is the free-floating capsule used on displays without a notch.
struct NotchShape: Shape {
    enum Style { case notch, pill }

    let style: Style
    var topCornerRadius: Double
    var bottomCornerRadius: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch style {
        case .pill:
            let radius = min(bottomCornerRadius, rect.height / 2, rect.width / 2)
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        case .notch:
            let top = min(topCornerRadius, rect.height / 2, rect.width / 4)
            let bottom = min(bottomCornerRadius, rect.height - top, rect.width / 2 - top)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                control: CGPoint(x: rect.minX + top, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                control: CGPoint(x: rect.minX + top, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                control: CGPoint(x: rect.maxX - top, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.maxX - top, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }
}
