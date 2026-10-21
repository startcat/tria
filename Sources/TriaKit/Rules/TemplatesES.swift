enum TemplatesES {
    static let autonomoFolders = [
        "1-Facturas Emitidas", "2-Facturas Recibidas", "3-Impuestos", "4-Seguridad Social", "5-Bancos",
        "6-Contratos y Clientes", "7-Seguros", "8-Certificados", "9-Administracion",
    ]

    static let autonomo = """
    ---
    inbox: "99-Pendiente"
    duplicates: "98-Duplicados"
    protected: []
    new_folders: subfolders_only
    ---
    # Organización de documentos — Autónomo

    Tria lee cada documento de `99-Pendiente/`, decide su carpeta y le pone nombre según estas reglas. Ante la duda, lo deja pendiente.

    ## Carpetas

    | Carpeta | Contenido |
    |---|---|
    | `1-Facturas Emitidas/` | Facturas que emito a mis clientes. Subcarpetas `AAAA/1T`…`4T` según la fecha de la factura. |
    | `2-Facturas Recibidas/` | Facturas y tiques de proveedores y gastos. Subcarpetas `AAAA/1T`…`4T` según la fecha de la factura. |
    | `3-Impuestos/` | Modelos de la AEAT, una subcarpeta por modelo: `Modelo 130`, `Modelo 303`, `Modelo 390`, `Modelo 100 - Renta`, `Otros Modelos`. |
    | `4-Seguridad Social/` | Cuotas de autónomo (RETA), resoluciones, altas y bajas. |
    | `5-Bancos/` | Extractos, cartas y comunicaciones bancarias. |
    | `6-Contratos y Clientes/` | Contratos, presupuestos y documentación de clientes. |
    | `7-Seguros/` | Pólizas y recibos de seguros. |
    | `8-Certificados/` | Certificados de la AEAT, la Seguridad Social, bancos y retenciones. |
    | `9-Administracion/` | Otros organismos: ayuntamiento, DGT, suministros y notificaciones. |

    ## Nomenclatura

    Fechas `AAAA-MM-DD` (o `AAAA-MM` si solo consta el mes). Sin tildes ni caracteres especiales en los nombres. Se conserva la extensión original.

    | Tipo | Formato | Ejemplo |
    |---|---|---|
    | Factura emitida | `Factura Emitida [Numero] [Cliente] - AAAA-MM-DD` | `Factura Emitida 2025-014 Estudio Norte - 2025-05-02.pdf` |
    | Factura recibida | `Factura [Proveedor] - AAAA-MM-DD` | `Factura Papeleria Mar - 2025-03-14.pdf` |
    | Modelo AEAT | `Modelo XXX - AAAA - TT` (TT = `1T`…`4T`; los anuales, sin TT) | `Modelo 303 - 2025 - 1T.pdf` |
    | Seguridad Social | `Seguridad Social - [Asunto] - AAAA-MM` | `Seguridad Social - Cuota RETA - 2025-02.pdf` |
    | Banco | `[Banco] - [Asunto] - AAAA-MM-DD` | `Banco Ejemplo - Extracto - 2025-01-31.pdf` |
    | Contrato | `Contrato [Tipo] [Empresa] - AAAA-MM` | `Contrato Servicios Estudio Norte - 2025-01.pdf` |
    | Seguro | `Seguro [Tipo] [Compania] - AAAA` | `Seguro Responsabilidad Civil Aseguradora Sur - 2025.pdf` |
    | Certificado | `Certificado [Que] [Organismo] - AAAA-MM-DD` | `Certificado Corriente Pago AEAT - 2025-07-01.pdf` |
    | Otros organismos | `[Organismo] - [Asunto] - AAAA-MM-DD` | `Ayuntamiento - Recibo IBI - 2025-06-15.pdf` |

    ## Casos especiales

    - Una factura es **emitida** si el emisor es el titular del perfil (su nombre, un nombre comercial o su NIF aparece como emisor); si no, es **recibida**.
    - El trimestre se decide por la fecha de la factura, no por la del pago.
    - Los tiques y recibos de gastos van con las facturas recibidas.
    - Un borrador de modelo va a su carpeta con ` - Borrador` al final del nombre.
    - Si no se ve la fecha, el emisor o el tipo de documento, el documento queda pendiente.
    """

    static let slFolders = [
        "1-Modelos Tributarios",
        "1-Modelos Tributarios/Modelo 036 - Censal",
        "1-Modelos Tributarios/Modelo 111 - IRPF Retenciones",
        "1-Modelos Tributarios/Modelo 115 - IRPF Retenciones Alquileres",
        "1-Modelos Tributarios/Modelo 200 - Impuesto Sociedades",
        "1-Modelos Tributarios/Modelo 303 - IVA",
        "1-Modelos Tributarios/Modelo 347 - Operaciones con Terceros",
        "1-Modelos Tributarios/Modelo 349 - Operaciones Intracomunitarias",
        "1-Modelos Tributarios/Modelo 390 - IVA Resumen Anual",
        "1-Modelos Tributarios/Otros Modelos",
        "2-Contratos", "2-Contratos/Renting", "2-Contratos/NDAs y Confidencialidad", "2-Contratos/Plantillas",
        "2-Contratos/Otros",
        "3-Actas y Documentos Societarios", "3-Actas y Documentos Societarios/Actas de Junta",
        "3-Actas y Documentos Societarios/Cuentas Anuales", "3-Actas y Documentos Societarios/Escrituras",
        "3-Actas y Documentos Societarios/Registro Mercantil", "3-Actas y Documentos Societarios/Otros",
        "4-Correspondencia Bancaria", "5-Ordenes Domiciliacion",
        "6-Propuestas y Presupuestos", "6-Propuestas y Presupuestos/Emitidas", "6-Propuestas y Presupuestos/Recibidas",
        "7-Facturas", "7-Facturas/Emitidas", "7-Facturas/Recibidas", "7-Facturas/Libros Trimestrales",
        "8-Nominas", "9-Certificados", "10-Notificaciones AEAT", "11-Correspondencia Administrativa",
        "12-Documentos Socios", "13-Trabajadores", "14-Oficina",
        "15-Proteccion de Datos", "15-Proteccion de Datos/Documento de Seguridad",
        "15-Proteccion de Datos/Clausulas y Consentimientos", "15-Proteccion de Datos/Politicas Web",
        "15-Proteccion de Datos/Derechos", "15-Proteccion de Datos/Registros",
        "16-Proyectos y Clientes", "17-Gestion Interna",
    ]

    static let sl = """
    ---
    inbox: "99-Pendiente"
    duplicates: "98-Duplicados"
    protected: []
    new_folders: subfolders_only
    ---
    # Organización de documentos — Sociedad limitada

    Tria lee cada documento de `99-Pendiente/`, decide su carpeta y le pone nombre según estas reglas. Ante la duda, lo deja pendiente. No se crean carpetas de primer nivel nuevas.

    ## Carpetas

    | Carpeta | Contenido |
    |---|---|
    | `1-Modelos Tributarios/` | Una subcarpeta por modelo: `Modelo 036 - Censal`, `Modelo 111 - IRPF Retenciones`, `Modelo 115 - IRPF Retenciones Alquileres`, `Modelo 200 - Impuesto Sociedades` (incluye el 202), `Modelo 303 - IVA`, `Modelo 347 - Operaciones con Terceros`, `Modelo 349 - Operaciones Intracomunitarias`, `Modelo 390 - IVA Resumen Anual`, `Otros Modelos`. |
    | `2-Contratos/` | `Renting/`, `NDAs y Confidencialidad/`, `Plantillas/` (modelos en blanco) y `Otros/`. |
    | `3-Actas y Documentos Societarios/` | `Actas de Junta/`, `Cuentas Anuales/`, `Escrituras/`, `Registro Mercantil/` y `Otros/`. |
    | `4-Correspondencia Bancaria/` | Cartas, transferencias y notificaciones de bancos. |
    | `5-Ordenes Domiciliacion/` | Órdenes SEPA y mandatos. |
    | `6-Propuestas y Presupuestos/` | `Emitidas/<Cliente>/` (una subcarpeta por cliente, con su nombre corto) y `Recibidas/`. |
    | `7-Facturas/` | `Emitidas/AAAA/NT/` y `Recibidas/AAAA/NT/` (NT = `1T`…`4T` según la fecha de la factura) y `Libros Trimestrales/`. |
    | `8-Nominas/` | Nóminas y resúmenes de nóminas. |
    | `9-Certificados/` | Certificados de la AEAT, la Seguridad Social, bancos y retenciones. |
    | `10-Notificaciones AEAT/` | Notificaciones, requerimientos y resoluciones de la AEAT. |
    | `11-Correspondencia Administrativa/` | Otros organismos: INE, ayuntamientos, suministros, gestorías. |
    | `12-Documentos Socios/` | Documentos personales de cada socio: `<Socio>/`. |
    | `13-Trabajadores/` | Contratos laborales, modelo 145 y documentación de empleados. |
    | `14-Oficina/` | Alquiler, planos y documentación del local. |
    | `15-Proteccion de Datos/` | `Documento de Seguridad/`, `Clausulas y Consentimientos/`, `Politicas Web/`, `Derechos/` y `Registros/`. |
    | `16-Proyectos y Clientes/` | Documentación de proyectos que no es económica ni contractual: `<Cliente>/`. |
    | `17-Gestion Interna/` | Hojas de trabajo propias, estimaciones y planificación. |

    ## Nomenclatura

    Fechas `AAAA-MM-DD` (o `AAAA-MM` si solo consta el mes). Sin tildes ni caracteres especiales en los nombres. Se conserva la extensión original.

    | Tipo | Formato | Ejemplo |
    |---|---|---|
    | Modelo tributario | `Modelo XXX - AAAA - TT` (TT = `1T`…`4T`, o `1P`…`3P` para el 202; los anuales, sin TT) | `Modelo 303 - 2025 - 1T.pdf` |
    | Factura recibida | `Factura [Proveedor] - AAAA-MM-DD` | `Factura Papereria Mar - 2025-03-14.pdf` |
    | Factura emitida | `Factura Emitida [Numero] [Cliente] - AAAA-MM-DD` | `Factura Emitida 2025-014 Cliente Ejemplo - 2025-05-02.pdf` |
    | Libro trimestral | `Facturas Emitidas - AAAA - TT` / `Facturas Recibidas - AAAA - TT` | `Facturas Recibidas - 2025 - 2T.pdf` |
    | Contrato | `Contrato [Tipo] [Empresa] - AAAA-MM` | `Contrato Renting AutoRent - 2024-09.pdf` |
    | Acta | `Acta [Tipo] - AAAA-MM-DD` | `Acta Junta General - 2025-06-30.pdf` |
    | Cuentas anuales | `Cuentas Anuales - AAAA` | `Cuentas Anuales - 2024.pdf` |
    | Banco | `[Banco] - [Asunto] - AAAA-MM-DD` | `Banco Ejemplo - Transferencia Recibida - 2025-02-10.pdf` |
    | Domiciliación | `Orden Domiciliacion [Entidad] - AAAA-MM-DD` | `Orden Domiciliacion Telefonia Ejemplo - 2025-01-20.pdf` |
    | Propuesta | `Propuesta [Cliente o Proyecto] - AAAA-MM` | `Propuesta Cliente Ejemplo App - 2025-03.pdf` |
    | Nómina | `Nominas - AAAA-MM` | `Nominas - 2025-04.pdf` |
    | Certificado | `Certificado [Que] [Organismo] - AAAA-MM-DD` | `Certificado Corriente Obligaciones AEAT - 2025-07-01.pdf` |
    | Notificación AEAT | `AEAT - [Asunto] - AAAA-MM-DD` | `AEAT - Requerimiento Informacion - 2025-03-03.pdf` |
    | Otros organismos | `[Organismo] - [Asunto] - AAAA-MM-DD` | `INE - Encuesta Anual - 2025-04-29.pdf` |
    | Protección de datos | `[Tema] - [Asunto o empresa] - AAAA` | `Politica de Privacidad - ejemplo.com - 2025.pdf` |

    ## Casos especiales

    - Una factura es **emitida** si el emisor es la sociedad del perfil; si no, es **recibida**. El trimestre se decide por la fecha de la factura.
    - Los PDF que agrupan todas las facturas de un trimestre van a `7-Facturas/Libros Trimestrales/`.
    - El modelo 202 (pagos fraccionados) va con el 200.
    - Un borrador de modelo va a su carpeta con ` - Borrador` al final del nombre.
    - Un contrato de encargado de tratamiento va a `15-Proteccion de Datos/Clausulas y Consentimientos/`, no a `2-Contratos/`.
    - Un documento personal de un socio (no de la sociedad) va a `12-Documentos Socios/<Socio>/`, con el nombre del socio tal como figura en el perfil.
    - Si no se ve la fecha, la entidad o el tipo de documento, el documento queda pendiente.
    """

    static let hogarFolders = [
        "1-Vivienda", "2-Salud", "3-Vehiculos", "4-Bancos y Finanzas", "5-Impuestos", "6-Trabajo y Nominas",
        "7-Estudios", "8-Seguros", "9-Garantias y Compras", "10-Suministros", "11-Administracion",
    ]

    static let hogar = """
    ---
    inbox: "99-Pendiente"
    duplicates: "98-Duplicados"
    protected: []
    new_folders: subfolders_only
    ---
    # Organización de documentos — Hogar

    Tria lee cada documento de `99-Pendiente/`, decide su carpeta y le pone nombre según estas reglas. Ante la duda, lo deja pendiente.

    ## Carpetas

    | Carpeta | Contenido |
    |---|---|
    | `1-Vivienda/` | Escrituras, hipoteca, alquiler, comunidad de propietarios y obras. |
    | `2-Salud/` | Informes médicos, recetas, análisis y facturas sanitarias. Una subcarpeta por miembro del perfil si hace falta. |
    | `3-Vehiculos/` | Documentación, ITV, mantenimiento y multas de tráfico. |
    | `4-Bancos y Finanzas/` | Extractos, préstamos, inversiones y comunicaciones bancarias. |
    | `5-Impuestos/` | Renta (IRPF), IBI y otros tributos. Subcarpetas por ejercicio. |
    | `6-Trabajo y Nominas/` | Contratos de trabajo, nóminas y certificados de empresa. |
    | `7-Estudios/` | Matrículas, títulos y documentación escolar. |
    | `8-Seguros/` | Pólizas y recibos de seguros (hogar, vida, salud, coche). |
    | `9-Garantias y Compras/` | Facturas de compra y garantías de productos. |
    | `10-Suministros/` | Luz, agua, gas, teléfono e internet. |
    | `11-Administracion/` | Ayuntamiento, DGT y otros organismos. |

    ## Nomenclatura

    Fechas `AAAA-MM-DD` (o `AAAA-MM` si solo consta el mes). Sin tildes ni caracteres especiales en los nombres. Se conserva la extensión original.

    | Tipo | Formato | Ejemplo |
    |---|---|---|
    | General | `[Tipo] [Entidad] - AAAA-MM-DD` | `Contrato Alquiler Inmobiliaria Centro - 2025-09-01.pdf` |
    | Recibo de suministro | `Recibo [Suministro] [Compania] - AAAA-MM` | `Recibo Luz Electrica Ejemplo - 2025-03.pdf` |
    | Nómina | `Nomina [Empresa] - AAAA-MM` | `Nomina Empresa Ejemplo - 2025-04.pdf` |
    | Renta | `Renta - AAAA` (ejercicio) | `Renta - 2024.pdf` |
    | Informe médico | `Informe [Especialidad] - AAAA-MM-DD` | `Informe Dermatologia - 2025-02-11.pdf` |
    | Garantía | `Garantia [Producto] [Tienda] - AAAA-MM-DD` | `Garantia Lavadora Tienda Ejemplo - 2025-01-08.pdf` |
    | Seguro | `Seguro [Tipo] [Compania] - AAAA` | `Seguro Hogar Aseguradora Sur - 2025.pdf` |
    | Vehículo | `[Vehiculo] - [Asunto] - AAAA-MM-DD` | `Coche - ITV - 2025-05-20.pdf` |

    ## Casos especiales

    - El IBI y los tributos locales van a `5-Impuestos/`, no a `1-Vivienda/`.
    - Las multas de tráfico van a `3-Vehiculos/`.
    - El vehículo se nombra con su nombre corto del perfil (por ejemplo, `Coche`).
    - La factura de compra de un aparato va a `9-Garantias y Compras/` aunque incluya la garantía.
    - Si no se ve la fecha, la entidad o el tipo de documento, el documento queda pendiente.
    """
}
