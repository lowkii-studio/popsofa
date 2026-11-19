import SwiftUI
import AppKit
import Speech
import AVFoundation

// MARK: - Spracheingabe (Deutsch)

@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var partial = ""

    /// Wird mit dem fertig erkannten Text aufgerufen.
    var onFinal: ((String) -> Void)?

    // Diktat in der Sprache des Profils (pt-PT, en-US …)
    private var recognizer: SFSpeechRecognizer? { SFSpeechRecognizer(locale: Locale(identifier: TMDB.language)) }
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceToken = 0

    func toggle() {
        listening ? stop() : start()
    }

    func start() {
        guard !listening else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.partial = tr("Spracherkennung nicht erlaubt (Systemeinstellungen › Datenschutz & Sicherheit)")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        if granted {
                            self.begin()
                        } else {
                            self.partial = tr("Mikrofon nicht erlaubt (Systemeinstellungen › Datenschutz & Sicherheit)")
                        }
                    }
                }
            }
        }
    }

    private func begin() {
        guard let rec = recognizer, rec.isAvailable else {
            partial = tr("Spracherkennung momentan nicht verfügbar")
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            partial = tr("Mikrofon konnte nicht gestartet werden")
            return
        }

        partial = ""
        listening = true
        armSilenceTimer()

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.task != nil else { return }
                if let r = result {
                    self.partial = r.bestTranscription.formattedString
                    self.armSilenceTimer()
                    if r.isFinal { self.finish() }
                }
                if error != nil { self.finish() }
            }
        }
    }

    /// Nach ca. 2 Sekunden Stille automatisch beenden.
    private func armSilenceTimer() {
        silenceToken += 1
        let token = silenceToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.listening, token == self.silenceToken else { return }
            self.stop()
        }
    }

    func stop() {
        guard listening else { return }
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // Das finale Ergebnis kommt danach über den Callback; Notfall-Timeout:
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.finish()
        }
    }

    private func finish() {
        guard task != nil || request != nil else { return }
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        task = nil
        request = nil
        listening = false
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        partial = ""
        if !text.isEmpty { onFinal?(text) }
    }
}

// MARK: - Tastenbelegung

struct Key: Identifiable {
    enum Kind: Equatable {
        case char(String)
        case shift, backspace, space, enter, mic, close
        case cursor(Int)            // Textcursor ←/→ (Korrektur mitten im Text)
    }
    let id = UUID()
    let label: String
    let kind: Kind
    var symbol: String? = nil
    var width: CGFloat = 58
}

private func chars(_ s: String) -> [Key] {
    s.map { Key(label: String($0), kind: .char(String($0))) }
}

// MARK: - Bildschirmtastatur (steuert die vorderste App per Tastatur-Events)

@MainActor
final class KeyboardController: ObservableObject {
    static let shared = KeyboardController()

    @Published private(set) var visible = false
    @Published var row = 1
    @Published var col = 0
    @Published private(set) var shift = false

    let dictation = Dictation()
    private var panel: NSPanel?

    static let rows: [[Key]] = [
        chars("1234567890") + [Key(label: "⌫", kind: .backspace, width: 92)],
        chars("qwertzuiopü"),
        chars("asdfghjklöä"),
        [Key(label: "⇧", kind: .shift, width: 92)] + chars("yxcvbnm,.?"),
        [Key(label: "", kind: .mic, symbol: "mic.fill", width: 92),
         Key(label: "@", kind: .char("@")),
         Key(label: "", kind: .cursor(-1), symbol: "arrowtriangle.left.fill", width: 70),
         Key(label: "Leertaste", kind: .space, width: 200),
         Key(label: "", kind: .cursor(1), symbol: "arrowtriangle.right.fill", width: 70),
         Key(label: ".com", kind: .char(".com"), width: 92),
         Key(label: "↵", kind: .enter, width: 92),
         Key(label: "✕", kind: .close, width: 92)],
    ]

    private init() {
        dictation.onFinal = { text in
            Input.type(text)
        }
    }

    // MARK: Anzeigen / Verstecken

    func toggle() { visible ? hide() : show() }

    func show() {
        guard Input.hasAccessibility(prompt: true) else {
            HUD.shared.show(tr("Bedienungshilfen-Zugriff erlauben, damit die Tastatur tippen kann"),
                            symbol: "exclamationmark.triangle.fill", duration: 4)
            return
        }
        visible = true
        row = 1
        col = 0
        shift = false

        let host = NSHostingView(rootView: KeyboardView(kb: self, dictation: dictation))
        host.setFrameSize(host.fittingSize)

        let p = panel ?? KeyboardPanel(contentRect: host.frame,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        p.contentView = host
        p.setContentSize(host.frame.size)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.frame.midX - host.frame.width / 2,
                                     y: screen.frame.minY + 40))
        }
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        guard visible else { return }
        visible = false
        if dictation.listening { dictation.stop() }
        panel?.orderOut(nil)
    }

    // MARK: Navigation und Tippen

    func move(dRow: Int, dCol: Int) {
        let rows = Self.rows
        if dRow != 0 {
            let newRow = min(max(row + dRow, 0), rows.count - 1)
            guard newRow != row else { return }
            let oldMax = max(rows[row].count - 1, 1)
            let newMax = rows[newRow].count - 1
            col = Int((Double(col) / Double(oldMax) * Double(newMax)).rounded())
            row = newRow
        }
        if dCol != 0 {
            col = min(max(col + dCol, 0), rows[row].count - 1)
        }
    }

    func toggleShift() { shift.toggle() }

    func press() {
        let key = Self.rows[row][col]
        switch key.kind {
        case .char(let s):
            Input.type(shift ? s.uppercased() : s)
            shift = false
        case .shift: shift.toggle()
        case .backspace: Input.key(Input.Code.delete)
        case .space: Input.key(Input.Code.space)
        case .enter: Input.key(Input.Code.returnKey)
        case .mic: dictation.toggle()
        case .close: hide()
        case .cursor(let d): Input.key(d < 0 ? Input.Code.leftArrow : Input.Code.rightArrow)
        }
    }
}

/// Panel, das nie den Fokus übernimmt – die Eingabe landet im Feld der vorderen App.
final class KeyboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Darstellung

struct KeyboardView: View {
    @ObservedObject var kb: KeyboardController
    @ObservedObject var dictation: Dictation

    var body: some View {
        VStack(spacing: 10) {
            if dictation.listening || !dictation.partial.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: dictation.listening ? "mic.fill" : "mic")
                        .foregroundColor(dictation.listening ? .red : .white.opacity(0.6))
                    Text(dictation.partial.isEmpty ? tr("Ich höre zu …") : dictation.partial)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.ui(20, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
            }

            ForEach(0..<KeyboardController.rows.count, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(0..<KeyboardController.rows[r].count, id: \.self) { c in
                        KeyCap(key: KeyboardController.rows[r][c],
                               focused: kb.row == r && kb.col == c,
                               shift: kb.shift,
                               listening: dictation.listening)
                            .onTapGesture {
                                kb.row = r
                                kb.col = c
                                kb.press()
                            }
                    }
                }
            }

            Text(tr("A Taste   ·   LT RT Cursor ◀ ▶   ·   X ⌫   ·   Y Leerzeichen   ·   LB ⇧   ·   RB ↵   ·   R3 Sprache   ·   B Schließen"))
                .font(.ui(15, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .padding(.top, 4)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: "#15151B").opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(14)
        .frame(width: 880 * Metrics.s)
    }
}

struct KeyCap: View {
    let key: Key
    let focused: Bool
    let shift: Bool
    let listening: Bool

    private var isActiveToggle: Bool {
        (key.kind == .shift && shift) || (key.kind == .mic && listening)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background)
            if let symbol = key.symbol {
                Image(systemName: symbol).font(.ui(22, weight: .semibold))
            } else {
                Text(display)
                    .font(.ui(key.label.count > 2 ? 18 : 26, weight: .medium))
            }
        }
        .foregroundColor(focused ? .black : .white)
        .frame(width: key.width, height: 54)
        .scaleEffect(focused ? 1.12 : 1)
        .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 10, y: 6)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
        .zIndex(focused ? 1 : 0)
    }

    private var display: String {
        if case .char(let s) = key.kind { return shift ? s.uppercased() : s }
        return tr(key.label)
    }

    private var background: Color {
        if focused { return .white }
        if isActiveToggle { return key.kind == .mic ? Color.red.opacity(0.85) : Color.blue.opacity(0.8) }
        return Color.white.opacity(0.13)
    }
}
