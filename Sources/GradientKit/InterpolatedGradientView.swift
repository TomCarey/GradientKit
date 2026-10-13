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
/// elevation changes.
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

    /// In unit coordinates. For `.radial` this is the centre; for `.conic`, the centre of rotation.
    open var startPoint: CGPoint {
        get { gradientLayer.startPoint }
        set { gradientLayer.startPoint = newValue }
    }

    /// In unit coordinates. For `.radial` the offset from `startPoint` sets the
    /// ellipse's radii; for `.conic` it sets the starting angle.
    open var endPoint: CGPoint {
        get { gradientLayer.endPoint }
        set { gradientLayer.endPoint = newValue }
    }

    public init(
        colors: [UIColor] = [],
        locations: [Double]? = nil,
        interpolation: GradientInterpolation = .pythagorean,
        easing: GradientEasing = .linear,
        frame: CGRect = .zero
    ) {
        super.init(frame: frame)
        commonInit()
        self.locations = locations
        self.interpolation = interpolation
        self.easing = easing
        self.colors = colors
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        startPoint = CGPoint(x: 0, y: 0.5)
        endPoint = CGPoint(x: 1, y: 0.5)
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) { (view: Self, _) in
            view.updateColors()
        }
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
