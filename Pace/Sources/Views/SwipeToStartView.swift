import SwiftUI

/// Slide-to-start control: drag the runner knob all the way right to trigger `action`.
/// The runner's stride is driven by the drag offset, so it runs forward as you swipe
/// and backward as it springs home on an incomplete swipe.
struct SwipeToStartView: View {
    var title: String = "SWIPE TO RUN"
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var completed = false

    private let height: CGFloat = 68
    private let inset: CGFloat = 6
    /// Points of travel per full stride cycle (two footstrikes).
    private let strideLength: CGFloat = 70
    private let restPhase: CGFloat = 1.1

    var body: some View {
        GeometryReader { geo in
            let knob = height - inset * 2
            let maxOffset = max(geo.size.width - knob - inset * 2, 1)
            let progress = min(offset / maxOffset, 1)
            // Start mid-stride so the resting knob already reads as a runner.
            let phase = restPhase + offset / strideLength * 2 * .pi

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.text.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))

                Capsule()
                    .fill(Theme.accent.opacity(0.25 + 0.75 * progress))
                    .frame(width: knob + inset * 2 + offset)

                HStack(spacing: 10) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .tracking(1.5)
                    Image(systemName: "chevron.right.2")
                        .font(.headline.weight(.black))
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isEnabled && !isDragging)
                }
                .foregroundStyle(Theme.text.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.leading, knob)
                .opacity(1 - Double(progress) * 1.6)

                ZStack {
                    Circle().fill(Theme.accent)
                    RunnerFigure(phase: phase)
                        .stroke(Theme.onAccent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .frame(width: knob * 0.62, height: knob * 0.62)
                }
                .frame(width: knob, height: knob)
                .shadow(color: Theme.accent.opacity(isDragging ? 0.6 : 0.25), radius: isDragging ? 14 : 6)
                .scaleEffect(isDragging ? 1.06 : 1)
                .offset(x: inset + offset)
                .gesture(dragGesture(maxOffset: maxOffset))
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: Int(phase / .pi))
            .sensoryFeedback(.success, trigger: completed) { _, new in new }
        }
        .frame(height: height)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled && !completed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start run")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled { action() } }
    }

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                offset = min(max(value.translation.width, 0), maxOffset)
            }
            .onEnded { value in
                isDragging = false
                let projected = value.predictedEndTranslation.width
                if offset >= maxOffset * 0.92 || (offset > maxOffset * 0.6 && projected >= maxOffset) {
                    complete(maxOffset: maxOffset)
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { offset = 0 }
                }
            }
    }

    private func complete(maxOffset: CGFloat) {
        withAnimation(.easeOut(duration: 0.18)) { offset = maxOffset }
        completed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action()
            // Reset once the run sheet has covered the control.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                offset = 0
                completed = false
            }
        }
    }
}

/// Stick-figure runner facing right, posed by `phase` (radians through the stride cycle).
/// Drawn in a 24×24 unit space and scaled to the rect. Animatable so springs re-pose the limbs.
struct RunnerFigure: Shape {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let bob = -abs(sin(phase)) * 0.9
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + (y + bob) * s)
        }
        /// Point `length` away from `from`, at `angle` from straight down (positive = forward).
        func limb(_ from: CGPoint, _ angle: CGFloat, _ length: CGFloat) -> CGPoint {
            CGPoint(x: from.x + sin(angle) * length * s, y: from.y + cos(angle) * length * s)
        }
        let deg = CGFloat.pi / 180

        let hip = pt(11.5, 12.5)
        let shoulder = pt(13, 7)
        let headCenter = pt(14.6, 3.6)

        var path = Path()
        path.addEllipse(in: CGRect(x: headCenter.x - 1.1 * s, y: headCenter.y - 1.1 * s, width: 2.2 * s, height: 2.2 * s))
        path.move(to: shoulder)
        path.addLine(to: hip)

        for side in [CGFloat(0), .pi] {
            let p = phase + side
            // Legs: thigh swings ±38°; knee folds during the forward (recovery) swing.
            let thigh = 38 * deg * sin(p)
            let kneeFlex = (12 + 78 * max(0, cos(p))) * deg
            let knee = limb(hip, thigh, 5.2)
            let foot = limb(knee, thigh - kneeFlex, 5)
            path.move(to: hip)
            path.addLine(to: knee)
            path.addLine(to: foot)

            // Arms swing opposite to the same-side leg, elbows bent ~90°.
            let upperArm = -42 * deg * sin(p)
            let elbow = limb(shoulder, upperArm, 3.6)
            let hand = limb(elbow, upperArm + 95 * deg, 3.2)
            path.move(to: shoulder)
            path.addLine(to: elbow)
            path.addLine(to: hand)
        }
        return path
    }
}

#Preview {
    SwipeToStartView { }
        .padding(24)
        .background(Theme.backgroundTop)
}
