/// How the colours between two gradient stops are blended.
public enum GradientInterpolation: Hashable, Sendable {
    /// Straight lerp of gamma-encoded sRGB values — CSS `in srgb`, SwiftUI's
    /// `Gradient.ColorSpace.device`, and what `CGGradient` does. (Not to be
    /// confused with linear-light blending, CSS `in srgb-linear`, which
    /// ``pythagorean`` approximates. SwiftUI's *default* gradient colour space
    /// is `.perceptual`, which renders very close to ``oklab``.)
    case sRGB
    /// Root-mean-square of gamma-encoded sRGB: `sqrt((1-t)·a² + t·b²)`.
    case pythagorean
    /// Lerp in OKLab. Perceptually even lightness; stays on the straight line
    /// between the two colours, so complementary pairs pass through grey.
    /// Out-of-gamut results are gamut mapped with ``GamutMapping/reduceChroma``.
    case oklab
    /// Lerp of lightness, chroma and hue in OKLCH. Keeps colours saturated by
    /// travelling around the hue wheel rather than through grey. Out-of-gamut
    /// results are gamut mapped with ``GamutMapping/reduceChroma``.
    case oklch(HueInterpolation)

    /// OKLCH taking the shorter way round the hue wheel.
    public static let oklch = GradientInterpolation.oklch(.shorter)
}

extension ColorComponents {
    public static func interpolate(
        _ a: ColorComponents, _ b: ColorComponents,
        fraction t: Double, using interpolation: GradientInterpolation
    ) -> ColorComponents {
        switch interpolation {
        case .sRGB: linear(a, b, fraction: t)
        case .pythagorean: pythagorean(a, b, fraction: t)
        case .oklab: oklab(a, b, fraction: t)
        case let .oklch(hue): oklch(a, b, fraction: t, hue: hue)
        }
    }

    /// Interpolation in OKLab with premultiplied alpha (as CSS Color 4 does).
    public static func oklab(
        _ a: ColorComponents, _ b: ColorComponents,
        fraction t: Double, mapping: GamutMapping = .reduceChroma
    ) -> ColorComponents {
        let la = OKLab(a), lb = OKLab(b)
        let alpha = lerp(a.alpha, b.alpha, t)
        func mix(_ x: Double, _ y: Double) -> Double {
            alpha > 0 ? lerp(x * a.alpha, y * b.alpha, t) / alpha : 0
        }
        return OKLab(
            lightness: mix(la.lightness, lb.lightness),
            a: mix(la.a, lb.a),
            b: mix(la.b, lb.b),
            alpha: alpha
        ).components(mapping: mapping)
    }

    /// Interpolation in OKLCH. Lightness and chroma are premultiplied by alpha;
    /// hue is not. A grey endpoint takes the other endpoint's hue so a fade to
    /// white/black/grey doesn't swing through unrelated colours.
    public static func oklch(
        _ a: ColorComponents, _ b: ColorComponents,
        fraction t: Double, hue method: HueInterpolation = .shorter,
        mapping: GamutMapping = .reduceChroma
    ) -> ColorComponents {
        let ca = OKLCH(a), cb = OKLCH(b)
        var h1 = ca.hue, h2 = cb.hue
        switch (ca.isAchromatic, cb.isAchromatic) {
        case (true, false): h1 = h2
        case (false, true): h2 = h1
        default: break
        }
        (h1, h2) = method.fixup(h1, h2)

        let alpha = lerp(a.alpha, b.alpha, t)
        func mix(_ x: Double, _ y: Double) -> Double {
            alpha > 0 ? lerp(x * a.alpha, y * b.alpha, t) / alpha : 0
        }
        let hue = lerp(h1, h2, t).truncatingRemainder(dividingBy: 360)
        return OKLCH(
            lightness: mix(ca.lightness, cb.lightness),
            chroma: mix(ca.chroma, cb.chroma),
            hue: hue < 0 ? hue + 360 : hue,
            alpha: alpha
        ).components(mapping: mapping)
    }
}

private func lerp(_ x: Double, _ y: Double, _ t: Double) -> Double { x + (y - x) * t }
