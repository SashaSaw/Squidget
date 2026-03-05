import SwiftUI

// MARK: - Data

struct PlayCard: Identifiable {
    let id: Int
    let colorTop: Color
    let colorBottom: Color
    let symbol: String
}

// MARK: - Card Flick View

struct CardFlickView: View {

    @State private var cards: [PlayCard] = []
    @State private var topCardOffset: CGSize = .zero
    @State private var topCardRotation: Double = 0
    @State private var isFlicking = false
    @State private var flickedCount = 0

    private let threshold: CGFloat = 90          // how far to drag before it commits
    private let velocityThreshold: CGFloat = 600 // fast flick also triggers dismiss

    var body: some View {
        ZStack {
            background

            // Empty state — resets automatically
            if cards.isEmpty {
                emptyState
            }

            // Card stack — bottom cards rendered first
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let isTop = index == cards.count - 1
                let depth  = cards.count - 1 - index // 0 = top, increases downward

                CardTileView(card: card)
                    .scaleEffect(stackScale(depth: depth))
                    .offset(y: stackOffset(depth: depth))
                    .offset(isTop ? topCardOffset : .zero)
                    .rotationEffect(.degrees(isTop ? topCardRotation : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: topCardOffset)
                    .zIndex(Double(index))
                    .gesture(isTop ? flickGesture : nil)
            }

            // Counter
            counterBadge
        }
        .ignoresSafeArea()
        .onAppear(perform: resetDeck)
    }

    // MARK: - Gestures

    var flickGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isFlicking else { return }
                topCardOffset = value.translation
                // Rotation: tilt based on horizontal drag, scaled by vertical position of drag start
                topCardRotation = Double(value.translation.width / 18)
            }
            .onEnded { value in
                guard !isFlicking else { return }

                let velocity = CGPoint(
                    x: value.predictedEndTranslation.width - value.translation.width,
                    y: value.predictedEndTranslation.height - value.translation.height
                )
                let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                let dragDist = sqrt(
                    value.translation.width * value.translation.width +
                    value.translation.height * value.translation.height
                )

                if dragDist > threshold || speed > velocityThreshold {
                    dismissTopCard(toward: value.predictedEndTranslation)
                } else {
                    snapBack()
                }
            }
    }

    // MARK: - Card Actions

    func dismissTopCard(toward translation: CGSize) {
        isFlicking = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Fly card off screen in the direction of the flick
        let scale: CGFloat = 3.5
        withAnimation(.easeIn(duration: 0.28)) {
            topCardOffset = CGSize(
                width:  translation.width  * scale,
                height: translation.height * scale
            )
            topCardRotation *= 2.5
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            cards.removeLast()
            flickedCount += 1
            topCardOffset = .zero
            topCardRotation = 0
            isFlicking = false

            // Auto-reset after last card
            if cards.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    resetDeck()
                }
            }
        }
    }

    func snapBack() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
            topCardOffset = .zero
            topCardRotation = 0
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4)
    }

    func resetDeck() {
        flickedCount = 0
        cards = CardFlickView.makeDeck()
        // Gentle haptic on reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Stack Styling

    func stackScale(depth: Int) -> CGFloat {
        // Top card = 1.0, each card below is slightly smaller
        max(1.0 - CGFloat(depth) * 0.04, 0.7)
    }

    func stackOffset(depth: Int) -> CGFloat {
        // Each card peeks up from below
        CGFloat(depth) * (-10)
    }

    // MARK: - Sub-views

    var background: some View {
        Color(red: 0.10, green: 0.10, blue: 0.13).ignoresSafeArea()
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("Reshuffling…")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    var counterBadge: some View {
        VStack {
            HStack {
                Spacer()
                Text("\(flickedCount) flicked")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .padding(.top, 60)
                    .padding(.trailing, 24)
            }
            Spacer()
        }
    }

    // MARK: - Deck Factory

    static func makeDeck() -> [PlayCard] {
        let palette: [(Color, Color, String)] = [
            (Color(red: 0.95, green: 0.35, blue: 0.35), Color(red: 0.7,  green: 0.15, blue: 0.15), "heart.fill"),
            (Color(red: 1.00, green: 0.60, blue: 0.20), Color(red: 0.75, green: 0.35, blue: 0.05), "flame.fill"),
            (Color(red: 0.95, green: 0.85, blue: 0.25), Color(red: 0.70, green: 0.60, blue: 0.05), "star.fill"),
            (Color(red: 0.30, green: 0.85, blue: 0.45), Color(red: 0.10, green: 0.55, blue: 0.25), "leaf.fill"),
            (Color(red: 0.30, green: 0.65, blue: 1.00), Color(red: 0.10, green: 0.35, blue: 0.80), "drop.fill"),
            (Color(red: 0.70, green: 0.35, blue: 1.00), Color(red: 0.45, green: 0.10, blue: 0.75), "sparkles"),
            (Color(red: 0.95, green: 0.40, blue: 0.75), Color(red: 0.70, green: 0.15, blue: 0.50), "moon.stars.fill"),
            (Color(red: 0.40, green: 0.80, blue: 0.90), Color(red: 0.10, green: 0.50, blue: 0.65), "wind"),
        ]
        return palette.enumerated().map { i, p in
            PlayCard(id: i, colorTop: p.0, colorBottom: p.1, symbol: p.2)
        }
    }
}

// MARK: - Single Card Tile

struct CardTileView: View {
    let card: PlayCard

    var body: some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [card.colorTop, card.colorBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: card.colorBottom.opacity(0.5), radius: 20, x: 0, y: 10)

            // Inner highlight
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )

            // Decorative large symbol (background)
            Image(systemName: card.symbol)
                .font(.system(size: 180, weight: .bold))
                .foregroundColor(.white.opacity(0.08))
                .offset(x: 60, y: 60)

            // Centre symbol
            Image(systemName: card.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            // Corner pips
            VStack {
                HStack {
                    cardPip
                    Spacer()
                    cardPip
                }
                Spacer()
                HStack {
                    cardPip
                    Spacer()
                    cardPip
                }
            }
            .padding(24)
        }
        .frame(width: 300, height: 420)
    }

    var cardPip: some View {
        Image(systemName: card.symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
    }
}
