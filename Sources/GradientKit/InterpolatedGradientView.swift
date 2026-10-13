#if canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// A UIKit view backed by an ``InterpolatedGradientLayer``.
///
/// ```swift
/// let view = InterpolatedGradientView(colors: [.systemBlue, .systemYellow], interpolation: .oklch)
/// view.startPoint = CGPoint(x: 0, y: 0)
/// view.endPoint = CGPoint(x: 1, y: 1)
/// ```
///
/// Dynamic colours (`.systemBlue`, asset-catalog colours…) are resolved against
/// the view's trait collection and re-resolved when dark mode, contrast or
/// elevation changes. If your colours also depend on custom traits, add them
/// to ``colorTraits``.
open class InterpolatedGradientView: UIView {
    open override class var layerClass: AnyClass { InterpolatedGradientLayer.self }

    public var gradientLayer: InterpolatedGradientLayer { layer as! InterpolatedGradientLayer }

    open var colors: [UIColor] = [] { didSet { updateColors() } }

    /// Locations for ``colors`` in `0...1`, or `nil` for evenly spaced.
    open var locations: [Double]? {
        get { gradientLayer.gradientLocations }
        set { gradientLayer.gradientLocations = newValue }
    }

    open var interpolation: GradientInterpolation {
        get { gradientLayer.interpolation }
        set { gradientLayer.interpolation = newValue }
    }

    open var easing: GradientEasing {
        get { gradientLayer.easing }
        set { gradientLayer.easing = newValue }
    }

    /// `.axial` (default), `.radial` or `.conic`. See `CAGradientLayer.type`.
    open var type: CAGradientLayerType {
        get { gradientLayer.type }
        set { gradientLayer.type = newValue }
    }

    /// In unit coordinates. Defaults to the top centre, so gradients run top to
    /// bottom as on `CAGradientLayer`. For `.radial` this is the centre; for
    /// `.conic`, the centre of rotation.
    open var startPoint: CGPoint {
        get { gradientLayer.startPoint }
        set { gradientLayer.startPoint = newValue }
    }

    /// In unit coordinates. Defaults to the bottom centre. For `.radial` the offset from `startPoint` sets the
    /// ellipse's radii; for `.conic` it sets the starting angle.
    open var endPoint: CGPoint {
        get { gradientLayer.endPoint }
        set { gradientLayer.endPoint = newValue }
    }

    public init(
        colors: [UIColor] = [],
        locations: [Double]? = nil,
        interpolation: GradientInterpolation = .oklab,
        easing: GradientEasing = .linear,
        frame: CGRect = .zero
    ) {
        super.init(frame: frame)
        commonInit()
        self.locations = locations
        self.interpolation = interpolation
        self.easing = easing
        self.colors = colors
        updateColors() // `didSet` doesn't run for assignments in the class's own initialiser.
    }

    /// `color` at ``startPoint``, fading to transparent (or `endColor`) at ``endPoint``.
    ///
    /// A scrim: solid along the bottom edge, clear at the top. Fades ease in and
    /// out by default, so there's no visible edge where they meet the solid
    /// colour. The end colours extend beyond the start and end points, so to
    /// hold the solid colour over the bottom fifth and fade over the rest:
    ///
    /// ```swift
    /// let scrim = InterpolatedGradientView(fading: .systemBackground)
    /// scrim.startPoint = CGPoint(x: 0.5, y: 0.8)
    /// ```
    public convenience init(
        fading color: UIColor,
        to endColor: UIColor? = nil,
        interpolation: GradientInterpolation = .oklab,
        easing: GradientEasing = .easeInOut,
        frame: CGRect = .zero
    ) {
        // Fade to the same colour rather than `.clear`, which `.sRGB` doesn't premultiply.
        self.init(
            colors: [color, endColor ?? color.withAlphaComponent(0)],
            interpolation: interpolation,
            easing: easing,
            frame: frame
        )
        startPoint = CGPoint(x: 0.5, y: 1)
        endPoint = CGPoint(x: 0.5, y: 0)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Traits whose changes re-resolve ``colors``. Defaults to the system traits
    /// that affect colour appearance; append any custom traits your dynamic
    /// colours read.
    open var colorTraits: [UITrait] = UITraitCollection.systemTraitsAffectingColorAppearance {
        didSet { registerColorTraits() }
    }

    private var colorTraitRegistration: (any UITraitChangeRegistration)?

    private func commonInit() {
        registerColorTraits()
    }

    private func registerColorTraits() {
        if let colorTraitRegistration {
            unregisterForTraitChanges(colorTraitRegistration)
        }
        colorTraitRegistration = registerForTraitChanges(colorTraits) { (view: Self, _) in
            view.updateColors()
        }
        updateColors()
    }

    private func updateColors() {
        gradientLayer.gradientColors = colors.map { $0.resolvedColor(with: traitCollection).cgColor }
    }
}

#Preview("UIKit view") {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 8
    stack.isLayoutMarginsRelativeArrangement = true
    stack.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)

    let modes: [(String, GradientInterpolation)] = [
        ("sRGB", .sRGB), ("Pythagorean", .pythagorean), ("OKLab", .oklab), ("OKLCH", .oklch),
    ]
    for (name, mode) in modes {
        let label = UILabel()
        label.text = name
        label.font = .preferredFont(forTextStyle: .caption1)
        let gradient = InterpolatedGradientView(colors: [.systemBlue, .systemYellow], interpolation: mode)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.layer.cornerRadius = 6
        gradient.clipsToBounds = true
        gradient.heightAnchor.constraint(equalToConstant: 36).isActive = true
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(gradient)
    }

    let shapes = UIStackView()
    shapes.spacing = 8
    shapes.distribution = .fillEqually
    let radial = InterpolatedGradientView(colors: [.white, .systemIndigo, .black], interpolation: .oklab)
    radial.type = .radial
    radial.startPoint = CGPoint(x: 0.5, y: 0.5)
    radial.endPoint = CGPoint(x: 1, y: 1)
    let conic = InterpolatedGradientView(colors: [.red, .red], interpolation: .oklch(.increasing))
    conic.type = .conic
    conic.startPoint = CGPoint(x: 0.5, y: 0.5)
    conic.endPoint = CGPoint(x: 0.5, y: 0)
    for view in [radial, conic] {
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        shapes.addArrangedSubview(view)
    }
    shapes.heightAnchor.constraint(equalToConstant: 140).isActive = true
    stack.addArrangedSubview(shapes)
    return stack
}
#endif
