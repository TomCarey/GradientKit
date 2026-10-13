/// How quickly a gradient moves from one stop's colour to the next.
///
/// Easing reshapes *where* along each segment the blend happens without
/// changing *which* colours it passes through (that's ``GradientInterpolation``),
/// so the two combine freely: `.oklch` with `.easeInOut`, `.pythagorean` with
/// `.easeOut`, and so on. It applies to every segment between adjacent stops,
/// like a CSS animation timing function applied to each gradient segment.
public enum GradientEasing: Hashable, Sendable {
    /// Constant speed — the colour changes evenly across the segment.
    case linear
    /// CSS `ease`: `cubic-bezier(0.25, 0.1, 0.25, 1)`. Quick start, long soft finish.
    case ease
    /// CSS `ease-in`: `cubic-bezier(0.42, 0, 1, 1)`. Lingers on the first colour.
    case easeIn
    /// CSS `ease-out`: `cubic-bezier(0, 0, 0.58, 1)`. Lingers on the second colour.
    case easeOut
    /// CSS `ease-in-out`: `cubic-bezier(0.42, 0, 0.58, 1)`. Lingers on both colours.
    case easeInOut
    /// A custom curve from (0, 0) to (1, 1) with control points (x1, y1) and
    /// (x2, y2), as in CSS `cubic-bezier()` or `UICubicTimingParameters`.
    /// `x1` and `x2` are clamped to `0...1`; `y` values outside `0...1`
    /// (overshoot) are clamped when applied so colours never extrapolate.
    case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)

    /// Maps a linear fraction `t` in `0...1` to the eased fraction.
    public func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear: return t
        case .ease: return Self.bezier(0.25, 0.1, 0.25, 1, t)
        case .easeIn: return Self.bezier(0.42, 0, 1, 1, t)
        case .easeOut: return Self.bezier(0, 0, 0.58, 1, t)
        case .easeInOut: return Self.bezier(0.42, 0, 0.58, 1, t)
        case let .cubicBezier(x1, y1, x2, y2):
            return min(max(Self.bezier(min(max(x1, 0), 1), y1, min(max(x2, 0), 1), y2, t), 0), 1)
        }
    }

    /// Solves the Bézier for the curve parameter whose x is `x`, then returns its y.
    private static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        // Polynomial coefficients for P(s) = ((a·s + b)·s + c)·s with P0 = 0, P3 = 1.
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        func curveX(_ s: Double) -> Double { ((ax * s + bx) * s + cx) * s }
        func curveY(_ s: Double) -> Double { ((ay * s + by) * s + cy) * s }
        func slopeX(_ s: Double) -> Double { (3 * ax * s + 2 * bx) * s + cx }

        // Newton–Raphson converges in a few steps on well-behaved curves…
        var s = x
        for _ in 0..<8 {
            let error = curveX(s) - x
            if abs(error) < 1e-9 { return curveY(s) }
            let slope = slopeX(s)
            if abs(slope) < 1e-9 { break }
            s -= error / slope
        }
        // …and bisection handles the flat spots where it doesn't. x(s) is
        // monotonic on 0...1 because x1 and x2 are within 0...1.
        var low = 0.0, high = 1.0
        s = x
        while high - low > 1e-9 {
            if curveX(s) < x { low = s } else { high = s }
            s = (low + high) / 2
        }
        return curveY(s)
    }
}
