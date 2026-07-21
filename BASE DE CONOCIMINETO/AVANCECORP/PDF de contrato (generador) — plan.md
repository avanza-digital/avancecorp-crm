# PDF de contrato (generador) — plan

Plan aprobado 2026-07-21 (ultracode: 5 lectores + arquitecto + 3 críticos adversariales, 27 hallazgos incorporados). **Objetivo:** botón "PDF" en el detalle de contrato del CRM que genera, 100% en el navegador (cero backend, $0/mes), un PDF fiel al modelo Word "Contrato de Asociación en Participación" (junio 2026). Modelo fuente: `~/Downloads/Modelo Contrato Avance Corp - Junio 2026 (1).docx`.

Ver [[CRM conexión a datos reales]] y [[Handoff Cartera 2026-07-21]] (el botón vive en el ContratoDetalle que abre la pantalla Cartera).

## Decisiones de Miguel (2026-07-21, FINALES)

- **Erratas del modelo → SE CORRIGEN** (el PDF genera contratos nuevos; lista exacta de correcciones para su OK, documentada aquí en Fase 1).
- **Fecha de suscripción = `fecha_inicio`** del contrato (no la fecha de descarga).
- **Interés compuesto → tabla de 3 filas** (INVERSIÓN → DEVOLUCIÓN DE INTERESES con % acumulado exacto → RETORNO); redacción a aprobar en Fase 5.
- **Cartera vieja SIN domicilio → se completa solo desde el portal admin** (NO se añade policy de update fuera de ventana; sus PDFs llevan línea en blanco mientras tanto).
- **Correo cláusula 8.1** = `servicioalcliente@cacmascapital.com` (reemplaza a guillermo@).
- **Domicilio del cliente = campo nuevo en BD** (Fase 3), **USD = mismo articulado adaptando moneda**, **fidelidad = idéntico al Word**.

## Decisiones técnicas (verificadas contra el repo)

- **pdfmake 0.2.x** en chunk 100% lazy `pdf-vendor` (`advancedChunks`, test estricto a node_modules/pdfmake). Pasa la CSP (`script-src 'self'`, sin eval/WASM). Descarga: blob + `<a download>`; `getBlob` es **callback** en 0.2.x → envolver en Promise. Nombre: `Contrato-{numero_contrato}.pdf`.
- **Entry BYTE-IDÉNTICO (259.614 bytes)** — criterio duro por fase; cualquier delta = import estático colado.
- **Fuente: Liberation Sans subseteada desde la Fase 2** (el cuerpo real del docx es Arial 11pt NO incrustada; los `.odttf` son Cambria/Calibri de Microsoft → PROHIBIDO embeberlos). ⚠️ La "Helvetica base-14" de pdfmake NO existe en el build de navegador (revienta en runtime). `defaultStyle.font` SIEMPRE declarado y testeado (default Roboto revienta sin VFS).
- **Métricas del docx:** A4; márgenes 2.00/2.54/2.25/2.54 cm; cuerpo 11pt justificado, interlineado 1.15; tabla 14.66 cm centrada (anchos tw `553|2285|1433|1820|2220`), cabecera negrita sin sombreado, bordes 0.5pt; firmas 9pt; footer N° de página `#4F81BD`. El "membrete" son sellos flotantes del ejemplar escaneado, no un header.
- **Privacidad:** los datos del cliente del modelo Word JAMÁS entran al código (test lo verifica).
- **PEN/USD jamás mezclados**: la cláusula 3.3 usa exclusivamente la sección bancaria de la moneda del contrato (cuenta + tipo + N° + **CCI**, fallback si falta cualquiera).

## Fases

**F1 — Motor puro** (`src/lib/pdf/`, cero UI/bundle): `numero-a-letras` (es-PE, lanza fuera de rango) · `fechas-legales` (parseDateLocal UTC-5-seguro; capitalización parametrizada; plazo SIEMPRE derivado de fechas, jamás "UN (01) AÑO" fijo) · `moneda-legal` (2 decimales forzados) · `contrato-pdf-datos` (derivación pura: fila 0 INVERSIÓN sintética; fila RETORNO con **N°=0** como el modelo; % por cuota = `tasa_anual/cuotasPorAnio` con hasta 4 decimales si no divide exacto; correo del asociado cl. 4.1; `tasa_anual` cl. 3.2; **dedupe del titular principal** — el fixture demo lo duplica; identidad en cascada `ClienteDetalle → ClienteBasico`) · `contrato-pdf-definicion` (14 cláusulas con slots, type-only import). ~40+ tests.

**F2 — UI + lazy + fuentes + demo**: grupo `pdf-vendor` · `fuentes-vfs.ts` (Liberation Sans base64, solo desde la fachada) · fachada con import() dinámico e interop UMD · botón "PDF" en el DialogFooter de `contrato-detalle.tsx` (todos los roles) · en el clic **`ensureQueryData`** del detalle del cliente (evita carrera de query en vuelo → PDF con blancos evitables); si la RLS niega perfiles (supervisión), identidad desde `ClienteBasico` y solo degradan bancarios+domicilio con toast · demo 100% sin red (fixtures ClienteDetalle demo) · E2E de descarga + **smoke contra build+preview** (dev no ejercita el chunk real de Rolldown).

**F3 — Domicilio (única pieza BD)**: `alter table public.perfiles add column domicilio text` (aditiva; **pre-check GRANT por columna** en perfiles antes del frontend — trampa de crm.leads) · ciclo completo branch→gate RLS espejo (con caso nuevo)→advisors→merge · frontend: ClienteDetalle + Valibot + input en ClienteForm (viaja por el UPDATE del paso 2 → la edge `crear-cliente` NO se toca) + `database.types.ts` a mano · el PDF deja el placeholder. Si alguna vez se evalúa carril portal directo: sería la excepción public **n.º 3** (ya hay 2 en MIGRACIONES.md).

**F4 — Fidelidad final**: métricas exactas, firmas con `columns` (no tabs), **decisión del sello ANTES de esta fase** (image1.png pre-croppeada con srcRect si se aprueba; la firma del cliente JAMÁS; los 7 sellos marginales no se replican). Comparación lado a lado vs el Word exportado.

**F5 — Prueba visual de Miguel**: checklist (PEN 12 cuotas / USD / compuesto / mancomunado / sin domicilio-bancarios / no-activos / impresión A4) + decisiones restantes.

## Preguntas abiertas (para Fase 4-5, no bloquean)

Sello estampado sí/no · redacción compuesto y mancomunado (comparecencia sin domicilio de co-titulares) · titular_distinto (cuenta de un tercero) en 3.3 · estados no-activos ¿PDF histórico? · supervisión ¿degradado basta o PDF completo vía fn crm con gate? · paridad de captura de domicilio en convertir-lead/importar (follow-up) · nombre de archivo con apellidos · rastro de generación (¿evento Sentry?).

## Erratas del modelo corregidas (aplicadas en la muestra 2026-07-21; pendiente OK de Miguel/abogado)

1. Cl. 4.1: "en el correo electrónico **correo** {email}" → palabra duplicada eliminada.
2. Cl. 8.1: "generara" → "**generará**" (×2).
3. Cl. 10: "DECIMA: DISOLUCION" → "**DÉCIMA: DISOLUCIÓN**"; "facultados" → "facultadas" (las partes); "reciproca" → "recíproca".
4. Cl. 11.1: "**LA** ASOCIANTE declara" → "**EL** ASOCIANTE declara" (consistencia).
5. Cl. 11.3: "organizativas y **7º** de personal" → "organizativas y de personal" (artefacto de edición).
6. Ordinales normalizados al femenino: QUINTO→**QUINTA**, SEXTO→**SEXTA**, DÉCIMO SEGUNDA/TERCERA/CUARTA→**DÉCIMA** SEGUNDA/TERCERA/CUARTA. ("SÉTIMA" se mantiene: forma válida.)
7. Intro: "con domicilio {dirección}" → "con domicilio **en** {dirección}".
8. Cl. 3.3: "en la TIPO DE CUENTA AHORRO N° … del CAJA HUANCAYO Conforme" → "en la **cuenta de {TIPO} N° …, con C.C.I. N° …, del {BANCO}**, conforme al siguiente cronograma:" (redacción del slot bancario).
9. Montos "s/.50,000.00"/"s/50,000.00" → formato uniforme "**S/ 50,000.00**".
10. Texto de suscripción: punto final agregado.

## Muestra generada (2026-07-21)

`~/Desktop/Contrato Avance Corp — MUESTRA para revisión legal.pdf` — 6 págs, generada con pdfmake 0.2.23 (la MISMA librería del plan), métricas del docx (A4, márgenes 2.00/2.54/2.25/2.54, cuerpo 11pt justificado 1.15, tabla 14.66cm, firmas 9pt, folio azul `#4F81BD`), erratas corregidas, datos del cliente FICTICIOS (CARLOS ALBERTO EJEMPLO TORRES) con los parámetros comerciales del modelo (S/ 50,000 · 15% · 12 cuotas · 06/06/2026) para comparación lado a lado. Script reproducible: scratchpad de la sesión `pdf-muestra/generar-muestra.cjs` (la plantilla de este script ES el borrador de `contrato-pdf-definicion.ts` de la Fase 1). Muestra en Arial del sistema; el CRM embeberá Liberation Sans (métricamente idéntica).

## Estado

- [x] Muestra para revisión legal (2026-07-21) · [ ] Fase 1 · [ ] Fase 2 · [ ] Fase 3 · [ ] Fase 4 · [ ] Fase 5
