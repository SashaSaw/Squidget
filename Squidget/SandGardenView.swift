import SwiftUI
import CoreHaptics

// MARK: - Data Model

struct SandStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint] = []
}

// MARK: - Main View

struct SandGardenView: View {
    @State private var strokes: [SandStroke] = []
    @State private var activeStroke: SandStroke? = nil
    @State private var hapticEngine: CHHapticEngine?
    @State private var showClearFlash = false

    // Rake config
    let tineCount = 5
    let tineSpacing: CGFloat = 10

    var body: some View {
        ZStack {
            // Sand background — layered gradients for texture
            sandBackground

            // Drawing canvas
            Canvas { context, _ in
                for stroke in strokes {
                    drawRake(in: &context, stroke: stroke)
                }
                if let active = activeStroke {
                    drawRake(in: &context, stroke: active)
                }
            }
            .gesture(dragGesture)

            // UI overlay
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: clearSand) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.5, green: 0.42, blue: 0.28))
                            .padding(16)
                            .background(
                                Circle()
                                    .fill(Color(red: 0.92, green: 0.86, blue: 0.72).opacity(0.8))
                            )
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: prepareHaptics)
    }

    // MARK: - Sand Background

    var sandBackground: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.81, blue: 0.64),
                            Color(red: 0.82, green: 0.74, blue: 0.56)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle grain overlay using a canvas of dots
            Canvas { context, size in
                var rng = SeededRandom(seed: 42)
                for _ in 0..<800 {
                    let x = CGFloat(rng.next()) * size.width
                    let y = CGFloat(rng.next()) * size.height
                    let r = CGFloat(rng.next()) * 1.5 + 0.5
                    let opacity = Double(rng.next()) * 0.12 + 0.04
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(Color(red: 0.55, green: 0.45, blue: 0.28).opacity(opacity))
                    )
                }
            }
        }
    }

    // MARK: - Drag Gesture

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeStroke == nil {
                    activeStroke = SandStroke()
                    lightHaptic()
                }
                activeStroke?.points.append(value.location)
                // Play a gentle tick every ~20pts of movement
                if let count = activeStroke?.points.count, count % 6 == 0 {
                    scratchHaptic()
                }
            }
            .onEnded { _ in
                if let stroke = activeStroke {
                    strokes.append(stroke)
                }
                activeStroke = nil
                endStrokeHaptic()
            }
    }

    // MARK: - Drawing

    func drawRake(in context: inout GraphicsContext, stroke: SandStroke) {
        guard stroke.points.count > 1 else { return }

        let totalWidth = CGFloat(tineCount - 1) * tineSpacing

        for i in 0..<tineCount {
            let offset = CGFloat(i) * tineSpacing - totalWidth / 2

            var path = Path()
            var isFirst = true

            for idx in 0..<stroke.points.count {
                let point = stroke.points[idx]
                let perp = perpendicular(for: stroke.points, at: idx)
                let offsetPoint = CGPoint(
                    x: point.x + perp.x * offset,
                    y: point.y + perp.y * offset
                )

                if isFirst {
                    path.move(to: offsetPoint)
                    isFirst = false
                } else {
                    path.addLine(to: offsetPoint)
                }
            }

            // Shadow line (slightly darker, offset)
            var shadowPath = path
            context.stroke(
                path,
                with: .color(Color(red: 0.45, green: 0.37, blue: 0.22).opacity(0.45)),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )

            // Highlight line (lighter top edge)
            context.stroke(
                path,
                with: .color(Color(red: 0.95, green: 0.90, blue: 0.76).opacity(0.35)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
            )
        }
    }

    func perpendicular(for points: [CGPoint], at idx: Int) -> CGPoint {
        let dx: CGFloat
        let dy: CGFloat

        if idx < points.count - 1 {
            dx = points[idx + 1].x - points[idx].x
            dy = points[idx + 1].y - points[idx].y
        } else if idx > 0 {
            dx = points[idx].x - points[idx - 1].x
            dy = points[idx].y - points[idx - 1].y
        } else {
            return CGPoint(x: 0, y: 1)
        }

        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return CGPoint(x: 0, y: 1) }
        return CGPoint(x: -dy / len, y: dx / len)
    }

    // MARK: - Actions

    func clearSand() {
        withAnimation(.easeInOut(duration: 0.3)) {
            strokes.removeAll()
            activeStroke = nil
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Haptics

    func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            hapticEngine?.resetHandler = {
                try? self.hapticEngine?.start()
            }
        } catch {}
    }

    func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4)
    }

    func scratchHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else {
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        do {
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.25)
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [sharpness, intensity],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    func endStrokeHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
    }
}

// MARK: - Seeded RNG (for deterministic sand grain)

struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let value = UInt32(state >> 33)
        return Float(value) / Float(UInt32.max)
    }
}
