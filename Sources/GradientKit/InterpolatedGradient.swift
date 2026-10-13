import SwiftUI

/// A gradient whose colours are blended in OKLab (the default), OKLCH or with
/// Pythagorean (root-mean-square) interpolation instead of plain sRGB.
///
/// Use it anywhere a `ShapeStyle` is accepted:
///
/// ```swift
/// Rectangle().fill(.interpolatedLinear(colors: [.red, .green], startPoint: .leading, endPoint: .trailing))
/// Circle().fill(.interpolatedRadial(colors: [.yellow, .blue], startRadius: 0, endRadius: 100))
/// Rectangle().fill(.interpolatedLinear(colors: [.blue, .yellow], interpolation: .oklch, startPoint: .top, endPoint: .bottom))
/// Rectangle().fill(.interpolatedLinear(colors: [.black, .white], interpolation: .pythagorean, easing: .easeInOut, startPoint: .leading, endPoint: .trailing))
/// ```
///
/// Or draw it directly with Quartz shadings via ``InterpolatedShadingView``.
public struct InterpolatedGradient: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public var color: Color
        public var location: Double

        public init(color: Color, location: Double) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    /// How colours between stops are blended. Defaults to ``GradientInterpolation/oklab``.
    public var interpolation: GradientInterpolation

    /// How quickly each segment moves between its two colours. Defaults to ``GradientEasing/linear``.
    public var easing: GradientEasing

    /// The largest colour error (ΔE OK; ~0.02 is just noticeable) allowed when
    /// approximating the curve with stops that are blended linearly — as SwiftUI
    /// gradients and `CAGradientLayer` do. See ``Resolved/approximationStops(tolerance:)``.
    public var tolerance: Double

    public init(
        stops: [Stop],
        interpolation: GradientInterpolation = .oklab,
        easing: GradientEasing = .linear,
        tolerance: Double = Resolved.defaultTolerance
    ) {
        self.stops = stops.sorted { $0.location < $1.location }
        self.interpolation = interpolation
        self.easing = easing
        self.tolerance = tolerance
    }

    /// Evenly spaced colours, like `Gradient(colors:)`.
    public init(
        colors: [Color],
        interpolation: GradientInterpolation = .oklab,
        easing: GradientEasing = .linear,
        tolerance: Double = Resolved.defaultTolerance
    ) {
        let last = Double(max(colors.count - 1, 1))
        self.init(
            stops: colors.enumerated().map { Stop(color: $1, location: Double($0) / last) },
            interpolation: interpolation,
            easing: easing,
            tolerance: tolerance
        )
    }

    public init(
        _ gradient: Gradient,
        interpolation: GradientInterpolation = .oklab,
        easing: GradientEasing = .linear,
        tolerance: Double = Resolved.defaultTolerance
    ) {
        self.init(
            stops: gradient.stops.map { Stop(color: $0.color, location: Double($0.location)) },
            interpolation: interpolation,
            easing: easing,
            tolerance: tolerance
        )
    }

    /// `color` fading out to transparent, or into `endColor`.
    ///
    /// Fades ease in and out by default. A straight linear fade starts and stops
    /// abruptly, leaving a visible edge where it meets the solid colour. To hold the
    /// solid colour or the transparency over part of a shape, move the gradient's
    /// start and end points in, since the end colours extend beyond them:
    ///
    /// ```swift
    /// // Clear over the top half, fading in to the background at the bottom.
    /// Rectangle().fill(.interpolatedLinear(.fade(.background), startPoint: .bottom, endPoint: .center))
    /// ```
    public static func fade(
        _ color: Color,
        to endColor: Color? = nil,
        interpolation: GradientInterpolation = .oklab,
        easing: GradientEasing = .easeInOut,
        tolerance: Double = Resolved.defaultTolerance
    ) -> InterpolatedGradient {
        // Fade to the same colour rather than `.clear`, which `.sRGB` doesn't premultiply.
        InterpolatedGradient(
            colors: [color, endColor ?? color.opacity(0)],
            interpolation: interpolation,
            easing: easing,
            tolerance: tolerance
        )
    }

    /// Resolves the stops' colours for an environment, producing a value that
    /// can be sampled at any location.
    public func resolved(in environment: EnvironmentValues) -> Resolved {
        Resolved(
            stops: stops.map { (ColorComponents($0.color, in: environment), $0.location) },
            interpolation: interpolation,
            easing: easing
        )
    }

    /// A SwiftUI `Gradient` with enough intermediate stops to reproduce the
    /// interpolation curve.
    public func swiftUIGradient(in environment: EnvironmentValues) -> Gradient {
        resolved(in: environment).swiftUIGradient(tolerance: tolerance)
    }

    /// A gradient whose colours have been converted to concrete components.
    public struct Resolved: Sendable {
        public let stops: [(components: ColorComponents, location: Double)]
        public let interpolation: GradientInterpolation
        public let easing: GradientEasing

        public init(
            stops: [(components: ColorComponents, location: Double)],
            interpolation: GradientInterpolation = .oklab,
            easing: GradientEasing = .linear
        ) {
            self.stops = stops.sorted { $0.location < $1.location }
            self.interpolation = interpolation
            self.easing = easing
        }

        /// The colour a fraction `t` of the way from `a` to `b`, after easing.
        func blend(_ a: ColorComponents, _ b: ColorComponents, _ t: Double) -> ColorComponents {
            .interpolate(a, b, fraction: easing.apply(t), using: interpolation)
        }

        /// The colour at `location`, clamping beyond the first and last stops.
        public func components(at location: Double) -> ColorComponents {
            guard let first = stops.first, let last = stops.last else {
                return ColorComponents(red: 0, green: 0, blue: 0, alpha: 0)
            }
            if location <= first.location { return first.components }
            if location >= last.location { return last.components }

            let upper = stops.firstIndex { $0.location >= location }!
            let a = stops[upper - 1], b = stops[upper]
            let span = b.location - a.location
            let t = span > 0 ? (location - a.location) / span : 1
            return blend(a.components, b.components, t)
        }

        public static let defaultTolerance = 0.002

        /// The default largest colour difference (ΔE OK) between adjacent stops.
        /// See ``approximationStops(tolerance:maxStep:)``.
        public static let defaultMaxStep = 0.02

        /// Stops that reproduce this gradient when blended between each other —
        /// for SwiftUI `Gradient`s and `CAGradientLayer`.
        ///
        /// Each segment is split recursively, but only where needed:
        /// - where a straight sRGB line between its ends strays more than
        ///   `tolerance` (ΔE OK) from the exact curve — steep stretches such as
        ///   Pythagorean near black or OKLCH gamut mapping near a primary; and
        /// - where its ends differ by more than `maxStep`. Renderers don't all
        ///   blend between stops in sRGB (Core Animation uses a different gamma,
        ///   SwiftUI defaults to a perceptual space), so keeping neighbouring
        ///   stops close together makes the result independent of how the gaps
        ///   are filled.
        public func approximationStops(
            tolerance: Double = defaultTolerance,
            maxStep: Double = defaultMaxStep
        ) -> [(components: ColorComponents, location: Double)] {
            guard let first = stops.first else { return [] }
            let initialPieces = 4, maxDepth = 10
            var result = [first]

            func error(_ x: ColorComponents, _ y: ColorComponents) -> Double {
                // Colour differences matter less as the colour becomes transparent.
                max(OKLab(x).distance(to: OKLab(y)) * max(x.alpha, y.alpha), abs(x.alpha - y.alpha))
            }

            for (a, b) in zip(stops, stops.dropFirst()) {
                guard b.location > a.location else {
                    result.append(b) // Coincident stops make a hard edge; nothing to fill in.
                    continue
                }
                func color(_ t: Double) -> ColorComponents { blend(a.components, b.components, t) }
                func subdivide(_ t0: Double, _ c0: ColorComponents, _ t1: Double, _ c1: ColorComponents, depth: Int) {
                    let needsSplit = depth < maxDepth && (
                        error(c0, c1) > maxStep || [0.25, 0.5, 0.75].contains { f in
                            error(.linear(c0, c1, fraction: f), color(t0 + (t1 - t0) * f)) > tolerance
                        }
                    )
                    if needsSplit {
                        let tm = (t0 + t1) / 2, cm = color(tm)
                        subdivide(t0, c0, tm, cm, depth: depth + 1)
                        subdivide(tm, cm, t1, c1, depth: depth + 1)
                    } else {
                        result.append((c1, a.location + (b.location - a.location) * t1))
                    }
                }
                // Start from a few even pieces so a curve can't hide behind a midpoint that happens to match.
                var previous = (t: 0.0, color: a.components)
                for i in 1...initialPieces {
                    let t = Double(i) / Double(initialPieces)
                    let c = i == initialPieces ? b.components : color(t)
                    subdivide(previous.t, previous.color, t, c, depth: 0)
                    previous = (t, c)
                }
            }
            return result
        }

        public func swiftUIGradient(tolerance: Double = defaultTolerance, maxStep: Double = defaultMaxStep) -> Gradient {
            Gradient(stops: approximationStops(tolerance: tolerance, maxStep: maxStep).map { .init(color: $0.components.color, location: $0.location) })
        }
    }
}

// MARK: - ShapeStyles

public struct InterpolatedLinearGradient: ShapeStyle {
    public var gradient: InterpolatedGradient
    public var startPoint: UnitPoint
    public var endPoint: UnitPoint

    public init(gradient: InterpolatedGradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public func resolve(in environment: EnvironmentValues) -> LinearGradient {
        LinearGradient(gradient: gradient.swiftUIGradient(in: environment), startPoint: startPoint, endPoint: endPoint)
    }
}

public struct InterpolatedRadialGradient: ShapeStyle {
    public var gradient: InterpolatedGradient
    public var center: UnitPoint
    public var startRadius: CGFloat
    public var endRadius: CGFloat

    public init(gradient: InterpolatedGradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }

    public func resolve(in environment: EnvironmentValues) -> RadialGradient {
        RadialGradient(
            gradient: gradient.swiftUIGradient(in: environment),
            center: center, startRadius: startRadius, endRadius: endRadius
        )
    }
}

public struct InterpolatedAngularGradient: ShapeStyle {
    public var gradient: InterpolatedGradient
    public var center: UnitPoint
    public var startAngle: Angle
    public var endAngle: Angle

    public init(gradient: InterpolatedGradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .degrees(360)) {
        self.gradient = gradient
        self.center = center
        self.startAngle = startAngle
        self.endAngle = endAngle
    }

    public func resolve(in environment: EnvironmentValues) -> AngularGradient {
        AngularGradient(
            gradient: gradient.swiftUIGradient(in: environment),
            center: center, startAngle: startAngle, endAngle: endAngle
        )
    }
}

extension ShapeStyle where Self == InterpolatedLinearGradient {
    public static func interpolatedLinear(_ gradient: InterpolatedGradient, startPoint: UnitPoint, endPoint: UnitPoint) -> Self {
        .init(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }

    public static func interpolatedLinear(
        colors: [Color], interpolation: GradientInterpolation = .oklab, easing: GradientEasing = .linear,
        startPoint: UnitPoint, endPoint: UnitPoint
    ) -> Self {
        .init(gradient: InterpolatedGradient(colors: colors, interpolation: interpolation, easing: easing), startPoint: startPoint, endPoint: endPoint)
    }

    /// `color` at `startPoint`, fading to transparent (or `endColor`) at `endPoint`.
    /// Defaults to a scrim: solid along the bottom edge, clear at the top.
    /// See ``InterpolatedGradient/fade(_:to:interpolation:easing:tolerance:)``.
    public static func interpolatedFade(
        _ color: Color, to endColor: Color? = nil,
        interpolation: GradientInterpolation = .oklab, easing: GradientEasing = .easeInOut,
        startPoint: UnitPoint = .bottom, endPoint: UnitPoint = .top
    ) -> Self {
        .init(
            gradient: .fade(color, to: endColor, interpolation: interpolation, easing: easing),
            startPoint: startPoint, endPoint: endPoint
        )
    }
}

extension ShapeStyle where Self == InterpolatedRadialGradient {
    public static func interpolatedRadial(_ gradient: InterpolatedGradient, center: UnitPoint = .center, startRadius: CGFloat, endRadius: CGFloat) -> Self {
        .init(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius)
    }

    public static func interpolatedRadial(
        colors: [Color], interpolation: GradientInterpolation = .oklab, easing: GradientEasing = .linear,
        center: UnitPoint = .center, startRadius: CGFloat, endRadius: CGFloat
    ) -> Self {
        .init(
            gradient: InterpolatedGradient(colors: colors, interpolation: interpolation, easing: easing),
            center: center, startRadius: startRadius, endRadius: endRadius
        )
    }
}

extension ShapeStyle where Self == InterpolatedAngularGradient {
    public static func interpolatedAngular(_ gradient: InterpolatedGradient, center: UnitPoint = .center, startAngle: Angle = .zero, endAngle: Angle = .degrees(360)) -> Self {
        .init(gradient: gradient, center: center, startAngle: startAngle, endAngle: endAngle)
    }

    public static func interpolatedAngular(
        colors: [Color], interpolation: GradientInterpolation = .oklab, easing: GradientEasing = .linear,
        center: UnitPoint = .center, startAngle: Angle = .zero, endAngle: Angle = .degrees(360)
    ) -> Self {
        .init(
            gradient: InterpolatedGradient(colors: colors, interpolation: interpolation, easing: easing),
            center: center, startAngle: startAngle, endAngle: endAngle
        )
    }
}
