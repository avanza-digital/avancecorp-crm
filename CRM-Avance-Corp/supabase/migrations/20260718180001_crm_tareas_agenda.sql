-- Agenda comercial · Fase A — crm.tareas (motor de proxima accion).
--
-- Diseno completo en el vault: "Agenda comercial del CRM (plan v2)".
-- Dos tablas con roles distintos, NO dos fuentes de verdad:
--   crm.tareas      = FUTURO, mutable (pendiente -> completada|cancelada|no_show)
--   crm.actividades = PASADO, log inmutable (INSERT-only; NO se toca aqui)
-- El puente es crm.cerrar_tarea(): cierra la tarea + inserta el resultado en el
-- log + crea la siguiente, en UNA transaccion.
--
-- Reglas clave:
--  * "vencida" se DERIVA (estado='pendiente' AND vence_en < now()) — jamas se
--    guarda: sin cron, sin drift.
--  * Reagendar tras no-show NO revive la tarea: crea una NUEVA encadenada por
--    reagendada_de (la metrica anti no-show cuenta filas cerradas en no_show).
--  * La tenencia (vendedor_id / asignado_supervisor_id) se DERIVA del lead en
--    el INSERT y los triggers de coherencia la siguen: reasignar el lead mueve
--    sus tareas pendientes; cerrar el lead las cancela.
--  * RLS calcada de leads_* (helpers private.* existentes); es_lector_global
--    SOLO en SELECT; sin DELETE (cancelar = estado).
--  * Completar/no_show van SOLO por la RPC (flag crm.op_tarea): el UPDATE
--    directo del cliente solo puede cancelar o reprogramar.
--
-- Incluye ademas (misma pasada de gate, aditivas):
--  * crm.leads.no_contactar + consentimiento_en/fuente (capa legal peruana:
--    Ley 29571 / INDECOPI "No Insista"). GRANT POR COLUMNA obligatorio:
--    crm.leads tiene privilegios por columna (trampa documentada 2026-07-18).
--
-- Frontera: solo esquema crm (las FKs a public.perfiles ya existian en leads).

set local lock_timeout = '10s';

-- ── 1) Tabla ──────────────────────────────────────────────────────────────────

create table crm.tareas (
  id                     uuid primary key default gen_random_uuid(),
  -- Exactamente UN sujeto: lead (venta) o perfil de cliente (postventa/cobranza,
  -- fase posterior — la columna nace hoy para no pagar otro ciclo de gate).
  lead_id                uuid references crm.leads(id) on delete cascade,
  perfil_id              uuid references public.perfiles(id) on delete cascade,
  -- Tenencia (espejo del lead, mantenida por triggers): null = tarea de bandeja
  -- de un lead parkeado, visible/operable por su supervisor.
  vendedor_id            uuid references crm.equipo(perfil_id) on delete set null,
  asignado_supervisor_id uuid references crm.equipo(perfil_id) on delete set null,
  tipo                   text not null
                         constraint tareas_tipo_valido
                         check (tipo in ('llamada','whatsapp','reunion','tarea')),
  titulo                 text not null
                         constraint tareas_titulo_valido
                         check (length(btrim(titulo)) between 1 and 200),
  nota                   text
                         constraint tareas_nota_valida
                         check (nota is null or length(nota) <= 2000),
  -- Cuando TOCA hacerla. Es aviso, no deadline (modelo Close): "vencida" se
  -- deriva de aqui y las vencidas van primero en la cola, nunca se esconden.
  vence_en               timestamptz not null
                         constraint tareas_vence_en_cuerda
                         check (vence_en >= timestamptz '2026-01-01 00:00Z'
                            and vence_en <  timestamptz '2100-01-01 00:00Z'),
  duracion_min           smallint
                         constraint tareas_duracion_valida
                         check (duracion_min is null or duracion_min between 5 and 480),
  estado                 text not null default 'pendiente'
                         constraint tareas_estado_valido
                         check (estado in ('pendiente','completada','cancelada','no_show')),
  -- Puente al log inmutable: la actividad que registro el cierre (via RPC).
  resultado_actividad_id uuid references crm.actividades(id) on delete set null,
  -- Cadena de reagendas post no-show (la cita nueva apunta a la caida).
  reagendada_de          uuid references crm.tareas(id) on delete set null,
  -- Anti no-show: cuando el cliente respondio al recordatorio confirmando.
  confirmada_en          timestamptz,
  -- Contador mantenido por trigger (cambiar vence_en en pendiente lo incrementa;
  -- el cliente no puede escribirlo directo).
  reprogramaciones       smallint not null default 0
                         constraint tareas_reprogramaciones_validas
                         check (reprogramaciones >= 0),
  activo                 boolean not null default true,
  creado_por             uuid references public.perfiles(id) on delete set null,
  creado_en              timestamptz not null default now(),
  actualizado_en         timestamptz not null default now(),
  constraint tareas_un_solo_sujeto check (num_nonnulls(lead_id, perfil_id) = 1),
  -- Una tarea viva no puede tener resultado; el resultado llega con el cierre.
  constraint tareas_cierre_coherente
    check (estado <> 'pendiente' or resultado_actividad_id is null)
);

comment on table crm.tareas is
  'Agenda comercial: acciones FUTURAS mutables (el pasado vive en crm.actividades, log inmutable). Vencida se deriva (pendiente + vence_en < now()); cierre por crm.cerrar_tarea().';
comment on column crm.tareas.vence_en is
  'Cuando toca la accion. Aviso, no deadline: vencida = pendiente AND vence_en < now(). La ventana legal peruana (L-S 07:00-20:00, Ley 29571) la aplica la UI al proponer fechas.';
comment on column crm.tareas.vendedor_id is
  'Tenencia espejo del lead (mantenida por trigger): null = bandeja del supervisor (lead parkeado). En tareas de perfil (postventa) es el dueno directo.';
comment on column crm.tareas.confirmada_en is
  'Anti no-show: momento en que el cliente confirmo la cita respondiendo al recordatorio.';
comment on column crm.tareas.reagendada_de is
  'Tarea previa cerrada en no_show que esta reagenda. La metrica de no-shows cuenta filas en estado no_show.';

-- Indices de la cola (HOY: vendedor + estado + vence_en) y de los huerfanos.
create index tareas_cola_idx on crm.tareas (vendedor_id, estado, vence_en);
create index tareas_lead_pendiente_idx on crm.tareas (lead_id) where estado = 'pendiente';
create index tareas_bandeja_idx on crm.tareas (asignado_supervisor_id)
  where vendedor_id is null and estado = 'pendiente';
-- Indices FK (clase de advisor ya conocida: FKs sin indice).
create index tareas_perfil_idx on crm.tareas (perfil_id) where perfil_id is not null;
create index tareas_creado_por_idx on crm.tareas (creado_por);
create index tareas_resultado_actividad_idx on crm.tareas (resultado_actividad_id)
  where resultado_actividad_id is not null;
create index tareas_reagendada_de_idx on crm.tareas (reagendada_de)
  where reagendada_de is not null;

-- ── 2) Triggers propios de crm.tareas ────────────────────────────────────────

-- INSERT: deriva la tenencia del lead (estructuralmente coherente: la tarea
-- cuelga del lead, no de lo que diga el payload) y exige nacer pendiente.
create or replace function private.trg_tareas_before_insert()
returns trigger
language plpgsql
security definer
set search_path = crm, private, public
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
  -- Nacer cerrada solo con el flag privilegiado (RPC/seed), nunca desde el cliente.
  if new.estado <> 'pendiente'
     and coalesce(current_setting('crm.op_tarea', true), 'off') <> 'on' then
    raise exception 'Una tarea nace pendiente; los cierres van por crm.cerrar_tarea()';
  end if;
  return new;
end;
$$;

-- UPDATE: integridad de la maquina de estados y de los campos de sistema.
--  * cerrada => inmutable (reagendar un no_show = tarea NUEVA encadenada).
--  * completar/no_show SOLO via RPC (flag crm.op_tarea).
--  * cambiar vence_en en pendiente incrementa reprogramaciones (el cliente no
--    escribe el contador ni el puente al log).
create or replace function private.trg_tareas_before_update()
returns trigger
language plpgsql
security definer
set search_path = crm, private, public
as $$
declare
  v_op boolean := coalesce(current_setting('crm.op_tarea', true), 'off') = 'on';
begin
  if old.estado <> 'pendiente' then
    raise exception 'La tarea ya esta cerrada; reagendar crea una tarea nueva';
  end if;
  if new.estado in ('completada','no_show') and not v_op then
    raise exception 'Completar o marcar no-show va por crm.cerrar_tarea()';
  end if;
  if new.resultado_actividad_id is distinct from old.resultado_actividad_id and not v_op then
    raise exception 'El resultado lo escribe crm.cerrar_tarea()';
  end if;
  -- Trazabilidad inmutable (mismo criterio que leads): el origen no se reescribe.
  new.creado_por := old.creado_por;
  new.creado_en  := old.creado_en;
  new.lead_id    := old.lead_id;
  new.perfil_id  := old.perfil_id;
  new.reagendada_de := old.reagendada_de;
  -- Contador de sistema: reprogramar = cambiar la fecha de una pendiente.
  if new.vence_en is distinct from old.vence_en then
    new.reprogramaciones := old.reprogramaciones + 1;
  else
    new.reprogramaciones := old.reprogramaciones;
  end if;
  return new;
end;
$$;

create trigger trg_tareas_00_before_insert before insert on crm.tareas
  for each row execute function private.trg_tareas_before_insert();
create trigger trg_tareas_00_before_update before update on crm.tareas
  for each row execute function private.trg_tareas_before_update();
create trigger trg_tareas_touch before update on crm.tareas
  for each row execute function private.set_actualizado_en_crm();
create trigger trg_audit_tareas after insert or delete or update on crm.tareas
  for each row execute function private.log_audit_crm();

-- ── 3) Coherencia con el ciclo de vida del lead ──────────────────────────────
-- AFTER UPDATE sobre crm.leads: las tareas SIGUEN al lead (reasignacion) y un
-- lead cerrado no deja pendientes gritando "vencida" para siempre.
-- SECURITY DEFINER: es bookkeeping del sistema; jamas debe fallar por RLS del
-- usuario que disparo el cambio (p.ej. convertir_lead corre como definer).

create or replace function private.trg_leads_sync_tareas()
returns trigger
language plpgsql
security definer
set search_path = crm, private, public
as $$
begin
  -- Reasignacion / reparto de parkeado: propaga tenencia a las PENDIENTES.
  if (new.vendedor_id is distinct from old.vendedor_id)
     or (new.asignado_supervisor_id is distinct from old.asignado_supervisor_id) then
    update crm.tareas t
       set vendedor_id = new.vendedor_id,
           asignado_supervisor_id = new.asignado_supervisor_id
     where t.lead_id = new.id and t.estado = 'pendiente';
  end if;
  -- Cierre o soft-delete del lead: cancela las pendientes.
  if (new.etapa in ('convertido','descartado') and old.etapa not in ('convertido','descartado'))
     or (old.activo = true and new.activo = false) then
    update crm.tareas t
       set estado = 'cancelada'
     where t.lead_id = new.id and t.estado = 'pendiente';
  end if;
  return null;
end;
$$;

-- 'zz' para dispararse al final de la cadena de AFTER (orden alfabetico).
create trigger trg_leads_zz_sync_tareas after update on crm.leads
  for each row execute function private.trg_leads_sync_tareas();

-- ── 4) RLS (calcada de leads_*) ──────────────────────────────────────────────

alter table crm.tareas enable row level security;

create policy tareas_select on crm.tareas
  for select to authenticated
  using (
    (activo = true and (
      vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (vendedor_id is null
          and asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
      or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    ))
    or (select private.es_lector_global())  -- directorio/admin: lectura total
  );

create policy tareas_insert on crm.tareas
  for insert to authenticated
  with check (
    activo = true
    and creado_por = (select auth.uid())
    and (select private.rol_crm((select auth.uid()))) is not null
    -- La tenencia final la fijo el BEFORE trigger derivandola del lead; aqui se
    -- exige que ESE resultado caiga en mi ambito de escritura (espejo leads_insert).
    and (
      vendedor_id = (select auth.uid())
      or ((select private.rol_crm((select auth.uid()))) in ('supervisor','gerencia')
          and (vendedor_id is null
               or vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))))
    )
    and (asignado_supervisor_id is null
         or asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
  );

create policy tareas_update on crm.tareas
  for update to authenticated
  using (
    activo = true
    and (
      vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (vendedor_id is null
          and asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
      or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    )
  )
  with check (
    (vendedor_id is null
     or vendedor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    and (asignado_supervisor_id is null
         or asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    -- el soft-delete (activo=false) es privilegio de supervisor/gerencia
    and (activo = true or (select private.rol_crm((select auth.uid()))) in ('supervisor','gerencia'))
  );
-- SIN policy DELETE. directorio/admin NO aparecen en insert/update -> solo-lectura.

-- ── 5) RPC crm.cerrar_tarea — el puente atomico al log ───────────────────────

create or replace function crm.cerrar_tarea(
  p_tarea_id uuid,
  p_estado text,
  p_resultado_tipo text default null,
  p_resultado_detalle text default null,
  p_siguiente jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = crm, private, public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_tarea  crm.tareas%rowtype;
  v_act_id uuid;
  v_sig_id uuid;
  v_sig_tipo text;
  v_sig_titulo text;
  v_sig_vence timestamptz;
  v_sig_duracion smallint;
begin
  -- Solo la fuerza de ventas + gerencia cierran (directorio es solo-lectura).
  if v_uid is null or v_rol is null then
    raise exception 'No autorizado';
  end if;

  if p_estado not in ('completada','no_show','cancelada') then
    raise exception 'Estado de cierre invalido';
  end if;

  -- Ambito de ESCRITURA (espejo tareas_update) + lock: dos cierres simultaneos
  -- de la misma tarea no pueden colarse.
  select * into v_tarea
  from crm.tareas t
  where t.id = p_tarea_id
    and t.activo = true
    and t.estado = 'pendiente'
    and (
      t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (t.vendedor_id is null
          and t.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
      or v_rol = 'gerencia'
    )
  for update;
  if not found then
    raise exception 'Tarea no encontrada, cerrada o fuera de tu ambito';
  end if;

  -- Resultado: SOLO tipos manuales del log (los automaticos son de triggers) y
  -- SOLO en tareas de lead (actividades exige lead_id). Regla comercial: una
  -- LLAMADA completada exige resultado 1-tap (patron Outreach); en el resto es
  -- opcional (fricción minima).
  if p_resultado_tipo is not null then
    if v_tarea.lead_id is null then
      raise exception 'Una tarea de cliente no registra actividad de lead';
    end if;
    if p_resultado_tipo not in
       ('llamada_realizada','llamada_no_contestada','whatsapp_enviado',
        'whatsapp_recibido','reunion_realizada','nota') then
      raise exception 'Tipo de resultado invalido';
    end if;
  end if;
  if v_tarea.tipo = 'llamada' and p_estado = 'completada' and p_resultado_tipo is null then
    raise exception 'Registra el resultado de la llamada (contesto / no contesto)';
  end if;

  if p_resultado_tipo is not null then
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (v_tarea.lead_id, p_resultado_tipo, nullif(btrim(coalesce(p_resultado_detalle,'')), ''), v_uid)
    returning id into v_act_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas
     set estado = p_estado,
         resultado_actividad_id = v_act_id
   where id = p_tarea_id;

  -- Tarea siguiente opcional (el "completar y agendar siguiente" en un paso).
  if p_siguiente is not null then
    v_sig_tipo   := p_siguiente->>'tipo';
    v_sig_titulo := btrim(coalesce(p_siguiente->>'titulo',''));
    begin
      v_sig_vence := (p_siguiente->>'vence_en')::timestamptz;
    exception when others then
      raise exception 'Fecha invalida en la tarea siguiente';
    end;
    if p_siguiente->>'duracion_min' is not null then
      v_sig_duracion := (p_siguiente->>'duracion_min')::smallint;
    end if;
    if v_sig_tipo is null or v_sig_titulo = '' or v_sig_vence is null then
      raise exception 'La tarea siguiente exige tipo, titulo y vence_en';
    end if;
    perform set_config('crm.op_tarea', 'off', true);
    insert into crm.tareas
      (lead_id, perfil_id, tipo, titulo, nota, vence_en, duracion_min,
       reagendada_de, creado_por)
    values
      (v_tarea.lead_id, v_tarea.perfil_id, v_sig_tipo, v_sig_titulo,
       nullif(btrim(coalesce(p_siguiente->>'nota','')), ''), v_sig_vence, v_sig_duracion,
       case when p_estado = 'no_show' then p_tarea_id else null end, v_uid)
    returning id into v_sig_id;
  end if;
  perform set_config('crm.op_tarea', 'off', true);

  return jsonb_build_object(
    'ok', true,
    'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'siguiente_id', v_sig_id
  );
end;
$$;

-- ── 6) Columnas legales en crm.leads (Ley 29571 / INDECOPI) ──────────────────

alter table crm.leads
  add column no_contactar boolean not null default false,
  add column consentimiento_en timestamptz,
  add column consentimiento_fuente text
    constraint leads_consentimiento_fuente_valida
    check (consentimiento_fuente is null or length(consentimiento_fuente) <= 80);

comment on column crm.leads.no_contactar is
  'Flag DURO tipo "No Insista": apaga toda sugerencia de outreach del motor de la agenda. La UI lo respeta; no borra el lead.';
comment on column crm.leads.consentimiento_en is
  'Cuando el lead consintio ser contactado (registro para INDECOPI).';
comment on column crm.leads.consentimiento_fuente is
  'De donde salio el consentimiento (formulario web, referido, oficina...).';

-- crm.leads tiene GRANT POR COLUMNA: sin esto las columnas nuevas son
-- invisibles para PostgREST (trampa documentada en MIGRACIONES.md).
grant select (no_contactar, consentimiento_en, consentimiento_fuente)
  on crm.leads to authenticated, service_role;
grant insert (no_contactar, consentimiento_en, consentimiento_fuente)
  on crm.leads to authenticated, service_role;
grant update (no_contactar, consentimiento_en, consentimiento_fuente)
  on crm.leads to authenticated, service_role;

-- ── 7) Grants y hardening ────────────────────────────────────────────────────

grant select, insert, update on crm.tareas to authenticated;
grant select, insert, update on crm.tareas to service_role;
-- anon: nada (deny-by-default). Sin DELETE para nadie del API.

revoke all on function crm.cerrar_tarea(uuid, text, text, text, jsonb) from public, anon;
grant execute on function crm.cerrar_tarea(uuid, text, text, text, jsonb) to authenticated, service_role;
-- WARN authenticated_security_definer_function_executable: clase ACEPTADA y
-- documentada (mismo patron que convertir_lead/metricas_*): la RPC revoca
-- PUBLIC/anon y gatea por rol activo + ambito adentro.

revoke execute on function private.trg_tareas_before_insert() from public, anon, authenticated;
revoke execute on function private.trg_tareas_before_update() from public, anon, authenticated;
revoke execute on function private.trg_leads_sync_tareas()    from public, anon, authenticated;
