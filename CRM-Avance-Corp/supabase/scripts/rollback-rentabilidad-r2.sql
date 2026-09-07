-- ============================================================================
-- REVERSA de RENTABILIDAD R2 (20260906180000): suelta el observador diferido de public.contratos, la tarjeta y la sobrecarga
-- de 5 argumentos del núcleo, y RESTAURA private.resolver_tasa(uuid,text,uuid,timestamptz) al texto exacto de R1
-- (md5 f394b983…). Las filas origen='observacion' del ledger se CONSERVAN (historia; el ledger es append-only) y la tabla
-- crm.rentabilidad_hitos también (anota observacion_desactivada_en). Repetible.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r2'));
do $pre$
declare v_h4 text; v_h5 text;
begin
  -- Solo se revierte un estado CONOCIDO (Codex R2 #16): el núcleo de 4 args debe ser el de R1 (f394b983…) o el envoltorio de
  -- R2; si es otro texto, hay una evolución posterior y esta reversa no corresponde. La sobrecarga de 5 args, si existe, se suelta.
  select md5(p.prosrc) into v_h4 from pg_proc p where p.oid = to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz)');
  if v_h4 is null then
    raise exception 'REVERSA R2: falta private.resolver_tasa(uuid,text,uuid,timestamptz) (¿R1 revertida?)';
  end if;
  if v_h4 not in ('f394b983e5554deb38a210329694aa70', md5(E'\n  select private.resolver_tasa(p_cliente_id, p_categoria, p_contrato_origen_id, p_instante, null::uuid)\n')) then
    raise exception 'REVERSA R2: el núcleo de 4 args no es ni el de R1 ni el envoltorio de R2 (%): hay una versión posterior', left(v_h4, 8);
  end if;
  if to_regclass('crm.ledger_rentabilidad') is null then
    raise exception 'REVERSA R2: falta el ledger de R1';
  end if;
  -- La sobrecarga de 5 args, si existe, debe ser la de una versión de R2 conocida (Codex R2 #16); otra evolución no se suelta a ciegas.
  select md5(p.prosrc) into v_h5 from pg_proc p where p.oid = to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)');
  if v_h5 is not null and v_h5 not in ('a3f043fb2b4c76ecbb59e5e3e98e3ba0') then
    raise exception 'REVERSA R2: private.resolver_tasa(5 args) no es de ninguna versión conocida de R2 (%): hay una evolución posterior', left(v_h5, 8);
  end if;
  -- El registro, si existe, debe ser el de R2 (no se desregistra otra cosa).
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906180000'
             and (name <> 'crm_rentabilidad_r2_observacion_ledger_y_tarjeta' or md5(statements[1]) not in ('2bf3ddc74351a1c58e9fc3b03b8a4516', '689531c32feefacf22d148c2fad2ef45', 'dbedf24aeece56c1da5917a128beadec'))) then
    raise exception 'REVERSA R2: la versión 20260906180000 registrada no es un contenido conocido de R2';
  end if;
end
$pre$;
drop trigger if exists trg_contratos_zz_observar_rentabilidad on public.contratos;
drop function if exists private.trg_contratos_observar_rentabilidad();
drop function if exists crm.observacion_rentabilidad_fn(date, date);
-- La tabla de hitos SOBREVIVE (rastro de cuándo estuvo activa la observación; Codex R2 #26): se anota la desactivación.
-- Solo si la tabla existe (Codex #28: tras una instalación abortada puede no existir; la relación se resuelve dentro del EXECUTE).
do $hito$
begin
  if to_regclass('crm.rentabilidad_hitos') is not null then
    execute $q$insert into crm.rentabilidad_hitos (clave, valor, registrado_en)
      select 'observacion_desactivada_en', jsonb_build_object('en', clock_timestamp(), 'reversa', '20260906180000',
               'activa_desde', (select h.valor ->> 'en' from crm.rentabilidad_hitos h where h.clave = 'observacion_activa_desde')), clock_timestamp()
      on conflict (clave) do update set valor = excluded.valor, registrado_en = excluded.registrado_en$q$;
  end if;
end
$hito$;
drop index if exists crm.ledger_rentabilidad_secuencia_idx;
alter table crm.ledger_rentabilidad drop column if exists secuencia;
drop function if exists private.resolver_tasa(uuid, text, uuid, timestamptz, uuid);
-- El núcleo de R1, byte a byte:
create or replace function private.resolver_tasa(
  p_cliente_id uuid,
  p_categoria text,
  p_contrato_origen_id uuid,
  p_instante timestamptz default statement_timestamp()
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_pol      crm.politica_rentabilidad;
  v_cli      record;
  v_origen   public.contratos%rowtype;
  v_previos  integer;
  v_activos  integer;
  v_base     numeric;
  v_regla    text;
begin
  if p_cliente_id is null then
    raise exception 'El cliente es obligatorio' using errcode = '22023';
  end if;
  if p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (nuevo, renovacion o upgrade)' using errcode = '22023';
  end if;
  v_pol := private.politica_rentabilidad_vigente(p_instante);
  if v_pol.id is null then
    raise exception 'No hay política de rentabilidad vigente' using errcode = 'P0002';
  end if;
  select p.id, p.activo, p.asesor_perfil_id into v_cli
  from public.perfiles p where p.id = p_cliente_id and p.rol = 'cliente';
  if v_cli.id is null then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  if v_cli.activo is not true then
    -- Las puertas de alta exigen cliente ACTIVO: una tasa para un cliente inactivo sería una promesa que ningún alta cumple (auditor m1).
    raise exception 'El cliente está inactivo' using errcode = 'P0409';
  end if;
  select count(*), count(*) filter (where c.estado = 'activo')
    into v_previos, v_activos
  from public.contratos c where c.cliente_id = p_cliente_id and not c.es_demo;

  if p_categoria = 'nuevo' then
    if p_contrato_origen_id is not null then
      raise exception 'Una primera inversión no lleva contrato origen' using errcode = '22023';
    end if;
    v_base := v_pol.tasa_base_nueva;
    v_regla := 'primera_inversion';
  else
    if p_contrato_origen_id is null then
      raise exception 'Selecciona el contrato que se % (contrato origen)', case when p_categoria = 'renovacion' then 'renueva' else 'amplía' end
        using errcode = '22023';
    end if;
    select * into v_origen from public.contratos c where c.id = p_contrato_origen_id;
    if v_origen.id is null then
      raise exception 'El contrato origen no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from p_cliente_id then
      raise exception 'El contrato origen pertenece a otro cliente' using errcode = 'P0409';
    end if;
    if p_categoria = 'renovacion' then
      -- Mismo criterio que public.crear_contrato: se renueva un contrato activo o vencido que aún no fue renovado.
      if v_origen.estado not in ('activo', 'vencido') or v_origen.renovado_a_id is not null then
        raise exception 'El contrato origen ya fue cerrado o renovado (estado «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_renovacion';
    else
      -- D2: el upgrade amplía un contrato ACTIVO concreto que el analista selecciona.
      if v_origen.estado <> 'activo' or v_origen.renovado_a_id is not null then
        raise exception 'El upgrade solo amplía un contrato activo (este está «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_upgrade';
    end if;
    v_base := v_origen.tasa_anual;
  end if;

  return jsonb_build_object(
    'tasa_base', v_base,
    'regla', v_regla,
    'categoria', p_categoria,
    'cliente_id', p_cliente_id,
    'contrato_origen', case when v_origen.id is null then null else jsonb_build_object(
        'id', v_origen.id, 'numero_contrato', v_origen.numero_contrato, 'tasa_anual', v_origen.tasa_anual,
        'estado', v_origen.estado, 'moneda', v_origen.moneda, 'capital', v_origen.capital,
        'fecha_vencimiento', v_origen.fecha_vencimiento) end,
    'contratos_previos', v_previos,
    'contratos_activos', v_activos,
    -- D1: la excepción de un cliente que YA invirtió tiene prioridad en la bandeja de Gerencia.
    'prioridad_bandeja', (p_categoria = 'nuevo' and v_previos > 0),
    'politica', jsonb_build_object('id', v_pol.id, 'version', v_pol.version, 'modo', v_pol.modo,
        'tasa_base_nueva', v_pol.tasa_base_nueva, 'tope_tecnico', v_pol.tope_tecnico,
        'vigencia_solicitud_dias', v_pol.vigencia_solicitud_dias),
    'resuelto_en', coalesce(p_instante, statement_timestamp())
  );
end;
$function$;
revoke all on function private.resolver_tasa(uuid, text, uuid, timestamptz) from public, anon, authenticated, service_role;
comment on function private.resolver_tasa(uuid, text, uuid, timestamptz) is
  'Rentabilidad R1: EL ÚNICO NÚCLEO que responde «qué tasa base corresponde a este contrato y por qué». nuevo → tasa base de la política vigente (D1); renovacion → hereda tasa_anual del origen activo/vencido no renovado; upgrade → hereda la del origen ACTIVO seleccionado (D2). Toda puerta, trigger o pantalla que necesite la tasa base la CONSUME de aquí; está prohibido reimplementarla.';
do $post$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.resolver_tasa(uuid,text,uuid,timestamptz)'::regprocedure) is distinct from 'f394b983e5554deb38a210329694aa70' then
    raise exception 'REVERSA R2: el núcleo no quedó con el texto de R1 (f394b983…)';
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.contratos'::regclass and tgname = 'trg_contratos_zz_observar_rentabilidad')
     or to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)') is not null
     or to_regprocedure('crm.observacion_rentabilidad_fn(date,date)') is not null
     or to_regprocedure('private.trg_contratos_observar_rentabilidad()') is not null then
    raise exception 'REVERSA R2: quedó algún objeto vivo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906180000';
  raise notice 'REVERSA RENTABILIDAD R2 OK (núcleo de R1 restaurado; versión 20260906180000 desregistrada si estaba)';
end
$post$;
commit;
