import SwiftUI

struct FixedTargetOvalOverlay: View {
    let imageSize: CGSize          // still here if you need later, but not used for sizing
    let screenSize: CGSize         // Screen size
    let irisDistanceRatio: Float?  // nil or the ratio value
    let faceManager: FaceManager   // kept in case you use it later

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            let ovalWidthScreen  = w * 0.70
            let ovalHeightScreen = ovalWidthScreen * 1.20

            let centerX = w / 2.0
            let centerY = h / 2.0

            let rect = CGRect(
                x: centerX - ovalWidthScreen / 2,
                y: centerY - ovalHeightScreen / 2,
                width: ovalWidthScreen,
                height: ovalHeightScreen
            )

            // ✅ No control-flow, just a Bool expression
            let ratio = irisDistanceRatio ?? 0
            let isAccepted = (0.95 ... 1.05).contains(ratio)

            let strokeColor = isAccepted ? Color.green : Color.gray.opacity(0.8)

            Path { path in
                path.addEllipse(in: rect)
            }
            .stroke(
                strokeColor,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .animation(.easeInOut(duration: 0.3), value: isAccepted)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(false)

    }
}
