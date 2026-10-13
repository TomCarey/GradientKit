import SwiftUI
import Testing
@testable import GradientKit

private let red = ColorComponents(red: 1, green: 0, blue: 0)
private let green = ColorComponents(red: 0, green: 1, blue: 0)

@Test func endpointsAreExact() {
    #expect(ColorComponents.pythagorean(red, green, fraction: 0) == red)
    #expect(ColorComponents.pythagorean(red, green, fraction: 1) == green)
}

@Test func midpointIsRootMeanSquare() {
    let mid = ColorComponents.pythagorean(red, green, fraction: 0.5)
    #expect(abs(mid.red - 0.5.squareRoot()) < 1e-12)
    #expect(abs(mid.green - 0.5.squareRoot()) < 1e-12)
    #expect(mid.blue == 0)
    #expect(mid.alpha == 1)
}

@Test func midpointIsBrighterThanLinear() {
    let linear = ColorComponents.linear(red, green, fraction: 0.5)
    let pythagorean = ColorComponents.pythagorean(red, green, fraction: 0.5)
    #expect(pythagorean.red > linear.red)
    #expect(pythagorean.green > linear.green)
}

@Test(arguments: [GradientInterpolation.pythagorean, .oklab, .oklch])
func fadeToClearKeepsColour(_ mode: GradientInterpolation) {
    let orange = ColorComponents(red: 1, green: 0.6, blue: 0.2)
    let clear = ColorComponents(red: 0, green: 0, blue: 0, alpha: 0)
    for t in [0.25, 0.5, 0.9] {
        let mixed = ColorComponents.interpolate(orange, clear, fraction: t, using: mode)
        #expect(abs(mixed.alpha - (1 - t)) < 1e-12)
        #expect(abs(mixed.red - orange.red) < 1e-6)
        #expect(abs(mixed.green - orange.green) < 1e-6)
        #expect(abs(mixed.blue - orange.blue) < 1e-6)
    }
}

@Test func resolvedSamplesAcrossMultipleStops() {
    let blue = ColorComponents(red: 0, green: 0, blue: 1)
    let gradient = InterpolatedGradient.Resolved(stops: [(red, 0), (green, 0.5), (blue, 1)], interpolation: .pythagorean)
    #expect(gradient.components(at: -1) == red)
    #expect(gradient.components(at: 0.5) == green)
    #expect(gradient.components(at: 2) == blue)
    #expect(abs(gradient.components(at: 0.75).blue - 0.5.squareRoot()) < 1e-12)
}

@Test func shadingFunctionIsCreated() {
    let gradient = InterpolatedGradient.Resolved(stops: [(red, 0), (green, 1)])
    #expect(InterpolatedShading.axial(gradient, start: .zero, end: CGPoint(x: 1, y: 0)) != nil)
}

// MARK: - OKLab / OKLCH

private func isClose(_ a: ColorComponents, _ b: ColorComponents, tolerance: Double = 1e-6) -> Bool {
    abs(a.red - b.red) < tolerance && abs(a.green - b.green) < tolerance
        && abs(a.blue - b.blue) < tolerance && abs(a.alpha - b.alpha) < tolerance
}

@Test func oklabRoundTrips() {
    for c in [red, green, ColorComponents(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.4)] {
        #expect(isClose(OKLab(c).components, c))
        #expect(isClose(OKLCH(c).components, c))
    }
}

@Test func oklabReferenceValues() {
    // Reference values from Björn Ottosson's OKLab post.
    let white = OKLab(ColorComponents(red: 1, green: 1, blue: 1))
    #expect(abs(white.lightness - 1) < 1e-4 && abs(white.a) < 1e-4 && abs(white.b) < 1e-4)
    let redLab = OKLab(red)
    #expect(abs(redLab.lightness - 0.62796) < 1e-4)
    #expect(abs(redLab.a - 0.22486) < 1e-4)
    #expect(abs(redLab.b - 0.12585) < 1e-4)
}

@Test(arguments: [GradientInterpolation.sRGB, .pythagorean, .oklab, .oklch, .oklch(.longer)])
func endpointsAreExactForEveryMode(_ mode: GradientInterpolation) {
    #expect(isClose(ColorComponents.interpolate(red, green, fraction: 0, using: mode), red))
    #expect(isClose(ColorComponents.interpolate(red, green, fraction: 1, using: mode), green))
}

@Test func oklchMidpointKeepsChromaHigherThanOklab() {
    let blue = ColorComponents(red: 0, green: 0, blue: 1)
    let yellow = ColorComponents(red: 1, green: 1, blue: 0)
    let lab = OKLCH(ColorComponents.oklab(blue, yellow, fraction: 0.5))
    let lch = OKLCH(ColorComponents.oklch(blue, yellow, fraction: 0.5))
    #expect(lch.chroma > lab.chroma)
}

@Test func hueDirections() {
    #expect(HueInterpolation.shorter.fixup(350, 10) == (350, 370))
    #expect(HueInterpolation.longer.fixup(10, 40) == (370, 40))
    #expect(HueInterpolation.increasing.fixup(40, 10) == (40, 370))
    #expect(HueInterpolation.decreasing.fixup(10, 40) == (370, 40))
}

@Test func oklchFadeToGreyKeepsHue() {
    let white = ColorComponents(red: 1, green: 1, blue: 1)
    let mid = OKLCH(ColorComponents.oklch(red, white, fraction: 0.5))
    #expect(abs(mid.hue - OKLCH(red).hue) < 1)
}

// MARK: - Gamut mapping

/// A vivid green that sRGB can't display: lightness 0.7, chroma 0.35, hue 145°.
private let outOfGamut = OKLCH(lightness: 0.7, chroma: 0.35, hue: 145)

@Test func gamutMappingLandsInGamut() {
    #expect(!OKLab(outOfGamut).isInSRGBGamut)
    let mapped = outOfGamut.components
    for channel in [mapped.red, mapped.green, mapped.blue] {
        #expect((0...1).contains(channel))
    }
}

/// The CSS algorithm finishes with a clip that may move the colour by up to a
/// just-noticeable difference, so any single hue can drift a few degrees — but
/// across the wheel it holds lightness and hue far better than clipping alone.
@Test func gamutMappingPreservesHueAndLightnessBetterThanClipping() {
    func hueError(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
    var worst = (mappedHue: 0.0, clippedHue: 0.0, mappedLightness: 0.0, clippedLightness: 0.0)
    for hue in stride(from: 0.0, to: 360, by: 10) {
        let original = OKLCH(lightness: 0.7, chroma: 0.35, hue: hue)
        let mapped = OKLCH(original.components(mapping: .reduceChroma))
        let clipped = OKLCH(original.components(mapping: .clip))
        #expect(mapped.chroma <= original.chroma)
        worst.mappedHue = max(worst.mappedHue, hueError(mapped.hue, hue))
        worst.clippedHue = max(worst.clippedHue, hueError(clipped.hue, hue))
        worst.mappedLightness = max(worst.mappedLightness, abs(mapped.lightness - 0.7))
        worst.clippedLightness = max(worst.clippedLightness, abs(clipped.lightness - 0.7))
    }
    #expect(worst.mappedHue < 6)
    #expect(worst.mappedLightness <= 0.02)
    #expect(worst.mappedHue < worst.clippedHue / 2)
    #expect(worst.mappedLightness < worst.clippedLightness / 2)
}

@Test func gamutMappingLeavesInGamutColoursAlone() {
    let colour = ColorComponents(red: 0.3, green: 0.6, blue: 0.4)
    #expect(isClose(OKLCH(colour).components(mapping: .reduceChroma), colour))
}

@Test func gamutMappingHandlesExtremeLightness() {
    #expect(OKLCH(lightness: 1.2, chroma: 0.3, hue: 30).components == ColorComponents(red: 1, green: 1, blue: 1))
    #expect(OKLCH(lightness: -0.1, chroma: 0.3, hue: 30).components == ColorComponents(red: 0, green: 0, blue: 0))
}

// MARK: - Adaptive approximation stops

@Test(arguments: [GradientInterpolation.pythagorean, .oklab, .oklch, .oklch(.longer)])
func approximationStopsStayWithinTolerance(_ mode: GradientInterpolation) {
    let pairs: [(ColorComponents, ColorComponents)] = [
        (.init(red: 0, green: 0, blue: 0), .init(red: 1, green: 1, blue: 1)),
        (.init(red: 0, green: 0, blue: 1), .init(red: 1, green: 1, blue: 0)),
        (red, .init(red: 0, green: 0, blue: 1)),
        (red, green),
        (red, .init(red: 1, green: 0, blue: 0, alpha: 0)),
    ]
    let tolerance = InterpolatedGradient.Resolved.defaultTolerance
    for (a, b) in pairs {
        let gradient = InterpolatedGradient.Resolved(stops: [(a, 0), (b, 1)], interpolation: mode)
        let stops = gradient.approximationStops(tolerance: tolerance)
        #expect(stops.first?.location == 0 && stops.last?.location == 1)
        #expect(stops.count < 600)
        var worst = 0.0
        // Pieces at the minimum width (1/4096 of a segment) have hit the depth limit, which only
        // happens at a singularity (√ at black). They are sub-pixel at any realistic size.
        for (s0, s1) in zip(stops, stops.dropFirst()) where s1.location - s0.location > 1.0 / 4096 {
            for f in stride(from: 0.1, to: 1, by: 0.1) {
                let approx = ColorComponents.linear(s0.components, s1.components, fraction: f)
                let exact = gradient.components(at: s0.location + (s1.location - s0.location) * f)
                worst = max(worst, OKLab(approx).distance(to: OKLab(exact)) * max(approx.alpha, exact.alpha))
            }
        }
        // Allow a little slack: only 3 probe points per piece are checked while subdividing.
        #expect(worst < 0.01, "\(mode) \(a) → \(b): worst \(worst)")
    }
}

@Test func approximationStopsKeepHardEdges() {
    let gradient = InterpolatedGradient.Resolved(stops: [(red, 0), (red, 0.5), (green, 0.5), (green, 1)], interpolation: .oklab)
    let stops = gradient.approximationStops()
    #expect(stops.contains { $0.location == 0.5 && $0.components == red })
    #expect(stops.contains { $0.location == 0.5 && $0.components == green })
}

// MARK: - InterpolatedGradientLayer

#if !os(watchOS)
import QuartzCore

@Test func layerFillsInApproximationStops() throws {
    let layer = InterpolatedGradientLayer()
    layer.interpolation = .oklch
    layer.gradientColors = [red.cgColor, ColorComponents(red: 0, green: 0, blue: 1).cgColor]
    let colors = try #require(layer.colors as? [CGColor])
    let locations = try #require(layer.locations).map(\.doubleValue)
    #expect(colors.count == locations.count)
    #expect(colors.count > 2)
    #expect(locations.first == 0 && locations.last == 1)
    #expect(locations == locations.sorted())
}

@Test func layerPresentationCopyKeepsSettings() {
    let layer = InterpolatedGradientLayer()
    layer.interpolation = .oklab
    layer.gradientLocations = [0, 0.3]
    layer.gradientColors = [red.cgColor, green.cgColor]
    let copy = InterpolatedGradientLayer(layer: layer)
    #expect(copy.interpolation == .oklab)
    #expect(copy.gradientLocations == [0, 0.3])
    #expect(copy.gradientColors.count == 2)
}
#endif

// MARK: - Easing

private let allEasings: [GradientEasing] = [
    .linear, .ease, .easeIn, .easeOut, .easeInOut, .cubicBezier(x1: 0.7, y1: 0, x2: 0.3, y2: 1),
]

@Test(arguments: allEasings)
func easingHitsEndpointsAndIsMonotonic(_ easing: GradientEasing) {
    #expect(abs(easing.apply(0)) < 1e-9)
    #expect(abs(easing.apply(1) - 1) < 1e-9)
    var previous = 0.0
    for i in 1...200 {
        let value = easing.apply(Double(i) / 200)
        #expect(value >= previous - 1e-12)
        previous = value
    }
}

@Test func easingShapes() {
    #expect(GradientEasing.linear.apply(0.3) == 0.3)
    #expect(GradientEasing.easeIn.apply(0.5) < 0.5)
    #expect(GradientEasing.easeOut.apply(0.5) > 0.5)
    #expect(abs(GradientEasing.easeInOut.apply(0.5) - 0.5) < 1e-6)
    // A Bézier with control points on the diagonal is the identity.
    #expect(abs(GradientEasing.cubicBezier(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75).apply(0.37) - 0.37) < 1e-6)
    // Known value from the CSS `ease-in` curve.
    #expect(abs(GradientEasing.easeIn.apply(0.5) - 0.3153) < 1e-3)
}

@Test func easingClampsOvershoot() {
    let back = GradientEasing.cubicBezier(x1: 0.3, y1: -0.6, x2: 0.7, y2: 1.6)
    for i in 0...100 {
        #expect((0...1).contains(back.apply(Double(i) / 100)))
    }
}

@Test func easingAppliesPerSegment() {
    let blue = ColorComponents(red: 0, green: 0, blue: 1)
    let gradient = InterpolatedGradient.Resolved(stops: [(red, 0), (green, 0.5), (blue, 1)], interpolation: .oklab, easing: .easeIn)
    let expected = ColorComponents.oklab(green, blue, fraction: GradientEasing.easeIn.apply(0.5))
    #expect(isClose(gradient.components(at: 0.75), expected))
    #expect(isClose(gradient.components(at: 0.5), green))
}

@Test(arguments: allEasings)
func approximationStopsTrackEasing(_ easing: GradientEasing) {
    let gradient = InterpolatedGradient.Resolved(
        stops: [(red, 0), (ColorComponents(red: 0, green: 0, blue: 1), 1)], interpolation: .oklab, easing: easing
    )
    let stops = gradient.approximationStops()
    var worst = 0.0
    for (s0, s1) in zip(stops, stops.dropFirst()) {
        for f in stride(from: 0.1, to: 1, by: 0.1) {
            let approx = ColorComponents.linear(s0.components, s1.components, fraction: f)
            worst = max(worst, OKLab(approx).distance(to: OKLab(gradient.components(at: s0.location + (s1.location - s0.location) * f))))
        }
    }
    #expect(worst < 0.01)
}

// MARK: - Fades

@Test(arguments: [GradientInterpolation.sRGB, .pythagorean, .oklab, .oklch])
func fadeKeepsColourAndEasesAlpha(_ mode: GradientInterpolation) {
    let colour = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6)
    let gradient = InterpolatedGradient.fade(colour, interpolation: mode).resolved(in: EnvironmentValues())
    for location in [0.0, 0.2, 0.5, 0.8, 1.0] {
        let sample = gradient.components(at: location)
        #expect(abs(sample.alpha - (1 - GradientEasing.easeInOut.apply(location))) < 1e-6)
        if location < 1 {
            #expect(isClose(ColorComponents(red: sample.red, green: sample.green, blue: sample.blue), ColorComponents(red: 0.2, green: 0.4, blue: 0.6)), "\(mode) at \(location)")
        }
    }
}

@Test func fadeIntoEndColour() {
    let gradient = InterpolatedGradient.fade(.white, to: .black, easing: .linear).resolved(in: EnvironmentValues())
    #expect(isClose(gradient.components(at: 1), ColorComponents(red: 0, green: 0, blue: 0)))
    #expect(gradient.interpolation == .oklab)
}

// MARK: - InterpolatedGradientView

#if canImport(UIKit) && !os(watchOS)
import UIKit

private struct TestColourTrait: UITraitDefinition {
    static let defaultValue = false
}

private let traitColour = UIColor { $0[TestColourTrait.self] ? .red : .blue }

@MainActor @Test func viewFadeEndsTransparent() throws {
    let view = InterpolatedGradientView(fading: .red)
    #expect(view.colors.count == 2)
    #expect(view.easing == .easeInOut)
    #expect(view.interpolation == .oklab)
    #expect(view.startPoint == CGPoint(x: 0.5, y: 1) && view.endPoint == CGPoint(x: 0.5, y: 0))
    let plain = InterpolatedGradientView()
    #expect(plain.startPoint == CGPoint(x: 0.5, y: 0) && plain.endPoint == CGPoint(x: 0.5, y: 1))
    let colors = try #require(view.gradientLayer.colors as? [CGColor])
    #expect(colors.first?.alpha == 1)
    #expect(colors.last?.alpha == 0)
}

@MainActor @Test func viewReResolvesCustomColourTraits() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let view = InterpolatedGradientView(colors: [traitColour, traitColour], frame: window.bounds)
    view.colorTraits += [TestColourTrait.self]
    window.addSubview(view)
    window.isHidden = false
    func firstColour() throws -> ColorComponents {
        let first = try #require((view.gradientLayer.colors as? [CGColor])?.first)
        return try #require(ColorComponents(first))
    }
    #expect(isClose(try firstColour(), ColorComponents(red: 0, green: 0, blue: 1)))

    view.traitOverrides[TestColourTrait.self] = true
    view.layoutIfNeeded()
    #expect(isClose(try firstColour(), ColorComponents(red: 1, green: 0, blue: 0)))
}
#endif
