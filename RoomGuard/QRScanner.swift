import SwiftUI
import AVFoundation

struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        controller.onError = onError
        return controller
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private let capture = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "RoomGuard.QR")
    private var preview: AVCaptureVideoPreviewLayer?
    private var completed = false
    private var stopped = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                if granted { self.configure() }
                else { self.onError?("Allow camera access in iPhone Settings to scan, or paste the pairing text instead.") }
            }
        }
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera), capture.canAddInput(input) else {
            onError?("Camera unavailable. You can paste the pairing text instead."); return
        }
        capture.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard capture.canAddOutput(output) else { onError?("QR scanning is unavailable."); return }
        capture.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: capture)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
        view.setNeedsLayout()
        captureQueue.async { [capture] in capture.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func stop() {
        stopped = true
        captureQueue.async { [capture] in if capture.isRunning { capture.stopRunning() } }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !completed, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        completed = true
        stop()
        onCode?(code)
    }
}
