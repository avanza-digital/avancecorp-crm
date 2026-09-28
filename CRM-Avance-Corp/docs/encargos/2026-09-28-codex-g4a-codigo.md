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

# Encargo: REFUTAR el CÓDIGO de G4a (Gerencia lee pendientes) antes de aplicarlo en producción — LEVEL 3

Ya revisaste el PLAN G4 (CHANGES_REQUESTED: rol nulo explícito en G4a; G4b con selector de ámbito y roles
explícitos): incorporado y aprobado por Miguel. Esta es la 2.ª y última revisión: el código de G4a (G4b va aparte).
Busca escalada, fugas, huecos del re-sellado/reversa/registrador, pruebas que no acrediten lo que dicen, y
riesgos del orden de publicación. Refuta.

## Verificación del PRIMARY (hechos)
- Producción (lectura, 27/09): huellas vivas = repo (ámbito af06…, núcleo f49d…, puerta d69d…, gate 42446b8f…);
  `assert_gestion_diaria()` y los 4 `assert_sla_*` en verde; md5(prosrc) del núcleo H3 vivo = fde88f7d….
- Banco Docker AISLADO (`crm-banco-g4`, esquema de prod por `db dump`, paridad 27/27 por md5, actores sintéticos,
  config SLA copiada de prod con autores ficticios):
  · migración aplicada en UN mensaje → huellas nuevas núcleo a0bde87d… / gate 6aecb25a…; `assert_gestion_diaria()` OK.
  · `test-g4a.sql` → `G4A_OK` (transcrito abajo).
  · reversa → 4 huellas H3 exactas + `assert_gestion_diaria()` OK; Gerencia vuelve a 42501. Reaplicación → Gerencia
    autorizada y `G4A_OK` de nuevo.
  · registrador probado (dentro de ROLLBACK, con una `schema_migrations` local): registra 1 fila exacta.
- auditor-rls (subagente del proyecto): migración sin P0/P1; pidió arreglar pruebas (inactivo fabricado, casos del
  plan, bloque en `test-rls.mjs`, ensayo de la reversa) y fijar el gate por identidad en `$sellar$` → hecho.
- Front: `npm run check` NO corrido aún con G4a (unitarias de Gestión Diaria + hook: PASS, 835 + 18).

## Migración `supabase/migrations/20260928043728_crm_gestion_diaria_pendientes_gerencia.sql`
```sql
-- G4a (27/09/2026): Gerencia lee los pendientes de cualquier analista de la operación.
-- Plan G4 v2 aprobado por Miguel («G4a y luego G4b») y revisado por Codex.
--
-- Solo cambia la AUTORIZACIÓN del núcleo H3 (20260923234404):
--   · Supervisión: su árbol, como hasta ahora.
--   · Gerencia: el roster canónico con supervisor nulo (toda la operación visible, «fuera»
--     incluido), el mismo que ya usa gestion_diaria_equipo_core para Gerencia.
--   · Coordinación, analistas, lector global y rol nulo: 42501, como hasta ahora.
-- Misma firma y mismas claves: `supervisor_id` sigue siendo quien consulta (para Gerencia,
-- su propio id), así los bundles publicados (v.strictObject) no cambian. No toca tablas,
-- políticas ni grants; la lectura sigue siendo INVOKER bajo la RLS de crm.tareas, que ya
-- concede a Gerencia todas las tareas activas (las de postventa siguen además bajo la
-- política restrictiva de banderas `tareas_postventa_lectura`, igual para la cifra y la lista).
--
-- Reversa: supabase/scripts/g4/reversa-g4a.sql (cuerpo y sello anteriores). Si el front de
-- Gerencia ya muestra Pendientes, revertir PRIMERO el front y después la base.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
declare v_firma text; v_huella text;
begin
  perform private.assert_gestion_diaria();
  -- Huellas vivas exactas (producción, 27/09): si algo cambió, no se adapta en silencio.
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'f49dc3a7d106bef0f089980c9eb30db1'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a'),
    ('private.assert_gestion_diaria_pendientes()', '42446b8f98e22d6906745081f99c5ba7')
  ) as h(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_huella then
      raise exception 'G4a: cambió % en vivo; revisar antes de continuar', v_firma;
    end if;
  end loop;
end $preflight$;

CREATE OR REPLACE FUNCTION private.gestion_diaria_pendientes_core(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_ambito jsonb;
  v_ahora timestamptz := statement_timestamp();
  v_respuesta jsonb;
  v_invalida boolean;
begin
  -- También protege la invocación directa del núcleo por authenticated. Supervisión y,
  -- desde G4a (27/09/2026), Gerencia; el rol nulo se rechaza explícitamente (Codex).
  if v_uid is null or not coalesce(v_rol in ('supervisor', 'gerencia'), false) then
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;
  -- Supervisión: su árbol, como en H3. Gerencia: el roster canónico con supervisor nulo
  -- (toda la operación visible, «fuera» incluido), el mismo de gestion_diaria_equipo_core.
  v_ambito := private.gestion_diaria_equipo_ambito(case when v_rol = 'supervisor' then v_uid end);
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

-- El cuerpo creado debe ser EXACTAMENTE el revisado; después se re-sella el gate H3
-- sustituyendo solo la huella del núcleo (patrón $sellar_equipo$ de H3).
do $sellar$
declare v_def text; v_huella text;
begin
  v_huella := md5(pg_get_functiondef('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure));
  if v_huella is distinct from 'a0bde87db9ea86694ba4ee79dc109729' then
    raise exception 'G4a: el núcleo creado no es el revisado (%)', v_huella;
  end if;
  -- El gate se fija por identidad en esta misma sentencia (auditor-rls): nada de copiar un
  -- cambio ajeno confirmado entre el preflight y aquí.
  v_def := pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure);
  if md5(v_def) is distinct from '42446b8f98e22d6906745081f99c5ba7' then
    raise exception 'G4a: el gate H3 cambió antes de re-sellarlo';
  end if;
  if (length(v_def) - length(replace(v_def, 'f49dc3a7d106bef0f089980c9eb30db1', ''))) <> 32 then
    raise exception 'G4a: la huella anterior del núcleo no aparece una sola vez en el gate H3';
  end if;
  execute replace(v_def, 'f49dc3a7d106bef0f089980c9eb30db1', v_huella);
  if md5(pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure)) is distinct from '6aecb25a8a66e10cc5dcae69afb66281' then
    raise exception 'G4a: el gate re-sellado no es el revisado';
  end if;
end $sellar$;

comment on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) is
  'Núcleo H3+G4a: tareas actuales de un analista del ámbito de quien consulta (Supervisión: su árbol; Gerencia: toda la operación visible). INVOKER bajo RLS; cursor vence_en/id; supervisor_id = quien consulta.';
comment on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) is
  'H3+G4a: tareas actuales del analista autorizado (Supervisión: su árbol; Gerencia: toda la operación visible); cursor vence_en/id, límite 1–100, resumen previo al filtro y referencia mínima bajo RLS. supervisor_id devuelve a quien consulta. Sin escrituras ni totales de leads.';

do $postflight$
begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end $postflight$;
notify pgrst, 'reload schema';
commit;
```

## Reversa `supabase/scripts/g4/reversa-g4a.sql` (sin el cuerpo H3, que es el de 20260923234404 tal cual)
```sql
-- Reversa de G4a (20260928043728): restaura el núcleo H3 y su sello. Si el front de
-- Gerencia ya muestra Pendientes, revertir PRIMERO el front (release anterior) y después esto.
-- Aplicar en un solo mensaje (supabase db query --linked --file …), como la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
begin
  if md5(pg_get_functiondef('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure)) is distinct from 'a0bde87db9ea86694ba4ee79dc109729'
    or md5(pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure)) is distinct from '6aecb25a8a66e10cc5dcae69afb66281' then
    raise exception 'Reversa G4a: el núcleo o el gate vivos no son los de G4a; no se toca';
  end if;
end $preflight$;

-- [cuerpo H3 íntegro de 20260923234404, md5(prosrc)=fde88f7d…]


do $sellar$
declare v_def text;
begin
  if md5(pg_get_functiondef('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure)) is distinct from 'f49dc3a7d106bef0f089980c9eb30db1' then
    raise exception 'Reversa G4a: el núcleo restaurado no es el de H3';
  end if;
  v_def := pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure);
  if (length(v_def) - length(replace(v_def, 'a0bde87db9ea86694ba4ee79dc109729', ''))) <> 32 then
    raise exception 'Reversa G4a: la huella de G4a no aparece una sola vez en el gate H3';
  end if;
  execute replace(v_def, 'a0bde87db9ea86694ba4ee79dc109729', 'f49dc3a7d106bef0f089980c9eb30db1');
end $sellar$;
comment on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) is
  'H3: tareas actuales del analista autorizado del supervisor; cursor vence_en/id, límite 1–100, resumen previo al filtro y referencia mínima bajo RLS. Sin escrituras ni totales de leads.';
comment on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) is null;
do $postflight$
begin
  if md5(pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure)) is distinct from '42446b8f98e22d6906745081f99c5ba7' then
    raise exception 'Reversa G4a: el gate H3 no quedó como antes';
  end if;
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end $postflight$;
notify pgrst, 'reload schema';
commit;

```

## Registrador `supabase/scripts/g4/registrar-20260928043728.sql` (sin el cuerpo embebido)
```sql
-- Registra 20260928043728 (crm_gestion_diaria_pendientes_gerencia) CON su cuerpo — fail-closed.
-- Orden de la casa: PRIMERO aplicar la migración con `db query --linked --file`, DESPUÉS este
-- registrador. El cuerpo embebido es el archivo de la migración tal cual (no editar a mano).
do $reg_g4a$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_g4a$<migración 20260928043728 íntegra>$mig_g4a$;

  -- 1) La migración tiene que estar aplicada TAL CUAL: núcleo y gate con las huellas revisadas.
  if md5(pg_get_functiondef('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure)) is distinct from 'a0bde87db9ea86694ba4ee79dc109729'
     or md5(pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure)) is distinct from '6aecb25a8a66e10cc5dcae69afb66281' then
    raise exception 'registrar G4a: la migración 20260928043728 no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if private.assert_gestion_diaria_pendientes() not like 'OK:%' then
    raise exception 'registrar G4a: el gate propio no responde OK';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260928043728' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar G4a: la versión 20260928043728 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260928043728', 'crm_gestion_diaria_pendientes_gerencia', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260928043728' and name = 'crm_gestion_diaria_pendientes_gerencia'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar G4a: la relectura no encontró la fila exacta';
  end if;
end $reg_g4a$;

```

## Pruebas `supabase/scripts/g4/test-g4a.sql` (sin el cuerpo H3 embebido)
```sql
-- G4a: Gerencia lee pendientes de cualquier analista de la operación. Datos sintéticos;
-- lecturas como authenticated/anon con identidad efectiva; todo termina en ROLLBACK.
-- Requiere la migración 20260928043728 instalada. Casos pedidos por auditor-rls (27/09).
begin;
set local statement_timeout = '300s';
set local timezone = 'America/Lima';
do $$ begin
  if shobj_description((select oid from pg_database where datname = current_database()), 'pg_database')
    is distinct from 'BANCO SINTETICO G4 / sin produccion' then
    raise exception 'G4a: sólo en el banco sintético G4';
  end if;
end $$;

create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'G4a: %', mensaje; end if; end $$;
create function pg_temp.codigo(comando text) returns text language plpgsql as $$
declare recibido text; begin
  begin execute comando; exception when others then recibido := sqlstate; end;
  return coalesce(recibido, 'ninguno');
end $$;
create function pg_temp.denegada(comando text, codigo text default '42501') returns void language plpgsql as $$
declare recibido text := pg_temp.codigo(comando); begin
  perform pg_temp.afirmar(recibido = codigo, format('error esperado %s; recibido %s: %s', codigo, recibido, comando));
end $$;
create function pg_temp.como(actor uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', coalesce(actor::text, ''), true); end $$;

-- Actores efectivos (como H3): supervisor con rol vigente; «ajeno» FUERA del árbol de sup1
-- (se resuelve con el propio ámbito canónico, así los anidados no cuelan); v2 se inactiva abajo.
create temporary table g4_actores as
with sups as (
  select e.perfil_id from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'supervisor'
    and exists (select 1 from crm.equipo v where v.supervisor_id = e.perfil_id and private.rol_crm(v.perfil_id) = 'vendedor')
  order by e.perfil_id limit 1
), bajo as (
  select v.perfil_id from crm.equipo v, sups s
  where v.supervisor_id = s.perfil_id and private.rol_crm(v.perfil_id) = 'vendedor' order by v.perfil_id
)
select (select perfil_id from sups) sup1,
  (select perfil_id from bajo limit 1) v1,
  (select perfil_id from bajo offset 1 limit 1) v2,
  -- «Fuera» = analista activo sin supervisor EFECTIVO (nulo o con el supervisor dado de baja), como en el pulso.
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'vendedor'
    and (supervisor_id is null or private.rol_crm(supervisor_id) is distinct from 'supervisor') order by perfil_id limit 1) fuera,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'coordinador' limit 1) coordinador,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'gerencia' limit 1) gerente,
  (select id from public.perfiles where activo and rol = 'directorio' limit 1) global,
  gen_random_uuid() nadie, gen_random_uuid() inversionista, null::uuid ajeno;
select pg_temp.como(sup1) from g4_actores;
set local role authenticated;
create temporary table g4_roster_sup1 as
select (r->>'analista_id')::uuid id from jsonb_array_elements(private.gestion_diaria_equipo_ambito(null)->'roster') r;
reset role;
update g4_actores set ajeno = (select e.perfil_id from crm.equipo e where private.rol_crm(e.perfil_id) = 'vendedor'
  and private.rol_crm(e.supervisor_id) = 'supervisor' and e.perfil_id not in (select id from g4_roster_sup1) order by e.perfil_id limit 1);
grant select on g4_actores to authenticated, anon;
select pg_temp.afirmar(sup1 is not null and v1 is not null and v2 is not null and ajeno is not null and fuera is not null
  and coordinador is not null and gerente is not null and global is not null,
  'faltan actores sintéticos (sup1 con dos analistas, ajeno fuera de su árbol, fuera, coordinador, gerente, global)') from g4_actores;
select pg_temp.como(global) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(private.es_lector_global(), 'el actor «global» debe ser lector global efectivo');
reset role;

-- El núcleo H3 con otro nombre, acreditado por identidad (md5 de su cuerpo vivo en producción).
create function pg_temp.core_h3(...) -- cuerpo H3 íntegro (acreditado abajo por md5(prosrc))


select pg_temp.afirmar(md5(prosrc) = 'fde88f7d2cca6a912693733969391db5', 'la copia H3 de la prueba no es el cuerpo vivo')
from pg_proc where oid = 'pg_temp.core_h3(uuid,boolean,integer,timestamptz,uuid)'::regprocedure;

-- Fixtures (sólo aquí se desactivan triggers de usuario; se restauran enseguida).
alter table crm.tareas disable trigger user;
update crm.tareas set activo = false
where vendedor_id in (select unnest(array[v1, v2, ajeno, fuera]) from g4_actores);
insert into crm.tareas(perfil_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select a.v1, a.v1, 'tarea', 'G4A V1 ' || i, now() - make_interval(secs => i), a.v1
from g4_actores a cross join generate_series(1, 1004) i;
insert into crm.tareas(perfil_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select a.v1, a.v1, 'tarea', 'G4A V1 FUTURA', now() + interval '1 day', a.v1 from g4_actores a;
insert into crm.tareas(perfil_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select x.id, x.id, 'tarea', 'G4A ' || x.etiqueta, now() - interval '1 hour', x.id
from g4_actores a cross join lateral (values (a.v2, 'V2'), (a.ajeno, 'AJENO'), (a.fuera, 'FUERA')) x(id, etiqueta);
alter table crm.inversionistas disable trigger user;
insert into crm.inversionistas(id, responsable_relacion_id, creado_por) select inversionista, ajeno, gerente from g4_actores;
alter table crm.inversionistas enable trigger user;
insert into crm.tareas(inversionista_id, postventa_revision, vendedor_id, tipo, titulo, vence_en, creado_por)
select inversionista, 1, v1, 'tarea', 'G4A POSTVENTA', now() - interval '2 hours', v1 from g4_actores;
alter table crm.tareas enable trigger user;
-- Postventa visible como en producción: las tres banderas de su candado (el banco no siembra
-- la configuración multiempresa; se ponen aquí, sin triggers, y el ROLLBACK las deshace).
alter table crm.multiempresa_flags disable trigger user;
insert into crm.multiempresa_flags(nombre, activo) values ('resolver_en_puertas', true), ('ficha_360_neutral', true), ('postventa_neutral', true)
on conflict (nombre) do update set activo = true;
alter table crm.multiempresa_flags enable trigger user;
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(private.postventa_visible(inversionista), 'postventa visible para Gerencia con las banderas') from g4_actores;
reset role;

-- 1. Supervisión: idéntica a H3 (respuesta y errores); fuera de su árbol, 42501.
select pg_temp.como(sup1) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(pg_temp.core_h3(v1, false, 25, null, null) = private.gestion_diaria_pendientes_core(v1, false, 25, null, null)
  and pg_temp.core_h3(v1, true, 100, null, null) = private.gestion_diaria_pendientes_core(v1, true, 100, null, null),
  'Supervisión debe recibir la misma respuesta que con H3') from g4_actores;
select pg_temp.afirmar(pg_temp.codigo(format('select pg_temp.core_h3(%L,false,25,null,null)', x))
    = pg_temp.codigo(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null)', x)),
  'mismo error que H3 para ' || coalesce(x::text, 'null'))
from g4_actores, unnest(array[ajeno, fuera, nadie, null]) x;
select pg_temp.afirmar(pg_temp.codigo(format('select pg_temp.core_h3(%L,false,0,null,null)', v1))
  = pg_temp.codigo(format('select private.gestion_diaria_pendientes_core(%L,false,0,null,null)', v1)), 'mismo 22023 que H3') from g4_actores;
select pg_temp.afirmar(p->>'supervisor_id' = sup1::text and p->>'analista_id' = v1::text, 'la respuesta nombra a quien consulta')
from g4_actores, lateral (select crm.gestion_diaria_pendientes_fn(v1) p) q;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', x)) from g4_actores, unnest(array[ajeno, fuera, nadie]) x;
reset role;

-- 2. Gerencia: analista de un equipo, de otro equipo y de «fuera»; la respuesta nombra al gerente.
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.afirmar(p->>'supervisor_id' = gerente::text and p->>'analista_id' = v1::text
  and (p#>>'{resumen,tareas_pendientes}')::int = 1006 and (p#>>'{resumen,tareas_vencidas}')::int = 1005
  and not exists (select 1 from jsonb_array_elements(p->'items') i where i->>'vendedor_id' <> v1::text),
  'Gerencia lee al analista de sup1, postventa incluida')
from g4_actores, lateral (select crm.gestion_diaria_pendientes_fn(v1) p) q;
select pg_temp.afirmar((p#>>'{resumen,tareas_pendientes}')::int = 1 and p->'items'->0->>'titulo' = 'G4A ' || etiqueta,
  'Gerencia lee a ' || etiqueta)
from g4_actores, lateral (values (ajeno, 'AJENO'), (fuera, 'FUERA')) x(id, etiqueta),
  lateral (select crm.gestion_diaria_pendientes_fn(x.id) p) q;
-- Cifra = lista: el detalle por analista que Gerencia ya ve cuenta lo mismo que la lista.
select pg_temp.afirmar((f->>'tareas_pendientes')::int = 1006 and (f->>'tareas_vencidas')::int = 1005, 'cifra del detalle = lista')
from g4_actores, lateral (select f from jsonb_array_elements(private.gestion_diaria_equipo_core(current_date, null)->'equipo') f
  where (f->>'analista_id')::uuid = v1) q;
-- Recorrido completo de 1.006 tareas en páginas de 100: once páginas, sin repetir ni saltar.
create temporary table g4_ids(id uuid primary key, item jsonb);
do $$ declare p jsonb; c_fecha timestamptz; c_id uuid; n int := 0; fila jsonb; begin
  loop
    p := crm.gestion_diaria_pendientes_fn((select v1 from g4_actores), false, 100, c_fecha, c_id);
    n := n + 1;
    for fila in select value from jsonb_array_elements(p->'items') loop
      insert into g4_ids values ((fila->>'id')::uuid, fila);
    end loop;
    exit when not (p->>'hay_mas')::boolean;
    c_fecha := (p#>>'{siguiente_cursor,despues_de}')::timestamptz; c_id := (p#>>'{siguiente_cursor,despues_id}')::uuid;
    perform pg_temp.afirmar(n < 20, 'el cursor debe terminar');
  end loop;
  perform pg_temp.afirmar(n = 11 and (select count(*) from g4_ids) = 1006, format('recorrido completo (%s páginas, %s filas)', n, (select count(*) from g4_ids)));
end $$;
select pg_temp.afirmar(item->>'referencia_tipo' = 'postventa' and item->'lead_id' = 'null'::jsonb, 'postventa sin enlace inventado')
from g4_ids where item->>'titulo' = 'G4A POSTVENTA';
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', nadie)) from g4_actores;
select pg_temp.denegada('select crm.gestion_diaria_pendientes_fn(null)', '22023');
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L, false, 0)', v1), '22023') from g4_actores;
reset role;

-- 3. Postventa con una bandera apagada: ni se cuenta ni se lista, y sigue cuadrando con el detalle.
alter table crm.multiempresa_flags disable trigger user;
update crm.multiempresa_flags set activo = false where nombre = 'postventa_neutral';
alter table crm.multiempresa_flags enable trigger user;
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.afirmar((p#>>'{resumen,tareas_pendientes}')::int = 1005
  and (f->>'tareas_pendientes')::int = 1005, 'postventa oculta: fuera de la cifra y de la lista')
from g4_actores, lateral (select crm.gestion_diaria_pendientes_fn(v1) p) q,
  lateral (select f from jsonb_array_elements(private.gestion_diaria_equipo_core(current_date, null)->'equipo') f
    where (f->>'analista_id')::uuid = v1) d;
reset role;

-- 4. Analista inactivo (fabricado: v2 bajo sup1, con tarea visible por RLS): 42501 para sup1 y Gerencia.
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false where perfil_id = (select v2 from g4_actores);
alter table crm.equipo enable trigger user;
do $$ declare actor uuid; begin
  for actor in select unnest(array[sup1, gerente]) from g4_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', (select v2 from g4_actores)));
    execute 'reset role';
  end loop;
end $$;

-- 5. Siguen sin esta puerta: analista, coordinación, lector global, uid sin rol y llamada sin identidad.
do $$ declare actor uuid; begin
  for actor in select unnest(array[v1, coordinador, global, nadie, null]) from g4_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', (select ajeno from g4_actores)));
    perform pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null)', (select ajeno from g4_actores)));
    execute 'reset role';
  end loop;
end $$;

-- 6. Gerencia desactivada (offboarding): 42501.
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false where perfil_id = (select gerente from g4_actores);
alter table crm.equipo enable trigger user;
select pg_temp.como(gerente) from g4_actores;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', v1)) from g4_actores;
reset role;

-- 7. anon no ejecuta ni la puerta ni el núcleo.
set local role anon;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)', v1)) from g4_actores;
select pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null)', v1)) from g4_actores;
reset role;

-- 8. El gate completo sigue en verde con el sello nuevo.
select pg_temp.afirmar(private.assert_gestion_diaria_pendientes() like 'OK:%', 'gate H3 re-sellado');
select 'G4A_OK' as resultado;
rollback;

```

## Diff de `supabase/scripts/test-rls.mjs` y de la suite H3 + front
```diff
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
index f9541dd2..067b5af6 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
@@ -46,7 +46,7 @@ export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, titu
   vacio?: string | undefined
   /** Selección automática: sus cargas y errores no se anuncian (el usuario no la abrió). */
   silencioso?: boolean
-  /** Gerencia (27/09): sin pestaña Pendientes hasta tener permiso sobre esa consulta (G4). */
+  /** Sin pestaña Pendientes cuando la sesión no puede consultarlos (gerencia antes de G4a). */
   conPendientes?: boolean
   /** Alcance del registro del equipo; null = lo que la sesión puede ver (el equipo del supervisor). */
   idsEquipo?: readonly string[] | null
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx
index 6de80f5a..6c7ec4b8 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx
@@ -1,7 +1,7 @@
 // Gerencia dentro de un equipo («Toda la operación / Equipo de X», 27/09/2026):
 // la pantalla del supervisor —cifras-filtro, buscador, tabla nueva (más
-// Pendientes, que gerencia compara) y la ficha protagonista del analista— SIN
-// pestaña Pendientes hasta que gerencia tenga permiso sobre esa consulta (G4).
+// Pendientes, que gerencia compara) y la ficha protagonista del analista, con su
+// pestaña Pendientes desde G4a (el servidor ya autoriza a gerencia, 27/09).
 // La selección del usuario vive en la ruta (atrás/adelante, enlaces directos); la
 // automática —quien más atención necesita— solo en la pantalla y sin mover el
 // foco. Se conservan los autores inactivos y los registros sin autor (Codex).
@@ -222,7 +222,7 @@ export function VistaEquipoGerencia({ hora = null, equipo, filas, error, cargand
             ampliado={ampliado} puedeAmpliar={!estrecho} ampliar={() => { setAmpliado((v) => !v); if (automatica && local) setLocal({ ...local, origen: 'usuario' }) }} cerrar={cerrar}
             oculta={oculta} limpiar={() => setFiltros(() => BASE)} actualizacion={actualizacion} revalidar={revocar} esHoy={esHoy} ahora={ahora}
             vacio="Nadie del equipo necesita atención ahora. Elige un analista para ver su día." silencioso={automatica}
-            conPendientes={false} idsEquipo={idsEquipo} subtitulo={equipo.clave === 'fuera' ? 'Analista fuera de equipos comerciales' : `Analista del equipo de ${equipo.nombre}`} />
+            idsEquipo={idsEquipo} subtitulo={equipo.clave === 'fuera' ? 'Analista fuera de equipos comerciales' : `Analista del equipo de ${equipo.nombre}`} />
         </PanelSupervisorAdaptable>
       </div>
     </section>
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.test.tsx b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.test.tsx
index da72fdbf..c84722bb 100644
--- a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.test.tsx
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.test.tsx
@@ -118,3 +118,21 @@ describe('Memoria y refresco paginados del supervisor', () => {
     expect(result.current.items).toEqual([])
   })
 })
+
+describe('G4a: quién consulta pendientes', () => {
+  it('gerencia consulta con su propio id como «supervisor» del pedido: el servidor autoriza toda la operación', async () => {
+    const gerente = idPendiente(90)
+    dobles.yo = { id: gerente, rol: 'gerencia', demo: false } as Yo
+    const { result } = renderHook(() => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, true), { wrapper: envolver })
+    await waitFor(() => expect(dobles.listar).toHaveBeenCalled())
+    expect(dobles.listar).toHaveBeenCalledWith(expect.objectContaining({ supervisor: gerente, analista: pedidoPendientes.analista }), expect.any(AbortSignal))
+    expect(result.current.sinPermiso).toBe(false)
+  })
+  it.each(['vendedor', 'coordinador', 'directorio'] as const)('%s no consulta pendientes', async (rol) => {
+    dobles.yo = { id: idPendiente(91), rol, demo: false } as Yo
+    const { result } = renderHook(() => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, true), { wrapper: envolver })
+    await act(async () => { await Promise.resolve() })
+    expect(dobles.listar).not.toHaveBeenCalled()
+    expect(result.current.items).toEqual([])
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.ts b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.ts
index 7e1e74dd..96a32f31 100644
--- a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.ts
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.ts
@@ -19,7 +19,8 @@ export function usePendientesSupervisor(dia: string, analista: string, soloVenci
   const ahora = useAhora()
   const cliente = useQueryClient()
   const revocada = useRef(false)
-  const autorizado = yo?.rol === 'supervisor'
+  // Supervisión (su equipo) y, desde G4a (27/09/2026), Gerencia (toda la operación): el servidor decide.
+  const autorizado = yo?.rol === 'supervisor' || yo?.rol === 'gerencia'
   const clave = useMemo(() => [...clavePendientes(yo?.id ?? null, yo?.rol ?? null, yo?.demo ?? null, dia, analista, soloVencidas), apertura],
     [yo?.id, yo?.rol, yo?.demo, dia, analista, soloVencidas, apertura])
   const ambitoClave = useMemo(() => clave.slice(0, -3), [clave])
@@ -37,7 +38,9 @@ export function usePendientesSupervisor(dia: string, analista: string, soloVenci
       if (!yo || !autorizado) throw new CrmApiError('Consulta no autorizada.', '42501')
       const pedido = { supervisor: yo.id, analista, soloVencidas, limite: LIMITE_PENDIENTES, cursor: pageParam }
       if (yo.demo) {
-        if (!analistasDelEquipo(equipo, yo.id).includes(analista)) throw new CrmApiError('Consulta no autorizada.', '42501')
+        // En demo, el mismo ámbito que el servidor: Supervisión su árbol; Gerencia todo analista activo.
+        const permitidos = yo.rol === 'gerencia' ? ambito.vendedores.filter((m) => m.activo).map((m) => m.perfil_id) : analistasDelEquipo(equipo, yo.id)
+        if (!permitidos.includes(analista)) throw new CrmApiError('Consulta no autorizada.', '42501')
         return Promise.resolve(pendientesDesdeDemo(pedido, tareas, ambito.leads, ahora))
       }
       return listarPendientesSupervisor(pedido, signal)
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
index d09d4a28..6eedc763 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
@@ -114,8 +114,8 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
     ruta(`#/gestion-diaria/analista/${p.analista_id}`)
     render(<GestionDiariaGerencia />)
     const panel = screen.getByRole('region', { name: `Detalle de ${p.nombre_completo}` })
-    // Gerencia aún no consulta pendientes (G4): su ficha no ofrece esa pestaña.
-    expect(within(panel).queryByRole('tab', { name: 'Pendientes' })).not.toBeInTheDocument()
+    // G4a: el servidor ya autoriza a gerencia, así que su ficha ofrece Pendientes como la del supervisor.
+    expect(within(panel).getByRole('tab', { name: 'Pendientes' })).toBeInTheDocument()
     fireEvent.click(within(panel).getByRole('tab', { name: 'Registro' }))
     expect(within(panel).getByTestId('registro')).toHaveTextContent(JSON.stringify([p.analista_id]))
     const registro = within(panel).getByTestId('registro')
diff --git a/CRM-Avance-Corp/supabase/scripts/gestion-diaria-horizontal/test-pendientes.sql b/CRM-Avance-Corp/supabase/scripts/gestion-diaria-horizontal/test-pendientes.sql
index 5ac1ae4f..5b2e9264 100644
--- a/CRM-Avance-Corp/supabase/scripts/gestion-diaria-horizontal/test-pendientes.sql
+++ b/CRM-Avance-Corp/supabase/scripts/gestion-diaria-horizontal/test-pendientes.sql
@@ -155,9 +155,10 @@ select pg_temp.afirmar(p->'items'='[]'::jsonb and p#>>'{resumen,tareas_pendiente
   and p#>>'{resumen,tareas_vencidas}'='0' and p->'siguiente_cursor'='null'::jsonb and p->>'hay_mas'='false','cero completo y coherente')
 from (select crm.gestion_diaria_pendientes_fn(vendedor) p from h3_actores) q;
 reset role;
--- Vendedor, coordinador, gerencia y lector global no tienen esta puerta H3.
+-- Vendedor, coordinador y lector global no tienen esta puerta. Gerencia la tiene desde
+-- G4a (20260928043728); sus casos viven en supabase/scripts/g4/test-g4a.sql.
 do $$ declare actor uuid; begin
-  for actor in select unnest(array[vendedor,coordinador,gerente,global]) from h3_actores loop
+  for actor in select unnest(array[vendedor,coordinador,global]) from h3_actores loop
     perform set_config('request.jwt.claim.sub',actor::text,true);
     execute 'set local role authenticated';
     perform pg_temp.denegada(format('select crm.gestion_diaria_pendientes_fn(%L)',(select vendedor from h3_actores)));
diff --git a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
index 03c1d7a0..78f60e0b 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
@@ -8325,6 +8325,41 @@ async function testGestionDiariaCortes(sessions, seed) {
   // en la copia local autorizada y con reloj clonado, no con cambios de hora reales.
 }
 
+// H3 + G4a (27/09/2026): pendientes por analista. Supervisión, su árbol; Gerencia, toda la
+// operación; la respuesta nombra a quien consulta. Casos pedidos por auditor-rls para G4a.
+async function testGestionDiariaPendientes(sessions, seed) {
+  console.log('\n— Gestión Diaria: pendientes por analista (H3 + G4a) —');
+  const FN = 'gestion_diaria_pendientes_fn';
+  const id = (key) => seed.profileIdByKey[key];
+  const rpc = (quien, analista, extra = {}) => sessions[quien].client.schema('crm').rpc(FN, { p_analista_id: analista, ...extra });
+  const probe = await rpc('sup1', id('vend1'));
+  if (probe.error?.code === 'PGRST202') {
+    const msg = '⚠ H3 no instalada: pendientes SALTADOS (no probado)';
+    if (process.env.CRM_RLS_EXIGE_GESTION_DIARIA === '1') fail(msg);
+    else console.log(`  ${msg}`);
+    return;
+  }
+  for (const [quien, analista] of [['sup1', 'vend1'], ['gerencia', 'vend1'], ['gerencia', 'vend3']]) {
+    const { data, error } = await rpc(quien, id(analista));
+    check(!error && data?.supervisor_id === id(quien) && data?.analista_id === id(analista),
+      `${quien} → ${analista}: pendientes autorizados y a nombre de quien consulta`);
+  }
+  for (const [quien, analista, etiqueta] of [['sup1', id('vend3'), 'vend3 (otro equipo)'], ['sup1', randomUUID(), 'inexistente'],
+    ['gerencia', id('vendInactive'), 'vendInactive'], ['gerencia', randomUUID(), 'inexistente']]) {
+    const { error } = await rpc(quien, analista);
+    check(isAuthorizationError(error), `${quien}: pendientes de ${etiqueta} → 42501`);
+  }
+  for (const quien of ['vend1', 'coordinador', 'directorio', 'vendInactive']) {
+    const { error } = await rpc(quien, id('vend1'));
+    check(isAuthorizationError(error), `${quien}: sin puerta de pendientes → 42501`);
+  }
+  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-pendientes'));
+  const anonRpc = await anon.schema('crm').rpc(FN, { p_analista_id: id('vend1') });
+  check(isAuthorizationError(anonRpc.error), 'anon no ejecuta pendientes');
+  const limite = await rpc('gerencia', id('vend1'), { p_limite: 0 });
+  check(limite.error?.code === '22023', 'gerencia: límite 0 → 22023');
+}
+
 async function testGestionDiariaResultado(sessions, seed) {
   console.log('\n— Gestión Diaria: resultado tipificado de llamada (F2) —');
   const FN = 'registrar_llamada_v3';
@@ -14774,6 +14809,7 @@ async function main() {
       await testGestionDiariaResultado(sessions, verifiedSeed);
       await testGestionDiariaAnalista(sessions, verifiedSeed);
       await testGestionDiariaCortes(sessions, verifiedSeed);
+      await testGestionDiariaPendientes(sessions, verifiedSeed);
       await testCapitalNucleo(sessions, verifiedSeed);
       await testCorreoAccesoCliente(sessions, verifiedSeed);
       await testVentaCruzada(sessions, verifiedSeed);
```

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
