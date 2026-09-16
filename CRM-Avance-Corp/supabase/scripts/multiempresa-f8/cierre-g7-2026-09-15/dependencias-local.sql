-- Sincronización de dependencias publicadas; SOLO copia sintética G7.
begin;
set local lock_timeout='2s';set local statement_timeout='30s';
do $guardia$ begin if current_database()<>'g7_cierre_20260915' then raise exception 'Banco incorrecto';end if;end $guardia$;
set local check_function_bodies=off;
CREATE OR REPLACE FUNCTION private.resolver_tasa(p_cliente_id uuid, p_categoria text, p_contrato_origen_id uuid, p_instante timestamp with time zone, p_contrato_nuevo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pol      crm.politica_rentabilidad;
  v_cli      record;
  v_origen   public.contratos%rowtype;
  v_previos  integer;
  v_activos  integer;
  v_base     numeric;
  v_regla    text;
begin
  -- Sin perfil aún: únicamente una intención nueva sin origen; misma política central.
  if p_cliente_id is null and (p_categoria is distinct from 'nuevo' or p_contrato_origen_id is not null) then
    raise exception 'Una renovación o ampliación requiere su cliente y contrato origen' using errcode='22023';
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
  if p_cliente_id is not null and v_cli.id is null then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  if p_cliente_id is not null and v_cli.activo is not true then
    raise exception 'El cliente está inactivo' using errcode = 'P0409';
  end if;
  -- «Previos» = los contratos del cliente sin contar el que se está observando (al commit, el nuevo ya existe).
  select count(*), count(*) filter (where c.estado = 'activo')
    into v_previos, v_activos
  from public.contratos c
  where c.cliente_id = p_cliente_id and not c.es_demo and c.id is distinct from p_contrato_nuevo_id;

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
      -- Mismo criterio que public.crear_contrato: se renueva un contrato activo o vencido que aún no fue renovado…
      -- …salvo que ya haya quedado renovado POR ESTE contrato (observación al commit): sigue siendo su origen.
      -- IS NOT TRUE (no «NOT»): con renovado_a_id NULL la segunda alternativa es NULL y un «NOT NULL» dejaría pasar un
      -- origen retirado (Codex R2 #3). La segunda alternativa exige además estado 'renovado'.
      if (
           (v_origen.estado in ('activo', 'vencido') and v_origen.renovado_a_id is null)
        or (p_contrato_nuevo_id is not null and v_origen.estado = 'renovado' and v_origen.renovado_a_id = p_contrato_nuevo_id)
      ) is not true then
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
    'tasa_minima_sin_autorizacion', private.rentabilidad_minimo_alta(p_categoria, v_base),
    'regla', v_regla,
    'categoria', p_categoria,
    'cliente_id', p_cliente_id,
    'contrato_origen', case when v_origen.id is null then null else jsonb_build_object(
        'id', v_origen.id, 'numero_contrato', v_origen.numero_contrato, 'tasa_anual', v_origen.tasa_anual,
        'estado', v_origen.estado, 'moneda', v_origen.moneda, 'capital', v_origen.capital,
        'fecha_vencimiento', v_origen.fecha_vencimiento) end,
    'contratos_previos', v_previos,
    'contratos_activos', v_activos,
    'prioridad_bandeja', (p_categoria = 'nuevo' and v_previos > 0),
    'politica', jsonb_build_object('id', v_pol.id, 'version', v_pol.version, 'modo', v_pol.modo,
        'tasa_base_nueva', v_pol.tasa_base_nueva, 'tope_tecnico', v_pol.tope_tecnico,
        'vigencia_solicitud_dias', v_pol.vigencia_solicitud_dias),
    'resuelto_en', coalesce(p_instante, statement_timestamp())
  );
end;
$function$;
alter function private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid) owner to postgres;
revoke all on function private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.cliente_tasa_lead(p_lead uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(l.perfil_id,
   (select i.perfil_id from crm.inversionistas i where i.id=private.inversionista_canonica(l.inversionista_id)),
   (select i.perfil_id from crm.inversionista_leads il join crm.inversionistas i
     on i.id=private.inversionista_canonica(il.inversionista_id) where il.lead_id=l.id limit 1),
   (select p.id from public.perfiles p where p.rol='cliente' and p.dni=l.dni
     and coalesce(nullif(btrim(p.tipo_documento),''),'DNI')='DNI' limit 1))
 from crm.leads l where l.id=p_lead;
$function$;
alter function private.cliente_tasa_lead(uuid) owner to postgres;
revoke all on function private.cliente_tasa_lead(uuid) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.rentabilidad_minimo_alta(p_categoria text, p_base numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE STRICT
 SET search_path TO ''
AS $function$
  select case when p_categoria='nuevo' then 0.01::numeric else p_base end;
$function$;
alter function private.rentabilidad_minimo_alta(text,numeric) owner to postgres;
revoke all on function private.rentabilidad_minimo_alta(text,numeric) from public,anon,authenticated,service_role;
alter table private.contrato_pdf_jobs drop constraint contrato_pdf_jobs_template_valido;
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_template_valido CHECK ((template_version = ANY (ARRAY['contrato-aep-17-v2'::text, 'contrato-aep-17-v3'::text, 'contrato-aep-17-v4'::text, 'contrato-aep-17-v5'::text, 'contrato-aep-17-v6'::text, 'contrato-aep-17-v7'::text, 'contrato-aep-17-v8'::text, 'contrato-aep-17-v9'::text])));
alter table crm.solicitudes_tasa alter column cliente_id drop not null;
alter table crm.solicitudes_tasa add column if not exists lead_id uuid references crm.leads(id) on delete restrict;
alter table crm.solicitudes_tasa add column if not exists huella_preconversion text;
alter table crm.solicitudes_tasa add column if not exists documento_lead text;
-- Cotejo de catálogo productivo de 15/09 23:56 UTC: mismo sujeto obligatorio
-- y mismo valor predeterminado, sin relajar el esquema para pasar los ensayos.
do $sujeto$ begin
  if not exists(select 1 from pg_constraint where conrelid='crm.solicitudes_tasa'::regclass
    and conname='solicitudes_tasa_sujeto') then
    alter table crm.solicitudes_tasa add constraint solicitudes_tasa_sujeto
      check(cliente_id is not null or lead_id is not null);
  end if;
end; $sujeto$;
alter table private.contrato_pdf_jobs alter column template_version set default 'contrato-aep-17-v9';
alter table crm.conversion_reservas add column if not exists condiciones_tasa jsonb;
notify pgrst,'reload schema';
commit;
