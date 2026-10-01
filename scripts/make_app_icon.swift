// Renders the app icon: swift scripts/make_app_icon.swift Pace/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// Pink palette's alternate icon: swift scripts/make_app_icon.swift Pace/Resources/Assets.xcassets/AppIconPink.appiconset/AppIcon.png --pink
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments[1]
let pink = CommandLine.arguments.contains("--pink")
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

// Background: the app's black → deep teal (plum for pink) gradient (CG origin is bottom-left).
let bottom = pink ? rgb(0.20, 0.03, 0.13) : rgb(0.06, 0.11, 0.13)
let bg = CGGradient(colorsSpace: cs, colors: [bottom, rgb(0, 0, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
// Accent glow from the top, like the run screen.
let glowColor: (CGFloat, CGFloat, CGFloat) = pink ? (1.0, 0.42, 0.72) : (0, 0.85, 0.76)
let glow = CGGradient(colorsSpace: cs, colors: [rgb(glowColor.0, glowColor.1, glowColor.2, 0.30), rgb(glowColor.0, glowColor.1, glowColor.2, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 1024), startRadius: 0, endCenter: CGPoint(x: 512, y: 1024), endRadius: 760, options: [])

let mint = pink ? rgb(1.0, 0.42, 0.72) : rgb(0, 0.855, 0.765)
let amber = rgb(1.0, 0.72, 0.28)

// Rows from top (one continuous run) to bottom (short runs between walks):
// the program in one picture. Each number is a run's relative length; walks
// between runs are round amber dots.
let rows: [[CGFloat]] = [
    [1],
    [5, 4],
    [1, 1, 1],
    [1, 1, 1, 1],
]
let left: CGFloat = 152, width: CGFloat = 720
let rowHeight: CGFloat = 80, rowGap: CGFloat = 60, segGap: CGFloat = 18
let total = CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowGap
var top = (CGFloat(size) + total) / 2

func capsule(_ rect: CGRect, _ color: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
}

for row in rows {
    let walks = CGFloat(row.count - 1)
    let usable = width - walks * rowHeight - segGap * walks * 2
    let units = row.reduce(0, +)
    var x = left
    for (index, part) in row.enumerated() {
        let w = usable * part / units
        capsule(CGRect(x: x, y: top - rowHeight, width: w, height: rowHeight), mint)
        x += w
        if index < row.count - 1 {
            x += segGap
            capsule(CGRect(x: x, y: top - rowHeight, width: rowHeight, height: rowHeight), amber)
            x += rowHeight + segGap
        }
    }
    top -= rowHeight + rowGap
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
