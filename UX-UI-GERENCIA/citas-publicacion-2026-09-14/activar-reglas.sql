-- Aplicación administrativa autorizada por Miguel; no es una migración de schema.
-- Ejecutar sólo después del merge de las cinco candidatas y antes del smoke.
-- Conserva la autoría del Superadmin existente y describe la ejecución asistida.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
do $aplicar$
declare
  v_actor uuid;
  v_antes jsonb;
  v_despues jsonb;
  v_config jsonb := '{"citas_por_lead":1.25,"entrevistas_porcentaje":70,"depositos_porcentaje":70,"excluir_manuales_base":false,"actividad_manuales":"incluir","conteo_entrevistas":"citas_realizadas","base_avance":"actividad_real","mes_resultado":"evento","analista_resultado":"evento","mes_inicio":"2026-09","mostrar_meta_citas":false,"base_depositos":"personas_entrevistadas"}'::jsonb;
begin
  if date_trunc('month',now() at time zone 'America/Lima')::date<>date '2026-09-01' then
    raise exception 'La vigencia preparada es septiembre de 2026; revisar el periodo';
  end if;
  if md5(pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure))<>'4ad2b90baf96b11b63a626122bd5d64b' then
    raise exception 'El lector no coincide con la versión verificada';
  end if;
  select id into strict v_actor from public.perfiles where rol='superadmin' and activo;
  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  v_antes:=crm.control_citas_configuracion_fn();
  if (v_antes->>'version_actual')::integer<>0 then
    raise exception 'Ya hay una configuración guardada; conciliar sin sobrescribir';
  end if;
  v_despues:=crm.guardar_control_citas_fn(0,v_config,
    'Aplicación administrativa ejecutada por Codex en nombre del Superadmin, autorizada por Miguel: 1,25 citas/lead interno; metas 70/70; mes y analista del evento; clientes por personas entrevistadas.');
  assert (v_despues->>'version_actual')::integer=1,'Se esperaba la primera versión';
  perform crm.aplicar_control_citas_fn(1);
  v_despues:=private.control_citas_vigente(date '2026-09-01');
  assert (v_despues->>'version')::integer=1 and v_despues->'configuracion'=v_config,'La vigencia no coincide con lo autorizado';
  assert (select count(*) from public.audit_log where tabla in('crm.control_citas_versiones','crm.control_citas_aplicaciones') and operacion='INSERT' and usuario_id=v_actor)=2,'Falta evidencia de autoría';
end $aplicar$;
select jsonb_build_object('estado','APLICADO','control',private.control_citas_vigente(date '2026-09-01')) as evidencia;
commit;
