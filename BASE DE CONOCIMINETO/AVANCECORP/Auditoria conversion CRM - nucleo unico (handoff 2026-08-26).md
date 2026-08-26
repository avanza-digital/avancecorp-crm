---
tags: [crm, conversion, auditoria, handoff, pendiente-continuar]
actualizado: 2026-08-26
estado: cerrado — los 3 pasos HECHOS; el plan espera la aprobación de Miguel (7 decisiones D1–D7) en [[Conversion unica en todo el CRM - plan de migraciones]]
---

# Auditoría "conversión" CRM — hacia un núcleo único (handoff)

Nota de traspaso para retomar esta investigación en OTRA sesión de Claude Code
(mismo repo, cualquier cuenta).

## ⚡ EMPEZAR AQUÍ — plan exacto, en orden, sin re-derivar nada

**NO** volver a auditar desde cero, **NO** volver a buscar la causa raíz, **NO**
releer todas las migraciones a mano. Todo eso ya está hecho y confirmado más
abajo. Los tres pasos, en este orden:

1. ✅ **HECHO 2026-08-26** — Verificación adversarial COMPLETA (69/69 veredictos).
   Resultado: **22 de 23 confirmados**; **H22 REFUTADO** (la conversión de
   empresa se pacta con un solo campo replicado — `config-metas.tsx:93-95` —,
   el "promedio" devuelve lo tecleado; solo queda texto obsoleto en
   `metas-editor.tsx:38`). El crítico de completitud añadió **N1–N16
   pendientes de verificar** (destaca N1: la ruta "Capital" está muerta,
   `lib/vistas.ts:77`). Informe final para Miguel:
   [[Auditoria conversion CRM - informe final gerencia (2026-08-26)]].
   Nota técnica: el `resumeFromRunId` NO sirve entre sesiones — se reconstruyó
   sembrando los 23 veredictos previos desde `wf_7000b107-334/journal.jsonl`;
   la corrida nueva es `wf_ec49a9ba-919` (sesión `5a9b6045`, journal en
   `~/.claude/projects/-Users-usuario-Desktop-DESARROLLO-DESARROLLO-AVANCECORP-desktop/5a9b6045-f2a0-4d21-8aa3-cb4f6797cad0/subagents/workflows/wf_ec49a9ba-919/journal.jsonl`).

2. ✅ **HECHO 2026-08-26** — Inventario completo corrido de cero
   (run `wf_7ebabc4e-a85`, 6 agentes): **41 funciones SQL** que producen
   conversión + **55 cálculos en el front** (los 3 roles), ficha del núcleo y
   borrador técnico de unificación (núcleo set-returning
   `private.conversion_episodios` + 8 migraciones en orden + 5 decisiones
   para Miguel). Todo en
   [[Auditoria conversion CRM - inventario y diseno de unificacion (2026-08-26)]].
   ⚠️ Hallazgo operativo del inventario: el texto vigente de
   `private.metricas_conversiones_implementacion` solo existe EN CALIENTE
   (parche `20260824170630` aplicado sin migración) — fijarlo con preflight
   md5 antes de reescribirla.

3. ✅ **HECHO 2026-08-26** — Plan escrito y verificado adversarialmente
   (4 lentes contra el repo, run `wf_4a2c07a4-480`; 16 correcciones
   aplicadas, 2 eran bloqueantes: la Distribución valida su payload con
   `strictObject` → añadir claves también rompe, por eso F2.3 va en dos
   tiempos; y «servidor ahora» NO es invisible — números nuevos bajo rótulos
   viejos hasta F3). El plan:
   [[Conversion unica en todo el CRM - plan de migraciones]] — 4 fases
   (F0 anclar el texto vivo · F1 tabla-base con paridad · F2 los 5 motores ·
   F3 front, bloqueada por ramas) y **7 decisiones D1–D7 esperando a
   Miguel**. NO escribir ni una migración SQL sin su OK explícito al plan
   (regla no negociable del proyecto).

Todo lo que sigue en este documento es **contexto ya cerrado**, para consultar
si hace falta un detalle — no para re-trabajar.

## El pedido de Miguel (2026-08-26)

1. Reportó que en gerencia "HOY" muestra un % de conversión y "Conversiones"
   muestra 0% el mismo día.
2. Tras el diagnóstico, pidió arquitectura: *«a nivel de servidor pueda enlazar
   todas estas métricas y no sean conexiones independientes, porque se rompe
   una y no vamos a saber qué es»*.
3. Lo generalizó a todo el CRM: *«quiero que todas las conversiones de todo el
   CRM llamen a un solo núcleo»* — los tres roles (vendedor, supervisor,
   gerencia), no solo gerencia.

Ver también [[Conversion mensual - definicion cerrada]] y
[[Conversion mensual - plan de implementacion]] (el plan original de agosto
que ya unificó metas con el núcleo — este trabajo es su continuación natural).

## Causa raíz confirmada (no re-verificar, es definitiva)

`crm.leads.contrato_id` **no lo escribe nadie** en todo el sistema. Verificado
con grep exhaustivo sobre: todas las migraciones SQL del CRM, las edge
functions del CRM, las edge functions compartidas del portal
(`_supabase_functions/functions/*`), y el JS de `public_html/js/admin/*`.
`crm.convertir_lead` escribe `etapa`, `perfil_id` y `convertido_en` — nunca
`contrato_id`. Medido en producción el 2026-08-14 (`MIGRACIONES.md:1460`):
371 contratos, CERO con lead enlazado.

Consecuencia: `crm.metricas_conversiones_fn` (pantalla "Conversiones" de
gerencia y varios KPIs/gráficas de "HOY") calcula
`conversion_contratos_pct = 100 × contratos / leads` donde `contrato` =
`l.contrato_id is not null` — **da 0% siempre**, no es una diferencia de
fórmula, es una métrica muerta por construcción.

## El núcleo ya existe y es la dirección correcta

`private.conversion_mensual_por_vendedor` (definición vigente en
`CRM-Avance-Corp/supabase/migrations/20260824231133_crm_gestion_clientes_renovaciones_conversion.sql:738-876`):
cohorte por fecha de ASIGNACIÓN (`crm.lead_asignaciones.asignado_en`),
numerador = cierres de lead (por `resultado_en`) ponderados (referidos al
15% vigente en `crm.conversion_pesos`, fuera del divisor) + operaciones de
cartera elegibles (renovaciones/upgrades, máx. 1 por cliente/mes), excluye
cierres externos anulados (`private.cierre_externo_anulado`), incluye
arrastre de meses anteriores.

Ya lo consumen: `crm.conversion_mensual_fn` (wrapper, misma migración,
línea 890+) y `crm.cumplimiento_metas_fn` (vía `cumplimiento_metas_sin_cartera_fn`,
migración 20260813212332 + envoltorios del 24/08). Es el patrón "Migración B"
del plan original — replicarlo para el resto.

## Inventario de motores de "conversión" en todo el CRM (NO unificados aún)

Última definición vigente de cada uno (grep `create or replace function` con
timestamp más alto, ya localizado — no rebuscar):

| Función | Última migración | Cohorte / fórmula | Pantallas/rol |
|---|---|---|---|
| `private.conversion_mensual_por_vendedor` + `crm.conversion_mensual_fn` | `20260824231133` | asignación, ponderada, arrastre, cartera | **El núcleo.** HOY héroe, Ranking, Metas, alerta individual (gerencia) |
| `crm.cumplimiento_metas_fn` → `cumplimiento_metas_sin_cartera_fn` | `20260824231133` / `20260824233619` | consume el núcleo | Metas (los 3 roles) |
| `private.metricas_conversiones_implementacion` → `crm.metricas_conversiones_fn` | `20260807203757` (rename), fórmula original `20260805200000` | fecha de ALTA, `contrato_id is not null` (**muerta**) | Conversiones (gerencia), KPIs/gráficas de HOY, alerta global |
| `crm.metricas_conversiones_equipo_fn` | `20260810024404` | paridad as-built con la anterior, alta, `contrato_id` | Ranking (columnas leads/clientes/conversion_pct) |
| `crm.metricas_distribucion_leads_v2_fn` | `20260807203757` (última `create or replace`; primera en `20260718152741`) | convertidos/(convertidos+descartados), sin ponderar | Distribución de leads / "Conversión por monto" |
| `crm.metricas_reuniones_fn` | `20260807203757` (última; primera `20260805180000`) | contratos sobre leads con reunión realizada | Reuniones — "Terminan en cliente X%" |
| `crm.metricas_vendedores_fn` | `20260809144920` | ventana MÓVIL de 45 días (`v_corte := ahora - interval '45 days'`), `etapa='convertido'` crudo, denominador = activos+convertidos | Gestión de equipo (supervisor/gerencia), Pipeline, Cartera — "Convertidos", "conversión 45 d" |
| `crm.resumen_cartera_fn` | `20260809144920` | (sin fichar en detalle — pendiente) | Cartera / Leads |

RPC names confirmados vía `app/src/data/crm-api.ts` (línea del `.rpc(...)`):
`cumplimiento_metas_fn` 779 · `metricas_distribucion_leads_v2_fn` 3422 ·
`metricas_agenda_fn` 3467 · `metricas_conversiones_fn` 3495 ·
`conversion_mensual_fn` 3542 · `metricas_conversiones_equipo_fn` 3579 ·
`metricas_reuniones_fn` 3608 · `resumen_cartera_fn` 3638 ·
`metricas_vendedores_fn` 3684.

## 23 inconsistencias encontradas y deduplicadas (auditoría adversarial)

Barrido completo + dedup ya corrido (workflow `wf_7000b107-334`, journal en
`/Users/usuario/.claude-grupo/projects/-Users-usuario-Desktop-DESARROLLO-DESARROLLO-AVANCECORP-desktop/8251144e-0cd4-4f33-86f8-cf5e63460142/subagents/workflows/wf_7000b107-334/journal.jsonl`
— **leer ese fichero antes de re-auditar, no repetir el barrido**, tiene el
detalle completo con archivo:línea de cada hallazgo). Verificación adversarial
(3 lentes: código-front / sql / escéptico-de-negocio) llevaba ~20 de 69
veredictos corridos cuando se cortó la sesión — **ninguno refutado hasta el
corte** (CONFIRMADO o PARCIAL). Falta terminar de verificar H8 en adelante.

Lista deduplicada (H1–H23), visibilidad entre paréntesis:

1. **H1** (alta) — "N cierres de M recibidos" no cuadra con el % de al lado: cierres crudos (sin ponderar, sin cartera) vs % ponderado + cartera. HOY, Capital, Rendimiento, Ranking.
2. **H2** (alta) — Resumen/Capital: "M recibidos" del héroe (asignación, mes) vs KPI "Clientes que invirtieron N de M leads" (alta, rango) — dos "leads" distintos en la misma pantalla.
3. **H3** (alta) — Conversiones: cuenta contratos enlazados (**muerto**, ver causa raíz).
4. **H4** (alta) — HOY: héroe = mes calendario de la fecha final del rango; resto de la pantalla = rango completo. Sin rótulo.
5. **H5** (alta) — Metas: aviso dice "mes en curso" pero mezcla mes de `hasta` con mes actual real.
6. **H6** (alta) — Mismo vendedor, dos "conversión" con nombre idéntico en pantallas distintas.
7. **H7** (alta) — Ficha del vendedor: dos "recibidos" distintos y cierres≠clientes en la misma hoja.
8. **H8** (alta) — Rendimiento/Equipo: "Conversión del mes" (núcleo) arriba vs "Cierra el X% de lo que resuelve" (distribución v2) abajo, misma pantalla.
9. **H9** (alta) — Cuarta fórmula: "Conversión · 45 días" de Gestión de equipo (ventana móvil, `etapa` cruda, denominador activos+convertidos).
10. **H10** (alta) — Alerta individual mide mes actual fijo (cacheada al boot); su "Ver ranking" lleva al mes del rango.
11. **H11** (alta) — Alerta individual (núcleo) vs alerta global "Cayó la conversión" (alta) — incompatibles en la misma bandeja.
12. **H12** (media) — "Evolución de la conversión": línea semanal por alta, comparada contra meta pactada con el núcleo.
13. **H13** (media) — "Conversión por origen": alta; la barra "Referido" contradice el tratamiento (15%, fuera del divisor) del héroe.
14. **H14** (media) — Conversiones héroe: "Clientes" (contrato) y "Capital" (fecha_cierre_comercial) son universos distintos bajo la misma cabecera.
15. **H15** (media) — Vendedor solo-cartera se rotula "Solo arrastre · 0 cierres" pero aporta al total.
16. **H16** (media) — Reuniones: "Terminan en cliente X%" (contratos) choca con "Conversión por origen" de Capital.
17. **H17** (media) — Anular un cierre de cooperativa baja "Conversión del mes" pero no "Cierra el X%" de Distribución, misma pantalla.
18. **H18** (media) — Equipo: "N recibidos" (núcleo, mes) vs "Recibió N leads en el período" (distribución, rango+USD).
19. **H19** (media) — "N convertidos · 45 d" (Gestión de equipo) vs "Convertidos" de Pipeline/Leads (todo el ámbito).
20. **H20** (media) — "N cierres" de HOY (mes, ledger, sin anulados) vs "Convertidos" de Pipeline (45 d móviles, etapa cruda, con anulados).
21. **H21** (media) — Umbral "muestra suficiente" de la alerta compara contra recibidos aunque el campo se llama `resueltos`.
22. **H22** (baja) — "Conversión de la empresa" en Metas = promedio simple de metas individuales, no ponderado.
23. **H23** (baja) — Pipeline: tile "Convertidos" (RPC, reloj servidor) vs chip "Convertido N" (conteo en cliente, store cargado al boot, tope 2000 filas).

## Dónde está la evidencia cruda (por si un script ya no existe)

- Journal completo del re-audit (23 hallazgos + verificaciones ya corridas,
  con archivo:línea de cada uno): `wf_7000b107-334/journal.jsonl`, ruta
  completa `/Users/usuario/.claude-grupo/projects/-Users-usuario-Desktop-DESARROLLO-DESARROLLO-AVANCECORP-desktop/8251144e-0cd4-4f33-86f8-cf5e63460142/subagents/workflows/wf_7000b107-334/journal.jsonl`.
- Journal del primer barrido (el que encontró la causa raíz de `contrato_id`,
  ya narrado arriba y no requiere reabrirse): `wf_5ef635f3-834/journal.jsonl`
  en la misma carpeta `subagents/workflows/`.
- El paso 4 (aprobación de Miguel antes de escribir SQL) no es opcional: es
  regla no negociable del proyecto — ningún cambio de esquema se escribe sin
  su OK explícito, y el ciclo pasa por `auditor-rls` + `test-rls.mjs` +
  advisors antes de merge (ver `CRM-Avance-Corp/supabase/migrations/LEEME.md`).

## Contexto operativo para quien retome

- Repo: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp`.
- Reglas no negociables: `CRM-Avance-Corp/CLAUDE.md` y
  `supabase/migrations/LEEME.md` (nunca editar migración commiteada, RLS
  deny-by-default, grants por columna en `crm.leads`, ciclo
  branch→aplicar→test-rls→advisors→merge — el merge de branches de Supabase
  está roto desde el 13/08, se aplica con `aplicar-*-prod.sh` con OK explícito
  de Miguel).
- Usar CODEgraph MCP primero para ubicarse en el código (instrucción del
  proyecto); en esta sesión no estaba conectado y se usó grep como respaldo.
