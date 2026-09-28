-- Mantenimiento DML autorizado; NO es una migración ni una RPC.
-- Ejecutar dentro de BEGIN ISOLATION LEVEL REPEATABLE READ, con manifiesto
-- privado en crm.correccion_origen_plan y request.jwt.claim.sub de Gerencia.
-- Cada elemento acredita la fuente/importes esperados y diferencia canal
-- confirmado de asignación administrativa. Sin manifiesto no hace nada.
-- No deshabilita triggers ni modifica episodios/fotos inmutables.
do $corregir$
declare
  v_plan jsonb := current_setting('crm.correccion_origen_plan')::jsonb;
  v_fila jsonb;
  v_uid uuid := auth.uid();
  v_batch uuid;
  v_lead crm.leads%rowtype;
  v_fecha date;
  v_capital numeric;
  v_moneda text;
  v_vendedor uuid;
  v_pertenece boolean;
  v_antes jsonb;
  v_despues jsonb;
  v_nota text;
  v_prev text := current_setting('crm.op_privilegiada',true);
  v_total integer;
  v_cambiados integer := 0;
begin
  if current_user <> 'postgres' or v_uid is null
     or private.rol_crm(v_uid) is distinct from 'gerencia'
     or not exists(select 1 from crm.equipo where perfil_id=v_uid and activo)
  then raise exception 'Requiere mantenimiento SQL y Gerencia activa'; end if;
  if current_setting('transaction_isolation') <> 'repeatable read' then
    raise exception 'Requiere una transaccion REPEATABLE READ'; end if;
  if jsonb_typeof(v_plan) is distinct from 'object'
     or jsonb_typeof(v_plan->'filas') is distinct from 'array'
     or coalesce(length(v_plan->>'motivo'),0) not between 10 and 300
     or v_plan->>'periodo' is null
     or (v_plan->>'periodo')::date <> date_trunc('month',(v_plan->>'periodo')::date)::date
  then raise exception 'Manifiesto invalido'; end if;
  v_batch := (v_plan->>'batch')::uuid;
  if v_batch is null then raise exception 'Falta identificador del lote'; end if;
  v_total := jsonb_array_length(v_plan->'filas');
  if v_total not between 1 and 20 or
     (select count(distinct f->>'lead_id') from jsonb_array_elements(v_plan->'filas') f) <> v_total
  then raise exception 'Lote vacio, excesivo o con leads duplicados'; end if;

  perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),
    ((v_plan->>'periodo')::date-date '2000-01-01')::integer);
  if exists(select 1 from crm.periodos_cerrados where periodo=(v_plan->>'periodo')::date)
  then raise exception 'El mes comercial ya esta sellado'; end if;
  -- Bloqueo acotado y orden común para las filas exactas del manifiesto.
  perform l.id from crm.leads l where l.id in
    (select (f->>'lead_id')::uuid from jsonb_array_elements(v_plan->'filas') f)
    order by l.id for update nowait;

  select jsonb_build_object(
    'contratos',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from public.contratos t),
    'cuotas',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from public.cronograma_pagos t),
    'externos',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from crm.cierres_externos t),
    'cartera',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from crm.operaciones_cartera t),
    'episodios',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from crm.lead_asignaciones t),
    'fotos',(select md5(string_agg(to_jsonb(t)::text,'' order by periodo,vendedor_id)) from crm.cierre_mes_vendedor t)
  ) into v_antes;

  for v_fila in select f from jsonb_array_elements(v_plan->'filas') f order by f->>'lead_id' loop
    if coalesce(v_fila->>'nuevo','') not in ('landing','formulario')
       or coalesce(v_fila->>'evidencia','') not in ('confirmacion','asignacion_administrativa')
       or coalesce(v_fila->>'fuente_tipo','') not in ('contrato','cierre_externo')
    then raise exception 'Canal, evidencia o fuente invalida'; end if;
    select * into strict v_lead from crm.leads where id=(v_fila->>'lead_id')::uuid;
    if v_lead.etapa <> 'convertido' or v_lead.vendedor_id is distinct from (v_fila->>'vendedor_id')::uuid
    then raise exception 'El lead cambio de estado o responsable'; end if;
    if v_fila->>'fuente_tipo'='contrato' then
      select c.fecha_cierre_comercial,c.capital,c.moneda,c.analista_cierre_id,
        c.cliente_id=v_lead.perfil_id and not c.es_demo
      into v_fecha,v_capital,v_moneda,v_vendedor,v_pertenece
      from public.contratos c where c.id=(v_fila->>'fuente_id')::uuid;
    else
      select coalesce(c.fecha_comercial,(c.creado_en at time zone 'America/Lima')::date),
        c.monto,c.moneda,c.vendedor_id,c.lead_id=v_lead.id and c.anulado_en is null
      into v_fecha,v_capital,v_moneda,v_vendedor,v_pertenece
      from crm.cierres_externos c where c.id=(v_fila->>'fuente_id')::uuid;
    end if;
    if not found or v_pertenece is distinct from true
       or v_capital is distinct from (v_fila->>'capital')::numeric
       or v_moneda is distinct from v_fila->>'moneda'
       or v_vendedor is distinct from (v_fila->>'vendedor_id')::uuid
       or date_trunc('month',v_fecha)::date is distinct from (v_plan->>'periodo')::date
    then raise exception 'Fuente, importe, moneda, periodo o atribucion divergente'; end if;
    if v_lead.origen=v_fila->>'nuevo' and exists(select 1 from public.audit_log a
      where a.tabla='crm.leads.origen_confirmado' and a.fila_id=v_lead.id::text
        and a.data_despues->>'batch'=v_batch::text and a.data_despues->>'origen'=v_fila->>'nuevo'
        and a.data_despues->>'fuente_id'=v_fila->>'fuente_id'
        and a.data_despues->>'evidencia'=v_fila->>'evidencia')
    then continue; end if;
    if v_lead.origen <> 'otro' then raise exception 'El origen ya no es Otro'; end if;
    v_nota := case when v_fila->>'evidencia'='confirmacion'
      then 'Origen confirmado por Gerencia: '
      else 'Origen asignado administrativamente por Gerencia; canal historico no acreditado: ' end
      ||case when v_fila->>'nuevo'='formulario' then 'Formulario' else 'Landing' end
      ||' ('||to_char(current_date,'DD/MM/YYYY')||').';
    perform set_config('crm.op_privilegiada','on',true);
    update crm.leads set origen=v_fila->>'nuevo',
      nota=concat_ws(E'\n',nullif(v_lead.nota,''),v_nota)
      where id=v_lead.id;
    perform set_config('crm.op_privilegiada',coalesce(v_prev,'off'),true);
    if (select (to_jsonb(l)-array['origen','nota','actualizado_en'])
      from crm.leads l where l.id=v_lead.id) is distinct from
      (to_jsonb(v_lead)-array['origen','nota','actualizado_en'])
    then raise exception 'La correccion modifico otros campos del lead'; end if;
    insert into public.audit_log(tabla,operacion,fila_id,usuario_id,data_antes,data_despues)
    values('crm.leads.origen_confirmado','UPDATE',v_lead.id::text,v_uid,
      jsonb_build_object('origen',v_lead.origen),
      jsonb_build_object('origen',v_fila->>'nuevo','batch',v_batch,
        'evidencia',v_fila->>'evidencia','motivo',v_plan->>'motivo',
        'ejecutor','Codex mediante mantenimiento SQL autorizado',
        'fuente_tipo',v_fila->>'fuente_tipo','fuente_id',v_fila->>'fuente_id'));
    v_cambiados := v_cambiados+1;
  end loop;

  select jsonb_build_object(
    'contratos',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from public.contratos t),
    'cuotas',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from public.cronograma_pagos t),
    'externos',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from crm.cierres_externos t),
    'cartera',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from crm.operaciones_cartera t),
    'episodios',(select md5(string_agg(to_jsonb(t)::text,'' order by id)) from crm.lead_asignaciones t),
    'fotos',(select md5(string_agg(to_jsonb(t)::text,'' order by periodo,vendedor_id)) from crm.cierre_mes_vendedor t)
  ) into v_despues;
  if v_antes is distinct from v_despues then
    raise exception 'Cambio financiero, de episodios o de fotos: se revierte el lote'; end if;
  perform set_config('crm.correccion_origen_resultado',jsonb_build_object(
    'cambiados',v_cambiados,'total',v_total,'preservacion','PASS','batch',v_batch)::text,true);
end;
$corregir$;
