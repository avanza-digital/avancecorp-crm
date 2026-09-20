---
tags: [crm, escalabilidad, tareas, agenda, fase-2, sin-topes]
actualizado: 2026-09-19
estado: SQL PREPARADO Y ENSAYADO (sin instalar en prod) · front en PR · publicar servidor ANTES que front
---

# Tareas sin tope — Fase 2 del plan «sin topes» (2026-09-19)

Continúa [[Historial por lead sin topes - Fase 1 (2026-09-19)]]. Relacionado con
[[Plan de escalabilidad del CRM a data gigante]] (F2 §5) y
[[Mapa de capas del servidor CRM - 2026-09-17]] (Etapa 1, foco 2: la agenda leía `crm.tareas` directo).

## Objetivo (fijado por Miguel el 19/09)

Que ninguna pantalla del CRM pierda tareas por el corte de 1 000 filas, hoy ni cuando haya diez
veces más, y que las tareas se lean por una puerta de la capa 3 en vez de leer la tabla directo.

## La causa, medida en producción

La agenda pedía las tareas pendientes del ámbito en UNA llamada directa a la tabla (`limit 2000`).
PostgREST recorta a **1 000** y la alarma del front (calibrada a 2 000) nunca sonaba.

| Quién | Pendientes | Frente al corte |
|---|---|---|
| Gerencia | 1 156 | **ya perdía 156** (las de vencimiento más lejano) |
| Supervisor Jorge | 699 | lo cruza en semanas |
| Supervisora Carmen | 457 | idem |
| Ritmo | 1 236 tareas nuevas / 7 días | |

## Lo que se hizo

**Servidor** — migración `20260919235100_crm_tareas_pendientes_keyset.sql` (molde de la Fase 1):

- Puerta `crm.tareas_pendientes_fn(p_limite=500 [1..1000], p_despues_de, p_despues_id) returns jsonb
  {version:1, items}`: `SECURITY INVOKER`, 22023 por input, 42501 solo por admisión al CRM. **Sin
  predicado de ámbito copiado**: devuelve exactamente lo que `tareas_select` ya mostraba en la tabla.
- Núcleo `private.tareas_pendientes_core`: página keyset `(vence_en asc, id asc)` en forma de tupla,
  con `lead_nombre`/`lead_etapa` embebidos (nullable) para que la Fase 4 deje a la agenda sin foto de
  leads.
- Un solo índice parcial `tareas_pendientes_keyset_idx (vence_en, id) where estado='pendiente' and activo`.
- Base preflight/gate (huella y conjunto de `tareas_select`, grants por columna de `crm.leads`, USAGE),
  gate propio (que exige además RLS activa en las dos tablas), **17 mutantes** con desenlace triple (detectado / no detectado / no aplicado), postflight con los 4 gates SLA. Reversa: drop de 5 funciones + índice.

**Front** — `listarTareasDelAmbito` en bucle por cursor (lotes de 500, pide 501) hasta que no llega la
fila extra; **sin constante de tope**; alarma de tendencia a 20 000 que avisa pero no corta; cursor de la
última fila cruda, que debe avanzar en sentido estricto (repetición, retroceso o ciclo cortan con error); dedupe por id entre lotes; fusión con postventa ordenada por unidades de código (no `localeCompare`), con la alarma de postventa en 2 000 porque su RPC conserva `limit 2000`. Las pantallas no cambian.

## Decisiones

- **Se descartó la «pista de ámbito»** que el plan contemplaba (un predicado redundante por vendedor +
  índice por vendedor): medido en prod bajo sesión real, sin ella la lectura tarda 15 ms para un analista
  y 13 ms para gerencia. Un predicado copiado por milisegundos que nadie nota es la semilla del próximo
  desfase (ya pasó una vez con la RPC vieja de actividades).
- El tope de `p_limite` es 1 000 (no 500) porque el front pide `lote + 1`; el payload es UN jsonb y
  `max_rows` no lo recorta.
- No se sella la restrictiva de postventa (`tareas_postventa_lectura`): solo resta, y la puerta la hereda
  por ser invoker.

## Ensayo

En el **contenedor local** (`supabase_db_avancecorp-f5-bank`, copia `tareas_cursor_20260919` desde una base
a paridad `20260917235656` con mundo SLA y postventa), archivo exacto en un solo mensaje: gate OK, 17/17
mutantes, matriz de 11 actores puerta = tabla en orden, keyset con empate de `vence_en`, volumen de 1 200
tareas en 3 lotes = tabla, errores correctos, plan por el índice nuevo con cursor profundo. Guion: `supabase/scripts/tareas-pendientes/ensayar-local.sh`. El
banco remoto `banco-f7` no sirve para esto (sin mundo SLA ni postventa) y no se tocó.

## Revisiones

- `auditor-rls`: sin fuga ni desfase; pidió el acta, cinco mutantes más y una cita corregida. Su caso
  «tarea visible con lead invisible» no se puede sembrar por soft-delete (el trigger cancela las tareas).
- Codex (por CLI en solo lectura, el MCP no conectó): tres P2 aceptados: alarma de postventa de vuelta a
  2 000, cursor con avance estricto (contra ciclos A→B→A), y RLS activa comprobada en el gate. También
  destapó que `localeCompare` desordenaba fechas con precisión distinta (defecto anterior a esta fase).

## Lo que falta

1. **[Miguel]** instalar el SQL con `!` → medir md5 en prod → registrador → sonda anónima.
2. Fusionar la PR, front en worktree limpio con `npm ci`, `release:crm`, preflight, publicar, smoke.
3. Acta en `MIGRACIONES.md` (ya escrita como «preparada»), mapa de capas (Foco 2), `main` el mismo día.
4. Fases 3 y 4 del plan (pipeline por columna, retirar la RPC vieja de actividades, leads sin foto).

## Lecciones

- El `node_modules` del taller puede ir por detrás del `package-lock` (faltaba la fuente de la PR #29):
  un `npm install` reconcilia sin borrar; los E2E y el build no arrancan sin eso.
- Soft-borrar un lead cancela sus tareas pendientes por trigger: «tarea visible con lead invisible» no
  se puede sembrar así; el único camino real es el re-apuntado por `inversionista_id` (postventa).
- Con `set role authenticated` + `request.jwt.claims` en un `DO` (no en un `select`) la sesión de ensayo
  no ensucia la salida de `psql`.
- `localeCompare` NO ordena fechas ISO con precisión mixta (su colación pone «.» antes que «+»): para
  cadenas del mismo formato y desplazamiento, comparar por unidades de código.
- Un mutante debe distinguir «detectado» de «no aplicado»: si el DDL de la mutación falla, contarlo como
  defensa probada es mentirse.
