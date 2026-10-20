import AppKit
import SwiftUI
import CodexQuotaCore

/// Two compressed photographs share one cup geometry. Only the liquid mask and
/// the photographic meniscus move; all thirteen levels reuse the same bitmaps.
struct CoffeeCupView: View {
    let remaining: Double?
    private var level: Int? { CoffeeLevel.heightPercent(for: remaining) }
    private var steamStyle: CoffeeSteamStyle { CoffeeSteamStyle(remaining: remaining) }

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: min(proxy.size.width, proxy.size.height * 460 / 340),
                              height: min(proxy.size.height, proxy.size.width * 340 / 460))
            let height = Double(level ?? 0) / 100
            let surface = 0.707 - 0.495 * height
            let halfWidth = 0.214 - 0.060 * pow(1 - height, 4)
            let surfaceRadius = min(0.067 * (0.72 + 0.28 * height), (0.707 - surface) * 0.75)
            ZStack(alignment: .topLeading) {
                if let empty = CoffeeImages.empty, let full = CoffeeImages.full {
                    Image(nsImage: empty).resizable().interpolation(.high)
                    if let level, level > 0 {
                        Image(nsImage: full).resizable().interpolation(.high)
                            .mask(LiquidBody(surface: surface, halfWidth: halfWidth))
                        if let cap = CoffeeImages.surface {
                            Image(nsImage: cap).resizable().interpolation(.high)
                                .frame(width: size.width * halfWidth * 2,
                                       height: size.height * surfaceRadius * 2)
                                .clipShape(Ellipse())
                                .position(x: size.width * 0.4665, y: size.height * surface)
                        }
                    }
                } else {
                    // An explicit asset error is preferable to a misleading quota graphic.
                    Image(systemName: "cup.and.saucer")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundStyle(CoffeeTheme.secondary.opacity(0.3))
                        .frame(width: size.width, height: size.height)
                }
                if level == nil {
                    CoffeeTheme.background.opacity(0.65)
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(CoffeeTheme.secondary)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .mask {
                // Feather only the image boundary into the panel; cup pixels stay opaque.
                Rectangle().fill(.white)
                    .overlay(alignment: .leading) {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 15).blendMode(.destinationOut)
                    }
                    .overlay(alignment: .trailing) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 15).blendMode(.destinationOut)
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 20).blendMode(.destinationOut)
                    }
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 20).blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .overlay(alignment: .topLeading) {
                if steamStyle.isVisible, let steam = CoffeeImages.steam {
                    // Vapor rises from a broad area of the liquid, including
                    // inside the glass at lower fills, rather than a point at the rim.
                    // Keep the upper extent while extending the soft base to the surface.
                    let steamHeight = steamStyle.heightFraction + max(0, surface - 0.21)
                    Image(nsImage: steam).resizable().interpolation(.high)
                        .frame(width: size.width * steamStyle.widthFraction,
                               height: size.height * steamHeight)
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.12),
                                .init(color: .white, location: 0.68),
                                .init(color: .clear, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        }
                        .position(x: size.width * 0.4665,
                                  y: size.height * (surface - steamHeight / 2))
                        .opacity(steamStyle.opacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct LiquidBody: Shape {
    let surface: Double
    let halfWidth: Double
    func path(in rect: CGRect) -> Path {
        let cx = 0.4665
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.width * x, y: rect.height * y)
        }
        var path = Path()
        path.move(to: point(cx - halfWidth, surface))
        path.addLine(to: point(cx + halfWidth, surface))
        path.addCurve(to: point(cx + 0.145, 0.707),
                      control1: point(cx + min(halfWidth, 0.205), max(surface, 0.61)),
                      control2: point(cx + 0.177, 0.69))
        path.addQuadCurve(to: point(cx - 0.145, 0.707), control: point(cx, 0.756))
        path.addCurve(to: point(cx - halfWidth, surface),
                      control1: point(cx - 0.177, 0.69),
                      control2: point(cx - min(halfWidth, 0.205), max(surface, 0.61)))
        path.closeSubpath()
        return path
    }
}

@MainActor
private enum CoffeeImages {
    static let full = load("full")
    static let empty = load("empty")
    static let steam: NSImage? = Bundle.main.url(forResource: "steam", withExtension: "png", subdirectory: "Coffee")
        .flatMap { NSImage(contentsOf: $0) }
    static let surface: NSImage? = {
        guard let full, let cg = full.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cg.cropping(to: CGRect(x: CGFloat(cg.width) * 0.253,
                                                   y: CGFloat(cg.height) * (49.0 / 340),
                                                   width: CGFloat(cg.width) * 0.427,
                                                   height: CGFloat(cg.height) * (46.0 / 340))) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }()

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Coffee") else { return nil }
        return NSImage(contentsOf: url)
    }
}
