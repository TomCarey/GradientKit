import CoreGraphics
import SwiftUI

/// Gamma-encoded sRGB components plus alpha, each in `0...1`.
///
/// sRGB values are stored roughly as the *square root* of physical light
/// intensity (gamma ≈ 2.2). Blending them linearly therefore under-represents
/// the light in the middle of a gradient, producing the familiar dark, muddy
/// band between saturated colours. Squaring each channel before blending and
/// taking the square root afterwards — the Pythagorean / root-mean-square
/// mix — approximates blending in linear light and keeps the transition bright.
public struct ColorComponents: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Converts any `CGColor` into extended sRGB. Returns `nil` if the colour
    /// cannot be converted (for example pattern colours).
    public init?(_ cgColor: CGColor) {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
            let c = converted.components, c.count >= 4
        else { return nil }
        self.init(red: Double(c[0]), green: Double(c[1]), blue: Double(c[2]), alpha: Double(c[3]))
    }

    /// Resolves a SwiftUI `Color` for the supplied environment (light/dark mode etc).
    public init(_ color: Color, in environment: EnvironmentValues) {
        let r = color.resolve(in: environment)
        self.init(red: Double(r.red), green: Double(r.green), blue: Double(r.blue), alpha: Double(r.opacity))
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Plain linear interpolation of gamma-encoded sRGB, as `CGGradient` does.
    public static func linear(_ a: ColorComponents, _ b: ColorComponents, fraction t: Double) -> ColorComponents {
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return ColorComponents(
            red: lerp(a.red, b.red),
            green: lerp(a.green, b.green),
            blue: lerp(a.blue, b.blue),
            alpha: lerp(a.alpha, b.alpha)
        )
    }

    /// Pythagorean interpolation: `sqrt((1 - t)·a² + t·b²)` per colour channel.
    ///
    /// The squared (≈ linear light) channels are premultiplied by alpha before
    /// mixing so a fade to `.clear` does not pick up the clear colour's (black)
    /// RGB. Alpha itself is a linear coverage value and is interpolated linearly.
    public static func pythagorean(_ a: ColorComponents, _ b: ColorComponents, fraction t: Double) -> ColorComponents {
        let alpha = a.alpha + (b.alpha - a.alpha) * t
        func mix(_ x: Double, _ y: Double) -> Double {
            guard alpha > 0 else { return 0 }
            // Preserve sign so extended-range (wide gamut) components survive.
            let squared = ((1 - t) * a.alpha * x * abs(x) + t * b.alpha * y * abs(y)) / alpha
            return squared < 0 ? -(-squared).squareRoot() : squared.squareRoot()
        }
        return ColorComponents(
            red: mix(a.red, b.red),
            green: mix(a.green, b.green),
            blue: mix(a.blue, b.blue),
            alpha: alpha
        )
    }
}
