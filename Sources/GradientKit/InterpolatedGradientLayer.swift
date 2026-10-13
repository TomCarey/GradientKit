#if !os(watchOS)
import QuartzCore

/// A `CAGradientLayer` that blends its colours with a ``GradientInterpolation``.
///
/// Set ``gradientColors``, ``gradientLocations`` and ``interpolation``; the layer
/// fills in `colors` and `locations` with adaptive approximation stops (see
/// ``InterpolatedGradient/Resolved/approximationStops(tolerance:)``) so Core
/// Animation's linear blending between them tracks the exact curve. `type`,
/// `startPoint` and `endPoint` work as on any `CAGradientLayer`.
///
/// Don't set `colors` or `locations` directly — they are overwritten.
open class InterpolatedGradientLayer: CAGradientLayer {
    /// The gradient's colours. Converted to sRGB.
    open var gradientColors: [CGColor] = [] { didSet { updateStops() } }

    /// Locations for ``gradientColors`` in `0...1`, or `nil` for evenly spaced.
    open var gradientLocations: [Double]? { didSet { updateStops() } }

    open var interpolation: GradientInterpolation = .pythagorean { didSet { updateStops() } }

    open var easing: GradientEasing = .linear { didSet { updateStops() } }

    /// Maximum colour error (ΔE OK) of the approximation; ~0.02 is just noticeable.
    open var tolerance: Double = InterpolatedGradient.Resolved.defaultTolerance { didSet { updateStops() } }

    public override init() {
        super.init()
    }

    /// Used by Core Animation to create presentation layers.
    public override init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? InterpolatedGradientLayer else { return }
        gradientColors = other.gradientColors
        gradientLocations = other.gradientLocations
        interpolation = other.interpolation
        easing = other.easing
        tolerance = other.tolerance
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// The resolved gradient, ready to sample or to draw with ``InterpolatedShading``.
    public var resolvedGradient: InterpolatedGradient.Resolved {
        let components = gradientColors.compactMap(ColorComponents.init)
        let last = Double(max(components.count - 1, 1))
        let locations = gradientLocations ?? components.indices.map { Double($0) / last }
        return InterpolatedGradient.Resolved(
            stops: zip(components, locations).map { ($0, $1) },
            interpolation: interpolation,
            easing: easing
        )
    }

    private func updateStops() {
        let stops = resolvedGradient.approximationStops(tolerance: tolerance)
        colors = stops.map(\.components.cgColor)
        locations = stops.map { NSNumber(value: $0.location) }
    }
}
#endif
