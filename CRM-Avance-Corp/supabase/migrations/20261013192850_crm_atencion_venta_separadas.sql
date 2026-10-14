-- Aprobado por Miguel 13/10/2026: dos acciones; private, adaptador public y guardia de asesor.
-- Reversa de código: supabase/scripts/atencion-venta/reversa.sql.
-- No altera capital, snapshots, autoría de registro ni operaciones_cartera.vendedor_id.
begin;
set local lock_timeout='5s';

create or replace function private.puede_cambiar_atencion() returns boolean
language sql stable set search_path='' as $$
 select auth.uid() is not null and not private.membresia_crm_revocada()
   and (private.es_gerencia_crm_activa() or public.es_admin());
$$;

CREATE OR REPLACE FUNCTION "private"."cambiar_atencion_persona"("p_inversionista" "uuid", "p_nuevo_responsable" "uuid", "p_motivo" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    SET "lock_timeout" TO '5s'
    AS $$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_tramo crm.inversionista_responsables%rowtype; v_nuevo_id uuid; v_ahora timestamptz; v_lead crm.leads%rowtype;
  v_rol_nuevo text; v_leads uuid[] := array[]::uuid[]; v_leads_movidos integer := 0; v_perfil_movido boolean := false; v_tenencia text := 'sin_cambios';  -- F2.b [D-2]
begin
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.puede_cambiar_atencion() then
    raise exception 'Solo Gerencia o administradores del portal cambian la atención' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  if p_inversionista is null or p_nuevo_responsable is null then
    raise exception 'Faltan la persona o el nuevo responsable' using errcode = '22023';
  end if;
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  -- jerarquía compartida (el offboarding la toma exclusiva) + Gerencia y destinatario revalidados bajo ella -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.puede_cambiar_atencion() then
    raise exception 'Solo Gerencia o administradores del portal cambian la atención (membresía revalidada)' using errcode = '42501';
  end if;
  if not coalesce(private.rol_crm(p_nuevo_responsable) in ('vendedor', 'supervisor', 'gerencia'), false) then
    raise exception 'El nuevo responsable debe ser un miembro activo del equipo comercial (rol efectivo)' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: reasigna en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  -- F2.b [D-2] (Codex #12): el motivo se revalida contra los documentos BAJO el lock de la persona (la validación de
  -- arriba corre antes del lock y una corrección documental concurrente pudo cambiarlos).
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;
  if v_tramo.id is not null and v_tramo.responsable_id = p_nuevo_responsable
     and v_inv.responsable_relacion_id = p_nuevo_responsable
     and (private.rol_crm(p_nuevo_responsable) = 'gerencia' or (
       (v_inv.perfil_id is null or exists (select 1 from public.perfiles p where p.id=v_inv.perfil_id and p.asesor_perfil_id=p_nuevo_responsable and p.asesor_id is null))
       and not exists(select 1 from crm.leads l where l.id in (select x from private.leads_de_personas(array[p_inversionista]) x)
         and l.activo and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
         and (l.vendedor_id is distinct from p_nuevo_responsable or l.asignado_supervisor_id is not null)))) then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista, 'tramo_id', v_tramo.id);
  end if;
  -- F2.b [D-2]: capacidad operativa del nuevo responsable. Si puede tener cartera (vendedor/supervisor activo, rol
  -- efectivo), los leads VIVOS en tenencia operativa de la persona (enlace ∪ puente ∪ sueltos con su documento, D-13)
  -- pasan a su cartera y el perfil cliente de la persona también. Orden: persona (ya) → tramo (ya) → tareas
  -- pendientes → leads → perfil, como el veto (b2) y la fusión (b5). Con Gerencia como nuevo responsable no hay
  -- cartera que mover: solo el tramo (tenencia = 'sin_cambios').
  v_rol_nuevo := private.rol_crm(p_nuevo_responsable);
  if v_rol_nuevo in ('vendedor', 'supervisor') then
    select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_leads
    from (select l.id from crm.leads l
           where l.id in (select x from private.leads_de_personas(array[p_inversionista]) x)
             and l.activo = true
             and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
             and (l.vendedor_id is distinct from p_nuevo_responsable or l.asignado_supervisor_id is not null)
           order by l.id) s;
    -- (Codex N1/N4) tampoco se espera por una TAREA ni por el PERFIL: cerrar_tarea tiene la tarea y va tarea → lead/perfil;
    -- el Portal actualiza el perfil y su trigger va perfil → tareas. Con la persona y el tramo en la mano, todo lo demás
    -- se toma SIN esperar → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.tareas t
       where t.estado = 'pendiente'
         and (t.lead_id = any(v_leads) or (v_inv.perfil_id is not null and t.perfil_id = v_inv.perfil_id))
       order by t.id
       for update nowait;
      if v_inv.perfil_id is not null then
        perform 1 from public.perfiles p where p.id = v_inv.perfil_id for no key update nowait;
      end if;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando una tarea o la ficha de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    -- (Codex #1) tareas → leads es el orden de b2/D-3 y de cerrar_tarea; derivar y repartir van lead → tareas (por el
    -- trigger de sincronización) bajo el mismo interlock compartido. Como la fusión (b5, E3-9): los leads se toman
    -- SIN esperar; si otra sesión tiene uno → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    v_tenencia := 'movida';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_tramo.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo.id;
  end if;
  insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
  values (p_inversionista, p_nuevo_responsable, v_ahora, p_motivo, v_uid) returning id into v_nuevo_id;
  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;
  -- F2.b [D-2]: la cartera sigue al responsable (los triggers de leads llevan el ledger de asignaciones, la actividad
  -- «reasignacion», tenencia_desde y las tareas pendientes; el del perfil mueve las tareas de cliente y deja su actividad).
  if v_tenencia = 'movida' then
    if coalesce(pg_catalog.array_length(v_leads, 1), 0) > 0 then
      -- (auditor M2) se REVALIDA bajo los locks: sigue vivo, en etapa abierta y sigue siendo de la persona (un descarte o una
      -- conversión concurrentes solo bloquean el lead; la puerta del DNI de D-13 puede llevarse un suelto a otra persona).
      update crm.leads l
         set vendedor_id = p_nuevo_responsable,
             asignado_supervisor_id = null
       where l.id = any(v_leads)
         and l.activo = true
         and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
         and l.id in (select x from private.leads_de_personas(array[p_inversionista]) x);
      get diagnostics v_leads_movidos = row_count;
    end if;
    if v_inv.perfil_id is not null then
      update public.perfiles p
         set asesor_perfil_id = p_nuevo_responsable,
             asesor_id = null,
             actualizado_en = pg_catalog.clock_timestamp()
       where p.id = v_inv.perfil_id and p.rol = 'cliente' and p.activo is true
         and (p.asesor_perfil_id is distinct from p_nuevo_responsable or p.asesor_id is not null);
      v_perfil_movido := found;
    end if;
    -- (auditor N5) «movida» solo si algo se movió de verdad.
    if v_leads_movidos = 0 and not v_perfil_movido then
      v_tenencia := 'sin_cambios';
    end if;
  end if;
  select * into v_lead from crm.leads where inversionista_id = p_inversionista and activo = true order by id limit 1;
  if v_lead.id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Atención del cliente actualizada',
            pg_catalog.jsonb_build_object('evento', 'reasignacion_responsable', 'inversionista_id', p_inversionista,
                                          'anterior', v_tramo.responsable_id, 'nuevo', p_nuevo_responsable, 'tramo_id', v_nuevo_id),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'reasignado', 'inversionista_id', p_inversionista,
    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable,
    'tenencia', pg_catalog.jsonb_build_object('estado', v_tenencia, 'leads_movidos', v_leads_movidos, 'perfil_movido', v_perfil_movido));  -- F2.b [D-2]
end;
$$;



-- Resolución hipotética de solo lectura. La postcondición compara contra el
-- núcleo vivo: una divergencia revierte la transacción, nunca anuncia éxito.
create or replace function private.analista_previsto_contrato(
 p_contrato uuid, p_respaldo uuid, p_venta uuid, p_destino uuid,
 p_cliente uuid, p_asesor uuid) returns uuid
language sql stable set search_path='' as $$
 with recursive cadena as (
   select p_contrato id, 0 nivel, array[p_contrato] visitados
   union all
   select o.contrato_origen_id, c.nivel+1, c.visitados||o.contrato_origen_id
   from cadena c join crm.operaciones_cartera o on o.contrato_nuevo_id=c.id
   where o.contrato_origen_id is not null and not o.contrato_origen_id=any(c.visitados) and c.nivel<100
 ), base as (
   select coalesce((select case when c.id=p_venta then p_destino else c.analista_cierre_id end
     from cadena x join public.contratos c on c.id=x.id where c.categoria='upgrade' order by x.nivel limit 1),
     p_respaldo) analista
 )
 select private.heredero_de_baja(b.analista,
   case when c.cliente_id=p_cliente then p_asesor else p.asesor_perfil_id end)
 from base b join public.contratos c on c.id=p_contrato join public.perfiles p on p.id=c.cliente_id;
$$;

create or replace function private.cambio_responsabilidad_previa(p_accion text,p_id uuid,p_destino uuid)
returns jsonb language plpgsql volatile set search_path='' as $$
declare
 v_persona crm.inversionistas%rowtype; v_perfil public.perfiles%rowtype; v_contrato public.contratos%rowtype;
 v_venta uuid; v_cliente uuid; v_asesor uuid; v_actual uuid; v_operativo boolean;
 v_ids uuid[]; v_efectos jsonb; v_estado jsonb; v_leads jsonb; v_tareas jsonb; v_version text;
begin
 if p_accion is null or p_accion not in ('venta','atencion_persona','atencion_cliente') then
   raise exception 'Acción desconocida' using errcode='22023';
 end if;
 if auth.uid() is null or private.membresia_crm_revocada() or
   (case when p_accion='venta' then not (public.es_gestor_cartera() or coalesce(private.rol_crm(auth.uid())='gerencia',false))
    else not private.puede_cambiar_atencion() end) then
   raise exception 'No autorizado para esta acción' using errcode='42501';
 end if;
 if p_id is null or p_destino is null then raise exception 'Selecciona origen y destino' using errcode='22023'; end if;
 if not exists(select 1 from crm.equipo e where e.perfil_id=p_destino and e.rol_crm in ('vendedor','supervisor','gerencia')
   and (p_accion='venta' or private.rol_crm(p_destino) in ('vendedor','supervisor','gerencia'))) then
   raise exception 'El destino no pertenece al equipo comercial habilitado' using errcode='22023';
 end if;
 if p_accion='venta' then
   select * into v_contrato from public.contratos where id=p_id;
   if not found then raise exception 'Contrato no encontrado' using errcode='P0002'; end if;
   if v_contrato.es_demo then raise exception 'Un contrato de prueba no se atribuye a nadie' using errcode='22023'; end if;
   v_venta:=p_id; v_cliente:=v_contrato.cliente_id; v_actual:=v_contrato.analista_cierre_id;
 elsif p_accion='atencion_persona' then
   select * into v_persona from crm.inversionistas where id=p_id;
   if not found then raise exception 'La persona no existe' using errcode='P0002'; end if;
   v_cliente:=v_persona.perfil_id;
 else
   v_cliente:=p_id;
 end if;
 if v_cliente is not null then
   select * into v_perfil from public.perfiles where id=v_cliente and rol='cliente';
   if not found then raise exception 'Cliente no encontrado' using errcode='P0002'; end if;
   if p_accion<>'venta' and v_perfil.activo is not true then
     raise exception 'La ficha del cliente está inactiva; requiere revisión' using errcode='P0409';
   end if;
   if v_persona.id is null then select * into v_persona from crm.inversionistas where perfil_id=v_cliente and estado<>'fusionado'; end if;
 end if;
 if p_accion<>'venta' then
   if not private.resolver_en_puertas_bajo_candado() then
     raise exception 'Identidad unificada apagada' using errcode='P0409';
   end if;
   if v_persona.id is not null and v_persona.estado<>'activo' then
     raise exception 'Usa una identidad canónica activa' using errcode='P0409';
   end if;
   v_actual:=coalesce(v_persona.responsable_relacion_id,v_perfil.asesor_perfil_id);
 end if;
 v_operativo:=private.rol_crm(p_destino) in ('vendedor','supervisor');
 v_asesor:=case when p_accion<>'venta' and v_operativo then p_destino else v_perfil.asesor_perfil_id end;
 if p_accion<>'venta' and v_persona.id is null and not v_operativo then
   raise exception 'Un cliente sin identidad unificada requiere un responsable con cartera' using errcode='22023';
 end if;
 -- Todos los contratos de la ficha y descendientes: también protege el conjunto
 -- frente a cadenas nuevas. El token no expone los datos internos usados para versionar.
 with recursive alcance as (
   select c.id from public.contratos c where c.cliente_id=v_cliente
   union
   select o.contrato_nuevo_id from alcance a join crm.operaciones_cartera o on o.contrato_origen_id=a.id
 ) select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_ids from alcance;
 select coalesce(jsonb_agg(jsonb_build_object(
   'tipo','contrato','id',c.id,'numero',c.numero_contrato,'fecha',c.fecha_cierre_comercial,
   'moneda',c.moneda,'monto',c.capital,'anterior',private.analista_efectivo_contrato(c.id,c.analista_cierre_id),
   'previsto',private.analista_previsto_contrato(c.id,case when c.id=v_venta then p_destino else c.analista_cierre_id end,
     v_venta,p_destino,v_cliente,v_asesor),
   'desglose_anterior',case when o.id is not null and o.desglose_completo then private.analista_efectivo_contrato(c.id,o.vendedor_id) end,
   'desglose_previsto',case when o.id is not null and o.desglose_completo then private.analista_previsto_contrato(c.id,o.vendedor_id,v_venta,p_destino,v_cliente,v_asesor) end
 ) order by c.id),'[]') into v_efectos from public.contratos c
 left join crm.operaciones_cartera o on o.contrato_nuevo_id=c.id where c.id=any(v_ids) and not c.es_demo;
 if p_accion<>'venta' and v_persona.id is not null then
   select v_efectos||coalesce(jsonb_agg(jsonb_build_object(
     'tipo','cooperativa','id',ce.id,'numero',ce.cooperativa,'fecha',ce.fecha_comercial,
     'moneda',ce.moneda,'monto',ce.monto,'anterior',private.analista_efectivo_cierre(ce.id),
     'previsto',private.heredero_de_baja(ce.vendedor_id,p_destino),
     'desglose_anterior',null,'desglose_previsto',null) order by ce.id),'[]') into v_efectos
   from crm.cierres_externos ce left join crm.leads l on l.id=ce.lead_id
   where coalesce(ce.inversionista_id,l.inversionista_id)=v_persona.id;
 end if;
 if p_accion='venta' and exists(select 1 from jsonb_array_elements(v_efectos) e
   where e->>'id'=p_id::text and (e->>'previsto' is not distinct from e->>'anterior')
   and v_actual is distinct from p_destino) then
   raise exception 'Esta venta hereda su atribución. Corrige el contrato de origen de la cadena o revisa la baja del analista' using errcode='P0409';
 end if;
 if p_accion='venta' and exists(select 1 from jsonb_array_elements(v_efectos) e
   where e->>'desglose_previsto' is not null and e->>'desglose_previsto' is distinct from e->>'previsto') then
   raise exception 'El desglose y la venta quedarían atribuidos a personas distintas. Esta cadena requiere conciliación' using errcode='P0409';
 end if;
 select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]') into v_leads from crm.leads l
 where v_persona.id is not null and l.id in(select x from private.leads_de_personas(array[v_persona.id]) x)
   and l.activo and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada');
 select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]') into v_tareas from crm.tareas t
 where t.estado='pendiente' and (t.perfil_id=v_cliente or t.inversionista_id=v_persona.id
   or t.lead_id in(select (l->>'id')::uuid from jsonb_array_elements(v_leads) l));
 v_estado:=jsonb_build_object('actor',auth.uid(),'accion',p_accion,'id',p_id,'destino',p_destino,
   'persona',to_jsonb(v_persona),'perfil',to_jsonb(v_perfil),'efectos',v_efectos,'leads',v_leads,'tareas',v_tareas,
   'tramos',(select jsonb_agg(to_jsonb(r) order by r.id) from crm.inversionista_responsables r where r.inversionista_id=v_persona.id and r.hasta is null),
   'contratos',(select jsonb_agg(to_jsonb(c) order by c.id) from public.contratos c where c.id=any(v_ids)),
   'operaciones',(select jsonb_agg(to_jsonb(o) order by o.id) from crm.operaciones_cartera o where o.contrato_nuevo_id=any(v_ids) or o.contrato_origen_id=any(v_ids)),
   'equipo',(select jsonb_agg(to_jsonb(e) order by e.perfil_id) from crm.equipo e),
   'perfiles_equipo',(select jsonb_agg(jsonb_build_array(p.id,p.activo,p.rol) order by p.id) from public.perfiles p where exists(select 1 from crm.equipo e where e.perfil_id=p.id)),
   'cierres',(select jsonb_agg(to_jsonb(ce) order by ce.id) from crm.cierres_externos ce where ce.id in(select (e->>'id')::uuid from jsonb_array_elements(v_efectos) e where e->>'tipo'='cooperativa')),
   'periodos',(select jsonb_agg(to_jsonb(pc) order by pc.periodo) from crm.periodos_cerrados pc));
 v_version:=md5(v_estado::text);
 select coalesce(jsonb_agg(e||jsonb_build_object(
   'anterior_nombre',(select nombre_completo from public.perfiles where id=(e->>'anterior')::uuid),
   'previsto_nombre',(select nombre_completo from public.perfiles where id=(e->>'previsto')::uuid))), '[]')
 into v_efectos from jsonb_array_elements(v_efectos) e;
 return jsonb_build_object('version',v_version,'accion',p_accion,'id',p_id,'destino',p_destino,
   'persona_id',v_persona.id,'cliente_id',v_cliente,'anterior',v_actual,
   'anterior_nombre',(select nombre_completo from public.perfiles where id=v_actual),
   'destino_nombre',(select nombre_completo from public.perfiles where id=p_destino),
   'perfil_cambia',p_accion<>'venta' and v_cliente is not null and v_operativo and v_perfil.asesor_perfil_id is distinct from p_destino,
   'leads',case when p_accion<>'venta' and v_operativo then jsonb_array_length(v_leads) else 0 end,
   'tareas',case when p_accion<>'venta' then jsonb_array_length(v_tareas) else 0 end,
   'efectos',v_efectos,
   'aviso',case when p_accion='venta' then 'Corrige la venta y su atribución efectiva. El capital y las fotos de meses sellados se conservan.'
     when not v_operativo then 'Gerencia asume la relación. Se conserva la cartera operativa del asesor; las ventas históricas conservan su vendedor registrado.'
     else 'Cambia la atención y la cartera operativa. Conserva el vendedor registrado de cada venta; la herencia por baja puede cambiar su atribución efectiva.' end);
end;
$$;

create or replace function private.ejecutar_cambio_responsabilidad(
 p_accion text,p_id uuid,p_destino uuid,p_motivo text,p_version text,p_legacy boolean default false)
returns jsonb language plpgsql set search_path='' set lock_timeout='5s' as $$
declare
 v_pre jsonb; v_pos jsonb; v_resultado jsonb; v_persona uuid; v_cliente uuid; v_rastro uuid;
 v_ids uuid[]; v_anterior uuid; v_e jsonb; v_real uuid; v_motivo text:=btrim(p_motivo);
 v_config text:=current_setting('crm.atencion_autorizada',true);
begin
 if not p_legacy and nullif(p_version,'') is null then raise exception 'Revisa el efecto antes de confirmar' using errcode='22023'; end if;
 if v_motivo is null or length(v_motivo)<(case when p_accion='venta' then 1 else 3 end)
   or length(v_motivo)>(case when p_accion='venta' then 300 else 500 end) then
   raise exception 'Escribe un motivo válido para el cambio' using errcode='22023';
 end if;
 -- Mismo orden que offboarding y cambios de identidad.
 perform private.resolver_en_puertas_bajo_candado();
 perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
 v_pre:=private.cambio_responsabilidad_previa(p_accion,p_id,p_destino);
 v_persona:=(v_pre->>'persona_id')::uuid; v_cliente:=(v_pre->>'cliente_id')::uuid;
 begin
   perform 1 from public.perfiles where id in (auth.uid(),p_destino) order by id for share nowait;
   perform 1 from crm.inversionistas where id=v_persona for update nowait;
   perform 1 from crm.inversionista_responsables where inversionista_id=v_persona and hasta is null order by id for update nowait;
   perform 1 from crm.tareas t where t.estado='pendiente' and (t.perfil_id=v_cliente or t.inversionista_id=v_persona
     or t.lead_id in(select x from private.leads_de_personas(array[v_persona]) x)) order by t.id for update nowait;
   perform 1 from crm.leads l where v_persona is not null and l.id in(select x from private.leads_de_personas(array[v_persona]) x) order by l.id for update nowait;
   -- FOR UPDATE además protege inserciones de contratos por la FK del cliente.
   perform 1 from public.perfiles where id=v_cliente for update nowait;
   select coalesce(array_agg((e->>'id')::uuid),'{}') into v_ids from jsonb_array_elements(v_pre->'efectos') e where e->>'tipo'='contrato';
   perform 1 from public.contratos where id=any(v_ids) order by id for update nowait;
   perform 1 from crm.operaciones_cartera where contrato_nuevo_id=any(v_ids) or contrato_origen_id=any(v_ids) order by id for update nowait;
   perform 1 from crm.cierres_externos where id in(select (e->>'id')::uuid from jsonb_array_elements(v_pre->'efectos') e where e->>'tipo'='cooperativa') order by id for update nowait;
 exception when lock_not_available then
   raise exception 'Otra sesión está trabajando la ficha o sus operaciones. Vuelve a revisar' using errcode='40001';
 end;
 v_pos:=private.cambio_responsabilidad_previa(p_accion,p_id,p_destino);
 if v_pos->>'version' is distinct from v_pre->>'version' or (not p_legacy and v_pos->>'version' is distinct from p_version) then
   raise exception 'La información cambió. Revisa de nuevo el efecto antes de guardar' using errcode='40001';
 end if;
 -- Una firma antigua no puede confirmar atribución efectiva que no mostró:
 -- atención también hereda ventas de analistas dados de baja.
 if p_legacy and exists(select 1 from jsonb_array_elements(v_pre->'efectos') e
    where (p_accion<>'venta' or e->>'id'<>p_id::text)
      and e->>'anterior' is distinct from e->>'previsto') then
   raise exception 'El cambio también modifica la atribución de ventas. Usa la acción con vista previa' using errcode='P0409';
 end if;
 if p_accion='venta' then
   v_anterior:=(v_pre->>'anterior')::uuid;
   if v_anterior is not distinct from p_destino then raise exception 'Esa venta ya esta atribuida a esa persona' using errcode='P0409'; end if;
   insert into crm.reasignaciones_analista(contrato_id,analista_de,analista_a,motivo,reasignado_por)
   values(p_id,v_anterior,p_destino,v_motivo,auth.uid()) returning id into v_rastro;
   perform set_config('crm.reasignando_analista','on',true);
   update public.contratos set analista_cierre_id=p_destino where id=p_id;
   perform set_config('crm.reasignando_analista','off',true);
   v_resultado:=jsonb_build_object('ok',true,'contrato_id',p_id,'de',v_anterior,'a',p_destino,'reasignacion_id',v_rastro);
 else
   perform set_config('crm.atencion_autorizada',coalesce(v_cliente::text,''),true);
   if v_persona is not null then
     v_resultado:=private.cambiar_atencion_persona(v_persona,p_destino,v_motivo);
     if (select responsable_relacion_id from crm.inversionistas where id=v_persona) is distinct from p_destino
       or not exists(select 1 from crm.inversionista_responsables where inversionista_id=v_persona and hasta is null and responsable_id=p_destino) then
       raise exception 'No se pudo verificar la atención del cliente' using errcode='P0409';
     end if;
   else
     perform private.motivo_sin_documento(v_motivo,array[(select dni from public.perfiles where id=v_cliente)]);
     update public.perfiles set asesor_perfil_id=p_destino,asesor_id=null,actualizado_en=clock_timestamp() where id=v_cliente;
     -- Sin persona no existe tramo donde guardar el motivo. Se conserva en la
     -- timeline existente, junto al cambio de asesor registrado por su trigger.
     insert into crm.actividades_cliente(cliente_id,vendedor_id,tipo,detalle,creado_por)
     values(v_cliente,p_destino,'nota','Motivo del cambio de atención: '||v_motivo,auth.uid());
     v_resultado:=jsonb_build_object('ok',true,'estado','reasignado','cliente_id',v_cliente);
   end if;
   if private.rol_crm(p_destino) in ('vendedor','supervisor') and v_cliente is not null
     and not exists(select 1 from public.perfiles where id=v_cliente and asesor_perfil_id=p_destino and asesor_id is null) then
     raise exception 'El asesor del portal no quedó alineado. No se guardó el cambio' using errcode='P0409';
   end if;
   if private.rol_crm(p_destino) in ('vendedor','supervisor') and exists(
     select 1 from crm.leads l where v_persona is not null
       and l.id in(select x from private.leads_de_personas(array[v_persona]) x)
       and l.activo and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
       and (l.vendedor_id is distinct from p_destino or l.asignado_supervisor_id is not null)) then
     raise exception 'Los leads abiertos no quedaron alineados; se revierte el cambio' using errcode='P0409';
   end if;
   if exists(select 1 from crm.tareas t where t.activo and t.estado='pendiente'
     and (t.inversionista_id=v_persona or (private.rol_crm(p_destino) in ('vendedor','supervisor') and
       (t.perfil_id=v_cliente or t.lead_id in(select l.id from crm.leads l where l.id in(select x from private.leads_de_personas(array[v_persona]) x) and l.activo and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')))))
     and t.vendedor_id is distinct from p_destino) then
     raise exception 'Las tareas pendientes no quedaron alineadas; se revierte el cambio' using errcode='P0409';
   end if;
   perform set_config('crm.atencion_autorizada',coalesce(v_config,''),true);
 end if;
 -- Comprueba el resultado usando las funciones que realmente usa Facturación.
 for v_e in select value from jsonb_array_elements(v_pre->'efectos') loop
   if v_e->>'tipo'='contrato' then
     select private.analista_efectivo_contrato(c.id,c.analista_cierre_id) into v_real from public.contratos c where c.id=(v_e->>'id')::uuid;
     if v_e->>'desglose_previsto' is not null and (select private.analista_efectivo_contrato(o.contrato_nuevo_id,o.vendedor_id)::text
       from crm.operaciones_cartera o where o.contrato_nuevo_id=(v_e->>'id')::uuid) is distinct from v_e->>'desglose_previsto' then
       raise exception 'El desglose no coincide con el efecto confirmado' using errcode='P0409';
     end if;
   else v_real:=private.analista_efectivo_cierre((v_e->>'id')::uuid);
   end if;
   if v_real::text is distinct from v_e->>'previsto' then raise exception 'La atribución efectiva no coincide con lo confirmado' using errcode='P0409'; end if;
 end loop;
 return case when p_legacy then v_resultado else v_resultado||jsonb_build_object('efectos',v_pre->'efectos','version_confirmada',p_version) end;
end;
$$;

-- Puertas delgadas. Definer indispensable para modificar columnas protegidas y
-- aplicar una operación entre tablas con RLS; el núcleo revalida rol real/activo.
create or replace function crm.previsualizar_cambio_responsabilidad_fn(p_accion text,p_id uuid,p_destino uuid)
returns jsonb language sql volatile security definer set search_path='' as $$
 select private.cambio_responsabilidad_previa(p_accion,p_id,p_destino);
$$;
-- PostgREST 14.5 reintenta 40001 indefinidamente. El conflicto del núcleo se
-- traduce en la frontera HTTP: rollback de todo el bloque y PT409 sin reintento.
create or replace function crm.confirmar_cambio_responsabilidad_fn(p_accion text,p_id uuid,p_destino uuid,p_motivo text,p_version text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return private.ejecutar_cambio_responsabilidad(p_accion,p_id,p_destino,p_motivo,p_version);
exception when serialization_failure or deadlock_detected or lock_not_available then
 raise exception 'La información cambió o está siendo editada. Revisa de nuevo el efecto antes de guardar' using errcode='PT409';
end;
$$;
create or replace function public.reasignar_analista_contrato(p_contrato_id uuid,p_analista_id uuid,p_motivo text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return private.ejecutar_cambio_responsabilidad('venta',p_contrato_id,p_analista_id,p_motivo,null,true);
exception when serialization_failure or deadlock_detected or lock_not_available then
 raise exception 'La información cambió o está siendo editada. Vuelve a revisar la venta' using errcode='PT409';
end;
$$;
create or replace function crm.reasignar_responsable_relacion_fn(p_inversionista uuid,p_nuevo_responsable uuid,p_motivo text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.resolver_en_puertas_bajo_candado() then
   raise exception 'Identidad unificada apagada' using errcode='P0409';
 end if;
 if not private.es_gerencia_crm_activa() then raise exception 'Solo Gerencia reasigna el responsable de relación' using errcode='42501'; end if;
 return private.ejecutar_cambio_responsabilidad('atencion_persona',p_inversionista,p_nuevo_responsable,p_motivo,null,true);
exception when serialization_failure or deadlock_detected or lock_not_available then
 raise exception 'La información cambió o está siendo editada. Vuelve a revisar la atención' using errcode='PT409';
end;
$$;

-- INVOKER: current_user distingue UPDATE autenticado de un núcleo DEFINER.
-- No confía en una variable GUC que el cliente pueda fijar. Conserva los
-- escritores privilegiados inventariados: baja, revisión F4 y núcleo de atención.
create or replace function private.trg_perfiles_asesor_por_nucleo() returns trigger
language plpgsql set search_path='' as $$
begin
 if (new.asesor_perfil_id is distinct from old.asesor_perfil_id or new.asesor_id is distinct from old.asesor_id)
    and current_user<>'postgres' then
   raise exception 'Para cambiar la atención usa la acción Cambiar quién atiende al cliente' using errcode='42501';
 end if;
 return new;
end;
$$;
create trigger aaa_asesor_solo_nucleo before update of asesor_perfil_id,asesor_id on public.perfiles
for each row execute function private.trg_perfiles_asesor_por_nucleo();


-- El contexto transaccional no es una capacidad: verifica también el estado
-- canónico recién escrito y su tramo. Un GUC falsificado no permite desalinear.
create or replace function private.atencion_perfil_permitida(p_cliente uuid,p_destino uuid)
returns boolean language sql stable set search_path='' as $$
 select private.puede_cambiar_atencion() and p_destino is not null
   and private.rol_crm(p_destino) in ('vendedor','supervisor')
   and (not exists(select 1 from crm.inversionistas i where i.perfil_id=p_cliente and i.estado<>'fusionado')
     or exists(select 1 from crm.inversionistas i join crm.inversionista_responsables r on r.inversionista_id=i.id
       where i.perfil_id=p_cliente and i.estado='activo' and i.responsable_relacion_id=p_destino
         and r.hasta is null and r.responsable_id=p_destino));
$$;
revoke all on function private.atencion_perfil_permitida(uuid,uuid) from public,anon,authenticated,service_role;
comment on function private.atencion_perfil_permitida(uuid,uuid) is 'Valida autoridad activa y alineación real persona/tramo antes de liberar las columnas de atención. El GUC no autoriza por sí solo.';

CREATE OR REPLACE FUNCTION "public"."proteger_campos_inmutables"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_f4_alinea boolean := false;
  v_atencion boolean := false;
BEGIN
  -- Excepción de una única columna desde la revisión F4 del servidor. Las
  -- escrituras directas mantienen todas las congelaciones originales.
  IF TG_TABLE_NAME='perfiles' AND current_user='postgres'
     AND nullif(current_setting('crm.f4_revision_solicitud',true),'') IS NOT NULL THEN
    v_f4_alinea:=private.f4_alineacion_perfil_permitida(OLD.id,NEW.asesor_perfil_id);
  END IF;
  IF TG_TABLE_NAME='perfiles' AND current_user='postgres' THEN
    IF current_setting('crm.atencion_autorizada',true)=OLD.id::text THEN
      IF private.atencion_perfil_permitida(OLD.id,NEW.asesor_perfil_id) THEN
        v_f4_alinea:=true; v_atencion:=true;
      END IF;
    END IF;
  END IF;
  NEW.id         := OLD.id;
  NEW.creado_en  := OLD.creado_en;
  NEW.creado_por := OLD.creado_por;

  -- Campos privilegiados / de asignacion: se congelan para el usuario que edita su PROPIA
  -- fila (cliente) y TAMBIEN para un ANALISTA que edita la fila de un cliente. Antes solo se
  -- congelaban en la auto-edicion (NEW.id=auth.uid()), por eso un analista podia togglear
  -- activo / debe_cambiar_password / blanquear asesor_perfil_id de su cliente via UPDATE forjado.
  -- admin/superadmin quedan EXCLUIDOS (siguen reasignando/activando). service_role
  -- (auth.uid() IS NULL, no es_analista) NO se ve afectado -> las edges de alta/baja siguen igual.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND ( NEW.id = auth.uid() OR public.es_analista() ) THEN
    NEW.activo           := OLD.activo;
    NEW.rol              := OLD.rol;
    IF NOT v_atencion THEN NEW.asesor_id := OLD.asesor_id; END IF;
    IF NOT v_f4_alinea THEN NEW.asesor_perfil_id := OLD.asesor_perfil_id; END IF;
    NEW.cargo            := OLD.cargo;
    -- El flag de cambio de clave solo lo baja el PROPIO usuario (primer login);
    -- un analista editando a un cliente NO puede tocarlo.
    IF NEW.id <> auth.uid() THEN
      NEW.debe_cambiar_password := OLD.debe_cambiar_password;
    END IF;
  END IF;

  -- Asiento «Operaciones» (2026-08-21): edita al cliente y lo activa o desactiva,
  -- pero NO lo mueve de analista. El `rol` se congela ademas por si acaso: la
  -- politica ya lo acota a 'cliente', esto es la segunda linea de defensa.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND public.es_operaciones()
     AND NEW.id <> auth.uid() THEN
    IF (NEW.asesor_perfil_id IS DISTINCT FROM OLD.asesor_perfil_id AND NOT v_f4_alinea)
       OR NEW.asesor_id IS DISTINCT FROM OLD.asesor_id THEN
      RAISE EXCEPTION 'El asiento Operaciones no puede reasignar el asesor de un cliente'
        USING ERRCODE = '42501';
    END IF;
    NEW.rol := OLD.rol;
  END IF;

  -- Ciclo de vida de contratos (2026-07-13): una vez cerrado un ciclo, el
  -- enlace de renovacion y los sellos de cierre quedan congelados para
  -- cualquier no-superadmin (correcciones = superadmin).
  IF TG_TABLE_NAME = 'contratos' AND NOT public.es_superadmin() THEN
    IF OLD.renovado_a_id IS NOT NULL THEN NEW.renovado_a_id := OLD.renovado_a_id; END IF;
    IF OLD.cerrado_en    IS NOT NULL THEN NEW.cerrado_en    := OLD.cerrado_en;    END IF;
    IF OLD.cerrado_por   IS NOT NULL THEN NEW.cerrado_por   := OLD.cerrado_por;   END IF;
  END IF;

  RETURN NEW;
END; $$;

revoke all on function private.puede_cambiar_atencion() from public,anon,authenticated,service_role;
comment on function private.puede_cambiar_atencion() is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function private.cambiar_atencion_persona(uuid,uuid,text) from public,anon,authenticated,service_role;
comment on function private.cambiar_atencion_persona(uuid,uuid,text) is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function private.analista_previsto_contrato(uuid,uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
comment on function private.analista_previsto_contrato(uuid,uuid,uuid,uuid,uuid,uuid) is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function private.cambio_responsabilidad_previa(text,uuid,uuid) from public,anon,authenticated,service_role;
comment on function private.cambio_responsabilidad_previa(text,uuid,uuid) is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function private.ejecutar_cambio_responsabilidad(text,uuid,uuid,text,text,boolean) from public,anon,authenticated,service_role;
comment on function private.ejecutar_cambio_responsabilidad(text,uuid,uuid,text,text,boolean) is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function crm.previsualizar_cambio_responsabilidad_fn(text,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function crm.previsualizar_cambio_responsabilidad_fn(text,uuid,uuid) to authenticated;
comment on function crm.previsualizar_cambio_responsabilidad_fn(text,uuid,uuid) is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function crm.confirmar_cambio_responsabilidad_fn(text,uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function crm.confirmar_cambio_responsabilidad_fn(text,uuid,uuid,text,text) to authenticated;
comment on function crm.confirmar_cambio_responsabilidad_fn(text,uuid,uuid,text,text) is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function public.reasignar_analista_contrato(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.reasignar_analista_contrato(uuid,uuid,text) to authenticated;
comment on function public.reasignar_analista_contrato(uuid,uuid,text) is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function crm.reasignar_responsable_relacion_fn(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function crm.reasignar_responsable_relacion_fn(uuid,uuid,text) to authenticated;
comment on function crm.reasignar_responsable_relacion_fn(uuid,uuid,text) is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function private.trg_perfiles_asesor_por_nucleo() from public,anon,authenticated,service_role;
comment on function private.trg_perfiles_asesor_por_nucleo() is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

revoke all on function public.proteger_campos_inmutables() from public,anon,authenticated,service_role;
grant execute on function public.proteger_campos_inmutables() to authenticated;
comment on function public.proteger_campos_inmutables() is 'Atención y venta separadas. Núcleo con autorización real y comprobación atómica; candidata aprobada 13/10/2026. Ver docs/encargos/facturacion-atribucion-20261013/PLAN.md.';

comment on trigger aaa_asesor_solo_nucleo on public.perfiles is 'Bloquea UPDATE directo de asesor; admite núcleos con privilegios de postgres. OK explícito Miguel 13/10/2026.';
commit;
