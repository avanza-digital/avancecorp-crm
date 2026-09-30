---
tags: [crm, conversion, coordinacion, reparto, divisor]
actualizado: 2026-09-30
estado: produccion
---

# Conversión: la coordinadora ve el divisor del núcleo, no el reporte de entregas

<<<<<<< avancecorp/main
**SERVIDOR EN PRODUCCIÓN 30/09/2026 (migración y registro por `!` de Miguel; Astrid 115 = 65 + 50 y Merlys 88 = 60 + 28 verificados en prod; PR #146 fusionada). Pendiente: advisors y publicar el front con `/release-crm`.**
=======
**EN PRODUCCIÓN 30/09/2026: servidor (migración y registro por `!` de Miguel; Astrid 115 = 65 + 50 y Merlys 88 = 60 + 28 verificados en prod; advisors sin errores) y front (release `crm-20260930T213752Z-6bb984edc63c`, build `build-20260930T213751470Z`, publicado desde la rama de rescate sobre el tip vivo `57e7b3b4`; smoke PASS). PR #146 y #147 fusionadas; la rama de rescate vuelve a `main` por la PR #149.**
>>>>>>> rescue/conversion-coordinacion-20260930

## El síntoma y su causa real

Rosa (rol `coordinador`) veía en `#/repartir` → «Supervisión → analistas» **62** leads de
formulario para Astrid Centenaro en setiembre; el núcleo de conversión dice **65** (divisor
115 = 65 formulario + 50 landing).

Ese 62 sale de `crm.reporte_derivaciones_coordinacion_fn`, el **reporte de entregas**
(migración `20260904174534`). Cuenta por **fecha de entrega** y, a propósito (regla de
equidad del reparto, compartida con el reporte «Derivar leads» del supervisor), **deja de
sumar la entrega que volvió a la misma bandeja antes de gestionarse** y sí suma la
re-entrega: atribuye el lead al **último** receptor. El núcleo (`private.conversion_episodios`,
episodio `recibido`) cuenta **una llegada por lead, por su alta original en Lima, en el
primer analista** del ledger, y no se la resta al reasignar. Los 8 leads que difieren en
setiembre (3 de Astrid, 5 de Merlys) tienen todos el mismo patrón: episodio cerrado con
`motivo_cierre = 'parqueado'` y mismo supervisor de origen y destino, y luego re-entregado.
No hay ninguna otra diferencia ese mes. La hipótesis «cuenta por dueño actual» quedó
refutada (daría 63). El Ranking por origen ya usa la primera asignación.

## La decisión (Miguel, 30/09)

- El reporte de entregas **no cambia**: responde «qué entregó Supervisión en una fecha».
- Coordinación recibe el **divisor real del núcleo** por una **puerta nueva**, con ámbito
  de **toda la empresa** (el mismo que ya tiene en el reporte de entregas).
- No se toca el núcleo ni sus pesos, ni los conteos por dueño actual, ni las puertas de
  conversión existentes (`conversion_mensual_sin_cartera_fn` sigue negando al coordinador).

## Qué se construyó

- Migración `20260930185623_crm_conversion_divisor_coordinacion`: núcleos
  `private.conversion_divisor_empresa(date)` (compone `private.conversion_neta_por_vendedor`,
  la misma pieza que Metas, con el desglose por origen de los episodios recibidos; mes
  sellado → foto de `crm.cierre_mes_vendedor`, sin recalcular) y
  `private.conversion_divisor_empresa_totales(date)` (total de la empresa y lo «sin analista»;
  sellado: foto + `fuera_ranking` + `conversion_sin_analista`), y puerta
  `crm.conversion_divisor_coordinacion_fn(date)` (gate canónico del reparto:
  coordinador o gerencia; valida el período; delega; no lee tablas). Postflight con candado
  de dispersión (ninguna lee `crm.leads` ni el ledger), paridad con el núcleo y ejecución de
  la puerta sin actor (42501).
- Front: pestaña **«Conversiones»** en Repartir: mes, resumen de la empresa (llegadas,
  formulario, landing, cierres ponderados, conversión) y tabla por analista con
  supervisor, formulario, landing, llegadas, cierres y %. Fila «Sin analista asignado».
  En mes cerrado enseña la foto y el desglose va en «—». El navegador no calcula: si
  formulario + landing ≠ divisor, o la empresa no suma, rechaza el paquete entero.
- Oráculo `supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql`
  (recorre las puertas reales del reparto; 4 mutantes cazados) y registrador fail-closed.

## Verificación (30/09, banco Docker propio a paridad con prod)

Migración PASS · oráculo OK sin residuo · mutantes ×4 cazados · registrador probado (misma
md5, idempotente, fail-closed) · `npm run check` PASS (319 archivos / 4956 tests) · E2E Docker
Repartir 31/31 · Codex ×2 (LEVEL 3), auditor-rls y revisor-a11y con todos los hallazgos aplicados
(actas en `CRM-Avance-Corp/docs/encargos/2026-09-30-conversion-divisor-coordinacion-r1.md` y `-r2.md`).
NOT RUN: `test-rls.mjs` completo (bloque añadido, sintaxis verificada) y advisors.

Deuda anotada por los revisores, fuera de este alcance: el `tablist` a mano de `repartir.tsx`
(la casa ya tiene `ui/tabs.tsx` con el patrón APG) y el contraste de `TheadCrm` (≈4,49:1).

Relacionado: [[Reporte diario de derivaciones para Coordinación]],
[[Como se mide la conversion del asesor]], [[Conversion mensual - definicion cerrada]],
[[Leads - marca y filtro de reasignados (2026-09-28)]] y [[Inicio]].

## v2 (misma tarde): de dónde salen los cierres y rango de fechas

Miguel pidió, ya publicada la v1, ver **referidos, upgrade y renovación** y poder consultar
**entre dos fechas**. La migración `20260930221500` redefine la puerta (acreditando por md5 los
cuerpos vivos) y sus núcleos: por analista y de la empresa, cierres de formulario, landing,
referido (cantidad · aporte al peso, hoy 0,15), oficina (no pesa), upgrade (pesa 1) y renovación
(cantidad · aporte a 0,15), con el numerador bruto y el ajuste de meses pagados; y un modo
**rango** (`p_desde`/`p_hasta`, inclusivos en Lima, hasta 366 días, sin futuro): un mes
calendario exacto es ese mes (con su foto si está sellado); cualquier otro tramo se calcula en
vivo como hace la puerta de Gerencia (peso del referido del mes de `hasta`, sin ajustes).
Invariante que el servidor exige con datos reales y el navegador vuelve a comprobar: **partes =
numerador bruto** y **neto = bruto − ajuste**. Setiembre real: Astrid 5 + 2 + 1×0,15 + 4 upgrade =
11,15; empresa 65 + 25 + 19×0,15 + 24 + 3×0,15 = 117,15. Pestaña: selector «Mes / Rango de
fechas», cabecera agrupada Llegadas / Cierres y la fórmula del numerador escrita con los pesos.
Estado: preparada y verificada (banco Docker, oráculo v2, registrador, prod en solo lectura,
`npm run check` 322/5045, E2E Docker); pendiente de `!` de Miguel y release del front.

### Revisiones de la v2 (30/09 noche) — lo que cambió

Codex r1 (5 hallazgos), `auditor-rls` y `revisor-a11y` pidieron cambios; se aplicaron todos:

- **La foto sellada guarda dos conteos de cartera** y solo uno sirve: `conversiones_*` (primera
  operación elegible por cliente y mes, lo que suma el numerador). `operaciones_*` cuenta todas y
  habría inflado upgrade y renovación de todo mes sellado. Hoy prod no tiene meses sellados; setiembre
  será el primero, así que el error habría aparecido el 01/10. El oráculo siembra una foto con las dos
  cifras distintas para cazarlo.
- **La empresa no es «bruto − ajuste»**: el suelo en cero se aplica por analista y la empresa suma
  netos. El navegador lo comprobaba mal (habría rechazado un total correcto con un solo analista en
  el suelo). La fórmula ya no afirma igualdades que el servidor no garantiza (rango: sin «n × peso»;
  sellado: sin «=»).
- **Un rango libre que toca meses ya cerrados se calcula en vivo** (precedente de Gerencia) y ahora lo
  declara: `periodo.cruza_meses_sellados` y `fuente.modo` ('foto' | 'mensual' | 'rango_vivo'); la
  pestaña avisa «puede diferir de la foto del cierre».
- **Cierres de otros orígenes** (web, campaña, whatsapp, otro) no pesan pero ya no se esconden:
  `cierres.otros`; en la tabla, «Sin peso» = oficina + otros.
- **Pruebas que dependían del calendario**: el 30/09 «1 → hoy» ES el mes, así que el postflight y el
  oráculo no ejercitaban un rango real; ahora prueban el mes anterior como rango exacto y el 15 del mes
  anterior → hoy como rango real (partes = bruto, ajuste 0, divisor aditivo).
- **El registrador acredita los cuerpos vivos** por `md5(prosrc)` antes de registrar.
- **Accesibilidad**: un solo `<thead>` con dos filas y `scope`; ninguna subcolumna agrupada se oculta
  por ancho (desalineaba cabecera y cuerpo entre 1024 y 1279 px); teclear fechas espera 350 ms y no
  desmonta la tabla; `aria-invalid` solo en el campo que está mal.

**Pendiente de decisión de Miguel (auditor P3-3):** la coordinadora ve ahora, por persona, el ajuste
pendiente y el bruto (deuda de cierres anulados tras pagar). No es PII; es un dato nuevo en su ámbito.

Ver [[Como se mide la conversion del asesor]], [[Cierre de mes]] y [[Auditoria de conversiones - capas backend a frontend (2026-09-21)]].

