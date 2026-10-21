enum TemplatesCA {
    static let autonomoFolders = [
        "1-Factures Emeses", "2-Factures Rebudes", "3-Impostos", "4-Seguretat Social", "5-Bancs",
        "6-Contractes i Clients", "7-Assegurances", "8-Certificats", "9-Administracio",
    ]

    static let autonomo = """
    ---
    inbox: "99-Pendent"
    duplicates: "98-Duplicats"
    protected: []
    new_folders: subfolders_only
    ---
    # Organització de documents — Autònom

    La Tria llegeix cada document de `99-Pendent/`, decideix la carpeta i li posa nom segons aquestes regles. Si té dubtes, el deixa pendent.

    ## Carpetes

    | Carpeta | Contingut |
    |---|---|
    | `1-Factures Emeses/` | Factures que emeto als meus clients. Subcarpetes `AAAA/1T`…`4T` segons la data de la factura. |
    | `2-Factures Rebudes/` | Factures i tiquets de proveïdors i despeses. Subcarpetes `AAAA/1T`…`4T` segons la data de la factura. |
    | `3-Impostos/` | Models de l'AEAT, una subcarpeta per model: `Model 130`, `Model 303`, `Model 390`, `Model 100 - Renda`, `Altres Models`. |
    | `4-Seguretat Social/` | Quotes d'autònom (RETA), resolucions, altes i baixes. |
    | `5-Bancs/` | Extractes, cartes i comunicacions bancàries. |
    | `6-Contractes i Clients/` | Contractes, pressupostos i documentació de clients. |
    | `7-Assegurances/` | Pòlisses i rebuts d'assegurances. |
    | `8-Certificats/` | Certificats de l'AEAT, la Seguretat Social, bancs i retencions. |
    | `9-Administracio/` | Altres organismes: ajuntament, DGT, subministraments i notificacions. |

    ## Nomenclatura

    Dates `AAAA-MM-DD` (o `AAAA-MM` si només consta el mes). Sense accents ni caràcters especials als noms. Es conserva l'extensió original.

    | Tipus | Format | Exemple |
    |---|---|---|
    | Factura emesa | `Factura Emesa [Numero] [Client] - AAAA-MM-DD` | `Factura Emesa 2025-014 Estudi Nord - 2025-05-02.pdf` |
    | Factura rebuda | `Factura [Proveidor] - AAAA-MM-DD` | `Factura Papereria Mar - 2025-03-14.pdf` |
    | Model AEAT | `Model XXX - AAAA - TT` (TT = `1T`…`4T`; els anuals, sense TT) | `Model 303 - 2025 - 1T.pdf` |
    | Seguretat Social | `Seguretat Social - [Assumpte] - AAAA-MM` | `Seguretat Social - Quota RETA - 2025-02.pdf` |
    | Banc | `[Banc] - [Assumpte] - AAAA-MM-DD` | `Banc Exemple - Extracte - 2025-01-31.pdf` |
    | Contracte | `Contracte [Tipus] [Empresa] - AAAA-MM` | `Contracte Serveis Estudi Nord - 2025-01.pdf` |
    | Assegurança | `Asseguranca [Tipus] [Companyia] - AAAA` | `Asseguranca Responsabilitat Civil Asseguradora Sud - 2025.pdf` |
    | Certificat | `Certificat [Que] [Organisme] - AAAA-MM-DD` | `Certificat Corrent Pagament AEAT - 2025-07-01.pdf` |
    | Altres organismes | `[Organisme] - [Assumpte] - AAAA-MM-DD` | `Ajuntament - Rebut IBI - 2025-06-15.pdf` |

    ## Casos especials

    - Una factura és **emesa** si l'emissor és el titular del perfil (el seu nom, un nom comercial o el seu NIF apareix com a emissor); si no, és **rebuda**.
    - El trimestre es decideix per la data de la factura, no per la del pagament.
    - Els tiquets i rebuts de despeses van amb les factures rebudes.
    - Un esborrany de model va a la seva carpeta amb ` - Esborrany` al final del nom.
    - Si no es veu la data, l'emissor o el tipus de document, el document queda pendent.
    """

    static let slFolders = [
        "1-Models Tributaris",
        "1-Models Tributaris/Model 036 - Censal",
        "1-Models Tributaris/Model 111 - IRPF Retencions",
        "1-Models Tributaris/Model 115 - IRPF Retencions Lloguers",
        "1-Models Tributaris/Model 200 - Impost Societats",
        "1-Models Tributaris/Model 303 - IVA",
        "1-Models Tributaris/Model 347 - Operacions amb Tercers",
        "1-Models Tributaris/Model 349 - Operacions Intracomunitaries",
        "1-Models Tributaris/Model 390 - IVA Resum Anual",
        "1-Models Tributaris/Altres Models",
        "2-Contractes", "2-Contractes/Renting", "2-Contractes/NDAs i Confidencialitat", "2-Contractes/Plantilles",
        "2-Contractes/Altres",
        "3-Actes i Documents Societaris", "3-Actes i Documents Societaris/Actes de Junta",
        "3-Actes i Documents Societaris/Comptes Anuals", "3-Actes i Documents Societaris/Escriptures",
        "3-Actes i Documents Societaris/Registre Mercantil", "3-Actes i Documents Societaris/Altres",
        "4-Correspondencia Bancaria", "5-Ordres Domiciliacio",
        "6-Propostes i Pressupostos", "6-Propostes i Pressupostos/Emeses", "6-Propostes i Pressupostos/Rebudes",
        "7-Factures", "7-Factures/Emeses", "7-Factures/Rebudes", "7-Factures/Llibres Trimestrals",
        "8-Nomines", "9-Certificats", "10-Notificacions AEAT", "11-Correspondencia Administrativa",
        "12-Documents Socis", "13-Treballadors", "14-Oficina",
        "15-Proteccio de Dades", "15-Proteccio de Dades/Document de Seguretat",
        "15-Proteccio de Dades/Clausules i Consentiments", "15-Proteccio de Dades/Politiques Web",
        "15-Proteccio de Dades/Drets", "15-Proteccio de Dades/Registres",
        "16-Projectes i Clients", "17-Gestio Interna",
    ]

    static let sl = """
    ---
    inbox: "99-Pendent"
    duplicates: "98-Duplicats"
    protected: []
    new_folders: subfolders_only
    ---
    # Organització de documents — Societat limitada

    La Tria llegeix cada document de `99-Pendent/`, decideix la carpeta i li posa nom segons aquestes regles. Si té dubtes, el deixa pendent. No es creen carpetes de primer nivell noves.

    ## Carpetes

    | Carpeta | Contingut |
    |---|---|
    | `1-Models Tributaris/` | Una subcarpeta per model: `Model 036 - Censal`, `Model 111 - IRPF Retencions`, `Model 115 - IRPF Retencions Lloguers`, `Model 200 - Impost Societats` (inclou el 202), `Model 303 - IVA`, `Model 347 - Operacions amb Tercers`, `Model 349 - Operacions Intracomunitaries`, `Model 390 - IVA Resum Anual`, `Altres Models`. |
    | `2-Contractes/` | `Renting/`, `NDAs i Confidencialitat/`, `Plantilles/` (models en blanc) i `Altres/`. |
    | `3-Actes i Documents Societaris/` | `Actes de Junta/`, `Comptes Anuals/`, `Escriptures/`, `Registre Mercantil/` i `Altres/`. |
    | `4-Correspondencia Bancaria/` | Cartes, transferències i notificacions de bancs. |
    | `5-Ordres Domiciliacio/` | Ordres SEPA i mandats. |
    | `6-Propostes i Pressupostos/` | `Emeses/<Client>/` (una subcarpeta per client, amb el nom curt) i `Rebudes/`. |
    | `7-Factures/` | `Emeses/AAAA/NT/` i `Rebudes/AAAA/NT/` (NT = `1T`…`4T` segons la data de la factura) i `Llibres Trimestrals/`. |
    | `8-Nomines/` | Nòmines i resums de nòmines. |
    | `9-Certificats/` | Certificats de l'AEAT, la Seguretat Social, bancs i retencions. |
    | `10-Notificacions AEAT/` | Notificacions, requeriments i resolucions de l'AEAT. |
    | `11-Correspondencia Administrativa/` | Altres organismes: INE, ajuntaments, subministraments, gestories. |
    | `12-Documents Socis/` | Documents personals de cada soci: `<Soci>/`. |
    | `13-Treballadors/` | Contractes laborals, model 145 i documentació de treballadors. |
    | `14-Oficina/` | Lloguer, plànols i documentació del local. |
    | `15-Proteccio de Dades/` | `Document de Seguretat/`, `Clausules i Consentiments/`, `Politiques Web/`, `Drets/` i `Registres/`. |
    | `16-Projectes i Clients/` | Documentació de projectes que no és econòmica ni contractual: `<Client>/`. |
    | `17-Gestio Interna/` | Fulls de treball propis, estimacions i planificació. |

    ## Nomenclatura

    Dates `AAAA-MM-DD` (o `AAAA-MM` si només consta el mes). Sense accents ni caràcters especials als noms. Es conserva l'extensió original.

    | Tipus | Format | Exemple |
    |---|---|---|
    | Model tributari | `Model XXX - AAAA - TT` (TT = `1T`…`4T`, o `1P`…`3P` per al 202; els anuals, sense TT) | `Model 303 - 2025 - 1T.pdf` |
    | Factura rebuda | `Factura [Proveidor] - AAAA-MM-DD` | `Factura Papereria Mar - 2025-03-14.pdf` |
    | Factura emesa | `Factura Emesa [Numero] [Client] - AAAA-MM-DD` | `Factura Emesa 2025-014 Client Exemple - 2025-05-02.pdf` |
    | Llibre trimestral | `Factures Emeses - AAAA - TT` / `Factures Rebudes - AAAA - TT` | `Factures Rebudes - 2025 - 2T.pdf` |
    | Contracte | `Contracte [Tipus] [Empresa] - AAAA-MM` | `Contracte Renting AutoRent - 2024-09.pdf` |
    | Acta | `Acta [Tipus] - AAAA-MM-DD` | `Acta Junta General - 2025-06-30.pdf` |
    | Comptes anuals | `Comptes Anuals - AAAA` | `Comptes Anuals - 2024.pdf` |
    | Banc | `[Banc] - [Assumpte] - AAAA-MM-DD` | `Banc Exemple - Transferencia Rebuda - 2025-02-10.pdf` |
    | Domiciliació | `Ordre Domiciliacio [Entitat] - AAAA-MM-DD` | `Ordre Domiciliacio Telefonia Exemple - 2025-01-20.pdf` |
    | Proposta | `Proposta [Client o Projecte] - AAAA-MM` | `Proposta Client Exemple App - 2025-03.pdf` |
    | Nòmina | `Nomines - AAAA-MM` | `Nomines - 2025-04.pdf` |
    | Certificat | `Certificat [Que] [Organisme] - AAAA-MM-DD` | `Certificat Corrent Obligacions AEAT - 2025-07-01.pdf` |
    | Notificació AEAT | `AEAT - [Assumpte] - AAAA-MM-DD` | `AEAT - Requeriment Informacio - 2025-03-03.pdf` |
    | Altres organismes | `[Organisme] - [Assumpte] - AAAA-MM-DD` | `INE - Enquesta Anual - 2025-04-29.pdf` |
    | Protecció de dades | `[Tema] - [Assumpte o empresa] - AAAA` | `Politica de Privacitat - exemple.cat - 2025.pdf` |

    ## Casos especials

    - Una factura és **emesa** si l'emissor és la societat del perfil; si no, és **rebuda**. El trimestre es decideix per la data de la factura.
    - Els PDF que agrupen totes les factures d'un trimestre van a `7-Factures/Llibres Trimestrals/`.
    - El model 202 (pagaments fraccionats) va amb el 200.
    - Un esborrany de model va a la seva carpeta amb ` - Esborrany` al final del nom.
    - Un contracte d'encarregat del tractament va a `15-Proteccio de Dades/Clausules i Consentiments/`, no a `2-Contractes/`.
    - Un document personal d'un soci (no de la societat) va a `12-Documents Socis/<Soci>/`, amb el nom del soci tal com figura al perfil.
    - Si no es veu la data, l'entitat o el tipus de document, el document queda pendent.
    """

    static let hogarFolders = [
        "1-Habitatge", "2-Salut", "3-Vehicles", "4-Bancs i Finances", "5-Impostos", "6-Feina i Nomines",
        "7-Estudis", "8-Assegurances", "9-Garanties i Compres", "10-Subministraments", "11-Administracio",
    ]

    static let hogar = """
    ---
    inbox: "99-Pendent"
    duplicates: "98-Duplicats"
    protected: []
    new_folders: subfolders_only
    ---
    # Organització de documents — Llar

    La Tria llegeix cada document de `99-Pendent/`, decideix la carpeta i li posa nom segons aquestes regles. Si té dubtes, el deixa pendent.

    ## Carpetes

    | Carpeta | Contingut |
    |---|---|
    | `1-Habitatge/` | Escriptures, hipoteca, lloguer, comunitat de propietaris i obres. |
    | `2-Salut/` | Informes mèdics, receptes, anàlisis i factures sanitàries. Una subcarpeta per membre del perfil si cal. |
    | `3-Vehicles/` | Documentació, ITV, manteniment i multes de trànsit. |
    | `4-Bancs i Finances/` | Extractes, préstecs, inversions i comunicacions bancàries. |
    | `5-Impostos/` | Renda (IRPF), IBI i altres tributs. Subcarpetes per exercici. |
    | `6-Feina i Nomines/` | Contractes de treball, nòmines i certificats d'empresa. |
    | `7-Estudis/` | Matrícules, títols i documentació escolar. |
    | `8-Assegurances/` | Pòlisses i rebuts d'assegurances (llar, vida, salut, cotxe). |
    | `9-Garanties i Compres/` | Factures de compra i garanties de productes. |
    | `10-Subministraments/` | Llum, aigua, gas, telèfon i internet. |
    | `11-Administracio/` | Ajuntament, DGT i altres organismes. |

    ## Nomenclatura

    Dates `AAAA-MM-DD` (o `AAAA-MM` si només consta el mes). Sense accents ni caràcters especials als noms. Es conserva l'extensió original.

    | Tipus | Format | Exemple |
    |---|---|---|
    | General | `[Tipus] [Entitat] - AAAA-MM-DD` | `Contracte Lloguer Immobiliaria Centre - 2025-09-01.pdf` |
    | Rebut de subministrament | `Rebut [Subministrament] [Companyia] - AAAA-MM` | `Rebut Llum Electrica Exemple - 2025-03.pdf` |
    | Nòmina | `Nomina [Empresa] - AAAA-MM` | `Nomina Empresa Exemple - 2025-04.pdf` |
    | Renda | `Renda - AAAA` (exercici) | `Renda - 2024.pdf` |
    | Informe mèdic | `Informe [Especialitat] - AAAA-MM-DD` | `Informe Dermatologia - 2025-02-11.pdf` |
    | Garantia | `Garantia [Producte] [Botiga] - AAAA-MM-DD` | `Garantia Rentadora Botiga Exemple - 2025-01-08.pdf` |
    | Assegurança | `Asseguranca [Tipus] [Companyia] - AAAA` | `Asseguranca Llar Asseguradora Sud - 2025.pdf` |
    | Vehicle | `[Vehicle] - [Assumpte] - AAAA-MM-DD` | `Cotxe - ITV - 2025-05-20.pdf` |

    ## Casos especials

    - L'IBI i els tributs locals van a `5-Impostos/`, no a `1-Habitatge/`.
    - Les multes de trànsit van a `3-Vehicles/`.
    - El vehicle s'anomena amb el seu nom curt del perfil (per exemple, `Cotxe`).
    - La factura de compra d'un aparell va a `9-Garanties i Compres/` encara que inclogui la garantia.
    - Si no es veu la data, l'entitat o el tipus de document, el document queda pendent.
    """
}
