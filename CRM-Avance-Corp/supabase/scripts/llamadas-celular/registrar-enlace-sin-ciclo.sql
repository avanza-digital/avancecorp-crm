-- REGISTRO en supabase_migrations.schema_migrations de 20261005182227_crm_llamadas_celular_enlace_sin_ciclo (séptima: enlace exacto sin ciclo con Deshacer).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración, en un mensaje aparte (punto 18 de
-- REVISION-2026-10-02.md; guía PUBLICAR-F2-F3.md: cada registrador justo después de su migración). Idempotente; se
-- niega si los objetos no están con su forma o si la versión ya está registrada con otro nombre u otro contenido;
-- relee la fila antes de confirmar. statements = el archivo entero (md5 6dea6bd39fa2435ae883396e2c957783, con finales de línea LF:
-- correrlo desde un checkout LF, como la Mac de Miguel; en una copia de Windows con CRLF el md5 no coincide y se
-- niega). La ÚLTIMA sentencia, después del commit, es una fila de veredicto: `db query --linked` no muestra los
-- raise notice (corrección de Miguel al #173; molde: scripts/anexo-cronograma/registrar-20260929151350.sql).
-- En una copia Docker se corre con `psql -f`: `db query --local --file` falla con varias sentencias.
-- Generado el 05/10/2026 desde la migración en LF. Patrón: los registrar-*.sql de esta carpeta.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_llamadas_celular_registro'));
do $chk$
begin
  if (
    to_regprocedure('private.llamada_celular_cumplir_intencion(uuid)') is not null
    and to_regprocedure('private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)') is not null
    and pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_cumplir_intencion(uuid)'::regprocedure),
                          'for key share nowait') > 0
    and pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)'::regprocedure),
                          'for key share nowait') > 0
  ) is not true then
    raise exception 'REGISTRO: la migración 20261005182227 no está aplicada (o no con su forma); aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261005182227' and (coalesce(name, '') <> 'crm_llamadas_celular_enlace_sin_ciclo' or statements is distinct from array[$mig$-- Llamadas desde el celular · séptima migración: el enlace exacto SIN CICLO de candados con «Deshacer». Corrige el [P2]
-- de la revisión del agente de Miguel en el PR #190 (05/10/2026, 18:13 UTC; reproducido con dos sesiones sobre las seis
-- migraciones): al unir un resultado con su llamada, la llave foránea del enlace (y la de la intención) toma el resultado
-- FOR KEY SHARE aunque nadie lo pida; Deshacer (20260920005000:649 y 682) bloquea resultado → lead FOR UPDATE; la
-- ingesta y la v5 llegan con el lead ya tomado y esperaban el resultado: lead → resultado contra resultado → lead =
-- interbloqueo (40P01). Se publica JUNTO con las seis (va antes de dar de alta celulares, como ellas).
--
-- Qué hace (sin editar F4-a, 20261005155914; mismas firmas, mismos permisos, sin tablas ni datos):
--   1. private.llamada_celular_cumplir_intencion (la ingesta): toma el resultado FOR KEY SHARE NOWAIT antes de crear el
--      enlace. Si Deshacer lo tiene (55P03 lock_not_available, lo único que se atrapa), la intención ya se retiró y no se
--      une: la llamada queda en la pestaña para unirla a mano. Decisión de Jhosep (05/10): no esperar.
--   2. private.llamada_celular_enlazar_exacto (la v5): igual, antes de crear o mover el enlace o la intención. Si lo tiene
--      otro → {estado: no_enlazado, motivo: resultado_en_uso}; el resultado ya quedó guardado. Solo pasa en el reintento
--      de una operación cuyo resultado se está deshaciendo: en el camino normal el resultado es de esta transacción.
--   Solo Deshacer bloquea un resultado FOR UPDATE (comprobado en todas las migraciones el 05/10). La actualización que
--   hace la v4 (FOR NO KEY UPDATE) no choca con FOR KEY SHARE: el «no esperar» no falla por otros escritores.
--
-- Capas (estándar de 4 capas): solo núcleo de private (INVOKER, sin EXECUTE para nadie); las puertas (v5 e ingesta de
-- servicio) no cambian de firma. La v5 suma un valor de motivo (resultado_en_uso); ninguna pantalla la usa todavía (F4-b).
-- Excepción single-tenant (F2.3.3): el CRM es de una sola empresa; no hay columna de tenant.
-- Reversión: ../scripts/llamadas-celular/reversa-enlace-sin-ciclo.sql (solo cuerpos y COMMENT, sin datos: vuelve a la
-- huella exacta de las seis). Verificación: npm run test:llamadas:local (pasadas 13 y 14: huella, oráculos de F4-a y de la
-- quinta, carreras con Deshacer pausado entre sus dos candados, en los dos órdenes y revertido, y mutantes).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('private.llamadas_celular_intenciones') is null
     or to_regprocedure('private.llamada_celular_cumplir_intencion(uuid)') is null
     or to_regprocedure('private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)') is null then
    raise exception 'LLAMADAS_ENLACE_SIN_CICLO: falta F4-a (20261005155914)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_cumplir_intencion(uuid)'::regprocedure),
                       'for key share nowait') > 0 then
    raise exception 'LLAMADAS_ENLACE_SIN_CICLO: ya está aplicada; no se sobrescribe';
  end if;
end;
$precondicion$;

-- ── 1. El enlace de la v5: el resultado, sin esperar ─────────────────────────────────────────
create or replace function private.llamada_celular_enlazar_exacto(
  p_actor uuid, p_lead_id uuid, p_actividad_id uuid, p_origen text, p_via text, p_ahora timestamptz)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_act crm.actividades%rowtype;
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_enl crm.llamadas_celular_enlaces%rowtype;
  v_int private.llamadas_celular_intenciones%rowtype;
  v_hora timestamptz;
  v_deshecha boolean;
  v_restriccion text;
  v_estado text;
begin
  -- 1. El id: forma fija, dentro de la ventana de la ingesta y de un celular del analista que registra.
  if p_origen is null or p_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'id_invalido');
  end if;
  v_hora := pg_catalog.to_timestamp(pg_catalog.split_part(p_origen, '-', 2)::bigint);
  if v_hora < p_ahora - interval '30 days' or v_hora > p_ahora + interval '1 day' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'id_invalido');
  end if;
  if not exists (select 1 from crm.celulares_asignaciones a
                 where a.etiqueta = pg_catalog.split_part(p_origen, '-', 1) and a.analista_id = p_actor
                   and (a.vigente_hasta is null or a.vigente_hasta >= v_hora)) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'celular_ajeno');
  end if;

  -- 2. El resultado: lo creó o reconfirmó la v4 en esta transacción, con el lead ya bloqueado. Se toma FOR KEY SHARE SIN
  --    ESPERAR (20261005182227): el enlace y la intención lo piden igual por su llave foránea, y Deshacer lo bloquea
  --    ANTES que el lead (ciclo reproducido en el #190). Solo choca en el reintento de una operación cuyo resultado se
  --    está deshaciendo: en el camino normal el resultado es de esta misma transacción.
  begin
    select * into v_act from crm.actividades a where a.id = p_actividad_id for key share nowait;
  exception when lock_not_available then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_en_uso');
  end;
  if v_act.id is null or v_act.lead_id <> p_lead_id or v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
     or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
    raise exception using errcode = '23514', message = 'El servidor no confirmó el resultado de la llamada';
  end if;
  if v_act.metadata ? 'deshecho_en' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_deshecho');
  end if;

  -- 3. ¿La llamada ya llegó? Candado: lead (v4) → llamada → enlace.
  select * into v_ev from crm.llamadas_celular_eventos e where e.evento_origen_id = p_origen for update;
  if found then
    if v_ev.analista_id <> p_actor then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'celular_ajeno');
    end if;
    if v_ev.atencion = 'descartado_con_motivo' then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'descartada');
    end if;
    if v_ev.identificacion <> 'identificado' or v_ev.lead_id is distinct from p_lead_id then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'otro_lead');
    end if;
    select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id for update;
    if found then
      if v_enl.actividad_id = p_actividad_id then
        return pg_catalog.jsonb_build_object('estado', 'repetido');
      end if;
      select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
      if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'ya_tiene_resultado');
      end if;
      begin
        update crm.llamadas_celular_enlaces set actividad_id = p_actividad_id, enlazado_por = p_actor
         where id = v_enl.id;
      exception when unique_violation then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
      end;
      v_estado := 'movido';
    else
      begin
        insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via)
        values (v_ev.id, p_actividad_id, v_ev.lead_id, p_actor, p_via);
      exception when unique_violation then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
      end;
      v_estado := 'enlazado';
    end if;
    -- La máquina de estados de la tabla exige pasar por «requiere resultado».
    if v_ev.atencion = 'por_revisar' then
      update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
    end if;
    if v_ev.atencion <> 'registrado' then
      update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
    end if;
    return pg_catalog.jsonb_build_object('estado', v_estado);
  end if;

  -- 4. Todavía no llegó. Si el aviso llegó y se ignoró, no se guarda nada: nunca se cumpliría.
  if exists (select 1 from private.llamadas_celular_recepciones r where r.evento_origen_id = p_origen) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'sin_llamada');
  end if;
  if exists (select 1 from crm.llamadas_celular_enlaces l where l.actividad_id = p_actividad_id) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
  end if;
  select * into v_int from private.llamadas_celular_intenciones i where i.evento_origen_id = p_origen for update;
  if found then
    if v_int.actividad_id = p_actividad_id then
      return pg_catalog.jsonb_build_object('estado', 'pendiente');
    end if;
    if v_int.analista_id <> p_actor or v_int.lead_id <> p_lead_id then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'otro_lead');
    end if;
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_int.actividad_id;
    if not coalesce(v_deshecha, false) then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'ya_tiene_resultado');
    end if;
    begin
      update private.llamadas_celular_intenciones set actividad_id = p_actividad_id where id = v_int.id;
    exception when unique_violation then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
    end;
    return pg_catalog.jsonb_build_object('estado', 'pendiente');
  end if;
  begin
    insert into private.llamadas_celular_intenciones (evento_origen_id, analista_id, lead_id, actividad_id, via)
    values (p_origen, p_actor, p_lead_id, p_actividad_id, p_via);
  exception when unique_violation then
    get stacked diagnostics v_restriccion = constraint_name;
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo',
      case when v_restriccion = 'llamadas_celular_intenciones_origen_uq' then 'ya_tiene_resultado'
           else 'resultado_ya_enlazado' end);
  end;
  return pg_catalog.jsonb_build_object('estado', 'pendiente');
end;
$function$;

-- ── 2. La intención que cumple la ingesta: el resultado, sin esperar ─────────────────────────
create or replace function private.llamada_celular_cumplir_intencion(p_evento_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_int private.llamadas_celular_intenciones%rowtype;
  v_act crm.actividades%rowtype;
begin
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found then
    return;
  end if;
  select * into v_int from private.llamadas_celular_intenciones i where i.evento_origen_id = v_ev.evento_origen_id for update;
  if not found then
    return;
  end if;
  perform pg_catalog.set_config('crm.op_enlace_llamadas', 'on', true);
  delete from private.llamadas_celular_intenciones where id = v_int.id;
  perform pg_catalog.set_config('crm.op_enlace_llamadas', 'off', true);
  if v_int.analista_id <> v_ev.analista_id or v_ev.identificacion <> 'identificado'
     or v_ev.lead_id is distinct from v_int.lead_id then
    return;
  end if;
  -- El resultado se toma FOR KEY SHARE SIN ESPERAR (20261005182227): Deshacer lo bloquea ANTES que el lead, que aquí ya
  -- está tomado, y la llave foránea del enlace lo pedía igual (ciclo reproducido en el #190). Si lo tiene otro, la
  -- intención ya se retiró y la llamada queda para unirla a mano (decisión de Jhosep, 05/10: no esperar).
  begin
    select * into v_act from crm.actividades a where a.id = v_int.actividad_id for key share nowait;
  exception when lock_not_available then
    return;
  end;
  if v_act.id is null or v_act.metadata ? 'deshecho_en' then
    return;
  end if;
  begin
    insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via)
    values (v_ev.id, v_int.actividad_id, v_ev.lead_id, v_int.analista_id, v_int.via);
  exception when unique_violation then
    return;  -- ese resultado ya quedó unido a otra llamada
  end;
  if v_ev.atencion = 'por_revisar' then
    update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
  end if;
  update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
end;
$function$;

-- ── 3. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz) is
  'Enlace EXACTO (F4-a) de un resultado recién registrado por la v5 con la llamada de su id: id con forma y ventana de un celular del analista; llamada ya llegada, del mismo analista, identificada con ese lead → enlace (o lo mueve si el anterior se deshizo); no llegada → intención de enlace (o la mueve); sin la regla de los 10 minutos. Nunca lanza por un enlace imposible: {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}. Candados: lead (ya bloqueado por la v4) → resultado FOR KEY SHARE sin esperar → llamada → enlace o intención. Desde 20261005182227 el resultado se toma sin esperar (Deshacer bloquea resultado → lead; esperarlo con el lead tomado cerraba un ciclo): si lo tiene otro → no_enlazado, motivo resultado_en_uso.';
comment on function private.llamada_celular_cumplir_intencion(uuid) is
  'La ingesta, guardada una llamada, cumple la intención de su id: la retira y, si coincide (mismo analista, llamada identificada con ese lead, resultado vigente y sin otra llamada), crea el enlace con su vía y deja la llamada en «registrado». Desde 20261005182227 toma el resultado FOR KEY SHARE sin esperar: Deshacer lo bloquea antes que el lead, que aquí ya está tomado, y la llave foránea del enlace lo pedía igual (ciclo reproducido en la revisión de Miguel del #190). Si lo tiene otro, la intención se retira sin enlace y la llamada queda para unirla a mano (decisión de Jhosep, 05/10).';

-- ── 4. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)',
    'private.llamada_celular_cumplir_intencion(uuid)'] loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f::regprocedure) then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: % debería ser SECURITY INVOKER', v_f;
    end if;
    if exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
               where p.oid = v_f::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner)
       or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f::regprocedure) then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: EXECUTE inesperado en %', v_f;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: search_path inesperado en %', v_f;
    end if;
    if pg_catalog.obj_description(v_f::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: % sin COMMENT', v_f;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: % atrapa cualquier error (WHEN OTHERS)', v_f;
    end if;
  end loop;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'::regprocedure),
                       'private.llamada_celular_cumplir_intencion(') = 0 then
    raise exception 'LLAMADAS_ENLACE_SIN_CICLO: la ingesta no cumple las intenciones de enlace';
  end if;
end;
$postflight$;

commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261005182227 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261005182227', 'crm_llamadas_celular_enlace_sin_ciclo', array[$mig$-- Llamadas desde el celular · séptima migración: el enlace exacto SIN CICLO de candados con «Deshacer». Corrige el [P2]
-- de la revisión del agente de Miguel en el PR #190 (05/10/2026, 18:13 UTC; reproducido con dos sesiones sobre las seis
-- migraciones): al unir un resultado con su llamada, la llave foránea del enlace (y la de la intención) toma el resultado
-- FOR KEY SHARE aunque nadie lo pida; Deshacer (20260920005000:649 y 682) bloquea resultado → lead FOR UPDATE; la
-- ingesta y la v5 llegan con el lead ya tomado y esperaban el resultado: lead → resultado contra resultado → lead =
-- interbloqueo (40P01). Se publica JUNTO con las seis (va antes de dar de alta celulares, como ellas).
--
-- Qué hace (sin editar F4-a, 20261005155914; mismas firmas, mismos permisos, sin tablas ni datos):
--   1. private.llamada_celular_cumplir_intencion (la ingesta): toma el resultado FOR KEY SHARE NOWAIT antes de crear el
--      enlace. Si Deshacer lo tiene (55P03 lock_not_available, lo único que se atrapa), la intención ya se retiró y no se
--      une: la llamada queda en la pestaña para unirla a mano. Decisión de Jhosep (05/10): no esperar.
--   2. private.llamada_celular_enlazar_exacto (la v5): igual, antes de crear o mover el enlace o la intención. Si lo tiene
--      otro → {estado: no_enlazado, motivo: resultado_en_uso}; el resultado ya quedó guardado. Solo pasa en el reintento
--      de una operación cuyo resultado se está deshaciendo: en el camino normal el resultado es de esta transacción.
--   Solo Deshacer bloquea un resultado FOR UPDATE (comprobado en todas las migraciones el 05/10). La actualización que
--   hace la v4 (FOR NO KEY UPDATE) no choca con FOR KEY SHARE: el «no esperar» no falla por otros escritores.
--
-- Capas (estándar de 4 capas): solo núcleo de private (INVOKER, sin EXECUTE para nadie); las puertas (v5 e ingesta de
-- servicio) no cambian de firma. La v5 suma un valor de motivo (resultado_en_uso); ninguna pantalla la usa todavía (F4-b).
-- Excepción single-tenant (F2.3.3): el CRM es de una sola empresa; no hay columna de tenant.
-- Reversión: ../scripts/llamadas-celular/reversa-enlace-sin-ciclo.sql (solo cuerpos y COMMENT, sin datos: vuelve a la
-- huella exacta de las seis). Verificación: npm run test:llamadas:local (pasadas 13 y 14: huella, oráculos de F4-a y de la
-- quinta, carreras con Deshacer pausado entre sus dos candados, en los dos órdenes y revertido, y mutantes).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('private.llamadas_celular_intenciones') is null
     or to_regprocedure('private.llamada_celular_cumplir_intencion(uuid)') is null
     or to_regprocedure('private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)') is null then
    raise exception 'LLAMADAS_ENLACE_SIN_CICLO: falta F4-a (20261005155914)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_cumplir_intencion(uuid)'::regprocedure),
                       'for key share nowait') > 0 then
    raise exception 'LLAMADAS_ENLACE_SIN_CICLO: ya está aplicada; no se sobrescribe';
  end if;
end;
$precondicion$;

-- ── 1. El enlace de la v5: el resultado, sin esperar ─────────────────────────────────────────
create or replace function private.llamada_celular_enlazar_exacto(
  p_actor uuid, p_lead_id uuid, p_actividad_id uuid, p_origen text, p_via text, p_ahora timestamptz)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_act crm.actividades%rowtype;
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_enl crm.llamadas_celular_enlaces%rowtype;
  v_int private.llamadas_celular_intenciones%rowtype;
  v_hora timestamptz;
  v_deshecha boolean;
  v_restriccion text;
  v_estado text;
begin
  -- 1. El id: forma fija, dentro de la ventana de la ingesta y de un celular del analista que registra.
  if p_origen is null or p_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'id_invalido');
  end if;
  v_hora := pg_catalog.to_timestamp(pg_catalog.split_part(p_origen, '-', 2)::bigint);
  if v_hora < p_ahora - interval '30 days' or v_hora > p_ahora + interval '1 day' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'id_invalido');
  end if;
  if not exists (select 1 from crm.celulares_asignaciones a
                 where a.etiqueta = pg_catalog.split_part(p_origen, '-', 1) and a.analista_id = p_actor
                   and (a.vigente_hasta is null or a.vigente_hasta >= v_hora)) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'celular_ajeno');
  end if;

  -- 2. El resultado: lo creó o reconfirmó la v4 en esta transacción, con el lead ya bloqueado. Se toma FOR KEY SHARE SIN
  --    ESPERAR (20261005182227): el enlace y la intención lo piden igual por su llave foránea, y Deshacer lo bloquea
  --    ANTES que el lead (ciclo reproducido en el #190). Solo choca en el reintento de una operación cuyo resultado se
  --    está deshaciendo: en el camino normal el resultado es de esta misma transacción.
  begin
    select * into v_act from crm.actividades a where a.id = p_actividad_id for key share nowait;
  exception when lock_not_available then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_en_uso');
  end;
  if v_act.id is null or v_act.lead_id <> p_lead_id or v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
     or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
    raise exception using errcode = '23514', message = 'El servidor no confirmó el resultado de la llamada';
  end if;
  if v_act.metadata ? 'deshecho_en' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_deshecho');
  end if;

  -- 3. ¿La llamada ya llegó? Candado: lead (v4) → llamada → enlace.
  select * into v_ev from crm.llamadas_celular_eventos e where e.evento_origen_id = p_origen for update;
  if found then
    if v_ev.analista_id <> p_actor then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'celular_ajeno');
    end if;
    if v_ev.atencion = 'descartado_con_motivo' then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'descartada');
    end if;
    if v_ev.identificacion <> 'identificado' or v_ev.lead_id is distinct from p_lead_id then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'otro_lead');
    end if;
    select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id for update;
    if found then
      if v_enl.actividad_id = p_actividad_id then
        return pg_catalog.jsonb_build_object('estado', 'repetido');
      end if;
      select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
      if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'ya_tiene_resultado');
      end if;
      begin
        update crm.llamadas_celular_enlaces set actividad_id = p_actividad_id, enlazado_por = p_actor
         where id = v_enl.id;
      exception when unique_violation then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
      end;
      v_estado := 'movido';
    else
      begin
        insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via)
        values (v_ev.id, p_actividad_id, v_ev.lead_id, p_actor, p_via);
      exception when unique_violation then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
      end;
      v_estado := 'enlazado';
    end if;
    -- La máquina de estados de la tabla exige pasar por «requiere resultado».
    if v_ev.atencion = 'por_revisar' then
      update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
    end if;
    if v_ev.atencion <> 'registrado' then
      update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
    end if;
    return pg_catalog.jsonb_build_object('estado', v_estado);
  end if;

  -- 4. Todavía no llegó. Si el aviso llegó y se ignoró, no se guarda nada: nunca se cumpliría.
  if exists (select 1 from private.llamadas_celular_recepciones r where r.evento_origen_id = p_origen) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'sin_llamada');
  end if;
  if exists (select 1 from crm.llamadas_celular_enlaces l where l.actividad_id = p_actividad_id) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
  end if;
  select * into v_int from private.llamadas_celular_intenciones i where i.evento_origen_id = p_origen for update;
  if found then
    if v_int.actividad_id = p_actividad_id then
      return pg_catalog.jsonb_build_object('estado', 'pendiente');
    end if;
    if v_int.analista_id <> p_actor or v_int.lead_id <> p_lead_id then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'otro_lead');
    end if;
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_int.actividad_id;
    if not coalesce(v_deshecha, false) then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'ya_tiene_resultado');
    end if;
    begin
      update private.llamadas_celular_intenciones set actividad_id = p_actividad_id where id = v_int.id;
    exception when unique_violation then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
    end;
    return pg_catalog.jsonb_build_object('estado', 'pendiente');
  end if;
  begin
    insert into private.llamadas_celular_intenciones (evento_origen_id, analista_id, lead_id, actividad_id, via)
    values (p_origen, p_actor, p_lead_id, p_actividad_id, p_via);
  exception when unique_violation then
    get stacked diagnostics v_restriccion = constraint_name;
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo',
      case when v_restriccion = 'llamadas_celular_intenciones_origen_uq' then 'ya_tiene_resultado'
           else 'resultado_ya_enlazado' end);
  end;
  return pg_catalog.jsonb_build_object('estado', 'pendiente');
end;
$function$;

-- ── 2. La intención que cumple la ingesta: el resultado, sin esperar ─────────────────────────
create or replace function private.llamada_celular_cumplir_intencion(p_evento_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_int private.llamadas_celular_intenciones%rowtype;
  v_act crm.actividades%rowtype;
begin
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found then
    return;
  end if;
  select * into v_int from private.llamadas_celular_intenciones i where i.evento_origen_id = v_ev.evento_origen_id for update;
  if not found then
    return;
  end if;
  perform pg_catalog.set_config('crm.op_enlace_llamadas', 'on', true);
  delete from private.llamadas_celular_intenciones where id = v_int.id;
  perform pg_catalog.set_config('crm.op_enlace_llamadas', 'off', true);
  if v_int.analista_id <> v_ev.analista_id or v_ev.identificacion <> 'identificado'
     or v_ev.lead_id is distinct from v_int.lead_id then
    return;
  end if;
  -- El resultado se toma FOR KEY SHARE SIN ESPERAR (20261005182227): Deshacer lo bloquea ANTES que el lead, que aquí ya
  -- está tomado, y la llave foránea del enlace lo pedía igual (ciclo reproducido en el #190). Si lo tiene otro, la
  -- intención ya se retiró y la llamada queda para unirla a mano (decisión de Jhosep, 05/10: no esperar).
  begin
    select * into v_act from crm.actividades a where a.id = v_int.actividad_id for key share nowait;
  exception when lock_not_available then
    return;
  end;
  if v_act.id is null or v_act.metadata ? 'deshecho_en' then
    return;
  end if;
  begin
    insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via)
    values (v_ev.id, v_int.actividad_id, v_ev.lead_id, v_int.analista_id, v_int.via);
  exception when unique_violation then
    return;  -- ese resultado ya quedó unido a otra llamada
  end;
  if v_ev.atencion = 'por_revisar' then
    update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
  end if;
  update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
end;
$function$;

-- ── 3. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz) is
  'Enlace EXACTO (F4-a) de un resultado recién registrado por la v5 con la llamada de su id: id con forma y ventana de un celular del analista; llamada ya llegada, del mismo analista, identificada con ese lead → enlace (o lo mueve si el anterior se deshizo); no llegada → intención de enlace (o la mueve); sin la regla de los 10 minutos. Nunca lanza por un enlace imposible: {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}. Candados: lead (ya bloqueado por la v4) → resultado FOR KEY SHARE sin esperar → llamada → enlace o intención. Desde 20261005182227 el resultado se toma sin esperar (Deshacer bloquea resultado → lead; esperarlo con el lead tomado cerraba un ciclo): si lo tiene otro → no_enlazado, motivo resultado_en_uso.';
comment on function private.llamada_celular_cumplir_intencion(uuid) is
  'La ingesta, guardada una llamada, cumple la intención de su id: la retira y, si coincide (mismo analista, llamada identificada con ese lead, resultado vigente y sin otra llamada), crea el enlace con su vía y deja la llamada en «registrado». Desde 20261005182227 toma el resultado FOR KEY SHARE sin esperar: Deshacer lo bloquea antes que el lead, que aquí ya está tomado, y la llave foránea del enlace lo pedía igual (ciclo reproducido en la revisión de Miguel del #190). Si lo tiene otro, la intención se retira sin enlace y la llamada queda para unirla a mano (decisión de Jhosep, 05/10).';

-- ── 4. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)',
    'private.llamada_celular_cumplir_intencion(uuid)'] loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f::regprocedure) then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: % debería ser SECURITY INVOKER', v_f;
    end if;
    if exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
               where p.oid = v_f::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner)
       or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f::regprocedure) then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: EXECUTE inesperado en %', v_f;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: search_path inesperado en %', v_f;
    end if;
    if pg_catalog.obj_description(v_f::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: % sin COMMENT', v_f;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_ENLACE_SIN_CICLO: % atrapa cualquier error (WHEN OTHERS)', v_f;
    end if;
  end loop;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'::regprocedure),
                       'private.llamada_celular_cumplir_intencion(') = 0 then
    raise exception 'LLAMADAS_ENLACE_SIN_CICLO: la ingesta no cumple las intenciones de enlace';
  end if;
end;
$postflight$;

commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261005182227' and name = 'crm_llamadas_celular_enlace_sin_ciclo' and cardinality(statements) = 1
                   and md5(statements[1]) = '6dea6bd39fa2435ae883396e2c957783') then
    raise exception 'REGISTRO: la fila 20261005182227 / crm_llamadas_celular_enlace_sin_ciclo no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261005182227 / crm_llamadas_celular_enlace_sin_ciclo (1 sentencia: el archivo entero)';
end $post$;
commit;
select (select count(*) from supabase_migrations.schema_migrations
        where version = '20261005182227' and name = 'crm_llamadas_celular_enlace_sin_ciclo' and md5(statements[1]) = '6dea6bd39fa2435ae883396e2c957783') = 1
       as veredicto_registro_20261005182227;
