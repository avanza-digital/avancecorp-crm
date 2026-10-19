-- Alcance aprobado: todas las primeras conversiones pendientes, nuevas y antiguas.
-- La fecha pública cohorte_desde se conserva por compatibilidad: indica cuándo
-- comienza la exigencia global; ya no compara el inicio/creación de un lead.
-- Instalación previa a la primera activación. No cambia modo, datos ni evidencia.
-- Reversión operativa: RPC gerencial a observacion/apagado, conservando auditoría.
begin;
set local search_path='';
set local quote_all_identifiers=off;
do $$
declare r record;
begin
  for r in select * from (values
    ('private.recorrido_exigir(uuid,text)','41cbc0745b546990ae97e0e91bfa3fb6'),
    ('private.recorrido_insert_convertido_guard()','413d9521ba125ae51714081a2986c151'),
    ('crm.recorrido_leads_fn(uuid[])','eebb31ea593b765e464e79d824c65d78'),
    ('crm.recorrido_configurar_fn(text,text,integer,timestamptz)','07db736b5d832cecd18952648dcf575d'))
    as esperado(firma,huella) loop
    if to_regprocedure(r.firma) is null or md5(pg_get_functiondef(to_regprocedure(r.firma)))<>r.huella then
      raise exception 'El contrato del recorrido cambio: revisar % antes de ampliar el alcance',r.firma using errcode='55000';
    end if;
  end loop;
  -- Serializa esta instalación con la primera activación de Gerencia. El lock
  -- se conserva hasta COMMIT: no cambia el alcance de un control ya activado.
  perform 1 from crm.recorrido_control where id for update;
  if not exists(select 1 from crm.recorrido_control where id and modo in ('observacion','apagado') and cohorte_desde is null) then
    raise exception 'El alcance integral se instala antes de la primera activacion; revisar el estado vigente' using errcode='55000';
  end if;
  perform private.assert_sla_nucleo();
end $$;

create or replace function private.recorrido_exigir(p_lead uuid,p_paso text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare v_l crm.leads%rowtype;v_c crm.recorrido_control%rowtype;v_r jsonb;v_exigible boolean;
  v_tarea uuid;v_asistencia uuid;v_identidad_desde timestamptz;
begin
  -- Las operaciones de clientes existentes conservan el contexto canónico actual.
  if p_lead is null then return null;end if;
  -- Los callers conservan autorización/identidad. El lock protege hechos y
  -- ciclo sin bloquear FK que solo hacen referencia al lead. NOWAIT evita
  -- invertir esperas con rutas que llegaron por otra fila.
  select * into strict v_l from crm.leads where id=p_lead for no key update nowait;
  select * into strict v_c from crm.recorrido_control where id for share;
  if v_c.modo='exigir' and current_setting('transaction_isolation')<>'read committed' then
    raise exception 'Reintenta la operación en una transacción de lectura vigente' using errcode='55000';
  end if;
  select resultado into strict v_r from private.recorrido_evaluar(array[p_lead]);
  v_exigible:=coalesce(v_c.modo='exigir'
    and clock_timestamp()>=v_c.cohorte_desde
    and (v_r->>'aplica')::boolean,false);
  if v_exigible and not coalesce((v_r->>'habilita_conversion')::boolean,false) then
    raise exception using errcode='P0409',
      message='Antes de convertir, registra que asistió a su cita y que la entrevista se realizó, con su resultado. Revisa los pasos en la ficha del lead.',
      detail=jsonb_build_object('regla','recorrido_lead','paso',p_paso,'lead_id',p_lead,
        'ciclo_n',v_l.ciclo_actual,'pendiente',v_r->>'pendiente','revision',v_c.revision)::text;
  end if;
  -- Fotografía de LA pareja que acreditó la entrevista, no la última asistencia
  -- de otra cita del mismo lead. En observación puede quedar incompleta.
  v_tarea:=coalesce((v_r#>>'{evidencias,entrevista_tarea_id}')::uuid,
    (v_r#>>'{evidencias,asistencia_tarea_id}')::uuid);
  if v_tarea is not null then
    select resultado_actividad_id into v_asistencia from crm.tareas where id=v_tarea and lead_id=p_lead;
  end if;
  select min(creado_en) into v_identidad_desde from crm.inversionista_leads
    where lead_id=p_lead and inversionista_id=v_l.inversionista_id and rol='canonico';
  return jsonb_build_object('version',1,'lead_id',p_lead,'ciclo_n',v_l.ciclo_actual,
    'ciclo_inicio',v_r->'ciclo_inicio','modo',v_c.modo,'revision',v_c.revision,
    'cohorte_desde',v_c.cohorte_desde,'alcance','primeras_conversiones_pendientes',
    'exigible',v_exigible,'estado',v_r->>'estado',
    'verificado_en',clock_timestamp(),'identidad_vinculada_en',v_identidad_desde,
    'asistencia_tarea_id',v_tarea,'asistencia_id',v_asistencia,
    'entrevista_tarea_id',v_r#>'{evidencias,entrevista_tarea_id}');
end $$;

create or replace function private.recorrido_insert_convertido_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_c crm.recorrido_control%rowtype;
begin
  select * into strict v_c from crm.recorrido_control where id for share;
  -- Un INSERT terminal no puede tener asistencia y entrevista de su nuevo ciclo.
  -- La antigüedad declarada nunca excluye una primera conversión pendiente.
  if v_c.modo='exigir' and clock_timestamp()>=v_c.cohorte_desde then
    raise exception 'Registra primero el lead, su asistencia y entrevista; después confirma la inversión'
      using errcode='P0409';
  end if;
  return new;
end $$;

create or replace function crm.recorrido_configurar_fn(p_modo text,p_motivo text,p_revision integer,p_cohorte_desde timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_control crm.recorrido_control%rowtype;
  v_writer text:=coalesce(current_setting('crm.recorrido_control_writer',true),'off');
begin
  if not private.es_gerencia_crm_activa() then raise exception 'No autorizado' using errcode='42501'; end if;
  if p_modo is null or p_modo not in ('apagado','observacion','exigir')
    or p_motivo is null or length(btrim(p_motivo)) not between 8 and 1000
    or p_revision is null or (p_cohorte_desde is not null and not isfinite(p_cohorte_desde)) then
    raise exception 'Indica modo, motivo y revision validos' using errcode='22023';
  end if;
  select * into strict v_control from crm.recorrido_control where id for update;
  if v_control.revision<>p_revision then raise exception 'El modo cambio; consulta de nuevo' using errcode='40001'; end if;
  if v_control.cohorte_desde is not null and p_cohorte_desde is not null and p_cohorte_desde<>v_control.cohorte_desde then
    raise exception 'El corte de activacion no se reinicia' using errcode='22023';
  end if;
  if v_control.cohorte_desde is null and p_cohorte_desde is not null and p_cohorte_desde<clock_timestamp() then
    raise exception 'La fecha inicial de exigencia no puede estar en el pasado' using errcode='22023';
  end if;
  if v_control.cohorte_desde is null and p_cohorte_desde>clock_timestamp()+interval '24 hours' then
    raise exception 'Programa la activacion dentro de las proximas 24 horas' using errcode='22023';
  end if;
  perform set_config('crm.recorrido_control_writer','on',true);
  update crm.recorrido_control set modo=p_modo, motivo=btrim(p_motivo), revision=revision+1,
    cohorte_desde=coalesce(cohorte_desde,p_cohorte_desde,case when p_modo='exigir' then clock_timestamp() end),
    actualizado_por=(select auth.uid()),actualizado_en=clock_timestamp()
    where id returning * into v_control;
  perform set_config('crm.recorrido_control_writer',v_writer,true);
  return to_jsonb(v_control)-'id';
end $$;

create or replace function crm.recorrido_leads_fn(p_lead_ids uuid[]) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_amb record;v_ids uuid[];v_filas jsonb;v_control crm.recorrido_control%rowtype;
begin
  select * into strict v_amb from private.sla_operacion_ambito(p_lead_ids,false);
  if p_lead_ids is null or cardinality(p_lead_ids)>100 then
    raise exception 'Consulta entre cero y cien leads por lote' using errcode='22023';end if;
  select array_agg(l.id) into v_ids from crm.leads l where l.id=any(p_lead_ids) and l.activo
    and (v_amb.es_global or l.vendedor_id=any(v_amb.visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id=any(v_amb.visibles)));
  select * into strict v_control from crm.recorrido_control where id;
  select coalesce(jsonb_agg(e.resultado||jsonb_build_object('exigible',coalesce(v_control.modo='exigir'
      and clock_timestamp()>=v_control.cohorte_desde
      and (e.resultado->>'aplica')::boolean,false)) order by e.lead_id),'[]'::jsonb)
    into v_filas from private.recorrido_evaluar(coalesce(v_ids,'{}'::uuid[])) e join crm.leads l on l.id=e.lead_id;
  return jsonb_build_object('version',1,'modo',v_control.modo,'revision',v_control.revision,
    'cohorte_desde',v_control.cohorte_desde,'filas',v_filas);
end $$;

comment on column crm.recorrido_control.cohorte_desde is 'Inicio inmutable de la primera exigencia global. No exime leads o ciclos anteriores; nombre conservado por compatibilidad con la API publicada.';
comment on function private.recorrido_exigir(uuid,text) is 'Revalida asistencia y entrevista de la misma cita y ciclo en toda primera conversion pendiente, sin exencion por antiguedad. Preserva snapshot y locks del flujo financiero.';
comment on function private.recorrido_insert_convertido_guard() is 'Impide insertar directamente un convertido durante la exigencia global, sin excepcion por creado_en.';
comment on function crm.recorrido_leads_fn(uuid[]) is 'Lectura autorizada de hechos actuales: exigible coincide con el control de todas las primeras conversiones pendientes desde la fecha de activacion.';
comment on function crm.recorrido_configurar_fn(text,text,integer,timestamptz) is 'Gerencia activa, observa o apaga la exigencia con revision auditada. La fecha marca inicio global, no antiguedad de leads; no se reinicia.';
revoke all on function private.recorrido_exigir(uuid,text),private.recorrido_insert_convertido_guard() from public,anon,authenticated,service_role;
revoke all on function crm.recorrido_leads_fn(uuid[]),crm.recorrido_configurar_fn(text,text,integer,timestamptz) from public,anon,authenticated,service_role;
grant execute on function crm.recorrido_leads_fn(uuid[]),crm.recorrido_configurar_fn(text,text,integer,timestamptz) to authenticated;
select private.assert_sla_nucleo();
notify pgrst,'reload schema';
commit;
