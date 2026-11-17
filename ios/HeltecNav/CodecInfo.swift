import Foundation

/// Spiegazioni (pulsante ⓘ): come funziona, esempio, quando sospettarlo.
extension Op {
    var spiegazione: (come: String, esempio: String, indizi: String) {
        switch self {
        case .caesar:
            return ("Ogni lettera viene spostata avanti di N posizioni nell'alfabeto (in fondo si ricomincia da A). Per decifrare si torna indietro di N. Con l'alfabeto italiano a 21 lettere J K W X Y restano uguali.",
                    "N=3: CIAO → FLDR",
                    "Testo fatto solo di lettere, parole di lunghezza normale ma illeggibili. Le lettere più frequenti non sono E A I O. La decifratura automatica prova tutti gli spostamenti.")
        case .rot13:
            return ("Cesare con spostamento 13: siccome 13+13=26, la stessa operazione cifra e decifra.", "CIAO → PVNB", "Tipico di forum e giochi informatici.")
        case .rot5:
            return ("Sposta solo le cifre di 5 (0↔5, 1↔6…). Le lettere restano uguali.", "1234 → 6789", "Numeri che sembrano sbagliati di poco, codici a 4 cifre.")
        case .rot18:
            return ("ROT13 sulle lettere + ROT5 sulle cifre.", "ORO16 → BEB61", "Testo misto lettere e numeri.")
        case .rot47:
            return ("Ruota di 47 tutti i caratteri ASCII stampabili (lettere, cifre e simboli, da ! a ~). Si cifra e decifra allo stesso modo.", "Ciao → r:2@", "Testo pieno di simboli strani come { } ~ @ ma senza spazi strani.")
        case .atbash:
            return ("L'alfabeto viene ribaltato: A↔Z, B↔Y, C↔X… Cifra e decifra sono la stessa operazione. Antichissimo (ebraico).", "ORO → LIL", "Testo con molte Z, Y, X, V. Contesto biblico o esoterico.")
        case .affine:
            return ("Ogni lettera x (A=0) diventa a·x + b, modulo 26. 'a' deve essere coprimo con 26 (1,3,5,7,9,11,15,17,19,21,23,25). Cesare è il caso a=1.", "a=5 b=8: ORO → APA", "Come Cesare ma nessuno spostamento funziona. La decifratura automatica prova tutte le combinazioni.")
        case .vigenere:
            return ("Cesare con uno spostamento diverso per ogni lettera, dato dalla parola chiave ripetuta (A=0, B=1…). Senza la chiave è difficile.", "Chiave LORN: ATTACCO → LHKNNQF", "Frequenze delle lettere 'piatte'. Serve una parola chiave: prova quelle della gara (LORN, ORO, MIDA, OBELISCUS…).")
        case .beaufort:
            return ("Variante di Vigenère: lettera cifrata = chiave − testo. Cifra e decifra sono la stessa operazione.", "Chiave ORO: CIAO → MJOA", "Se Vigenère con la chiave giusta non funziona, prova Beaufort.")
        case .autokey:
            return ("Vigenère in cui, dopo la chiave, si usa come chiave il testo in chiaro stesso. Non si ripete mai.", "Chiave ORO: ATTACCO → OKHAVVO", "Come Vigenère, ma solo l'inizio si decifra con la chiave normale.")
        case .gronsfeld:
            return ("Vigenère con chiave fatta di cifre: ogni cifra è lo spostamento (0–9).", "Chiave 1215: CIAO → DKBT", "Codici numerici dati insieme a un testo cifrato, date (14111926).")
        case .keyword:
            return ("Si scrive la parola chiave senza lettere doppie e poi il resto dell'alfabeto: è il nuovo alfabeto. A diventa la prima lettera, B la seconda…", "Chiave ORO → alfabeto ORABCDEF…: CIAO → AGOM", "Sostituzione semplice: lettere sempre uguali, ma non è uno spostamento.")
        case .playfair:
            return ("Griglia 5×5 con la chiave (J=I). Il testo si divide in coppie: stessa riga → lettere a destra; stessa colonna → sotto; altrimenti gli angoli opposti del rettangolo.", "Chiave LORN: OBIETTIVO → coppie OB IE TX TI VO", "Testo con numero pari di lettere, senza J, senza coppie di lettere doppie (XX in mezzo).")
        case .bifid:
            return ("Griglia di Polibio 5×5 con la chiave: si scrivono riga e colonna di ogni lettera, si mescolano e si rileggono a coppie.", "—", "Testo senza J, lettere che non seguono le frequenze italiane.")
        case .railfence:
            return ("Le lettere si scrivono a zig-zag su N righe (binari) e poi si leggono riga per riga. Le lettere sono quelle giuste ma in ordine sbagliato.", "3 binari: ATTACCO → ACTACTO", "Anagramma: le frequenze sono italiane normali ma il testo è mescolato.")
        case .scytale:
            return ("Il testo si scrive in righe da N lettere (come su un bastone avvolto) e si legge per colonne.", "4 colonne: ATTACCOALBA → ACLTCBTOAAA", "Anagramma regolare: una lettera ogni N forma parole.")
        case .columnar:
            return ("Il testo si scrive in righe lunghe quanto la chiave, poi le colonne si leggono nell'ordine alfabetico delle lettere della chiave.", "Chiave ORO: le colonne si leggono nell'ordine O(1) R(3) O(2)", "Anagramma, spesso a gruppi della stessa lunghezza.")
        case .xor:
            return ("Ogni byte del testo viene combinato con la chiave con l'operazione XOR; rifacendo XOR con la stessa chiave si torna indietro. Il risultato si scrive di solito in esadecimale.", "—", "Esadecimale che decodificato dà caratteri senza senso.")
        case .enigma:
            return ("Simulazione della macchina tedesca Enigma M3 (riflettore B): 3 rotori scelti tra I–V, posizione degli anelli, posizione di partenza e collegamenti del pannello (coppie di lettere). Cifra e decifra sono uguali.", "I II III AAA AAA: AAAAA → BDZGO", "Contesto militare WWII, configurazione data in un foglio a parte.")
        case .base64:
            return ("Trasforma i byte in 64 simboli (A–Z a–z 0–9 + /), a gruppi di 4; spesso finisce con = o ==.", "ORO → T1JP", "Lettere maiuscole e minuscole mescolate con cifre, + /, lunghezza multipla di 4, = in fondo.")
        case .base64url:
            return ("Come Base64 ma con - e _ al posto di + e /, di solito senza = finali. Si usa negli indirizzi web.", "—", "Base64 con - e _.")
        case .base32:
            return ("Byte scritti con 32 simboli: A–Z e 2–7, a gruppi di 8 con = finali.", "ORO → J5JE6===", "Solo maiuscole e cifre da 2 a 7, molti = in fondo.")
        case .base58:
            return ("Come Base64 ma senza i caratteri che si confondono (0 O I l) e senza simboli. Usato per Bitcoin.", "—", "Lettere e cifre miste senza 0, O, I, l.")
        case .ascii85:
            return ("Byte a gruppi di 4 scritti con 5 caratteri ASCII (da ! a u). Spesso tra <~ e ~>.", "—", "Testo denso di simboli e punteggiatura, a volte tra <~ ~>.")
        case .hex:
            return ("Ogni byte scritto con due cifre esadecimali (0–9, A–F).", "ORO → 4F 52 4F", "Solo 0–9 e A–F, in coppie. 4x/5x = maiuscole, 6x/7x = minuscole, 20 = spazio.")
        case .binary:
            return ("Ogni carattere scritto in base 2, di solito a gruppi di 8 bit (ASCII). Con 5 bit spesso A=1.", "A → 01000001", "Solo 0 e 1. Gruppi da 8 che iniziano con 01 = lettere.")
        case .octal:
            return ("Codice di ogni carattere scritto in base 8.", "A → 101", "Numeri con sole cifre 0–7, intorno a 101–172.")
        case .decimal:
            return ("Codice ASCII/Unicode di ogni carattere in base 10.", "ORO → 79 82 79", "Numeri tra 32 e 126 (65–90 maiuscole, 97–122 minuscole).")
        case .url:
            return ("I caratteri speciali di un indirizzo web diventano %XX (esadecimale); lo spazio a volte diventa +.", "è → %C3%A8", "Testo con molti %.")
        case .html:
            return ("Caratteri scritti come entità HTML: &amp; &lt; &#233; &#xE9;.", "è → &egrave; o &#232;", "Testo con & e ; ripetuti.")
        case .unicodeEsc:
            return ("Caratteri scritti con il loro codice Unicode: \\u00E8, \\x41, U+00E8.", "è → \\u00E8", "Testo con \\u e cifre esadecimali.")
        case .quotedPrintable:
            return ("Usato nelle email: i caratteri non ASCII diventano =XX.", "è → =C3=A8", "Testo leggibile con molti =XX.")
        case .punycodeLite:
            return ("Nomi di dominio con accenti scritti in ASCII, iniziano con xn--.", "xn--citt-6na → città", "Indirizzi che cominciano con xn--.")
        case .morse:
            return ("Ogni lettera è una sequenza di punti e linee. Lettere separate da spazio, parole da /. Riconosce anche punteggiatura e À È É Ò.", "SOS → ... --- ...", "Punti, linee, trattini, suoni brevi e lunghi, luci che lampeggiano (vedi strumento Morse).")
        case .braille:
            return ("Caratteri Braille Unicode (6 punti). Le cifre sono precedute dal segno di numero ⠼.", "oro → ⠕⠗⠕", "Simboli fatti di puntini ⠿, o rilievi su un oggetto: ricopiali punto per punto.")
        case .nato:
            return ("Ogni lettera è una parola: alfabeto NATO (Alfa, Bravo…) o italiano (Ancona, Bari, Como…). Si decodificano entrambi.", "ORO → Oscar Romeo Oscar", "Elenco di città italiane o parole radio.")
        case .a1z26:
            return ("Ogni lettera è la sua posizione: A=1, B=2 … Z=26 (o fino a 21 con l'alfabeto italiano).", "ORO → 15-18-15", "Numeri tutti tra 1 e 26.")
        case .a0z25:
            return ("Come A=1 ma si parte da zero: A=0 … Z=25.", "ORO → 14-17-14", "Numeri tra 0 e 25, compare lo 0.")
        case .z1a26:
            return ("Alfabeto al contrario: Z=1, Y=2 … A=26.", "ORO → 12-9-12", "Numeri 1–26 che con A=1 non danno nulla.")
        case .polybius:
            return ("Griglia 5×5 (I e J insieme): ogni lettera diventa riga+colonna. Con una chiave la griglia si riempie prima con la chiave.", "ORO → 34 42 34", "Coppie di cifre tutte tra 1 e 5.")
        case .tapcode:
            return ("Codice dei prigionieri: griglia 5×5 (C=K), si battono N colpi per la riga e N per la colonna.", "A → . .   B → . ..", "Colpi, punti o luci a coppie di gruppi, numeri tra 1 e 5.")
        case .bacon:
            return ("Ogni lettera diventa 5 simboli A/B (come 5 bit). Esiste la versione a 24 lettere (I=J, U=V).", "A → AAAAA, B → AAAAB", "Sequenze di due soli simboli (A/B, 0/1, due font diversi, maiuscole/minuscole).")
        case .baconCase:
            return ("Bacone nascosto in un testo normale: ogni lettera conta come A o B a seconda che sia minuscola o maiuscola (o viceversa).", "—", "Testo con maiuscole messe a caso in mezzo alle parole.")
        case .multitap:
            return ("Vecchia tastiera del telefono: il tasto si preme tante volte quanto la posizione della lettera (2=ABC: 2=A, 22=B, 222=C). 0 = spazio.", "ORO → 666 777 666", "Gruppi di cifre ripetute uguali, solo 2–9.")
        case .t9:
            return ("Un tasto per lettera (2=ABC, 3=DEF… 9=WXYZ). Non si decodifica in modo unico: utile per trasformare una parola in un codice numerico.", "ORO → 676", "Codici numerici di lucchetti che 'corrispondono' a una parola.")
        case .roman:
            return ("Numeri romani I V X L C D M e il loro valore.", "MMXXVI → 2026", "Lettere solo tra I V X L C D M.")
        case .numeriParole:
            return ("Numeri scritti in italiano ↔ cifre.", "quattordici → 14", "Numeri nascosti in un testo.")
        case .reverse:
            return ("Il testo letto da destra a sinistra.", "ORO MIDA → ADIM ORO", "Parole che hanno senso lette al contrario.")
        case .reverseWords:
            return ("Ogni parola rovesciata, l'ordine delle parole resta.", "RE MIDA → ER ADIM", "Usato nell'invito dell'Ordo (con Cesare 12).")
        case .reverseOrder:
            return ("Le parole restano scritte uguali ma in ordine inverso.", "uno due tre → tre due uno", "Frasi che 'suonano' al contrario.")
        case .upper, .lower, .swapCase:
            return ("Cambia maiuscole e minuscole.", "—", "Prima di altri passaggi, per uniformare.")
        case .removeSpaces:
            return ("Toglie spazi e punteggiatura, restano lettere e cifre.", "—", "Prima di trasposizioni e cifrari a griglia.")
        case .removeAccents:
            return ("à→a, è→e… Utile perché molti cifrari usano solo A–Z.", "—", "Testi italiani prima di cifrare.")
        case .onlyLetters:
            return ("Restano solo le lettere.", "—", "Pulizia.")
        case .initials:
            return ("La prima lettera di ogni parola (acrostico).", "Ogni Roccia Oscura → ORO", "Poesie, elenchi, frasi un po' forzate.")
        case .finals:
            return ("L'ultima lettera di ogni parola.", "—", "Usato nel promemoria dell'Ordo (LUX ET VERITAS).")
        case .lastWords:
            return ("L'ultima parola di ogni frase, con iniziali e finali.", "—", "Testi con frasi che finiscono in modo strano (parole spurie).")
        case .onlyUpper:
            return ("Restano solo le lettere maiuscole.", "—", "Maiuscole fuori posto in un testo (come LORN nell'OPORD).")
        case .onlyLower:
            return ("Restano solo le minuscole.", "—", "Testo tutto maiuscolo con qualche minuscola.")
        case .nthLetter:
            return ("Prende una lettera ogni N, partendo dalla posizione indicata.", "Ogni 2 da 1: OXRXOX → ORO", "Testo lungo con un messaggio 'a passo fisso'.")
        case .swapPairs:
            return ("Scambia le lettere a due a due.", "ROO → ORO", "Anagramma leggero.")
        case .replace:
            return ("Sostituisce pezzi di testo secondo le regole che scrivi (X=E, Q=A …). Per risolvere a mano le sostituzioni.", "—", "Quando hai capito alcune lettere e vuoi provare le altre.")
        case .frequencies:
            return ("Conta quante volte compare ogni lettera e la confronta con l'italiano (E A I O le più frequenti). χ² basso = somiglia all'italiano.", "—", "Per capire se è sostituzione (frequenze spostate) o trasposizione (frequenze normali).")
        case .count:
            return ("Conta caratteri, lettere, cifre, parole e righe.", "—", "Lunghezze multiple di 4, 5, 8 suggeriscono Base64, Bacone, binario.")
        case .baseConv:
            return ("Converte numeri da una base a un'altra (2 = binario, 8 = ottale, 10 = decimale, 16 = esadecimale, fino a 36).", "Da 10 a 2: 14 → 1110", "Numeri strani, codici di lucchetti.")
        case .unixTime:
            return ("Secondi dal 1/1/1970: decodifica → data e ora italiana; codifica → da data a numero.", "1794610800 → 14/11/2026 00:00", "Numeri di 10 cifre che cominciano con 17.")
        case .md5, .sha1, .sha256, .sha512:
            return ("Impronta (hash) del testo: non si può tornare indietro, ma puoi verificare se una parola dà proprio quell'impronta.", "—", "Stringhe esadecimali lunghe 32 (MD5), 40 (SHA-1), 64 (SHA-256), 128 (SHA-512).")
        case .crc32:
            return ("Somma di controllo a 8 cifre esadecimali.", "—", "Codici di 8 caratteri esadecimali.")
        }
    }
}
