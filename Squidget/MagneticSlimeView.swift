import SwiftUI
import CoreHaptics
import Combine

// MARK: - Main View

struct MagneticSlimeView: View {

    // Number of blobs in the slime chain
    private let blobCount = 9

    // Each blob lerps toward the one ahead of it.
    // springFactors[0] is the fastest (closest to finger).
    private let springFactors: [CGFloat] = [0.38, 0.30, 0.24, 0.19, 0.15, 0.12, 0.10, 0.08, 0.06]

    @State private var targetPosition: CGPoint = .zero
    @State private var positions: [CGPoint] = []
    @State private var isDragging = false
    @State private var hapticEngine: CHHapticEngine?

    // 60fps update loop
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                // Draw blobs back-to-front (largest/trailing first)
                ForEach(Array((0..<blobCount).reversed()), id: \.self) { i in
                    blobView(index: i)
                }

                // Idle hint
                if !isDragging {
                    Text("drag me")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.top, geo.size.height * 0.72)
                }
            }
            .ignoresSafeArea()
            .onAppear {
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                targetPosition = center
                positions = Array(repeating: center, count: blobCount)
                prepareHaptics()
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        targetPosition = value.location
                        if !isDragging {
                            isDragging = true
                            pulseHaptic()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        releaseHaptic()
                    }
            )
            .onReceive(timer) { _ in
                guard !positions.isEmpty else { return }
                // Chain: each blob follows the previous at a spring rate
                positions[0] = lerp(positions[0], targetPosition, t: springFactors[0])
                for i in 1..<blobCount {
                    positions[i] = lerp(positions[i], positions[i - 1], t: springFactors[i])
                }
            }
        }
    }

    // MARK: - Blob View

    @ViewBuilder
    func blobView(index i: Int) -> some View {
        if !positions.isEmpty {
            let progress = CGFloat(i) / CGFloat(blobCount - 1) // 0 = lead, 1 = tail
            let size = blobSize(for: i)

            Ellipse()
                .fill(slimeGradient(progress: progress))
                .frame(width: size.width, height: size.height)
                .blur(radius: blurRadius(for: i))
                .position(positions[i])
                .opacity(blobOpacity(for: i))
        }
    }

    // MARK: - Styling Helpers

    var background: some View {
        ZStack {
            Color(red: 0.04, green: 0.07, blue: 0.06)

            // Subtle radial glow in the center
            RadialGradient(
                colors: [
                    Color(red: 0.1, green: 0.3, blue: 0.15).opacity(0.4),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }

    func slimeGradient(progress: CGFloat) -> LinearGradient {
        // Lead blob is bright lime-green; tail fades to dark teal
        let topColor = Color(
            red: 0.25 + 0.1 * (1 - progress),
            green: 0.90 - 0.30 * progress,
            blue: 0.30 + 0.10 * progress
        )
        let bottomColor = Color(
            red: 0.08,
            green: 0.55 - 0.20 * progress,
            blue: 0.25
        )
        return LinearGradient(
            colors: [topColor, bottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func blobSize(for i: Int) -> CGSize {
        // Lead blob is roughly 90pt wide; tail blobs shrink
        let baseW: CGFloat = 92
        let baseH: CGFloat = 86
        let shrink = CGFloat(i) * 7.5
        return CGSize(width: max(baseW - shrink, 18), height: max(baseH - shrink, 16))
    }

    func blurRadius(for i: Int) -> CGFloat {
        // Slight blur increases toward the tail for a soft merging look
        return 3.0 + CGFloat(i) * 0.8
    }

    func blobOpacity(for i: Int) -> Double {
        // Tail blobs are slightly more transparent
        return max(0.55, 1.0 - Double(i) * 0.04)
    }

    // MARK: - Math

    func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t
        )
    }

    // MARK: - Haptics

    func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            hapticEngine?.resetHandler = { try? self.hapticEngine?.start() }
        } catch {}
    }

    func pulseHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
            return
        }
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    func releaseHaptic() {
        // Soft thud when you let go and the slime settles
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
            return
        }
        do {
            let events: [CHHapticEvent] = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                    ],
                    relativeTime: 0.12
                )
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {}
    }
}
