ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (archivo:línea o fragmento citado de este encargo), TEST GAPS,
REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como
hipótesis lo no demostrado. Omite secciones vacías.

# Encargo: REFUTAR el PLAN G4 (gerencia ve pendientes y la lista de citas agendadas) — LEVEL 3

Contexto: CRM Avance Corp (Supabase, esquema `crm` expuesto como puerta, núcleo en `private`, RLS). La pantalla de
gerencia de Gestión Diaria está publicada (G0–G3). Hoy gerencia NO tiene pestaña Pendientes porque
`private.gestion_diaria_pendientes_core` exige rol supervisor. Miguel pidió «vamos con G4».

Busca dónde el plan abre acceso de más, rompe a los supervisores o a los bundles viejos, deja cifras que no son su
lista exacta, o se salta el ciclo de migraciones del proyecto. Pide REFUTAR, no aprobar.

## Hechos verificados por el PRIMARY
- Producción (lectura, 27/09): md5(pg_get_functiondef) vivo = repo:
  `private.gestion_diaria_equipo_ambito(uuid)` af06caf4d0ea5d392d9c36f069b3501b ·
  `private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)` f49dc3a7d106bef0f089980c9eb30db1 ·
  `crm.gestion_diaria_pendientes_fn(...)` d69dd41dbd7106283584e7d6b1cc9e1a ·
  `private.assert_gestion_diaria_pendientes()` 42446b8f98e22d6906745081f99c5ba7 (definer, sella las tres de arriba).
- RLS `crm.tareas` SELECT (`tareas_select`): `activo = true AND (vendedor_id IN private.vendedor_ids_visibles(auth.uid())
  OR (vendedor_id IS NULL AND asignado_supervisor_id IN ...) OR private.rol_crm(auth.uid()) = 'gerencia'
  OR private.es_lector_global())`; además `tareas_postventa_lectura`: `inversionista_id IS NULL OR private.postventa_visible(inversionista_id)`
  y `crm_actor_activo_gate`: `private.puede_acceder_crm()`.
- `gestion_diaria_equipo_core` (el detalle por analista que gerencia YA usa con `p_supervisor_id` nulo) cuenta
  pendientes/vencidas por analista bajo esa misma RLS con el mismo ámbito.
- «Citas agendadas» (cifra del pulso y del detalle): `crm.tareas` con `tipo = 'reunion'` y `creado_en` en la ventana
  Lima del día, SIN filtrar estado ni activo; en «fuera» entran también las de `vendedor_id` nulo cuando se piden
  (`array_position(p_vendedor_ids, null) is not null`). Misma definición que `metricas_agenda_fn`.
- Front: `validarPaginaPendientes` (strictObject) exige `p.supervisor_id === pedido.supervisor` (el id de quien
  consulta), `analista_id`, `solo_vencidas`, `limite`, orden estricto (vence_en,id), `hay_mas` ⇔ cursor, etc.
  Los bundles publicados de supervisor NO aceptan claves nuevas en la respuesta.
- Banco: el banco H3 sintético ya no existe; la receta del proyecto es un Docker local AISLADO con
  `supabase db dump --linked --schema public,crm,private` (paridad verificada por md5). El branch de Supabase
  está muerto para este proyecto. `db push` prohibido; `apply_migration` directo a prod prohibido; en prod lo
  aplica Miguel con `!` (`supabase db query --linked --file`).

## Cuerpos vivos (idénticos al repo, migración 20260923234404)
```sql
create function private.gestion_diaria_equipo_ambito(p_supervisor_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_supervisor uuid := p_supervisor_id;
  v_roster jsonb;
begin
  if v_uid is null or not private.puede_acceder_crm()
    or not (coalesce(v_rol in ('supervisor', 'gerencia'), false) or private.es_lector_global()) then
    raise exception 'No autorizado para consultar el equipo' using errcode = '42501';
  end if;
  if v_rol = 'supervisor' then
    if v_supervisor is not null and v_supervisor <> v_uid then
      raise exception 'Solo puedes consultar tu propio equipo' using errcode = '42501';
    end if;
    v_supervisor := v_uid;
  end if;
  if v_supervisor is not null and not exists (
    select 1 from crm.equipo_visible_fn() e
    where e.perfil_id = v_supervisor and e.activo and e.rol_crm = 'supervisor'
  ) then
    raise exception 'El supervisor no pertenece a tu ambito activo' using errcode = '42501';
  end if;

  -- Recorrer las aristas bajo RLS conserva los puentes inactivos del ámbito
  -- canónico. equipo_visible_fn filtra identidades efectivas: usarlo también
  -- para recorrer perdería descendientes activos bajo un supervisor revocado.
  -- Sólo las identidades activas autorizadas llegan al roster final.
  -- Se parte del roster, NO de actividades ni de cartera. UNION corta ciclos.
  with recursive visibles as materialized (select * from crm.equipo_visible_fn()),
  arbol as (
    select e.perfil_id from crm.equipo e where e.perfil_id = v_supervisor
    union
    select e.perfil_id from crm.equipo e join arbol a on e.supervisor_id = a.perfil_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('analista_id', e.perfil_id,
    'nombre_completo', e.nombre_completo) order by e.nombre_completo, e.perfil_id), '[]'::jsonb)
  into v_roster
  from visibles e where e.activo and e.rol_crm = 'vendedor'
    and (v_supervisor is null or e.perfil_id in (select a.perfil_id from arbol a));
  return jsonb_build_object('supervisor_id', v_supervisor, 'roster', v_roster);
end;
$function$;
revoke all on function private.gestion_diaria_equipo_ambito(uuid) from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_equipo_ambito(uuid) to authenticated;

create function private.gestion_diaria_pendientes_core(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_ambito jsonb;
  v_ahora timestamptz := statement_timestamp();
  v_respuesta jsonb;
  v_invalida boolean;
begin
  -- También protege la invocación directa del núcleo por authenticated.
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'supervisor' then
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;
  v_ambito := private.gestion_diaria_equipo_ambito(v_uid);
  if p_analista_id is null or p_solo_vencidas is null or p_limite is null
    or p_limite < 1 or p_limite > 100
    or (p_despues_de is null) <> (p_despues_id is null)
    or (p_despues_de is not null and not isfinite(p_despues_de)) then
    raise exception 'Parámetros de pendientes inválidos' using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_ambito->'roster') r
    where (r->>'analista_id')::uuid = p_analista_id) then
    -- Ajeno, inactivo e inexistente tienen idéntica respuesta.
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;

  -- Resumen y página comparten sentencia y RLS. La referencia no determina
  -- quién es responsable de la tarea ni elimina tareas sin lead visible.
  with base as materialized (
    select t.id, t.vendedor_id, t.tipo, t.titulo, t.vence_en,
      t.lead_id, t.perfil_id, t.inversionista_id
    from crm.tareas t
    where t.vendedor_id = p_analista_id and t.activo and t.estado = 'pendiente'
  ), resumen as (
    select coalesce(cardinality(array_agg(b.id)), 0) as tareas_pendientes,
      coalesce(cardinality(array_agg(b.id) filter (where b.vence_en < v_ahora)), 0) as tareas_vencidas,
      coalesce(bool_or(num_nonnulls(b.lead_id, b.perfil_id, b.inversionista_id) <> 1
        or not isfinite(b.vence_en)), false) as invalida
    from base b
  ), sonda as materialized (
    select b.* from base b
    where (not p_solo_vencidas or b.vence_en < v_ahora)
      and (p_despues_de is null or (b.vence_en, b.id) > (p_despues_de, p_despues_id))
    order by b.vence_en, b.id limit p_limite + 1
  ), pagina as materialized (
    select s.* from sonda s order by s.vence_en, s.id limit p_limite
  ), estado as (
    select coalesce(cardinality(array_agg(s.id)), 0) > p_limite as hay_mas from sonda s
  )
  select jsonb_build_object(
    'version', 1, 'zona', 'America/Lima', 'supervisor_id', v_uid,
    'analista_id', p_analista_id, 'generado_en', v_ahora, 'pendientes_al', v_ahora,
    'solo_vencidas', p_solo_vencidas, 'limite', p_limite,
    'resumen', jsonb_build_object('tareas_pendientes', r.tareas_pendientes,
      'tareas_vencidas', r.tareas_vencidas),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'vendedor_id', p.vendedor_id, 'tipo', p.tipo, 'titulo', p.titulo,
      'vence_en', p.vence_en, 'estado', 'pendiente',
      'referencia_tipo', case when p.lead_id is not null then 'lead'
        when p.perfil_id is not null then 'perfil' else 'postventa' end,
      'lead_id', case when nullif(btrim(l.nombre_completo), '') is not null then l.id end,
      'lead_nombre', nullif(btrim(l.nombre_completo), '')
    ) order by p.vence_en, p.id) from pagina p left join crm.leads l on l.id = p.lead_id), '[]'::jsonb),
    'hay_mas', e.hay_mas,
    'siguiente_cursor', case when e.hay_mas then (select jsonb_build_object(
      'despues_de', p.vence_en, 'despues_id', p.id)
      from pagina p order by p.vence_en desc, p.id desc limit 1) else null end
  ), r.invalida into v_respuesta, v_invalida from resumen r cross join estado e;
  if v_invalida then
    raise exception 'No se pudo confirmar la integridad de las tareas' using errcode = '22000';
  end if;
  return v_respuesta;
end;
$function$;
revoke all on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) to authenticated;

create function crm.gestion_diaria_pendientes_fn(
  p_analista_id uuid, p_solo_vencidas boolean default false, p_limite integer default 25,
  p_despues_de timestamptz default null, p_despues_id uuid default null
) returns jsonb
language sql stable security invoker set search_path = ''
as $function$
  select private.gestion_diaria_pendientes_core(p_analista_id, p_solo_vencidas,
    p_limite, p_despues_de, p_despues_id);
$function$;
revoke all on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) to authenticated;
comment on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) is
create function private.assert_gestion_diaria_pendientes() returns text
language plpgsql stable security definer set search_path = ''
as $function$
declare v_firma text; v_hash text;
begin
  for v_firma, v_hash in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'f49dc3a7d106bef0f089980c9eb30db1'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a')
  ) as firmas(firma, huella) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and md5(pg_get_functiondef(p.oid)) = v_hash) then
      raise exception 'H3: contrato, cuerpo o permisos alterados en %', v_firma;
    end if;
  end loop;
  perform private.assert_tareas_pendientes_base();
  perform private.assert_gestion_diaria_equipo();
  return 'OK: pendientes H3 paginados, ámbito canónico compartido, invoker/RLS y referencias mínimas';
end;
$function$;
revoke all on function private.assert_gestion_diaria_pendientes() from public, anon, authenticated, service_role;
```

## PLAN G4 (propuesto)

**G4a — Pendientes para gerencia (migración pequeña)**
1. `create or replace private.gestion_diaria_pendientes_core` con UN cambio de autorización:
   - `v_rol := private.rol_crm(v_uid)`; denegar 42501 si `v_uid is null or v_rol not in ('supervisor','gerencia')`
     (coordinador, vendedor, directorio/lector global siguen fuera, aunque el ámbito admita lector global).
   - `v_ambito := private.gestion_diaria_equipo_ambito(case when v_rol = 'supervisor' then v_uid end)`:
     supervisor → su árbol (sin cambio); gerencia → toda la operación visible (roster canónico con supervisor nulo,
     el mismo que ya usa `gestion_diaria_equipo_core` para gerencia; incluye «fuera»).
   - El resto del cuerpo, igual: validación de parámetros, pertenencia al roster (ajeno/inactivo/inexistente → 42501
     idéntico), página, resumen y verificación de integridad.
   - `supervisor_id` de la respuesta sigue siendo `v_uid` (el que consulta): para gerencia, su propio id. Misma forma
     y claves → los bundles viejos no cambian; el front de gerencia manda su id como `pedido.supervisor`.
     COMMENT de la puerta actualizado para decirlo.
2. Preflight: `assert_gestion_diaria()` + huellas vivas exactas de las 4 funciones de arriba; si difieren, abortar.
3. Re-sellado de `assert_gestion_diaria_pendientes` (sustituir la huella vieja del núcleo por la nueva, patrón
   `$sellar_equipo$` del repo) y postflight `assert_gestion_diaria()` + `assert_sla_*`. `notify pgrst`.
4. Reversa versionada: cuerpo y sello anteriores.
5. Pruebas en banco Docker aislado con el esquema de prod: gerencia lee a un analista de otro equipo y a uno de
   «fuera»; supervisor: respuesta idéntica a la anterior (comparación en la misma sentencia contra el cuerpo previo);
   vendedor, coordinador, lector global, analista inactivo, inexistente, anon → denegados; 1.005 tareas/cursor;
   postventa no visible. auditor-rls + esta revisión.
6. Orden: migración en prod (la aplica Miguel) ANTES del front; es aditiva para quien ya la usa.
7. Front de gerencia dentro de un equipo: pestaña Pendientes en la ficha del analista; aviso «N vencidas → Ver
   pendientes»; «Vencidas» (fila, ficha del equipo, total) llevan a la lista exacta del analista (Pendientes solo
   vencidas) a través del desglose por analista del equipo.

**G4b — Lista exacta de citas agendadas (consulta nueva)**
1. Puerta `crm.gestion_diaria_citas_fn(p_dia date, p_supervisor_id uuid default null, p_analista_id uuid default null,
   p_limite int default 25, p_despues_de timestamptz default null, p_despues_id uuid default null)` + núcleo
   `private.gestion_diaria_citas_core`, INVOKER, `search_path=''`, sin escrituras.
2. Ámbito: el mismo canónico (supervisor → su árbol, `p_supervisor_id` ajeno 42501; gerencia → todo o un equipo);
   `p_analista_id` debe pertenecer al roster (si no, 42501 idéntico). Para el grupo «fuera» en gerencia se incluyen
   las de `vendedor_id` nulo, igual que la cifra.
3. Definición IDÉNTICA a la cifra: `tipo='reunion'` y `creado_en` en [día Lima, día+1), sin filtrar estado/activo.
   Ítems: id, vendedor_id + nombre, lead (id y nombre solo si visible), `vence_en` (cuándo es la cita), estado,
   activo, creado_en. Orden y cursor por (creado_en, id); resumen con el total antes de paginar.
4. Mismo ciclo de pruebas/revisión/orden que G4a; asserts propios con huellas.
5. Front: «Citas agendadas» del total, de la fila y de la ficha del equipo y el cuadro del analista abren la lista.

Recomendación a Miguel: G4a primero (pequeño), G4b después.

## .ai/REVIEW_PROTOCOL.md (transcrito)
# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.
