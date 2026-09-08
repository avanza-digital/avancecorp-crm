-- Una solicitud pendiente bloquea el alta, incluso a la tasa base.
-- Ámbito: cliente + categoría + contrato origen, independientemente del actor,
-- capital/plazo/modalidad. Una respuesta o caducidad libera el alta; R4 conserva
-- la validación de cualquier tasa superior y el consumo de la autorización.
-- No cambia tablas/ACL/firmas públicas ni contratos históricos.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
begin
  if to_regprocedure('private.rentabilidad_bloquear_operacion(uuid,text,uuid)') is not null
     or to_regprocedure('private.rentabilidad_exigir_respuesta(uuid,text,uuid)') is not null then
    raise exception 'El bloqueo de solicitudes ya existe: revisar antes de reemplazarlo';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid='public.contratos'::regclass
    and tgfoid='private.trg_contratos_observar_rentabilidad()'::regprocedure
    and tgenabled='O' and tgdeferrable and tginitdeferred and (tgtype & 4) = 4) then
    raise exception 'Falta el candado diferido activo de altas de R4';
  end if;
end;
$preflight$;

create or replace function private.rentabilidad_bloquear_operacion(
  p_cliente uuid, p_categoria text, p_origen uuid
) returns void
language sql volatile security invoker set search_path = ''
as $function$
  select pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.rentabilidad_operacion_pendiente'),
    pg_catalog.hashtext(p_cliente::text || ':' || p_categoria || ':' || coalesce(p_origen::text, ''))
  );
$function$;
revoke all on function private.rentabilidad_bloquear_operacion(uuid, text, uuid) from public, anon, authenticated, service_role;

create or replace function private.rentabilidad_exigir_respuesta(
  p_cliente uuid, p_categoria text, p_origen uuid
) returns void
language plpgsql volatile security invoker set search_path = ''
as $function$
begin
  perform private.rentabilidad_bloquear_operacion(p_cliente, p_categoria, p_origen);
  if exists (
    select 1 from crm.solicitudes_tasa s
    where s.cliente_id = p_cliente and s.categoria = p_categoria
      and s.contrato_origen_id is not distinct from p_origen
      and s.estado = 'pendiente' and s.vence_en > pg_catalog.clock_timestamp()
  ) then
    raise exception 'La solicitud de tasa está pendiente de Gerencia. Espera su respuesta antes de crear el contrato, incluso a la tasa base.'
      using errcode = 'P0411';
  end if;
end;
$function$;
revoke all on function private.rentabilidad_exigir_respuesta(uuid, text, uuid) from public, anon, authenticated, service_role;
comment on function private.rentabilidad_exigir_respuesta(uuid, text, uuid) is
  'Impide crear un contrato con una solicitud de tasa pendiente vigente para el mismo cliente, categoría y origen, aunque cambien capital/plazo o lo intente otro actor. Error P0411. No depende del modo observacion/enforcement. Solo uso interno desde el candado del alta.';

-- Inserciones acotadas sobre las definiciones INSTALADAS: no reponer versiones
-- antiguas de R4 ni sobrescribir correcciones posteriores o la idempotencia.
-- Cada ancla debe aparecer exactamente una vez; si cambió el cuerpo, se aborta.
do $patch$
declare
  v_def text;
  v_ancla text;
  v_nueva text;
begin
  v_def := pg_catalog.pg_get_functiondef('crm.solicitar_tasa_fn(jsonb)'::regprocedure);
  v_ancla := '  v_huella := private.huella_solicitud_tasa(v_cliente, v_cat, v_origen, v_pc, v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv);';
  if cardinality(string_to_array(v_def, v_ancla)) <> 2
     or position('private.rentabilidad_bloquear_operacion' in v_def) > 0 then
    raise exception 'Preflight: solicitar_tasa_fn cambió o el bloqueo ya está instalado';
  end if;
  v_nueva := E'  perform private.rentabilidad_bloquear_operacion(v_cliente, v_cat, v_origen);\n' || v_ancla;
  execute replace(v_def, v_ancla, v_nueva);

  v_def := pg_catalog.pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure);
  v_ancla := ' -- El rechazo vive AQUÍ, fuera del manejador: dentro, el propio WHEN OTHERS se lo tragaría.';
  if cardinality(string_to_array(v_def, v_ancla)) <> 2
     or position('private.rentabilidad_exigir_respuesta' in v_def) > 0 then
    raise exception 'Preflight: el candado de rentabilidad cambió o el bloqueo ya está instalado';
  end if;
  v_nueva := $insert$
 -- Fuera del manejador de observación: ni los errores ni P0411 se ignoran.
 -- R4 ya resolvió el origen y consumió su GUC una sola vez; no volver a leerlo.
 if tg_op = 'INSERT' and v_c.id is not null and v_c.es_demo is not true then
   perform private.rentabilidad_exigir_respuesta(v_c.cliente_id, v_c.categoria, coalesce(v_origen, v_origen_dec));
 end if;
$insert$ || v_ancla;
  execute replace(v_def, v_ancla, v_nueva);
end;
$patch$;

notify pgrst, 'reload schema';
commit;
