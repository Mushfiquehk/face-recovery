import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

/// The oval framing guide. Consistent framing is part of the capture protocol, not decoration:
/// distance and angle change apparent under-eye shadow as much as a bad night does.
struct FramingGuide: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let oval = CGRect(
                x: size.width * 0.15,
                y: size.height * 0.16,
                width: size.width * 0.70,
                height: size.height * 0.56
            )

            ZStack {
                Ellipse()
                    .path(in: oval)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))

                Text("Fill the oval. Face the light, same spot each morning.")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .position(x: size.width / 2, y: oval.maxY + 28)
            }
        }
        .allowsHitTesting(false)
    }
}
