---
tags: [crm, conversion, auditoria, informe]
actualizado: 2026-08-26
estado: cerrado — 22 de 23 hallazgos confirmados adversarialmente (3 lentes), H22 refutado
---

> Informe final del paso 1 del handoff [[Auditoria conversion CRM - nucleo unico (handoff 2026-08-26)]].
> Verificación adversarial completa: 69 veredictos (3 lentes × 23 hallazgos), 22 confirmados, 1 refutado (H22).
> Journal de esta corrida: `wf_ec49a9ba-919` (sesión 5a9b6045); los 23 veredictos de la sesión anterior se sembraron desde `wf_7000b107-334`.
> Siguen: paso 2 (inventario vendedor/supervisor) y paso 3 (plan de migraciones — **requiere OK de Miguel antes de cualquier SQL**).

# Conversión del CRM: por qué gerencia ve cifras que no cuadran

## 1. Diagnóstico (3 líneas)

1. Bajo la palabra **«conversión»** conviven **seis fórmulas distintas** en el servidor (más un séptimo conteo de «Convertidos»): la mensual ponderada (`private.conversion_mensual_por_vendedor`, `20260824231133:738-876`), contratos÷altas (`private.metricas_conversiones_implementacion`, `20260805200000`), ventas÷resueltos por moneda (`private.metricas_distribucion_leads_core`, `20260717224252`), convertidos-45d÷cartera viva (`crm.metricas_vendedores_fn`, `20260809144920:509`), contratos÷leads-reunidos (`20260805180000:1169`) y el mismo núcleo mensual con **otra ventana** en metas/alertas (`crm.cumplimiento_metas_fn`).
2. Ninguna pantalla dice qué fórmula usa ni qué ventana mide; el mismo rótulo («Conversión», «cierres», «clientes», «recibidos») se reutiliza para poblaciones distintas.
3. El **0 % de «Conversiones»** no es un bug de cálculo: esa pantalla exige `crm.leads.contrato_id` (`20260805200000:78`), columna que **ningún proceso rellena en producción** (verificado: 371 contratos, cero con lead enlazado — `supabase/scripts/test-metas-versionadas.sql:760-773`). Es estructuralmente 0.

## 2. Escenario mínimo que reproduce «HOY > 0 % y Conversiones 0 %»

Base: 2 leads, 1 vendedor. Hoy 26-ago, rango por defecto 01→26 ago.

| | Lead A | Lead B |
|---|---|---|
| Alta (`creado_en`) | 18-jul | 10-ago |
| Asignado | 20-jul | 10-ago |
| Resultado | convertido 05-ago (perfil creado, **sin contrato enlazado**) | abierto |

- **HOY › Resumen**: «Conversión del mes **100 %**», «1 cierres de 1 recibidos» — divisor = lead B (asignado en agosto), numerador = lead A (cerró en agosto, arrastre de julio) — `20260824231133:767-787,:797`; `resumen-gerencia.tsx:327-334`.
- **HOY › Conversiones**: «Conversión a clientes **0.0 %** · 0 clientes de 1 leads» — cohorte = altas del rango (lead B), numerador = `contrato_id not null` = 0 — `20260805200000:45,:78,:174`; `inteligencia-comercial.tsx:573-574,:594`.
- Mismo día: `#/equipo` **50 %**, `#/pipeline` «Convertidos 1», `#/metas` barra al 400 %, bandeja de alertas **en silencio** (umbrales ≥10 y ≥30, `alertas-gerencia.ts:103,:108`).

## 3. Los seis motores

| Función SQL | Cohorte | Ventana | Numerador | Denominador | Referidos | Arrastre | Dónde se ve |
|---|---|---|---|---|---|---|---|
| `private.conversion_mensual_por_vendedor` (`conversion_mensual_fn`) | asignación (`lead_asignaciones`) | mes calendario del **`hasta`** del rango | cierres ponderados + cartera − ajuste | recibidos **no referidos** | ×0,15, fuera del divisor | sí | HOY héroe/KPI, Ranking, Rendimiento, ficha vendedor |
| igual núcleo vía `cumplimiento_metas_fn` | asignación | **mes actual fijo** (`store.tsx:758`) | idem | idem | idem | sí | Metas, alerta «Conversión bajo meta» |
| `private.metricas_conversiones_implementacion` | **alta** del lead | rango libre | leads con `contrato_id` | todos los leads del rango | 100 % | no | Conversiones (héroe, embudo, orígenes, evolución), KPI «Clientes que invirtieron» |
| `private.metricas_distribucion_leads_core` | **episodios** de asignación | rango libre | convertidos (crudos, con anulados) | convertidos+descartados, **por moneda** | 100 % | no | Rendimiento, panel inferior «Cierres del período» |
| `crm.metricas_vendedores_fn` | dueño actual del lead | **45 días móviles** solo en el numerador | convertidos (incl. anulados) | cartera viva + descartados históricos | 100 % | n/a | Gestión de equipo «Conversión · 45 días» |
| `private.metricas_reuniones_implementacion` | reuniones realizadas | rango libre | leads reunidos con contrato | leads reunidos | 100 % | no | Reuniones «Terminan en cliente» |

(+ `crm.resumen_cartera_fn:149`: conteo «Convertidos», 45 d móviles, con anulados → Pipeline y Leads.)

## 4. Inconsistencias confirmadas (22)

**Visibilidad alta**

1. **H1** «N cierres · M recibidos» junto a un % que no es N/M (los cierres son crudos; el % pondera referidos, suma cartera y resta anulaciones) — `resumen-gerencia.tsx:334,:359`, `equipo-gerencia.tsx:61-62,:149,:156`, `ranking-vendedores.tsx:186-189`.
2. **H3** «Conversión a clientes» y el embudo cuentan **contratos**; el escalón «Perfiles creados» que reconciliaría se oculta — `inteligencia-comercial.tsx:526,:594`.
3. **H2** En la misma pantalla, «M recibidos este mes» (asignación) vs «de N leads» (altas del rango) — `resumen-gerencia.tsx:334` vs `:360`.
4. **H4** El héroe mide el mes de la **fecha final** del rango y el resto el rango; nada nombra el mes — `hoy/gerencia.tsx:200-201`.
5. **H5** En Metas el aviso dice «mes en curso» pero la conversión es del mes de `hasta` y la meta es del mes actual — `hoy/gerencia.tsx:326-330,:377-394`.
6. **H6** Dos gráficas homónimas «Conversión por vendedor» con fórmulas distintas y mismo `aria-label` — `equipo-gerencia.tsx:122-123` vs `inteligencia-comercial.tsx:611-614`. *(Corrección: «Ver ranking» conserva el orden; la inversión aparece al abrir Conversiones.)*
7. **H7** Ficha del vendedor: «Recibidos N · cierres K» (mes) junto a «Leads recibidos / Clientes» (rango) — `inteligencia-comercial.tsx:354` vs `:378-379`.
8. **H8** Rendimiento: «Conversión del mes» arriba y «Cierra el X % de lo que resuelve» abajo, mismo vendedor — `equipo-gerencia.tsx:70` vs `distribucion-leads-gerencia.tsx:636`.
9. **H9** Cuarta fórmula «Conversión · 45 días» — `equipo.tsx:776`. *(Corrección: con 0 abiertos muestra «—», no «0 %».)*
10. **H10** La alerta mide el mes actual; su destino «Ver ranking» mide el mes de `hasta`, y la alerta no se refresca — `alertas-provider.tsx:58-65,:378-384`.
11. **H11** En la misma bandeja: alerta individual ponderada vs «Cayó la conversión general» (contratos÷altas, con sesgo de maduración) — `alertas-provider.tsx:59` vs `:76`.

**Visibilidad media**

12. **H12** «Conversión real» semanal (contratos÷altas) se dibuja contra la meta pactada para la ponderada — `resumen-gerencia.tsx:224-244`.
13. **H13** «Conversión por origen» pinta los referidos al 100 % mientras el héroe los pondera a 0,15 — `resumen-gerencia.tsx:405-411`.
14. **H14** «Clientes» (altas con contrato) vs «Capital» (contratos por `fecha_cierre_comercial`) — `inteligencia-comercial.tsx:596-597`.
15. **H15** Vendedor con solo cartera: «0 cierres · Solo arrastre» pero suma al total — `20260824231133:926-934`.
16. **H16** Reuniones llama «clientes» a contratos y su % por origen choca con el de Resumen — `reuniones-gerencia.tsx:120`.
17. **H17** Anular un cierre baja la conversión de Rendimiento y **no** el «Cierra el X %» del panel de abajo — `20260824231133:787` vs `20260717224252:209`.
18. **H18** Dos «recibidos» distintos en Rendimiento (leads sin referidos del mes vs episodios del rango) — `equipo-gerencia.tsx:68` vs `distribucion-leads-gerencia.tsx:629`.
19. **H19** «N convertidos · 45 d» (solo equipos con supervisor activo) vs «Convertidos» de Pipeline/Leads (todo) — `equipo.tsx:726` vs `pipeline.tsx:330`.
20. **H20** «N cierres» (mes, ledger, sin anulados) vs «Convertidos» (45 d móviles, etapa, con anulados) — `resumen-gerencia.tsx:334` vs `cartera.tsx:96`.
21. **H21** El corte «muestra suficiente» (≥10 recibidos no referidos) no se dice en pantalla — `alertas-gerencia.ts:103,:233`.

**Baja**

22. **H23** En Pipeline, tile «Convertidos» (servidor) vs chip «Convertido N» (foto del store) — `pipeline.tsx:330` vs `:532`.

## 5. Pendientes de verificar (críticas nuevas, aún sin confirmar)

- **N1** La ruta «Capital» está **muerta** (`lib/vistas.ts:77`); todo lo que H1/H2/H16/H17 atribuyen a «Capital» ocurre en **Resumen**. Menú, título y componente siguen vivos.
- **N2** Un solo vendedor sin supervisor activo dejaría **toda** la conversión por vendedor en «No disponible» — `conversion-vendedores.ts:274-279`.
- **N3** El «0 %» de Gestión de equipo viene de `else 0` en el servidor (`20260809144920:658`), con guard equivocado en el front.
- **N4/N5/N6** La demo enseña otro negocio y su selector de período es inerte → los e2e **no pueden** ver estos desfases.
- **N7/N8** Campos que el servidor calcula y nadie pinta: `cierres_sin_episodio`, `fuera_de_roster`, `produccion.clientes`.
- **N9** Avance de meta capado en HOY (100 %) y sin capar en Metas (400 %).
- **N10–N16** Plurales fijos («1 cierres de 1 recibidos»), agrupación por nombre de supervisor, doble redondeo, gate de realidad que no mide `lead_asignaciones`, pie con rango sobre datos de ejemplo, código muerto.

## 6. Descartados

- **H22** (tarjeta «Conversión de la empresa» vs texto «no se divide por … conversión»): la conversión se pacta con **un solo campo de empresa** que se replica a todos (`config-metas.tsx:93-95,:400`), así que el «promedio» devuelve exactamente lo tecleado. Queda solo un texto obsoleto en `metas-editor.tsx:38`.

## 7. Recomendación (orden)

1. **Arreglar el 0 %**: enlazar `crm.leads.contrato_id` al crear contrato, o —mejor— **retirar** «Conversión a clientes», el embudo y «Conversión por origen» como *conversión* y renombrarlos «Contratos firmados» (hoy son 0 estructural y ya contradicen a HOY).
2. **Una sola definición**: que Ranking, Rendimiento, ficha, Metas y alertas lean el mismo `private.conversion_mensual_por_vendedor` con la **misma ventana** (mes del rango), no el mes actual fijo (H5, H10).
3. **Renombrar, no recalcular**, lo que mide otra cosa: «Cierres del período» (H8/H17/H18), «Conversión · 45 días» (H9), «Terminan en cliente» (H16), «Convertidos» de Pipeline/Leads (H19/H20) → añadir su base y ventana al rótulo.
4. **Hacer legible el %**: bajo cada cifra, «N cierres (referidos ×0,15) + R renovaciones − A anuladas ÷ M recibidos no referidos» (H1, H15).
5. **Excluir cierres anulados** en `metricas_distribucion_leads_core` (H17) y nombrar el mes en pantalla (H4).