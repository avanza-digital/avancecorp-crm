-- Mantenimiento administrativo F4: aplicar exclusivamente un censo concreto.
-- Requiere 07-historicos.sql. Instalar no aplica ningún lote ni enciende banderas.
create table crm.inversion_backfill_lotes (
  id uuid primary key,
  hash_mapa text not null check (hash_mapa ~ '^[a-f0-9]{64}$'),
  mapa jsonb not null check (jsonb_typeof(mapa)='array'),
  resultado jsonb,
  operador name not null default session_user,
  creado_xid xid8 not null default pg_current_xact_id(),
  creado_en timestamptz not null default statement_timestamp(),
  finalizado_en timestamptz,
  check ((resultado is null)=(finalizado_en is null)),
  check (resultado is null or jsonb_typeof(resultado)='object')
);
comment on table crm.inversion_backfill_lotes is
  'Lotes acotados de vinculación histórica F4: mapa previo, huellas y resultado. No copia dinero ni documentos. Un lote completo es inmutable y no amplía permisos de usuario.';
alter table crm.inversion_backfill_lotes enable row level security;
revoke all on crm.inversion_backfill_lotes from public,anon,authenticated,service_role;
create trigger trg_audit_inversion_backfill_lotes after insert or update on crm.inversion_backfill_lotes
  for each row execute function private.log_audit_sin_secretos('mapa','resultado');

create or replace function private.f4_proteger_lote_historico()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if tg_when='AFTER' then
    if exists (select 1 from crm.inversion_backfill_lotes l where l.id=new.id and l.finalizado_en is null) then
      raise exception 'Un lote histórico no puede quedar incompleto' using errcode='23514';
    end if;
    return null;
  end if;
  if tg_op='DELETE' or old.finalizado_en is not null
     or old.creado_xid<>pg_current_xact_id() then
    raise exception 'El acta histórica se conserva íntegra' using errcode='P0409';
  end if;
  if (to_jsonb(new)-array['resultado','finalizado_en'])
       is distinct from (to_jsonb(old)-array['resultado','finalizado_en'])
     or new.finalizado_en is null or new.resultado is null then
    raise exception 'Solo puede concluirse el lote de esta transacción' using errcode='P0409';
  end if;
  return new;
end;
$$;
revoke all on function private.f4_proteger_lote_historico() from public,anon,authenticated,service_role;
create trigger trg_inversion_backfill_inmutable before update or delete on crm.inversion_backfill_lotes
  for each row execute function private.f4_proteger_lote_historico();
create constraint trigger trg_inversion_backfill_completo after insert or update on crm.inversion_backfill_lotes
  deferrable initially deferred for each row execute function private.f4_proteger_lote_historico();

create or replace function private.inversion_historica_aplicar(p_lote uuid,p_mapa jsonb)
returns jsonb language plpgsql security invoker set search_path='' set lock_timeout='5s' as $$
declare
  v_mapa jsonb;
  v_hash text;
  v_previo crm.inversion_backfill_lotes%rowtype;
  v_r record;
  v_actual jsonb;
  v_final jsonb;
  v_inversion uuid;
  v_resultado jsonb;
  v_filas jsonb := '[]';
  v_n integer;
  v_personas uuid[];
  v_perfiles uuid[];
  v_leads uuid[];
  v_contratos uuid[];
  v_cierres uuid[];
  v_inversiones uuid[];
  v_old_priv text := current_setting('crm.op_privilegiada',true);
begin
  -- Mantenimiento por conexión administrativa, nunca una puerta HTTP ni una
  -- delegación implícita de service_role. INVOKER mantiene los privilegios reales.
  if session_user not in ('postgres','supabase_admin') or current_user<>'postgres' then
    raise exception 'La vinculación histórica exige una sesión administrativa' using errcode='42501';
  end if;
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'El lote histórico exige READ COMMITTED' using errcode='0A000';
  end if;
  if p_lote is null or jsonb_typeof(p_mapa) is distinct from 'array' then
    raise exception 'Indica lote y previsualización completos' using errcode='22023';
  end if;
  if jsonb_array_length(p_mapa)<1 or jsonb_array_length(p_mapa)>100 then
    raise exception 'El lote admite entre una y cien fuentes concretas' using errcode='22023';
  end if;
  select jsonb_agg(value order by value->>'tipo',value->>'id'),
    count(distinct (value->>'tipo',value->>'id')) into v_mapa,v_n
    from jsonb_array_elements(p_mapa);
  if v_n<>jsonb_array_length(p_mapa) then
    raise exception 'Una fuente no se repite dentro del lote' using errcode='22023';
  end if;
  v_hash:=private.idem_hash(v_mapa);

  -- Ventana breve y explícita de mantenimiento. El orden coincide con el
  -- protocolo de banderas: identidad -> inversión. No se cambia ninguna bandera.
  -- El exclusivo de identidad drena sus escritores antes de fijar la foto; las
  -- correcciones financieras que no lo usan se arbitran con locks NOWAIT abajo.
  perform pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'La identidad debe estar encendida para vincular sus fuentes' using errcode='P0409';
  end if;
  if private.inversiones_escritura_bajo_candado() then
    raise exception 'Apaga el escritor de inversiones antes del lote histórico' using errcode='P0409';
  end if;
  select * into v_previo from crm.inversion_backfill_lotes where id=p_lote;
  if found then
    if v_previo.hash_mapa<>v_hash then
      raise exception 'El lote ya corresponde a otra previsualización' using errcode='P0409';
    end if;
    if v_previo.finalizado_en is null then
      raise exception 'Lote histórico incoherente: requiere revisión' using errcode='P0409';
    end if;
    return v_previo.resultado;
  end if;

  -- El mantenimiento F2 legado no participa en las banderas de identidad.
  -- Bloquear filas existentes no cubre un mapa todavía ausente: SHARE fija
  -- también ese conjunto frente a INSERT/UPDATE/DELETE hasta COMMIT. NOWAIT
  -- rechaza otra intervención administrativa sin crear un ciclo de espera.
  lock table crm.backfill_multiempresa_mapa in share mode nowait;

  -- Revalidar referencias antes de usarlas para bloquear; nunca confiar en los
  -- IDs de persona/empresa o en el estado que envíe el consumidor del censo.
  for v_r in select value from jsonb_array_elements(v_mapa) loop
    v_actual:=private.inversion_historica_estado(v_r.value->>'tipo',(v_r.value->>'id')::uuid);
    if v_actual is distinct from v_r.value then
      raise exception 'La previsualización histórica cambió; repite el censo' using errcode='40001';
    end if;
    if v_actual->>'estado' not in ('pendiente','titular_pendiente','resuelto') then
      raise exception 'El lote contiene una fuente que requiere revisión o está excluida' using errcode='P0409';
    end if;
  end loop;
  select array_agg(distinct (value->>'persona')::uuid),
    array_agg(distinct (value->>'perfil')::uuid),array_agg(distinct (value->>'lead')::uuid),
    array_agg((value->>'id')::uuid) filter(where value->>'tipo'='contrato'),
    array_agg((value->>'id')::uuid) filter(where value->>'tipo'='cierre'),
    array_agg(distinct (value->>'inversion')::uuid)
    into v_personas,v_perfiles,v_leads,v_contratos,v_cierres,v_inversiones
    from jsonb_array_elements(v_mapa);
  perform 1 from crm.inversionistas where id=any(v_personas) order by id for update nowait;
  perform 1 from public.perfiles where id=any(v_perfiles) order by id for share nowait;
  perform 1 from crm.cierres_externos where id=any(v_cierres) order by id for update nowait;
  perform 1 from public.contratos where id=any(v_contratos) order by id for update nowait;
  perform 1 from crm.inversiones where id=any(v_inversiones) order by id for update nowait;
  perform 1 from crm.inversion_titulares where inversion_id=any(v_inversiones) order by id for update nowait;
  perform 1 from crm.leads where id=any(v_leads) order by id for share nowait;
  for v_r in select value from jsonb_array_elements(v_mapa) loop
    if private.inversion_historica_estado(v_r.value->>'tipo',(v_r.value->>'id')::uuid)
       is distinct from v_r.value then
      raise exception 'La fuente histórica cambió mientras se bloqueaba; repite el censo' using errcode='40001';
    end if;
  end loop;

  -- Acta ANTES de enlazar. Si cualquier paso falla, PostgreSQL revierte acta y
  -- enlaces; la restricción diferida impide confirmar un acta inconclusa.
  insert into crm.inversion_backfill_lotes(id,hash_mapa,mapa) values(p_lote,v_hash,v_mapa);
  for v_r in select value from jsonb_array_elements(v_mapa) loop
    v_actual:=v_r.value;
    if v_actual->>'estado'<>'resuelto' then
      if v_actual->>'tipo'='cierre' and v_actual->>'fuente_persona' is null then
        perform set_config('crm.op_privilegiada','on',true);
        update crm.cierres_externos set inversionista_id=(v_actual->>'persona')::uuid
          where id=(v_actual->>'id')::uuid and inversionista_id is null;
        get diagnostics v_n=row_count;
        perform set_config('crm.op_privilegiada',coalesce(v_old_priv,'off'),true);
        if v_n<>1 then raise exception 'La fuente ya cambió de identidad' using errcode='40001'; end if;
      end if;
      v_inversion:=private.inversion_vincular_fuente((v_actual->>'persona')::uuid,
        case when v_actual->>'tipo'='contrato' then (v_actual->>'id')::uuid end,
        case when v_actual->>'tipo'='cierre' then (v_actual->>'id')::uuid end,
        (v_actual->>'creado_por')::uuid,(v_actual->>'inicial')::boolean);
    else
      v_inversion:=(v_actual->>'inversion')::uuid;
    end if;
    v_final:=private.inversion_historica_estado(v_actual->>'tipo',(v_actual->>'id')::uuid);
    if v_final->>'estado'<>'resuelto' or (v_final->>'inversion')::uuid<>v_inversion then
      raise exception 'La vinculación histórica no quedó conciliada' using errcode='P0409';
    end if;
    v_filas:=v_filas||jsonb_build_array(jsonb_build_object('tipo',v_actual->>'tipo','id',v_actual->>'id',
      'accion',case v_actual->>'estado' when 'resuelto' then 'sin_cambios'
        when 'titular_pendiente' then 'titular_completado' else 'vinculada' end,
      'inversion',v_inversion,'titular',v_final->>'titular','persona',v_final->>'persona',
      'huella_final',v_final->>'huella'));
  end loop;
  v_resultado:=jsonb_build_object('lote',p_lote,'fuentes',v_filas,'hash_mapa',v_hash);
  update crm.inversion_backfill_lotes set resultado=v_resultado,finalizado_en=clock_timestamp() where id=p_lote;
  perform set_config('crm.op_privilegiada',coalesce(v_old_priv,'off'),true);
  return v_resultado;
exception when others then
  perform set_config('crm.op_privilegiada',coalesce(v_old_priv,'off'),true);
  raise;
end;
$$;
revoke all on function private.inversion_historica_aplicar(uuid,jsonb) from public,anon,authenticated,service_role;
