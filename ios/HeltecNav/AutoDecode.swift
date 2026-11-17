import Foundation

/// Una lettura possibile del testo (percorso di metodi + risultato + quanto somiglia all'italiano).
struct Lettura: Identifiable, Hashable {
    let id = UUID()
    let metodo: String          // es. "Base64 → Cesare −3"
    let testo: String
    let punteggio: Double       // più alto = più probabile
    var parole: [String] = []
    var passi: [ChainStep] = [] // per ricostruire la catena nella scheda Catena
}

/// Decifrazione automatica a più strati: prova ogni metodo sensato, poi riprova sui risultati più promettenti
/// (fino a 3 passaggi), e ordina tutto per somiglianza all'italiano.
enum AutoDecode {
    static let vocabolario: Set<String> = Set("""
    CHE NON PER UNA DEL DELLA DELLE DEI DAL DALLA NEL NELLA CON SUL SULLA COME PIU SONO HANNO ERA ANCHE QUESTO QUESTA \
    QUELLO ALLA ALLE AGLI SUO SUA LORO TRA FRA DOVE QUANDO OGNI TUTTI TUTTO DOPO PRIMA SOLO ORA OGGI DOMANI SERA NOTTE \
    ORE PUNTO CODICE CHIAVE PORTA CASA TORRE CASTELLO CHIESA PONTE STRADA NORD SUD EST OVEST SINISTRA DESTRA SOTTO \
    SOPRA DENTRO FUORI METRI PASSI ORO RE MIDA FERRO STAGNO PIOMBO PIETRA FILOSOFALE ALCHIMIA ALCHIMISTA OBELISCO OBELISCUS \
    VALDRAGO NEROBIANCO MORETTI BALSIMELLI VANE ELISIR LUX VERITAS FALLO EROS CERIMONIA CONFRATERNITA ORDO MAISTO CONTI \
    SARA LABORATORIO DEPOSITO ARMI OBIETTIVO SQUADRA MISSIONE ATTENZIONE TROVA CERCA VAI SEGUI APRI PRENDI LASCIA \
    UNO DUE TRE QUATTRO CINQUE SEI SETTE OTTO NOVE DIECI CENTO MILLE ZERO SEGRETO MESSAGGIO DIARIO LUCCHETTO TESORO \
    IL LO LA LE GLI DI DA IN SU MA SE NO SI CI VI MI TI NE UN HO HA AL AI \
    FORMULA CHIMICO ANTIDOTO OSPEDALE PACEMAKER INTERPOL FAMIGLIA FAMIGLIE CUORI QUADRI PICCHE FIORI CARTA ACQUA FUOCO TERRA ARIA SOLE LUNA
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    static func punteggio(_ s: String) -> (Double, [String]) {
        let lettere = s.filter { Cipher.idx($0) != nil }.count
        guard lettere >= 2 else { return (-1_000, []) }
        let chi = Cipher.chi2(s)
        var score = -chi / Double(max(lettere, 1)) * 10
        let up = s.uppercased().folding(options: .diacriticInsensitive, locale: nil)
        var trovate: [String] = []
        for p in vocabolario where p.count >= 4 && up.contains(p) { trovate.append(p) }
        let parole = Cipher.words(up)
        let intere = parole.filter { vocabolario.contains($0) }
        score += Double(trovate.reduce(0) { $0 + $1.count }) * 2 + Double(intere.count) * 6
        if parole.count >= 3 { score += Double(intere.count) / Double(parole.count) * 25 }
        let strani = s.filter { !($0.isLetter || $0.isNumber || $0.isWhitespace || ".,;:'!?-()\"/".contains($0)) }.count
        score -= Double(strani) * 3
        return (score, Array(Set(trovate + intere)).sorted { $0.count > $1.count })
    }

    /// Il testo "sembra ancora codificato": vale la pena di provare un altro strato anche se non è italiano.
    static func sembraCodificato(_ t: String) -> Bool {
        let c = t.filter { !$0.isWhitespace }
        guard c.count >= 4 else { return false }
        if c.allSatisfy({ "01".contains($0) }) || c.allSatisfy({ ".-/·_".contains($0) }) { return true }
        if c.allSatisfy(\.isHexDigit) && c.count % 2 == 0 { return true }
        if c.allSatisfy({ $0.isNumber || ",-/".contains($0) }) { return true }
        if c.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=-_".contains($0)) }) && c.count % 4 == 0
            && c.contains(where: \.isLowercase) && c.contains(where: \.isUppercase) { return true }
        if c.contains("%") || c.contains("&#") || c.contains("\\u") { return true }
        return c.unicodeScalars.contains { (0x2800...0x28FF).contains($0.value) }
    }

    static func stampabile(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        let ok = s.filter { $0.isLetter || $0.isNumber || $0.isWhitespace || $0.isPunctuation || $0.isSymbol }.count
        return Double(ok) / Double(s.count) > 0.9 && !s.contains("\u{FFFD}")
    }

    /// Tutte le decodifiche di un passo che hanno senso per questo testo.
    static func passi(_ t: String, chiavi: [String], primo: Bool) -> [(ChainStep, String)] {
        var out: [(ChainStep, String)] = []
        func prova(_ op: Op, _ p: OpParams? = nil, encode: Bool = false) {
            let st = ChainStep(op: op, encode: encode, params: p ?? op.defaultParams)
            let r = st.run(t).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !r.isEmpty, r != t, stampabile(r), !r.hasSuffix("non valido") else { return }
            out.append((st, r))
        }
        func par(_ f: (inout OpParams) -> Void, _ op: Op) -> OpParams { var p = op.defaultParams; f(&p); return p }

        let c = t.filter { !$0.isWhitespace }
        let soloMorse = c.allSatisfy { ".-_·—–/|".contains($0) } && c.contains(where: { ".-·".contains($0) })
        let soloBin = c.allSatisfy { "01".contains($0) } && c.count >= 5
        let soloNum = c.allSatisfy { $0.isNumber || ",.-/".contains($0) } && c.contains(where: \.isNumber)
        let soloAB = c.uppercased().allSatisfy { "AB".contains($0) } && c.count >= 5
        let hex = c.replacingOccurrences(of: "0x", with: "").allSatisfy(\.isHexDigit) && c.count >= 4
        let b64chars = c.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+/=-_".contains($0)) }
        let haLettere = t.contains(where: { Cipher.idx($0) != nil })

        if soloMorse { prova(.morse) }
        if soloBin {
            for bits in [8, 7, 5, 6] { prova(.binary, par({ $0.n = bits }, .binary)) }
        }
        if soloAB { prova(.bacon) }
        if soloNum {
            prova(.a1z26); prova(.a0z25); prova(.z1a26)
            prova(.a1z26, par({ $0.alfabeto = .it21 }, .a1z26))
            prova(.decimal); prova(.octal); prova(.multitap); prova(.tapcode)
            if c.allSatisfy({ "12345,-/".contains($0) }) { prova(.polybius) }
            if c.count == 10, c.hasPrefix("1") { prova(.unixTime) }
        }
        if hex && !soloBin { prova(.hex) }
        if b64chars && c.count >= 4 {
            prova(.base64); prova(.base64url); prova(.base58)
            if c.uppercased() == c { prova(.base32) }
        }
        if t.contains("<~") || (c.count >= 5 && c.allSatisfy { $0.isASCII && $0 >= "!" && $0 <= "u" } && c.contains(where: { "!#$%&()*;<>@[]^".contains($0) })) {
            prova(.ascii85)
        }
        if t.contains("%") { prova(.url) }
        if t.contains("&") && t.contains(";") { prova(.html) }
        if t.contains("\\u") || t.contains("\\x") || t.contains("U+") { prova(.unicodeEsc) }
        if t.range(of: "=[0-9A-F]{2}", options: .regularExpression) != nil { prova(.quotedPrintable) }
        if t.lowercased().contains("xn--") { prova(.punycodeLite) }
        if t.unicodeScalars.contains(where: { (0x2800...0x28FF).contains($0.value) }) { prova(.braille) }
        if c.uppercased().allSatisfy({ "IVXLCDM".contains($0) }) && c.count >= 2 { prova(.roman) }
        let w = Cipher.words(t.uppercased())
        if w.count >= 2 && w.filter({ Codec.natoWords.map { $0.uppercased().replacingOccurrences(of: "-", with: "") }.contains($0)
                                     || Codec.italianWords.map { $0.uppercased() }.contains($0) }).count * 2 >= w.count {
            prova(.nato)
        }

        guard haLettere else { return out }
        prova(.reverse); prova(.reverseWords); prova(.reverseOrder); prova(.swapPairs)
        prova(.atbash); prova(.atbash, par({ $0.alfabeto = .it21 }, .atbash))
        if t.contains(where: { "!#$%&()*+;<=>?@[]^{|}~".contains($0) }) { prova(.rot47) }
        // Cesare: i 25 spostamenti (26 lettere) e i 20 (italiano 21); se non servono tutti si tengono i migliori
        var ces: [(Double, ChainStep, String)] = []
        for al in Alfabeto.allCases {
            for n in 1..<al.m {
                let st = ChainStep(op: .caesar, encode: false, params: OpParams(n: n, alfabeto: al))
                let r = st.run(t)
                ces.append((Cipher.chi2(r), st, r))
            }
        }
        ces.sort { $0.0 < $1.0 }
        for x in (primo ? ces : Array(ces.prefix(2))) { out.append((x.1, x.2)) }
        guard primo else {
            for k in chiavi where k.count >= 2 { prova(.vigenere, par({ $0.key = k }, .vigenere)) }
            return out
        }
        // Affine: tutte le combinazioni, tengo le 3 migliori
        var aff: [(Double, ChainStep, String)] = []
        for a in [3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25] {
            for b in 0..<26 {
                let st = ChainStep(op: .affine, encode: false, params: OpParams(n: a, n2: b))
                let r = st.run(t)
                aff.append((Cipher.chi2(r), st, r))
            }
        }
        aff.sort { $0.0 < $1.0 }
        for x in aff.prefix(3) { out.append((x.1, x.2)) }
        for k in chiavi where k.count >= 2 {
            for op in [Op.vigenere, .beaufort, .autokey, .keyword, .playfair] { prova(op, par({ $0.key = k }, op)) }
        }
        if Cipher.words(t).count == 1 || t.count < 400 {
            for r in 2...6 { prova(.railfence, par({ $0.n = r }, .railfence)) }
            for k in 2...8 { prova(.scytale, par({ $0.n = k }, .scytale)) }
        }
        if w.count >= 3 { prova(.initials); prova(.finals); prova(.lastWords) }
        let maiu = t.filter(\.isUppercase)
        if maiu.count >= 3 && maiu.count < t.filter(\.isLetter).count {
            prova(.onlyUpper)
            if t.filter(\.isLetter).count >= 10 { prova(.baconCase) }
        }
        return out
    }

    static func tutte(_ raw: String, chiavi: [String]) -> [Lettura] {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        let maxDepth = t.count <= 300 ? 3 : (t.count <= 3000 ? 2 : 1)
        struct Stato { let passi: [ChainStep]; let testo: String; let score: Double; var decodifica = false }
        var risultati: [Lettura] = []
        var visti = Set<String>([t])
        let (p0, w0) = punteggio(t)
        risultati.append(Lettura(metodo: "Testo così com'è", testo: t, punteggio: p0, parole: w0))
        var frontiera = [Stato(passi: [], testo: t, score: p0)]
        for depth in 1...maxDepth {
            var prossimi: [Stato] = []
            for s in frontiera {
                for (st, r) in passi(s.testo, chiavi: chiavi, primo: depth == 1) where !visti.contains(r) {
                    visti.insert(r)
                    let path = s.passi + [st]
                    let (p, w) = punteggio(r)
                    var score = p - Double(depth - 1) * 4
                    let decodifica = [OpCategoria.codifiche, .lettereNumeri].contains(st.op.categoria)
                    // un cifrario a lettere applicato a un Base64/hex/binario non è quasi mai la strada giusta
                    if sembraCodificato(s.testo) && !decodifica { score -= 30 }
                    risultati.append(Lettura(metodo: path.map(\.etichettaBreve).joined(separator: " → "), testo: r,
                                             punteggio: score, parole: w, passi: path))
                    prossimi.append(Stato(passi: path, testo: r,
                                          score: score + (sembraCodificato(r) ? 40 : 0) + (decodifica ? 35 : 0),
                                          decodifica: decodifica))
                }
            }
            // le decodifiche (Base64, hex, binario, Morse, numeri…) passano sempre allo strato dopo, anche se
            // il risultato non sembra ancora italiano: sotto può esserci un altro cifrario
            let ordinati = prossimi.sorted { $0.score > $1.score }
            let dec = ordinati.filter(\.decodifica).prefix(6)
            let altri = ordinati.filter { !$0.decodifica }.prefix(depth == 1 ? 8 : 5)
            frontiera = Array(dec) + Array(altri)
            if frontiera.isEmpty { break }
        }
        return risultati.sorted { $0.punteggio > $1.punteggio }
    }
}

extension ChainStep {
    /// Etichetta corta per i percorsi della decifratura automatica.
    var etichettaBreve: String {
        switch op {
        case .caesar: return "Cesare −\(params.n)" + (params.alfabeto == .it21 ? " (21)" : "") + " [chiave \(Cipher.letter(params.n, upper: true))]"
        case .affine: return "Affine a=\(params.n) b=\(params.n2)"
        case .vigenere, .beaufort, .autokey, .keyword, .playfair: return "\(op.titolo) «\(params.key)»"
        case .railfence: return "Rail fence \(params.n)"
        case .scytale: return "Scitala \(params.n)"
        case .binary: return "Binario \(params.n) bit"
        case .atbash, .a1z26: return op.titolo + (params.alfabeto == .it21 ? " (21)" : "")
        default: return op.titolo
        }
    }
}
