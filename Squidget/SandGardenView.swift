import SwiftUI
import CoreHaptics

// MARK: - Data Model

struct SandStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint] = []
    var tinePositions: [CGPoint] = []
}

// MARK: - Main View

struct SandGardenView: View {
    @State private var strokes: [SandStroke] = []
    @State private var activeStroke: SandStroke? = nil
    @State private var hapticEngine: CHHapticEngine?
    @State private var showClearFlash = false

    // Rake config
    let tineCount = 5
    let tineSpacing: CGFloat = 22
    let handleLength: CGFloat = 90

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
                    drawRakeHandle(in: &context, stroke: active)
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
                let finger = value.location
                activeStroke?.points.append(finger)

                // Compute constrained tine position
                if let count = activeStroke?.tinePositions.count, count > 0 {
                    let oldTine = activeStroke!.tinePositions[count - 1]
                    let dx = oldTine.x - finger.x
                    let dy = oldTine.y - finger.y
                    let dist = sqrt(dx * dx + dy * dy)

                    let newTine: CGPoint
                    if dist > 0.001 {
                        // Project old tine onto circle of radius handleLength around finger
                        newTine = CGPoint(
                            x: finger.x + (dx / dist) * handleLength,
                            y: finger.y + (dy / dist) * handleLength
                        )
                    } else {
                        // Finger is on old tine — fall back to direction-based placement
                        let pts = activeStroke!.points
                        let prev = pts[pts.count - 2]
                        let cur = pts[pts.count - 1]
                        let fdx = cur.x - prev.x
                        let fdy = cur.y - prev.y
                        let flen = sqrt(fdx * fdx + fdy * fdy)
                        if flen > 0.001 {
                            newTine = CGPoint(
                                x: finger.x - (fdx / flen) * handleLength,
                                y: finger.y - (fdy / flen) * handleLength
                            )
                        } else {
                            newTine = oldTine
                        }
                    }
                    activeStroke?.tinePositions.append(newTine)

                    // Fix first tine position retroactively on second point
                    if count == 1 {
                        let p0 = activeStroke!.points[0]
                        let p1 = activeStroke!.points[1]
                        let fdx = p1.x - p0.x
                        let fdy = p1.y - p0.y
                        let flen = sqrt(fdx * fdx + fdy * fdy)
                        if flen > 0.001 {
                            activeStroke?.tinePositions[0] = CGPoint(
                                x: p0.x - (fdx / flen) * handleLength,
                                y: p0.y - (fdy / flen) * handleLength
                            )
                        }
                    }
                } else {
                    // First point — place tine at finger (will be corrected when second point arrives)
                    activeStroke?.tinePositions.append(finger)
                }

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
        guard stroke.points.count > 1, stroke.tinePositions.count == stroke.points.count else { return }

        let totalWidth = CGFloat(tineCount - 1) * tineSpacing

        for i in 0..<tineCount {
            let offset = CGFloat(i) * tineSpacing - totalWidth / 2

            var path = Path()
            var isFirst = true

            for idx in 0..<stroke.tinePositions.count {
                let finger = stroke.points[idx]
                let tine = stroke.tinePositions[idx]

                // Perpendicular derived from finger→tine vector
                let dx = tine.x - finger.x
                let dy = tine.y - finger.y
                let len = sqrt(dx * dx + dy * dy)

                let perpX: CGFloat
                let perpY: CGFloat
                if len > 0.001 {
                    let ndx = dx / len
                    let ndy = dy / len
                    perpX = -ndy
                    perpY = ndx
                } else {
                    let (_, perp) = smoothedDirection(for: stroke.points, at: idx)
                    perpX = perp.x
                    perpY = perp.y
                }

                let offsetPoint = CGPoint(
                    x: tine.x + perpX * offset,
                    y: tine.y + perpY * offset
                )

                if isFirst {
                    path.move(to: offsetPoint)
                    isFirst = false
                } else {
                    path.addLine(to: offsetPoint)
                }
            }

            // Layer 1 (outer): wide, low opacity — soft fade edges
            context.stroke(
                path,
                with: .color(Color(red: 0.45, green: 0.37, blue: 0.22).opacity(0.18)),
                style: StrokeStyle(lineWidth: 8.0, lineCap: .round, lineJoin: .round)
            )

            // Layer 2 (mid): medium width, medium opacity — transition
            context.stroke(
                path,
                with: .color(Color(red: 0.42, green: 0.34, blue: 0.20).opacity(0.35)),
                style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round)
            )

            // Layer 3 (center): narrow, high opacity — dark center groove
            context.stroke(
                path,
                with: .color(Color(red: 0.35, green: 0.28, blue: 0.15).opacity(0.6)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    func drawRakeHandle(in context: inout GraphicsContext, stroke: SandStroke) {
        guard stroke.points.count >= 2, stroke.tinePositions.count == stroke.points.count else { return }

        let tip = stroke.points.last!
        let handleEnd = stroke.tinePositions.last!

        // Direction and perpendicular from finger→tine
        let dx = handleEnd.x - tip.x
        let dy = handleEnd.y - tip.y
        let len = sqrt(dx * dx + dy * dy)

        let dirX: CGFloat
        let dirY: CGFloat
        let perpX: CGFloat
        let perpY: CGFloat
        if len > 0.001 {
            dirX = dx / len
            dirY = dy / len
            perpX = -dirY
            perpY = dirX
        } else {
            let lastIdx = stroke.points.count - 1
            let (dir, perp) = smoothedDirection(for: stroke.points, at: lastIdx)
            dirX = -dir.x
            dirY = -dir.y
            perpX = perp.x
            perpY = perp.y
        }

        let tineLength: CGFloat = 20
        let rakeColor = Color(red: 0.85, green: 0.18, blue: 0.15)
        let rakeOutline = Color(red: 0.65, green: 0.12, blue: 0.10)
        let totalWidth = CGFloat(tineCount - 1) * tineSpacing

        // Handle: from finger (tip) to handleEnd (tine center)
        var handlePath = Path()
        handlePath.move(to: tip)
        handlePath.addLine(to: handleEnd)

        context.stroke(handlePath, with: .color(rakeOutline), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        context.stroke(handlePath, with: .color(rakeColor), style: StrokeStyle(lineWidth: 6, lineCap: .round))

        // Tine bar: perpendicular line at handleEnd
        let barLeft = CGPoint(
            x: handleEnd.x + perpX * totalWidth / 2 + perpX * 4,
            y: handleEnd.y + perpY * totalWidth / 2 + perpY * 4
        )
        let barRight = CGPoint(
            x: handleEnd.x - perpX * totalWidth / 2 - perpX * 4,
            y: handleEnd.y - perpY * totalWidth / 2 - perpY * 4
        )

        var barPath = Path()
        barPath.move(to: barLeft)
        barPath.addLine(to: barRight)

        context.stroke(barPath, with: .color(rakeOutline), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        context.stroke(barPath, with: .color(rakeColor), style: StrokeStyle(lineWidth: 6, lineCap: .round))

        // Tines: from bar extending toward finger by tineLength
        for i in 0..<tineCount {
            let offset = CGFloat(i) * tineSpacing - totalWidth / 2
            let tineStart = CGPoint(
                x: handleEnd.x + perpX * offset,
                y: handleEnd.y + perpY * offset
            )
            let tineEnd = CGPoint(
                x: tineStart.x - dirX * tineLength,
                y: tineStart.y - dirY * tineLength
            )

            var tinePath = Path()
            tinePath.move(to: tineStart)
            tinePath.addLine(to: tineEnd)

            context.stroke(tinePath, with: .color(rakeOutline), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            context.stroke(tinePath, with: .color(rakeColor), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
    }

    func smoothedDirection(for points: [CGPoint], at idx: Int, windowSize: Int = 10) -> (dir: CGPoint, perp: CGPoint) {
        let start = max(0, idx - windowSize)
        let end = min(points.count - 1, idx + windowSize)

        guard end > start else {
            return (dir: CGPoint(x: 1, y: 0), perp: CGPoint(x: 0, y: 1))
        }

        var sumDx: CGFloat = 0
        var sumDy: CGFloat = 0

        for i in start..<end {
            sumDx += points[i + 1].x - points[i].x
            sumDy += points[i + 1].y - points[i].y
        }

        let len = sqrt(sumDx * sumDx + sumDy * sumDy)
        guard len > 0 else {
            return (dir: CGPoint(x: 1, y: 0), perp: CGPoint(x: 0, y: 1))
        }

        let dirX = sumDx / len
        let dirY = sumDy / len
        return (dir: CGPoint(x: dirX, y: dirY), perp: CGPoint(x: -dirY, y: dirX))
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
