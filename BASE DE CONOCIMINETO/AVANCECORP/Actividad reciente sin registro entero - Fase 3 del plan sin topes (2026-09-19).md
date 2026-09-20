---
tags: [crm, escalabilidad, actividades, directorio, fase-3, sin-topes]
actualizado: 2026-09-19
estado: SQL PREPARADO Y ENSAYADO (sin instalar en prod) · front listo · PR pendiente · publicar servidor ANTES que front
---

# Actividad reciente sin registro entero — Fase 3 del plan «sin topes» (2026-09-19)

Continúa [[Historial por lead sin topes - Fase 1 (2026-09-19)]] y
[[Tareas sin tope - Fase 2 del plan sin topes (2026-09-19)]]. Relacionado con
[[Plan de escalabilidad del CRM a data gigante]] (F3) y [[Mapa de capas del servidor CRM - 2026-09-17]].

## Objetivo (fijado por Miguel el 19/09)

Que ninguna pantalla dependa de descargar el registro de actividades del ámbito (recortado a 1 000
filas): Pipeline, Hoy · Supervisor y Hoy · Directorio piden al servidor solo lo que muestran, la RPC vieja
sale del arranque y se deprecia, y muere el último tope de actividades del front.

## Lo que se midió antes de tocar nada

- El arranque llamaba a `crm.actividades_del_ambito_fn` (13 645 actividades en un año, 2 886 por semana):
  PostgREST la recortaba a 1 000 y la alarma del front (10 000) nunca sonaba.
- Con el modo SLA `activo` en producción desde el 07/09, en sesión real esa lista solo la usaba de verdad
  **una** pantalla: la bitácora «Actividad reciente» de Hoy · Directorio (8 filas). El semáforo del Pipeline
  se pinta con la fotografía SLA; los cuatro hooks operativos usan las actividades solo en demo; la espera
  de la bandeja del supervisor cae a `tenencia_desde`; las alertas legado solo corren en demo o con el SLA
  apagado.
- `resumen_reparto_fn` es solo para coordinación y gerencia (42501 a un supervisor): no sirve para
  Hoy · Supervisor, como suponía el plan.

## Lo que se hizo

**Servidor** — migración `20260920014500_crm_actividades_recientes.sql`: puerta
`crm.actividades_recientes_fn(p_limite=8 [1..50]) returns jsonb {version, items}` INVOKER sin predicado
copiado; núcleo con `lead_nombre` (bajo `leads_select`) y `autor_nombre` (el ayudante de la Fase 1);
base/gate con RLS activa y `actividades_select` sellada; 18 mutantes de desenlace triple; postflight con
los 4 gates SLA. Ensayo local en copia a paridad (Fase 1 instalada antes): PASS.

**Front** — el arranque ya no baja actividades; el store solo guarda las optimistas locales; la bitácora
del directorio pide sus 8 filas por la puerta (con estados cargando/error); los gates de evidencia
(descartar por «No responde», retroceso al anular) rehúsan sin historial en caché en vez de juzgar sobre
una lista vacía; las alertas legado en sesión real se callan con un aviso claro; `LIMITE_ACTIVIDADES_AMBITO`
y `listarActividadesDelAmbito` borrados; la ruta E2E de la RPC vieja retirada.

**Desvío del plan (con evidencia):** el Pipeline por columna con keyset no hace falta para esta fase y pasa a
la Fase 4, donde se retira la foto de leads.

## Lo que falta

1. Revisiones (`auditor-rls`, Codex) y PR.
2. **[Miguel]** instalar el SQL con `!` → md5 en prod → registrador → sonda anónima → fusionar → `/release-crm`.
3. Observar `actividades_del_ambito_fn` una semana en los logs de PostgREST y depreciarla por migración
   aparte (~27/09).
4. Fase 4: leads sin foto (búsqueda, Agenda y Citas con `lead_nombre`, bandejas, higiene, arranque sin
   leads, Pipeline por columna).

## Lecciones

- Antes de reescribir una pantalla, medir quién usa el dato de verdad en sesión real: tres de los cuatro
  «consumidores» del registro de actividades solo lo usaban en demo o como respaldo.
- Una lista que ya no se descarga no puede seguir alimentando gates ni alertas «por defecto vacío»: o se
  rehúsa con un mensaje claro, o se inventan señales falsas.
