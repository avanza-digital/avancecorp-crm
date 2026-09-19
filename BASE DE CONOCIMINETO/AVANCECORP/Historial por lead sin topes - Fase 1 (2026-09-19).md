---
tags: [crm, escalabilidad, historial, actividades, fase-1, sin-topes]
actualizado: 2026-09-19
estado: EN PRODUCCIÓN COMPLETA (19/09) — SQL ~15:50 Lima, registrada; front ~16:36 Lima (release crm-20260919T213432Z-4094df3c9224)
---

# Historial por lead sin topes — Fase 1 (2026-09-19)

Relacionado con [[Plan de escalabilidad del CRM a data gigante]] (F2 §5 y F3),
[[Mapa de capas del servidor CRM - 2026-09-17]] y [[Inicio]].

## El problema que Miguel reportó

«El historial de seguimientos no está sincronizado entre analista, supervisor y
gerencia: a un analista le sale un seguimiento y al supervisor solo "Lead
creado"». Y después: **«lo que no quiero es que haya esos límites»**.

## La causa, medida en producción

La ficha del lead no pedía el historial de ESE lead. El front descargaba TODAS
las actividades del ámbito del usuario con `crm.actividades_del_ambito_fn`
(DEFINER, sin parámetros, `order by creado_en desc limit 10000`) y filtraba por
lead en el navegador. PostgREST recorta cada respuesta a **1 000 filas**
(`max_rows`), así que el `limit 10000` nunca actuó y la alarma del front
(calibrada a 10 000) nunca sonó: recorte mudo.

| Usuario | Actividades en 365 d | Fila 1 000 (frontera de lo que veía) |
|---|---|---|
| Analista más activa | 1 473 | 31/08 |
| Supervisor Jorge | 5 609 | 15/09 |
| Supervisora Carmen | 8 016 | 15/09 |
| Gerencia | 13 626 | 17/09 |

Ritmo: 2 888 actividades por semana. «Lead creado» no es una actividad: es un
ítem fijo del front, y verlo solo significa cero filas para ese lead.

Mismo defecto de clase en las otras dos lecturas del arranque: las tareas del
ámbito (2 000 en una llamada → 1 000; hay 1 161 pendientes) y la foto de leads
(`MAX_LEADS_AMBITO = 2000`; había 1 983 con +398 por semana).

## Lo que se hizo (Fase 1 de 4)

**Servidor** — migración `20260919185718_crm_actividades_de_lead.sql` (EN PRODUCCIÓN el 19/09 ~15:50 Lima, registrada; ensayada antes en el banco `banco-f7`: gate OK, 5/5 mutantes, matriz de roles exacta), en capas:

- Núcleo `private.actividades_de_lead_core(uuid,int,timestamptz,uuid)`: una
  página keyset `(creado_en desc, id asc)` del historial de UN lead más las
  señales «alguna vez» (`tiene_reunion_realizada`, `tiene_contacto`,
  `ultima_conversacion_en`). `security invoker`, puro, sin `count(`.
- Puerta `crm.actividades_de_lead_fn(p_lead_id, p_limite=100, p_antes_de, p_antes_id)
  returns jsonb {version, items, senales}`: valida (22023), exige admisión al
  CRM (42501) y que el lead sea visible por `leads_select` (42501 «Lead fuera de
  tu cartera»: fuera de ámbito, borrado o inexistente responden igual; nunca un
  historial vacío). **INVOKER**: el alcance lo ponen `actividades_select` y
  `leads_select`, co-extensivas, cuyas huellas md5 se sellan en preflight y gate.
- Ayudante `private.nombre_de_autor(uuid)`: el único DEFINER, acotado a
  `crm.equipo`, para firmar cada gestión (la policy de `perfiles` solo deja leer
  la fila propia). Precedente: Ficha 360.
- Gate propio `private.assert_actividades_de_lead()` + los 4 gates del mundo SLA.
- `crm.actividades_del_ambito_fn` NO se toca (sigue viva para las pantallas de
  equipo hasta la Fase 3: cerrar → observar → derribar).

**Front** (PR #28, fusionada por squash como `4094df3c`; PUBLICADO ~16:36 Lima como `crm-20260919T213432Z-4094df3c9224`, smoke OK):

- `useHistorialLead` (páginas por cursor, TanStack) + `useActividadesDeLead`
  (fusiona las páginas con las gestiones recién registradas; en demo no toca la
  red). Regla de deduplicación de la fila optimista: vive hasta que llega una
  lectura del servidor POSTERIOR a su creación (su id es inventado, no sirve).
- `Timeline` de la ficha: estados honestos (cargando, error con reintentar,
  vacío) y «Cargar más gestiones»; el pliegue «Ver N anteriores» sigue igual.
- «Descartar por No responde», «Cerrar tarea» y el aviso de retroceso al anular
  una cita leen el historial por lead; el retroceso usa las señales «alguna
  vez» (una página de 100 podía ocultar la reunión que sí hubo).
- Enlaces `#lead=<id>` abren cualquier lead (ya no se contrastan contra la foto
  en memoria).
- Puente temporal: `MAX_LEADS_AMBITO` 2 000 → 5 000 con alarma de tendencia a
  4 000; muere en la Fase 4.

## Lo que falta (fases 2–4, plan aprobado)

- **Fase 2:** tareas por cursor (`crm.tareas_pendientes_fn`, dos índices).
- **Fase 3:** Pipeline por columna, `resumen_reparto_fn` en Hoy/supervisor,
  feed de recientes para directorio; el arranque deja de bajar actividades;
  la RPC vieja pasa a observación y luego a deprecación.
- **Fase 4:** ninguna pantalla depende de la foto de leads (búsqueda, agenda,
  bandeja de reparto, higiene, arranque). Cero topes.

Detalle ejecutable en `~/.claude/plans/ok-dame-un-plan-replicated-shannon.md`
y en el ledger `supabase/migrations/MIGRACIONES.md` (entrada 20260919185718).

## Lecciones

- El `node_modules` enlazado por symlink al taller no sirve para construir el
  tronco si otra PR añadió dependencias: `npm ci` propio en el worktree.
- Cada build lleva su id: el smoke se compara contra el ZIP publicado, no
  contra un `dist` reconstruido después.

- Un `limit` en la función NO es el límite efectivo: PostgREST tiene el suyo
  (`max_rows`), y la alarma hay que calibrarla contra ÉSE.
- «Sin límites» no es «descargar todo»: es que cada pantalla pida al servidor
  exactamente lo que muestra.
- Una fila optimista con id inventado no se deduplica por id: se deduplica por
  TIEMPO (lectura posterior a su creación).
- Las preguntas «alguna vez» (¿hubo reunión?) no pueden responderse con una
  página del historial: viajan como señales calculadas en el servidor.
