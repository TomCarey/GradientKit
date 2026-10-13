import Foundation

/// A colour in Björn Ottosson's OKLab perceptual colour space.
///
/// `lightness` is roughly `0...1`; `a` (green ↔ red) and `b` (blue ↔ yellow)
/// are roughly `-0.4...0.4`. Equal steps in OKLab look like equal steps in
/// colour, so blending here gives even, perceptually smooth gradients.
public struct OKLab: Hashable, Sendable {
    public var lightness: Double
    public var a: Double
    public var b: Double
    public var alpha: Double

    public init(lightness: Double, a: Double, b: Double, alpha: Double = 1) {
        self.lightness = lightness
        self.a = a
        self.b = b
        self.alpha = alpha
    }

    public init(_ c: ColorComponents) {
        let r = srgbToLinear(c.red), g = srgbToLinear(c.green), b = srgbToLinear(c.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        self.init(
            lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
            alpha: c.alpha
        )
    }

    public init(_ c: OKLCH) {
        let radians = c.hue * .pi / 180
        self.init(lightness: c.lightness, a: c.chroma * cos(radians), b: c.chroma * sin(radians), alpha: c.alpha)
    }

    /// Converts back to gamma-encoded sRGB, bringing out-of-gamut colours into
    /// sRGB with ``GamutMapping/reduceChroma``.
    public var components: ColorComponents { components(mapping: .reduceChroma) }

    /// Converts back to gamma-encoded sRGB using the given gamut mapping.
    public func components(mapping: GamutMapping) -> ColorComponents {
        switch mapping {
        case .clip: clipped
        case .reduceChroma: OKLCH(self).gamutMapped
        }
    }

    /// Linear-light sRGB, unclamped. Components outside `0...1` mean the colour
    /// can't be shown on an sRGB display.
    var linearSRGB: (red: Double, green: Double, blue: Double) {
        let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// Whether the colour fits inside sRGB (with a little tolerance for rounding).
    public var isInSRGBGamut: Bool {
        let c = linearSRGB
        let range = -1e-6...(1 + 1e-6)
        return range.contains(c.red) && range.contains(c.green) && range.contains(c.blue)
    }

    /// Channel-wise clamp to `0...1` — fast, but can shift hue and lightness.
    var clipped: ColorComponents {
        let c = linearSRGB
        func encode(_ x: Double) -> Double { min(max(linearToSRGB(x), 0), 1) }
        return ColorComponents(red: encode(c.red), green: encode(c.green), blue: encode(c.blue), alpha: alpha)
    }

    /// Euclidean distance in OKLab ("ΔE OK"). About 0.02 is a just-noticeable difference.
    public func distance(to other: OKLab) -> Double {
        let dl = lightness - other.lightness, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}

/// How a colour that falls outside the sRGB gamut is brought back inside it.
public enum GamutMapping: Hashable, Sendable {
    /// Clamp each RGB channel to `0...1`. Fast, but can visibly change hue and
    /// lightness and leaves hard creases in gradients.
    case clip
    /// The CSS Color 4 algorithm: keep lightness and hue, and reduce chroma
    /// until the colour fits (to within a just-noticeable difference).
    case reduceChroma
}

/// OKLab in polar form: lightness, chroma (colourfulness) and hue in degrees.
public struct OKLCH: Hashable, Sendable {
    public var lightness: Double
    public var chroma: Double
    /// Degrees in `0..<360`. Meaningless ("powerless") when `chroma` is ~0.
    public var hue: Double
    public var alpha: Double

    public init(lightness: Double, chroma: Double, hue: Double, alpha: Double = 1) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
        self.alpha = alpha
    }

    public init(_ lab: OKLab) {
        let hue = atan2(lab.b, lab.a) * 180 / .pi
        self.init(
            lightness: lab.lightness,
            chroma: (lab.a * lab.a + lab.b * lab.b).squareRoot(),
            hue: hue < 0 ? hue + 360 : hue,
            alpha: lab.alpha
        )
    }

    public init(_ c: ColorComponents) { self.init(OKLab(c)) }

    public var components: ColorComponents { OKLab(self).components }

    public func components(mapping: GamutMapping) -> ColorComponents { OKLab(self).components(mapping: mapping) }

    /// Below this chroma a colour is treated as grey and its hue is ignored.
    static let achromaticThreshold = 1e-4

    var isAchromatic: Bool { chroma < Self.achromaticThreshold }

    /// CSS Color 4 gamut mapping (§13.2): binary-search the largest chroma, at
    /// this lightness and hue, whose clipped sRGB value is within a
    /// just-noticeable difference of the unclipped colour.
    var gamutMapped: ColorComponents {
        let justNoticeable = 0.02, epsilon = 0.0001
        if lightness >= 1 { return ColorComponents(red: 1, green: 1, blue: 1, alpha: alpha) }
        if lightness <= 0 { return ColorComponents(red: 0, green: 0, blue: 0, alpha: alpha) }

        var current = self
        if OKLab(current).isInSRGBGamut { return OKLab(current).clipped }

        func error(of clipped: ColorComponents) -> Double {
            OKLab(clipped).distance(to: OKLab(current))
        }
        var clipped = OKLab(current).clipped
        if error(of: clipped) < justNoticeable { return clipped }

        var low = 0.0, high = chroma, lowInGamut = true
        while high - low > epsilon {
            current.chroma = (low + high) / 2
            if lowInGamut && OKLab(current).isInSRGBGamut {
                low = current.chroma
                continue
            }
            clipped = OKLab(current).clipped
            let e = error(of: clipped)
            if e < justNoticeable {
                if justNoticeable - e < epsilon { return clipped }
                lowInGamut = false
                low = current.chroma
            } else {
                high = current.chroma
            }
        }
        return OKLab(current).clipped
    }
}

/// Which way round the colour wheel an OKLCH gradient travels, matching CSS
/// Color 4's `<hue-interpolation-method>`.
public enum HueInterpolation: Hashable, Sendable {
    /// The shortest arc (≤ 180°). The CSS default.
    case shorter
    /// The long way round (≥ 180°).
    case longer
    /// Always increasing hue angle.
    case increasing
    /// Always decreasing hue angle.
    case decreasing

    /// Returns hue angles adjusted so that a straight lerp between them follows this method.
    func fixup(_ h1: Double, _ h2: Double) -> (Double, Double) {
        let delta = h2 - h1
        switch self {
        case .shorter:
            if delta > 180 { return (h1 + 360, h2) }
            if delta < -180 { return (h1, h2 + 360) }
        case .longer:
            if delta > 0 && delta < 180 { return (h1 + 360, h2) }
            if delta > -180 && delta <= 0 { return (h1, h2 + 360) }
        case .increasing:
            if h2 < h1 { return (h1, h2 + 360) }
        case .decreasing:
            if h1 < h2 { return (h1 + 360, h2) }
        }
        return (h1, h2)
    }
}

// MARK: - sRGB transfer function (sign-preserving for extended range)

func srgbToLinear(_ x: Double) -> Double {
    let v = abs(x)
    let linear = v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    return x < 0 ? -linear : linear
}

func linearToSRGB(_ x: Double) -> Double {
    let v = abs(x)
    let encoded = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    return x < 0 ? -encoded : encoded
}
