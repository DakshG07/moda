import AppKit
import SwiftUI

@MainActor
final class HUDViewModel: ObservableObject {
  @Published var percentage = 0
  @Published var accessibilityLabel = "Volume"
}

struct VolumeHUDView: View {
  static let designScale: CGFloat = 1.0 / 3.0
  static let size = CGSize(width: 157 * designScale, height: 562 * designScale)
  static let cornerRadius: CGFloat = 78.5 * designScale

  @ObservedObject var model: HUDViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      let fillHeight = VolumeMath.fillHeight(
        volumePercent: model.percentage,
        totalHeight: geometry.size.height
      )

      ZStack(alignment: .bottom) {
        GlassEffectBackground()

        Rectangle()
          .fill(Color.white)
          .frame(height: fillHeight)
          .animation(fillAnimation, value: model.percentage)

        number(color: .white)

        number(color: .black)
          .mask { fillMask(height: fillHeight) }
      }
      .clipShape(Capsule())
      .overlay {
        Capsule()
          .strokeBorder(
            LinearGradient(
              colors: [
                Color.white.opacity(0.34),
                Color.white.opacity(0.12),
                Color.white.opacity(0.22),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 0.5
          )
      }
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(model.accessibilityLabel)
    .accessibilityValue("\(model.percentage) percent")
  }

  private var fillAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.22, bounce: 0.04)
  }

  private func fillMask(height: CGFloat) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      Rectangle().frame(height: height)
    }
    .animation(fillAnimation, value: model.percentage)
  }

  private func number(color: Color) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      Text(model.percentage, format: .number)
        .font(
          .system(
            size: 50 * Self.designScale,
            weight: .bold,
            design: .default
          )
        )
        .monospacedDigit()
        .contentTransition(
          reduceMotion ? .opacity : .numericText(value: Double(model.percentage))
        )
        .animation(fillAnimation, value: model.percentage)
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12 * Self.designScale)
        .padding(.bottom, 41 * Self.designScale)
    }
  }
}

private struct GlassEffectBackground: NSViewRepresentable {
  func makeNSView(context: Context) -> NSGlassEffectView {
    let view = NSGlassEffectView()
    view.style = .clear
    view.cornerRadius = VolumeHUDView.cornerRadius
    view.tintColor = NSColor(white: 0.08, alpha: 0.20)
    view.clipsToBounds = true
    return view
  }

  func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
}
