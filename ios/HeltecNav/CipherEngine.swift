import Foundation

enum CipherOp: String, CaseIterable, Identifiable {
    case cesareTutti = "Cesare: tutti i 26"
    case cesare = "Cesare (spostamento)"
    case inverti = "Inverti tutto"
    case invertiParole = "Inverti ogni parola"
    case invertiCesare = "Parole invertite + Cesare tutti"
    case atbash = "Atbash (A↔Z)"
    case vigenereDec = "Vigenère decifra"
    case vigenereEnc = "Vigenère cifra"
    case vigenereChiavi = "Vigenère chiavi di gara"
    case numeriLettere = "Numeri → lettere (A1Z26)"
    case lettereNumeri = "Lettere → numeri (A1Z26)"
    case morseDec = "Morse → testo"
    case morseEnc = "Testo → Morse"
    case bacone = "Bacone (A/B a gruppi di 5)"
    case polibio = "Polibio (coppie di numeri)"
    case hex = "Esadecimale → testo"
    case base64 = "Base64 → testo"
    case binario = "Binario → testo"
    case iniziali = "Iniziali di ogni parola"
    case finali = "Ultime lettere di ogni parola"
    case finaliFrase = "Ultima parola di ogni frase"
    case maiuscole = "Solo maiuscole"
    case frequenze = "Frequenze lettere"
    case railFence = "Rail fence decifra (binari)"

    var id: String { rawValue }
    var needsKey: Bool { [.vigenereDec, .vigenereEnc].contains(self) }
    var needsNumber: Bool { [.cesare, .railFence].contains(self) }
}

enum Cipher {
    static let gameKeys = ["LORN", "ORO", "MIDA", "REMIDA", "OBELISCO", "OBELISCUS", "LUXETVERITAS", "FALLO", "EROS",
                           "VALDRAGO", "FERRO", "STAGNO", "PIOMBO", "ELISIR", "VANE", "ALCHIMIA"]

    static func run(_ op: CipherOp, _ text: String, key: String, n: Int) -> String {
        switch op {
        case .cesareTutti: return allShifts(text)
        case .cesare: return caesar(text, n)
        case .inverti: return String(text.reversed())
        case .invertiParole: return reverseWords(text)
        case .invertiCesare: return allShifts(reverseWords(text))
        case .atbash: return mapLetters(text) { 25 - $0 }
        case .vigenereDec: return vigenere(text, key, decrypt: true)
        case .vigenereEnc: return vigenere(text, key, decrypt: false)
        case .vigenereChiavi:
            return gameKeys.map { k in
                let d = vigenere(text, k, decrypt: true)
                return (chi2(d), "[\(k)] \(d)")
            }.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: "\n\n")
        case .numeriLettere: return numbersToLetters(text)
        case .lettereNumeri:
            return text.uppercased().compactMap { c -> String? in
                guard let i = idx(c) else { return c == " " ? "/" : nil }
                return String(i + 1)
            }.joined(separator: " ")
        case .morseDec: return morseDecode(text)
        case .morseEnc: return morseEncode(text)
        case .bacone: return bacon(text)
        case .polibio: return polybius(text)
        case .hex: return decodeHex(text)
        case .base64:
            let t = text.filter { !$0.isWhitespace }
            let padded = t + String(repeating: "=", count: (4 - t.count % 4) % 4)
            guard let d = Data(base64Encoded: padded) else { return "Base64 non valido" }
            return String(decoding: d, as: UTF8.self)
        case .binario:
            let bits = text.filter { $0 == "0" || $0 == "1" }
            var out = ""
            var i = bits.startIndex
            while bits.distance(from: i, to: bits.endIndex) >= 8 {
                let j = bits.index(i, offsetBy: 8)
                if let v = UInt8(bits[i..<j], radix: 2) { out.append(Character(UnicodeScalar(v))) }
                i = j
            }
            return out
        case .iniziali: return words(text).compactMap(\.first).map(String.init).joined()
        case .finali: return words(text).compactMap(\.last).map(String.init).joined()
        case .finaliFrase:
            let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?;\n")).filter { !words($0).isEmpty }
            let last = sentences.compactMap { words($0).last }
            return last.joined(separator: " ") + "\n\nUltime lettere: " + last.compactMap(\.last).map(String.init).joined()
                + "\nIniziali: " + last.compactMap(\.first).map(String.init).joined()
        case .maiuscole: return text.filter { $0.isUppercase }
        case .frequenze: return frequencies(text)
        case .railFence: return railFence(text, max(2, n))
        }
    }

    // MARK: base

    static func idx(_ c: Character) -> Int? {
        // le lettere accentate contano come la lettera base (è = E)
        let base = c.isASCII ? String(c) : String(c).folding(options: .diacriticInsensitive, locale: nil)
        guard base.count == 1, let a = base.uppercased().unicodeScalars.first, a.value >= 65, a.value <= 90 else { return nil }
        return Int(a.value) - 65
    }

    static func letter(_ i: Int, upper: Bool) -> Character {
        Character(UnicodeScalar(UInt8((upper ? 65 : 97) + ((i % 26) + 26) % 26)))
    }

    static func mapLetters(_ text: String, _ f: (Int) -> Int) -> String {
        String(text.map { c in
            guard let i = idx(c) else { return c }
            return letter(f(i), upper: c.isUppercase)
        })
    }

    static func caesar(_ t: String, _ n: Int) -> String { mapLetters(t) { $0 + n } }

    static func words(_ t: String) -> [String] {
        t.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    static func reverseWords(_ t: String) -> String {
        t.components(separatedBy: " ").map { String($0.reversed()) }.joined(separator: " ")
    }

    // frequenze dell'italiano (%), per riconoscere il testo in chiaro
    static let italian: [Double] = [11.74, 0.92, 4.5, 3.73, 11.79, 0.95, 1.64, 1.54, 11.28, 0.05, 0.05, 6.51, 2.51,
                                    6.88, 9.83, 3.05, 0.51, 6.37, 4.98, 5.62, 3.01, 2.10, 0.05, 0.05, 0.05, 0.49]

    static func chi2(_ t: String) -> Double {
        var counts = [Double](repeating: 0, count: 26)
        for c in t { if let i = idx(c) { counts[i] += 1 } }
        let total = counts.reduce(0, +)
        guard total > 0 else { return .infinity }
        return (0..<26).reduce(0) { s, i in
            let e = italian[i] / 100 * total
            return s + pow(counts[i] - e, 2) / e
        }
    }

    static func allShifts(_ t: String) -> String {
        (0..<26).map { n -> (Double, String) in
            let s = caesar(t, n)
            let dec = (26 - n) % 26
            let label = n == 0 ? "originale" : "+\(n) = lettera \(letter(n - 1, upper: true)) (era cifrato con +\(dec))"
            return (chi2(s), label + "\n" + s)
        }
        .sorted { $0.0 < $1.0 }
        .enumerated()
        .map { i, x in (i == 0 ? "★ " : "") + x.1 + String(format: "\n  χ² %.0f", x.0) }
        .joined(separator: "\n\n")
    }

    static func vigenere(_ t: String, _ key: String, decrypt: Bool) -> String {
        let k = key.compactMap(idx)
        guard !k.isEmpty else { return "Inserisci una chiave" }
        var j = 0
        return String(t.map { c in
            guard let i = idx(c) else { return c }
            let s = k[j % k.count]
            j += 1
            return letter(decrypt ? i - s : i + s, upper: c.isUppercase)
        })
    }

    static func numbersToLetters(_ t: String) -> String {
        t.components(separatedBy: "/").map { word in
            word.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.map { v in
                (1...26).contains(v) ? String(letter(v - 1, upper: true)) : "[\(v)]"
            }.joined()
        }.joined(separator: " ")
    }

    static let morse: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....", "I": "..",
        "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
        "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....", "6": "-....",
        "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "'": ".----.", "!": "-.-.--", "/": "-..-.", "(": "-.--.",
        ")": "-.--.-", "&": ".-...", ":": "---...", ";": "-.-.-.", "=": "-...-", "+": ".-.-.", "-": "-....-",
        "_": "..--.-", "\"": ".-..-.", "@": ".--.-.", "À": ".--.-", "È": ".-..-", "É": "..-..", "Ò": "---.",
    ]

    static func morseEncode(_ t: String) -> String {
        t.uppercased().map { c in c == " " ? "/" : (morse[c] ?? "") }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func morseDecode(_ t: String) -> String {
        let rev = Dictionary(uniqueKeysWithValues: morse.map { ($1, $0) })
        let norm = t.replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "·", with: ".")
            .replacingOccurrences(of: "|", with: "/")
        return norm.components(separatedBy: "/").map { w in
            String(w.split(separator: " ").map { rev[String($0)] ?? "?" })
        }.joined(separator: " ")
    }

    static func bacon(_ t: String) -> String {
        let ab = t.uppercased().compactMap { c -> Int? in c == "A" ? 0 : (c == "B" ? 1 : nil) }
        var v24 = "", v26 = ""
        let a24 = Array("ABCDEFGHIKLMNOPQRSTUWXYZ")
        for i in stride(from: 0, to: ab.count - ab.count % 5, by: 5) {
            let n = ab[i..<i + 5].reduce(0) { $0 * 2 + $1 }
            v26.append(n < 26 ? letter(n, upper: true) : "?")
            v24.append(n < 24 ? a24[n] : "?")
        }
        return "Alfabeto 26: \(v26)\nAlfabeto 24 (I=J, U=V): \(v24)\n\nSe il testo è normale, prima trasforma le lettere in A/B (es. maiuscole=B)."
    }

    static func polybius(_ t: String) -> String {
        let digits = t.filter { $0 >= "1" && $0 <= "5" }.compactMap { Int(String($0)) }
        let grid = Array("ABCDEFGHIKLMNOPQRSTUVWXYZ")
        var out = ""
        for i in stride(from: 0, to: digits.count - digits.count % 2, by: 2) {
            out.append(grid[(digits[i] - 1) * 5 + digits[i + 1] - 1])
        }
        return out + "\n(griglia 5x5 A–Z senza J; riga poi colonna)"
    }

    static func decodeHex(_ t: String) -> String {
        let h = t.filter { $0.isHexDigit }
        var bytes = [UInt8]()
        var i = h.startIndex
        while h.distance(from: i, to: h.endIndex) >= 2 {
            let j = h.index(i, offsetBy: 2)
            if let b = UInt8(h[i..<j], radix: 16) { bytes.append(b) }
            i = j
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func frequencies(_ t: String) -> String {
        var counts = [Int](repeating: 0, count: 26)
        for c in t { if let i = idx(c) { counts[i] += 1 } }
        let total = max(1, counts.reduce(0, +))
        let rows = (0..<26).filter { counts[$0] > 0 }.sorted { counts[$0] > counts[$1] }.map { i in
            String(format: "%@  %3d  %5.1f%%  (it %4.1f%%)  %@", String(letter(i, upper: true)), counts[i],
                   Double(counts[i]) * 100 / Double(total), italian[i], String(repeating: "█", count: counts[i] * 40 / total))
        }
        return "Lettere: \(total)  χ² italiano: \(String(format: "%.0f", chi2(t)))\n\n" + rows.joined(separator: "\n")
    }

    static func railFence(_ t: String, _ rails: Int) -> String {
        let chars = Array(t)
        let n = chars.count
        guard n > 0 else { return "" }
        let cycle = 2 * (rails - 1)
        let railOf = (0..<n).map { i -> Int in let p = i % cycle; return p < rails ? p : cycle - p }
        var out = [Character](repeating: " ", count: n)
        var k = 0
        for r in 0..<rails {
            for i in 0..<n where railOf[i] == r { out[i] = chars[k]; k += 1 }
        }
        return String(out)
    }
}
