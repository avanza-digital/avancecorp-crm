---
tags: [crm, rendimiento, indices, servidor]
fecha: 2026-09-30
---

# CRM — auditoría de índices (2026-09-30)

**Veredicto:** hoy **no falta ningún índice que valga la pena crear**. El único que faltaba de verdad
(`crm.inversionistas (perfil_id)`) se creó el 29/09 y ya trabaja (545 → 0,35 recorridos completos/s).
Lo que queda de recorridos completos **no lo arregla un índice**: es la forma de las consultas.
Ver [[CRM - perfil de carga lectura vs escritura (2026-09-29)]].

## Cómo se midió (solo lectura en producción, `supabase db query --linked`)
1. `pg_stat_user_tables` acumulado desde el arranque (25/09 20:50 UTC) y **dos fotos en vivo con 12 min
   de diferencia** (la cifra válida es la de hoy).
2. Claves foráneas sin índice (prefijo, distinguiendo índices parciales), duplicados e índices con 0 lecturas.
3. **Por función:** un bloque `DO` que fija los claims del actor con `set_config('request.jwt.claims', …)`,
   llama a la puerta y lee `pg_stat_xact_user_tables` (recorridos de ESA transacción) y termina SIEMPRE en
   `raise exception` → nada se escribe. Da, por llamada, qué tablas se recorren enteras y cuántas veces.
   (`pg_stat_statements.track = top`: las consultas internas de plpgsql no se ven de otra forma.)

## Lo que se recorre entero hoy (ventana en vivo de 12 min)
| tabla | recorridos/s | filas leídas/s | causa |
|---|---|---|---|
| `crm.leads` (2.654 filas) | 0,52 | 1.388 | núcleo SLA: **2 recorridos por llamada**, incluso pidiendo UN lead |
| `crm.tarea_sla_contexto` (5.337) | 0,21 | 1.139 | núcleo SLA: 1 recorrido por llamada (hash join sobre la tabla entera) |
| `crm.equipo` (24 filas, 8 páginas) | 21 | 331 | tabla diminuta: el recorrido ES el plan más barato; un índice no ayuda |
| `crm.inversionistas` | 0,35 | 200 | residual tras el índice del 29/09 (era 545/s) |
| resto | < 0,3 | < 50 | tablas de 8–136 filas |

**Causa del núcleo SLA (`private.sla_hechos_actuales`):** el filtro es
`(p_lead_ids is null or l.id = any(p_lead_ids))` y la función devuelve `ROWS 1000` (valor por defecto):
el planificador no puede usar la clave primaria y hace hash join con `leads` y `tarea_sla_contexto` enteras.
Medido: `estado_sla_leads_v2_fn(array[un_lead])` = 45 ms con 2 recorridos de leads + 1 de contexto; lo mismo en
`avisos_sla_resumen_v2_fn`, `cola_accion_v3_fn`, `gestion_diaria_*`, `gestion_diaria_pulso_fn`. Son ~8 MB leídos
por llamada, unos pocos ms: el tiempo real está en el bucle plpgsql y el JSON (medido el 29/09). **Arreglo =
reescribir la consulta del núcleo sellado (proyecto aparte), no un índice.**

## Otros hallazgos (ninguno pide índice)
- `inversionista_ficha_fn` (1.575 llamadas, 0,5 s): el recorrido entero de `crm.tareas` (7.052 filas) por la
  función en el `OR` existe, pero **NO es el coste** (ensayo con familia precalculada: idéntica 29/29, 499 → 492 ms;
  solo se evalúa cuando postventa es visible y cuesta ~15 ms). El coste real está abajo («Ficha: dónde se va el tiempo»).
- `gestion_diaria_pulso_fn`: 1.511 recorridos de `equipo` y 34 de `public.perfiles` por llamada (bucles por
  persona); tablas pequeñas, coste bajo; es forma de consulta.
- Claves foráneas sin índice: 102, casi todas `creado_por/actualizado_por → perfiles` (auditoría); solo
  importan al borrar perfiles y aquí no se borra (soft-delete). Las dos con datos, `tareas.inversionista_id`
  (solo índice parcial de pendientes) y `lead_sla_*.politica_id`, no generan recorridos medibles (tareas 0,00/s).
- Duplicado real: `inv_fusiones_fusionado_idx` e `inv_fusiones_fusionado_uidx` (misma columna, 8 kB).
- **156 de 370 índices de `crm` con 0 lecturas desde el 25/09**; los 9 mayores pesan 100–330 kB
  (`lead_sla_etapas_periodo_idx`, `cartera_lecturas_persona_fecha_idx`, `lead_asignaciones_sla_global_cohorte_idx`,
  `tarea_sla_contexto_ciclo_idx`, `sla_operacion_recibos_lead_idx`…). Con ~3.200 filas escritas al día su coste es
  despreciable: **no se tocan** (CERRAR → OBSERVAR → DERRIBAR).
- Lecturas directas del front a `crm.leads` (5.250 llamadas): 3 ms cada una; sin problema.
- Estadísticas del planificador: `leads`/`tareas` analizadas hoy; `inversionistas`, `equipo`, `cierres_externos`
  sin autoanalyze desde el 25/09 pero `reltuples` correcto (tablas pequeñas).

## Ficha de inversionista: dónde se va el tiempo (medido 30/09 con `track_functions` en transacción deshecha)
De 490 ms: **`private.cartera_f5_fuentes()` se calcula 7 veces por ficha = 291 ms** (ficha → `cartera_f5_exigir` ×2 →
`cartera_inversionistas_estado_fn` ×4 → fuentes; `postventa_estado_fn` ×1; `personas_visibles(uuid)` ×2; la CTE `fuentes`).
Dentro de fuentes, por cada una de las 726 fuentes se llama a `inversionista_canonica()` (13.408 llamadas = 218 ms) y a
`analista_atribuido_cadena()` (4.795 = 123 ms): dos CTE recursivas por FILA. Hoy hay 0 fusiones (canónica = id).

**Arreglo ensayado (scripts en `CRM-Avance-Corp/supabase/scripts/ensayo-cartera-f5-fuentes-mapas/`):** mismo cuerpo de
`cartera_f5_fuentes()` con dos mapas jsonb calculados UNA vez por llamada (`canon_map`: id → canónica con el mismo paseo
de 16 niveles; `atrib_map`: contrato → analista del primer ancestro «upgrade», misma cadena con visitados y tope 100) y
leídos con `->>`. Oráculo: **726/726 filas, md5 igual**; **42 → 11 ms** por llamada. Punta a punta con el reemplazo
deshecho: **33/33 salidas idénticas** (29 fichas, agenda, estado, cartera, postventa_estado); ficha **509 → 284 ms**,
agenda de postventa 164 → 97, cartera de inversionistas 193 → 126, estado de cartera 52 → 19. Beneficia a los 10
llamadores de fuentes. Sin guardián que la selle (solo `assert_cola_v3` menciona `inversionista_canonica`, que no se toca).
⚠️ Una CTE leída con subconsulta correlacionada por fila salió MÁS lenta (82 ms): el mapa jsonb es lo que funciona.

## Fase 1 HECHA (30/09 tarde): migración preparada, PR #144
Objetivo fijado por Miguel con `/goal` tras el plan por fases. Rama `crm/cartera-f5-fuentes-mapas` (worktree
`wt-cartera-f5-fuentes-mapas`, nacida del final de la cadena #143 `crm/gestion-diaria-solo-operativos`, no de `main`),
**PR #144** apilada. Migración `20260930172255_crm_cartera_f5_fuentes_mapas` (huella viva `94fa33cf…` → nueva `fa15f776…`,
REPEATABLE READ, oráculo de filas dentro de la transacción, preflight de las huellas de `inversionista_canonica` y
`analista_atribuido_cadena`) + `scripts/cartera-f5-fuentes-mapas/` (reversa con COMMENT previo, registrar de 2 sentencias,
verificar, prueba sintética, contexto de seguridad, ensayo-oraculo, LEEME con el orden de aplicación).
- Banco Docker propio `avancecorp-f5-fuentes-20260930` (imagen `supabase/postgres:17.6.1.105`, `db dump --linked --schema
  public,crm,private`; paridad de cuerpos crm 278 / private 536 con el MISMO md5 que prod): ciclo completo + 2 negativos.
  Prueba sintética 13/13 idénticas con expectativas explícitas.
- Codex r1 CHANGES_REQUESTED: P2 «empates de atribución» **rechazado**: `operaciones_cartera.contrato_nuevo_id` es UNIQUE
  (cadena lineal; el intento de sembrar el empate falló por esa clave); un desempate delegado se ensayó y se retiró. P2
  «huellas de las funciones copiadas» **aceptado**. auditor-rls PASS con 6 P3, todos atendidos.
- 🔴 El clasificador bloquea al modelo cualquier `create or replace` en prod, incluso dentro de una transacción deshecha:
  el ensayo de aceptación (`ensayo-oraculo.sql`) y la migración los lanza Miguel con `!`.
- **Codex r2: APPROVE** (retira el P2 de empates por el UNIQUE; un P3 sobre la foto de la sintética, corregido: «?» = coherencia
  NULL, «!» = false; rutas por inversión y por lead añadidas → 15/15 idénticas). Commits `218911d6` + `f5675b7c` en PR #144.
- **✅ Fase 3 EN PROD 30/09 ~13:49 Lima por `!` de Miguel:** ensayo deshecho 33/33 idénticas (ficha 476 → 269, agenda 159 → 98,
  cartera 178 → 125, estado 49 → 18) → migración → registro (2 sentencias) → `verificar.sql`: huella OK, fuentes 728 en **11,2 ms**
  (antes ~42), ficha **302 ms** (antes ~500), agenda de postventa **101** (antes ~165), cartera de inversionistas **95** (antes ~190)
  → advisors 242 = 242, ninguno nuevo. Ledger cerrado (`e79ecca0`, PR #144). Banco Docker propio retirado.
- **✅ Fase 4 (a) MEDIDO con tráfico real el 01/10** (tramo 30/09 18:51 → 01/10 20:51 UTC, `foto-trafico.sql` menos la foto T0 del
  ledger): ficha de inversionista 670 llamadas, **920 → 351 ms (−62 %)**; agenda de postventa 1.997, **286 → 107 (−62 %)**; cartera de
  inversionistas 1.596, **692 → 123 (−82 %)**; estado de cartera 163 → 44; estado de postventa 174 → 84; ficha de postventa 182 → 97;
  gestión del inversionista 584 → 170. Ledger `0e49bcc4`, PR #144. La media histórica incluye los días previos a los pasos 1–3
  del refactor, por eso la mejora real supera a la del ensayo aislado.
- **Fase 4 (b), pendiente:** traer la cadena #140–#144 a `main`: Miguel fusiona las PR (por squash) y el `main` local sigue bloqueado por
  `MIGRACIONES.md` e `Inicio.md` sin commitear de otras sesiones (además `main` local aún no contiene ni #139).

## Qué sí pagaría (por impacto)
1. **`cartera_f5_fuentes()` con mapas** (arriba): migración de una función privada, misma firma y filas; LEVEL 2–3
   (10 puertas la usan) → oráculo md5 en la migración, `test-rls.mjs`, advisors, Codex + auditor-rls. Pendiente de OK de Miguel.
2. Después, opcional: que la ficha calcule la cartera 1 vez y no 7 (exigir/estado se repiten); con el paso 1 vale ~70 ms.
3. Núcleo SLA: filtro por `p_lead_ids` sin `is null or` (dos ramas) y `ROWS` realista → quita 3 recorridos por
   llamada en ~0,25 llamadas/s. Toca el motor sellado (`assert_sla_nucleo`): mini-proyecto con plan y OK de Miguel.
