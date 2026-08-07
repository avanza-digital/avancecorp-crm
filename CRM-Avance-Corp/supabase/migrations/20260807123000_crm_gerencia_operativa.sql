-- Gerencia deja de ser un perfil de inteligencia de solo lectura y pasa a
-- operar TODO el CRM. La ampliacion se ancla a crm.equipo vivo; NO convierte
-- al perfil en admin/superadmin del portal ni abre pagos, usuarios o borrados.
--
-- Invariantes que se conservan:
--   * Directorio sigue siendo solo lectura.
--   * No aparece DELETE fisico en leads/tareas/actividades.
--   * No Insista, trazabilidad, tenencia y auditoria siguen en triggers.
--   * Un lead solo se convierte si ya tiene analista responsable; Gerencia
--     ejecuta el cierre, pero el cliente queda atribuido a ese analista.
--   * Contratos renovados/retirados siguen cerrados salvo superadmin.

begin;

set local lock_timeout = '10s';

do $$
begin
  if to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.puede_acceder_crm()') is null then
    raise exception 'Faltan helpers de autorizacion CRM';
  end if;
  if to_regprocedure('public.crear_contrato(jsonb,jsonb)') is null
     or to_regprocedure('public.actualizar_contrato(uuid,jsonb,jsonb)') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null then
    raise exception 'Faltan funciones contractuales vigentes';
  end if;
  if to_regclass('crm.leads') is null
     or to_regclass('crm.tareas') is null
     or to_regclass('crm.actividades') is null
     or to_regclass('public.perfiles') is null then
    raise exception 'Faltan tablas requeridas';
  end if;
end;
$$;

-- ── 1. Retirar el veto transversal de solo lectura ─────────────────────────

drop trigger if exists trg_00_gerencia_solo_lectura on crm.leads;
drop trigger if exists trg_00_gerencia_solo_lectura on crm.tareas;
drop trigger if exists trg_00_gerencia_solo_lectura on crm.actividades;
drop function if exists private.trg_gerencia_inteligencia_solo_lectura();

-- ── 2. RLS operativa: alcance global, autor vivo y soft-delete ──────────────

drop policy if exists leads_update on crm.leads;
create policy leads_update on crm.leads
  for update to authenticated
  using (
    activo = true
    and (
      private.rol_crm((select auth.uid())) = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  )
  with check (
    (
      vendedor_id is null
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
    and (
      asignado_supervisor_id is null
      or asignado_supervisor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
    and (
      activo = true
      or private.rol_crm((select auth.uid())) in ('supervisor', 'gerencia')
    )
  );

drop policy if exists actividades_insert on crm.actividades;
create policy actividades_insert on crm.actividades
  for insert to authenticated
  with check (
    creado_por = (select auth.uid())
    and tipo not in ('cambio_etapa', 'reasignacion', 'conversion')
    and exists (
      select 1
      from crm.leads l
      where l.id = actividades.lead_id
        and l.activo = true
        and (
          private.rol_crm((select auth.uid())) = 'gerencia'
          or l.vendedor_id = (select auth.uid())
          or (
            private.rol_crm((select auth.uid())) = 'supervisor'
            and (
              l.vendedor_id in (
                select private.vendedor_ids_visibles((select auth.uid()))
              )
              or (
                l.vendedor_id is null
                and l.asignado_supervisor_id in (
                  select private.vendedor_ids_visibles((select auth.uid()))
                )
              )
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
    and private.rol_crm((select auth.uid())) in (
      'vendedor', 'supervisor', 'gerencia'
    )
    and (
      private.rol_crm((select auth.uid())) = 'gerencia'
      or vendedor_id = (select auth.uid())
      or (
        private.rol_crm((select auth.uid())) = 'supervisor'
        and (
          vendedor_id is null
          or vendedor_id in (
            select private.vendedor_ids_visibles((select auth.uid()))
          )
        )
      )
    )
    and (
      vendedor_id is null
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
    and (
      asignado_supervisor_id is null
      or asignado_supervisor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
    and (
      lead_id is null
      or exists (select 1 from crm.leads l where l.id = lead_id)
    )
  );

drop policy if exists tareas_update on crm.tareas;
create policy tareas_update on crm.tareas
  for update to authenticated
  using (
    activo = true
    and (
      private.rol_crm((select auth.uid())) = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  )
  with check (
    (
      vendedor_id is null
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
    and (
      asignado_supervisor_id is null
      or asignado_supervisor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
    and (
      activo = true
      or private.rol_crm((select auth.uid())) in ('supervisor', 'gerencia')
    )
  );

-- ── 3. Conversion: Gerencia cierra, el analista conserva la cartera ─────────

create or replace function crm.convertir_lead(
  p_lead_id uuid,
  p_perfil_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text := private.rol_crm((select auth.uid()));
  v_lead       crm.leads%rowtype;
  v_dni_perfil text;
  v_asesor     uuid;
begin
  if v_uid is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  select dni, asesor_perfil_id
    into v_dni_perfil, v_asesor
  from public.perfiles
  where id = p_perfil_id
    and rol = 'cliente'
    and activo = true;
  if not found then
    raise exception 'El cliente destino no existe o no esta activo';
  end if;

  if v_lead.dni is not null
     and v_dni_perfil is not null
     and v_lead.dni <> v_dni_perfil then
    raise exception 'El documento del cliente no coincide con el del lead';
  end if;

  if v_rol <> 'gerencia'
     and (
       v_asesor is null
       or v_asesor not in (
         select private.vendedor_ids_visibles((select auth.uid()))
       )
     )
     and not (
       v_lead.dni is not null
       and v_dni_perfil is not null
       and v_lead.dni = v_dni_perfil
     ) then
    raise exception 'Ese cliente no pertenece a tu cartera';
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         perfil_id = p_perfil_id,
         convertido_en = now()
   where id = p_lead_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido a cliente',
    jsonb_build_object('perfil_id', p_perfil_id),
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'perfil_id', p_perfil_id
  );
end;
$$;

revoke all on function crm.convertir_lead(uuid, uuid)
  from public, anon, service_role;
grant execute on function crm.convertir_lead(uuid, uuid) to authenticated;

-- ── 4. Agenda: cerrar y reprogramar en todo el ambito de Gerencia ──────────

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
  if v_uid is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estado is null
     or p_estado not in ('completada', 'no_show', 'cancelada') then
    raise exception 'Estado de cierre invalido' using errcode = '22023';
  end if;

  perform 1
  from crm.leads
  where id = (
    select t.lead_id
    from crm.tareas t
    where t.id = p_tarea_id
      and t.activo
      and t.estado = 'pendiente'
      and (
        v_rol = 'gerencia'
        or t.vendedor_id in (
          select private.vendedor_ids_visibles(v_uid)
        )
        or (
          t.vendedor_id is null
          and t.asignado_supervisor_id in (
            select private.vendedor_ids_visibles(v_uid)
          )
        )
      )
  )
  for no key update;

  select *
    into v_tarea
  from crm.tareas t
  where t.id = p_tarea_id
    and t.activo
    and t.estado = 'pendiente'
    and (
      v_rol = 'gerencia'
      or t.vendedor_id in (
        select private.vendedor_ids_visibles(v_uid)
      )
      or (
        t.vendedor_id is null
        and t.asignado_supervisor_id in (
          select private.vendedor_ids_visibles(v_uid)
        )
      )
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
      'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
      'whatsapp_recibido', 'reunion_realizada', 'nota'
    ) then
      raise exception 'Tipo de resultado invalido';
    end if;
  end if;
  if v_tarea.tipo = 'llamada'
     and p_estado = 'completada'
     and p_resultado_tipo is null then
    raise exception 'Registra el resultado de la llamada (contesto / no contesto)';
  end if;

  if p_resultado_tipo is not null then
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (
      v_tarea.lead_id,
      p_resultado_tipo,
      nullif(btrim(coalesce(p_resultado_detalle, '')), ''),
      v_uid
    )
    returning id into v_act_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas
     set estado = p_estado,
         resultado_actividad_id = v_act_id,
         resultado_reunion = case
           when v_tarea.tipo = 'reunion' and p_estado = 'completada'
             then 'sin_clasificar'
           else null
         end,
         motivo_no_realizada = case
           when v_tarea.tipo = 'reunion' and p_estado = 'no_show'
             then 'cliente_no_asistio'
           when v_tarea.tipo = 'reunion' and p_estado = 'cancelada'
             then 'otro'
           else null
         end,
         detalle_cierre_reunion = case
           when v_tarea.tipo = 'reunion' and p_estado = 'cancelada'
             then coalesce(
               nullif(btrim(coalesce(p_resultado_detalle, '')), ''),
               'Compatibilidad: motivo no estructurado por cliente anterior'
             )
           when v_tarea.tipo = 'reunion'
             then nullif(btrim(coalesce(p_resultado_detalle, '')), '')
           else null
         end
   where id = p_tarea_id;
  perform set_config('crm.op_tarea', 'off', true);

  v_sig_id := private.crear_siguiente_tarea(
    v_tarea,
    p_siguiente,
    case when p_estado = 'no_show' then p_tarea_id else null end,
    v_uid
  );

  if p_estado = 'cancelada'
     and v_tarea.tipo = 'reunion'
     and v_tarea.lead_id is not null then
    v_retroceso := private.retroceso_por_anular_reunion(
      v_tarea.lead_id, p_tarea_id, v_uid
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'siguiente_id', v_sig_id,
    'retroceso', v_retroceso
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
  if v_uid is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estado is null
     or p_estado not in ('completada', 'no_show', 'cancelada') then
    raise exception 'Estado de reunion invalido' using errcode = '22023';
  end if;
  if p_estado = 'completada'
     and (
       p_resultado_reunion is null
       or p_resultado_reunion not in (
         'interesado', 'seguimiento', 'propuesta',
         'inicia_registro', 'no_interesado'
       )
     ) then
    raise exception 'Registra el resultado comercial de la reunion'
      using errcode = '22023';
  end if;
  if p_estado = 'no_show' then
    p_motivo_no_realizada := 'cliente_no_asistio';
  elsif p_estado = 'cancelada'
        and (
          p_motivo_no_realizada is null
          or p_motivo_no_realizada not in (
            'cancelada_cliente', 'cancelada_empresa', 'otro'
          )
        ) then
    raise exception 'Registra el motivo de cancelacion'
      using errcode = '22023';
  end if;
  if p_estado = 'cancelada'
     and p_motivo_no_realizada = 'otro'
     and nullif(btrim(coalesce(p_detalle, '')), '') is null then
    raise exception 'Describe el otro motivo de cancelacion'
      using errcode = '22023';
  end if;

  perform 1
  from crm.leads
  where id = (
    select t.lead_id
    from crm.tareas t
    where t.id = p_tarea_id
      and t.tipo = 'reunion'
      and t.activo
      and t.estado = 'pendiente'
      and (
        v_rol = 'gerencia'
        or t.vendedor_id in (
          select private.vendedor_ids_visibles(v_uid)
        )
        or (
          t.vendedor_id is null
          and t.asignado_supervisor_id in (
            select private.vendedor_ids_visibles(v_uid)
          )
        )
      )
  )
  for no key update;

  select *
    into v_tarea
  from crm.tareas t
  where t.id = p_tarea_id
    and t.tipo = 'reunion'
    and t.activo
    and t.estado = 'pendiente'
    and (
      v_rol = 'gerencia'
      or t.vendedor_id in (
        select private.vendedor_ids_visibles(v_uid)
      )
      or (
        t.vendedor_id is null
        and t.asignado_supervisor_id in (
          select private.vendedor_ids_visibles(v_uid)
        )
      )
    )
  for update;
  if not found then
    raise exception 'Reunion no encontrada, cerrada o fuera de tu ambito';
  end if;

  if p_estado = 'completada' and v_tarea.lead_id is not null then
    insert into crm.actividades (
      lead_id, tipo, detalle, metadata, creado_por
    ) values (
      v_tarea.lead_id,
      'reunion_realizada',
      nullif(btrim(coalesce(p_detalle, '')), ''),
      jsonb_build_object(
        'modalidad', v_tarea.modalidad_reunion,
        'resultado_reunion', p_resultado_reunion,
        'tarea_id', v_tarea.id
      ),
      v_uid
    )
    returning id into v_act_id;
  elsif p_estado = 'no_show'
        and v_tarea.lead_id is not null
        and btrim(coalesce(p_detalle, '')) <> '' then
    insert into crm.actividades (
      lead_id, tipo, detalle, metadata, creado_por
    ) values (
      v_tarea.lead_id,
      'nota',
      btrim(p_detalle),
      jsonb_build_object(
        'evento', 'reunion_no_show',
        'tarea_id', v_tarea.id
      ),
      v_uid
    )
    returning id into v_act_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas
     set estado = p_estado,
         resultado_actividad_id = v_act_id,
         resultado_reunion = case
           when p_estado = 'completada' then p_resultado_reunion
         end,
         motivo_no_realizada = case
           when p_estado in ('no_show', 'cancelada')
             then p_motivo_no_realizada
         end,
         detalle_cierre_reunion =
           nullif(btrim(coalesce(p_detalle, '')), '')
   where id = p_tarea_id;
  perform set_config('crm.op_tarea', 'off', true);

  v_sig_id := private.crear_siguiente_tarea(
    v_tarea,
    p_siguiente,
    case when p_estado = 'no_show' then p_tarea_id else null end,
    v_uid
  );

  if p_estado = 'cancelada' and v_tarea.lead_id is not null then
    v_retroceso := private.retroceso_por_anular_reunion(
      v_tarea.lead_id, p_tarea_id, v_uid
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'siguiente_id', v_sig_id,
    'retroceso', v_retroceso
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
  if v_uid is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_vence_en is null
     or p_vence_en < timestamptz '2026-01-01 00:00Z'
     or p_vence_en >= timestamptz '2100-01-01 00:00Z' then
    raise exception 'Fecha de reunion invalida' using errcode = '22023';
  end if;

  perform 1
  from crm.leads
  where id = (
    select t.lead_id
    from crm.tareas t
    where t.id = p_tarea_id
      and t.tipo = 'reunion'
      and t.activo
      and t.estado = 'pendiente'
      and (
        v_rol = 'gerencia'
        or t.vendedor_id in (
          select private.vendedor_ids_visibles(v_uid)
        )
        or (
          t.vendedor_id is null
          and t.asignado_supervisor_id in (
            select private.vendedor_ids_visibles(v_uid)
          )
        )
      )
  )
  for no key update;

  select *
    into v_tarea
  from crm.tareas t
  where t.id = p_tarea_id
    and t.tipo = 'reunion'
    and t.activo
    and t.estado = 'pendiente'
    and (
      v_rol = 'gerencia'
      or t.vendedor_id in (
        select private.vendedor_ids_visibles(v_uid)
      )
      or (
        t.vendedor_id is null
        and t.asignado_supervisor_id in (
          select private.vendedor_ids_visibles(v_uid)
        )
      )
    )
  for update;
  if not found then
    raise exception 'Reunion no encontrada, cerrada o fuera de tu ambito';
  end if;
  if p_vence_en = v_tarea.vence_en then
    raise exception 'La nueva fecha debe ser distinta'
      using errcode = '22023';
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas
     set estado = 'reprogramada',
         motivo_no_realizada = 'reprogramada',
         detalle_cierre_reunion = 'Reprogramada a ' || p_vence_en::text
   where id = p_tarea_id;
  perform set_config('crm.op_tarea', 'off', true);

  insert into crm.tareas (
    id, lead_id, perfil_id, tipo, titulo, nota, vence_en, duracion_min,
    modalidad_reunion, ubicacion_reunion, enlace_reunion,
    reagendada_de, reprogramaciones, creado_por
  ) values (
    v_nueva_id,
    v_tarea.lead_id,
    v_tarea.perfil_id,
    'reunion',
    v_tarea.titulo,
    v_tarea.nota,
    p_vence_en,
    v_tarea.duracion_min,
    v_tarea.modalidad_reunion,
    v_tarea.ubicacion_reunion,
    v_tarea.enlace_reunion,
    v_tarea.id,
    v_tarea.reprogramaciones + 1,
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'tarea_anterior_id', p_tarea_id,
    'tarea_nueva_id', v_nueva_id,
    'reprogramaciones', v_tarea.reprogramaciones + 1
  );
end;
$$;

revoke all on function crm.cerrar_tarea(uuid, text, text, text, jsonb)
  from public, anon, service_role;
grant execute on function crm.cerrar_tarea(uuid, text, text, text, jsonb)
  to authenticated;
revoke all on function crm.cerrar_reunion(uuid, text, text, text, text, jsonb)
  from public, anon, service_role;
grant execute on function crm.cerrar_reunion(uuid, text, text, text, text, jsonb)
  to authenticated;
revoke all on function crm.reprogramar_reunion(uuid, timestamptz, uuid)
  from public, anon, service_role;
grant execute on function crm.reprogramar_reunion(uuid, timestamptz, uuid)
  to authenticated;

-- ── 5. Cliente: lectura/correccion global sin administrar perfiles staff ────

drop policy if exists perfiles_select on public.perfiles;
create policy perfiles_select on public.perfiles
  for select to authenticated
  using (
    (select auth.uid()) = id
    or public.es_admin()
    or (
      rol = 'cliente'
      and private.rol_crm((select auth.uid())) = 'gerencia'
    )
  );

drop policy if exists perfiles_update on public.perfiles;
create policy perfiles_update on public.perfiles
  for update to authenticated
  using (
    (select auth.uid()) = id
    or (select public.es_superadmin())
    or ((select public.es_admin()) and rol in ('cliente', 'analista'))
  )
  with check (
    (select public.es_superadmin())
    or ((select public.es_admin()) and rol in ('cliente', 'analista'))
    or (
      (select auth.uid()) = id
      and rol = (select public.mi_rol())
    )
  );

-- La correccion gerencial NO abre UPDATE crudo sobre las decenas de columnas de
-- public.perfiles. Esta RPC admite exactamente el formulario del CRM, conserva
-- id/rol/activo/asesor/autoria y sella actualizado_en en el servidor.
create or replace function crm.actualizar_cliente_gerencia(
  p_cliente_id uuid,
  p_patch jsonb
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cliente public.perfiles%rowtype;
begin
  if private.rol_crm((select auth.uid())) <> 'gerencia' then
    raise exception 'Solo Gerencia puede corregir clientes fuera de cartera'
      using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Los datos del cliente son invalidos'
      using errcode = '22023';
  end if;
  if (
    p_patch - array[
      'nombre_completo', 'nombres', 'apellidos', 'tipo_documento',
      'dni', 'telefono',
      'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
      'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
      'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
      'titular_distinto_usd', 'beneficiario_nombre_usd',
      'beneficiario_dni_usd', 'actualizado_en'
    ]::text[]
  ) <> '{}'::jsonb then
    raise exception 'El formulario intento modificar campos no permitidos'
      using errcode = '22023';
  end if;

  select *
    into v_cliente
  from public.perfiles
  where id = p_cliente_id
    and rol = 'cliente'
  for update;
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;

  update public.perfiles
     set nombre_completo = case
           when p_patch ? 'nombre_completo'
             then p_patch->>'nombre_completo'
           else nombre_completo
         end,
         nombres = case
           when p_patch ? 'nombres' then p_patch->>'nombres'
           else nombres
         end,
         apellidos = case
           when p_patch ? 'apellidos' then p_patch->>'apellidos'
           else apellidos
         end,
         tipo_documento = case
           when p_patch ? 'tipo_documento'
             then p_patch->>'tipo_documento'
           else tipo_documento
         end,
         dni = case
           when p_patch ? 'dni' then p_patch->>'dni'
           else dni
         end,
         telefono = case
           when p_patch ? 'telefono' then p_patch->>'telefono'
           else telefono
         end,
         banco = case
           when p_patch ? 'banco' then p_patch->>'banco'
           else banco
         end,
         tipo_cuenta = case
           when p_patch ? 'tipo_cuenta' then p_patch->>'tipo_cuenta'
           else tipo_cuenta
         end,
         numero_cuenta = case
           when p_patch ? 'numero_cuenta'
             then p_patch->>'numero_cuenta'
           else numero_cuenta
         end,
         cci = case
           when p_patch ? 'cci' then p_patch->>'cci'
           else cci
         end,
         titular_distinto = case
           when p_patch ? 'titular_distinto'
             then (p_patch->>'titular_distinto')::boolean
           else titular_distinto
         end,
         beneficiario_nombre = case
           when p_patch ? 'beneficiario_nombre'
             then p_patch->>'beneficiario_nombre'
           else beneficiario_nombre
         end,
         beneficiario_dni = case
           when p_patch ? 'beneficiario_dni'
             then p_patch->>'beneficiario_dni'
           else beneficiario_dni
         end,
         banco_usd = case
           when p_patch ? 'banco_usd' then p_patch->>'banco_usd'
           else banco_usd
         end,
         tipo_cuenta_usd = case
           when p_patch ? 'tipo_cuenta_usd'
             then p_patch->>'tipo_cuenta_usd'
           else tipo_cuenta_usd
         end,
         numero_cuenta_usd = case
           when p_patch ? 'numero_cuenta_usd'
             then p_patch->>'numero_cuenta_usd'
           else numero_cuenta_usd
         end,
         cci_usd = case
           when p_patch ? 'cci_usd' then p_patch->>'cci_usd'
           else cci_usd
         end,
         titular_distinto_usd = case
           when p_patch ? 'titular_distinto_usd'
             then (p_patch->>'titular_distinto_usd')::boolean
           else titular_distinto_usd
         end,
         beneficiario_nombre_usd = case
           when p_patch ? 'beneficiario_nombre_usd'
             then p_patch->>'beneficiario_nombre_usd'
           else beneficiario_nombre_usd
         end,
         beneficiario_dni_usd = case
           when p_patch ? 'beneficiario_dni_usd'
             then p_patch->>'beneficiario_dni_usd'
           else beneficiario_dni_usd
         end,
         actualizado_en = now()
   where id = p_cliente_id;

  return true;
end;
$$;

revoke all on function crm.actualizar_cliente_gerencia(uuid, jsonb)
  from public, anon, service_role;
grant execute on function crm.actualizar_cliente_gerencia(uuid, jsonb)
  to authenticated;

-- Las RPC bancarias del CRM aceptan Gerencia por su rol CRM vivo. El portal
-- conserva admin/analista y su regla de cartera exactamente como antes.
create or replace function private.puede_gestionar_cuentas_cliente(
  p_cliente_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (select private.puede_acceder_crm())
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo = true
        and (
          private.rol_crm((select auth.uid())) = 'gerencia'
          or (select public.es_admin())
          or (
            (select public.es_analista())
            and (
              cli.asesor_perfil_id = (select auth.uid())
              or (
                cli.asesor_perfil_id is null
                and cli.creado_por = (select auth.uid())
              )
            )
          )
        )
    );
$$;

revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;

-- ── 6. Contratos: poder de Gerencia SOLO por estas RPC, no admin del portal ─

-- Las definiciones siguientes conservan literalmente la validacion y escritura
-- vigente del portal. El unico cambio de autorizacion es v_es_gerencia_crm.

create or replace function public.crear_contrato(
  p_contrato jsonb,
  p_cronograma jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid              uuid := auth.uid();
  v_es_analista      boolean := public.es_analista();
  v_es_admin         boolean := public.es_admin();
  v_es_gerencia_crm  boolean :=
    coalesce(private.rol_crm(v_uid) = 'gerencia', false);
  v_cliente_id       uuid := (p_contrato->>'cliente_id')::uuid;
  v_numero           text := nullif(btrim(p_contrato->>'numero_contrato'), '');
  v_categoria        text := p_contrato->>'categoria';
  v_anio             int := extract(year from now())::int;
  v_seq              int;
  v_contrato_id      uuid;
  v_cuota            jsonb;
begin
  if not (v_es_analista or v_es_admin or v_es_gerencia_crm) then
    raise exception 'No autorizado para crear contratos';
  end if;

  if v_es_analista and not v_es_admin and not v_es_gerencia_crm then
    if not exists (
      select 1
      from public.perfiles c
      where c.id = v_cliente_id
        and c.rol = 'cliente'
        and (
          c.asesor_perfil_id = v_uid
          or (
            c.asesor_perfil_id is null
            and c.creado_por = v_uid
          )
        )
    ) then
      raise exception
        'Solo puedes crear contratos para clientes de tu cartera (asignados a ti o que registraste)';
    end if;
  end if;

  if (p_contrato->>'capital')::numeric < 100
     or (p_contrato->>'capital')::numeric > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;

  if v_categoria is null
     or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception
      'Selecciona la categoria del contrato (Nuevo, Renovacion o Upgrade)';
  end if;

  if v_numero is null then
    select
      coalesce(
        max(
          nullif(
            regexp_replace(
              split_part(numero_contrato, '-', 3),
              '[^0-9]',
              '',
              'g'
            ),
            ''
          )::int
        ),
        0
      ) + 1
      into v_seq
    from public.contratos
    where numero_contrato like 'AC-' || v_anio || '-%';

    v_numero := 'AC-' || v_anio || '-' || lpad(v_seq::text, 4, '0');
  end if;

  if exists (
    select 1
    from public.contratos
    where numero_contrato = v_numero
  ) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id,
    numero_contrato,
    capital,
    moneda,
    tasa_anual,
    modalidad,
    tipo_interes,
    fecha_inicio,
    fecha_vencimiento,
    notas_internas,
    categoria,
    estado,
    creado_por
  ) values (
    v_cliente_id,
    v_numero,
    (p_contrato->>'capital')::numeric,
    coalesce(nullif(p_contrato->>'moneda', ''), 'PEN'),
    (p_contrato->>'tasa_anual')::numeric,
    p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria,
    'activo',
    v_uid
  )
  returning id into v_contrato_id;

  if p_cronograma is null or jsonb_array_length(p_cronograma) = 0 then
    raise exception 'El cronograma no puede estar vacio';
  end if;

  for v_cuota in
    select * from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id,
      numero_cuota,
      fecha_programada,
      monto_programado,
      estado,
      tipo
    ) values (
      v_contrato_id,
      (v_cuota->>'numero_cuota')::int,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric,
      'pendiente',
      coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
    );
  end loop;

  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(
      v_contrato_id,
      p_contrato->'titulares'
    );
  end if;

  return jsonb_build_object(
    'id', v_contrato_id,
    'numero_contrato', v_numero
  );
end;
$$;

create or replace function public.actualizar_contrato(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid              uuid := auth.uid();
  v_es_analista      boolean := public.es_analista();
  v_es_admin         boolean := public.es_admin();
  v_es_gerencia_crm  boolean :=
    coalesce(private.rol_crm(v_uid) = 'gerencia', false);
  v_row              public.contratos%rowtype;
  v_cuota            jsonb;
  v_numero           text;
begin
  select *
    into v_row
  from public.contratos
  where id = p_id;
  if not found then
    raise exception 'Contrato no encontrado';
  end if;

  if v_es_admin or v_es_gerencia_crm then
    null;
  elsif v_es_analista then
    if v_row.creado_por <> v_uid then
      raise exception 'Solo puedes corregir contratos que tu creaste';
    end if;
    if v_row.creado_en <= now() - interval '5 hours' then
      raise exception
        'La ventana de correccion de 5 horas ya vencio para este contrato';
    end if;
    if not exists (
      select 1
      from public.perfiles cli
      where cli.id = v_row.cliente_id
        and cli.rol = 'cliente'
        and (
          cli.asesor_perfil_id = v_uid
          or (
            cli.asesor_perfil_id is null
            and cli.creado_por = v_uid
          )
        )
    ) then
      raise exception
        'Este cliente ya no esta en tu cartera; no puedes corregir su contrato';
    end if;
  else
    raise exception 'No autorizado';
  end if;

  if v_row.estado in ('renovado', 'retirado')
     and not public.es_superadmin() then
    raise exception
      'El contrato esta cerrado (%): no se pueden editar sus terminos',
      v_row.estado;
  end if;

  if (p_contrato->>'capital')::numeric < 100
     or (p_contrato->>'capital')::numeric > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;

  if (p_contrato->>'categoria') is not null
     and (p_contrato->>'categoria') not in (
       'nuevo', 'renovacion', 'upgrade'
     ) then
    raise exception 'Categoria invalida';
  end if;

  v_numero := nullif(btrim(p_contrato->>'numero_contrato'), '');
  if v_numero is not null
     and v_numero is distinct from v_row.numero_contrato then
    if exists (
      select 1
      from public.contratos
      where numero_contrato = v_numero
        and id <> p_id
    ) then
      raise exception
        'El N de contrato % ya existe en otro contrato',
        v_numero;
    end if;
  end if;

  update public.contratos
     set numero_contrato =
           coalesce(v_numero, numero_contrato),
         capital =
           (p_contrato->>'capital')::numeric,
         moneda =
           coalesce(nullif(p_contrato->>'moneda', ''), moneda),
         tasa_anual =
           (p_contrato->>'tasa_anual')::numeric,
         modalidad =
           p_contrato->>'modalidad',
         tipo_interes =
           coalesce(
             nullif(p_contrato->>'tipo_interes', ''),
             tipo_interes
           ),
         fecha_inicio =
           (p_contrato->>'fecha_inicio')::date,
         fecha_vencimiento =
           (p_contrato->>'fecha_vencimiento')::date,
         notas_internas =
           nullif(
             btrim(coalesce(p_contrato->>'notas_internas', '')),
             ''
           ),
         categoria =
           coalesce(nullif(p_contrato->>'categoria', ''), categoria)
   where id = p_id;

  if p_cronograma is not null
     and jsonb_array_length(p_cronograma) > 0 then
    if not exists (
      select 1
      from public.cronograma_pagos
      where contrato_id = p_id
        and (
          estado = 'pagado'
          or monto_pagado is not null
        )
    ) then
      delete from public.cronograma_pagos
      where contrato_id = p_id;

      for v_cuota in
        select value
        from jsonb_array_elements(p_cronograma)
      loop
        insert into public.cronograma_pagos (
          contrato_id,
          numero_cuota,
          fecha_programada,
          monto_programado,
          estado,
          tipo
        ) values (
          p_id,
          (v_cuota->>'numero_cuota')::int,
          (v_cuota->>'fecha_programada')::date,
          (v_cuota->>'monto_programado')::numeric,
          'pendiente',
          coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
        );
      end loop;
    else
      delete from public.cronograma_pagos
      where contrato_id = p_id
        and not (
          estado = 'pagado'
          or monto_pagado is not null
        );

      for v_cuota in
        select je.value
        from jsonb_array_elements(p_cronograma) as je(value)
        where not exists (
          select 1
          from public.cronograma_pagos cp
          where cp.contrato_id = p_id
            and (
              cp.estado = 'pagado'
              or cp.monto_pagado is not null
            )
            and cp.numero_cuota =
              (je.value->>'numero_cuota')::int
        )
      loop
        insert into public.cronograma_pagos (
          contrato_id,
          numero_cuota,
          fecha_programada,
          monto_programado,
          estado,
          tipo
        ) values (
          p_id,
          (v_cuota->>'numero_cuota')::int,
          (v_cuota->>'fecha_programada')::date,
          (v_cuota->>'monto_programado')::numeric,
          'pendiente',
          coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
        );
      end loop;
    end if;
  end if;

  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(
      p_id,
      p_contrato->'titulares'
    );
  end if;

  return jsonb_build_object('id', p_id, 'ok', true);
end;
$$;

-- OR REPLACE conserva la firma, pero las ACL quedan explicitamente cerradas
-- para anon y abiertas solo a sesiones autenticadas como antes.
revoke all on function public.crear_contrato(jsonb, jsonb)
  from public, anon;
grant execute on function public.crear_contrato(jsonb, jsonb)
  to authenticated;
revoke all on function public.actualizar_contrato(uuid, jsonb, jsonb)
  from public, anon;
grant execute on function public.actualizar_contrato(uuid, jsonb, jsonb)
  to authenticated;

comment on function private.puede_gestionar_cuentas_cliente(uuid) is
  'Autoriza banca contractual con gate CRM vivo: Gerencia opera cualquier cliente activo; portal admin conserva alcance global y analista conserva cartera.';
comment on function crm.actualizar_cliente_gerencia(uuid, jsonb) is
  'Correccion global acotada de clientes para Gerencia CRM activa; no permite cambiar correo, rol, estado, asesor ni autoria.';
comment on function crm.convertir_lead(uuid, uuid) is
  'Convierte fuerza de ventas o Gerencia; Gerencia exige un analista ya asignado y conserva su atribucion.';

commit;
