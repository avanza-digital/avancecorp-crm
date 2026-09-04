-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — `no_contactar` por PERSONA (contrato §7.3)
-- ============================================================================
--
-- QUE: el veto «No contactar» se eleva al inversionista: bloquea a la PERSONA,
-- no solo un teléfono. Los leads vinculados lo HEREDAN. Levantarlo exige puerta
-- auditada de Gerencia con motivo. (Invariante #7 del contrato; meta #5 de F3.)
--
-- COMO (Codex #4 — evita el ciclo de locks con la fusión):
--   * Subida y bajada SOLO por RPC ORDENADA: identidad FOR UPDATE -> leads FOR
--     UPDATE (id asc). Nunca lead->identidad. Un trigger que propagara desde un
--     UPDATE directo iría lead->identidad y podría abrazarse con la fusión
--     (identidad->leads); por eso el trigger NO propaga: solo RECHAZA.
--   * Trigger de rechazo: un UPDATE directo de leads.no_contactar (authenticated
--     tiene GRANT por columna) se rechaza salvo bajo la válvula op_privilegiada,
--     que solo encienden las RPC. Monotonía garantizada: nadie baja el veto por
--     fuera de la puerta de Gerencia.
--   * Herencia al INSERT: un lead nuevo cuyo documento ya pertenece a una persona
--     vetada nace con no_contactar=true. Cierra el bypass de crm-importar-leads
--     (que inserta con service_role y no_contactar=false) en la capa de datos.
--   * Reparto, rescate y disponibilidad consultan el veto de la PERSONA con JOIN
--     directo a crm.inversionistas (migración 250000), sin helper por fila.
--
-- TODO detrás de la bandera resolver_en_puertas: APAGADA = los triggers no actúan
-- y las RPC actúan SOLO sobre el lead (como el UPDATE directo de hoy). Requiere F1.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_no_contactar_persona'));

do $guard$
begin
  if to_regclass('crm.inversionistas') is null
     or not exists (select 1 from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'F2 no_contactar: falta F1 (inversionistas o bandera)';
  end if;
end
$guard$;

-- (Sin helper por fila: las lecturas de 250000/260000 resuelven el veto de la
--  persona con JOIN directo a crm.inversionistas, set-based.)

-- ============================================================================
-- 2. RPC: MARCAR no contactar (cualquier rol CRM sobre un lead de su ámbito)
-- ============================================================================
create or replace function crm.marcar_no_contactar(
  p_lead_id uuid,
  p_motivo  text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
begin
  if v_uid is null or not coalesce(v_rol in ('vendedor','supervisor','gerencia'), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- ORDEN: identidad PRIMERO (sin bloquear el lead aún), luego leads.
  -- Con bandera APAGADA la RPC actúa solo sobre el lead (como el UPDATE directo de hoy).
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;

  select * into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (vendedor_id is null and asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;
  -- Revalidar tras esperar: si la identidad cambió (fusión/corrección), reintentar.
  if v_flag and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(no_contactar_en, pg_catalog.now()),
           no_contactar_por = coalesce(no_contactar_por, v_uid)
     where id = v_inv and no_contactar = false;
    -- Todos los leads de la persona heredan el veto (id asc = orden determinista).
    for v_lead in
      select * from crm.leads where inversionista_id = v_inv order by id for update
    loop
      if not v_lead.no_contactar then
        update crm.leads set no_contactar = true where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
  else
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    get diagnostics v_n = row_count;
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  -- tipo 'nota' (el CHECK de actividades no admite un tipo nuevo; el evento va en metadata).
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota',
          'Marcado como No contactar' || case when v_flag and v_inv is not null then ' (persona completa)' else '' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'marcar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', nullif(pg_catalog.btrim(coalesce(p_motivo,'')), '')),
          v_uid);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$$;
revoke all on function crm.marcar_no_contactar(uuid, text) from public, anon, service_role;
grant execute on function crm.marcar_no_contactar(uuid, text) to authenticated;

-- ============================================================================
-- 3. RPC: LEVANTAR no contactar (SOLO Gerencia, con motivo — puerta auditada)
-- ============================================================================
create or replace function crm.levantar_no_contactar(
  p_lead_id uuid,
  p_motivo  text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede levantar No contactar' using errcode = '42501';
  end if;
  if p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;

  -- ORDEN: identidad PRIMERO, luego leads.
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  if v_flag and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = false, no_contactar_en = null, no_contactar_por = null
     where id = v_inv and no_contactar = true;
    for v_lead in
      select * from crm.leads where inversionista_id = v_inv order by id for update
    loop
      if v_lead.no_contactar then
        update crm.leads set no_contactar = false where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
  else
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    get diagnostics v_n = row_count;
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota', 'Levantado No contactar por Gerencia',
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'levantar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', pg_catalog.btrim(p_motivo)),
          v_uid);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$$;
revoke all on function crm.levantar_no_contactar(uuid, text) from public, anon, service_role;
grant execute on function crm.levantar_no_contactar(uuid, text) to authenticated;

-- ============================================================================
-- 4. Trigger de RECHAZO: no_contactar solo cambia por la puerta (bajo válvula)
-- ============================================================================
create or replace function private.trg_leads_no_contactar_solo_puerta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;  -- bandera apagada: comportamiento de hoy
  end if;
  if new.no_contactar is distinct from old.no_contactar
     and coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') <> 'on' then
    raise exception 'No contactar se cambia solo por su puerta (marcar_no_contactar / levantar_no_contactar)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.trg_leads_no_contactar_solo_puerta() from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_000_no_contactar_puerta on crm.leads;
create trigger trg_leads_000_no_contactar_puerta
  before update of no_contactar on crm.leads
  for each row execute function private.trg_leads_no_contactar_solo_puerta();

-- ============================================================================
-- 5. Trigger de HERENCIA al INSERT: un lead nuevo de una persona vetada nace vetado
-- ============================================================================
create or replace function private.trg_leads_hereda_veto_persona()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_veto boolean;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  if new.no_contactar then
    return new;
  end if;
  -- Solo el documento exacto vincula (contrato #8). Lectura sin lock: no cambia
  -- el orden de locks (es un SELECT), no hay ciclo posible. Se NORMALIZA igual
  -- que el resolver (este trigger corre ANTES de que disponibilidad haga btrim).
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 digitos (lo exige el trigger de
  -- alta; contrato §18: CE/pasaporte se resuelven al convertir).
  if new.dni is not null then
    select i.no_contactar into v_veto
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(new.dni,''), '[^A-Za-z0-9]', '', 'g'))
      and idf.estado = 'vigente'
      and i.estado <> 'fusionado'
    limit 1;
    if coalesce(v_veto, false) then
      new.no_contactar := true;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.trg_leads_hereda_veto_persona() from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_000_hereda_veto on crm.leads;
create trigger trg_leads_000_hereda_veto
  before insert on crm.leads
  for each row execute function private.trg_leads_hereda_veto_persona();

-- ============================================================================
-- 6. Postflight
-- ============================================================================
do $post$
begin
  if to_regprocedure('crm.marcar_no_contactar(uuid,text)') is null
     or to_regprocedure('crm.levantar_no_contactar(uuid,text)') is null then
    raise exception 'POSTFLIGHT no_contactar: falta alguna función';
  end if;
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                 where t.tgname='trg_leads_000_no_contactar_puerta' and c.relname='leads'
                   and c.relnamespace='crm'::regnamespace and not t.tgisinternal)
     or not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                 where t.tgname='trg_leads_000_hereda_veto' and c.relname='leads'
                   and c.relnamespace='crm'::regnamespace and not t.tgisinternal) then
    raise exception 'POSTFLIGHT no_contactar: falta algún trigger';
  end if;
  if has_function_privilege('anon','crm.marcar_no_contactar(uuid,text)','EXECUTE')
     or has_function_privilege('anon','crm.levantar_no_contactar(uuid,text)','EXECUTE') then
    raise exception 'POSTFLIGHT no_contactar: grants abiertos de más';
  end if;
  raise notice 'F2 no_contactar OK: RPC ordenadas (identidad->leads), rechazo directo y herencia al insert (tras bandera).';
end
$post$;

commit;
