import Foundation

/// Comprueba la letra o el dígito de control de un NIF español: DNI, NIE o CIF (spec del perfil, §5). Solo sirve para
/// avisar: un NIF que no cuadra se puede guardar igual.
public enum SpanishTaxID {
    private static let dniLetters = Array("TRWAGMYFPDXBNJZSQVHLCKE")
    private static let cifControlLetters = Array("JABCDEFGHI")
    private static let cifInitials = Set("ABCDEFGHJNPQRSUVW")

    /// En mayúsculas, sin espacios, guiones ni puntos, y sin el prefijo «ES» del NIF-IVA.
    public static func normalized(_ value: String) -> String {
        var text = String(value.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
        if text.count == 11, text.hasPrefix("ES") { text.removeFirst(2) }
        return text
    }

    public static func isValid(_ value: String) -> Bool {
        let text = Array(normalized(value))
        guard text.count == 9, text[1...7].allSatisfy(\.isNumber) else { return false }
        let first = text[0], last = text[8]
        let digits = String(text[1...7])
        switch first {
        case "0"..."9":
            return dniLetter(String(text[0...7])) == last
        case "X", "Y", "Z":
            let prefix = first == "X" ? "0" : first == "Y" ? "1" : "2"
            return dniLetter(prefix + digits) == last
        case "K", "L", "M":
            return dniLetter(digits) == last
        case _ where cifInitials.contains(first):
            var sum = 0
            for (index, character) in digits.enumerated() {
                let digit = character.wholeNumberValue ?? 0
                if index % 2 == 0 {
                    let doubled = digit * 2
                    sum += doubled / 10 + doubled % 10
                } else {
                    sum += digit
                }
            }
            let control = (10 - sum % 10) % 10
            return last == Character(String(control)) || last == cifControlLetters[control]
        default:
            return false
        }
    }

    private static func dniLetter(_ number: String) -> Character? {
        guard let value = Int(number) else { return nil }
        return dniLetters[value % 23]
    }
}
