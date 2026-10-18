-- Qorilazo y Prodelco: un año de plazo equivale a 360 días corridos.
-- Borrador preparado desde el catálogo de producción leído el 16/10/2026.
-- Requiere aprobación del SQL y ensayo en una rama antes de instalar.
-- Las filas existentes mantienen meses calendario; no se recalculan fechas.
-- Reversa: cambiar el DEFAULT y el helper de nuevas altas a calendario.
-- Conservar la columna, su CHECK y la corrección por base para contratos de 360 días.
begin;
set local lock_timeout='5s';

do $deriva$
begin
  if md5(pg_get_functiondef('private.coopac_validar_condiciones(date,integer,numeric)'::regprocedure))
       is distinct from '10ad4aaf7e96013a50273fd1ac47f5b7'
    or md5(pg_get_functiondef('crm.inversionista_corregir_coopac_fn(uuid,uuid,uuid,text,jsonb)'::regprocedure))
       is distinct from 'd347a2c84dc07fa3f3bb91c871719872'
    or (select md5(pg_get_constraintdef(oid)) from pg_constraint
        where conrelid='crm.cierres_externos'::regclass
          and conname='cierres_coopac_condiciones_completas')
       is distinct from 'd6a4d93538ee16cf31d5f373209c901f' then
    raise exception 'Las condiciones COOPAC cambiaron; revisar el SQL antes de aplicar';
  end if;
end;
$deriva$;

-- El primer DEFAULT conserva la convención de todas las filas anteriores,
-- incluidos históricos sin plazo. El segundo rige solamente altas nuevas.
alter table crm.cierres_externos
  add column base_plazo text not null default 'calendario';
alter table crm.cierres_externos
  alter column base_plazo set default 'dias_360',
  add constraint cierres_coopac_base_plazo check (base_plazo in ('calendario','dias_360'));
comment on column crm.cierres_externos.base_plazo is
  'Convención del plazo, fijada al registrar: calendario en históricos; dias_360 en nuevas inversiones (30 días por mes). Se conserva al corregir. No altera importes ni rentabilidad.';

create function private.coopac_validar_condiciones_base(
  p_inicio date,p_plazo_meses integer,p_tasa_anual numeric,p_base_plazo text)
returns date language plpgsql immutable set search_path='' as $function$
begin
  if p_inicio is null or not isfinite(p_inicio)
    or p_plazo_meses is null or p_plazo_meses not between 1 and 1200 then
    raise exception 'Indica una fecha de inicio válida y un plazo de 1 a 1200 meses enteros' using errcode='22023';
  end if;
  if p_tasa_anual is null or p_tasa_anual in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
    or p_tasa_anual<=0 or p_tasa_anual<>trunc(p_tasa_anual,2) then
    raise exception 'La rentabilidad anual debe ser un porcentaje positivo con hasta dos decimales' using errcode='22023';
  end if;
  if p_base_plazo='calendario' then
    return (p_inicio + make_interval(months=>p_plazo_meses))::date;
  elsif p_base_plazo='dias_360' then
    return p_inicio + p_plazo_meses * 30;
  end if;
  raise exception 'Convención del plazo de cooperativa inválida' using errcode='22023';
end;
$function$;
alter function private.coopac_validar_condiciones_base(date,integer,numeric,text) owner to postgres;
revoke all on function private.coopac_validar_condiciones_base(date,integer,numeric,text) from public,anon,authenticated;
comment on function private.coopac_validar_condiciones_base(date,integer,numeric,text) is
  'Núcleo de vencimiento COOPAC: valida condiciones y conserva la convención del contrato al corregir.';

create or replace function private.coopac_validar_condiciones(p_inicio date,p_plazo_meses integer,p_tasa_anual numeric)
returns date language plpgsql immutable set search_path='' as $function$
begin
  return private.coopac_validar_condiciones_base(p_inicio,p_plazo_meses,p_tasa_anual,'dias_360');
end;
$function$;
comment on function private.coopac_validar_condiciones(date,integer,numeric) is
  'Núcleo de nuevas inversiones COOPAC: meses enteros de 30 días; 12 meses son 360 días corridos.';

alter table crm.cierres_externos drop constraint cierres_coopac_condiciones_completas;
alter table crm.cierres_externos add constraint cierres_coopac_condiciones_completas check (
  (plazo_meses is null and tasa_anual is null)
  or (plazo_meses is not null and tasa_anual is not null
    and base_plazo in ('calendario','dias_360') and plazo_meses between 1 and 1200
    and tasa_anual not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
    and tasa_anual>0 and tasa_anual=trunc(tasa_anual,2)
    and vence_en is not null and isfinite(vence_en)
    and vence_en=case base_plazo
      when 'calendario' then
        (coalesce(fecha_comercial,(creado_en at time zone 'America/Lima')::date)
          + make_interval(months=>plazo_meses))::date
      when 'dias_360' then
        coalesce(fecha_comercial,(creado_en at time zone 'America/Lima')::date) + plazo_meses * 30
    end)
);
comment on constraint cierres_coopac_condiciones_completas on crm.cierres_externos is
  'Plazo, tasa y vencimiento coherentes según la convención persistida. Conserva fechas históricas y exige 30 días por mes en nuevas altas.';

-- Mismos permisos, revisión optimista, idempotencia, auditoría y firma.
-- Único cambio funcional: calcular con la convención persistida en la fuente.
CREATE OR REPLACE FUNCTION crm.inversionista_corregir_coopac_fn(p_inversionista uuid, p_fuente uuid, p_clave uuid, p_revision text, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_i crm.inversionistas%rowtype; v_ce crm.cierres_externos%rowtype;
  v_recibo jsonb; v_vence date; v_plazo integer; v_tasa numeric; v_monto numeric; v_contexto_previo text;
begin
  if private.rol_crm(auth.uid()) is distinct from 'gerencia' or private.es_lector_global() then
    raise exception 'Solo Gerencia corrige inversiones de cooperativas' using errcode='42501'; end if;
  v_i:=private.postventa_persona(p_inversionista,false);
  v_ce:=private.postventa_fuente(p_fuente,v_i.id);
  select * into strict v_ce from crm.cierres_externos where id=p_fuente for update nowait;
  v_recibo:=private.postventa_recibo(p_clave,v_i.id,'corregir_coopac',
    jsonb_build_object('fuente',p_fuente,'revision',p_revision,'datos',p_datos));
  if v_recibo is not null then return v_recibo; end if;
  if p_revision is distinct from md5(to_jsonb(v_ce)::text) then
    raise exception 'La inversión cambió. Vuelve a abrirla antes de corregir' using errcode='PT409'; end if;
  if p_datos is null or jsonb_typeof(p_datos)<>'object' or
    p_datos-array['monto','numero_transaccion','referencia','nota','plazo_meses','tasa_anual','vence_en']<>'{}'::jsonb then
    raise exception 'Datos de inversión inválidos' using errcode='22023'; end if;
  if length(p_datos->>'nota')>2000 then raise exception 'La nota admite hasta 2000 caracteres' using errcode='22023'; end if;
  v_monto:=(p_datos->>'monto')::numeric;
  if v_monto is null or v_monto in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
    or v_monto<=0 or v_monto>999999999999.99 or v_monto<>trunc(v_monto,2) then
    raise exception 'Indica un monto positivo con hasta dos decimales' using errcode='22023'; end if;
  v_plazo:=(p_datos->>'plazo_meses')::integer; v_tasa:=(p_datos->>'tasa_anual')::numeric;
  if v_plazo is null and v_tasa is null and v_ce.plazo_meses is null then
    v_vence:=case when p_datos ? 'vence_en' then (p_datos->>'vence_en')::date else v_ce.vence_en end;
    if v_vence is not null and not isfinite(v_vence) then raise exception 'Vencimiento inválido' using errcode='22023'; end if;
  else
    v_vence:=private.coopac_validar_condiciones_base(coalesce(v_ce.fecha_comercial,(v_ce.creado_en at time zone 'America/Lima')::date),v_plazo,v_tasa,v_ce.base_plazo);
  end if;
  -- Las condiciones y el vencimiento cambian juntos para conservar su CHECK.
  perform set_config('crm.op_privilegiada','on',true);
  update crm.cierres_externos set plazo_meses=v_plazo,tasa_anual=v_tasa,vence_en=v_vence where id=p_fuente;
  perform set_config('crm.op_privilegiada','off',true);
  v_contexto_previo:=current_setting('crm.gestion_neutral',true);
  perform set_config('crm.gestion_neutral','on',true);
  perform crm.corregir_cierre_externo(p_fuente,v_monto,v_ce.moneda,v_ce.cooperativa,
    p_datos->>'numero_transaccion',p_datos->>'referencia',v_vence,p_datos->>'nota');
  perform set_config('crm.gestion_neutral',coalesce(v_contexto_previo,'off'),true);
  insert into crm.inversionista_gestiones(inversionista_id,empresa,tipo,detalle,metadata,creado_por)
    values(v_i.id,v_ce.cooperativa,'correccion_coopac','Gerencia corrigió la inversión de cooperativa',
      jsonb_build_object('accion','correccion_coopac','fuente_id',p_fuente,
        'antes',jsonb_build_object('monto',v_ce.monto,'numero_transaccion',v_ce.numero_transaccion,
          'referencia_externa',v_ce.referencia_externa,'nota',v_ce.nota),
        'despues',jsonb_build_object('monto',v_monto,'numero_transaccion',btrim(p_datos->>'numero_transaccion'),
          'referencia_externa',nullif(btrim(p_datos->>'referencia'),''),'nota',nullif(btrim(p_datos->>'nota'),'')),
        'condiciones_antes',jsonb_build_object('plazo_meses',v_ce.plazo_meses,'tasa_anual',v_ce.tasa_anual,'vence_en',v_ce.vence_en),
        'condiciones_despues',jsonb_build_object('plazo_meses',v_plazo,'tasa_anual',v_tasa,'vence_en',v_vence)),auth.uid());
  return private.postventa_responder(p_clave,jsonb_build_object('ok',true,'inversionista_id',v_i.id,'fuente_id',p_fuente));
exception when serialization_failure or lock_not_available or deadlock_detected then
  raise exception 'La inversión está cambiando. Vuelve a comprobarla' using errcode='PT409';
when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
  raise exception 'Revisa el monto, el plazo, la tasa y la fecha de vencimiento' using errcode='22023';
end;
$function$;

commit;
