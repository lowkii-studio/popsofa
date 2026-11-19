import SwiftUI

// MARK: - Seiten statt Systemdialoge
// Profil, Dienst, Schlüssel und iPhone koppeln als ganzseitige Ansicht im Stil der App –
// komplett mit dem Controller bedienbar: ↑↓ wählt Felder, A auf einem Feld öffnet die Bildschirmtastatur.

struct FormFieldSpec {
    let key: String
    let label: String
    let placeholder: String
    var mono = false
}

struct FormButton {
    let title: String
    var primary = false
    var destructive = false
    let action: @MainActor () -> Void
}

struct FormSpec {
    var title: String
    var step: String? = nil
    var intro: String
    var fields: [FormFieldSpec] = []
    var buttons: [FormButton]
    var note: String? = nil
}

extension AppState {
    /// Beschreibung der aktuell offenen Formular-Seite (nil bei Genres/Sehtest/keiner Seite).
    var formSpec: FormSpec? {
        switch sheet {
        case .add?:
            return FormSpec(
                title: tr("Eigenen Dienst hinzufügen"),
                intro: tr("Jede Webseite kann eine Kachel werden – sie öffnet dann im eingebauten Browser."),
                fields: [FormFieldSpec(key: "name", label: tr("Name"), placeholder: tr("z. B. Mubi")),
                         FormFieldSpec(key: "address", label: tr("Adresse"), placeholder: tr("z. B. mubi.com"))],
                buttons: [FormButton(title: tr("Hinzufügen"), primary: true) { self.addCustom(name: self.form["name"] ?? "", urlString: self.form["address"] ?? "") },
                          FormButton(title: tr("Abbrechen")) { self.closeSheet() }])
        case .key?:
            return FormSpec(
                title: tr("TMDB-Schlüssel"),
                intro: tr("1. Kostenloses Konto auf themoviedb.org anlegen\n2. Einstellungen › API › Schlüssel anfordern (privat)\n3. „API Read Access Token“ oder „API Key“ kopieren und hier einfügen (⌘V oder iPhone)"),
                fields: [FormFieldSpec(key: "key", label: tr("Schlüssel"), placeholder: tr("Schlüssel einfügen"), mono: true)],
                buttons: [FormButton(title: tr("Speichern"), primary: true) { self.saveKey(self.form["key"] ?? "") },
                          FormButton(title: tr("Abbrechen")) { self.closeSheet() }],
                note: tr("Wird im Schlüsselbund deines Macs gespeichert. Dein Geschmack bleibt lokal.") + "\n\n" + Attribution.tmdb)
        case .profile?:
            return profileFormSpec
        case .remote?:
            var b = [FormButton(title: remote.enabled ? tr("Fernbedienung ausschalten") : tr("Fernbedienung einschalten"),
                                primary: true) { self.remote.setEnabled(!self.remote.enabled) }]
            if !remote.devices.isEmpty {
                b.append(FormButton(title: tr("Alle Geräte abmelden"), destructive: true) {
                    self.remote.revokeAll(); self.showToast(tr("Alle Geräte abgemeldet"))
                })
            }
            b.append(FormButton(title: tr("Fertig")) { self.closeSheet() })
            return FormSpec(title: tr("iPhone koppeln"),
                            intro: tr("Dein iPhone wird im selben WLAN zu Touchpad, Tastatur und Fernbedienung – ohne App, direkt in Safari."),
                            buttons: b)
        default:
            return nil
        }
    }

    /// Bearbeitetes Profil zum aktiven machen (Dienste/Sprache/Genres gelten immer fürs aktive Profil).
    func activateEdited() {
        guard let id = editingProfile, id != activeProfileID else { return }
        switchProfile(id)
    }

    private var profileFormSpec: FormSpec {
        let editing = profiles.first { $0.id == editingProfile }
        // Neues Profil: erst nur der Name – Profilnamen bei Netflix & Co. später unter „Profil bearbeiten“.
        let fields = [FormFieldSpec(key: "name", label: tr("Dein Name in PopSofa"), placeholder: tr("z. B. Alex"))]
            + (editing == nil ? [] : StreamProfile.services(enabled: enabledIDs, all: allServices)).map {
                FormFieldSpec(key: "svc." + $0.id, label: tr("Profilname bei %@", $0.name), placeholder: tr("leer lassen, wenn gleich"))
            }
        var buttons: [FormButton]
        if let p = editing {
            // Dienste, Länder, Sprache und Genres gehören zur Person – vorher zu ihr wechseln, falls nicht aktiv.
            buttons = [FormButton(title: tr("Speichern"), primary: true) { self.saveProfileForm() },
                       FormButton(title: tr("Dienste & Länder")) { self.activateEdited(); self.saveProfileForm(then: .services); self.formFocus = 0 },
                       FormButton(title: tr("Sprache: %@", Region.languageName(p.language ?? contentLanguage))) {
                           self.activateEdited(); self.chooseLanguage()
                       },
                       FormButton(title: tr("Genres")) { self.activateEdited(); self.genreFocus = 0; self.saveProfileForm(then: .genres) },
                       FormButton(title: tr("Sehtest wiederholen")) { self.activateEdited(); self.saveProfileForm(then: .eyeTest); if self.sheet == .eyeTest { self.measureDistance(fallback: true) } }]
            if profiles.count > 1 {
                buttons.append(FormButton(title: tr("Löschen"), destructive: true) { self.deleteProfile(p.id) })
            }
            buttons.append(FormButton(title: tr("Abbrechen")) { self.closeSheet() })
        } else {
            buttons = [FormButton(title: tr("Weiter"), primary: true) { self.saveProfileForm() },
                       FormButton(title: tr("Abbrechen")) { self.closeSheet() }]
        }
        return FormSpec(
            title: editing == nil ? tr("Neues Profil") : tr("Profil bearbeiten"),
            step: editing == nil ? tr("Schritt %@ von %@", 1, 6) : nil,
            intro: editing == nil
                ? tr("Wie heißt du? Danach wählst du deine Dienste, machst einen kurzen Sehtest und wählst Genres.")
                : tr("Bei Netflix & Co. klickt PopSofa dann dein Profil an. Heißt dein Profil dort anders, trag den Namen ein."),
            fields: fields, buttons: buttons)
    }

    private func saveProfileForm(then next: Sheet? = nil) {
        let names = Dictionary(uniqueKeysWithValues: form.compactMap { k, v -> (String, String)? in
            guard k.hasPrefix("svc."), !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (String(k.dropFirst(4)), v)
        })
        saveProfile(name: form["name"] ?? "", streamNames: names, then: next)
    }

    /// Werte vorbelegen, wenn eine Formular-Seite aufgeht.
    func prepareForm() {
        form = [:]
        formFocus = 0
        editingField = nil
        if sheet == .profile, let p = profiles.first(where: { $0.id == editingProfile }) {
            form["name"] = p.name
            for (k, v) in p.streamNames { form["svc." + k] = v }
        }
        // Mit Maus/Tastatur gleich ins erste Feld; am Controller erst auf A (dann mit Bildschirmtastatur).
        if inputMode == .keyboard, let f = formSpec?.fields.first { editingField = f.key }
    }

    func closeSheet() {
        editingField = nil
        if KeyboardController.shared.visible { KeyboardController.shared.hide() }
        sheet = nil
    }

    /// ↑↓ zwischen Feldern, ←→ zwischen Knöpfen, ↑ aus dem ersten Element zu „Zurück“.
    func handleForm(_ e: PadEvent) {
        guard let spec = formSpec else { if e == .b { closeSheet() }; return }
        let nf = spec.fields.count, nb = spec.buttons.count
        if handleBack(e, close: { closeSheet() }) { return }
        formFocus = min(max(formFocus, 0), nf + nb - 1)
        let onButton = formFocus >= nf
        switch e {
        case .up:
            if formFocus == 0 || (onButton && nf == 0) { backFocus = true }
            else if onButton { formFocus = nf - 1 } else { formFocus -= 1 }
        case .down:
            if formFocus < nf - 1 { formFocus += 1 } else if !onButton { formFocus = nf }
        case .left: if onButton && formFocus > nf { formFocus -= 1 }
        case .right: if onButton && formFocus < nf + nb - 1 { formFocus += 1 }
        case .a:
            if onButton { spec.buttons[formFocus - nf].action() }
            else {
                editingField = spec.fields[formFocus].key
                KeyboardController.shared.show()
            }
        case .b: closeSheet()
        default: break
        }
    }

    /// ↵ im Feld: Tastatur zu, weiter zum nächsten Feld bzw. zum ersten Knopf.
    func fieldSubmitted(_ key: String) {
        guard let spec = formSpec, let i = spec.fields.firstIndex(where: { $0.key == key }) else { return }
        editingField = nil
        if KeyboardController.shared.visible { KeyboardController.shared.hide() }
        formFocus = i + 1
    }
}

// MARK: - Ansicht

/// Ganzseitiger Rahmen: Zurück oben links, Schritt, Überschrift, Text, Inhalt, Hinweise unten.
struct OverlayPage<Content: View>: View {
    @EnvironmentObject var state: AppState
    let title: String
    var step: String? = nil
    var intro: String? = nil
    let close: () -> Void
    var hints: [(String, String)] = []
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ink.bg.ignoresSafeArea()
            ThemedBackground().opacity(0.98).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20 * Metrics.s) {
                BackButton(focused: state.backFocus, action: close)
                VStack(alignment: .leading, spacing: 10 * Metrics.s) {
                    if let step { Text(step.uppercased()).font(.ui(15, weight: .heavy)).tracking(1).opacity(0.8) }
                    Text(title).headingFont(38).popTextShadow()
                    if let intro {
                        Text(intro).font(.read(18)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 900 * Metrics.text(18), alignment: .leading)   // ~80 Zeichen je Zeile
                    }
                }
                content()
                Spacer(minLength: 0)
                FlowLayout(spacing: 22, lineSpacing: 8, centered: false) {
                    if state.inputMode == .keyboard {
                        KeyboardHints()
                    } else {
                        ForEach(hints, id: \.1) { k, t in
                            Hint(glyph: k.count <= 2 ? .letter(k, .gray) : .symbol(k), text: t)
                        }
                    }
                }
                .font(.read(15, weight: .medium))
                .lineLimit(1)
            }
            .padding(.horizontal, Metrics.side)
            .padding(.top, 36)
            .padding(.bottom, 24)
        }
        .foregroundColor(Ink.fg)
    }
}

struct FormPage<Extra: View>: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    let spec: FormSpec
    @ViewBuilder var extra: () -> Extra
    @FocusState private var focusedKey: String?

    var body: some View {
        OverlayPage(title: spec.title, step: spec.step, intro: spec.intro, close: { state.closeSheet() },
                    hints: hints) {
            // Scrollt mit: bei großer Schrift oder vielen Feldern bleibt das gewählte Feld im Bild.
            FocusScroll(axis: .vertical, target: "f\(state.formFocus)", position: 0.45, space: "form", wheel: true) {
                VStack(alignment: .leading, spacing: 16 * Metrics.s) {
                    extra()
                    ForEach(Array(spec.fields.enumerated()), id: \.element.key) { i, f in
                        field(i, f).scrollAnchor("f\(i)", in: "form")
                    }
                    // Viele Knöpfe (Profil bearbeiten): umbrechen statt aus dem Bild laufen.
                    FlowLayout(spacing: 16 * Metrics.s, lineSpacing: 14 * Metrics.s, centered: false) {
                        ForEach(Array(spec.buttons.enumerated()), id: \.offset) { j, b in
                            button(spec.fields.count + j, b).scrollAnchor("f\(spec.fields.count + j)", in: "form")
                        }
                    }
                    .padding(.vertical, 10)
                    if let n = spec.note { Text(n).font(.read(15)).opacity(0.8) }
                    if state.sheet == .key, let logo = Attribution.logo {
                        Image(nsImage: logo).resizable().scaledToFit().frame(width: 90 * Metrics.s)
                            .padding(.top, 6).accessibilityLabel("TMDB")
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { focusedKey = state.editingField }
        .onChange(of: state.editingField) { focusedKey = $0 }
    }

    private var hints: [(String, String)] {
        let nf = spec.fields.count
        if state.backFocus { return [("A", tr("Zurück")), ("B", tr("Abbrechen"))] }
        let a = state.formFocus < nf ? tr("Bearbeiten (Tastatur)") : spec.buttons[safe: state.formFocus - nf]?.title ?? tr("Auswählen")
        return [("dpad", tr("Auswahl")), ("A", a), ("B", tr("Abbrechen"))]
    }

    private func focused(_ i: Int) -> Bool { !state.backFocus && state.formFocus == i }

    private func field(_ i: Int, _ f: FormFieldSpec) -> some View {
        let on = focused(i)
        let text = theme.bold ? Ink.bg : Ink.fg
        return VStack(alignment: .leading, spacing: 8) {
            Text(f.label).font(.read(16, weight: .semibold))
            // Eigener Platzhalter: der System-Platzhalter ist auf hellem Grund kaum lesbar.
            TextField("", text: Binding(get: { state.form[f.key] ?? "" }, set: { state.form[f.key] = $0 }))
                .background(alignment: .leading) {
                    if (state.form[f.key] ?? "").isEmpty {
                        Text(f.placeholder).foregroundColor(text.opacity(0.6)).allowsHitTesting(false)
                            .font(f.mono ? .ui(20, design: .monospaced) : .read(22, weight: .medium))
                    }
                }
                .textFieldStyle(.plain)
                .font(f.mono ? .ui(20, design: .monospaced) : .read(22, weight: .medium))
                .foregroundColor(text)
                .focused($focusedKey, equals: f.key)
                .onSubmit { state.fieldSubmitted(f.key) }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.bold ? theme.p.paper : Ink.fg.opacity(on ? 0.2 : 0.12)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(on ? (theme.bold ? theme.p.accent : Ink.fg) : (theme.bold ? Ink.bg : Ink.fg.opacity(0.25)),
                                  lineWidth: on ? 4 : 2))
                .frame(maxWidth: 760 * Metrics.s)
                .onTapGesture { state.backFocus = false; state.formFocus = i; state.editingField = f.key }
        }
        .scaleEffect(on && !Typo.calm ? 1.02 : 1, anchor: .leading)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: on)
    }

    private func button(_ i: Int, _ b: FormButton) -> some View {
        let on = focused(i)
        let fill: Color = b.destructive ? Color(hex: "#B3261E")
            : b.primary ? (theme.bold ? theme.p.accent : Ink.fg) : Ink.fg.opacity(0.14)
        let fg: Color = b.destructive ? Ink.fg : b.primary ? Ink.bg : Ink.fg
        return Button { state.backFocus = false; state.formFocus = i; b.action() } label: {
            Text(b.title).font(.read(18, weight: .bold))
                .padding(.horizontal, 26).padding(.vertical, 13)
                .foregroundColor(fg)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(theme.bold ? Ink.bg : .clear, lineWidth: 2))
                .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3)
                    .padding(-6).opacity(on ? 1 : 0))
                .scaleEffect(on && !Typo.calm ? 1.08 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
        }
        .buttonStyle(.plain)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Wählt die passende Seite für `state.sheet`.
struct SheetPage: View {
    @EnvironmentObject var state: AppState
    let sheet: Sheet

    var body: some View {
        switch sheet {
        case .genres: GenrePage()
        case .eyeTest: EyeTestPage()
        case .distance: DistancePage()
        case .services: ServicePickPage()
        case .access: AccessPage()
        case .colorTest: ColorTestPage()
        case .prism: PrismPage()
        case .remote: RemotePairPage(remote: state.remote)
        default:
            if let spec = state.formSpec { FormPage(spec: spec) { EmptyView() } }
        }
    }
}

/// „iPhone koppeln“: beobachtet den Server, damit Knöpfe und Status sofort umspringen.
struct RemotePairPage: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var remote: RemoteServer

    var body: some View {
        if let spec = state.formSpec { FormPage(spec: spec) { RemoteInfo(remote: remote) } }
    }
}
