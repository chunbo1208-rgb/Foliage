import SwiftUI

struct FoliageLaunchView: View {
    @State private var isPresented = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.97, green: 0.95, blue: 0.88), .white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                FoliageLogoMark()
                    .fill(Color(red: 0.95, green: 0.93, blue: 0.82))
                    .padding(23)
                    .frame(width: 132, height: 132)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.23, green: 0.47, blue: 0.32), .foliageGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                    )
                    .shadow(color: .foliageGreen.opacity(0.18), radius: 24, y: 12)

                VStack(spacing: 7) {
                    Text("Foliage")
                        .font(.system(size: 38, weight: .semibold, design: .serif))
                        .tracking(-0.7)

                    Text("READ  •  MARK  •  REMEMBER")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(2.1)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(Color.foliageGreen)
            .scaleEffect(isPresented ? 1 : 0.92)
            .opacity(isPresented ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Foliage. Read, mark, remember.")
        .onAppear {
            withAnimation(.spring(duration: 0.65, bounce: 0.18)) {
                isPresented = true
            }
        }
    }
}

struct FoliageLogoMark: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()

        path.move(to: point(0.49, 0.78))
        path.addCurve(to: point(0.14, 0.65), control1: point(0.39, 0.68), control2: point(0.27, 0.64))
        path.addLine(to: point(0.14, 0.32))
        path.addCurve(to: point(0.49, 0.43), control1: point(0.30, 0.30), control2: point(0.42, 0.35))
        path.closeSubpath()

        path.move(to: point(0.51, 0.78))
        path.addCurve(to: point(0.86, 0.65), control1: point(0.61, 0.68), control2: point(0.73, 0.64))
        path.addLine(to: point(0.86, 0.32))
        path.addCurve(to: point(0.51, 0.43), control1: point(0.70, 0.30), control2: point(0.58, 0.35))
        path.closeSubpath()

        path.move(to: point(0.50, 0.47))
        path.addCurve(to: point(0.67, 0.14), control1: point(0.53, 0.34), control2: point(0.59, 0.22))
        path.addCurve(to: point(0.82, 0.10), control1: point(0.72, 0.10), control2: point(0.77, 0.09))
        path.addCurve(to: point(0.75, 0.28), control1: point(0.83, 0.18), control2: point(0.80, 0.24))
        path.addCurve(to: point(0.57, 0.31), control1: point(0.69, 0.32), control2: point(0.62, 0.31))
        path.addCurve(to: point(0.50, 0.47), control1: point(0.54, 0.36), control2: point(0.52, 0.41))
        path.closeSubpath()

        return path
    }
}
