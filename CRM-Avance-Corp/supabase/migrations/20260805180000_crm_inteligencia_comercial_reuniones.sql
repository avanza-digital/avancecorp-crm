-- Inteligencia Comercial de Gerencia + reuniones auditables.
--
-- Objetivos:
--   1. crm.tareas sigue siendo la UNICA agenda; una reunion gana modalidad,
--      lugar/enlace, resultado comercial y motivo de no realizacion.
--   2. Reprogramar una reunion ya no pisa la fecha original: cierra la fila
--      como reprogramada y crea una nueva, enlazada por reagendada_de.
--   3. Gerencia conserva lectura global, pero no opera leads/tareas/actividades.
--      Sus dos escrituras deliberadas siguen siendo fijar_objetivos y
--      actualizar_capacidad_leads_objetivo.
--   4. Dos RPC agregadas entregan conversiones por cohorte/origen y efectividad
--      de reuniones por modalidad/origen/responsable, sin exponer PII.

begin;
set local lock_timeout = '10s';

-- ── 1. Contrato de reuniones sobre crm.tareas ───────────────────────────────

alter table crm.tareas
  add column modalidad_reunion text,
  add column ubicacion_reunion text,
  add column enlace_reunion text,
  add column resultado_reunion text,
  add column motivo_no_realizada text,
  add column detalle_cierre_reunion text;

-- Historia honesta: lo anterior a esta funcionalidad no se adivina.
update crm.tareas
   set modalidad_reunion = 'sin_clasificar',
       resultado_reunion = case
         when estado = 'completada' then 'sin_clasificar'
         else null
       end,
       motivo_no_realizada = case
         when estado = 'no_show' then 'cliente_no_asistio'
         when estado = 'cancelada' then 'otro'
         else null
       end,
       detalle_cierre_reunion = case
         when estado = 'cancelada' then 'Historica: motivo estructurado no disponible'
         else null
       end
 where tipo = 'reunion';

alter table crm.tareas drop constraint tareas_estado_valido;
alter table crm.tareas
  add constraint tareas_estado_valido
  check (estado in ('pendiente','completada','cancelada','no_show','reprogramada'));

alter table crm.tareas
  add constraint tareas_modalidad_reunion_valida
  check (
    (tipo = 'reunion' and modalidad_reunion in ('presencial','virtual','sin_clasificar'))
    or
    (tipo <> 'reunion' and modalidad_reunion is null)
  ),
  add constraint tareas_ubicacion_reunion_valida
  check (
    (tipo = 'reunion' and (ubicacion_reunion is null or length(btrim(ubicacion_reunion)) between 1 and 300))
    or (tipo <> 'reunion' and ubicacion_reunion is null)
  ),
  add constraint tareas_enlace_reunion_valido
  check (
    (tipo = 'reunion' and (
      enlace_reunion is null
      or (
        length(enlace_reunion) <= 1000
        and enlace_reunion ~* '^https://[a-z0-9.-]+(:[0-9]{1,5})?([/?#][^[:space:]]*)?$'
      )
    ))
    or (tipo <> 'reunion' and enlace_reunion is null)
  ),
  add constraint tareas_destino_reunion_coherente
  check (
    (tipo <> 'reunion' and ubicacion_reunion is null and enlace_reunion is null)
    or
    (tipo = 'reunion' and (
      (modalidad_reunion = 'presencial' and ubicacion_reunion is not null and enlace_reunion is null)
      or (modalidad_reunion = 'virtual' and ubicacion_reunion is null and enlace_reunion is not null)
      or (modalidad_reunion = 'sin_clasificar' and ubicacion_reunion is null and enlace_reunion is null)
    ))
  ),
  add constraint tareas_resultado_reunion_valido
  check (
    resultado_reunion is null
    or resultado_reunion in (
      'interesado','seguimiento','propuesta','inicia_registro',
      'no_interesado','sin_clasificar'
    )
  ),
  add constraint tareas_motivo_no_realizada_valido
  check (
    motivo_no_realizada is null
    or motivo_no_realizada in (
      'cliente_no_asistio','cancelada_cliente','cancelada_empresa',
      'reprogramada','otro'
    )
  ),
  add constraint tareas_detalle_cierre_reunion_valido
  check (detalle_cierre_reunion is null or length(detalle_cierre_reunion) <= 2000),
  add constraint tareas_cierre_reunion_coherente
  check (
    (tipo <> 'reunion' and resultado_reunion is null
      and motivo_no_realizada is null and detalle_cierre_reunion is null)
    or
    (tipo = 'reunion' and (
      (estado = 'pendiente' and resultado_reunion is null and motivo_no_realizada is null)
      or (estado = 'completada' and resultado_reunion is not null and motivo_no_realizada is null)
      or (estado = 'no_show' and resultado_reunion is null and motivo_no_realizada = 'cliente_no_asistio')
      or (estado = 'cancelada' and resultado_reunion is null
          and motivo_no_realizada in ('cancelada_cliente','cancelada_empresa','otro')
          and (
            motivo_no_realizada <> 'otro'
            or nullif(btrim(coalesce(detalle_cierre_reunion, '')), '') is not null
          ))
      or (estado = 'reprogramada' and resultado_reunion is null
          and motivo_no_realizada = 'reprogramada')
    ))
  );

comment on column crm.tareas.modalidad_reunion is
  'Modalidad de la reunion: presencial, virtual o sin_clasificar para historia anterior a 2026-08-05.';
comment on column crm.tareas.resultado_reunion is
  'Resultado comercial obligatorio al marcar una reunion realizada. El contrato/capital real se mide desde crm.leads y public.contratos, no desde esta declaracion.';
comment on column crm.tareas.motivo_no_realizada is
  'Motivo estructurado para no_show, cancelacion humana o reprogramacion.';
comment on column crm.tareas.detalle_cierre_reunion is
  'Contexto libre del cierre; no sustituye el estado ni los catalogos estructurados.';

create index tareas_reuniones_periodo_idx
  on crm.tareas (vence_en, vendedor_id)
  where tipo = 'reunion';

-- ── 2. Sellos de integridad de crm.tareas ───────────────────────────────────

create or replace function private.trg_tareas_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lead crm.leads%rowtype;
begin
  if new.lead_id is not null then
    select * into v_lead from crm.leads where id = new.lead_id;
    if not found then
      raise exception 'El lead de la tarea no existe';
    end if;
    if v_lead.activo = false or v_lead.etapa in ('convertido','descartado') then
      raise exception 'El lead esta cerrado: no admite tareas nuevas';
    end if;
    new.vendedor_id := v_lead.vendedor_id;
    new.asignado_supervisor_id := v_lead.asignado_supervisor_id;
  end if;

  if new.estado <> 'pendiente'
     and coalesce(current_setting('crm.op_tarea', true), 'off') <> 'on' then
    raise exception 'Una tarea nace pendiente; los cierres van por una RPC de agenda'
      using errcode = '22023';
  end if;

  if new.tipo = 'reunion' then
    -- Compatibilidad de despliegue: el bundle anterior puede crear una reunion
    -- durante la ventana migracion->front. Queda visible como sin clasificar,
    -- nunca se inventa presencial/virtual.
    new.modalidad_reunion := coalesce(new.modalidad_reunion, 'sin_clasificar');
  else
    new.modalidad_reunion := null;
    new.ubicacion_reunion := null;
    new.enlace_reunion := null;
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;

  if new.estado = 'pendiente' then
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;

  new.cancelada_por := case when new.estado = 'cancelada' then 'sistema' else null end;
  new.cancelada_por_id := null;
  return new;
end;
$$;

create or replace function private.trg_tareas_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_op      boolean := coalesce(current_setting('crm.op_tarea', true), 'off') = 'on';
  v_sistema boolean := coalesce(current_setting('crm.cancela_sistema', true), 'off') = 'on';
  v_uid     uuid    := (select auth.uid());
  v_asesor  boolean;
  v_cambio_vencimiento boolean;
begin
  v_cambio_vencimiento := new.vence_en is distinct from old.vence_en;

  if old.estado <> 'pendiente' then
    raise exception 'La tarea ya esta cerrada; una reunion reprogramada conserva su historia'
      using errcode = '22023';
  end if;
  if new.estado in ('completada','no_show','reprogramada') and not v_op then
    raise exception 'Cerrar o reprogramar una reunion va por la RPC de agenda'
      using errcode = '22023';
  end if;
  if new.estado = 'cancelada' and not v_op and not v_sistema and v_uid is not null then
    raise exception 'Anular una tarea va por crm.cerrar_tarea()'
      using errcode = '22023';
  end if;
  if new.resultado_actividad_id is distinct from old.resultado_actividad_id and not v_op then
    raise exception 'El resultado lo escribe la RPC de cierre'
      using errcode = '22023';
  end if;
  if (
    new.resultado_reunion is distinct from old.resultado_reunion
    or new.motivo_no_realizada is distinct from old.motivo_no_realizada
    or new.detalle_cierre_reunion is distinct from old.detalle_cierre_reunion
  ) and not v_op then
    raise exception 'El resultado de la reunion lo escribe la RPC de cierre'
      using errcode = '22023';
  end if;
  if old.tipo = 'reunion' and v_cambio_vencimiento and not v_op then
    raise exception 'Reprogramar una reunion va por crm.reprogramar_reunion()'
      using errcode = '22023';
  end if;

  if new.estado = 'cancelada' then
    v_asesor := (not v_sistema) and v_op and v_uid is not null;
    new.cancelada_por    := case when v_asesor then 'asesor' else 'sistema' end;
    new.cancelada_por_id := case when v_asesor then v_uid else null end;
  else
    new.cancelada_por    := old.cancelada_por;
    new.cancelada_por_id := old.cancelada_por_id;
  end if;

  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.lead_id := old.lead_id;
  new.perfil_id := old.perfil_id;
  new.reagendada_de := old.reagendada_de;
  new.tipo := old.tipo;
  new.modalidad_reunion := old.modalidad_reunion;
  new.ubicacion_reunion := old.ubicacion_reunion;
  new.enlace_reunion := old.enlace_reunion;

  if v_cambio_vencimiento then
    new.reprogramaciones := old.reprogramaciones + 1;
  else
    new.reprogramaciones := old.reprogramaciones;
  end if;
  return new;
end;
$$;

-- ── 3. Gerencia: inteligencia completa, operacion bloqueada ─────────────────

create or replace function private.trg_gerencia_inteligencia_solo_lectura()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is not null and private.rol_crm(v_uid) = 'gerencia' then
    raise exception 'Gerencia opera en modo de inteligencia comercial; esta accion corresponde a Supervisión o Ventas'
      using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.trg_gerencia_inteligencia_solo_lectura()
  from public, anon, authenticated, service_role;

create trigger trg_00_gerencia_solo_lectura
before insert or update or delete on crm.leads
for each row execute function private.trg_gerencia_inteligencia_solo_lectura();
create trigger trg_00_gerencia_solo_lectura
before insert or update or delete on crm.tareas
for each row execute function private.trg_gerencia_inteligencia_solo_lectura();
create trigger trg_00_gerencia_solo_lectura
before insert or update or delete on crm.actividades
for each row execute function private.trg_gerencia_inteligencia_solo_lectura();

-- Las policies reflejan la misma frontera. Los triggers anteriores cierran
-- ademas las RPC SECURITY DEFINER que de otro modo saltarian RLS.
drop policy if exists leads_update on crm.leads;
create policy leads_update on crm.leads
  for update to authenticated
  using (
    activo = true and (
      vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (vendedor_id is null and asignado_supervisor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      ))
    )
  )
  with check (
    (vendedor_id is null or vendedor_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    ))
    and (asignado_supervisor_id is null or asignado_supervisor_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    ))
    and (activo = true or private.rol_crm((select auth.uid())) = 'supervisor')
  );

drop policy if exists actividades_insert on crm.actividades;
create policy actividades_insert on crm.actividades
  for insert to authenticated
  with check (
    creado_por = (select auth.uid())
    and tipo not in ('cambio_etapa','reasignacion','conversion')
    and exists (
      select 1 from crm.leads l
      where l.id = actividades.lead_id
        and l.activo = true
        and (
          l.vendedor_id = (select auth.uid())
          or (
            private.rol_crm((select auth.uid())) = 'supervisor'
            and (
              l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
              or (l.vendedor_id is null and l.asignado_supervisor_id in (
                select private.vendedor_ids_visibles((select auth.uid()))
              ))
            )
          )
        )
    )
  );

drop policy if exists tareas_insert on crm.tareas;
create policy tareas_insert on crm.tareas
  for insert to authenticated
  with check (
    activo = true
    and creado_por = (select auth.uid())
    and private.rol_crm((select auth.uid())) in ('vendedor','supervisor')
    and (
      vendedor_id = (select auth.uid())
      or (
        private.rol_crm((select auth.uid())) = 'supervisor'
        and (vendedor_id is null or vendedor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        ))
      )
    )
    and (asignado_supervisor_id is null or asignado_supervisor_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    ))
    and (lead_id is null or exists (select 1 from crm.leads l where l.id = lead_id))
  );

drop policy if exists tareas_update on crm.tareas;
create policy tareas_update on crm.tareas
  for update to authenticated
  using (
    activo = true and (
      vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (vendedor_id is null and asignado_supervisor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      ))
    )
  )
  with check (
    (vendedor_id is null or vendedor_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    ))
    and (asignado_supervisor_id is null or asignado_supervisor_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    ))
    and (activo = true or private.rol_crm((select auth.uid())) = 'supervisor')
  );

-- ── 4. Helper privado para la siguiente accion ──────────────────────────────

create or replace function private.crear_siguiente_tarea(
  p_anterior crm.tareas,
  p_siguiente jsonb,
  p_reagendada_de uuid,
  p_uid uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tipo text;
  v_titulo text;
  v_vence timestamptz;
  v_duracion smallint;
  v_modalidad text;
begin
  if p_siguiente is null then return null; end if;
  v_tipo := p_siguiente->>'tipo';
  v_titulo := btrim(coalesce(p_siguiente->>'titulo',''));
  begin
    v_vence := (p_siguiente->>'vence_en')::timestamptz;
    v_id := nullif(p_siguiente->>'id','')::uuid;
  exception when others then
    raise exception 'Fecha o identificador invalido en la tarea siguiente';
  end;
  if p_siguiente->>'duracion_min' is not null then
    v_duracion := (p_siguiente->>'duracion_min')::smallint;
  end if;
  if v_tipo is null or v_tipo not in ('llamada','whatsapp','reunion','tarea')
     or v_titulo = '' or v_vence is null then
    raise exception 'La tarea siguiente exige tipo, titulo y vence_en validos';
  end if;
  if v_tipo = 'reunion' then
    v_modalidad := coalesce(nullif(p_siguiente->>'modalidad_reunion',''), 'sin_clasificar');
  end if;

  insert into crm.tareas (
    id, lead_id, perfil_id, tipo, titulo, nota, vence_en, duracion_min,
    modalidad_reunion, ubicacion_reunion, enlace_reunion,
    reagendada_de, creado_por
  ) values (
    coalesce(v_id, gen_random_uuid()), p_anterior.lead_id, p_anterior.perfil_id,
    v_tipo, v_titulo, nullif(btrim(coalesce(p_siguiente->>'nota','')), ''),
    v_vence, v_duracion, v_modalidad,
    case when v_tipo = 'reunion' then nullif(btrim(coalesce(p_siguiente->>'ubicacion_reunion','')), '') end,
    case when v_tipo = 'reunion' then nullif(btrim(coalesce(p_siguiente->>'enlace_reunion','')), '') end,
    p_reagendada_de, p_uid
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function private.crear_siguiente_tarea(crm.tareas, jsonb, uuid, uuid)
  from public, anon, authenticated, service_role;

-- ── 5. Cierre general compatible + cierre estructurado de reunion ───────────

create or replace function crm.cerrar_tarea(
  p_tarea_id uuid,
  p_estado text,
  p_resultado_tipo text default null,
  p_resultado_detalle text default null,
  p_siguiente jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_tarea crm.tareas%rowtype;
  v_act_id uuid;
  v_sig_id uuid;
  v_retroceso text;
begin
  if v_uid is null or v_rol not in ('vendedor','supervisor') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estado is null or p_estado not in ('completada','no_show','cancelada') then
    raise exception 'Estado de cierre invalido' using errcode = '22023';
  end if;

  perform 1 from crm.leads
   where id = (
     select t.lead_id from crm.tareas t
     where t.id = p_tarea_id and t.activo and t.estado = 'pendiente'
       and (
         t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
         or (t.vendedor_id is null and t.asignado_supervisor_id in (
           select private.vendedor_ids_visibles(v_uid)
         ))
       )
   ) for no key update;

  select * into v_tarea from crm.tareas t
   where t.id = p_tarea_id and t.activo and t.estado = 'pendiente'
     and (
       t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
       or (t.vendedor_id is null and t.asignado_supervisor_id in (
         select private.vendedor_ids_visibles(v_uid)
       ))
     )
   for update;
  if not found then
    raise exception 'Tarea no encontrada, cerrada o fuera de tu ambito';
  end if;

  if p_resultado_tipo is not null then
    if v_tarea.lead_id is null then
      raise exception 'Una tarea de cliente no registra actividad de lead';
    end if;
    if p_resultado_tipo not in (
      'llamada_realizada','llamada_no_contestada','whatsapp_enviado',
      'whatsapp_recibido','reunion_realizada','nota'
    ) then
      raise exception 'Tipo de resultado invalido';
    end if;
  end if;
  if v_tarea.tipo = 'llamada' and p_estado = 'completada' and p_resultado_tipo is null then
    raise exception 'Registra el resultado de la llamada (contesto / no contesto)';
  end if;

  if p_resultado_tipo is not null then
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (
      v_tarea.lead_id, p_resultado_tipo,
      nullif(btrim(coalesce(p_resultado_detalle,'')), ''), v_uid
    ) returning id into v_act_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas set
    estado = p_estado,
    resultado_actividad_id = v_act_id,
    -- Compatibilidad del bundle anterior: una reunion cerrada por esta RPC no
    -- pierde coherencia; queda explicitamente sin clasificar.
    resultado_reunion = case
      when v_tarea.tipo = 'reunion' and p_estado = 'completada' then 'sin_clasificar'
      else null
    end,
    motivo_no_realizada = case
      when v_tarea.tipo = 'reunion' and p_estado = 'no_show' then 'cliente_no_asistio'
      when v_tarea.tipo = 'reunion' and p_estado = 'cancelada' then 'otro'
      else null
    end,
    detalle_cierre_reunion = case
      when v_tarea.tipo = 'reunion' and p_estado = 'cancelada'
        then coalesce(
          nullif(btrim(coalesce(p_resultado_detalle,'')), ''),
          'Compatibilidad: motivo no estructurado por cliente anterior'
        )
      when v_tarea.tipo = 'reunion' then nullif(btrim(coalesce(p_resultado_detalle,'')), '')
      else null
    end
  where id = p_tarea_id;
  perform set_config('crm.op_tarea', 'off', true);

  v_sig_id := private.crear_siguiente_tarea(
    v_tarea, p_siguiente,
    case when p_estado = 'no_show' then p_tarea_id else null end,
    v_uid
  );

  if p_estado = 'cancelada' and v_tarea.tipo = 'reunion' and v_tarea.lead_id is not null then
    v_retroceso := private.retroceso_por_anular_reunion(v_tarea.lead_id, p_tarea_id, v_uid);
  end if;

  return jsonb_build_object(
    'ok', true, 'tarea_id', p_tarea_id, 'actividad_id', v_act_id,
    'siguiente_id', v_sig_id, 'retroceso', v_retroceso
  );
end;
$$;

create or replace function crm.cerrar_reunion(
  p_tarea_id uuid,
  p_estado text,
  p_resultado_reunion text default null,
  p_motivo_no_realizada text default null,
  p_detalle text default null,
  p_siguiente jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_tarea crm.tareas%rowtype;
  v_act_id uuid;
  v_sig_id uuid;
  v_retroceso text;
begin
  if v_uid is null or v_rol not in ('vendedor','supervisor') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estado is null or p_estado not in ('completada','no_show','cancelada') then
    raise exception 'Estado de reunion invalido' using errcode = '22023';
  end if;
  if p_estado = 'completada' and (
    p_resultado_reunion is null
    or p_resultado_reunion not in (
      'interesado','seguimiento','propuesta','inicia_registro','no_interesado'
    )
  ) then
    raise exception 'Registra el resultado comercial de la reunion' using errcode = '22023';
  end if;
  if p_estado = 'no_show' then
    p_motivo_no_realizada := 'cliente_no_asistio';
  elsif p_estado = 'cancelada' and (
    p_motivo_no_realizada is null
    or p_motivo_no_realizada not in ('cancelada_cliente','cancelada_empresa','otro')
  ) then
    raise exception 'Registra el motivo de cancelacion' using errcode = '22023';
  end if;
  if p_estado = 'cancelada' and p_motivo_no_realizada = 'otro'
     and nullif(btrim(coalesce(p_detalle, '')), '') is null then
    raise exception 'Describe el otro motivo de cancelacion' using errcode = '22023';
  end if;

  perform 1 from crm.leads
   where id = (
     select t.lead_id from crm.tareas t
     where t.id = p_tarea_id and t.tipo = 'reunion'
       and t.activo and t.estado = 'pendiente'
       and (
         t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
         or (t.vendedor_id is null and t.asignado_supervisor_id in (
           select private.vendedor_ids_visibles(v_uid)
         ))
       )
   ) for no key update;

  select * into v_tarea from crm.tareas t
   where t.id = p_tarea_id and t.tipo = 'reunion'
     and t.activo and t.estado = 'pendiente'
     and (
       t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
       or (t.vendedor_id is null and t.asignado_supervisor_id in (
         select private.vendedor_ids_visibles(v_uid)
       ))
     )
   for update;
  if not found then
    raise exception 'Reunion no encontrada, cerrada o fuera de tu ambito';
  end if;

  if p_estado = 'completada' and v_tarea.lead_id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (
      v_tarea.lead_id, 'reunion_realizada', nullif(btrim(coalesce(p_detalle,'')), ''),
      jsonb_build_object(
        'modalidad', v_tarea.modalidad_reunion,
        'resultado_reunion', p_resultado_reunion,
        'tarea_id', v_tarea.id
      ),
      v_uid
    ) returning id into v_act_id;
  elsif p_estado = 'no_show' and v_tarea.lead_id is not null and btrim(coalesce(p_detalle,'')) <> '' then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (
      v_tarea.lead_id, 'nota', btrim(p_detalle),
      jsonb_build_object('evento', 'reunion_no_show', 'tarea_id', v_tarea.id), v_uid
    ) returning id into v_act_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas set
    estado = p_estado,
    resultado_actividad_id = v_act_id,
    resultado_reunion = case when p_estado = 'completada' then p_resultado_reunion end,
    motivo_no_realizada = case when p_estado in ('no_show','cancelada') then p_motivo_no_realizada end,
    detalle_cierre_reunion = nullif(btrim(coalesce(p_detalle,'')), '')
  where id = p_tarea_id;
  perform set_config('crm.op_tarea', 'off', true);

  v_sig_id := private.crear_siguiente_tarea(
    v_tarea, p_siguiente,
    case when p_estado = 'no_show' then p_tarea_id else null end,
    v_uid
  );

  if p_estado = 'cancelada' and v_tarea.lead_id is not null then
    v_retroceso := private.retroceso_por_anular_reunion(v_tarea.lead_id, p_tarea_id, v_uid);
  end if;

  return jsonb_build_object(
    'ok', true, 'tarea_id', p_tarea_id, 'actividad_id', v_act_id,
    'siguiente_id', v_sig_id, 'retroceso', v_retroceso
  );
end;
$$;

create or replace function crm.reprogramar_reunion(
  p_tarea_id uuid,
  p_vence_en timestamptz,
  p_nueva_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_tarea crm.tareas%rowtype;
  v_nueva_id uuid := coalesce(p_nueva_id, gen_random_uuid());
begin
  if v_uid is null or v_rol not in ('vendedor','supervisor') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_vence_en is null
     or p_vence_en < timestamptz '2026-01-01 00:00Z'
     or p_vence_en >= timestamptz '2100-01-01 00:00Z' then
    raise exception 'Fecha de reunion invalida' using errcode = '22023';
  end if;

  perform 1 from crm.leads
   where id = (
     select t.lead_id from crm.tareas t
     where t.id = p_tarea_id and t.tipo = 'reunion'
       and t.activo and t.estado = 'pendiente'
       and (
         t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
         or (t.vendedor_id is null and t.asignado_supervisor_id in (
           select private.vendedor_ids_visibles(v_uid)
         ))
       )
   ) for no key update;

  select * into v_tarea from crm.tareas t
   where t.id = p_tarea_id and t.tipo = 'reunion'
     and t.activo and t.estado = 'pendiente'
     and (
       t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
       or (t.vendedor_id is null and t.asignado_supervisor_id in (
         select private.vendedor_ids_visibles(v_uid)
       ))
     )
   for update;
  if not found then
    raise exception 'Reunion no encontrada, cerrada o fuera de tu ambito';
  end if;
  if p_vence_en = v_tarea.vence_en then
    raise exception 'La nueva fecha debe ser distinta' using errcode = '22023';
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas set
    estado = 'reprogramada',
    motivo_no_realizada = 'reprogramada',
    detalle_cierre_reunion = 'Reprogramada a ' || p_vence_en::text
  where id = p_tarea_id;
  perform set_config('crm.op_tarea', 'off', true);

  insert into crm.tareas (
    id, lead_id, perfil_id, tipo, titulo, nota, vence_en, duracion_min,
    modalidad_reunion, ubicacion_reunion, enlace_reunion,
    reagendada_de, reprogramaciones, creado_por
  ) values (
    v_nueva_id, v_tarea.lead_id, v_tarea.perfil_id, 'reunion',
    v_tarea.titulo, v_tarea.nota, p_vence_en, v_tarea.duracion_min,
    v_tarea.modalidad_reunion, v_tarea.ubicacion_reunion, v_tarea.enlace_reunion,
    v_tarea.id, v_tarea.reprogramaciones + 1, v_uid
  );

  return jsonb_build_object(
    'ok', true, 'tarea_anterior_id', p_tarea_id,
    'tarea_nueva_id', v_nueva_id, 'reprogramaciones', v_tarea.reprogramaciones + 1
  );
end;
$$;

revoke all on function crm.cerrar_reunion(uuid,text,text,text,text,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.cerrar_reunion(uuid,text,text,text,text,jsonb) to authenticated;
revoke all on function crm.reprogramar_reunion(uuid,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.reprogramar_reunion(uuid,timestamptz,uuid) to authenticated;

-- ── 6. Conversión comercial por cohorte y origen ────────────────────────────

create or replace function crm.metricas_conversiones_fn(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
  v_autorizado boolean;
begin
  select exists (
    select 1 from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo and e.rol_crm = 'gerencia'
  ) or private.es_lector_global() into v_autorizado;
  if v_uid is null or not coalesce(v_autorizado, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  with cohorte_base as materialized (
    select l.*, c.capital as capital_contrato, c.moneda as moneda_contrato,
           c.creado_en as contrato_creado_en
    from crm.leads l
    left join public.contratos c on c.id = l.contrato_id
    where l.creado_en >= v_ini and l.creado_en < v_fin
  ),
  senales as materialized (
    select cb.*,
      (cb.vendedor_id is not null or cb.asignado_supervisor_id is not null or exists (
        select 1 from crm.lead_asignaciones la where la.lead_id = cb.id
      )) as h_asignado,
      exists (
        select 1 from crm.actividades a
        where a.lead_id = cb.id and (
          a.tipo in ('llamada_realizada','whatsapp_recibido','reunion_realizada')
          or (a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' in (
            'contactado','reunion_agendada','propuesta_enviada','convertido'
          ))
        )
      ) as h_contacto,
      exists (
        select 1 from crm.tareas t where t.lead_id = cb.id and t.tipo = 'reunion'
      ) or exists (
        select 1 from crm.actividades a where a.lead_id = cb.id
          and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' = 'reunion_agendada'
      ) as h_reunion_agendada,
      exists (
        select 1 from crm.tareas t where t.lead_id = cb.id
          and t.tipo = 'reunion' and t.estado = 'completada'
      ) or exists (
        select 1 from crm.actividades a where a.lead_id = cb.id and a.tipo = 'reunion_realizada'
      ) as h_reunion_realizada,
      exists (
        select 1 from crm.actividades a where a.lead_id = cb.id
          and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' = 'propuesta_enviada'
      ) or cb.etapa = 'propuesta_enviada' as h_propuesta,
      (cb.perfil_id is not null or cb.etapa = 'convertido') as h_cliente,
      (cb.contrato_id is not null) as h_contrato
    from cohorte_base cb
  ),
  cohorte as materialized (
    select s.*,
      h_asignado as asignado,
      (h_contacto or h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as contactado,
      (h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_agendada,
      (h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_realizada,
      (h_propuesta or h_cliente or h_contrato) as propuesta,
      (h_cliente or h_contrato) as cliente,
      h_contrato as contrato
    from senales s
  ),
  resumen as (
    select
      count(*)::int as leads,
      count(*) filter (where asignado)::int as asignados,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where propuesta)::int as propuestas,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados
    from cohorte
  ),
  produccion as (
    select
      (select count(*)::int from crm.leads l
        where l.convertido_en >= v_ini and l.convertido_en < v_fin) as clientes,
      (select count(*)::int from public.contratos c
        where c.creado_en >= v_ini and c.creado_en < v_fin
          and exists (select 1 from crm.leads l where l.contrato_id = c.id)) as contratos,
      coalesce((select sum(c.capital) from public.contratos c
        where c.creado_en >= v_ini and c.creado_en < v_fin and c.moneda = 'PEN'
          and exists (select 1 from crm.leads l where l.contrato_id = c.id)), 0) as capital_pen,
      coalesce((select sum(c.capital) from public.contratos c
        where c.creado_en >= v_ini and c.creado_en < v_fin and c.moneda = 'USD'
          and exists (select 1 from crm.leads l where l.contrato_id = c.id)), 0) as capital_usd
  ),
  origenes as (
    select coalesce(origen, 'sin_origen') as origen,
      count(*)::int as leads,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados,
      coalesce(sum(capital_contrato) filter (where moneda_contrato = 'PEN'), 0) as capital_pen,
      coalesce(sum(capital_contrato) filter (where moneda_contrato = 'USD'), 0) as capital_usd
    from cohorte group by coalesce(origen, 'sin_origen')
  ),
  categorias as (
    select coalesce(categoria_interes, 'sin_categoria') as categoria,
      count(*)::int as leads,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados
    from cohorte group by coalesce(categoria_interes, 'sin_categoria')
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1, 'zona', 'America/Lima'
    ),
    'cohorte', jsonb_build_object(
      'leads', r.leads, 'asignados', r.asignados, 'contactados', r.contactados,
      'reuniones_agendadas', r.reuniones_agendadas,
      'reuniones_realizadas', r.reuniones_realizadas,
      'propuestas', r.propuestas, 'clientes', r.clientes,
      'contratos', r.contratos, 'descartados', r.descartados,
      'conversion_clientes_pct', case when r.leads > 0 then round(100.0 * r.clientes / r.leads, 1) end,
      'conversion_contratos_pct', case when r.leads > 0 then round(100.0 * r.contratos / r.leads, 1) end,
      'conversion_resueltos_pct', case when r.clientes + r.descartados > 0
        then round(100.0 * r.clientes / (r.clientes + r.descartados), 1) end
    ),
    'produccion', jsonb_build_object(
      'clientes', p.clientes, 'contratos', p.contratos,
      'capital_pen', p.capital_pen, 'capital_usd', p.capital_usd
    ),
    'embudo', jsonb_build_array(
      jsonb_build_object('etapa','leads','cantidad',r.leads,'pct_anterior',case when r.leads > 0 then 100 else null end,'pct_total',case when r.leads > 0 then 100 else null end),
      jsonb_build_object('etapa','contactados','cantidad',r.contactados,'pct_anterior',case when r.leads > 0 then round(100.0*r.contactados/r.leads,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.contactados/r.leads,1) end),
      jsonb_build_object('etapa','reuniones_agendadas','cantidad',r.reuniones_agendadas,'pct_anterior',case when r.contactados > 0 then round(100.0*r.reuniones_agendadas/r.contactados,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.reuniones_agendadas/r.leads,1) end),
      jsonb_build_object('etapa','reuniones_realizadas','cantidad',r.reuniones_realizadas,'pct_anterior',case when r.reuniones_agendadas > 0 then round(100.0*r.reuniones_realizadas/r.reuniones_agendadas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.reuniones_realizadas/r.leads,1) end),
      jsonb_build_object('etapa','propuestas','cantidad',r.propuestas,'pct_anterior',case when r.reuniones_realizadas > 0 then round(100.0*r.propuestas/r.reuniones_realizadas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.propuestas/r.leads,1) end),
      jsonb_build_object('etapa','clientes','cantidad',r.clientes,'pct_anterior',case when r.propuestas > 0 then round(100.0*r.clientes/r.propuestas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.clientes/r.leads,1) end),
      jsonb_build_object('etapa','contratos','cantidad',r.contratos,'pct_anterior',case when r.clientes > 0 then round(100.0*r.contratos/r.clientes,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.contratos/r.leads,1) end)
    ),
    'origenes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'origen', o.origen, 'leads', o.leads, 'contactados', o.contactados,
        'reuniones_agendadas', o.reuniones_agendadas,
        'reuniones_realizadas', o.reuniones_realizadas,
        'clientes', o.clientes, 'contratos', o.contratos, 'descartados', o.descartados,
        'conversion_clientes_pct', case when o.leads > 0 then round(100.0*o.clientes/o.leads,1) end,
        'conversion_contratos_pct', case when o.leads > 0 then round(100.0*o.contratos/o.leads,1) end,
        'conversion_resueltos_pct', case when o.clientes+o.descartados > 0 then round(100.0*o.clientes/(o.clientes+o.descartados),1) end,
        'capital_pen', o.capital_pen, 'capital_usd', o.capital_usd
      ) order by o.contratos desc, o.clientes desc, o.leads desc, o.origen) from origenes o
    ), '[]'::jsonb),
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'categoria', c.categoria, 'leads', c.leads, 'clientes', c.clientes,
        'contratos', c.contratos, 'descartados', c.descartados,
        'conversion_pct', case when c.leads > 0 then round(100.0*c.contratos/c.leads,1) end
      ) order by c.contratos desc, c.leads desc, c.categoria) from categorias c
    ), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join produccion p;

  return v_payload;
end;
$$;

revoke all on function crm.metricas_conversiones_fn(date,date)
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_conversiones_fn(date,date) to authenticated;

-- ── 7. Efectividad de reuniones ─────────────────────────────────────────────

create or replace function crm.metricas_reuniones_fn(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_ahora timestamptz := now();
  v_payload jsonb;
  v_autorizado boolean;
begin
  select exists (
    select 1 from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo and e.rol_crm = 'gerencia'
  ) or private.es_lector_global() into v_autorizado;
  if v_uid is null or not coalesce(v_autorizado, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  with base as materialized (
    select t.*, coalesce(t.modalidad_reunion, 'sin_clasificar') as modalidad,
      coalesce(l.origen, 'sin_origen') as origen,
      l.perfil_id as cliente_id, l.contrato_id, l.convertido_en,
      c.capital, c.moneda, c.creado_en as contrato_creado_en,
      coalesce(p.nombre_completo, 'Sin responsable') as responsable_nombre,
      e.rol_crm, e.supervisor_id,
      coalesce(ps.nombre_completo, 'Sin equipo') as supervisor_nombre,
      t.vence_en <= v_ahora as metrica_debio_ocurrir,
      t.estado = 'completada' as metrica_realizada,
      t.estado = 'no_show' as metrica_no_show,
      (t.estado = 'cancelada' and t.cancelada_por = 'asesor')
        as metrica_cancelada_asesor,
      (t.estado = 'cancelada' and t.cancelada_por is distinct from 'asesor')
        as metrica_cancelada_sistema,
      t.estado = 'reprogramada' as metrica_reprogramada,
      (t.estado = 'pendiente' and t.vence_en <= v_ahora)
        as metrica_pendiente_cierre,
      (t.estado = 'pendiente' and t.vence_en > v_ahora)
        as metrica_programada_futura
    from crm.tareas t
    left join crm.leads l on l.id = t.lead_id
    left join public.contratos c on c.id = l.contrato_id
    left join public.perfiles p on p.id = t.vendedor_id
    left join crm.equipo e on e.perfil_id = t.vendedor_id
    left join public.perfiles ps on ps.id = e.supervisor_id
    where t.tipo = 'reunion' and t.activo
      and t.vence_en >= v_ini and t.vence_en < v_fin
  ),
  ultima_realizada as materialized (
    select distinct on (lead_id)
      lead_id, modalidad, origen, vendedor_id, responsable_nombre,
      supervisor_id, supervisor_nombre, cliente_id, contrato_id, convertido_en,
      capital, moneda, contrato_creado_en, vence_en,
      (cliente_id is not null and convertido_en >= vence_en)
        as metrica_conversion_cliente,
      (contrato_id is not null and contrato_creado_en >= vence_en)
        as metrica_conversion_contrato
    from base
    where metrica_realizada and lead_id is not null
    order by lead_id, vence_en desc, id desc
  ),
  resumen as (
    select count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_cancelada_sistema)::int as canceladas_sistema,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre,
      count(*) filter (where metrica_programada_futura)::int as programadas_futuras
    from base
  ),
  modalidad_base as (
    select modalidad,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base group by modalidad
  ),
  modalidad_conversion as (
    select modalidad,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada group by modalidad
  ),
  origen_base as (
    select origen,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas
    from base group by origen
  ),
  origen_conversion as (
    select origen,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos
    from ultima_realizada group by origen
  ),
  responsables as (
    select vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_asesor
          and cancelada_por_id is distinct from vendedor_id
      )::int as canceladas_ajenas_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base
    group by vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre
  ),
  resultados as (
    select coalesce(resultado_reunion, 'sin_clasificar') as resultado,
      count(*)::int as cantidad
    from base where metrica_realizada
    group by coalesce(resultado_reunion, 'sin_clasificar')
  ),
  conversion_global as (
    select count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada
  )
  select jsonb_build_object(
    'version', 1, 'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta-p_desde)+1, 'zona', 'America/Lima'
    ),
    'resumen', jsonb_build_object(
      'pactadas', r.pactadas, 'debieron_ocurrir', r.debieron_ocurrir,
      'realizadas', r.realizadas, 'no_concretadas', r.no_show+r.canceladas,
      'no_show', r.no_show, 'canceladas', r.canceladas,
      'canceladas_sistema', r.canceladas_sistema,
      'reprogramadas', r.reprogramadas,
      'pendientes_cierre', r.pendientes_cierre,
      'programadas_futuras', r.programadas_futuras,
      'pct_realizacion', case
        when r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas > 0
        then round(
          100.0*r.realizadas
          /(r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when r.realizadas+r.no_show > 0
        then round(100.0*r.realizadas/(r.realizadas+r.no_show),1) end
    ),
    'conversion', jsonb_build_object(
      'leads_reunidos', cg.leads_reunidos, 'clientes', cg.clientes,
      'contratos', cg.contratos,
      'conversion_cliente_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.clientes/cg.leads_reunidos,1) end,
      'conversion_contrato_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.contratos/cg.leads_reunidos,1) end,
      'capital_pen', cg.capital_pen, 'capital_usd', cg.capital_usd
    ),
    'modalidades', coalesce((select jsonb_agg(jsonb_build_object(
      'modalidad', mb.modalidad, 'pactadas', mb.pactadas,
      'debieron_ocurrir', mb.debieron_ocurrir, 'realizadas', mb.realizadas,
      'no_concretadas', mb.no_show+mb.canceladas, 'no_show', mb.no_show,
      'canceladas', mb.canceladas, 'reprogramadas', mb.reprogramadas,
      'pendientes_cierre', mb.pendientes_cierre,
      'pct_realizacion', case
        when mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas > 0
        then round(
          100.0*mb.realizadas
          /(mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when mb.realizadas+mb.no_show > 0 then round(100.0*mb.realizadas/(mb.realizadas+mb.no_show),1) end,
      'leads_reunidos', coalesce(mc.leads_reunidos,0),
      'clientes', coalesce(mc.clientes,0), 'contratos', coalesce(mc.contratos,0),
      'conversion_cliente_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.clientes/mc.leads_reunidos,1) end,
      'conversion_contrato_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.contratos/mc.leads_reunidos,1) end,
      'capital_pen', coalesce(mc.capital_pen,0), 'capital_usd', coalesce(mc.capital_usd,0)
    ) order by case mb.modalidad when 'presencial' then 1 when 'virtual' then 2 else 3 end)
      from modalidad_base mb left join modalidad_conversion mc using (modalidad)), '[]'::jsonb),
    'origenes', coalesce((select jsonb_agg(jsonb_build_object(
      'origen', ob.origen, 'pactadas', ob.pactadas, 'realizadas', ob.realizadas,
      'no_show', ob.no_show, 'canceladas', ob.canceladas,
      'pct_realizacion', case
        when ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas > 0
        then round(
          100.0*ob.realizadas
          /(ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas),
          1
        )
      end,
      'leads_reunidos', coalesce(oc.leads_reunidos,0),
      'clientes', coalesce(oc.clientes,0), 'contratos', coalesce(oc.contratos,0),
      'conversion_contrato_pct', case when coalesce(oc.leads_reunidos,0)>0 then round(100.0*oc.contratos/oc.leads_reunidos,1) end
    ) order by ob.realizadas desc, ob.pactadas desc, ob.origen)
      from origen_base ob left join origen_conversion oc using (origen)), '[]'::jsonb),
    'responsables', coalesce((select jsonb_agg(jsonb_build_object(
      'responsable_id', rr.vendedor_id, 'nombre', rr.responsable_nombre,
      'rol', rr.rol_crm, 'supervisor_id', rr.supervisor_id,
      'supervisor_nombre', rr.supervisor_nombre,
      'pactadas', rr.pactadas, 'realizadas', rr.realizadas,
      'no_show', rr.no_show, 'canceladas', rr.canceladas,
      'reprogramadas', rr.reprogramadas,
      'pendientes_cierre', rr.pendientes_cierre,
      'pct_realizacion', case
        when rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
          -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas > 0
        then round(
          100.0*rr.realizadas
          /(rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
            -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas),
          1
        )
      end
    ) order by rr.realizadas desc, rr.pactadas desc, rr.responsable_nombre) from responsables rr), '[]'::jsonb),
    'resultados', coalesce((select jsonb_agg(jsonb_build_object(
      'resultado', resultado, 'cantidad', cantidad
    ) order by cantidad desc, resultado) from resultados), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join conversion_global cg;

  return v_payload;
end;
$$;

revoke all on function crm.metricas_reuniones_fn(date,date)
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_reuniones_fn(date,date) to authenticated;

-- ── 8. El calendario externo conserva modalidad y destino ──────────────────

create or replace function crm.agenda_ics_feed_fn(p_token uuid, p_desde timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with miembro as materialized (
    select a.perfil_id
    from crm.agenda_ics a
    join crm.equipo e on e.perfil_id = a.perfil_id and e.activo = true
    join public.perfiles p on p.id = a.perfil_id and p.activo = true
    where a.token = p_token
  ),
  filas as (
    select t.id, t.tipo, t.titulo, t.nota, t.vence_en, t.duracion_min,
           t.modalidad_reunion, t.ubicacion_reunion, t.enlace_reunion
    from crm.tareas t
    join miembro m on m.perfil_id = t.vendedor_id
    where t.estado = 'pendiente' and t.activo and t.vence_en >= p_desde
    order by t.vence_en limit 500
  )
  select jsonb_build_object(
    'autorizado', exists (select 1 from miembro),
    'tareas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', f.id, 'tipo', f.tipo, 'titulo', f.titulo, 'nota', f.nota,
      'vence_en', f.vence_en, 'duracion_min', f.duracion_min,
      'modalidad_reunion', f.modalidad_reunion,
      'ubicacion_reunion', f.ubicacion_reunion,
      'enlace_reunion', f.enlace_reunion
    ) order by f.vence_en) from filas f), '[]'::jsonb)
  );
$$;

revoke all on function crm.agenda_ics_feed_fn(uuid,timestamptz)
  from public, anon, authenticated;
grant execute on function crm.agenda_ics_feed_fn(uuid,timestamptz) to service_role;

commit;
