import Foundation

/// Un socio o un miembro del hogar. Su nombre es su carpeta (spec del perfil, §2).
public struct ProfilePerson: Equatable, Sendable {
    public var name: String
    public var taxID: String?

    public init(name: String, taxID: String? = nil) {
        self.name = name
        self.taxID = taxID
    }
}

/// Un cliente habitual, con el nombre corto que se usa en carpetas y nombres.
public struct ProfileClient: Equatable, Sendable {
    public var name: String
    public var short: String?

    public init(name: String, short: String? = nil) {
        self.name = name
        self.short = short
    }
}

/// Un banco, con los últimos dígitos de la cuenta: nunca el IBAN entero (spec del perfil, §7).
public struct ProfileBank: Equatable, Sendable {
    public var name: String
    public var accountEnd: String?

    public init(name: String, accountEnd: String? = nil) {
        self.name = name
        self.accountEnd = accountEnd
    }
}

/// Un vehículo: su nombre corto es el que llevan los documentos («Coche - ITV - …»).
public struct ProfileVehicle: Equatable, Sendable {
    public var short: String
    public var plate: String?

    public init(short: String, plate: String? = nil) {
        self.short = short
        self.plate = plate
    }
}

public struct ProfileHome: Equatable, Sendable {
    public var short: String
    public var address: String?

    public init(short: String, address: String? = nil) {
        self.short = short
        self.address = address
    }
}

/// Una clave de la cabecera que Tria no conoce: se conserva tal cual al guardar y se envía (spec del perfil, §2).
public struct ProfileExtra: Equatable, Sendable {
    public var key: String
    /// La clave y su valor en YAML, listos para volver a escribirse.
    public var yaml: String

    public init(key: String, yaml: String) {
        self.key = key
        self.yaml = yaml
    }
}

/// Los campos del perfil con su clave en `PERFIL.md`.
public enum ProfileField: String, CaseIterable, Sendable {
    case name
    case taxID = "tax_id"
    case tradeNames = "trade_names"
    case partners, clients, banks, members, vehicles, homes

    /// Los campos de cada tipo, en el orden en que se escriben (spec del perfil, §2).
    public static func fields(for kind: TemplateKind) -> [ProfileField] {
        switch kind {
        case .autonomo: [.name, .taxID, .tradeNames, .clients, .banks]
        case .sl: [.name, .taxID, .tradeNames, .partners, .clients, .banks]
        case .hogar: [.members, .vehicles, .homes, .banks]
        }
    }
}

/// Quién es el titular del espacio, tal como lo dice `PERFIL.md` (spec del perfil, §2). Guarda también los campos de
/// otros tipos y las claves desconocidas, para no perderlos al escribir.
public struct Profile: Equatable, Sendable {
    public var kind: TemplateKind
    public var name: String?
    public var taxID: String?
    public var tradeNames: [String] = []
    public var partners: [ProfilePerson] = []
    public var clients: [ProfileClient] = []
    public var banks: [ProfileBank] = []
    public var members: [ProfilePerson] = []
    public var vehicles: [ProfileVehicle] = []
    public var homes: [ProfileHome] = []
    /// El cuerpo, debajo de la cabecera: notas libres.
    public var notes: String = ""
    public var extras: [ProfileExtra] = []

    public init(kind: TemplateKind, name: String? = nil, taxID: String? = nil) {
        self.kind = kind
        self.name = name
        self.taxID = taxID
    }

    /// Lo que falta para el mínimo: nombre y NIF en Autónomo y SL; un miembro en Hogar.
    public var missing: [ProfileField] {
        switch kind {
        case .autonomo, .sl: [ProfileField.name, .taxID].filter { !hasValue($0) }
        case .hogar: hasValue(.members) ? [] : [.members]
        }
    }

    public var isComplete: Bool { missing.isEmpty }

    public func hasValue(_ field: ProfileField) -> Bool {
        switch field {
        case .name: !(name ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .taxID: !(taxID ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .tradeNames: !tradeNames.isEmpty
        case .partners: !partners.isEmpty
        case .clients: !clients.isEmpty
        case .banks: !banks.isEmpty
        case .members: !members.isEmpty
        case .vehicles: !vehicles.isEmpty
        case .homes: !homes.isEmpty
        }
    }
}
