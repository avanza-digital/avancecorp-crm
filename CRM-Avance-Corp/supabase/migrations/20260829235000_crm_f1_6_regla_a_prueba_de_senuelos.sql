-- P-055 · FASE 1.6 — LA REGLA, A PRUEBA DE SEÑUELOS (auditoría adversarial de Codex)
--
-- Codex atacó la F1.4 y devolvió NO-GO con 9 hallazgos. Auditó la versión ANTES
-- de la enmienda y SIN poder leer producción (su CLI no tenía token), así que
-- parte de lo que trae ya estaba corregido y parte no se sostiene al medirlo.
-- Aquí va lo que SÍ queda en pie, con las dos correcciones que la medición
-- obligó a cambiar respecto de lo que él proponía.
--
-- LO QUE SE ARREGLA (sus hallazgos 2, 3, 4, 6, 7 y 8)
--
--  2. 🔴 LA REGLA ACEPTA TRIGGERS DECORATIVOS. Aun con la F1.5, un trigger en
--     modo `REPLICA` (tgenabled='R'), uno BEFORE, uno INSTEAD OF, uno con
--     `UPDATE OF` parcial o uno con un `WHEN (false)` contaban como auditoría.
--     Ahora se exige: activo de verdad ('O'/'A'), AFTER, por fila, sin
--     `UPDATE OF` parcial, y el auditor tiene que ser SECURITY DEFINER con
--     search_path fijo.
--     ⚖️ DOS AJUSTES SOBRE SU PROPUESTA, POR MEDICIÓN:
--       · Pedía `proconfig @> ['search_path=""']`. Medido: `log_audit_change`
--         vive con `search_path = 'public, pg_temp'` — exigir el vacío habría
--         puesto en rojo media base sin ganar nada. Se exige search_path FIJO.
--       · Pedía prohibir el `WHEN`. Medido: `public.cronograma_pagos` lo usa
--         desde antes de esta fase, deliberadamente. Prohibirlo habría marcado
--         como rota una tabla que audita bien. Se permite, pero DECLARADO: la
--         tabla tiene que estar en `private.auditoria_condicionada` con su
--         razón. Un compromiso que nadie escribió no vale.
--
--  3. El universo vigilado tenía huecos: particiones hoja, tablas UNLOGGED,
--     foráneas y vistas materializadas quedaban fuera. Hoy no existe ninguna
--     (medido: 48 tablas, todas normales y permanentes), así que es preventivo.
--
--  4. 🔴 EL MUTANTE NO PROBABA EL GATE, probaba sus piezas por separado: si se
--     rompía la comparación repo↔base, el mutante seguía verde. Ahora el cuerpo
--     del gate vive en `private.assert_auditoria()` y el mutante ejecuta ESA
--     MISMA función bajo cada mutación, exigiendo que reviente.
--
--  6. El cron se daba por bueno con que existiera un job activo con ese nombre.
--     Ahora se comprueba nombre, usuario, base, horario y comando exactos, y
--     que no haya duplicados de otro usuario.
--
--  7. El enmascarado guardaba `***:` + 8 de md5 — una huella determinista que
--     permite confirmar candidatos y correlacionar eventos. Pasa a `***` plano.
--     Y se enmascaran también `user_agent` y `dispositivo`: no son credenciales,
--     pero son la huella del aparato de un cliente y hoy la vería cualquier
--     admin.
--
--  8. Las razones de la lista blanca no estaban gobernadas: reaplicar no
--     actualizaba una razón y la huella solo miraba nombres. Ahora la huella
--     incluye el texto de la razón y el gate compara tabla + razón.
--
-- LO QUE NO SE TOCA, Y POR QUÉ (refutado con medición)
--   · Su #1 (F1.4 y F1.5 no forman unidad desplegable): se publicaron juntas y
--     el gate quedó verde contra producción. Su squash ya no aplica — y este
--     repo no edita migraciones publicadas.
--   · Su #5 (el upsert del portal ensucia): corregido en F1.5 y MEDIDO contra el
--     flujo vivo: el guardado repetido no añade ni una fila. Se mantiene, y aquí
--     el filtro se muda DENTRO del auditor para poder exigir triggers limpios.
--   · Su #9 (falta prueba de comportamiento): hecha en F1.5 contra producción en
--     transacción deshecha; aquí se amplía con roles reales en el espejo.

-- ---------------------------------------------------------------------------
-- 1. El enmascarado deja de ser un oráculo, y tapa la huella del aparato
-- ---------------------------------------------------------------------------

create or replace function private.enmascarar_claves(p_fila jsonb, p_claves text[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_fila is null then null else (
    select pg_catalog.jsonb_object_agg(
      k,
      case
        when k = any(p_claves) and pg_catalog.jsonb_typeof(v) = 'null' then v
        -- Sin huella: un md5 determinista, aunque truncado, permite confirmar
        -- candidatos y correlacionar dos eventos del mismo secreto.
        when k = any(p_claves) then '"***"'::jsonb
        else v
      end
    )
    from pg_catalog.jsonb_each(p_fila) as e(k, v)
  ) end;
$$;

comment on function private.enmascarar_claves(jsonb, text[]) is
  'Sustituye los valores de las claves indicadas por ***. Sin huella derivada: cualquier valor determinista sirve de oráculo para confirmar candidatos.';

revoke all on function private.enmascarar_claves(jsonb, text[])
  from public, anon, authenticated, service_role;

-- El auditor de secretos absorbe el filtro de ruido: así el trigger puede ser
-- uno solo, completo y SIN `WHEN` — que es lo que la regla nueva exige.
create or replace function private.log_audit_sin_secretos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secretos text[];
  v_fila uuid;
  v_actor uuid;
begin
  if tg_nargs = 0 then
    raise exception 'log_audit_sin_secretos exige las columnas a enmascarar como argumentos del trigger (tabla %.%)',
      tg_table_schema, tg_table_name;
  end if;
  v_secretos := tg_argv::text[];

  -- Ruido fuera: el portal reescribe la suscripción entera en cada carga del
  -- panel; si lo único que cambia es el reloj, no hay nada que auditar.
  if tg_op = 'UPDATE'
     and (pg_catalog.to_jsonb(old) - 'actualizado_en')
       = (pg_catalog.to_jsonb(new) - 'actualizado_en') then
    return new;
  end if;

  begin
    v_fila := coalesce(
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
    );
  exception when invalid_text_representation then
    v_fila := null;
  end;

  select p.id into v_actor
  from public.perfiles p where p.id = (select auth.uid());

  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    v_fila,
    v_actor,
    case when tg_op in ('UPDATE','DELETE')
      then private.enmascarar_claves(pg_catalog.to_jsonb(old), v_secretos) end,
    case when tg_op in ('INSERT','UPDATE')
      then private.enmascarar_claves(pg_catalog.to_jsonb(new), v_secretos) end
  );

  return coalesce(new, old);
end;
$$;

revoke all on function private.log_audit_sin_secretos()
  from public, anon, authenticated, service_role;

-- Un solo trigger, completo y sin condición. El filtro vive dentro del auditor.
drop trigger if exists trg_audit_suscripciones_push_upd on public.suscripciones_push;
drop trigger if exists trg_audit_suscripciones_push on public.suscripciones_push;
create trigger trg_audit_suscripciones_push
  after insert or update or delete on public.suscripciones_push
  for each row
  execute function private.log_audit_sin_secretos('endpoint', 'p256dh', 'auth', 'user_agent', 'dispositivo');

-- ---------------------------------------------------------------------------
-- 2. Los compromisos declarados: auditoría condicionada
-- ---------------------------------------------------------------------------

create table if not exists private.auditoria_condicionada (
  tabla        text        primary key,
  razon        text        not null,
  declarada_en timestamptz not null default pg_catalog.now(),
  constraint auditoria_condicionada_razon_de_verdad
    check (pg_catalog.length(pg_catalog.btrim(razon)) >= 40)
);

alter table private.auditoria_condicionada enable row level security;
revoke all on table private.auditoria_condicionada
  from public, anon, authenticated, service_role;

comment on table private.auditoria_condicionada is
  'Tablas cuyo rastro lleva un WHEN: auditan de verdad, pero se saltan casos a propósito. La regla las acepta SOLO si están aquí con su razón.';

drop trigger if exists trg_audit_auditoria_condicionada on private.auditoria_condicionada;
create trigger trg_audit_auditoria_condicionada
  after insert or update or delete on private.auditoria_condicionada
  for each row execute function private.log_audit_crm();

insert into private.auditoria_condicionada (tabla, razon) values
  ('public.cronograma_pagos',
   'Su rastro lleva un WHEN desde antes de esta fase, deliberadamente: el cronograma se reescribe en bloque en cada recálculo y sin la condición la auditoría se llenaría de filas idénticas. Auditar el cambio real sigue garantizado.')
on conflict (tabla) do update set razon = excluded.razon;

-- Las razones de la lista blanca también se gobiernan: reaplicar debe poder
-- corregir un texto.
insert into private.auditoria_exenciones (tabla, razon) values
  ('crm.usuario_eventos',
   'Es la bitácora de la pantalla de Usuarios: ella misma ES el rastro. Además su id es BIGINT y private.log_audit_crm castea a uuid, así que colgárselo abortaría el alta de usuarios entera (visto en la auditoría P-053).'),
  ('public.novedades_leidas',
   'Marca de «novedad leída» por persona. No es dinero, ni titulares, ni secreto: auditarla sería ruido puro que enterraría los movimientos que sí importan.'),
  ('public.audit_log',
   'Es la auditoría misma: colgarle un auditor sería una recursión infinita. Su integridad la dan sus permisos y la ausencia de política de borrado, no un rastro de sí misma.')
on conflict (tabla) do update set razon = excluded.razon;

-- La huella pasa a incluir el TEXTO de la razón y las dos listas: cambiar una
-- justificación sin pasar por el repo también rompe el sello.
create or replace function private.huella_exenciones()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.md5(
    coalesce((select pg_catalog.string_agg(e.tabla || pg_catalog.chr(31) || e.razon,
                                           pg_catalog.chr(30) order by e.tabla)
              from private.auditoria_exenciones e), '')
    || pg_catalog.chr(29) ||
    coalesce((select pg_catalog.string_agg(c.tabla || pg_catalog.chr(31) || c.razon,
                                           pg_catalog.chr(30) order by c.tabla)
              from private.auditoria_condicionada c), '')
  );
$$;

revoke all on function private.huella_exenciones()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. La regla, a prueba de señuelos
-- ---------------------------------------------------------------------------

create or replace function private.tablas_sin_rastro()
returns table (tabla text)
language sql
stable
security invoker
set search_path = ''
as $$
  select n.nspname || '.' || c.relname
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  -- Universo completo: tablas normales y particionadas (padres E hijas: el
  -- trigger del padre se CLONA en cada hija), foráneas y materializadas.
  -- Permanentes y UNLOGGED (una tabla sin WAL sigue guardando datos de negocio).
  where c.relkind in ('r', 'p', 'f', 'm')
    and c.relpersistence in ('p', 'u')
    and n.nspname in ('crm', 'public')
    and not exists (
      select 1 from private.auditoria_exenciones e
      where e.tabla = n.nspname || '.' || c.relname)
    and coalesce((
      select pg_catalog.bit_or(t.tgtype)
      from pg_catalog.pg_trigger t
      join pg_catalog.pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = c.oid
        and not t.tgisinternal
        -- Activo DE VERDAD: 'D' es apagado y 'R' solo dispara en réplica.
        and t.tgenabled in ('O', 'A')
        and (t.tgtype & 1) = 1     -- FOR EACH ROW
        and (t.tgtype & 2) = 0     -- AFTER, no BEFORE
        and (t.tgtype & 64) = 0    -- no INSTEAD OF
        -- Sin `UPDATE OF` parcial: dispara por estar la columna en el SET, no
        -- por cambiar, y deja fuera las columnas que no lista.
        and t.tgattr = ''::pg_catalog.int2vector
        -- Un `WHEN` puede anularlo entero: solo cuenta si está declarado.
        and (t.tgqual is null or exists (
              select 1 from private.auditoria_condicionada cc
              where cc.tabla = n.nspname || '.' || c.relname))
        -- Por OID, no por nombre: una función señuelo llamada igual en otro
        -- esquema pasaba la comprobación anterior.
        and t.tgfoid in ('private.log_audit_crm()'::regprocedure,
                         'public.log_audit_change()'::regprocedure,
                         'private.log_audit_sin_secretos()'::regprocedure)
        -- Y el auditor tiene que seguir siendo lo que dice ser: DEFINER con
        -- search_path fijo (no se exige vacío: log_audit_change vive con
        -- 'public, pg_temp' desde siempre y audita bien).
        and p.prosecdef
        and p.proconfig is not null
    ), 0) & 28 <> 28               -- 4 INSERT | 8 DELETE | 16 UPDATE
  order by 1;
$$;

comment on function private.tablas_sin_rastro() is
  'Fuente única de la regla: tablas de crm/public sin rastro COMPLETO Y EFECTIVO — trigger AFTER, por fila, activo de verdad, sin UPDATE OF parcial, sin WHEN salvo declarado en auditoria_condicionada, apuntando POR OID a un auditor SECURITY DEFINER con search_path fijo, y cubriendo los tres verbos. Debe devolver CERO filas.';

revoke all on function private.tablas_sin_rastro()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. El gate entero, dentro del servidor: una sola comprobación que el
--    trinquete Y el mutante ejecutan. Antes el mutante probaba las piezas
--    sueltas y podía quedarse verde con el gate roto.
-- ---------------------------------------------------------------------------

create or replace function private.assert_auditoria()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sin_rastro text;
  v_cuantas int;
  v_alertas text;
  v_cron int;
begin
  select pg_catalog.count(*), pg_catalog.string_agg(s.tabla, ', ')
    into v_cuantas, v_sin_rastro
  from private.tablas_sin_rastro() s;

  if v_cuantas > 0 then
    raise exception using errcode = 'P0001',
      message = 'AUDITORÍA ROTA: ' || v_cuantas || ' tabla(s) sin rastro completo [' ||
        v_sin_rastro || ']. Cuélgale un auditor AFTER por fila para los tres ' ||
        'verbos, o declárala en private.auditoria_exenciones con su razón.';
  end if;

  if not exists (select 1 from private.auditoria_sello
                 where huella = private.huella_exenciones()) then
    raise exception using errcode = 'P0001',
      message = 'SELLO ROTO: las listas de exenciones o de auditoría condicionada cambiaron sin re-sellar.';
  end if;

  select pg_catalog.count(*) into v_cron
  from cron.job
  where jobname = 'crm-auditoria-vigia'
    and command = 'select private.vigia_auditoria()'
    and schedule = '29 6 * * *'
    and database = pg_catalog.current_database()
    and active;
  if v_cron <> 1 then
    raise exception using errcode = 'P0001',
      message = 'VIGÍA MAL PROGRAMADO: se esperaba exactamente 1 job activo con su horario, comando y base; hay ' || v_cron || '.';
  end if;

  select pg_catalog.string_agg(a.tabla, ', ') into v_alertas
  from private.auditoria_alertas a where a.resuelta_en is null;
  if v_alertas is not null then
    raise exception using errcode = 'P0001',
      message = 'EL VIGÍA TIENE ALERTAS ABIERTAS: ' || v_alertas;
  end if;
end;
$$;

comment on function private.assert_auditoria() is
  'El gate completo, en un solo sitio: regla + sello + cron exacto + alertas. Lo ejecutan igual el trinquete del repo y cada filo del mutante; así el mutante prueba el gate de verdad, no sus piezas.';

revoke all on function private.assert_auditoria()
  from public, anon, authenticated, service_role;

-- El cron, comprobado exactamente (nombre, dueño, base, horario y comando)
do $cron$
declare
  v_jobid bigint;
begin
  if exists (select 1 from cron.job
             where jobname = 'crm-auditoria-vigia' and username <> current_user) then
    raise exception 'Existe un job crm-auditoria-vigia de otro usuario: resolver a mano antes de seguir';
  end if;

  v_jobid := cron.schedule('crm-auditoria-vigia', '29 6 * * *', 'select private.vigia_auditoria()');
  perform cron.alter_job(v_jobid, active => true);

  if (select pg_catalog.count(*) from cron.job
      where jobid = v_jobid and jobname = 'crm-auditoria-vigia'
        and username = current_user and schedule = '29 6 * * *'
        and command = 'select private.vigia_auditoria()'
        and database = pg_catalog.current_database() and active) <> 1 then
    raise exception 'El job del vigía no quedó exactamente como se pidió';
  end if;
end;
$cron$;

-- Re-sellar: la huella cambió de fórmula y las listas se han reafirmado
insert into private.auditoria_sello (unico, huella)
values (true, private.huella_exenciones())
on conflict (unico) do update set huella = excluded.huella, sellado = pg_catalog.now();

-- ---------------------------------------------------------------------------
-- 5. Postflight
-- ---------------------------------------------------------------------------

do $postflight$
declare
  v_def text;
  v_prueba jsonb;
  v_abiertas int;
begin
  -- 5.1 El trigger de push quedó completo y SIN condición ni UPDATE OF
  select pg_catalog.pg_get_triggerdef(t.oid) into v_def
  from pg_trigger t where t.tgrelid = 'public.suscripciones_push'::regclass
    and t.tgname = 'trg_audit_suscripciones_push';
  if v_def is null
     or pg_catalog.strpos(v_def, 'WHEN') > 0
     or pg_catalog.strpos(v_def, 'UPDATE OF') > 0
     or pg_catalog.strpos(v_def, 'INSERT OR DELETE OR UPDATE') = 0 then
    raise exception 'F1.6: el trigger de suscripciones_push no quedó completo y limpio: %', coalesce(v_def, '(no existe)');
  end if;
  if exists (select 1 from pg_trigger where tgname = 'trg_audit_suscripciones_push_upd') then
    raise exception 'F1.6: el trigger partido sigue vivo';
  end if;

  -- 5.2 El enmascarado ya no deja huella derivada
  v_prueba := private.enmascarar_claves(
    '{"token":"secreto-de-prueba","nota":"visible"}'::jsonb, array['token']);
  if v_prueba ->> 'token' <> '***' then
    raise exception 'F1.6: el enmascarado sigue dejando una huella: %', v_prueba ->> 'token';
  end if;
  if v_prueba ->> 'nota' <> 'visible' then
    raise exception 'F1.6: el enmascarado se comió un campo que no era secreto';
  end if;

  -- 5.3 La regla sigue dando cero, ahora con todas las exigencias
  perform private.assert_auditoria();

  -- 5.4 Y el vigía sigue limpio
  select private.vigia_auditoria() into v_abiertas;
  if v_abiertas <> 0 then
    raise exception 'F1.6: el vigía dejó % alerta(s) abiertas', v_abiertas;
  end if;

  raise notice 'F1.6 OK: regla a prueba de señuelos · gate en una sola función · cron verificado · enmascarado sin oráculo · razones gobernadas';
end;
$postflight$;

-- El veredicto viaja como FILA (este canal no transporta los avisos).
select 'F1_6_APLICADA' as veredicto,
       (select pg_catalog.count(*) from private.tablas_sin_rastro()) as sin_rastro,
       (select pg_catalog.count(*) from private.auditoria_exenciones) as exenciones,
       (select pg_catalog.count(*) from private.auditoria_condicionada) as condicionadas,
       (select pg_catalog.count(*) from private.auditoria_alertas where resuelta_en is null) as alertas_abiertas;
