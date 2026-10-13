import SwiftUI

private let pairs: [(String, [Color])] = [
    ("Red → Green", [.red, .green]),
    ("Blue → Yellow", [.blue, .yellow]),
    ("Magenta → Cyan", [Color(red: 1, green: 0, blue: 1), Color(red: 0, green: 1, blue: 1)]),
    ("Black → White", [.black, .white]),
    ("Rainbow", [.red, .orange, .yellow, .green, .blue, .purple]),
]

private let modes: [(String, GradientInterpolation)] = [
    ("sRGB", .sRGB), ("Pythagorean", .pythagorean), ("OKLab", .oklab), ("OKLCH", .oklch),
]

/// A checkerboard so transparency is visible behind a gradient.
private struct Checkerboard: View {
    var size: CGFloat = 8

    var body: some View {
        Canvas { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.white))
            for row in 0..<Int(canvasSize.height / size) + 1 {
                for column in 0..<Int(canvasSize.width / size) + 1 where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * size, y: CGFloat(row) * size, width: size, height: size)
                    context.fill(Path(rect), with: .color(.gray.opacity(0.35)))
                }
            }
        }
    }
}

private struct ComparisonRow: View {
    let title: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            labelled("sRGB") {
                Rectangle().fill(.interpolatedLinear(colors: colors, interpolation: .sRGB, startPoint: .leading, endPoint: .trailing))
            }
            labelled("Pythagorean (ShapeStyle)") {
                Rectangle().fill(.interpolatedLinear(colors: colors, interpolation: .pythagorean, startPoint: .leading, endPoint: .trailing))
            }
            labelled("Pythagorean (CGShading)") {
                InterpolatedShadingView(colors: colors, interpolation: .pythagorean, kind: .axial(start: .leading, end: .trailing))
            }
            labelled("OKLab") {
                Rectangle().fill(.interpolatedLinear(colors: colors, interpolation: .oklab, startPoint: .leading, endPoint: .trailing))
            }
            // SwiftUI's default gradient colour space is perceptual (OKLab-like) on
            // current OS versions, so this row should match the OKLab row above.
            labelled("SwiftUI default (≈ OKLab)") {
                Rectangle().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            }
            labelled("OKLCH") {
                Rectangle().fill(.interpolatedLinear(colors: colors, interpolation: .oklch, startPoint: .leading, endPoint: .trailing))
            }
        }
    }

    private func labelled(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(height: 36)
            .overlay(alignment: .leading) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.thinMaterial, in: .capsule)
                    .padding(6)
            }
            .clipShape(.rect(cornerRadius: 6))
    }
}

#Preview("Interpolation comparison") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach(pairs, id: \.0) { ComparisonRow(title: $0.0, colors: $0.1) }
        }
        .padding()
    }
}

#Preview("Radial & Angular") {
    let colors: [Color] = [.yellow, .blue]
    Grid(horizontalSpacing: 16, verticalSpacing: 16) {
        GridRow {
            Text("sRGB").font(.headline)
            Text("OKLab").font(.headline)
        }
        GridRow {
            Circle().fill(.interpolatedRadial(colors: colors, interpolation: .sRGB, startRadius: 0, endRadius: 80))
            Circle().fill(.interpolatedRadial(colors: colors, startRadius: 0, endRadius: 80))
        }
        GridRow {
            Circle().fill(.interpolatedAngular(colors: [.red, .green, .blue, .red], interpolation: .sRGB))
            Circle().fill(.interpolatedAngular(colors: [.red, .green, .blue, .red]))
        }
        GridRow {
            Text("CGShading radial (OKLab)").font(.caption).gridCellColumns(2)
        }
        GridRow {
            InterpolatedShadingView(colors: colors, kind: .radial(center: .center, startRadius: 0, endRadius: 1))
                .clipShape(.circle)
                .gridCellColumns(2)
        }
    }
    .frame(width: 340)
    .padding()
}

#Preview("Midpoint swatches") {
    let samples: [(Color, Color)] = [(.red, .green), (.blue, .yellow), (.red, .blue), (.black, .white)]
    let environment = EnvironmentValues()
    VStack(spacing: 12) {
        ForEach(Array(samples.enumerated()), id: \.offset) { _, pair in
            let a = ColorComponents(pair.0, in: environment)
            let b = ColorComponents(pair.1, in: environment)
            HStack(spacing: 0) {
                pair.0
                ColorComponents.linear(a, b, fraction: 0.5).color.overlay { Text("lerp").font(.caption) }
                ColorComponents.pythagorean(a, b, fraction: 0.5).color.overlay { Text("√").font(.caption) }
                ColorComponents.oklab(a, b, fraction: 0.5).color.overlay { Text("lab").font(.caption) }
                ColorComponents.oklch(a, b, fraction: 0.5).color.overlay { Text("lch").font(.caption) }
                pair.1
            }
            .frame(height: 44)
            .clipShape(.rect(cornerRadius: 6))
        }
    }
    .padding()
    .frame(width: 420)
}

#Preview("Fade to clear") {
    let fades: [(String, [Color])] = [
        ("Orange", [.orange, .orange.opacity(0)]),
        ("Blue", [.blue, .blue.opacity(0)]),
        ("Black", [.black, .black.opacity(0)]),
        ("White", [.white, .white.opacity(0)]),
    ]
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
        GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            ForEach(fades, id: \.0) { Text($0.0).font(.caption.weight(.semibold)) }
        }
        GridRow {
            Text("SwiftUI default").font(.caption)
            ForEach(fades, id: \.0) { _, colors in
                Rectangle()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .background(Checkerboard())
            }
        }
        .frame(height: 36)
        ForEach(modes, id: \.0) { name, mode in
            GridRow {
                Text(name).font(.caption)
                ForEach(fades, id: \.0) { _, colors in
                    Rectangle()
                        .fill(.interpolatedLinear(colors: colors, interpolation: mode, startPoint: .leading, endPoint: .trailing))
                        .background(Checkerboard())
                }
            }
            .frame(height: 36)
        }
    }
    .padding()
    .frame(width: 520)
}

#Preview("Scrims") {
    // A linear fade starts abruptly, leaving a visible edge where it meets the
    // image; an eased fade blends in. Both hold clear over the top half.
    let background = Color(red: 0.08, green: 0.1, blue: 0.13)
    let backdrop = LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    HStack(spacing: 12) {
        VStack {
            backdrop.overlay {
                LinearGradient(colors: [background.opacity(0), background.opacity(0), background], startPoint: .top, endPoint: .bottom)
            }
            Text("Linear").font(.caption)
        }
        VStack {
            backdrop.overlay {
                Rectangle().fill(.interpolatedFade(background, startPoint: .bottom, endPoint: .center))
            }
            Text(".interpolatedFade").font(.caption)
        }
    }
    .padding()
    .background(background)
    .foregroundStyle(.white)
    .frame(width: 360, height: 300)
}

#Preview("OKLCH hue directions") {
    let colors: [Color] = [.red, .blue]
    let methods: [(String, HueInterpolation)] = [
        ("shorter", .shorter), ("longer", .longer), ("increasing", .increasing), ("decreasing", .decreasing),
    ]
    VStack(alignment: .leading, spacing: 8) {
        ForEach(methods, id: \.0) { name, method in
            Text(name).font(.caption.weight(.semibold))
            InterpolatedShadingView(colors: colors, interpolation: .oklch(method), kind: .axial(start: .leading, end: .trailing))
                .frame(height: 36)
                .clipShape(.rect(cornerRadius: 6))
        }
        Text("OKLCH angular wheel").font(.caption.weight(.semibold))
        Circle()
            .fill(.interpolatedAngular(colors: [.red, .red], interpolation: .oklch(.increasing)))
            .frame(width: 160, height: 160)
            .frame(maxWidth: .infinity)
    }
    .padding()
    .frame(width: 340)
}

#Preview("Fade to white / black") {
    let fades: [(String, [Color])] = [
        ("Blue → White", [.blue, .white]),
        ("Yellow → Black", [.yellow, .black]),
        ("Black → White", [.black, .white]),
    ]
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
        GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            ForEach(fades, id: \.0) { Text($0.0).font(.caption.weight(.semibold)) }
        }
        ForEach(modes, id: \.0) { name, mode in
            GridRow {
                Text(name).font(.caption)
                ForEach(fades, id: \.0) { _, colors in
                    Rectangle().fill(.interpolatedLinear(colors: colors, interpolation: mode, startPoint: .leading, endPoint: .trailing))
                }
            }
            .frame(height: 30)
        }
    }
    .padding()
    .frame(width: 480)
}

#Preview("Gamut mapping") {
    let pairs: [(String, ColorComponents, ColorComponents, HueInterpolation)] = [
        ("Blue → Yellow", .init(red: 0, green: 0, blue: 1), .init(red: 1, green: 1, blue: 0), .shorter),
        ("Red → Blue (longer)", .init(red: 1, green: 0, blue: 0), .init(red: 0, green: 0, blue: 1), .longer),
        ("Green → Magenta", .init(red: 0, green: 1, blue: 0), .init(red: 1, green: 0, blue: 1), .shorter),
        ("Cyan → Red", .init(red: 0, green: 1, blue: 1), .init(red: 1, green: 0, blue: 0), .increasing),
    ]
    func strip(_ a: ColorComponents, _ b: ColorComponents, _ hue: HueInterpolation, _ mapping: GamutMapping) -> some View {
        let samples = 128
        let stops = (0...samples).map { i in
            let t = Double(i) / Double(samples)
            return Gradient.Stop(color: ColorComponents.oklch(a, b, fraction: t, hue: hue, mapping: mapping).color, location: t)
        }
        return Rectangle()
            .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
            .frame(height: 30)
            .clipShape(.rect(cornerRadius: 4))
    }
    return VStack(alignment: .leading, spacing: 10) {
        ForEach(pairs, id: \.0) { name, a, b, hue in
            Text(name).font(.caption.weight(.semibold))
            HStack(spacing: 6) {
                Text("clip").font(.caption2).frame(width: 64, alignment: .leading)
                strip(a, b, hue, .clip)
            }
            HStack(spacing: 6) {
                Text("gamut map").font(.caption2).frame(width: 64, alignment: .leading)
                strip(a, b, hue, .reduceChroma)
            }
        }
    }
    .padding()
    .frame(width: 420)
}

#Preview("Easing") {
    let easings: [(String, GradientEasing)] = [
        ("linear", .linear), ("ease", .ease), ("easeIn", .easeIn), ("easeOut", .easeOut), ("easeInOut", .easeInOut),
        ("bézier .7,0,.3,1", .cubicBezier(x1: 0.7, y1: 0, x2: 0.3, y2: 1)),
    ]
    let pairs: [(String, [Color], GradientInterpolation)] = [
        ("Black → White · OKLab", [.black, .white], .oklab),
        ("Blue → Yellow · OKLab", [.blue, .yellow], .oklab),
        ("Red → Green → Blue · OKLab", [.red, .green, .blue], .oklab),
    ]
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(pairs, id: \.0) { title, colors, interpolation in
                Text(title).font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(easings, id: \.0) { name, easing in
                        GridRow {
                            Text(name).font(.caption).lineLimit(1)
                            EasingCurve(easing: easing).frame(width: 30, height: 30)
                            Rectangle()
                                .fill(.interpolatedLinear(colors: colors, interpolation: interpolation, easing: easing, startPoint: .leading, endPoint: .trailing))
                                .frame(height: 30)
                                .clipShape(.rect(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .padding()
    }
    .frame(width: 440)
}

/// A small plot of an easing curve.
private struct EasingCurve: View {
    let easing: GradientEasing

    var body: some View {
        Canvas { context, size in
            let frame = Path(CGRect(origin: .zero, size: size))
            context.stroke(frame, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
            var curve = Path()
            for i in 0...40 {
                let t = Double(i) / 40
                let point = CGPoint(x: t * size.width, y: (1 - easing.apply(t)) * size.height)
                if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(.accentColor), lineWidth: 1.5)
        }
    }
}
