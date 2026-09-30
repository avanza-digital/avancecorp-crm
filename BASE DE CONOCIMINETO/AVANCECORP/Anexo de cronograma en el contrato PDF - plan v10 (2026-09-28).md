---
tags: [crm, contratos, pdf, anexo, plan, retomar]
fecha: 2026-09-28
actualizado: 2026-09-29T11:40:00-05:00
estado: en-produccion
---

# Anexo de cronograma del contrato — plan v3.1: documento imprimible aparte (2026-09-28)

**v3.1:** refutado por Codex el 28/09 (CHANGES_REQUESTED: 4 P1 + 2 P2); hallazgos aplicados abajo y en el anexo técnico.

**Pedido de Miguel (28/09/2026):** el sistema debe poder entregar el ANEXO con el cronograma de
liquidaciones parciales (modelo «Propuesta de Anexo para contrato de AEP», carpeta
`CRM-Avance-Corp/pendientes/`). Vio las muestras y dijo «me gusta». Decisión final del mismo día:
**«todo sigue igual, solo que el añadido es que el analista ahora puede imprimir este anexo»**. Es decir:
el contrato PDF no cambia; el anexo es un documento aparte que el analista imprime cuando quiere.

Descartado el plan v2 (casilla al crear + columna + plantilla v10 con dos variantes): más piezas de las
que el pedido necesita. Queda documentado en la respuesta de Codex
`CRM-Avance-Corp/docs/encargos/2026-09-28-codex-anexo-cronograma-plan-respuesta.md` por si se retoma.

Muestras del anexo como documento propio: `CRM-Avance-Corp/MODELO DE CONTRATO/muestras-anexo-v10/anexo-suelto/`
(mensual, trimestral, compuesto, mancomunado, 60 cuotas y el contrato v9 sin cambios). Se regeneran con
`deno run -A _render-muestra.ts <pdf> <fecha> --anexo [--modalidad=…] [--compuesto] [--anios=N] [--cotitulares=N]`.
Las de la primera carpeta (anexo pegado al contrato) quedan como historia.

## Estado (29/09/2026)

**✅ EN PRODUCCIÓN 29/09 ~11:35 Lima, publicado por Miguel con `!` en este orden:** migración `20260929151350`
(verificada: 4 funciones con las huellas del banco, puertas solo `service_role`, bitácora con RLS forzada y 2
candados) → registrador (`REGISTRO_ANEXO_OK`) → edge (10/10 módulos vivos = árbol, arranca y rechaza sin sesión)
→ front desde worktree limpio en `fb79c46f`: artefacto `crm-20260929T163329Z-fb79c46f8848`, preflight ok sobre lo
vivo `9a74a1d0`, deploy por el MCP de Hostinger (el primer intento dio «timeout initialize», el segundo pasó),
humo: `build-20260929T163327395Z`, bundle `index-C3C0xtjL.js` = dist, chunk del botón vivo. Falta el humo de
negocio: Miguel imprime el anexo de un contrato real y se verifica el asiento en la bitácora. 🔴 Rotar el token
de Hostinger (quedó en el terminal). Integración pendiente: traer #130 a `main` local cuando la otra sesión
commitee `database.types.ts`, y PR de integración del anexo a GitHub.

**OK de Miguel (29/09):** «deja las firmas tal cual como están, implementa el documento tal cual como
está». Fases 1 y 2 CONSTRUIDAS y verificadas en local; falta la Fase 3 (publicación con su `!`).

- Commits en `main` local: `829c4afd` (edge: `anexo-v1.ts`, acción «anexo», tests 70/70, contrato v9
  byte-idéntico) y el siguiente (migración `20260929151350`, registrador y reversa en
  `supabase/scripts/anexo-cronograma/`, oráculo del PDF ampliado, botón y cliente del front, e2e).
- Verificación: edge `deno test` 70/70 · front `npm run check` 4 853 pruebas + build · e2e Docker
  `contrato-anexo.spec.ts` 2/2 · arnés SQL `run-test-contrato-pdf-v2-local.sh --run` SQL_OK + RUNNER_OK
  (con la migración y el bloque nuevo) · `test:rls:preflight` PASS · revisor a11y PASS (P3 aplicado).
  ⚠️ Trampa cazada: en el arnés, ejecutar una función SIN EXECUTE bajo `set role` tumba el Postgres
  del banco; el permiso se acredita por catálogo.
- Diseño final de la bitácora: tabla propia `private.contrato_pdf_anexo_impresiones` (solo añadir), NO
  `public.audit_log`: su CHECK de `operacion` es del portal y `bandeja_actividad` enseñaría el asiento
  al cliente. Sin FK a contratos/contrato_pdfs para sobrevivir a la eliminación auditada.
- Entrega al navegador: JSON (`pdf_base64` + sha256 + bytes + nombre) por `functions.invoke`; el front
  verifica y abre la pestaña reservada en el clic. Sin visor de PDF (Chromium en Docker) el e2e mide lo
  observable: pestaña abierta y sin aviso de error.
- Reviews del código, ambos CHANGES_REQUESTED y ambos aplicados (tercer commit):
  · auditor-rls: sin fugas ni P0/P1; la FK `actor_id … on delete set null` chocaba con el candado de
    solo añadir (→ sin FK) y la puerta `crm.` abría dos saltos puerta→tabla (→ núcleos en `private`).
  · Codex: la vigencia se decidía en dos lecturas sin bloqueo (→ mutex de la fila del contrato); la
    forma del cronograma era laxa (→ estricta por tipo de interés); la bitácora registraba solicitudes,
    no anexos entregados (→ puerta `contrato_pdf_anexo_emitido` DESPUÉS de dibujar, con sha256 y bytes;
    sin asiento no hay entrega); error de cronograma separado de snapshot inválido y de render; TRUNCATE
    cubierto; la migración se reaplica sobre la bitácora conservada por la reversa (probado).
- Bitácora final: `private.contrato_pdf_anexo_emisiones` (quién, cuándo, contrato, revisión, plantillas,
  sha256, bytes). Huellas md5 de las 4 funciones selladas en el registrador.
- Pendiente: publicación (migración → registrador → edge desde `CRM-Avance-Corp/` → `/release-crm`),
  `gen:types` tras aplicar, push a GitHub, humo en producción (imprimir un anexo real).

## Objetivo

Desde la ficha del contrato, el analista pulsa «Imprimir anexo de cronograma» y obtiene un PDF de una o
más hojas con los datos del contrato, la tabla de liquidaciones parciales, la liquidación final, los
textos de naturaleza y prevalencia y las firmas. Sale siempre igual porque se arma con los datos ya
congelados del contrato sellado. El contrato PDF sigue exactamente como hoy.

## Fases (en orden de ejecución)

### Fase 1 · El anexo existe en el servidor

- **Qué se construye:** una lectura nueva que entrega los datos congelados del contrato sellado a quien ya
  puede ver su PDF (misma regla de cartera y cadena de supervisión), y en el generador del PDF una acción
  nueva «anexo» que dibuja el documento con la firma impresa de Avance Corp. Sin guardar nada. El contrato
  vuelve a quedar byte a byte como la v9 (se retira el anexo pegado que hoy está sin commit).
- **Qué ve Miguel:** las muestras finales del anexo como documento propio (mensual, compuesto, mancomunado,
  60 cuotas) para su OK de texto y ubicación.
- **Cómo se comprueba:** tests de la edge con goldens del anexo y de la acción nueva (sin sesión, sin PDF
  sellado, fuera de cartera, ok); el contrato v9 sigue dando los mismos bytes; migración ensayada en Docker
  con reversa; `auditor-rls` y Codex.
- **¿Apta para producción?** se dirá al cerrar. Comercialmente: todavía nada visible; es la pieza que
  permite imprimir.

### Fase 2 · El botón en la ficha del contrato

- **Qué se construye:** «Imprimir anexo de cronograma» junto a «Ver contrato PDF» y «Descargar contrato
  PDF». Abre el anexo en una pestaña nueva, listo para imprimir o guardar. Si el contrato aún no tiene PDF
  sellado, avisa «Primero genera el contrato PDF». Solo para contratos con PDF sellado (régimen nuevo).
- **Qué ve Miguel:** el botón en la ficha y el anexo abriéndose, tras publicar.
- **Cómo se comprueba:** `npm run check` completo, e2e en Docker con la edge simulada, revisor de
  accesibilidad.
- **Comercialmente:** el analista entrega al cliente su hoja de fechas y montos en un clic, sin armar nada
  aparte, y decide cuándo hacerlo.

### Fase 3 · Publicación y verificación (con el `!` de Miguel)

1. Antes de nada: traer `avancecorp/main`, cerrar el commit en `main` y verificar que local y GitHub
   apuntan al mismo commit. Todo lo que se publica se construye desde ese commit (Codex P1).
2. Migración y registrador (sola no hace nada visible).
3. Edge, en ventana muerta (la acción nueva no toca ver/descargar/borrar).
4. Front con preflight.
5. Verificación en producción: Miguel imprime el anexo de un contrato real (solo deja el asiento de
   bitácora) y lo compara con la muestra; se comprueba en un navegador real que abre en pestaña nueva
   con su nombre y sin bloqueador de ventanas.
6. Mismo día: push a GitHub, PR de integración, nota del vault y memoria.

## Decisiones tomadas por defecto (Miguel las corrige sobre la muestra)

| Tema | Decisión |
|---|---|
| Fecha y monto de la liquidación final | los de la fila «retorno» del cronograma sellado (vencimiento + 7 días naturales, capital). Codex P1: el anexo no puede contradecir el cronograma congelado; si esa fila falta o no cuadra con el capital, el anexo no se emite |
| Interés compuesto | sin filas parciales; liquidación final con dos filas: participación en utilidades y restitución del capital |
| Qué contratos | los que ya tienen PDF sellado (régimen nuevo, desde el 19/08) |
| ¿Se guarda el anexo? | no se guardan los bytes; pero cada impresión deja un asiento en la bitácora (quién, cuándo, contrato, revisión, versión de plantilla y hash) y el pie del anexo dice «Generado el … a partir del contrato N° … sellado el …». Codex P1: procedencia verificable sin montar un segundo sellado |
| Firma impresa de Avance Corp en el anexo | se mantiene (el anexo es parte integrante y lo firman ambas partes, como el contrato). **Pregunta al abogado junto con la de la cláusula 3.9** |
| Dónde | solo en el CRM (no en el portal admin) y no en el modo demo |
| Montos fijos en «Participación» frente a la cláusula 3.9 | consultar al abogado |
| Contratos con PDF antiguo (v1, sin snapshot) | el servidor responde «este contrato no tiene datos congelados para el anexo» y el botón lo explica; no es un error del sistema |

## Qué NO cambia

El contrato PDF (misma versión v9, mismos bytes), sus datos congelados, las RPC de alta y corrección,
el cálculo del cronograma, el portal del cliente y los PDF ya sellados.

## Diferidos

- Anexo para contratos del régimen anterior al 19/08 (no tienen datos congelados).
- Botón en el portal admin y en el modo demo del CRM.
- La plantilla demo del front ya no es gemela de la real y no tiene test de paridad.

## Anexo técnico (plan v3)

Detalle completo en el encargo a Codex `CRM-Avance-Corp/docs/encargos/2026-09-28-codex-anexo-imprimible-plan.md`
y su respuesta. Cambios v3.1 tras Codex:

- **D1** `crm.contrato_pdf_snapshot_sellado(uuid,uuid)` (solo `service_role`, `puede_leer_contrato_pdf_como`,
  55000 en eliminación) devuelve la revisión sellada más alta; distingue `ANEXO_SIN_PDF_SELLADO` de
  `ANEXO_SIN_SNAPSHOT` (PDF v1 sin snapshot v2). Antes de escribir: contar en prod (solo lectura) cuántos
  `contrato_pdfs` tienen snapshot nulo o no v2.
- **D1b Bitácora:** cada impresión inserta un asiento en el registro de solo añadir (`audit_log`) con actor,
  contrato, revisión, `anexo-cronograma-v1`, sha256 y bytes. Es la procedencia que pidió Codex sin guardar
  bytes: el anexo se reproduce desde el snapshot sellado con esa versión de plantilla. La promesa de
  determinismo se limita a «misma versión desplegada»; se prueba con dos renders independientes.
- **D2** Reglas financieras contra el cronograma sellado: exactamente una fila `retorno` con monto = capital
  y fecha ≥ vencimiento; parciales = filas `cuota`; compuesto = 0 `cuota` + 1 `devolucion` con fecha =
  vencimiento; cualquier otra forma ⇒ error de integridad (no se emite). Pie: «Generado el <fecha> a partir
  del contrato N° <n> sellado el <fecha>». Firma impresa: se mantiene, pendiente del abogado.
- **D2b Entrega:** respuesta JSON `{nombre_archivo, sha256, bytes, template, pdf_base64}` por
  `functions.invoke` (evita `Content-Type` binario, cabeceras expuestas por CORS y `Content-Disposition`
  perdido en `blob:`); nombre saneado con `nombreArchivoContrato` (ASCII).
- **D3** El front abre la pestaña EN el clic (antes de la petición, para el bloqueador de ventanas), crea el
  `Blob` como `application/pdf`, verifica sha256 y bytes, y navega la pestaña al `blob:`; mensajes distintos
  para «sin PDF sellado», «sin datos congelados» y «fuera de tu cartera». Visibilidad del botón igual que
  los botones del PDF.
- **D4** Orden: integrar remoto y commit verificado en `main` → migración → edge → front construido desde ese
  commit. Goldens v9 del contrato conservados y regresión de `ensure/status/delete`.
- Pruebas añadidas: RPC directa como `anon` y `authenticated`; vía edge con otra cartera, lector global,
  cadena D2, cliente inactivo, contrato en eliminación; revisiones múltiples; cronogramas con `retorno`
  ausente/duplicado/discrepante; navegador real (CORS, tipo, nombre, bloqueador, 60 cuotas).

Relacionadas: [[Plantilla v9 del PDF - cotitulares en el contrato (2026-09-14)]] ·
[[PDF contractual privado e inmutable 2026-08-17]] · [[Regimen documental del contrato 2026-08-20]] ·
[[PDF de contrato (generador) — plan]] · [[Inicio]]
