# Contrato de la capa semántica — Leads y Citas (F6)

Borrador del 2026-08-30, medido contra producción esa noche. Es el paso 1 del molde
que ya funcionó dos veces ([[Contrato de la capa semantica - Capital (F4, 2026-08-29)]]):
**primero se escribe qué significa cada número, Miguel lo aprueba, y solo entonces se toca código.**

Relacionado: [[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]] ·
[[Conversion unica en todo el CRM - plan de migraciones]] · [[Terminologia de citas en el CRM]]

---

## El censo, medido el 30/08 (no estimado)

El plan hablaba de «21 funciones de leads y 6 de citas» (auditoría de julio). La medición real:

| | Funciones |
|---|---|
| Tocan `crm.leads` | **64** |
| De esas, **cuentan** leads | **28** |
| Hablan de citas/reuniones | 46 |
| De esas, **cuentan** citas | **11** (todas cuentan también leads, salvo `metricas_sla_fn`) |

**Las 30 que cuentan** (leads, citas o ambas), por familia:

**Métricas puras (las que hay que unificar):**
`crm.metricas_vendedores_fn` (⚠️ única con ventana de 45 días) · `crm.resumen_cartera_fn` ·
`crm.metricas_conversiones_equipo_fn` · `crm.conversion_mensual_sin_cartera_fn` ·
`crm.series_comerciales_fn` · `crm.metricas_reuniones_fn` · `crm.metricas_sla_fn` ·
`crm.cola_accion_fn` · `crm.resumen_reparto_fn` · `crm.resumen_tareas_fn` ·
`crm.rescate_descartes_meses` · `crm.ingresos_reparto_mes_fn` · `crm.cierres_externos_fn` ·
`private.metricas_conversiones_implementacion` · `private.metricas_distribucion_leads_core` ·
`private.metricas_reuniones_implementacion` · `private.metricas_agenda_implementacion` ·
`private.metricas_sla_global_core` · `private.supervisores_para_reparto_implementacion`

**Operativas que cuentan para decidir (se convierten al final, con más cuidado):**
`crm.cerrar_periodo` (el MOTOR DEL SELLO: cuenta leads para la conversión del cierre) ·
`private.registrar_ajuste_si_mes_cerrado` · `crm.derivar_leads_equipo_fn` ·
`crm.reporte_derivaciones_equipo_fn` · `crm.agenda_reparto_diaria` ·
`crm.guardar_agenda_reparto_diaria` · `crm.panel_distribucion_reparto` ·
`crm.rescatar_descartes` · `crm.impacto_desactivacion_usuario_fn` ·
`private.produccion_mes_por_vendedor` (ya es consumidor del núcleo de capital) ·
`private.contratos_afectados_por_anulacion` · `private.trg_leads_asignaciones`

**🔑 EL MAPA REAL (cambia el plan a mejor):** el núcleo de leads **YA EXISTE** —
`private.conversion_episodios(...)`, lo dejó la «conversión única» — y **9 funciones ya beben
de él** (Conversiones, Distribución v3, series, resumen de cartera, cartera por vendedor,
reuniones...). El Bloque B no es construir un núcleo: es **convertir a las ~24 que siguen
contando a crudo** y separar dos preguntas que hoy se confunden: la de CONVERSIÓN (va al
núcleo) y la de INVENTARIO/carga de trabajo (cuántos leads hay en cada etapa, cuántos por
repartir — que necesita su propia función pequeña, no el ledger). Para citas NO hay núcleo:
la definición canónica vive INCRUSTADA en `private.metricas_reuniones_implementacion`
(banderas: pactada, debió ocurrir, realizada, no-show, cancelada por asesor / por sistema,
reprogramada, pendiente de cierre, programada a futuro). El Bloque A la EXTRAE tal cual.

**Dato de diseño:** «citas» NO es una tabla — son `crm.tareas` con tipo `reunion`
([[Terminologia de citas en el CRM]]). La calculadora de citas vive dentro de la de tareas.
Tamaños: leads 724 · tareas 1 352 · actividades 4 264 · asignaciones 693.

---

## La foto del 30/08 — y las contradicciones que ya se ven

Con la misma gerencia, el mismo día, agosto:

| Pregunta | Pantalla | Respuesta |
|---|---|---|
| ¿Cuántos convertidos? | Series comerciales | **20 cierres** |
| ¿Cuántos convertidos? | Embudo de cartera | **21 convertidos** |
| ¿Capital ganado PEN? | Series | **221 000** |
| ¿Capital ganado PEN? | Resumen de cartera | **251 000** |
| ¿Conversión? | Series | **2,8 %** (20/724) |
| ¿Citas realizadas? | Reuniones | 6 de 40 pactadas (17,6 %) |

⚠️ agosto es **mes parcial** (el ledger de leads empieza el 17/08): los «724 nuevos» de
agosto son TODA la base. Cualquier % de agosto hereda esa asimetría.

---

## Las 5 decisiones de Miguel (2026-08-30) — FIRMADAS

1. **El mes del lead = el mes en que ENTRÓ** (cohorte de entrada). Es el divisor de toda conversión.
2. **Referidos pesan ×0,15**, como hoy y como el cierre sellable. Venta nueva = 1.
3. **El descartado va al DIVISOR** — decisión previa ([[crm-conversion-descartados-cuentan]]), reafirmada por vigencia.
4. **La cita anulada QUEDA**, en su propia columna: pactadas la incluye, y hay columna de canceladas.
5. **La ventana de 45 días MUERE**: `metricas_vendedores_fn` pasa al mes calendario; el rótulo dirá el mes.

## Estado

🔨 **Bloque A (citas) EN CURSO** — núcleo `private.citas_episodios`-estilo sobre `crm.tareas`
tipo reunión, con las 5 decisiones firmadas. Luego: Bloque B (leads, 3–4 sesiones) → trinquete
→ auditorías → publicación por tandas con oráculo de paridad en cada consumidor.
