import CoreGraphics
import SwiftUI

/// Builds Quartz `CGShading`s whose colour function evaluates the gradient's
/// interpolation (Pythagorean, OKLab, OKLCH…) for every sample — the approach described in Apple's
/// "Gradients" chapter of the Quartz 2D Programming Guide, where a `CGFunction`
/// maps the shading's parameter `t ∈ [0, 1]` to colour components.
///
/// Unlike the SwiftUI `ShapeStyle`s, which approximate the curve with many
/// linear stops, this is exact at every pixel.
public enum InterpolatedShading {
    /// Holds the resolved stops for the C callback; released by Quartz with the function.
    private final class Info: Sendable {
        let gradient: InterpolatedGradient.Resolved
        init(_ gradient: InterpolatedGradient.Resolved) { self.gradient = gradient }
    }

    /// A `CGFunction` with a one-value domain `[0, 1]` and four outputs (sRGB + alpha).
    public static func function(for gradient: InterpolatedGradient.Resolved) -> CGFunction? {
        var callbacks = CGFunctionCallbacks(
            version: 0,
            evaluate: { info, input, output in
                guard let info else { return }
                let gradient = Unmanaged<Info>.fromOpaque(info).takeUnretainedValue().gradient
                let c = gradient.components(at: Double(input[0]))
                output[0] = CGFloat(c.red)
                output[1] = CGFloat(c.green)
                output[2] = CGFloat(c.blue)
                output[3] = CGFloat(c.alpha)
            },
            releaseInfo: { info in
                guard let info else { return }
                Unmanaged<Info>.fromOpaque(info).release()
            }
        )
        let domain: [CGFloat] = [0, 1]
        let range: [CGFloat] = [0, 1, 0, 1, 0, 1, 0, 1]
        let info = Unmanaged.passRetained(Info(gradient)).toOpaque()
        guard let function = CGFunction(
            info: info, domainDimension: 1, domain: domain,
            rangeDimension: 4, range: range, callbacks: &callbacks
        ) else {
            Unmanaged<Info>.fromOpaque(info).release()
            return nil
        }
        return function
    }

    /// An axial (linear) shading between two points in user space.
    public static func axial(
        _ gradient: InterpolatedGradient.Resolved,
        start: CGPoint, end: CGPoint,
        extendStart: Bool = true, extendEnd: Bool = true
    ) -> CGShading? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let function = function(for: gradient) else { return nil }
        return CGShading(
            axialSpace: space, start: start, end: end,
            function: function, extendStart: extendStart, extendEnd: extendEnd
        )
    }

    /// A radial shading between two circles in user space.
    public static func radial(
        _ gradient: InterpolatedGradient.Resolved,
        startCenter: CGPoint, startRadius: CGFloat,
        endCenter: CGPoint, endRadius: CGFloat,
        extendStart: Bool = true, extendEnd: Bool = true
    ) -> CGShading? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let function = function(for: gradient) else { return nil }
        return CGShading(
            radialSpace: space,
            start: startCenter, startRadius: startRadius,
            end: endCenter, endRadius: endRadius,
            function: function, extendStart: extendStart, extendEnd: extendEnd
        )
    }
}

/// A view that fills itself with an exact, per-pixel interpolated gradient
/// drawn by a Quartz `CGShading`.
public struct InterpolatedShadingView: View {
    public enum Kind: Hashable, Sendable {
        case axial(start: UnitPoint, end: UnitPoint)
        /// Radii are fractions of half the view's shorter side.
        case radial(center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat)
    }

    public var gradient: InterpolatedGradient
    public var kind: Kind

    @Environment(\.self) private var environment

    public init(_ gradient: InterpolatedGradient, kind: Kind) {
        self.gradient = gradient
        self.kind = kind
    }

    public init(colors: [Color], interpolation: GradientInterpolation = .oklab, easing: GradientEasing = .linear, kind: Kind) {
        self.init(InterpolatedGradient(colors: colors, interpolation: interpolation, easing: easing), kind: kind)
    }

    public var body: some View {
        let resolved = gradient.resolved(in: environment)
        Canvas { context, size in
            func point(_ unit: UnitPoint) -> CGPoint {
                CGPoint(x: unit.x * size.width, y: unit.y * size.height)
            }
            let shading: CGShading? = switch kind {
            case let .axial(start, end):
                InterpolatedShading.axial(resolved, start: point(start), end: point(end))
            case let .radial(center, startRadius, endRadius):
                InterpolatedShading.radial(
                    resolved,
                    startCenter: point(center), startRadius: startRadius * min(size.width, size.height) / 2,
                    endCenter: point(center), endRadius: endRadius * min(size.width, size.height) / 2
                )
            }
            guard let shading else { return }
            context.withCGContext { cg in
                cg.clip(to: CGRect(origin: .zero, size: size))
                cg.drawShading(shading)
            }
        }
    }
}
