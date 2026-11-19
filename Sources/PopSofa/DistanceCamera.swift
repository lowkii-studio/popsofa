import AVFoundation
import Vision

/// Misst einmalig (~3 s) den Abstand zum Gesicht vor der Kamera. Es werden keine Bilder gespeichert.
final class DistanceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // ponytail: feste Werte statt Kalibrierung – Augenabstand ~63 mm (±6 %), Gesichtsbreite ~15 cm (±15 %),
    // Mac-Kameras ~65–80° Bildwinkel. Genauer nur mit Kalibrierung (Maßband) pro Kamera.
    static let eyeDistanceMM: CGFloat = 63
    static let faceWidthMM: CGFloat = 150
    static var hfovDegrees: CGFloat = 70

    /// Abstand in mm aus dem Anteil einer bekannten Breite an der Bildbreite.
    static func distance(fraction f: CGFloat, realMM: CGFloat) -> CGFloat {
        realMM / (2 * tan(hfovDegrees * .pi / 360) * f)
    }

    /// Gibt es eine Kamera? (Zugeklapptes MacBook ohne externe Kamera: nein.)
    static var available: Bool { AVCaptureDevice.default(for: .video) != nil }

    static func selfTest() {
        precondition(abs(distance(fraction: 0.1, realMM: faceWidthMM) - 1071) < 5)
        // 63 mm Augenabstand bei 2,5 m füllen ≈ 1,8 % der Bildbreite
        let f = eyeDistanceMM / (2 * tan(hfovDegrees * .pi / 360) * 2500)
        precondition(abs(distance(fraction: f, realMM: eyeDistanceMM) - 2500) < 1)
    }

    private static var current: DistanceCamera?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "distance.camera")
    private var byEyes: [CGFloat] = [], byFace: [CGFloat] = []
    private var lastFace: Bool?
    private var done: ((CGFloat?) -> Void)?
    private var onFace: ((Bool) -> Void)?

    /// `onFace` meldet laufend (auf dem Main-Thread), ob gerade ein Gesicht zu sehen ist.
    @MainActor static func measure(seconds: Double = 3, onFace: ((Bool) -> Void)? = nil, _ done: @escaping (CGFloat?) -> Void) {
        // Läuft schon eine Messung: deren Ergebnis an den neuen Aufrufer geben.
        if let cam = current { cam.done = done; cam.onFace = onFace; return }
        AVCaptureDevice.requestAccess(for: .video) { ok in
            Task { @MainActor in
                guard ok, let cam = DistanceCamera(done) else { done(nil); return }
                cam.onFace = onFace
                current = cam
                cam.start(seconds)
            }
        }
    }

    private init?(_ done: @escaping (CGFloat?) -> Void) {
        guard let dev = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: dev) else { return nil }
        super.init()
        self.done = done
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(out) else { return nil }
        session.addInput(input)
        session.addOutput(out)
    }

    private func start(_ seconds: Double) {
        queue.async { [self] in
            session.startRunning()
            queue.asyncAfter(deadline: .now() + seconds) { [self] in finish() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sample) else { return }
        let w = CGFloat(CVPixelBufferGetWidth(px)), h = CGFloat(CVPixelBufferGetHeight(px))
        let req = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: px, options: [:]).perform([req])
        // Größtes Gesicht = wer am nächsten sitzt
        let face = req.results?.max { $0.boundingBox.width < $1.boundingBox.width }
        if let f = face, f.boundingBox.width > 0.01 {
            let box = f.boundingBox
            byFace.append(Self.distance(fraction: box.width, realMM: Self.faceWidthMM))
            if let l = f.landmarks?.leftPupil?.normalizedPoints.first, let r = f.landmarks?.rightPupil?.normalizedPoints.first {
                let dx = (l.x - r.x) * box.width * w, dy = (l.y - r.y) * box.height * h
                let frac = hypot(dx, dy) / w
                if frac > 0.003 { byEyes.append(Self.distance(fraction: frac, realMM: Self.eyeDistanceMM)) }
            }
        }
        let seen = face != nil
        if seen != lastFace, let cb = onFace {
            lastFace = seen
            DispatchQueue.main.async { cb(seen) }
        }
    }

    private func finish() {
        session.stopRunning()
        // Augen sind genauer; nur wenn sie kaum erkannt wurden, zählt die Gesichtsbreite.
        let list = (byEyes.count >= 3 ? byEyes : byFace).sorted()
        let mm = list.isEmpty ? nil : list[list.count / 2]
        let cb = done
        Task { @MainActor in
            DistanceCamera.current = nil
            cb?(mm.map { min(max($0, 300), 6000) })
        }
    }
}
