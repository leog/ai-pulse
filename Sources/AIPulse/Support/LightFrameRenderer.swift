import AppKit
import SwiftUI
import AIPulseKit

/// `AIPulse --render-lights <directory>` — renders the light strip's
/// animation as deterministic PNG frame sequences, one directory per signal
/// state, plus a full state-cycle with and without captions. The strip's
/// animation is a pure function of time, so frames are sampled exactly and
/// loops close seamlessly. `Scripts/make-gifs.sh` assembles the GIFs.
@MainActor
enum LightFrameRenderer {
    /// Native loop length per animated state, from LightStripView's math:
    /// working = comet cycle (12 positions × 0.12 s), attention = one
    /// breath (2π/3 s), failure = blink cycle, idle = one aurora drift
    /// (sin(t/3) → 6π s).
    private struct StateSpec {
        let signal: LightSignal
        let name: String
        let period: TimeInterval?
        let frames: Int
        let title: String
        let note: String
    }

    private static let specs: [StateSpec] = [
        .init(signal: .working, name: "working", period: 1.44, frames: 36,
              title: "Working", note: "A cyan comet streaks while an agent runs"),
        .init(signal: .attention, name: "attention", period: 2 * .pi / 3, frames: 42,
              title: "Needs you", note: "Breathes orange when an agent waits for input or approval"),
        .init(signal: .failure, name: "failure", period: 1.2, frames: 24,
              title: "Failed", note: "Double-blinks red when a session breaks"),
        .init(signal: .idle, name: "idle", period: 6 * .pi, frames: 47,
              title: "Idle", note: "A slow aurora drifts while sessions sit quiet"),
        .init(signal: .success, name: "success", period: nil, frames: 1,
              title: "Finished", note: "All eight settle to solid green"),
        .init(signal: .off, name: "off", period: nil, frames: 1,
              title: "Off", note: "Dark when nothing is connected"),
    ]

    /// Captioned (social) tiles get a dark canvas: sharing platforms
    /// flatten or discard alpha unpredictably, and the white captions need
    /// a guaranteed dark ground. README tiles stay transparent (APNG) so
    /// they sit on GitHub's own theme background.
    private static let canvas = Color(red: 0.051, green: 0.055, blue: 0.09)

    static func runIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--render-lights"),
              CommandLine.arguments.count > index + 1 else { return false }
        let root = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)

        for spec in specs {
            let directory = root.appendingPathComponent("states/\(spec.name)")
            for frame in 0..<spec.frames {
                let time = (spec.period ?? 0) * Double(frame) / Double(spec.frames)
                write(
                    tile(signal: spec.signal, time: time, caption: nil, size: .init(width: 190, height: 64)),
                    to: directory.appendingPathComponent(String(format: "f%03d.png", frame))
                )
            }
        }

        // Full cycle at a uniform 20 fps: hero (strip only) and social
        // (captioned). Animated states get two native loops so motion
        // registers; static states hold briefly.
        for (name, caption, size) in [
            ("cycle", false, CGSize(width: 190, height: 64)),
            ("social", true, CGSize(width: 480, height: 200)),
        ] {
            var frame = 0
            let directory = root.appendingPathComponent(name)
            for spec in specs {
                let seconds = spec.period.map { min($0, 4.2) * (($0 * 2) <= 4.2 ? 2 : 1) } ?? 1.5
                for i in 0..<Int(seconds * 20) {
                    write(
                        tile(
                            signal: spec.signal,
                            time: Double(i) / 20,
                            caption: caption ? (spec.title, spec.note) : nil,
                            size: size
                        ),
                        to: directory.appendingPathComponent(String(format: "f%04d.png", frame))
                    )
                    frame += 1
                }
            }
        }
        print("Rendered light frames into \(root.path)")
        return true
    }

    private static func tile(
        signal: LightSignal,
        time: TimeInterval,
        caption: (title: String, note: String)?,
        size: CGSize
    ) -> some View {
        ZStack {
            if let caption {
                canvas
                VStack(spacing: 18) {
                    LightStripView(signal: signal, frozenTime: time)
                        .scaleEffect(2)
                        .frame(height: 60)
                    VStack(spacing: 6) {
                        Text(caption.title)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(caption.note)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            } else {
                LightStripView(signal: signal, frozenTime: time)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private static func write(_ view: some View, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
