-- Corrección administrativa directa de tasa: conserva la puerta transaccional,
-- cuotas pagadas y revisión PDF. La excepción a la política se concede solo
-- durante ESTA RPC, al contrato indicado y a un admin/superadmin vigente.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $cambio$
declare
  cuerpo text := pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure);
  antes text;
  despues text;
begin
  if cuerpo is null then raise exception 'Falta el observador de rentabilidad'; end if;

  antes := $a$  v_solicitud  uuid;
begin$a$;
  despues := $d$  v_solicitud  uuid;
  v_admin_corr boolean := false;
  v_admin_motivo text;
begin$d$;
  if cardinality(string_to_array(cuerpo, antes)) <> 2 then raise exception 'Declaración del observador cambió'; end if;
  cuerpo := replace(cuerpo, antes, despues);

  antes := $a$  v_enforce := (v_modo = 'enforcement');$a$;
  despues := $d$  v_enforce := (v_modo = 'enforcement');
  if tg_op = 'UPDATE' then
    v_admin_motivo := nullif(btrim(current_setting('crm.tasa_admin_motivo', true)), '');
    v_admin_corr := coalesce(v_c.tasa_anual is distinct from old.tasa_anual
      and current_setting('crm.tasa_admin_contrato_id', true) = v_c.id::text
      and length(v_admin_motivo) between 5 and 500
      and not (v_cambios ?| array['capital', 'moneda', 'fecha_inicio', 'fecha_vencimiento',
                       'modalidad', 'tipo_interes', 'producto_condicion_id', 'categoria', 'cliente_id'])
      and public.es_admin(), false);
    if v_admin_corr then
      v_en_juego := true;
      v_huella_mov := v_cambios ?| array['capital', 'moneda', 'fecha_inicio', 'fecha_vencimiento',
                       'modalidad', 'tipo_interes', 'producto_condicion_id', 'categoria', 'cliente_id'];
    end if;
  end if;$d$;
  if cardinality(string_to_array(cuerpo, antes)) <> 2 then raise exception 'Modo del observador cambió'; end if;
  cuerpo := replace(cuerpo, antes, despues);

  antes := $a$  if v_enforce and v_c.es_demo is not true then$a$;
  despues := $d$  if v_enforce and v_c.es_demo is not true and not v_admin_corr then$d$;
  if cardinality(string_to_array(cuerpo, antes)) <> 2 then raise exception 'Candado del observador cambió'; end if;
  cuerpo := replace(cuerpo, antes, despues);

  antes := $a$    'origen_declarado', v_origen_dec,$a$;
  despues := $d$    'origen_declarado', v_origen_dec,
    'correccion_admin_directa', case when v_admin_corr then true end,
    'motivo_correccion_admin', case when v_admin_corr then v_admin_motivo end,$d$;
  if cardinality(string_to_array(cuerpo, antes)) <> 2 then raise exception 'Detalle del ledger cambió'; end if;
  execute replace(cuerpo, antes, despues);
end;
$cambio$;

create or replace function crm.corregir_tasa_contrato_admin_pdf_v1(
  p_id uuid, p_contrato jsonb, p_cronograma jsonb, p_motivo text,
  p_tasa_esperada numeric
) returns jsonb
language plpgsql security definer set search_path = ''
as $funcion$
declare
  v_tasa_actual numeric;
  v_tasa_nueva numeric;
  v_contrato_actual public.contratos%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if auth.uid() is null or not public.es_admin()
     or private.membresia_crm_revocada() then
    raise insufficient_privilege using message = 'Solo Administración puede corregir la tasa directamente';
  end if;
  if length(v_motivo) not between 5 and 500 then
    raise exception 'Indica un motivo de entre 5 y 500 caracteres para corregir la tasa'
      using errcode = '22023';
  end if;
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  v_tasa_nueva := (p_contrato ->> 'tasa_anual')::numeric;
  if v_tasa_nueva is null or v_tasa_nueva < 0.01 or v_tasa_nueva > 50
     or v_tasa_nueva <> round(v_tasa_nueva, 2) then
    raise exception 'La tasa debe estar entre 0,01%% y 50%%, con dos decimales como máximo'
      using errcode = '22023';
  end if;
  select c.* into v_contrato_actual
    from public.contratos c where c.id = p_id for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  v_tasa_actual := v_contrato_actual.tasa_anual;
  if p_tasa_esperada is null or v_tasa_actual is distinct from p_tasa_esperada then
    raise exception 'La tasa del contrato cambió desde que abriste el formulario; recarga antes de corregirla'
      using errcode = '22023';
  end if;
  if v_tasa_nueva is not distinct from v_tasa_actual then
    raise exception 'La tasa no cambió; usa la corrección normal del contrato'
      using errcode = '22023';
  end if;
  if row(
       (p_contrato ->> 'capital')::numeric,
       coalesce(nullif(p_contrato ->> 'moneda', ''), v_contrato_actual.moneda),
       p_contrato ->> 'modalidad',
       coalesce(nullif(p_contrato ->> 'tipo_interes', ''), v_contrato_actual.tipo_interes),
       (p_contrato ->> 'fecha_inicio')::date,
       (p_contrato ->> 'fecha_vencimiento')::date,
       coalesce(nullif(p_contrato ->> 'categoria', ''), v_contrato_actual.categoria)
     ) is distinct from row(
       v_contrato_actual.capital, v_contrato_actual.moneda,
       v_contrato_actual.modalidad, v_contrato_actual.tipo_interes,
       v_contrato_actual.fecha_inicio, v_contrato_actual.fecha_vencimiento,
       v_contrato_actual.categoria
     ) then
    raise exception 'Corrige la tasa por separado de capital, moneda, plazo, modalidad y categoría'
      using errcode = '22023';
  end if;

  -- SET LOCAL persiste hasta el commit para el trigger de rentabilidad diferido.
  -- El observador revalida el rol y el id antes de aplicar la excepción.
  perform set_config('crm.tasa_admin_contrato_id', p_id::text, true);
  perform set_config('crm.tasa_admin_motivo', v_motivo, true);
  return crm.actualizar_contrato_con_cuenta_pdf_v3(p_id, p_contrato, p_cronograma);
end;
$funcion$;

revoke all on function crm.corregir_tasa_contrato_admin_pdf_v1(uuid,jsonb,jsonb,text,numeric) from public, anon;
grant execute on function crm.corregir_tasa_contrato_admin_pdf_v1(uuid,jsonb,jsonb,text,numeric) to authenticated;
comment on function crm.corregir_tasa_contrato_admin_pdf_v1(uuid,jsonb,jsonb,text,numeric) is
  'Admin/superadmin vigente corrige tasa sin aprobación de Gerencia: motivo en ledger, cronograma y revisión PDF atómicos; conserva cuotas pagadas.';

notify pgrst, 'reload schema';
commit;
