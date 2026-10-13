
# GradientKit

[![CI](https://github.com/TomCarey/GradientKit/actions/workflows/ci.yml/badge.svg)](https://github.com/TomCarey/GradientKit/actions/workflows/ci.yml)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FTomCarey%2FGradientKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/TomCarey/GradientKit)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FTomCarey%2FGradientKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/TomCarey/GradientKit)

Gradients for SwiftUI, UIKit and Core Graphics that blend colours better than a straight line through sRGB.

A standard sRGB gradient blends gamma-encoded values, so the middle of a gradient between two saturated colours goes dark and muddy (red → green passes through brown). GradientKit lets you choose how colours blend between stops:

| Interpolation | What it does | Good for |
|---|---|---|
| `.oklab` *(default)* | Blend in the [OKLab](https://bottosson.github.io/posts/oklab/) perceptual colour space | Even, smooth lightness; fades to white, black or transparency |
| `.oklch` | Blend lightness, chroma and hue in OKLCH, going round the hue wheel | Vivid gradients that stay saturated |
| `.pythagorean` | Root-mean-square blend, `√((1−t)·a² + t·b²)`. A cheap approximation of blending real light | Bright transitions between saturated colours |
| `.sRGB` | Straight blend of gamma-encoded sRGB (CSS `in srgb`, `CGGradient`) | Matching legacy gradients |

Each mode can be combined with an [easing curve](#easing) and drawn as a [SwiftUI shape style](#swiftui), a [Quartz shading](#core-graphics), or a [UIKit view or `CAGradientLayer`](#uikit).

### Defaults

GradientKit picks defaults so the shortest call usually looks right:

- **Interpolation: `.oklab`.** It has even lightness for any pair of colours and never swings through unrelated hues. Reach for `.oklch` when a gradient between distant hues should stay vivid.
- **Easing: `.linear`** for gradients and **`.easeInOut`** for [fades](#fades). Easing applies to every segment, so on a multi-stop gradient it would linger on each stop; on a two-colour fade it hides the edge where the fade begins.
- **Direction:** `InterpolatedGradientView` runs top to bottom, like `CAGradientLayer`. Fades default to a scrim, solid along the bottom edge and clear at the top.

## Requirements

iOS 17, macOS 14, tvOS 17, watchOS 10 or visionOS 1, with Swift 6.

## Installation

Add the package in Xcode (**File ▸ Add Package Dependencies…**) or in `Package.swift`:

<!-- x-release-please-start-version -->
```swift
dependencies: [
    .package(url: "https://github.com/TomCarey/GradientKit.git", from: "0.2.0"),
],
targets: [
    .target(name: "MyApp", dependencies: ["GradientKit"]),
]
```
<!-- x-release-please-end -->

## SwiftUI

Use the gradients anywhere SwiftUI accepts a `ShapeStyle`:

```swift
import GradientKit
import SwiftUI

struct Banner: View {
    var body: some View {
        VStack {
            // OKLab blending by default
            Rectangle()
                .fill(.interpolatedLinear(colors: [.red, .green], startPoint: .leading, endPoint: .trailing))

            // Choose the interpolation and easing
            Rectangle()
                .fill(.interpolatedLinear(
                    colors: [.blue, .yellow],
                    interpolation: .oklch,
                    easing: .easeInOut,
                    startPoint: .top, endPoint: .bottom
                ))

            Circle()
                .fill(.interpolatedRadial(colors: [.white, .indigo], interpolation: .oklab, startRadius: 0, endRadius: 100))

            Circle()
                .fill(.interpolatedAngular(colors: [.red, .red], interpolation: .oklch(.increasing)))
        }
    }
}
```

For explicit stop locations, build an `InterpolatedGradient` and pass it in:

```swift
let sunset = InterpolatedGradient(
    stops: [
        .init(color: .indigo, location: 0),
        .init(color: .pink, location: 0.6),
        .init(color: .orange, location: 1),
    ],
    interpolation: .oklch,
    easing: .easeOut
)

Rectangle().fill(.interpolatedLinear(sunset, startPoint: .top, endPoint: .bottom))
```

You can also start from an existing SwiftUI gradient with `InterpolatedGradient(Gradient(colors: [.red, .blue]), interpolation: .oklab)`.

## Interpolation

### OKLCH hue direction

OKLCH blends hue as an angle, so you can choose which way round the colour wheel a gradient travels. The options match CSS:

```swift
.oklch                    // same as .oklch(.shorter), the shortest arc (the CSS default)
.oklch(.longer)           // the long way round
.oklch(.increasing)       // always increasing hue, e.g. a full rainbow from red to red
.oklch(.decreasing)       // always decreasing hue
```

If one end is grey, white or black, it takes the other end's hue, so a fade to white doesn't swing through unrelated colours.

<img width="327" height="267" alt="Screenshot 2026-10-14 at 10 28 32 AM" src="https://github.com/user-attachments/assets/ad2e9011-ecf7-415d-ad49-7096e76d4620" />


### Gamut mapping

OKLab and OKLCH can produce colours that an sRGB display can't show. Rather than clamping each channel, which shifts hue and leaves creases, GradientKit uses the [CSS Color 4 gamut-mapping algorithm](https://www.w3.org/TR/css-color-4/#gamut-mapping). It keeps lightness and hue and reduces chroma (saturation) until the colour fits. The lower-level functions also offer plain clipping:

```swift
let vividGreen = OKLCH(lightness: 0.7, chroma: 0.35, hue: 145) // outside sRGB
vividGreen.components                    // gamut mapped (default)
vividGreen.components(mapping: .clip)    // per-channel clamp
```

<img width="414" height="420" alt="Gamut Mapping" src="https://github.com/user-attachments/assets/c1fd534b-5295-4bdf-bfde-3cb75430f29b" />

### Transparency

Pythagorean, OKLab and OKLCH premultiply by alpha, so a fade to a transparent colour keeps its hue instead of greying out. `.sRGB` doesn't, to match `CGGradient`, so fade to the same colour at zero opacity rather than `.clear` (or use [`fade`](#fades), which does that for you):

```swift
Rectangle().fill(.interpolatedLinear(colors: [.orange, .orange.opacity(0)], startPoint: .leading, endPoint: .trailing))
```

## Easing

Easing controls *how quickly* each segment moves between its two colours. It doesn't change which colours the gradient passes through. It applies separately to every segment between adjacent stops, so stop colours stay exactly where you placed them.

```swift
.linear        // constant speed (default)
.ease          // CSS ease: quick start, long soft finish
.easeIn        // lingers on the first colour
.easeOut       // lingers on the second colour
.easeInOut     // lingers on both
.cubicBezier(x1: 0.7, y1: 0, x2: 0.3, y2: 1) // custom, as in CSS cubic-bezier()
```

Curves that overshoot ("back" easing) are clamped, so colours never extrapolate past a stop.

<img width="437" height="260" alt="Easing" src="https://github.com/user-attachments/assets/51e0ed6f-0860-4026-a1c6-1ede57adc41f" />

## Fades

The most common gradient in an app is a scrim: a solid colour fading to transparent over an image or the end of some text. `fade` builds one, easing in and out by default. A linear fade starts and stops abruptly, which leaves a visible edge where it meets the solid colour.

```swift
// Solid along the bottom edge, clear at the top
Rectangle().fill(.interpolatedFade(.background))

// Solid at the bottom, clear from the middle up
Rectangle().fill(.interpolatedFade(.background, endPoint: .center))

// Fade into another colour instead of transparency
Rectangle().fill(.interpolatedFade(.indigo, to: .black.opacity(0.5), startPoint: .bottom, endPoint: .top))

// As an InterpolatedGradient, for radial or angular fades
Circle().fill(.interpolatedRadial(.fade(.white), startRadius: 0, endRadius: 80))
```

The end colours extend beyond the start and end points. To hold the solid colour or the transparency over part of a shape, move the points in, rather than repeating stops.


`InterpolatedShading` builds a Quartz `CGShading` whose `CGFunction` computes the exact colour for every sample, following Apple's [Quartz 2D shading guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_shadings/dq_shadings.html):

```swift
let gradient = InterpolatedGradient.Resolved(
    stops: [
        (ColorComponents(red: 0, green: 0, blue: 1), 0),
        (ColorComponents(red: 1, green: 1, blue: 0), 1),
    ],
    interpolation: .oklch
)

if let shading = InterpolatedShading.axial(gradient, start: .zero, end: CGPoint(x: 300, y: 0)) {
    context.drawShading(shading)
}
```

`InterpolatedShading.radial(_:startCenter:startRadius:endCenter:endRadius:)` draws radial shadings. In SwiftUI, `InterpolatedShadingView` wraps the same drawing in a `Canvas`:

```swift
InterpolatedShadingView(colors: [.red, .blue], interpolation: .oklch(.longer), kind: .axial(start: .leading, end: .trailing))

// Radii are fractions of half the view's shorter side.
InterpolatedShadingView(colors: [.white, .black], interpolation: .oklab, kind: .radial(center: .center, startRadius: 0, endRadius: 1))
```

## UIKit

`InterpolatedGradientView` is a `UIView` backed by a `CAGradientLayer`. It resolves dynamic colours such as `.systemBlue` against its trait collection and updates them when dark mode or contrast changes:

```swift
let header = InterpolatedGradientView(
    colors: [.systemIndigo, .systemPink],
    interpolation: .oklch,
    easing: .easeInOut
)
header.startPoint = CGPoint(x: 0, y: 0)
header.endPoint = CGPoint(x: 1, y: 1)

let spotlight = InterpolatedGradientView(colors: [.white, .black])
spotlight.type = .radial
spotlight.startPoint = CGPoint(x: 0.5, y: 0.5) // centre
spotlight.endPoint = CGPoint(x: 1, y: 1)       // sets the radii
```

`type` can be `.axial`, `.radial` or `.conic`. `startPoint` and `endPoint` use unit coordinates and mean the same as on `CAGradientLayer`, including running top to bottom by default.

For a [fade](#fades), the colour sits at `startPoint` and the transparency at `endPoint`. By default that's a scrim along the bottom edge:

```swift
// Solid along the left fifth, fading out to the right
let edge = InterpolatedGradientView(fading: .systemBackground)
edge.startPoint = CGPoint(x: 0.2, y: 0.5)
edge.endPoint = CGPoint(x: 1, y: 0.5)
```

Colours are re-resolved when the system traits that affect colour appearance change. If your dynamic colours also read custom traits, add them to `colorTraits`:

```swift
header.colorTraits += [PresentationModeTrait.self]
```

To work with layers directly, including on macOS, use `InterpolatedGradientLayer`. Set `gradientColors` and `gradientLocations`, not `colors` and `locations`; the layer fills those in itself:

```swift
let layer = InterpolatedGradientLayer()
layer.gradientColors = [UIColor.systemTeal.cgColor, UIColor.systemPurple.cgColor]
layer.gradientLocations = [0.2, 1]
layer.interpolation = .pythagorean
layer.easing = .easeOut
```

An eased layer also makes a softer mask for fading out the edges of scrolling content:

```swift
let mask = InterpolatedGradientLayer()
mask.gradientColors = [UIColor.clear, .white, .white, .clear].map(\.cgColor)
mask.gradientLocations = [0, 0.05, 0.85, 1]
mask.easing = .easeInOut
textContainer.layer.mask = mask
```

## Sampling colours directly

`ColorComponents`, `OKLab` and `OKLCH` give you the colour maths without a gradient:

```swift
let red = ColorComponents(red: 1, green: 0, blue: 0)
let blue = ColorComponents(red: 0, green: 0, blue: 1)

let mid = ColorComponents.interpolate(red, blue, fraction: 0.5, using: .oklch(.longer))
let swiftUIColor = mid.color
let cgColor = mid.cgColor

let lch = OKLCH(mid)          // lightness, chroma, hue
let distance = OKLab(red).distance(to: OKLab(blue))   // ΔE OK colour difference
```

You can sample a resolved gradient at any location:

```swift
let resolved = sunset.resolved(in: environment) // SwiftUI EnvironmentValues
let colour = resolved.components(at: 0.3)
```

## Accuracy notes

- **Adaptive stops.** SwiftUI gradients and `CAGradientLayer` only blend straight between stops, so GradientKit adds extra stops where the exact curve needs them, typically 15–75 per gradient. It keeps the error below 0.002 ΔE OK, where about 0.02 is just noticeable. Adjust this with `InterpolatedGradient(..., tolerance:)` or `InterpolatedGradientLayer.tolerance`. `InterpolatedShading` and `InterpolatedShadingView` compute every colour exactly.
- **SwiftUI's default gradients are already perceptual.** On current OS versions SwiftUI's `LinearGradient` blends in its `.perceptual` colour space, which renders almost identically to `.oklab`. Use `.sRGB` to reproduce the older plain blend.
- **`CAGradientLayer` shifts the most saturated colours.** Core Animation converts gradient colours into its own internal colour space, so even a flat pure sRGB blue renders as roughly (4, 50, 255). Expect errors up to about 0.04 ΔE OK next to pure primaries in `InterpolatedGradientView` and `InterpolatedGradientLayer`. That's subtle, but it can show beside an exact rendering. Use `InterpolatedShading` when exact colour matters more than redraw cost.

## Previews

`Sources/GradientKit/Previews.swift` and `InterpolatedGradientView.swift` include Xcode previews comparing every interpolation mode, OKLCH hue directions, gamut mapping, fades to clear, white and black, easing curves and the UIKit view. Open `Package.swift` in Xcode and select any of those files to see them.

## Tests

```bash
swift test
```

## License

GradientKit is available under the MIT license. See [LICENSE](LICENSE).
