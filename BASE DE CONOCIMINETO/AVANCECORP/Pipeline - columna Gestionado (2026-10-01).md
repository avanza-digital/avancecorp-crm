---
tags: [crm, pipeline, leads, decision]
actualizado: 2026-10-01
---

# Pipeline — columna «Gestionado» (2026-10-01)

**Estado: PUBLICADO COMPLETO EL 01/10/2026.** Servidor ~15:20 Lima y pantalla ~16:15 Lima, ambos lanzados por Miguel con `!`. **PR #162 fusionada** en `main` de GitHub (`79f9e40e`).

## Publicación de la pantalla

- **Vivo del CRM:** `build-20261001T211328361Z`, commit **`a070838d`**, rama `rescue/pipeline-gestionado-20261001` (en GitHub). Es el vivo anterior `83674f19` (Tibio naranja, otra sesión) más este cambio. **El próximo release tiene que nacer de ahí.**
- Release `crm-20261001T211329Z-a070838d1b0d` (ZIP y manifiesto en `CRM-Avance-Corp/releases/` del taller). Recuperación: `crm-20261001T205947Z-83674f19eb7e.zip`.
- Smoke: `version.json` nuevo, home 200, entrada `assets/index-CL22-tVp.js` igual a la del paquete; **117 de 117 archivos de código idénticos** al manifiesto, 12 PNG 200 (la CDN las optimiza), `.htaccess` 403 y el ZIP 404.
- Gates sobre la versión publicada: `npm run check` PASS (5.534 pruebas) y E2E del tablero 53/53. La suite E2E completa (315 pasan, 2 fallan y son previas) se corrió sobre el mismo cambio asentado en el vivo anterior `54690b06`; entre ambos solo hay 3 archivos de color de la otra sesión.
- **Carrera con otra sesión:** el primer intento de subida lo rechazó el preflight porque, entre la comprobación y la subida (unos 5 minutos), otra sesión publicó `83674f19`. No se subió nada; se reasentó, se repitieron los gates y salió al segundo intento.
- `main` de GitHub trae este cambio por contenido (PR #162), no por historia. Le falta el «Tibio naranja» (PR #163, de la otra sesión) y le sobra, respecto del vivo, Llamadas F1 (#160), que no está publicada.

Antes de eso: **PR #162** abierta contra `main` (rama `crm/pipeline-gestionado`, `64b81bf8`) y fusionada por Miguel a las 15:43. Mientras tanto el CRM vivo sigue igual: el frente viejo no envía el filtro.

Verificación tras publicar el servidor (solo lectura): `acreditar.sql` dice «DESPUES de publicar», 15 anclas OK y 0 diferencias; la sonda HTTP anónima con `p_gestion` responde 401/`42501` (la API ya conoce el parámetro) y el control con un parámetro inexistente da `PGRST202`.

## Qué pidieron y qué se decidió

Los analistas pidieron «una etapa más» entre **Nuevo** y **Contactado** para distinguir lo que nadie ha tocado de lo que ya se intentó sin lograr contacto.

Decisiones de Miguel (01/10):

- **No es una etapa guardada.** El lead sigue con `etapa = 'nuevo'`; «Gestionado» es una **columna calculada** del Pipeline. Motivo: la lista de etapas está cableada en decenas de piezas (plazos, cola del día, embudo, avance automático) y una etapa real sería un proyecto grande con riesgo de leads que desaparecen de las colas.
- **El reasignado va a «Nuevo».** Solo cuenta lo que se intentó desde que el analista ACTUAL recibió el lead.
- Alcance: solo el Pipeline. En Leads y en la ficha sigue diciendo «Nuevo».

## La regla («gestión vigente»)

Un lead `nuevo` está en «Gestionado» cuando:

1. tiene analista (`vendedor_id`) y `tenencia_desde`;
2. existe una actividad de contacto (llamada realizada o no contestada, WhatsApp enviado o recibido, reunión realizada) con `creado_en >= tenencia_desde`;
3. y esa actividad **no está deshecha** (`metadata.deshecho_en`).

Consecuencias, todas fijadas con pruebas:

- Una **nota** no cuenta.
- **Reabrir** un descartado renueva la tenencia: vuelve a «Nuevo», aunque sea el mismo analista.
- Cuenta la **fecha**, no el autor: un intento del supervisor dentro de la tenencia pone el lead en «Gestionado».
- Sin analista (bandeja «por repartir») ⇒ «Nuevo».
- Devolver a mano un lead a «Nuevo» desde «Contactado» lo deja en «Gestionado» si ya tiene intentos.
- El lead entra en «Gestionado» **solo**, al registrar el intento. No se arrastra hacia ahí ni el menú «Mover a» la ofrece.

## Cómo está hecho

- **Servidor:** un parámetro opcional `p_gestion` (`'con_gestion'` | `'sin_gestion'`) en la puerta `crm.cartera_filtrada_fn`. Migración `20261001154153_crm_cartera_filtro_gestion.sql` (sha256 `01255f7b…`). La forma de la respuesta no cambia (hay navegadores con el bundle viejo). Kit, reversa, registrador y acreditación en `supabase/scripts/cartera-gestion/`.
- **Pantalla:** cinco listas servidas; «Nuevo» pide `sin_gestion` y «Gestionado» `con_gestion`. Las columnas del tablero viven en `app/src/lib/pipeline-columnas.ts`; `ETAPAS` no se tocó. En demo la misma regla se calcula en el navegador.
- **Orden de publicación:** servidor primero, pantalla después. Receta completa en el README del kit.

## Dónde está el trabajo

- **Entorno limpiado el 01/10 tras publicar** (pedido de Miguel): ya no existen las copias `wt-pipeline-gestionado` y `wt-release-gestionado` (esta tenía copia del archivo de entorno), el banco Docker `avancecorp-gestionado-20261001`, el volumen de E2E ni la vista previa local. Tampoco la rama de la PR (`crm/pipeline-gestionado`, local y GitHub): su contenido está en `main` por la #162.
- **Lo que queda, a propósito:** la rama `rescue/pipeline-gestionado-20261001` (local y GitHub), que es el commit vivo `a070838d`, y el ZIP y el manifiesto del release en `CRM-Avance-Corp/releases/` del taller.
- Para volver a ensayar el servidor: montar un banco con `supabase/scripts/potencial-lead/banco/montar-banco.sh` (contenedor `avancecorp-gestionado-AAAAMMDD`) y correr `supabase/scripts/cartera-gestion/ensayar.mjs`. Se ensayó contra el esquema de producción de la tarde del 01/10 (paridad de huellas: `crm` 286, `private` 553).
- Encargo de Codex y su respuesta: `CRM-Avance-Corp/docs/encargos/2026-10-01-codex-pipeline-gestionado*.md`.

## Realidad de producción (solo lectura, 01/10)

Última medición (tarde): 442 leads activos en «nuevo» → **297 a «Gestionado»** y **145 en «Nuevo»** (22 de ellos con contactos de un analista anterior). 0 leads con analista y sin `tenencia_desde`. 11 contactos deshechos de 8.307, ninguno decisivo. La cifra se mueve durante el día con los repartos.

## Verificación

| Comprobación | Resultado |
|---|---|
| Ensayo del servidor en banco (77 pasos: igualdad 256/256, oráculo 128/128, mutantes, reversa exacta) | PASS |
| `acreditar.sql` contra producción (solo lectura) | Todas las anclas OK: la migración pasaría su preflight |
| `npm run check` del frente, sobre la versión integrada (344 archivos, 5.544 pruebas) | PASS |
| E2E en Docker, suite completa, sobre la versión integrada | 315 pasan · 26 omitidas · **2 fallan y son previas** |
| `npm run check:scripts` | PASS |
| `test:rls:preflight` y la matriz nueva de `test-rls.mjs` | **NOT RUN** (exige credenciales) |
| Advisors | NOT RUN (son de la nube; tras publicar) |

Los dos E2E que fallan (`gerencia-operativa.spec.ts:108` y `gestion-diaria-vuelta.spec.ts:11`) fallan igual en la base sin este cambio: usan fechas fijas del 30/09 y se rompieron con el cambio de mes.

## Revisiones

- **Revisor de código** (dos pasadas): primera CHANGES_REQUESTED, segunda PASS. Encontró un arrastre que podía dejar el tablero sin abrir fichas y que el demo seguía contando lo deshecho. Corregidos.
- **revisor-a11y:** el foco se perdía al cambiar la tarjeta de columna; la caída de una columna no se anunciaba; el menú «···» no respondía a flechas ni a Escape (defecto anterior). Corregidos.
- **auditor-rls:** sin fuga entre roles. Pidió anclar también el reloj de la actividad y endurecer la matriz. Hecho (guarda 5).
- **Codex:** partición correcta. Aceptado: vigilar las policies restrictivas (punto ciego de `assert_actividades_de_lead_base`). Rechazado con evidencia: microsegundos en el espejo demo (ese dato nunca le llega) y la fecha futura falsificable (`trg_01_gestion_lead_serializada` re-sella `creado_en`).

## Pendientes y límites conocidos

- **Ancho:** las cinco columnas caben sin deslizar desde ~1.790 px con el menú abierto. En un portátil de 1.366 px se ven tres y hay scroll horizontal.
- **Color** de la columna: turquesa oscuro `#0e7490`. Pendiente de que Miguel lo vea.
- **Posición tras el intento:** las columnas se ordenan por última modificación del lead y registrar un intento no la cambia. Con más de 50 gestionados la tarjeta puede quedar tras «Cargar más».
- Tres detalles menores de la segunda revisión (carreras de foco muy estrechas, arrastre con el lead duplicado entre listas, marca de «Reintentar»): anotados, sin corregir.
- El gate analítico de producción está en rojo por un contador AJENO (`private.gestion_diaria_cola_hechos`); la migración lo conserva tal cual.
- El build vivo al cierre (`build-20261001T185238130Z`, commit `54690b06`, rama `release/potencial-lead-f3a-20261001`) no es ancestro de esta rama: el release tiene que nacer de la línea viva. `pipeline.tsx`, `sheet.tsx`, `e2e/_helpers.ts` y `test-rls.mjs` son idénticos en `avancecorp/main` y en el vivo, así que el parche asienta igual.
- **Sesiones paralelas:** el mismo día otra sesión publicó la marca de potencial dentro de `pipeline.tsx`. Hubo que asentar este trabajo encima (un conflicto de una línea y el ledger) y repetir todos los gates. Antes de publicar, volver a mirar `version.json` y `avancecorp/main`.
- Ajeno, para otra tarea: el «Deshacer» de descartes de Gestión diaria no refresca las listas del Pipeline; la lateral de «reasignado» de la función tiene un plan lento para gerencia (~50 ms).

## Lecciones

- **Chromium dispara `focusout` sin destino al quitar del DOM el nodo enfocado; jsdom no.** Un rescate de foco puede estar verde en unitarias y no funcionar nunca en el navegador: probarlo en E2E.
- **Dos listas hermanas llegan en respuestas separadas:** una tarjeta que cambia de columna puede no estar en ninguna durante un instante.
- **Un worktree bajo el Escritorio lo sincroniza iCloud:** `test-results/` se llenó de marcadores y el E2E dio fallos falsos (`Unknown system error -35`). Apartar la carpeta y repetir.
- **`pg_get_triggerdef` cambia con el `search_path`:** las anclas md5 de una migración se miden y se comprueban con `search_path` vacío.

Relacionado: [[Pipeline - etiqueta sin asignar por nombre ausente (2026-09-21)]] · [[Leads - marca y filtro de reasignados (2026-09-28)]] · [[E2E del CRM en local con Docker (2026-09-22)]]
