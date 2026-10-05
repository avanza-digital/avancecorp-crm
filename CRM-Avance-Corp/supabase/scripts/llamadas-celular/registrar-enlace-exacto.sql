-- REGISTRO en supabase_migrations.schema_migrations de 20261005155914_crm_llamadas_celular_enlace_exacto (F4-a: enlace exacto encuesta ↔ llamada).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración, en un mensaje aparte (punto 18 de
-- REVISION-2026-10-02.md; guía PUBLICAR-F2-F3.md: cada registrador justo después de su migración). Idempotente; se
-- niega si los objetos no están con su forma o si la versión ya está registrada con otro nombre u otro contenido;
-- relee la fila antes de confirmar. statements = el archivo entero (md5 69d2137ecf345dda3e8be66b3d6b44fb, con finales de línea LF:
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
    to_regclass('private.llamadas_celular_intenciones') is not null
    and to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is not null
    and to_regprocedure('private.llamada_celular_cumplir_intencion(uuid)') is not null
    and exists (select 1 from pg_catalog.pg_attribute a
                where a.attrelid = 'crm.llamadas_celular_enlaces'::regclass and a.attname = 'via' and not a.attisdropped)
  ) is not true then
    raise exception 'REGISTRO: la migración 20261005155914 no está aplicada (o no con su forma); aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261005155914' and (coalesce(name, '') <> 'crm_llamadas_celular_enlace_exacto' or statements is distinct from array[$mig$-- Llamadas desde el celular · F4-a: ENLACE EXACTO encuesta ↔ llamada (sexta migración; se publica JUNTO con las cinco
-- de F2 + F3, decisión 1 de Miguel del 03/10). Plan: CORRECCION-PLAN-CORTO.md §7 (v2, PR #179) y F4-PLAN-CORTO.md §1.
-- Cierra el fallo 5 de la revisión del 02/10 (nada unía la encuesta con su llamada) del lado de la base; la pantalla
-- que lleva el id hasta la encuesta y llama a la v5 es F4-b.
--
-- Qué hace (sobre 20261005143843; no toca la v4 sellada):
--   1. crm.registrar_llamada_v5: la misma operación que la v4 (llama a su núcleo sellado private.llamada_registrar_v4,
--      que bloquea el lead y crea el resultado) y, en la MISMA transacción, une ese resultado a la llamada por su id
--      exacto (C<n>-<segundos>, el que la macro pone en la URL al colgar):
--        · si la llamada ya llegó (del celular del mismo analista, identificada con ese lead) → el enlace;
--        · si todavía no llegó → una intención de enlace, que la ingesta cumple sola al llegar el aviso;
--        · si no se puede unir (id mal formado, celular ajeno, otro lead, descartada, ya tenía otro resultado no
--          deshecho) → el resultado se guarda IGUAL y la respuesta dice «no_enlazado» y por qué: la llamada queda en
--          la pestaña para unirla a mano (decisión de Jhosep, 05/10).
--      Sin la regla de los 10 minutos: en el camino exacto un reloj adelantado no rechaza nada (confirmación 3 de
--      Miguel, Codex P2-5). Al registrar el resultado corregido tras Deshacer, el enlace (o la intención) pasa al
--      corregido (confirmación 2). Una llamada ambigua no se une por este camino: va a la pestaña (Jhosep, 05/10).
--   2. private.llamadas_celular_intenciones: la intención de enlace por id. Única por id y por resultado; caduca a los
--      32 días (si el aviso nunca llega). Tabla técnica de private, sin auditoría (como las recepciones).
--   3. crm.llamadas_celular_enlaces.via: al_colgar, pestana o manual. Sin ella no se mide «encuesta abierta al colgar»
--      por celular, el objetivo de Jhosep. Inmutable.
--   4. La ingesta (cuerpo de 20261005143843 con dos cambios): bloquea el lead FOR SHARE antes de guardar la llamada (el
--      orden lead → llamada → enlace de la v5) y, guardada, cumple la intención si la hay.
--   5. La purga (cuerpo de 20261005143843 con un cambio): retira las intenciones de más de 32 días.
--
-- Candados: v5 = lead (núcleo de v4, FOR UPDATE) → llamada → enlace o intención; ingesta = lead FOR SHARE → llamada →
-- intención → enlace. Los dos empiezan por el lead: un aviso que llega mientras se guarda la encuesta espera, y la
-- encuesta que llega mientras se guarda el aviso también; ninguno pierde el enlace. La ingesta lee el resultado sin
-- candado: Deshacer toma resultado → lead, y bloquearlo después del lead invertiría ese orden.
--
-- Decisiones de criterio de Claude (05/10/2026), para Miguel:
--   · La intención va en private, sin auditoría: es transitoria y no guarda datos personales (id, lead, resultado).
--   · via nace con valor por defecto «manual»: el enlace manual (crm.enlazar_llamada_celular) no cambia; la v5 y la
--     intención la fijan siempre.
--   · La v5 exige que la etiqueta del id sea de un celular del analista que registra (vigente, o cerrado después de
--     la llamada). Un supervisor que registra por el lead de su analista no enlaza: la llamada queda en la pestaña.
--   · Si el aviso ya llegó y se ignoró (recepción sin llamada), no se guarda intención: nunca se cumpliría.
--   · «Qué pasó hoy» (la lectura de lo ya resuelto, hallazgo 1 de F4) pasa a F4-b, con la pantalla.
--
-- Excepción single-tenant (estándar de 4 capas, F2.3.3): el CRM es de una sola empresa; no hay columna de tenant.
-- Reversión: ../scripts/llamadas-celular/reversa-enlace-exacto.sql, SOLO antes del primer aviso (sin enlaces ni
-- intenciones): vuelve exactamente al estado de las cinco. Verificación: npm run test:llamadas:local (oráculo
-- tests/llamadas-celular/oraculo-enlace-exacto.sql, huella del catálogo, mutantes y carreras con dos sesiones).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('private.llamadas_celular_intenciones') is not null
     or to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is not null then
    raise exception 'LLAMADAS_ENLACE_EXACTO: los objetos ya existen; no se sobrescriben';
  end if;
  if to_regclass('private.llamadas_celular_recepciones') is null
     or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is null
     or to_regprocedure('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)') is null then
    raise exception 'LLAMADAS_ENLACE_EXACTO: falta la quinta migración (20261005143843)';
  end if;
  if to_regprocedure('private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)') is null then
    raise exception 'LLAMADAS_ENLACE_EXACTO: falta el núcleo de la encuesta v4 (20260921153654)';
  end if;
  -- La v5 compone la v4 SELLADA: si su gate existe (producción), tiene que pasar antes de instalar.
  if to_regprocedure('private.assert_gestion_diaria_resultado_v4()') is not null then
    perform private.assert_gestion_diaria_resultado_v4();
  end if;
end;
$precondicion$;

lock table crm.llamadas_celular_eventos, crm.llamadas_celular_enlaces in access exclusive mode;

-- ── 1. Intenciones de enlace (private, sin auditoría, 32 días) ───────────────────────────────
create table private.llamadas_celular_intenciones (
  id               uuid primary key default gen_random_uuid(),
  evento_origen_id text not null
                   constraint llamadas_celular_intenciones_origen_valido
                   check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$')
                   constraint llamadas_celular_intenciones_origen_uq unique,
  analista_id      uuid not null references crm.equipo(perfil_id) on delete restrict,
  lead_id          uuid not null references crm.leads(id) on delete cascade,
  actividad_id     uuid not null references crm.actividades(id) on delete cascade
                   constraint llamadas_celular_intenciones_actividad_uq unique,
  via              text not null
                   constraint llamadas_celular_intenciones_via_valida check (via in ('al_colgar', 'pestana')),
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);
alter table private.llamadas_celular_intenciones enable row level security;
revoke all on private.llamadas_celular_intenciones from public, anon, authenticated, service_role;
create index llamadas_celular_intenciones_analista_idx on private.llamadas_celular_intenciones (analista_id);
create index llamadas_celular_intenciones_lead_idx on private.llamadas_celular_intenciones (lead_id);
create index llamadas_celular_intenciones_creado_idx on private.llamadas_celular_intenciones (creado_en);

create function private.trg_llamadas_celular_intenciones_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_deshecha boolean;
begin
  if tg_op = 'DELETE' then
    -- La cumple la ingesta (GUC de enlace), la retira la purga (su GUC) o se va con su lead o su resultado (cascada).
    if coalesce(pg_catalog.current_setting('crm.op_enlace_llamadas', true), 'off') = 'on'
       or coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'
       or pg_catalog.pg_trigger_depth() > 1 then
      return old;
    end if;
    raise exception using errcode = '42501', message = 'Una intención de enlace no se borra a mano';
  end if;
  if new.id <> old.id or new.evento_origen_id <> old.evento_origen_id or new.analista_id <> old.analista_id
     or new.lead_id <> old.lead_id or new.via <> old.via or new.creado_en <> old.creado_en then
    raise exception using errcode = '42501',
      message = 'De una intención de enlace solo cambia el resultado, cuando el anterior se deshizo';
  end if;
  if new.actividad_id <> old.actividad_id then
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = old.actividad_id;
    if not coalesce(v_deshecha, false) then
      raise exception using errcode = '42501',
        message = 'La intención solo pasa a otro resultado si el anterior se deshizo';
    end if;
  end if;
  new.actualizado_en := pg_catalog.now();
  return new;
end;
$function$;
create trigger trg_llamadas_celular_intenciones_00_candado
  before update or delete on private.llamadas_celular_intenciones
  for each row execute function private.trg_llamadas_celular_intenciones_candado();
create trigger trg_llamadas_celular_intenciones_00_sin_vaciar
  before truncate on private.llamadas_celular_intenciones
  for each statement execute function private.trg_llamadas_celular_sin_vaciar();

-- ── 2. Vía del enlace (inmutable) ────────────────────────────────────────────────────────────
alter table crm.llamadas_celular_enlaces
  add column via text not null default 'manual'
    constraint llamadas_celular_enlaces_via_valida check (via in ('al_colgar', 'pestana', 'manual'));

-- Candado de los enlaces: el cuerpo de 20261001145242 con un cambio (la vía no cambia).
create or replace function private.trg_llamadas_celular_enlaces_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_act crm.actividades%rowtype;
  v_ev  crm.llamadas_celular_eventos%rowtype;
  v_deshecha boolean;
begin
  if tg_op = 'DELETE' then
    if pg_catalog.pg_trigger_depth() > 1 then
      return old; -- cascada: se fue el evento o el lead
    end if;
    raise exception using errcode = '42501', message = 'El enlace de una llamada no se borra';
  end if;

  if tg_op = 'UPDATE' then
    -- La actividad se eliminó (cascada del lead → ON DELETE SET NULL): única escritura anidada
    -- aceptada, y solo si no cambia nada más.
    if pg_catalog.pg_trigger_depth() > 1 and new.actividad_id is null and old.actividad_id is not null
       and (pg_catalog.to_jsonb(new) - 'actividad_id' - 'actualizado_en')
         = (pg_catalog.to_jsonb(old) - 'actividad_id' - 'actualizado_en') then
      new.actualizado_en := pg_catalog.now();
      return new;
    end if;
    if new.id <> old.id or new.evento_id <> old.evento_id or new.lead_id <> old.lead_id
       or new.creado_en <> old.creado_en or new.via <> old.via then
      raise exception using errcode = '42501', message = 'El enlace de una llamada no cambia de evento, de lead ni de vía';
    end if;
    if new.actividad_id is distinct from old.actividad_id then
      if new.actividad_id is null then
        raise exception using errcode = '42501', message = 'Un enlace no se desenlaza: el resultado deshecho se marca, no se borra';
      end if;
      if old.actividad_id is not null then
        select (a.metadata ? 'deshecho_en') into v_deshecha
        from crm.actividades a where a.id = old.actividad_id;
        if not coalesce(v_deshecha, false) then
          raise exception using errcode = '42501',
            message = 'El enlace solo cambia de actividad si el resultado anterior fue deshecho';
        end if;
      end if;
    end if;
  elsif new.actividad_id is null then
    raise exception using errcode = '22023', message = 'Un enlace nace con la actividad registrada';
  end if;

  if new.actividad_id is not null and (tg_op = 'INSERT' or new.actividad_id is distinct from old.actividad_id) then
    select * into v_act from crm.actividades a where a.id = new.actividad_id;
    if not found then
      raise exception using errcode = '22023', message = 'La actividad enlazada no existe';
    end if;
    if v_act.lead_id <> new.lead_id then
      raise exception using errcode = '22023', message = 'La actividad enlazada es de otro lead';
    end if;
    if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
       or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
      raise exception using errcode = '22023',
        message = 'Solo se enlaza un resultado de llamada registrado por la encuesta';
    end if;
  end if;

  select * into v_ev from crm.llamadas_celular_eventos e where e.id = new.evento_id;
  if not found then
    raise exception using errcode = '22023', message = 'La llamada enlazada no existe';
  end if;
  if v_ev.lead_id is distinct from new.lead_id then
    raise exception using errcode = '22023', message = 'El enlace debe apuntar al lead de la llamada';
  end if;

  if tg_op = 'UPDATE' then
    new.actualizado_en := pg_catalog.now();
  end if;
  return new;
end;
$function$;

-- ── 3. Núcleo del enlace exacto (INVOKER, sin EXECUTE para nadie) ────────────────────────────

-- Une un resultado que la v5 acaba de registrar (o reconfirmar) con la llamada de ese id. Nunca lanza por un enlace
-- imposible: devuelve {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}.
create function private.llamada_celular_enlazar_exacto(
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

  -- 2. El resultado: lo creó o reconfirmó la v4 en esta transacción, con el lead ya bloqueado.
  select * into v_act from crm.actividades a where a.id = p_actividad_id;
  if not found or v_act.lead_id <> p_lead_id or v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
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

-- La ingesta, guardada la llamada, cumple la intención de su id. La intención se retira se cumpla o no: si no
-- coincide (otro analista, otro lead, resultado deshecho o ya unido a otra llamada), la llamada queda pendiente.
create function private.llamada_celular_cumplir_intencion(p_evento_id uuid)
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
  -- Sin candado sobre el resultado: Deshacer lo toma ANTES que el lead, y aquí el lead ya está bloqueado.
  select * into v_act from crm.actividades a where a.id = v_int.actividad_id;
  if not found or v_act.metadata ? 'deshecho_en' then
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

-- La ingesta: el cuerpo de 20261005143843 con dos cambios (candado del lead antes de guardar; cumplir la intención).
create or replace function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb, p_ahora timestamptz)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_claves constant text[] := array['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico',
                                    'duracion_seg', 'ocurrio_en'];
  v_asig crm.celulares_asignaciones%rowtype;
  v_pol crm.llamadas_celular_politica%rowtype;
  v_origen text;
  v_numero text;
  v_dir text;
  v_estado text;
  v_dur integer;
  v_ocurrio timestamptz;
  v_hora_id timestamptz;
  v_recepcion uuid;
  v_formas text[];
  v_e164 text;
  v_cand uuid[];
  v_lead uuid;
  v_ident text;
  v_aten text;
  v_metodo text;
  v_calidad jsonb := '{}'::jsonb;
  v_aceptado constant jsonb := '{"resultado": "aceptado"}'::jsonb;
  v_evento uuid;
begin
  -- La puerta ya bloqueó la asignación FOR SHARE y la revalidó; aquí se relee bajo el mismo candado.
  select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
  if not found or v_asig.vigente_hasta is not null
     or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
  end if;

  -- Validación: todo inválido responde «invalido» y el cupo ya gastado queda (menor 11, Codex P3). El bloque
  -- atrapa SOLO 22023: un error inesperado sigue siendo un error (503, que revierte todo, el cupo incluido).
  begin
    if p_evento is null or pg_catalog.jsonb_typeof(p_evento) <> 'object' then
      raise exception using errcode = '22023', message = 'El evento debe ser un objeto JSON';
    end if;
    if exists (select 1 from pg_catalog.jsonb_object_keys(p_evento) k where k <> all(v_claves)) then
      raise exception using errcode = '22023', message = 'El evento trae claves no previstas';
    end if;
    if coalesce(p_evento ->> 'v', '') <> '1' then
      raise exception using errcode = '22023', message = 'Versión de evento no soportada (se espera v = 1)';
    end if;
    v_origen := p_evento ->> 'evento_origen_id';
    if v_origen is null or v_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id inválido: se espera la etiqueta del celular y los segundos de su reloj (p. ej. C1-1790980958)';
    end if;
    if pg_catalog.split_part(v_origen, '-', 1) <> v_asig.etiqueta then
      raise exception using errcode = '22023',
        message = pg_catalog.format('evento_origen_id con la etiqueta de otro celular (esta clave es de %s)', v_asig.etiqueta);
    end if;
    v_hora_id := pg_catalog.to_timestamp(pg_catalog.split_part(v_origen, '-', 2)::bigint);
    if v_hora_id < p_ahora - interval '30 days' or v_hora_id > p_ahora + interval '1 day' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id fuera de la ventana: su hora debe caer entre hace 30 días y mañana (¿hora automática en el celular?)';
    end if;
    v_numero := nullif(pg_catalog.btrim(coalesce(p_evento ->> 'numero', '')), '');
    if pg_catalog.length(v_numero) > 40 then
      raise exception using errcode = '22023', message = 'El número no puede pasar de 40 caracteres';
    end if;
    v_dir := coalesce(p_evento ->> 'direccion', 'desconocida');
    if v_dir not in ('saliente', 'entrante', 'desconocida') then
      raise exception using errcode = '22023', message = 'direccion inválida (saliente, entrante o desconocida)';
    end if;
    v_estado := coalesce(p_evento ->> 'estado_tecnico', 'desconocido');
    if v_estado not in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido') then
      raise exception using errcode = '22023', message = 'estado_tecnico inválido';
    end if;
    if coalesce(pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg'), 'null') <> 'null' then
      if pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg') <> 'number'
         or (p_evento ->> 'duracion_seg') !~ '^[0-9]{1,5}$' or (p_evento ->> 'duracion_seg')::integer > 86400 then
        raise exception using errcode = '22023', message = 'duracion_seg debe ser un entero de 0 a 86400';
      end if;
      v_dur := (p_evento ->> 'duracion_seg')::integer;
    end if;
    v_ocurrio := private.llamada_celular_fecha(p_evento ->> 'ocurrio_en');
  exception when sqlstate '22023' then
    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
  end;

  -- Recepción ANTES de mirar leads, también si después se ignora (fallo 1). El primer envío gana: un reenvío
  -- del mismo id responde lo mismo sin buscar nada. Si guardar la llamada fallara, la recepción se revierte con
  -- ella: nada lo atrapa (Codex P1).
  insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en)
  values (v_origen, v_asig.id, p_ahora)
  on conflict (evento_origen_id) do nothing
  returning id into v_recepcion;
  if v_recepcion is null then
    return v_aceptado;
  end if;

  -- Solo salientes (decisión 2): la entrante y la dirección desconocida se ignoran (Codex P6).
  if v_dir <> 'saliente' then
    return v_aceptado;
  end if;

  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if v_ocurrio is not null and v_ocurrio > p_ahora + interval '5 minutes' then
    v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
  end if;
  v_formas := private.llamada_celular_formas(v_numero);
  v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
  if v_e164 is null and v_numero is not null then
    v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
  elsif v_numero is null then
    v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
  end if;
  v_cand := private.llamada_celular_candidatos_dueno(v_asig.analista_id, v_formas, p_ahora);

  if pg_catalog.cardinality(v_cand) = 1 then
    v_lead := v_cand[1];
    v_ident := 'identificado';
    v_metodo := 'exacto';
    -- Solo un lead del ámbito del dueño puede ser elegible; los de la bolsa y los reutilizables quedan por revisar.
    v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
                   then 'requiere_resultado' else 'por_revisar' end;
  elsif pg_catalog.cardinality(v_cand) > 1 then
    -- Ambigua, sin guardar cuántos (fallo 4).
    v_ident := 'ambiguo';
    v_aten := 'por_revisar';
  elsif coalesce(v_pol.guardar_sin_identificar, false) then
    v_ident := 'sin_identificar';
    v_aten := 'por_revisar';
  else
    -- Decisión 3: sin candidato, la llamada no pertenece al CRM, aunque el número sea de un lead de otro analista.
    return v_aceptado;
  end if;

  -- F4-a: el lead se bloquea ANTES de guardar la llamada, el orden de la v5 (lead → llamada → enlace): un aviso que
  -- llega mientras se guarda la encuesta de esa llamada espera y encuentra su intención.
  if v_lead is not null then
    perform 1 from crm.leads l where l.id = v_lead for share;
  end if;
  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion, estado_tecnico, duracion_seg,
     ocurrio_en, recibido_en, calidad, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
  values
    -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
    -- volver a buscar candidatos al asociar.
    (v_asig.id, v_asig.analista_id, v_origen, coalesce(v_e164, v_formas[1]), v_dir, v_estado, v_dur,
     v_ocurrio, p_ahora, v_calidad, v_ident, v_aten, v_lead, v_metodo, case when v_lead is not null then p_ahora end)
  returning id into v_evento;
  -- F4-a: si la encuesta llegó antes, la llamada se une ya a su resultado.
  perform private.llamada_celular_cumplir_intencion(v_evento);
  return v_aceptado;
end;
$function$;

-- La purga: el cuerpo de 20261005143843 con un cambio (intenciones de más de 32 días).
create or replace function private.caducar_llamadas_celular()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_pol crm.llamadas_celular_politica%rowtype;
  v_n integer := 0;
  v_parcial integer;
begin
  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if not found then
    return 0;
  end if;
  perform pg_catalog.set_config('crm.op_purga_llamadas', 'on', true);

  -- Descartadas con motivo: su plazo, desde descartado_en. El motivo y quién lo dio quedan en la auditoría.
  delete from crm.llamadas_celular_eventos e
   where e.atencion = 'descartado_con_motivo'
     and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin resolver: identificadas sin enlace y ambiguas, desde recibido_en. La atención también se mira: si una
  -- encuesta enlaza la llamada mientras la purga espera su candado, la fila vuelve con «registrado» y se queda.
  delete from crm.llamadas_celular_eventos e
   where e.identificacion in ('identificado', 'ambiguo')
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
  delete from crm.llamadas_celular_eventos e
   where e.identificacion = 'sin_identificar'
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Recepciones: 32 días (30 de ventana + 1 de tolerancia + 1 de margen). Pasado ese plazo, su id ya no entra
  -- por la ventana, así que no queda un registro eterno de a qué hora llamaba el analista (Codex P9).
  delete from private.llamadas_celular_recepciones r
   where r.recibido_en < pg_catalog.now() - interval '32 days';
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- F4-a: intenciones de enlace cuyo aviso nunca llegó (32 días, como las recepciones).
  delete from private.llamadas_celular_intenciones i
   where i.creado_en < pg_catalog.now() - interval '32 days';
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
  return v_n;
end;
$function$;

-- ── 4. Puerta v5 (DEFINER, EXECUTE solo authenticated) ───────────────────────────────────────
create function crm.registrar_llamada_v5(
  p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text default null, p_detalle text default null,
  p_siguiente jsonb default null, p_tarea_id uuid default null, p_descartar boolean default false,
  p_no_insista boolean default false, p_evento_origen_id text default null, p_via text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_resp jsonb;
begin
  -- Mismos roles que la v4; el ámbito lo decide su núcleo.
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  if p_operacion_id is null or p_lead_id is null or p_resultado is null then
    raise exception using errcode = '22023', message = 'Operacion, lead y resultado son obligatorios';
  end if;
  if p_evento_origen_id is not null and (p_via is null or p_via not in ('al_colgar', 'pestana')) then
    raise exception using errcode = '22023', message = 'Con el id de la llamada, la vía es al_colgar o pestana';
  end if;
  v_resp := private.llamada_registrar_v4(
    v_uid, p_operacion_id, p_lead_id, p_resultado, p_submotivo,
    nullif(pg_catalog.btrim(coalesce(p_detalle, '')), ''),
    p_siguiente, p_tarea_id, coalesce(p_descartar, false), coalesce(p_no_insista, false));
  if p_evento_origen_id is null then
    return v_resp || pg_catalog.jsonb_build_object('enlace', null);
  end if;
  return v_resp || pg_catalog.jsonb_build_object('enlace', private.llamada_celular_enlazar_exacto(
    v_uid, p_lead_id, (v_resp ->> 'actividad_id')::uuid, p_evento_origen_id, p_via, pg_catalog.clock_timestamp()));
end;
$function$;

-- ── 5. Permisos ──────────────────────────────────────────────────────────────────────────────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.trg_llamadas_celular_intenciones_candado()',
    'private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)',
    'private.llamada_celular_cumplir_intencion(uuid)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
  revoke all on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)
    from public, anon, authenticated, service_role;
  grant execute on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)
    to authenticated;
end;
$permisos$;

-- ── 6. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on table private.llamadas_celular_intenciones is
  'Intención de enlace (F4-a): la encuesta se guardó con el id de su llamada ANTES de que llegara el aviso del celular. La ingesta la cumple al llegar el aviso (crea el enlace con su vía) y la retira, se cumpla o no. Única por id y por resultado; caduca a los 32 días (la purga diaria) si el aviso nunca llega. Tabla técnica de private, sin acceso para la API y sin auditoría: transitoria, sin número ni datos personales. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.llamadas_celular_intenciones.id is 'Identificador de la intención.';
comment on column private.llamadas_celular_intenciones.evento_origen_id is 'Id de la llamada que llegó en la URL de la encuesta: C<n>-<segundos del reloj del celular>. Único.';
comment on column private.llamadas_celular_intenciones.analista_id is 'Quién registró el resultado: tiene que ser el analista del celular de la llamada para cumplirse. FK con RESTRICT.';
comment on column private.llamadas_celular_intenciones.lead_id is 'Lead del resultado: la llamada tiene que quedar identificada con este lead para cumplirse. Se va con el lead.';
comment on column private.llamadas_celular_intenciones.actividad_id is 'Resultado registrado por la encuesta (único). Cambia solo si se deshizo y se registró el corregido. Se va con la actividad.';
comment on column private.llamadas_celular_intenciones.via is 'Por dónde se abrió la encuesta: al_colgar (la URL de la macro) o pestana (la pestaña «Llamadas del celular»). Pasa al enlace.';
comment on column private.llamadas_celular_intenciones.creado_en is 'Cuándo se guardó la encuesta. De aquí corren los 32 días.';
comment on column private.llamadas_celular_intenciones.actualizado_en is 'Último cambio (solo al pasar al resultado corregido; lo sella el trigger).';
comment on column crm.llamadas_celular_enlaces.via is 'Por dónde se hizo el enlace: al_colgar (encuesta abierta por la URL de la macro), pestana (desde «Llamadas del celular») o manual (crm.enlazar_llamada_celular). Mide «encuesta abierta al colgar» por celular. Inmutable.';
comment on function private.trg_llamadas_celular_intenciones_candado() is
  'Candado de private.llamadas_celular_intenciones: solo cambia el resultado, y solo si el anterior se deshizo; DELETE solo al cumplirse (GUC crm.op_enlace_llamadas), en la purga (GUC crm.op_purga_llamadas) o en cascada. SECURITY DEFINER por coherencia con los demás candados; lee la actividad anterior.';
comment on function private.trg_llamadas_celular_enlaces_candado() is
  'Candado de crm.llamadas_celular_enlaces: nace con actividad; la actividad es de llamada, con metadata.evento = resultado_llamada y del mismo lead que la llamada; el enlace cambia de actividad solo si la anterior fue deshecha (metadata.deshecho_en); la vía no cambia (20261005155914); sin DELETE salvo cascada. SECURITY DEFINER porque lee crm.actividades y crm.llamadas_celular_eventos sin privilegios para la API.';
comment on function private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz) is
  'Enlace EXACTO (F4-a) de un resultado recién registrado por la v5 con la llamada de su id: id con forma y ventana de un celular del analista; llamada ya llegada, del mismo analista, identificada con ese lead → enlace (o lo mueve si el anterior se deshizo); no llegada → intención de enlace (o la mueve); sin la regla de los 10 minutos. Nunca lanza por un enlace imposible: {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}. Candados: lead (ya bloqueado por la v4) → llamada → enlace o intención.';
comment on function private.llamada_celular_cumplir_intencion(uuid) is
  'La ingesta, guardada una llamada, cumple la intención de su id: la retira y, si coincide (mismo analista, llamada identificada con ese lead, resultado vigente y sin otra llamada), crea el enlace con su vía y deja la llamada en «registrado». Lee el resultado sin candado (Deshacer toma resultado → lead).';
comment on function private.llamada_celular_ingerir(uuid,jsonb,timestamptz) is
  'Núcleo de la ingesta (lo llama crm.ingerir_llamada_celular_servicio tras la clave y el cupo, con la hora de la puerta): valida el evento v1 en un bloque que atrapa SOLO 22023 (inválido → {resultado: invalido, mensaje}); id C<n>-<segundos> con la etiqueta de la asignación y dentro de la ventana (30 días atrás, 1 adelante); registra la recepción antes de mirar leads (repetido → aceptado sin buscar nada); solo salientes; candidatos del dueño (uno → identificada, pide resultado si es elegible como el dueño; varios → ambigua sin conteo; ninguno → no se guarda salvo guardar_sin_identificar). Recepción y llamada confirman juntas. Siempre {resultado: aceptado} si es válido. DATO PERSONAL: el número. Desde 20261005155914 bloquea el lead antes de guardar la llamada y cumple la intención de enlace de su id (F4-a).';
comment on function private.caducar_llamadas_celular() is
  'Retención de llamadas del celular (decisión 4 de Miguel, 03/10): descartadas por su plazo desde descartado_en; identificadas sin enlace y ambiguas a dias_retencion_sin_resolver desde recibido_en; sin identificar a dias_retencion_sin_identificar; las registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones a los 32 días. Devuelve cuántas filas retiró (llamadas y recepciones). Fija el GUC crm.op_purga_llamadas para pasar los candados. La invoca pg_cron (crm-llamadas-celular-caducidad). SECURITY DEFINER: borra sin privilegios de la API. Desde 20261005155914 retira también las intenciones de enlace de más de 32 días.';
comment on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text) is
  'PUERTA v5 (F4-a): la operación de la v4 (su núcleo sellado private.llamada_registrar_v4: rol, ámbito, candado del lead, resultado, agenda y recibo) y, en la misma transacción, el enlace exacto con la llamada de p_evento_origen_id (vía al_colgar o pestana). Sin id, igual que la v4 con enlace null. Un enlace imposible no impide guardar el resultado: devuelve enlace.estado = no_enlazado con su motivo. DEFINER para componer el núcleo privado, no para ampliar el ámbito.';

-- ── 7. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
  v_t text := 'private.llamadas_celular_intenciones';
begin
  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó sin RLS', v_t;
  end if;
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
             where pg_catalog.has_table_privilege(r.rol, v_t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó accesible desde la API', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: % no debe tener policies (todo va por puertas)', v_t;
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = v_t::regclass and not t.tgisinternal and t.tgenabled in ('O', 'A')
        and t.tgname in ('trg_llamadas_celular_intenciones_00_candado', 'trg_llamadas_celular_intenciones_00_sin_vaciar')) <> 2 then
    raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó sin sus candados', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f' and c.conrelid = v_t::regclass
               and c.confrelid in ('public.perfiles'::regclass, 'crm.equipo'::regclass) and c.confdeltype <> 'r') then
    raise exception 'LLAMADAS_ENLACE_EXACTO: una FK hacia personas de % no es RESTRICT', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f' and c.conrelid = v_t::regclass
               and not exists (select 1 from pg_catalog.pg_index i
                               where i.indrelid = c.conrelid
                                 and (pg_catalog.string_to_array(i.indkey::text, ' ')::smallint[])[1:pg_catalog.array_length(c.conkey, 1)]
                                     = c.conkey)) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: hay una FK de % sin índice que la cubra', v_t;
  end if;
  if pg_catalog.obj_description(v_t::regclass, 'pg_class') is null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attnum > 0 and not a.attisdropped and pg_catalog.col_description(a.attrelid, a.attnum) is null
                  and (a.attrelid = v_t::regclass
                       or (a.attrelid = 'crm.llamadas_celular_enlaces'::regclass and a.attname = 'via'))) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: falta COMMENT en las intenciones o en la vía del enlace';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.llamadas_celular_enlaces'::regclass and not t.tgisinternal) <> 3
     or exists (select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.llamadas_celular_enlaces') then
    raise exception 'LLAMADAS_ENLACE_EXACTO: los enlaces perdieron un trigger o su rastro de auditoría';
  end if;

  for v_f in
    select * from (values
      ('private.trg_llamadas_celular_intenciones_candado()', true, null),
      ('private.trg_llamadas_celular_enlaces_candado()', true, null),
      ('private.caducar_llamadas_celular()', true, null),
      ('private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)', false, null),
      ('private.llamada_celular_cumplir_intencion(uuid)', false, null),
      ('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)', false, null),
      ('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_ENLACE_EXACTO: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_ENLACE_EXACTO: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_ENLACE_EXACTO: search_path inesperado en %', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_ENLACE_EXACTO: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_ENLACE_EXACTO: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'::regprocedure),
                       'private.llamada_celular_cumplir_intencion(') = 0 then
    raise exception 'LLAMADAS_ENLACE_EXACTO: la ingesta no cumple las intenciones de enlace';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)'::regprocedure),
                       'private.llamada_registrar_v4(') = 0 then
    raise exception 'LLAMADAS_ENLACE_EXACTO: la v5 no compone el núcleo sellado de la v4';
  end if;
  -- La v4 sigue sellada (si su gate existe): la v5 no la tocó.
  if to_regprocedure('private.assert_gestion_diaria_resultado_v4()') is not null then
    perform private.assert_gestion_diaria_resultado_v4();
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261005155914 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261005155914', 'crm_llamadas_celular_enlace_exacto', array[$mig$-- Llamadas desde el celular · F4-a: ENLACE EXACTO encuesta ↔ llamada (sexta migración; se publica JUNTO con las cinco
-- de F2 + F3, decisión 1 de Miguel del 03/10). Plan: CORRECCION-PLAN-CORTO.md §7 (v2, PR #179) y F4-PLAN-CORTO.md §1.
-- Cierra el fallo 5 de la revisión del 02/10 (nada unía la encuesta con su llamada) del lado de la base; la pantalla
-- que lleva el id hasta la encuesta y llama a la v5 es F4-b.
--
-- Qué hace (sobre 20261005143843; no toca la v4 sellada):
--   1. crm.registrar_llamada_v5: la misma operación que la v4 (llama a su núcleo sellado private.llamada_registrar_v4,
--      que bloquea el lead y crea el resultado) y, en la MISMA transacción, une ese resultado a la llamada por su id
--      exacto (C<n>-<segundos>, el que la macro pone en la URL al colgar):
--        · si la llamada ya llegó (del celular del mismo analista, identificada con ese lead) → el enlace;
--        · si todavía no llegó → una intención de enlace, que la ingesta cumple sola al llegar el aviso;
--        · si no se puede unir (id mal formado, celular ajeno, otro lead, descartada, ya tenía otro resultado no
--          deshecho) → el resultado se guarda IGUAL y la respuesta dice «no_enlazado» y por qué: la llamada queda en
--          la pestaña para unirla a mano (decisión de Jhosep, 05/10).
--      Sin la regla de los 10 minutos: en el camino exacto un reloj adelantado no rechaza nada (confirmación 3 de
--      Miguel, Codex P2-5). Al registrar el resultado corregido tras Deshacer, el enlace (o la intención) pasa al
--      corregido (confirmación 2). Una llamada ambigua no se une por este camino: va a la pestaña (Jhosep, 05/10).
--   2. private.llamadas_celular_intenciones: la intención de enlace por id. Única por id y por resultado; caduca a los
--      32 días (si el aviso nunca llega). Tabla técnica de private, sin auditoría (como las recepciones).
--   3. crm.llamadas_celular_enlaces.via: al_colgar, pestana o manual. Sin ella no se mide «encuesta abierta al colgar»
--      por celular, el objetivo de Jhosep. Inmutable.
--   4. La ingesta (cuerpo de 20261005143843 con dos cambios): bloquea el lead FOR SHARE antes de guardar la llamada (el
--      orden lead → llamada → enlace de la v5) y, guardada, cumple la intención si la hay.
--   5. La purga (cuerpo de 20261005143843 con un cambio): retira las intenciones de más de 32 días.
--
-- Candados: v5 = lead (núcleo de v4, FOR UPDATE) → llamada → enlace o intención; ingesta = lead FOR SHARE → llamada →
-- intención → enlace. Los dos empiezan por el lead: un aviso que llega mientras se guarda la encuesta espera, y la
-- encuesta que llega mientras se guarda el aviso también; ninguno pierde el enlace. La ingesta lee el resultado sin
-- candado: Deshacer toma resultado → lead, y bloquearlo después del lead invertiría ese orden.
--
-- Decisiones de criterio de Claude (05/10/2026), para Miguel:
--   · La intención va en private, sin auditoría: es transitoria y no guarda datos personales (id, lead, resultado).
--   · via nace con valor por defecto «manual»: el enlace manual (crm.enlazar_llamada_celular) no cambia; la v5 y la
--     intención la fijan siempre.
--   · La v5 exige que la etiqueta del id sea de un celular del analista que registra (vigente, o cerrado después de
--     la llamada). Un supervisor que registra por el lead de su analista no enlaza: la llamada queda en la pestaña.
--   · Si el aviso ya llegó y se ignoró (recepción sin llamada), no se guarda intención: nunca se cumpliría.
--   · «Qué pasó hoy» (la lectura de lo ya resuelto, hallazgo 1 de F4) pasa a F4-b, con la pantalla.
--
-- Excepción single-tenant (estándar de 4 capas, F2.3.3): el CRM es de una sola empresa; no hay columna de tenant.
-- Reversión: ../scripts/llamadas-celular/reversa-enlace-exacto.sql, SOLO antes del primer aviso (sin enlaces ni
-- intenciones): vuelve exactamente al estado de las cinco. Verificación: npm run test:llamadas:local (oráculo
-- tests/llamadas-celular/oraculo-enlace-exacto.sql, huella del catálogo, mutantes y carreras con dos sesiones).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('private.llamadas_celular_intenciones') is not null
     or to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is not null then
    raise exception 'LLAMADAS_ENLACE_EXACTO: los objetos ya existen; no se sobrescriben';
  end if;
  if to_regclass('private.llamadas_celular_recepciones') is null
     or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is null
     or to_regprocedure('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)') is null then
    raise exception 'LLAMADAS_ENLACE_EXACTO: falta la quinta migración (20261005143843)';
  end if;
  if to_regprocedure('private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)') is null then
    raise exception 'LLAMADAS_ENLACE_EXACTO: falta el núcleo de la encuesta v4 (20260921153654)';
  end if;
  -- La v5 compone la v4 SELLADA: si su gate existe (producción), tiene que pasar antes de instalar.
  if to_regprocedure('private.assert_gestion_diaria_resultado_v4()') is not null then
    perform private.assert_gestion_diaria_resultado_v4();
  end if;
end;
$precondicion$;

lock table crm.llamadas_celular_eventos, crm.llamadas_celular_enlaces in access exclusive mode;

-- ── 1. Intenciones de enlace (private, sin auditoría, 32 días) ───────────────────────────────
create table private.llamadas_celular_intenciones (
  id               uuid primary key default gen_random_uuid(),
  evento_origen_id text not null
                   constraint llamadas_celular_intenciones_origen_valido
                   check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$')
                   constraint llamadas_celular_intenciones_origen_uq unique,
  analista_id      uuid not null references crm.equipo(perfil_id) on delete restrict,
  lead_id          uuid not null references crm.leads(id) on delete cascade,
  actividad_id     uuid not null references crm.actividades(id) on delete cascade
                   constraint llamadas_celular_intenciones_actividad_uq unique,
  via              text not null
                   constraint llamadas_celular_intenciones_via_valida check (via in ('al_colgar', 'pestana')),
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);
alter table private.llamadas_celular_intenciones enable row level security;
revoke all on private.llamadas_celular_intenciones from public, anon, authenticated, service_role;
create index llamadas_celular_intenciones_analista_idx on private.llamadas_celular_intenciones (analista_id);
create index llamadas_celular_intenciones_lead_idx on private.llamadas_celular_intenciones (lead_id);
create index llamadas_celular_intenciones_creado_idx on private.llamadas_celular_intenciones (creado_en);

create function private.trg_llamadas_celular_intenciones_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_deshecha boolean;
begin
  if tg_op = 'DELETE' then
    -- La cumple la ingesta (GUC de enlace), la retira la purga (su GUC) o se va con su lead o su resultado (cascada).
    if coalesce(pg_catalog.current_setting('crm.op_enlace_llamadas', true), 'off') = 'on'
       or coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'
       or pg_catalog.pg_trigger_depth() > 1 then
      return old;
    end if;
    raise exception using errcode = '42501', message = 'Una intención de enlace no se borra a mano';
  end if;
  if new.id <> old.id or new.evento_origen_id <> old.evento_origen_id or new.analista_id <> old.analista_id
     or new.lead_id <> old.lead_id or new.via <> old.via or new.creado_en <> old.creado_en then
    raise exception using errcode = '42501',
      message = 'De una intención de enlace solo cambia el resultado, cuando el anterior se deshizo';
  end if;
  if new.actividad_id <> old.actividad_id then
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = old.actividad_id;
    if not coalesce(v_deshecha, false) then
      raise exception using errcode = '42501',
        message = 'La intención solo pasa a otro resultado si el anterior se deshizo';
    end if;
  end if;
  new.actualizado_en := pg_catalog.now();
  return new;
end;
$function$;
create trigger trg_llamadas_celular_intenciones_00_candado
  before update or delete on private.llamadas_celular_intenciones
  for each row execute function private.trg_llamadas_celular_intenciones_candado();
create trigger trg_llamadas_celular_intenciones_00_sin_vaciar
  before truncate on private.llamadas_celular_intenciones
  for each statement execute function private.trg_llamadas_celular_sin_vaciar();

-- ── 2. Vía del enlace (inmutable) ────────────────────────────────────────────────────────────
alter table crm.llamadas_celular_enlaces
  add column via text not null default 'manual'
    constraint llamadas_celular_enlaces_via_valida check (via in ('al_colgar', 'pestana', 'manual'));

-- Candado de los enlaces: el cuerpo de 20261001145242 con un cambio (la vía no cambia).
create or replace function private.trg_llamadas_celular_enlaces_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_act crm.actividades%rowtype;
  v_ev  crm.llamadas_celular_eventos%rowtype;
  v_deshecha boolean;
begin
  if tg_op = 'DELETE' then
    if pg_catalog.pg_trigger_depth() > 1 then
      return old; -- cascada: se fue el evento o el lead
    end if;
    raise exception using errcode = '42501', message = 'El enlace de una llamada no se borra';
  end if;

  if tg_op = 'UPDATE' then
    -- La actividad se eliminó (cascada del lead → ON DELETE SET NULL): única escritura anidada
    -- aceptada, y solo si no cambia nada más.
    if pg_catalog.pg_trigger_depth() > 1 and new.actividad_id is null and old.actividad_id is not null
       and (pg_catalog.to_jsonb(new) - 'actividad_id' - 'actualizado_en')
         = (pg_catalog.to_jsonb(old) - 'actividad_id' - 'actualizado_en') then
      new.actualizado_en := pg_catalog.now();
      return new;
    end if;
    if new.id <> old.id or new.evento_id <> old.evento_id or new.lead_id <> old.lead_id
       or new.creado_en <> old.creado_en or new.via <> old.via then
      raise exception using errcode = '42501', message = 'El enlace de una llamada no cambia de evento, de lead ni de vía';
    end if;
    if new.actividad_id is distinct from old.actividad_id then
      if new.actividad_id is null then
        raise exception using errcode = '42501', message = 'Un enlace no se desenlaza: el resultado deshecho se marca, no se borra';
      end if;
      if old.actividad_id is not null then
        select (a.metadata ? 'deshecho_en') into v_deshecha
        from crm.actividades a where a.id = old.actividad_id;
        if not coalesce(v_deshecha, false) then
          raise exception using errcode = '42501',
            message = 'El enlace solo cambia de actividad si el resultado anterior fue deshecho';
        end if;
      end if;
    end if;
  elsif new.actividad_id is null then
    raise exception using errcode = '22023', message = 'Un enlace nace con la actividad registrada';
  end if;

  if new.actividad_id is not null and (tg_op = 'INSERT' or new.actividad_id is distinct from old.actividad_id) then
    select * into v_act from crm.actividades a where a.id = new.actividad_id;
    if not found then
      raise exception using errcode = '22023', message = 'La actividad enlazada no existe';
    end if;
    if v_act.lead_id <> new.lead_id then
      raise exception using errcode = '22023', message = 'La actividad enlazada es de otro lead';
    end if;
    if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
       or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
      raise exception using errcode = '22023',
        message = 'Solo se enlaza un resultado de llamada registrado por la encuesta';
    end if;
  end if;

  select * into v_ev from crm.llamadas_celular_eventos e where e.id = new.evento_id;
  if not found then
    raise exception using errcode = '22023', message = 'La llamada enlazada no existe';
  end if;
  if v_ev.lead_id is distinct from new.lead_id then
    raise exception using errcode = '22023', message = 'El enlace debe apuntar al lead de la llamada';
  end if;

  if tg_op = 'UPDATE' then
    new.actualizado_en := pg_catalog.now();
  end if;
  return new;
end;
$function$;

-- ── 3. Núcleo del enlace exacto (INVOKER, sin EXECUTE para nadie) ────────────────────────────

-- Une un resultado que la v5 acaba de registrar (o reconfirmar) con la llamada de ese id. Nunca lanza por un enlace
-- imposible: devuelve {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}.
create function private.llamada_celular_enlazar_exacto(
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

  -- 2. El resultado: lo creó o reconfirmó la v4 en esta transacción, con el lead ya bloqueado.
  select * into v_act from crm.actividades a where a.id = p_actividad_id;
  if not found or v_act.lead_id <> p_lead_id or v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
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

-- La ingesta, guardada la llamada, cumple la intención de su id. La intención se retira se cumpla o no: si no
-- coincide (otro analista, otro lead, resultado deshecho o ya unido a otra llamada), la llamada queda pendiente.
create function private.llamada_celular_cumplir_intencion(p_evento_id uuid)
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
  -- Sin candado sobre el resultado: Deshacer lo toma ANTES que el lead, y aquí el lead ya está bloqueado.
  select * into v_act from crm.actividades a where a.id = v_int.actividad_id;
  if not found or v_act.metadata ? 'deshecho_en' then
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

-- La ingesta: el cuerpo de 20261005143843 con dos cambios (candado del lead antes de guardar; cumplir la intención).
create or replace function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb, p_ahora timestamptz)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_claves constant text[] := array['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico',
                                    'duracion_seg', 'ocurrio_en'];
  v_asig crm.celulares_asignaciones%rowtype;
  v_pol crm.llamadas_celular_politica%rowtype;
  v_origen text;
  v_numero text;
  v_dir text;
  v_estado text;
  v_dur integer;
  v_ocurrio timestamptz;
  v_hora_id timestamptz;
  v_recepcion uuid;
  v_formas text[];
  v_e164 text;
  v_cand uuid[];
  v_lead uuid;
  v_ident text;
  v_aten text;
  v_metodo text;
  v_calidad jsonb := '{}'::jsonb;
  v_aceptado constant jsonb := '{"resultado": "aceptado"}'::jsonb;
  v_evento uuid;
begin
  -- La puerta ya bloqueó la asignación FOR SHARE y la revalidó; aquí se relee bajo el mismo candado.
  select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
  if not found or v_asig.vigente_hasta is not null
     or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
  end if;

  -- Validación: todo inválido responde «invalido» y el cupo ya gastado queda (menor 11, Codex P3). El bloque
  -- atrapa SOLO 22023: un error inesperado sigue siendo un error (503, que revierte todo, el cupo incluido).
  begin
    if p_evento is null or pg_catalog.jsonb_typeof(p_evento) <> 'object' then
      raise exception using errcode = '22023', message = 'El evento debe ser un objeto JSON';
    end if;
    if exists (select 1 from pg_catalog.jsonb_object_keys(p_evento) k where k <> all(v_claves)) then
      raise exception using errcode = '22023', message = 'El evento trae claves no previstas';
    end if;
    if coalesce(p_evento ->> 'v', '') <> '1' then
      raise exception using errcode = '22023', message = 'Versión de evento no soportada (se espera v = 1)';
    end if;
    v_origen := p_evento ->> 'evento_origen_id';
    if v_origen is null or v_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id inválido: se espera la etiqueta del celular y los segundos de su reloj (p. ej. C1-1790980958)';
    end if;
    if pg_catalog.split_part(v_origen, '-', 1) <> v_asig.etiqueta then
      raise exception using errcode = '22023',
        message = pg_catalog.format('evento_origen_id con la etiqueta de otro celular (esta clave es de %s)', v_asig.etiqueta);
    end if;
    v_hora_id := pg_catalog.to_timestamp(pg_catalog.split_part(v_origen, '-', 2)::bigint);
    if v_hora_id < p_ahora - interval '30 days' or v_hora_id > p_ahora + interval '1 day' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id fuera de la ventana: su hora debe caer entre hace 30 días y mañana (¿hora automática en el celular?)';
    end if;
    v_numero := nullif(pg_catalog.btrim(coalesce(p_evento ->> 'numero', '')), '');
    if pg_catalog.length(v_numero) > 40 then
      raise exception using errcode = '22023', message = 'El número no puede pasar de 40 caracteres';
    end if;
    v_dir := coalesce(p_evento ->> 'direccion', 'desconocida');
    if v_dir not in ('saliente', 'entrante', 'desconocida') then
      raise exception using errcode = '22023', message = 'direccion inválida (saliente, entrante o desconocida)';
    end if;
    v_estado := coalesce(p_evento ->> 'estado_tecnico', 'desconocido');
    if v_estado not in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido') then
      raise exception using errcode = '22023', message = 'estado_tecnico inválido';
    end if;
    if coalesce(pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg'), 'null') <> 'null' then
      if pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg') <> 'number'
         or (p_evento ->> 'duracion_seg') !~ '^[0-9]{1,5}$' or (p_evento ->> 'duracion_seg')::integer > 86400 then
        raise exception using errcode = '22023', message = 'duracion_seg debe ser un entero de 0 a 86400';
      end if;
      v_dur := (p_evento ->> 'duracion_seg')::integer;
    end if;
    v_ocurrio := private.llamada_celular_fecha(p_evento ->> 'ocurrio_en');
  exception when sqlstate '22023' then
    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
  end;

  -- Recepción ANTES de mirar leads, también si después se ignora (fallo 1). El primer envío gana: un reenvío
  -- del mismo id responde lo mismo sin buscar nada. Si guardar la llamada fallara, la recepción se revierte con
  -- ella: nada lo atrapa (Codex P1).
  insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en)
  values (v_origen, v_asig.id, p_ahora)
  on conflict (evento_origen_id) do nothing
  returning id into v_recepcion;
  if v_recepcion is null then
    return v_aceptado;
  end if;

  -- Solo salientes (decisión 2): la entrante y la dirección desconocida se ignoran (Codex P6).
  if v_dir <> 'saliente' then
    return v_aceptado;
  end if;

  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if v_ocurrio is not null and v_ocurrio > p_ahora + interval '5 minutes' then
    v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
  end if;
  v_formas := private.llamada_celular_formas(v_numero);
  v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
  if v_e164 is null and v_numero is not null then
    v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
  elsif v_numero is null then
    v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
  end if;
  v_cand := private.llamada_celular_candidatos_dueno(v_asig.analista_id, v_formas, p_ahora);

  if pg_catalog.cardinality(v_cand) = 1 then
    v_lead := v_cand[1];
    v_ident := 'identificado';
    v_metodo := 'exacto';
    -- Solo un lead del ámbito del dueño puede ser elegible; los de la bolsa y los reutilizables quedan por revisar.
    v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
                   then 'requiere_resultado' else 'por_revisar' end;
  elsif pg_catalog.cardinality(v_cand) > 1 then
    -- Ambigua, sin guardar cuántos (fallo 4).
    v_ident := 'ambiguo';
    v_aten := 'por_revisar';
  elsif coalesce(v_pol.guardar_sin_identificar, false) then
    v_ident := 'sin_identificar';
    v_aten := 'por_revisar';
  else
    -- Decisión 3: sin candidato, la llamada no pertenece al CRM, aunque el número sea de un lead de otro analista.
    return v_aceptado;
  end if;

  -- F4-a: el lead se bloquea ANTES de guardar la llamada, el orden de la v5 (lead → llamada → enlace): un aviso que
  -- llega mientras se guarda la encuesta de esa llamada espera y encuentra su intención.
  if v_lead is not null then
    perform 1 from crm.leads l where l.id = v_lead for share;
  end if;
  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion, estado_tecnico, duracion_seg,
     ocurrio_en, recibido_en, calidad, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
  values
    -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
    -- volver a buscar candidatos al asociar.
    (v_asig.id, v_asig.analista_id, v_origen, coalesce(v_e164, v_formas[1]), v_dir, v_estado, v_dur,
     v_ocurrio, p_ahora, v_calidad, v_ident, v_aten, v_lead, v_metodo, case when v_lead is not null then p_ahora end)
  returning id into v_evento;
  -- F4-a: si la encuesta llegó antes, la llamada se une ya a su resultado.
  perform private.llamada_celular_cumplir_intencion(v_evento);
  return v_aceptado;
end;
$function$;

-- La purga: el cuerpo de 20261005143843 con un cambio (intenciones de más de 32 días).
create or replace function private.caducar_llamadas_celular()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_pol crm.llamadas_celular_politica%rowtype;
  v_n integer := 0;
  v_parcial integer;
begin
  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if not found then
    return 0;
  end if;
  perform pg_catalog.set_config('crm.op_purga_llamadas', 'on', true);

  -- Descartadas con motivo: su plazo, desde descartado_en. El motivo y quién lo dio quedan en la auditoría.
  delete from crm.llamadas_celular_eventos e
   where e.atencion = 'descartado_con_motivo'
     and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin resolver: identificadas sin enlace y ambiguas, desde recibido_en. La atención también se mira: si una
  -- encuesta enlaza la llamada mientras la purga espera su candado, la fila vuelve con «registrado» y se queda.
  delete from crm.llamadas_celular_eventos e
   where e.identificacion in ('identificado', 'ambiguo')
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
  delete from crm.llamadas_celular_eventos e
   where e.identificacion = 'sin_identificar'
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Recepciones: 32 días (30 de ventana + 1 de tolerancia + 1 de margen). Pasado ese plazo, su id ya no entra
  -- por la ventana, así que no queda un registro eterno de a qué hora llamaba el analista (Codex P9).
  delete from private.llamadas_celular_recepciones r
   where r.recibido_en < pg_catalog.now() - interval '32 days';
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- F4-a: intenciones de enlace cuyo aviso nunca llegó (32 días, como las recepciones).
  delete from private.llamadas_celular_intenciones i
   where i.creado_en < pg_catalog.now() - interval '32 days';
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
  return v_n;
end;
$function$;

-- ── 4. Puerta v5 (DEFINER, EXECUTE solo authenticated) ───────────────────────────────────────
create function crm.registrar_llamada_v5(
  p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text default null, p_detalle text default null,
  p_siguiente jsonb default null, p_tarea_id uuid default null, p_descartar boolean default false,
  p_no_insista boolean default false, p_evento_origen_id text default null, p_via text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_resp jsonb;
begin
  -- Mismos roles que la v4; el ámbito lo decide su núcleo.
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  if p_operacion_id is null or p_lead_id is null or p_resultado is null then
    raise exception using errcode = '22023', message = 'Operacion, lead y resultado son obligatorios';
  end if;
  if p_evento_origen_id is not null and (p_via is null or p_via not in ('al_colgar', 'pestana')) then
    raise exception using errcode = '22023', message = 'Con el id de la llamada, la vía es al_colgar o pestana';
  end if;
  v_resp := private.llamada_registrar_v4(
    v_uid, p_operacion_id, p_lead_id, p_resultado, p_submotivo,
    nullif(pg_catalog.btrim(coalesce(p_detalle, '')), ''),
    p_siguiente, p_tarea_id, coalesce(p_descartar, false), coalesce(p_no_insista, false));
  if p_evento_origen_id is null then
    return v_resp || pg_catalog.jsonb_build_object('enlace', null);
  end if;
  return v_resp || pg_catalog.jsonb_build_object('enlace', private.llamada_celular_enlazar_exacto(
    v_uid, p_lead_id, (v_resp ->> 'actividad_id')::uuid, p_evento_origen_id, p_via, pg_catalog.clock_timestamp()));
end;
$function$;

-- ── 5. Permisos ──────────────────────────────────────────────────────────────────────────────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.trg_llamadas_celular_intenciones_candado()',
    'private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)',
    'private.llamada_celular_cumplir_intencion(uuid)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
  revoke all on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)
    from public, anon, authenticated, service_role;
  grant execute on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)
    to authenticated;
end;
$permisos$;

-- ── 6. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on table private.llamadas_celular_intenciones is
  'Intención de enlace (F4-a): la encuesta se guardó con el id de su llamada ANTES de que llegara el aviso del celular. La ingesta la cumple al llegar el aviso (crea el enlace con su vía) y la retira, se cumpla o no. Única por id y por resultado; caduca a los 32 días (la purga diaria) si el aviso nunca llega. Tabla técnica de private, sin acceso para la API y sin auditoría: transitoria, sin número ni datos personales. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.llamadas_celular_intenciones.id is 'Identificador de la intención.';
comment on column private.llamadas_celular_intenciones.evento_origen_id is 'Id de la llamada que llegó en la URL de la encuesta: C<n>-<segundos del reloj del celular>. Único.';
comment on column private.llamadas_celular_intenciones.analista_id is 'Quién registró el resultado: tiene que ser el analista del celular de la llamada para cumplirse. FK con RESTRICT.';
comment on column private.llamadas_celular_intenciones.lead_id is 'Lead del resultado: la llamada tiene que quedar identificada con este lead para cumplirse. Se va con el lead.';
comment on column private.llamadas_celular_intenciones.actividad_id is 'Resultado registrado por la encuesta (único). Cambia solo si se deshizo y se registró el corregido. Se va con la actividad.';
comment on column private.llamadas_celular_intenciones.via is 'Por dónde se abrió la encuesta: al_colgar (la URL de la macro) o pestana (la pestaña «Llamadas del celular»). Pasa al enlace.';
comment on column private.llamadas_celular_intenciones.creado_en is 'Cuándo se guardó la encuesta. De aquí corren los 32 días.';
comment on column private.llamadas_celular_intenciones.actualizado_en is 'Último cambio (solo al pasar al resultado corregido; lo sella el trigger).';
comment on column crm.llamadas_celular_enlaces.via is 'Por dónde se hizo el enlace: al_colgar (encuesta abierta por la URL de la macro), pestana (desde «Llamadas del celular») o manual (crm.enlazar_llamada_celular). Mide «encuesta abierta al colgar» por celular. Inmutable.';
comment on function private.trg_llamadas_celular_intenciones_candado() is
  'Candado de private.llamadas_celular_intenciones: solo cambia el resultado, y solo si el anterior se deshizo; DELETE solo al cumplirse (GUC crm.op_enlace_llamadas), en la purga (GUC crm.op_purga_llamadas) o en cascada. SECURITY DEFINER por coherencia con los demás candados; lee la actividad anterior.';
comment on function private.trg_llamadas_celular_enlaces_candado() is
  'Candado de crm.llamadas_celular_enlaces: nace con actividad; la actividad es de llamada, con metadata.evento = resultado_llamada y del mismo lead que la llamada; el enlace cambia de actividad solo si la anterior fue deshecha (metadata.deshecho_en); la vía no cambia (20261005155914); sin DELETE salvo cascada. SECURITY DEFINER porque lee crm.actividades y crm.llamadas_celular_eventos sin privilegios para la API.';
comment on function private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz) is
  'Enlace EXACTO (F4-a) de un resultado recién registrado por la v5 con la llamada de su id: id con forma y ventana de un celular del analista; llamada ya llegada, del mismo analista, identificada con ese lead → enlace (o lo mueve si el anterior se deshizo); no llegada → intención de enlace (o la mueve); sin la regla de los 10 minutos. Nunca lanza por un enlace imposible: {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}. Candados: lead (ya bloqueado por la v4) → llamada → enlace o intención.';
comment on function private.llamada_celular_cumplir_intencion(uuid) is
  'La ingesta, guardada una llamada, cumple la intención de su id: la retira y, si coincide (mismo analista, llamada identificada con ese lead, resultado vigente y sin otra llamada), crea el enlace con su vía y deja la llamada en «registrado». Lee el resultado sin candado (Deshacer toma resultado → lead).';
comment on function private.llamada_celular_ingerir(uuid,jsonb,timestamptz) is
  'Núcleo de la ingesta (lo llama crm.ingerir_llamada_celular_servicio tras la clave y el cupo, con la hora de la puerta): valida el evento v1 en un bloque que atrapa SOLO 22023 (inválido → {resultado: invalido, mensaje}); id C<n>-<segundos> con la etiqueta de la asignación y dentro de la ventana (30 días atrás, 1 adelante); registra la recepción antes de mirar leads (repetido → aceptado sin buscar nada); solo salientes; candidatos del dueño (uno → identificada, pide resultado si es elegible como el dueño; varios → ambigua sin conteo; ninguno → no se guarda salvo guardar_sin_identificar). Recepción y llamada confirman juntas. Siempre {resultado: aceptado} si es válido. DATO PERSONAL: el número. Desde 20261005155914 bloquea el lead antes de guardar la llamada y cumple la intención de enlace de su id (F4-a).';
comment on function private.caducar_llamadas_celular() is
  'Retención de llamadas del celular (decisión 4 de Miguel, 03/10): descartadas por su plazo desde descartado_en; identificadas sin enlace y ambiguas a dias_retencion_sin_resolver desde recibido_en; sin identificar a dias_retencion_sin_identificar; las registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones a los 32 días. Devuelve cuántas filas retiró (llamadas y recepciones). Fija el GUC crm.op_purga_llamadas para pasar los candados. La invoca pg_cron (crm-llamadas-celular-caducidad). SECURITY DEFINER: borra sin privilegios de la API. Desde 20261005155914 retira también las intenciones de enlace de más de 32 días.';
comment on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text) is
  'PUERTA v5 (F4-a): la operación de la v4 (su núcleo sellado private.llamada_registrar_v4: rol, ámbito, candado del lead, resultado, agenda y recibo) y, en la misma transacción, el enlace exacto con la llamada de p_evento_origen_id (vía al_colgar o pestana). Sin id, igual que la v4 con enlace null. Un enlace imposible no impide guardar el resultado: devuelve enlace.estado = no_enlazado con su motivo. DEFINER para componer el núcleo privado, no para ampliar el ámbito.';

-- ── 7. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
  v_t text := 'private.llamadas_celular_intenciones';
begin
  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó sin RLS', v_t;
  end if;
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
             where pg_catalog.has_table_privilege(r.rol, v_t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó accesible desde la API', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: % no debe tener policies (todo va por puertas)', v_t;
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = v_t::regclass and not t.tgisinternal and t.tgenabled in ('O', 'A')
        and t.tgname in ('trg_llamadas_celular_intenciones_00_candado', 'trg_llamadas_celular_intenciones_00_sin_vaciar')) <> 2 then
    raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó sin sus candados', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f' and c.conrelid = v_t::regclass
               and c.confrelid in ('public.perfiles'::regclass, 'crm.equipo'::regclass) and c.confdeltype <> 'r') then
    raise exception 'LLAMADAS_ENLACE_EXACTO: una FK hacia personas de % no es RESTRICT', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f' and c.conrelid = v_t::regclass
               and not exists (select 1 from pg_catalog.pg_index i
                               where i.indrelid = c.conrelid
                                 and (pg_catalog.string_to_array(i.indkey::text, ' ')::smallint[])[1:pg_catalog.array_length(c.conkey, 1)]
                                     = c.conkey)) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: hay una FK de % sin índice que la cubra', v_t;
  end if;
  if pg_catalog.obj_description(v_t::regclass, 'pg_class') is null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attnum > 0 and not a.attisdropped and pg_catalog.col_description(a.attrelid, a.attnum) is null
                  and (a.attrelid = v_t::regclass
                       or (a.attrelid = 'crm.llamadas_celular_enlaces'::regclass and a.attname = 'via'))) then
    raise exception 'LLAMADAS_ENLACE_EXACTO: falta COMMENT en las intenciones o en la vía del enlace';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.llamadas_celular_enlaces'::regclass and not t.tgisinternal) <> 3
     or exists (select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.llamadas_celular_enlaces') then
    raise exception 'LLAMADAS_ENLACE_EXACTO: los enlaces perdieron un trigger o su rastro de auditoría';
  end if;

  for v_f in
    select * from (values
      ('private.trg_llamadas_celular_intenciones_candado()', true, null),
      ('private.trg_llamadas_celular_enlaces_candado()', true, null),
      ('private.caducar_llamadas_celular()', true, null),
      ('private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)', false, null),
      ('private.llamada_celular_cumplir_intencion(uuid)', false, null),
      ('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)', false, null),
      ('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_ENLACE_EXACTO: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_ENLACE_EXACTO: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_ENLACE_EXACTO: search_path inesperado en %', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_ENLACE_EXACTO: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_ENLACE_EXACTO: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'::regprocedure),
                       'private.llamada_celular_cumplir_intencion(') = 0 then
    raise exception 'LLAMADAS_ENLACE_EXACTO: la ingesta no cumple las intenciones de enlace';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)'::regprocedure),
                       'private.llamada_registrar_v4(') = 0 then
    raise exception 'LLAMADAS_ENLACE_EXACTO: la v5 no compone el núcleo sellado de la v4';
  end if;
  -- La v4 sigue sellada (si su gate existe): la v5 no la tocó.
  if to_regprocedure('private.assert_gestion_diaria_resultado_v4()') is not null then
    perform private.assert_gestion_diaria_resultado_v4();
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261005155914' and name = 'crm_llamadas_celular_enlace_exacto' and cardinality(statements) = 1
                   and md5(statements[1]) = '69d2137ecf345dda3e8be66b3d6b44fb') then
    raise exception 'REGISTRO: la fila 20261005155914 / crm_llamadas_celular_enlace_exacto no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261005155914 / crm_llamadas_celular_enlace_exacto (1 sentencia: el archivo entero)';
end $post$;
commit;
select (select count(*) from supabase_migrations.schema_migrations
        where version = '20261005155914' and name = 'crm_llamadas_celular_enlace_exacto' and md5(statements[1]) = '69d2137ecf345dda3e8be66b3d6b44fb') = 1
       as veredicto_registro_20261005155914;
