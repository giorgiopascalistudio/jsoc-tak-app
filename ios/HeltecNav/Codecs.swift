import Foundation
import CryptoKit

// MARK: - Catalogo delle operazioni (codifiche, cifrari, trasformazioni, numeri, hash)
//
// Ogni operazione ha un verso "decodifica" e, quando ha senso, "codifica". Si possono mettere in catena:
// l'uscita di un passo è l'ingresso del successivo (es. Base64 → Cesare → al contrario).

enum Alfabeto: String, Codable, CaseIterable, Identifiable {
    case a26 = "26 lettere", it21 = "Italiano 21"
    var id: String { rawValue }
    var lettere: [Character] { self == .a26 ? Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ") : Array("ABCDEFGHILMNOPQRSTUVZ") }
    var m: Int { lettere.count }
}

struct OpParams: Codable, Hashable {
    var n = 3
    var n2 = 0
    var key = ""
    var alfabeto: Alfabeto = .a26
}

enum OpCategoria: String, CaseIterable, Identifiable {
    case cifrari = "Cifrari", codifiche = "Codifiche", lettereNumeri = "Lettere e numeri", testo = "Testo",
         numeri = "Numeri e date", hash = "Hash"
    var id: String { rawValue }
}

enum Op: String, Codable, CaseIterable, Identifiable {
    // cifrari
    case caesar, rot13, rot5, rot18, rot47, atbash, affine, vigenere, beaufort, autokey, gronsfeld, keyword,
         playfair, bifid, railfence, scytale, columnar, xor, enigma
    // codifiche
    case base64, base64url, base32, base58, ascii85, hex, binary, octal, decimal, url, html, unicodeEsc,
         quotedPrintable, punycodeLite, morse, braille, nato
    // lettere e numeri
    case a1z26, a0z25, z1a26, polybius, tapcode, bacon, baconCase, multitap, t9, roman, numeriParole
    // testo
    case reverse, reverseWords, reverseOrder, upper, lower, swapCase, removeSpaces, removeAccents, onlyLetters,
         initials, finals, lastWords, onlyUpper, onlyLower, nthLetter, swapPairs, replace, frequencies, count
    // numeri e date
    case baseConv, unixTime
    // hash
    case md5, sha1, sha256, sha512, crc32

    var id: String { rawValue }

    var titolo: String {
        switch self {
        case .caesar: return "Cesare"
        case .rot13: return "ROT13"
        case .rot5: return "ROT5 (cifre)"
        case .rot18: return "ROT18 (lettere+cifre)"
        case .rot47: return "ROT47 (ASCII)"
        case .atbash: return "Atbash (A↔Z)"
        case .affine: return "Affine (a·x+b)"
        case .vigenere: return "Vigenère"
        case .beaufort: return "Beaufort"
        case .autokey: return "Vigenère autochiave"
        case .gronsfeld: return "Gronsfeld (chiave numerica)"
        case .keyword: return "Alfabeto con parola chiave"
        case .playfair: return "Playfair"
        case .bifid: return "Bifid (Delastelle)"
        case .railfence: return "Rail fence (binari)"
        case .scytale: return "Scitala"
        case .columnar: return "Trasposizione a colonne"
        case .xor: return "XOR con chiave"
        case .enigma: return "Enigma M3"
        case .base64: return "Base64"
        case .base64url: return "Base64 URL"
        case .base32: return "Base32"
        case .base58: return "Base58"
        case .ascii85: return "Ascii85"
        case .hex: return "Esadecimale"
        case .binary: return "Binario"
        case .octal: return "Ottale"
        case .decimal: return "Codici decimali (ASCII/Unicode)"
        case .url: return "URL (%XX)"
        case .html: return "Entità HTML"
        case .unicodeEsc: return "Escape Unicode (\\u)"
        case .quotedPrintable: return "Quoted-printable"
        case .punycodeLite: return "Punycode (xn--)"
        case .morse: return "Morse"
        case .braille: return "Braille"
        case .nato: return "Alfabeto fonetico (NATO / italiano)"
        case .a1z26: return "Lettere ↔ numeri A=1"
        case .a0z25: return "Lettere ↔ numeri A=0"
        case .z1a26: return "Lettere ↔ numeri Z=1"
        case .polybius: return "Polibio 5×5"
        case .tapcode: return "Tap code (colpi)"
        case .bacon: return "Bacone (A/B)"
        case .baconCase: return "Bacone nascosto (maiuscole/minuscole)"
        case .multitap: return "Tastiera telefono (44 33 555)"
        case .t9: return "Tastiera telefono T9 (un tasto per lettera)"
        case .roman: return "Numeri romani"
        case .numeriParole: return "Numeri in parole (italiano)"
        case .reverse: return "Al contrario"
        case .reverseWords: return "Ogni parola al contrario"
        case .reverseOrder: return "Ordine delle parole al contrario"
        case .upper: return "MAIUSCOLO"
        case .lower: return "minuscolo"
        case .swapCase: return "Inverti maiuscole/minuscole"
        case .removeSpaces: return "Togli spazi e punteggiatura"
        case .removeAccents: return "Togli accenti"
        case .onlyLetters: return "Solo lettere"
        case .initials: return "Iniziali delle parole"
        case .finals: return "Ultime lettere delle parole"
        case .lastWords: return "Ultima parola di ogni frase"
        case .onlyUpper: return "Solo le maiuscole"
        case .onlyLower: return "Solo le minuscole"
        case .nthLetter: return "Una lettera ogni N"
        case .swapPairs: return "Scambia le coppie"
        case .replace: return "Sostituisci"
        case .frequencies: return "Frequenze lettere"
        case .count: return "Conta caratteri e parole"
        case .baseConv: return "Cambio base numerica"
        case .unixTime: return "Unix time ↔ data"
        case .md5: return "MD5"
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        case .crc32: return "CRC32"
        }
    }

    var categoria: OpCategoria {
        switch self {
        case .caesar, .rot13, .rot5, .rot18, .rot47, .atbash, .affine, .vigenere, .beaufort, .autokey, .gronsfeld,
             .keyword, .playfair, .bifid, .railfence, .scytale, .columnar, .xor, .enigma: return .cifrari
        case .base64, .base64url, .base32, .base58, .ascii85, .hex, .binary, .octal, .decimal, .url, .html,
             .unicodeEsc, .quotedPrintable, .punycodeLite, .morse, .braille, .nato: return .codifiche
        case .a1z26, .a0z25, .z1a26, .polybius, .tapcode, .bacon, .baconCase, .multitap, .t9, .roman, .numeriParole: return .lettereNumeri
        case .baseConv, .unixTime: return .numeri
        case .md5, .sha1, .sha256, .sha512, .crc32: return .hash
        default: return .testo
        }
    }

    /// Operazioni dove codifica = decodifica (o che hanno un solo verso).
    var unSoloVerso: Bool {
        switch self {
        case .rot13, .rot5, .rot18, .rot47, .atbash, .beaufort, .enigma, .reverse, .reverseWords, .reverseOrder,
             .upper, .lower, .swapCase, .removeSpaces, .removeAccents, .onlyLetters, .initials, .finals, .lastWords,
             .onlyUpper, .onlyLower, .nthLetter, .swapPairs, .replace, .frequencies, .count, .baseConv, .md5, .sha1,
             .sha256, .sha512, .crc32, .baconCase: return true
        default: return false
        }
    }

    // parametri
    var usaN: String? {
        switch self {
        case .caesar: return "Spostamento"
        case .affine: return "a"
        case .railfence: return "Binari"
        case .scytale: return "Colonne"
        case .nthLetter: return "Ogni"
        case .baseConv: return "Da base"
        case .binary: return "Bit per carattere"
        default: return nil
        }
    }
    var usaN2: String? {
        switch self {
        case .affine: return "b"
        case .nthLetter: return "Partendo da"
        case .baseConv: return "A base"
        default: return nil
        }
    }
    var usaChiave: String? {
        switch self {
        case .vigenere, .beaufort, .autokey, .keyword, .playfair, .bifid, .columnar, .polybius: return "Chiave"
        case .gronsfeld: return "Chiave numerica (es. 2413)"
        case .xor: return "Chiave (testo)"
        case .enigma: return "Rotori · anelli · posizioni · spine  (es. I II III AAA AAA AB CD)"
        case .replace: return "Da=A, da=a  (es. X=E, Q=A)"
        default: return nil
        }
    }
    var usaAlfabeto: Bool { [.caesar, .atbash, .affine, .vigenere, .beaufort, .autokey, .gronsfeld, .keyword, .a1z26, .a0z25, .z1a26].contains(self) }

    var defaultParams: OpParams {
        var p = OpParams()
        switch self {
        case .caesar: p.n = 3
        case .affine: p.n = 5; p.n2 = 8
        case .railfence: p.n = 3
        case .scytale: p.n = 4
        case .nthLetter: p.n = 2; p.n2 = 1
        case .baseConv: p.n = 10; p.n2 = 2
        case .binary: p.n = 8
        case .vigenere, .beaufort, .autokey, .keyword, .playfair, .bifid, .columnar: p.key = "LORN"
        case .gronsfeld: p.key = "12151814"
        case .enigma: p.key = "I II III AAA AAA"
        default: break
        }
        return p
    }

    static func lista(_ c: OpCategoria) -> [Op] { allCases.filter { $0.categoria == c } }
}

// MARK: - Esecuzione

enum Codec {
    static func apply(_ op: Op, _ s: String, _ p: OpParams, encode: Bool) -> String {
        let dec = !encode
        switch op {
        // ---- cifrari
        case .caesar: return shift(s, dec ? -p.n : p.n, p.alfabeto)
        case .rot13: return shift(s, 13, .a26)
        case .rot5: return String(s.map { c in c.isASCII && c.isNumber ? Character(String((Int(String(c))! + 5) % 10)) : c })
        case .rot18: return apply(.rot5, shift(s, 13, .a26), p, encode: true)
        case .rot47: return String(s.unicodeScalars.map { u in
            (33...126).contains(u.value) ? Character(UnicodeScalar(33 + (u.value + 14) % 94)!) : Character(u) })
        case .atbash: return mapAlpha(s, p.alfabeto) { i, m in m - 1 - i }
        case .affine: return affine(s, a: p.n, b: p.n2, al: p.alfabeto, decode: dec)
        case .vigenere: return vig(s, p.key, p.alfabeto) { x, k, m in dec ? x - k : x + k }
        case .beaufort: return vig(s, p.key, p.alfabeto) { x, k, m in k - x }
        case .autokey: return autokey(s, p.key, p.alfabeto, decode: dec)
        case .gronsfeld:
            let shifts = p.key.compactMap { $0.wholeNumberValue }
            guard !shifts.isEmpty else { return "Chiave numerica mancante" }
            var j = 0
            return mapAlpha(s, p.alfabeto) { i, m in defer { j += 1 }; return i + (dec ? -1 : 1) * shifts[j % shifts.count] }
        case .keyword: return keyword(s, p.key, p.alfabeto, decode: dec)
        case .playfair: return playfair(s, p.key, decode: dec)
        case .bifid: return bifid(s, p.key, decode: dec)
        case .railfence: return dec ? Cipher.railFence(s, max(2, p.n)) : railEncode(s, max(2, p.n))
        case .scytale: return scytale(s, max(2, p.n), decode: dec)
        case .columnar: return columnar(s, p.key, decode: dec)
        case .xor: return xor(s, p.key, decode: dec)
        case .enigma:
            guard var e = Enigma(config: p.key) else { return "Configurazione non valida (es. I II III AAA AAA AB CD)" }
            return e.run(s)
        // ---- codifiche
        case .base64: return dec ? fromBase64(s, url: false) : Data(s.utf8).base64EncodedString()
        case .base64url:
            return dec ? fromBase64(s, url: true)
                : Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        case .base32: return dec ? (base32Decode(s).map(utf8) ?? "Base32 non valido") : base32Encode(Array(s.utf8))
        case .base58: return dec ? (base58Decode(s).map(utf8) ?? "Base58 non valido") : base58Encode(Array(s.utf8))
        case .ascii85: return dec ? (ascii85Decode(s).map(utf8) ?? "Ascii85 non valido") : ascii85Encode(Array(s.utf8))
        case .hex: return dec ? utf8(hexBytes(s)) : s.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .binary:
            let bits = max(5, min(16, p.n))
            if dec { return fromRadix(s, 2, groupBits: bits) }
            return s.unicodeScalars.map { String($0.value, radix: 2).leftPad(bits) }.joined(separator: " ")
        case .octal:
            return dec ? fromTokens(s, radix: 8) : s.unicodeScalars.map { String($0.value, radix: 8) }.joined(separator: " ")
        case .decimal:
            return dec ? fromTokens(s, radix: 10) : s.unicodeScalars.map { String($0.value) }.joined(separator: " ")
        case .url:
            return dec ? (s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "URL non valido")
                : (s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s)
        case .html: return dec ? htmlDecode(s) : htmlEncode(s)
        case .unicodeEsc: return dec ? unicodeUnescape(s) : s.unicodeScalars.map { $0.isASCII ? String($0) : String(format: "\\u%04X", $0.value) }.joined()
        case .quotedPrintable: return dec ? qpDecode(s) : qpEncode(s)
        case .punycodeLite: return dec ? punyDecodeDomain(s) : "Solo decodifica"
        case .morse: return dec ? Cipher.morseDecode(s) : Cipher.morseEncode(s)
        case .braille: return dec ? brailleDecode(s) : brailleEncode(s)
        case .nato: return dec ? natoDecode(s) : natoEncode(s)
        // ---- lettere e numeri
        case .a1z26: return dec ? numToLetters(s, base: 1, al: p.alfabeto, reverse: false) : lettersToNum(s, base: 1, al: p.alfabeto, reverse: false)
        case .a0z25: return dec ? numToLetters(s, base: 0, al: p.alfabeto, reverse: false) : lettersToNum(s, base: 0, al: p.alfabeto, reverse: false)
        case .z1a26: return dec ? numToLetters(s, base: 1, al: p.alfabeto, reverse: true) : lettersToNum(s, base: 1, al: p.alfabeto, reverse: true)
        case .polybius: return polybius(s, p.key, decode: dec)
        case .tapcode: return tap(s, decode: dec)
        case .bacon: return dec ? baconDecode(s) : baconEncode(s)
        case .baconCase:
            let ab = s.filter(\.isLetter).map { $0.isUppercase ? "B" : "A" }.joined()
            return "Maiuscole = B → " + baconDecode(ab) + "\nMinuscole = B → " + baconDecode(String(ab.map { $0 == "A" ? "B" : "A" }))
        case .multitap: return dec ? multitapDecode(s) : multitapEncode(s)
        case .t9: return dec ? "Il T9 a un tasto non si decodifica in modo unico: usa la tastiera (44 33 555)" : t9Encode(s)
        case .roman: return dec ? romanDecode(s) : romanEncode(s)
        case .numeriParole: return dec ? paroleToNum(s) : numToParole(s)
        // ---- testo
        case .reverse: return String(s.reversed())
        case .reverseWords: return Cipher.reverseWords(s)
        case .reverseOrder: return s.split(separator: " ").reversed().joined(separator: " ")
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .swapCase: return String(s.map { $0.isUppercase ? Character($0.lowercased()) : Character($0.uppercased()) })
        case .removeSpaces: return s.filter { $0.isLetter || $0.isNumber }
        case .removeAccents: return s.folding(options: .diacriticInsensitive, locale: nil)
        case .onlyLetters: return s.filter(\.isLetter)
        case .initials: return Cipher.words(s).compactMap(\.first).map(String.init).joined()
        case .finals: return Cipher.words(s).compactMap(\.last).map(String.init).joined()
        case .lastWords: return Cipher.run(.finaliFrase, s, key: "", n: 0)
        case .onlyUpper: return s.filter(\.isUppercase)
        case .onlyLower: return s.filter(\.isLowercase)
        case .nthLetter:
            let l = Array(s.filter(\.isLetter)), step = max(1, p.n), start = max(0, p.n2 - 1)
            return start < l.count ? String(stride(from: start, to: l.count, by: step).map { l[$0] }) : ""
        case .swapPairs:
            var a = Array(s)
            for i in stride(from: 0, to: a.count - 1, by: 2) { a.swapAt(i, i + 1) }
            return String(a)
        case .replace: return replace(s, p.key)
        case .frequencies: return Cipher.frequencies(s)
        case .count:
            return "Caratteri: \(s.count)\nLettere: \(s.filter(\.isLetter).count)\nCifre: \(s.filter(\.isNumber).count)\nParole: \(Cipher.words(s).count)\nRighe: \(s.components(separatedBy: .newlines).count)"
        // ---- numeri
        case .baseConv: return baseConv(s, from: p.n, to: p.n2)
        case .unixTime: return dec ? unixToDate(s) : dateToUnix(s)
        // ---- hash
        case .md5: return Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        case .sha1: return Insecure.SHA1.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        case .sha256: return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        case .sha512: return SHA512.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        case .crc32: return String(format: "%08X", crc32(Array(s.utf8)))
        }
    }

    // MARK: lettere su alfabeto (26 o italiano 21); maiuscole, minuscole e accenti rispettati

    static func letterIndex(_ c: Character, _ al: Alfabeto) -> Int? {
        let base = String(c).folding(options: .diacriticInsensitive, locale: nil).uppercased()
        guard base.count == 1, let ch = base.first else { return nil }
        return al.lettere.firstIndex(of: ch)
    }

    static func mapAlpha(_ s: String, _ al: Alfabeto, _ f: (Int, Int) -> Int) -> String {
        let m = al.m, L = al.lettere
        return String(s.map { c -> Character in
            guard let i = letterIndex(c, al) else { return c }
            let out = L[((f(i, m) % m) + m) % m]
            return c.isLowercase ? Character(out.lowercased()) : out
        })
    }

    static func shift(_ s: String, _ n: Int, _ al: Alfabeto) -> String { mapAlpha(s, al) { i, _ in i + n } }

    static func vig(_ s: String, _ key: String, _ al: Alfabeto, _ f: (Int, Int, Int) -> Int) -> String {
        let k = key.compactMap { letterIndex($0, al) }
        guard !k.isEmpty else { return "Chiave mancante" }
        var j = 0
        return mapAlpha(s, al) { i, m in defer { j += 1 }; return f(i, k[j % k.count], m) }
    }

    static func autokey(_ s: String, _ key: String, _ al: Alfabeto, decode: Bool) -> String {
        var stream = key.compactMap { letterIndex($0, al) }
        guard !stream.isEmpty else { return "Chiave mancante" }
        var j = 0
        return mapAlpha(s, al) { i, m in
            let k = stream[j]; j += 1
            let out = decode ? i - k : i + k
            stream.append(decode ? ((out % m) + m) % m : i)
            return out
        }
    }

    static func modInverse(_ a: Int, _ m: Int) -> Int? {
        for x in 1..<m where (a * x) % m == 1 { return x }
        return nil
    }

    static func affine(_ s: String, a: Int, b: Int, al: Alfabeto, decode: Bool) -> String {
        let m = al.m
        guard let inv = modInverse(((a % m) + m) % m, m) else { return "a=\(a) non va bene con \(m) lettere (deve essere coprimo)" }
        return mapAlpha(s, al) { x, _ in decode ? inv * (x - b) : a * x + b }
    }

    static func mixedAlphabet(_ key: String, _ base: [Character]) -> [Character] {
        var out: [Character] = []
        for c in key.uppercased().folding(options: .diacriticInsensitive, locale: nil) + String(base) where base.contains(c) && !out.contains(c) {
            out.append(c)
        }
        return out
    }

    static func keyword(_ s: String, _ key: String, _ al: Alfabeto, decode: Bool) -> String {
        let plain = al.lettere, mixed = mixedAlphabet(key, plain)
        return String(s.map { c -> Character in
            guard let i = letterIndex(c, al) else { return c }
            let out: Character = decode ? plain[mixed.firstIndex(of: plain[i]) ?? i] : mixed[i]
            return c.isLowercase ? Character(out.lowercased()) : out
        })
    }

    static func square(_ key: String) -> [Character] {
        mixedAlphabet(key.uppercased().replacingOccurrences(of: "J", with: "I"), Array("ABCDEFGHIKLMNOPQRSTUVWXYZ"))
    }

    static func cleanLetters(_ s: String) -> [Character] {
        s.uppercased().folding(options: .diacriticInsensitive, locale: nil).compactMap { c -> Character? in
            guard c.isASCII, c.isLetter else { return nil }
            return c == "J" ? "I" : c
        }
    }

    static func playfair(_ s: String, _ key: String, decode: Bool) -> String {
        let sq = square(key)
        var t = cleanLetters(s)
        if !decode {
            var out: [Character] = []
            var i = 0
            while i < t.count {
                let a = t[i]
                var b: Character = "X"
                if i + 1 < t.count, t[i + 1] != a { b = t[i + 1]; i += 2 } else { i += 1 }
                if a == "X" && b == "X" { b = "Q" }
                out += [a, b]
            }
            t = out
        } else if t.count % 2 == 1 { t.append("X") }
        let d = decode ? 4 : 1
        var res = ""
        for i in stride(from: 0, to: t.count, by: 2) {
            let p1 = sq.firstIndex(of: t[i])!, p2 = sq.firstIndex(of: t[i + 1])!
            let (r1, c1, r2, c2) = (p1 / 5, p1 % 5, p2 / 5, p2 % 5)
            if r1 == r2 { res += [sq[r1 * 5 + (c1 + d) % 5], sq[r2 * 5 + (c2 + d) % 5]].map(String.init).joined() }
            else if c1 == c2 { res += [sq[((r1 + d) % 5) * 5 + c1], sq[((r2 + d) % 5) * 5 + c2]].map(String.init).joined() }
            else { res += String(sq[r1 * 5 + c2]) + String(sq[r2 * 5 + c1]) }
            res += " "
        }
        return res.trimmingCharacters(in: .whitespaces)
    }

    static func bifid(_ s: String, _ key: String, decode: Bool) -> String {
        let sq = square(key), t = cleanLetters(s)
        let coords = t.map { sq.firstIndex(of: $0)! }
        if !decode {
            let rows = coords.map { $0 / 5 }, cols = coords.map { $0 % 5 }
            let all = rows + cols
            return String(stride(from: 0, to: all.count, by: 2).map { sq[all[$0] * 5 + all[$0 + 1]] })
        }
        let flat = coords.flatMap { [$0 / 5, $0 % 5] }
        let n = t.count
        return String((0..<n).map { sq[flat[$0] * 5 + flat[n + $0]] })
    }

    static func railEncode(_ s: String, _ rails: Int) -> String {
        let chars = Array(s)
        let cycle = 2 * (rails - 1)
        var rows = [String](repeating: "", count: rails)
        for (i, c) in chars.enumerated() { let p = i % cycle; rows[p < rails ? p : cycle - p].append(c) }
        return rows.joined()
    }

    static func scytale(_ s: String, _ cols: Int, decode: Bool) -> String {
        let chars = Array(s)
        let rows = Int(ceil(Double(chars.count) / Double(cols)))
        guard rows > 0 else { return s }
        if !decode {
            var out = ""
            for c in 0..<cols { for r in 0..<rows { let i = r * cols + c; if i < chars.count { out.append(chars[i]) } } }
            return out
        }
        // inversa: le colonne lunghe sono le prime (chars.count % cols)
        let full = chars.count % cols == 0 ? cols : chars.count % cols
        var grid = [[Character]](repeating: [], count: cols)
        var k = 0
        for c in 0..<cols {
            let h = c < full ? rows : rows - 1
            grid[c] = Array(chars[k..<min(k + h, chars.count)]); k += h
        }
        var out = ""
        for r in 0..<rows { for c in 0..<cols where r < grid[c].count { out.append(grid[c][r]) } }
        return out
    }

    static func columnar(_ s: String, _ key: String, decode: Bool) -> String {
        let k = Array(key.uppercased().filter(\.isLetter))
        guard k.count >= 2 else { return "Chiave di almeno 2 lettere" }
        let order = k.indices.sorted { k[$0] == k[$1] ? $0 < $1 : k[$0] < k[$1] }
        let chars = Array(s.filter { !$0.isWhitespace }), n = k.count
        let rows = Int(ceil(Double(chars.count) / Double(n)))
        if !decode {
            var parts: [String] = []
            for c in order {
                var col = ""
                for r in 0..<rows where r * n + c < chars.count { col.append(chars[r * n + c]) }
                parts.append(col)
            }
            return parts.joined(separator: " ")
        }
        let longCols = chars.count % n == 0 ? n : chars.count % n
        var cols = [[Character]](repeating: [], count: n)
        var idx = 0
        for c in order {
            let h = c < longCols ? rows : rows - 1
            cols[c] = Array(chars[idx..<min(idx + h, chars.count)]); idx += h
        }
        var out = ""
        for r in 0..<rows { for c in 0..<n where r < cols[c].count { out.append(cols[c][r]) } }
        return out
    }

    static func xor(_ s: String, _ key: String, decode: Bool) -> String {
        let k = Array(key.utf8)
        guard !k.isEmpty else { return "Chiave mancante" }
        let src: [UInt8] = decode && s.filter({ !$0.isWhitespace }).allSatisfy(\.isHexDigit) ? hexBytes(s) : Array(s.utf8)
        let out = src.enumerated().map { $1 ^ k[$0 % k.count] }
        return decode ? utf8(out) : out.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: codifiche

    static func utf8(_ b: [UInt8]) -> String { String(decoding: b, as: UTF8.self) }

    static func fromBase64(_ s: String, url: Bool) -> String {
        var t = s.filter { !$0.isWhitespace }
        if url { t = t.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") }
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        guard let d = Data(base64Encoded: t) else { return "Base64 non valido" }
        return String(decoding: d, as: UTF8.self)
    }

    static let b32 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    static func base32Encode(_ b: [UInt8]) -> String {
        var out = "", buf = 0, bits = 0
        for x in b { buf = (buf << 8) | Int(x); bits += 8
            while bits >= 5 { out.append(b32[(buf >> (bits - 5)) & 31]); bits -= 5 } }
        if bits > 0 { out.append(b32[(buf << (5 - bits)) & 31]) }
        while out.count % 8 != 0 { out.append("=") }
        return out
    }
    static func base32Decode(_ s: String) -> [UInt8]? {
        var out: [UInt8] = [], buf = 0, bits = 0
        for c in s.uppercased() where c != "=" && !c.isWhitespace {
            guard let v = b32.firstIndex(of: c) else { return nil }
            buf = (buf << 5) | v; bits += 5
            if bits >= 8 { out.append(UInt8((buf >> (bits - 8)) & 255)); bits -= 8 }
        }
        return out
    }

    static let b58 = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    static func base58Encode(_ b: [UInt8]) -> String {
        var digits: [Int] = [0]
        for x in b {
            var carry = Int(x)
            for i in 0..<digits.count { carry += digits[i] << 8; digits[i] = carry % 58; carry /= 58 }
            while carry > 0 { digits.append(carry % 58); carry /= 58 }
        }
        let zeros = b.prefix { $0 == 0 }.count
        return String(repeating: "1", count: zeros) + String(digits.reversed().drop { $0 == 0 && b.count > 0 }.map { b58[$0] })
    }
    static func base58Decode(_ s: String) -> [UInt8]? {
        var bytes: [Int] = [0]
        let t = s.filter { !$0.isWhitespace }
        for c in t {
            guard let v = b58.firstIndex(of: c) else { return nil }
            var carry = v
            for i in 0..<bytes.count { carry += bytes[i] * 58; bytes[i] = carry & 255; carry >>= 8 }
            while carry > 0 { bytes.append(carry & 255); carry >>= 8 }
        }
        let zeros = t.prefix { $0 == "1" }.count
        return [UInt8](repeating: 0, count: zeros) + bytes.reversed().drop { $0 == 0 }.map { UInt8($0) }
    }

    static func ascii85Encode(_ b: [UInt8]) -> String {
        var out = "<~"
        var i = 0
        while i < b.count {
            let chunk = Array(b[i..<min(i + 4, b.count)]), pad = 4 - chunk.count
            let v = (chunk + [UInt8](repeating: 0, count: pad)).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if v == 0 && pad == 0 { out += "z" } else {
                var cs = [Character](repeating: "!", count: 5), x = v
                for k in (0..<5).reversed() { cs[k] = Character(UnicodeScalar(UInt8(x % 85) + 33)); x /= 85 }
                out += String(cs.prefix(5 - pad))
            }
            i += 4
        }
        return out + "~>"
    }
    static func ascii85Decode(_ s: String) -> [UInt8]? {
        var t = s.filter { !$0.isWhitespace }
        if t.hasPrefix("<~") { t.removeFirst(2) }
        if t.hasSuffix("~>") { t.removeLast(2) }
        var out: [UInt8] = [], group: [UInt32] = []
        for c in t {
            if c == "z" && group.isEmpty { out += [0, 0, 0, 0]; continue }
            guard let a = c.asciiValue, a >= 33, a <= 117 else { return nil }
            group.append(UInt32(a - 33))
            if group.count == 5 {
                let v = group.reduce(UInt32(0)) { $0 &* 85 &+ $1 }
                out += [UInt8(v >> 24), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)]; group = []
            }
        }
        if !group.isEmpty {
            let pad = 5 - group.count
            let v = (group + [UInt32](repeating: 84, count: pad)).reduce(UInt32(0)) { $0 &* 85 &+ $1 }
            out += Array([UInt8(v >> 24), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)].prefix(4 - pad))
        }
        return out
    }

    static func hexBytes(_ s: String) -> [UInt8] {
        var t = s.replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: "\\x", with: "").filter(\.isHexDigit)
        if t.count % 2 == 1 { t = "0" + t }
        var out: [UInt8] = []
        var i = t.startIndex
        while i < t.endIndex {
            let j = t.index(i, offsetBy: 2)
            if let b = UInt8(t[i..<j], radix: 16) { out.append(b) }
            i = j
        }
        return out
    }

    /// Gruppi separati da spazi/virgole = un carattere ciascuno; senza separatori si taglia a blocchi di groupBits.
    static func fromRadix(_ s: String, _ radix: Int, groupBits: Int) -> String {
        let tokens = s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "|" }).map(String.init)
        let groups: [String]
        if tokens.count == 1, let t = tokens.first, t.count > groupBits {
            groups = stride(from: 0, to: t.count, by: groupBits).map { i in
                String(Array(t)[i..<min(i + groupBits, t.count)]) }
        } else { groups = tokens }
        let vals = groups.compactMap { UInt32($0, radix: radix) }
        if vals.allSatisfy({ $0 < 256 }) { return utf8(vals.map { UInt8($0) }) }
        return String(String.UnicodeScalarView(vals.compactMap { UnicodeScalar($0) }))
    }

    static func fromTokens(_ s: String, radix: Int) -> String {
        let vals = s.components(separatedBy: CharacterSet.alphanumerics.inverted).compactMap { UInt32($0, radix: radix) }
        if vals.allSatisfy({ $0 < 256 }) { return utf8(vals.map { UInt8($0) }) }
        return String(String.UnicodeScalarView(vals.compactMap { UnicodeScalar($0) }))
    }

    static let entita: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "agrave": "à", "egrave": "è", "eacute": "é", "igrave": "ì", "ograve": "ò", "ugrave": "ù", "Agrave": "À",
        "Egrave": "È", "Eacute": "É", "euro": "€", "copy": "©", "deg": "°"]

    static func htmlDecode(_ s: String) -> String {
        var out = s
        let re = try! NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            let body = (s as NSString).substring(with: m.range(at: 1))
            var rep: String?
            if body.hasPrefix("#x") { rep = UInt32(body.dropFirst(2), radix: 16).flatMap { UnicodeScalar($0) }.map { String($0) } }
            else if body.hasPrefix("#") { rep = UInt32(body.dropFirst()).flatMap { UnicodeScalar($0) }.map { String($0) } }
            else { rep = entita[body] }
            if let rep, let r = Range(m.range, in: out) { out.replaceSubrange(r, with: rep) }
        }
        return out
    }

    static func htmlEncode(_ s: String) -> String {
        s.unicodeScalars.map { u in
            switch u { case "&": return "&amp;"; case "<": return "&lt;"; case ">": return "&gt;"; case "\"": return "&quot;"; case "'": return "&#39;"
            default: return u.isASCII ? String(u) : "&#\(u.value);" }
        }.joined()
    }

    static func unicodeUnescape(_ s: String) -> String {
        var out = s
        let re = try! NSRegularExpression(pattern: #"\\u\{([0-9a-fA-F]+)\}|\\u([0-9a-fA-F]{4})|\\x([0-9a-fA-F]{2})|U\+([0-9a-fA-F]{4,6})"#)
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            let hex = (1...4).compactMap { i -> String? in
                let r = m.range(at: i); return r.location == NSNotFound ? nil : (s as NSString).substring(with: r) }.first ?? ""
            if let v = UInt32(hex, radix: 16), let u = UnicodeScalar(v), let r = Range(m.range, in: out) { out.replaceSubrange(r, with: String(u)) }
        }
        return out
    }

    static func qpDecode(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "")
        var bytes: [UInt8] = []
        var i = t.startIndex
        while i < t.endIndex {
            if t[i] == "=", let j = t.index(i, offsetBy: 3, limitedBy: t.endIndex), let b = UInt8(t[t.index(after: i)..<j], radix: 16) {
                bytes.append(b); i = j
            } else { bytes += Array(String(t[i]).utf8); i = t.index(after: i) }
        }
        return utf8(bytes)
    }

    static func qpEncode(_ s: String) -> String {
        s.utf8.map { b in (b >= 33 && b <= 126 && b != 61) || b == 32 ? String(UnicodeScalar(b)) : String(format: "=%02X", b) }.joined()
    }

    /// Punycode (RFC 3492) solo in decodifica, per etichette xn--.
    static func punyDecodeDomain(_ s: String) -> String {
        s.split(separator: ".", omittingEmptySubsequences: false).map { label -> String in
            let l = String(label)
            guard l.lowercased().hasPrefix("xn--") else { return l }
            return punyDecode(String(l.dropFirst(4))) ?? l
        }.joined(separator: ".")
    }

    static func punyDecode(_ input: String) -> String? {
        let base = 36, tmin = 1, tmax = 26, skew = 38, damp = 700
        var n = 128, i = 0, bias = 72
        var output: [UnicodeScalar] = []
        var rest = Substring(input)
        if let d = input.lastIndex(of: "-") {
            output = input[..<d].unicodeScalars.map { $0 }
            rest = input[input.index(after: d)...]
        }
        var chars = Array(rest.lowercased())
        func adapt(_ delta: Int, _ numPoints: Int, _ first: Bool) -> Int {
            var d = first ? delta / damp : delta / 2
            d += d / numPoints
            var k = 0
            while d > ((base - tmin) * tmax) / 2 { d /= base - tmin; k += base }
            return k + (base - tmin + 1) * d / (d + skew)
        }
        while !chars.isEmpty {
            let oldi = i
            var w = 1, k = base
            while true {
                guard !chars.isEmpty else { return nil }
                let c = chars.removeFirst()
                let digit: Int
                if let a = c.asciiValue, c.isLetter { digit = Int(a) - 97 } else if let v = c.wholeNumberValue { digit = v + 26 } else { return nil }
                i += digit * w
                let t = k <= bias ? tmin : (k >= bias + tmax ? tmax : k - bias)
                if digit < t { break }
                w *= base - t
                k += base
            }
            bias = adapt(i - oldi, output.count + 1, oldi == 0)
            n += i / (output.count + 1)
            i %= output.count + 1
            guard let u = UnicodeScalar(n) else { return nil }
            output.insert(u, at: i)
            i += 1
        }
        return String(String.UnicodeScalarView(output))
    }

    // Braille (grado 1, lettere minuscole; le cifre col segno di numero ⠼)
    static let brailleLetters: [Character: Character] = {
        let l = Array("abcdefghijklmnopqrstuvwxyz")
        let b = Array("⠁⠃⠉⠙⠑⠋⠛⠓⠊⠚⠅⠇⠍⠝⠕⠏⠟⠗⠎⠞⠥⠧⠺⠭⠽⠵")
        return Dictionary(uniqueKeysWithValues: zip(l, b))
    }()
    static let brailleExtra: [Character: Character] = [".": "⠲", ",": "⠂", "?": "⠦", "!": "⠖", "'": "⠄", "-": "⠤", ";": "⠆", ":": "⠒"]

    static func brailleEncode(_ s: String) -> String {
        var out = "", inNum = false
        for c in s.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            if let d = c.wholeNumberValue, c.isASCII {
                if !inNum { out.append("⠼"); inNum = true }
                out.append(brailleLetters[Array("jabcdefghi")[d]]!)
                continue
            }
            inNum = false
            if c == " " { out.append("⠀") } else if let b = brailleLetters[c] ?? brailleExtra[c] { out.append(b) } else { out.append(c) }
        }
        return out
    }

    static func brailleDecode(_ s: String) -> String {
        let rev = Dictionary(uniqueKeysWithValues: brailleLetters.map { ($1, $0) })
        let revX = Dictionary(uniqueKeysWithValues: brailleExtra.map { ($1, $0) })
        var out = "", inNum = false
        for c in s {
            if c == "⠼" { inNum = true; continue }
            if c == "⠀" || c == " " { out.append(" "); inNum = false; continue }
            if let l = rev[c] {
                if inNum, let i = Array("jabcdefghi").firstIndex(of: l) { out.append(Character(String(i))) } else { out.append(l); inNum = false }
            } else if let x = revX[c] { out.append(x); inNum = false } else { out.append(c) }
        }
        return out
    }

    static let natoWords = ["Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett", "Kilo",
                            "Lima", "Mike", "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
                            "Victor", "Whiskey", "X-ray", "Yankee", "Zulu"]
    static let italianWords = ["Ancona", "Bari", "Como", "Domodossola", "Empoli", "Firenze", "Genova", "Hotel", "Imola", "Jolly",
                               "Kappa", "Livorno", "Milano", "Napoli", "Otranto", "Palermo", "Quarto", "Roma", "Savona",
                               "Torino", "Udine", "Venezia", "Washington", "Xeres", "Yacht", "Zara"]
    static let digitWords = ["zero", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove"]

    static func natoEncode(_ s: String) -> String {
        s.uppercased().folding(options: .diacriticInsensitive, locale: nil).map { c -> String in
            if let i = Cipher.idx(c) { return natoWords[i] }
            if let d = c.wholeNumberValue { return digitWords[d] }
            return c == " " ? "/" : String(c)
        }.joined(separator: " ")
    }

    static func natoDecode(_ s: String) -> String {
        var map: [String: String] = [:]
        for (i, w) in natoWords.enumerated() { map[w.uppercased()] = String(Cipher.letter(i, upper: true)) }
        for (i, w) in italianWords.enumerated() { map[w.uppercased()] = String(Cipher.letter(i, upper: true)) }
        map["ALPHA"] = "A"; map["JULIET"] = "J"; map["XRAY"] = "X"; map["YORK"] = "Y"; map["ZETA"] = "Z"
        for (i, w) in digitWords.enumerated() { map[w.uppercased()] = String(i) }
        return s.components(separatedBy: "/").map { part in
            part.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map { w in
                let k = w.uppercased().replacingOccurrences(of: "-", with: "")
                return map[k] ?? map[w.uppercased()] ?? (w.count <= 1 ? String(w) : "?")
            }.joined()
        }.joined(separator: " ")
    }

    // MARK: lettere ↔ numeri

    static func numToLetters(_ s: String, base: Int, al: Alfabeto, reverse: Bool) -> String {
        let L = al.lettere, m = al.m
        return s.components(separatedBy: "/").map { word in
            word.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.map { v -> String in
                let i = v - base
                guard (0..<m).contains(i) else { return "[\(v)]" }
                return String(L[reverse ? m - 1 - i : i])
            }.joined()
        }.joined(separator: " ")
    }

    static func lettersToNum(_ s: String, base: Int, al: Alfabeto, reverse: Bool) -> String {
        s.split(separator: " ").map { w in
            w.compactMap { c -> String? in
                guard let i = letterIndex(c, al) else { return nil }
                return String((reverse ? al.m - 1 - i : i) + base)
            }.joined(separator: "-")
        }.joined(separator: " / ")
    }

    static func polybius(_ s: String, _ key: String, decode: Bool) -> String {
        let sq = square(key)
        if decode {
            let d = s.filter { $0 >= "1" && $0 <= "5" }.compactMap(\.wholeNumberValue)
            return String(stride(from: 0, to: d.count - d.count % 2, by: 2).map { sq[(d[$0] - 1) * 5 + d[$0 + 1] - 1] })
        }
        return s.split(separator: " ").map { w in
            cleanLetters(String(w)).map { c in let i = sq.firstIndex(of: c)!; return "\(i / 5 + 1)\(i % 5 + 1)" }.joined(separator: " ")
        }.joined(separator: " / ")
    }

    /// Tap code: griglia 5×5 con C=K. In ingresso accetta "1-3 2-4", "13 24" oppure gruppi di punti ". ...".
    static func tap(_ s: String, decode: Bool) -> String {
        let grid = Array("ABCDEFGHIJLMNOPQRSTUVWXYZ")
        if !decode {
            return cleanLetters(s.replacingOccurrences(of: "K", with: "C").replacingOccurrences(of: "k", with: "c")).map { c -> String in
                let ch: Character = c == "I" ? "I" : c
                guard let i = grid.firstIndex(of: ch) else { return "" }
                return String(repeating: ".", count: i / 5 + 1) + " " + String(repeating: ".", count: i % 5 + 1)
            }.joined(separator: "  ")
        }
        var nums: [Int]
        if s.contains(".") || s.contains("•") {
            let dots: String = s.replacingOccurrences(of: "•", with: ".")
            nums = dots.split(whereSeparator: { (c: Character) -> Bool in c != "." }).map { (g: Substring) -> Int in g.count }
        } else {
            nums = s.compactMap(\.wholeNumberValue)
        }
        nums = nums.filter { (1...5).contains($0) }
        return String(stride(from: 0, to: nums.count - nums.count % 2, by: 2).map { grid[(nums[$0] - 1) * 5 + nums[$0 + 1] - 1] })
    }

    static func baconEncode(_ s: String) -> String {
        s.uppercased().folding(options: .diacriticInsensitive, locale: nil).compactMap { c -> String? in
            guard let i = Cipher.idx(c) else { return c == " " ? "/" : nil }
            return String(String(i, radix: 2).leftPad(5).map { $0 == "0" ? "A" : "B" })
        }.joined(separator: " ")
    }

    static func baconDecode(_ s: String) -> String {
        let r = Cipher.bacon(s).components(separatedBy: "\n")
        return r.prefix(2).joined(separator: "\n")
    }

    static let tasti: [Character: String] = ["2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL", "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ"]

    static func multitapDecode(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "-" }).map { g -> String in
            if g == "0" || g == "/" { return " " }
            guard let k = g.first, g.allSatisfy({ $0 == k }), let letters = tasti[k] else { return "?" }
            let a = Array(letters)
            return String(a[(g.count - 1) % a.count])
        }.joined()
    }

    static func multitapEncode(_ s: String) -> String {
        s.uppercased().folding(options: .diacriticInsensitive, locale: nil).compactMap { c -> String? in
            if c == " " { return "0" }
            for (k, v) in tasti { if let i = v.firstIndex(of: c) { return String(repeating: k, count: v.distance(from: v.startIndex, to: i) + 1) } }
            return nil
        }.joined(separator: " ")
    }

    static func t9Encode(_ s: String) -> String {
        s.uppercased().folding(options: .diacriticInsensitive, locale: nil).map { c -> String in
            if c == " " { return " " }
            for (k, v) in tasti where v.contains(c) { return String(k) }
            return String(c)
        }.joined()
    }

    static let romani: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                          (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]

    static func romanEncode(_ s: String) -> String {
        s.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.map { n -> String in
            guard n > 0 && n < 4000 else { return "[\(n)]" }
            var x = n, out = ""
            for (v, r) in romani { while x >= v { out += r; x -= v } }
            return out
        }.joined(separator: " ")
    }

    static func romanDecode(_ s: String) -> String {
        let val: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        return s.uppercased().split(whereSeparator: { !"IVXLCDM".contains($0) }).map { w -> String in
            let v = w.compactMap { val[$0] }
            var tot = 0
            for (i, x) in v.enumerated() { tot += i + 1 < v.count && v[i + 1] > x ? -x : x }
            return String(tot)
        }.joined(separator: " ")
    }

    static let unita = ["zero", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove", "dieci", "undici",
                        "dodici", "tredici", "quattordici", "quindici", "sedici", "diciassette", "diciotto", "diciannove"]
    static let decine = ["", "", "venti", "trenta", "quaranta", "cinquanta", "sessanta", "settanta", "ottanta", "novanta"]

    static func inParole(_ n: Int) -> String {
        if n < 20 { return unita[n] }
        if n < 100 {
            let d = decine[n / 10], u = n % 10
            if u == 0 { return d }
            let base = (u == 1 || u == 8) ? String(d.dropLast()) : d
            return base + (u == 3 ? "tré" : unita[u])
        }
        if n < 1000 {
            let c = n / 100, r = n % 100
            return (c == 1 ? "cento" : unita[c] + "cento") + (r == 0 ? "" : (r / 10 == 8 ? String(inParole(r)) : inParole(r)))
        }
        if n < 1_000_000 {
            let m = n / 1000, r = n % 1000
            return (m == 1 ? "mille" : inParole(m) + "mila") + (r == 0 ? "" : inParole(r))
        }
        return String(n)
    }

    static func numToParole(_ s: String) -> String {
        s.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.map(inParole).joined(separator: " ")
    }

    static func paroleToNum(_ s: String) -> String {
        var map: [String: Int] = [:]
        for n in 0..<1000 { map[inParole(n)] = n }
        return s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: { !$0.isLetter }).map { w -> String in
                let k = String(w).replacingOccurrences(of: "tre", with: "tre")
                if let v = map[k] ?? map[k.replacingOccurrences(of: "tre", with: "tré")] { return String(v) }
                return "?"
            }.joined(separator: " ")
    }

    // MARK: testo e numeri

    static func replace(_ s: String, _ rules: String) -> String {
        var out = s
        for r in rules.components(separatedBy: CharacterSet(charactersIn: ",;\n")) {
            let parts = r.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let a = parts[0].trimmingCharacters(in: .whitespaces), b = parts[1].trimmingCharacters(in: .whitespaces)
            if !a.isEmpty { out = out.replacingOccurrences(of: a, with: "\u{1}" + b + "\u{2}") }
        }
        return out.replacingOccurrences(of: "\u{1}", with: "").replacingOccurrences(of: "\u{2}", with: "")
    }

    static func baseConv(_ s: String, from: Int, to: Int) -> String {
        guard (2...36).contains(from), (2...36).contains(to) else { return "Basi da 2 a 36" }
        return s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map { t in
            UInt64(t.lowercased(), radix: from).map { String($0, radix: to).uppercased() } ?? "?"
        }.joined(separator: " ")
    }

    static func unixToDate(_ s: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        return s.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }.map { v in
            f.string(from: Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v)) + " (ora italiana)"
        }.joined(separator: "\n")
    }

    static func dateToUnix(_ s: String) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        for fmt in ["dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines)) { return String(Int(d.timeIntervalSince1970)) }
        }
        return "Scrivi la data come 14/11/2026 08:00"
    }

    static func crc32(_ b: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for x in b {
            c ^= UInt32(x)
            for _ in 0..<8 { c = (c & 1) == 1 ? (c >> 1) ^ 0xEDB88320 : c >> 1 }
        }
        return ~c
    }
}

// MARK: - Enigma M3 (rotori I–V, riflettore B)

struct Enigma {
    static let rotori: [String: (String, Character)] = [
        "I": ("EKMFLGDQVZNTOWYHXUSPAIBRCJ", "Q"), "II": ("AJDKSIRUXBLHWTMCQGZNPYFVOE", "E"),
        "III": ("BDFHJLCPRTXVZNYEIWGAKMUSQO", "V"), "IV": ("ESOVPZJAYQUIRHXLNFTGKDCMWB", "J"),
        "V": ("VZBRGITYUPSDNHLXAWMJQOFECK", "Z")]
    static let riflettoreB = Array("YRUHQSLDPXNGOKMIEBFZCWVJAT")

    var wiring: [[Int]] = [], notch: [Int] = [], ring: [Int] = [], pos: [Int] = []
    var plug = Array(0..<26)

    init?(config: String) {
        let parts = config.uppercased().split(separator: " ").map(String.init)
        guard parts.count >= 3 else { return nil }
        for r in parts.prefix(3) {
            guard let w = Self.rotori[r] else { return nil }
            wiring.append(w.0.map { Int($0.asciiValue! - 65) })
            notch.append(Int(w.1.asciiValue! - 65))
        }
        let letters = { (s: String) -> [Int]? in
            let v = s.compactMap { $0.asciiValue }.map { Int($0) - 65 }
            return v.count == 3 && v.allSatisfy { (0..<26).contains($0) } ? v : nil
        }
        ring = parts.count > 3 ? (letters(parts[3]) ?? [0, 0, 0]) : [0, 0, 0]
        pos = parts.count > 4 ? (letters(parts[4]) ?? [0, 0, 0]) : [0, 0, 0]
        for pair in parts.dropFirst(5) where pair.count == 2 && pair.allSatisfy({ $0.isASCII && $0.isLetter }) {
            let a = Int(pair.first!.asciiValue!) - 65, b = Int(pair.last!.asciiValue!) - 65
            guard (0..<26).contains(a), (0..<26).contains(b) else { continue }
            plug[a] = b; plug[b] = a
        }
    }

    func through(_ c: Int, _ r: Int, back: Bool) -> Int {
        let shift = pos[r] - ring[r]
        let x = (c + shift + 26) % 26
        let y = back ? wiring[r].firstIndex(of: x)! : wiring[r][x]
        return (y - shift + 26) % 26
    }

    mutating func run(_ s: String) -> String {
        var out = ""
        for ch in s {
            guard let i = Cipher.idx(ch) else { out.append(ch); continue }
            // passo dei rotori (con il doppio passo del centrale)
            if pos[1] == notch[1] { pos[1] = (pos[1] + 1) % 26; pos[0] = (pos[0] + 1) % 26 }
            else if pos[2] == notch[2] { pos[1] = (pos[1] + 1) % 26 }
            pos[2] = (pos[2] + 1) % 26
            var c = plug[i]
            for r in [2, 1, 0] { c = through(c, r, back: false) }
            c = Int(Self.riflettoreB[c].asciiValue! - 65)
            for r in [0, 1, 2] { c = through(c, r, back: true) }
            c = plug[c]
            out.append(Cipher.letter(c, upper: ch.isUppercase))
        }
        return out
    }
}

// MARK: - Catena di passaggi

struct ChainStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var op: Op
    var encode: Bool
    var params: OpParams

    var etichetta: String {
        var s = op.titolo
        if !op.unSoloVerso { s += encode ? " · cifra" : " · decifra" }
        if let n = op.usaN { s += " \(n.lowercased()) \(params.n)" }
        if let n2 = op.usaN2 { s += " \(n2.lowercased()) \(params.n2)" }
        if op.usaChiave != nil, !params.key.isEmpty { s += " «\(params.key)»" }
        if op.usaAlfabeto && params.alfabeto == .it21 { s += " (21)" }
        return s
    }

    func run(_ s: String) -> String { Codec.apply(op, s, params, encode: encode) }
}

enum Chain {
    static func run(_ steps: [ChainStep], _ input: String) -> [String] {
        var out: [String] = []
        var cur = input
        for st in steps { cur = st.run(cur); out.append(cur) }
        return out
    }
}
