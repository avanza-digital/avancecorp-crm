-- Fase 0C: ledger analitico de episodios de asignacion.
--
-- Fronteras deliberadas:
--   * crm.actividades conserva el timeline humano.
--   * crm.lead_asignaciones conserva intervalos y snapshots analiticos.
--   * SLA/primer contacto se derivan luego; no se almacenan aqui.
--   * no se expone escritura ni lectura directa por Data API. La V1 consume
--     agregados mediante una RPC gerencia-gated en una migracion posterior.

begin;

-- El lock cierra la carrera entre validacion, backfill e instalacion del trigger.
-- ALTER TABLE tomara un lock aun mas fuerte y ambos se conservan hasta COMMIT.
lock table crm.leads in share row exclusive mode;

-- El ciclo vive en el lead, no solo en episodios: un lead puede reabrirse mientras
-- esta parqueado y, por tanto, atravesar un ciclo sin crear episodio de analista.
alter table crm.leads
  add column ciclo_actual integer not null default 1,
  add constraint leads_ciclo_actual_positivo check (ciclo_actual > 0) not valid,
  add constraint leads_tenencia_exclusiva
    check (vendedor_id is null or asignado_supervisor_id is null) not valid;

-- Recuperacion conservadora si hubiera aparecido informacion entre la
-- verificacion previa y este deploy. Las actividades de cambio de etapa son
-- estructuradas; cada descartado -> nuevo representa una reapertura real.
update crm.leads l
set ciclo_actual = 1 + coalesce((
  select count(*)::integer
  from crm.actividades a
  where a.lead_id = l.id
    and a.tipo = 'cambio_etapa'
    and a.metadata ->> 'etapa_anterior' = 'descartado'
    and a.metadata ->> 'etapa_nueva' = 'nuevo'
), 0);

alter table crm.leads validate constraint leads_ciclo_actual_positivo;
alter table crm.leads validate constraint leads_tenencia_exclusiva;

create extension if not exists btree_gist with schema extensions;

create table crm.lead_asignaciones (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm.leads(id) on delete restrict,
  ciclo_n integer not null check (ciclo_n > 0),
  episodio_n integer not null check (episodio_n > 0),
  analista_id uuid not null references crm.equipo(perfil_id) on delete restrict,

  motivo_apertura text not null check (motivo_apertura in (
    'ingreso',
    'asignado',
    'reasignado',
    'reabierto',
    'reactivado',
    'backfill_estado_actual'
  )),
  asignado_en timestamptz not null,
  asignado_por uuid references public.perfiles(id) on delete restrict,
  supervisor_origen_id uuid references crm.equipo(perfil_id) on delete restrict,

  -- Fotografia comercial: editar el lead despues no reescribe lo recibido.
  monto_estimado numeric(12,2) check (monto_estimado is null or monto_estimado >= 0),
  moneda text not null check (moneda in ('PEN', 'USD')),
  origen text not null,
  categoria_interes text,

  finalizado_en timestamptz,
  finalizado_por uuid references public.perfiles(id) on delete restrict,
  motivo_cierre text check (motivo_cierre in (
    'transferido',
    'parqueado',
    'convertido',
    'descartado',
    'desactivado'
  )),
  analista_destino_id uuid references crm.equipo(perfil_id) on delete restrict,
  supervisor_destino_id uuid references crm.equipo(perfil_id) on delete restrict,
  resultado text check (resultado in ('convertido', 'descartado')),
  resultado_en timestamptz,
  motivo_descarte_cierre text,

  aproximado boolean not null default false,
  creado_en timestamptz not null default now(),

  constraint lead_asignaciones_episodio_unico
    unique (lead_id, ciclo_n, episodio_n),
  constraint lead_asignaciones_intervalo_valido
    check (finalizado_en is null or finalizado_en >= asignado_en),
  constraint lead_asignaciones_cierre_consistente check (
    (
      finalizado_en is null
      and finalizado_por is null
      and motivo_cierre is null
      and analista_destino_id is null
      and supervisor_destino_id is null
      and resultado is null
      and resultado_en is null
      and motivo_descarte_cierre is null
    )
    or
    (
      finalizado_en is not null
      and motivo_cierre is not null
      and (
        (
          motivo_cierre = 'transferido'
          and analista_destino_id is not null
          and supervisor_destino_id is null
          and resultado is null
          and resultado_en is null
          and motivo_descarte_cierre is null
        )
        or
        (
          motivo_cierre = 'parqueado'
          and analista_destino_id is null
          and resultado is null
          and resultado_en is null
          and motivo_descarte_cierre is null
        )
        or
        (
          motivo_cierre = 'convertido'
          and analista_destino_id is null
          and supervisor_destino_id is null
          and resultado = 'convertido'
          and resultado_en = finalizado_en
          and motivo_descarte_cierre is null
        )
        or
        (
          motivo_cierre = 'descartado'
          and analista_destino_id is null
          and supervisor_destino_id is null
          and resultado = 'descartado'
          and resultado_en = finalizado_en
          and motivo_descarte_cierre is not null
        )
        or
        (
          motivo_cierre = 'desactivado'
          and analista_destino_id is null
          and supervisor_destino_id is null
          and resultado is null
          and resultado_en is null
          and motivo_descarte_cierre is null
        )
      )
    )
  )
);

comment on table crm.lead_asignaciones is
  'Ledger inmutable de episodios de responsabilidad analitica por lead.';
comment on column crm.lead_asignaciones.aproximado is
  'True solo para el estado vigente reconstruido al instalar 0C; nunca para episodios capturados hacia adelante.';

-- Una sola fila abierta es la garantia primaria pedida por el dominio. La
-- exclusion agrega defensa contra cualquier solape historico, no solo abiertos.
create unique index lead_asignaciones_un_abierto_por_lead_idx
  on crm.lead_asignaciones (lead_id)
  where finalizado_en is null;

alter table crm.lead_asignaciones
  add constraint lead_asignaciones_sin_solape
  exclude using gist (
    lead_id with =,
    tstzrange(asignado_en, coalesce(finalizado_en, 'infinity'::timestamptz), '[)') with &&
  );

create index lead_asignaciones_lead_fecha_idx
  on crm.lead_asignaciones (lead_id, asignado_en desc);
create index lead_asignaciones_analista_fecha_idx
  on crm.lead_asignaciones (analista_id, asignado_en desc);
create index lead_asignaciones_terminal_analista_idx
  on crm.lead_asignaciones (analista_id, finalizado_en desc)
  where motivo_cierre in ('convertido', 'descartado');
create index lead_asignaciones_asignado_por_idx
  on crm.lead_asignaciones (asignado_por)
  where asignado_por is not null;
create index lead_asignaciones_finalizado_por_idx
  on crm.lead_asignaciones (finalizado_por)
  where finalizado_por is not null;
create index lead_asignaciones_analista_destino_idx
  on crm.lead_asignaciones (analista_destino_id)
  where analista_destino_id is not null;
create index lead_asignaciones_supervisor_origen_idx
  on crm.lead_asignaciones (supervisor_origen_id)
  where supervisor_origen_id is not null;
create index lead_asignaciones_supervisor_destino_idx
  on crm.lead_asignaciones (supervisor_destino_id)
  where supervisor_destino_id is not null;

-- Indice de soporte para el SLA derivado por ventana de episodio.
create index if not exists actividades_contacto_episodio_idx
  on crm.actividades (lead_id, creado_por, creado_en)
  where tipo in (
    'llamada_realizada',
    'llamada_no_contestada',
    'whatsapp_enviado',
    'whatsapp_recibido',
    'reunion_realizada'
  );

alter table crm.lead_asignaciones enable row level security;
revoke all privileges on table crm.lead_asignaciones
  from public, anon, authenticated, service_role;

-- Backfill seguro bajo el lock de corte. En produccion se verificaron cero
-- leads; si aparecio alguno, solo se reconstruye su episodio VIGENTE y se marca
-- aproximado. El historial anterior no se inventa.
insert into crm.lead_asignaciones (
  lead_id,
  ciclo_n,
  episodio_n,
  analista_id,
  motivo_apertura,
  asignado_en,
  asignado_por,
  monto_estimado,
  moneda,
  origen,
  categoria_interes,
  aproximado
)
select
  l.id,
  l.ciclo_actual,
  1,
  l.vendedor_id,
  'backfill_estado_actual',
  coalesce(m.ultimo_movimiento, l.creado_en),
  null,
  l.monto_estimado,
  l.moneda,
  l.origen,
  l.categoria_interes,
  true
from crm.leads l
left join lateral (
  select max(a.creado_en) as ultimo_movimiento
  from crm.actividades a
  where a.lead_id = l.id
    and a.tipo = 'reasignacion'
    and a.metadata ->> 'vendedor_nuevo' = l.vendedor_id::text
) m on true
where l.activo = true
  and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
  and l.vendedor_id is not null;

-- Clasificador total y unico del par de tenencia. Timeline y ledger llaman a
-- esta misma funcion; la precedencia de cambios compuestos vive en un solo lugar.
create or replace function private.clasificar_movimiento_tenencia(
  p_vendedor_anterior uuid,
  p_vendedor_nuevo uuid,
  p_supervisor_anterior uuid,
  p_supervisor_nuevo uuid
)
returns text
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $function$
  select case
    when p_vendedor_nuevo is not null and p_supervisor_nuevo is not null
      then 'estado_invalido'
    when p_vendedor_anterior is distinct from p_vendedor_nuevo then
      case
        when p_vendedor_anterior is null and p_vendedor_nuevo is not null
          then 'asignado'
        when p_vendedor_anterior is not null and p_vendedor_nuevo is not null
          then 'transferido'
        when p_supervisor_nuevo is not null
          then 'parqueado'
        else 'sin_asignar'
      end
    when p_supervisor_anterior is distinct from p_supervisor_nuevo then
      case
        when p_supervisor_anterior is null and p_supervisor_nuevo is not null
          then 'entra_bandeja'
        when p_supervisor_anterior is not null and p_supervisor_nuevo is null
          then 'sale_bandeja'
        else 'cambio_bandeja'
      end
    else 'sin_cambio'
  end;
$function$;

-- Defensa de transiciones. No depende de RLS ni del bypass de conversion.
create or replace function private.trg_leads_guard_tenencia()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_rol text;
  v_activo boolean;
  v_rol_actor text;
  v_entra_terminal boolean;
begin
  if new.vendedor_id is not null and new.asignado_supervisor_id is not null then
    raise exception 'Un lead no puede tener analista y bandeja al mismo tiempo';
  end if;

  -- Solo un miembro comercial ACTIVO puede recibir responsabilidad nueva.
  if new.vendedor_id is not null
     and (
       tg_op = 'INSERT'
       or new.vendedor_id is distinct from old.vendedor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     ) then
    select e.rol_crm, e.activo
      into v_rol, v_activo
    from crm.equipo e
    where e.perfil_id = new.vendedor_id;

    if not found or v_activo is distinct from true or v_rol not in ('vendedor', 'supervisor') then
      raise exception 'El analista destino no existe, no esta activo o no puede recibir leads';
    end if;
  end if;

  -- Una bandeja pertenece exclusivamente a un supervisor activo.
  if new.asignado_supervisor_id is not null
     and (
       tg_op = 'INSERT'
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     ) then
    select e.rol_crm, e.activo
      into v_rol, v_activo
    from crm.equipo e
    where e.perfil_id = new.asignado_supervisor_id;

    if not found or v_activo is distinct from true or v_rol <> 'supervisor' then
      raise exception 'La bandeja destino no pertenece a un supervisor activo';
    end if;
  end if;

  -- Un usuario CRM no gerencial no puede liberar un lead a la cola global.
  if new.vendedor_id is null
     and new.asignado_supervisor_id is null
     and (
       tg_op = 'INSERT'
       or old.vendedor_id is not null
       or old.asignado_supervisor_id is not null
     )
     and auth.uid() is not null then
    v_rol_actor := private.rol_crm(auth.uid());
    if v_rol_actor is distinct from 'gerencia' then
      raise exception 'Solo Gerencia puede dejar un lead en la cola global';
    end if;
  end if;

  if tg_op = 'INSERT' then
    -- El cliente no decide el inicio del SLA ni puede crear un episodio futuro.
    -- El timestamp de alta y su primera actualizacion nacen del reloj servidor.
    new.creado_en := statement_timestamp();
    new.actualizado_en := new.creado_en;
    new.ciclo_actual := 1;
    return new;
  end if;

  -- El cliente API nunca gobierna el contador; solo una reapertura valida lo
  -- incrementa, incluso cuando el lead permanece parqueado.
  new.ciclo_actual := old.ciclo_actual;

  if old.etapa = 'convertido' and new.etapa is distinct from old.etapa then
    raise exception 'Un lead convertido no se puede reabrir';
  end if;

  if old.etapa = 'descartado' and new.etapa is distinct from old.etapa then
    if new.etapa <> 'nuevo' then
      raise exception 'Un lead descartado solo se puede reabrir en etapa nuevo';
    end if;
    new.ciclo_actual := old.ciclo_actual + 1;
  end if;

  v_entra_terminal := old.etapa not in ('convertido', 'descartado')
    and new.etapa in ('convertido', 'descartado');

  if v_entra_terminal
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Asigna al responsable antes de cerrar el lead';
  end if;

  if v_entra_terminal and old.activo = false then
    raise exception 'Reactiva el lead antes de cerrarlo';
  end if;

  if v_entra_terminal and old.activo = true and new.activo = false then
    raise exception 'Cierra o desactiva el lead en operaciones separadas';
  end if;

  -- La conversion representa un resultado ganado y exige analista vigente.
  -- El descarte sin analista se permite para depurar una cola, sin atribucion.
  if old.etapa <> 'convertido' and new.etapa = 'convertido'
     and old.vendedor_id is null then
    raise exception 'Asigna un analista antes de convertir el lead';
  end if;

  if old.activo = true and new.activo = false
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Reasigna o desactiva el lead en operaciones separadas';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_leads_00_guard_tenencia on crm.leads;
create trigger trg_leads_00_guard_tenencia
before insert or update on crm.leads
for each row
execute function private.trg_leads_guard_tenencia();

-- Evolucion consciente de 0A: ahora el timeline observa el par completo. Sigue
-- siendo UPDATE-only; el alta ya aparece como evento humano y el ledger abre el
-- episodio de nacimiento sin duplicar una reasignacion artificial.
create or replace function private.trg_leads_reasignacion()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_movimiento text;
  v_anterior text;
  v_nuevo text;
begin
  v_movimiento := private.clasificar_movimiento_tenencia(
    old.vendedor_id,
    new.vendedor_id,
    old.asignado_supervisor_id,
    new.asignado_supervisor_id
  );

  if v_movimiento = 'sin_cambio' then
    return new;
  end if;

  if old.vendedor_id is not null then
    select p.nombre_completo into v_anterior
    from public.perfiles p
    where p.id = old.vendedor_id;
  elsif old.asignado_supervisor_id is not null then
    select 'Bandeja de ' || p.nombre_completo into v_anterior
    from public.perfiles p
    where p.id = old.asignado_supervisor_id;
  else
    v_anterior := 'Sin asignar';
  end if;

  if new.vendedor_id is not null then
    select p.nombre_completo into v_nuevo
    from public.perfiles p
    where p.id = new.vendedor_id;
  elsif new.asignado_supervisor_id is not null then
    select 'Bandeja de ' || p.nombre_completo into v_nuevo
    from public.perfiles p
    where p.id = new.asignado_supervisor_id;
  else
    v_nuevo := 'Sin asignar';
  end if;

  insert into crm.actividades (
    lead_id,
    tipo,
    detalle,
    metadata,
    creado_por,
    creado_en
  )
  values (
    new.id,
    'reasignacion',
    coalesce(v_anterior, 'Responsable desconocido') || ' → '
      || coalesce(v_nuevo, 'Responsable desconocido'),
    jsonb_build_object(
      'movimiento', v_movimiento,
      'vendedor_anterior', old.vendedor_id,
      'vendedor_nuevo', new.vendedor_id,
      'supervisor_anterior', old.asignado_supervisor_id,
      'supervisor_nuevo', new.asignado_supervisor_id
    ),
    coalesce(auth.uid(), new.creado_por),
    statement_timestamp()
  );

  return new;
end;
$function$;

drop trigger if exists trg_leads_reasignacion on crm.leads;
create trigger trg_leads_reasignacion
before update on crm.leads
for each row
execute function private.trg_leads_reasignacion();

-- El propio ledger solo admite INSERT/CLOSE desde el trigger anidado. Un
-- episodio cerrado no vuelve a mutar ni siquiera si un writer privilegiado se
-- equivoca. DELETE se veta tambien cuando alguien intenta borrar el lead padre:
-- una vez que existe trazabilidad, el ciclo de vida correcto es soft-delete.
create or replace function private.trg_lead_asignaciones_inmutables()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Los episodios de asignacion no se eliminan';
  end if;

  if coalesce(current_setting('crm.ledger_writer', true), 'off') <> 'on'
     or pg_trigger_depth() < 2 then
    raise exception 'El ledger solo se escribe desde el movimiento del lead';
  end if;

  if tg_op = 'INSERT' then
    return new;
  end if;

  if old.finalizado_en is not null then
    raise exception 'Un episodio cerrado es inmutable';
  end if;

  if old.id is distinct from new.id
     or old.lead_id is distinct from new.lead_id
     or old.ciclo_n is distinct from new.ciclo_n
     or old.episodio_n is distinct from new.episodio_n
     or old.analista_id is distinct from new.analista_id
     or old.motivo_apertura is distinct from new.motivo_apertura
     or old.asignado_en is distinct from new.asignado_en
     or old.asignado_por is distinct from new.asignado_por
     or old.supervisor_origen_id is distinct from new.supervisor_origen_id
     or old.monto_estimado is distinct from new.monto_estimado
     or old.moneda is distinct from new.moneda
     or old.origen is distinct from new.origen
     or old.categoria_interes is distinct from new.categoria_interes
     or old.aproximado is distinct from new.aproximado
     or old.creado_en is distinct from new.creado_en then
    raise exception 'La fotografia de un episodio es inmutable';
  end if;

  if new.finalizado_en is null or new.motivo_cierre is null then
    raise exception 'La unica actualizacion valida del ledger es su cierre completo';
  end if;

  return new;
end;
$function$;

create trigger trg_lead_asignaciones_00_inmutables
before insert or update or delete on crm.lead_asignaciones
for each row
execute function private.trg_lead_asignaciones_inmutables();

create or replace function private.trg_leads_asignaciones()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_evento_en timestamptz;
  v_actor uuid;
  v_movimiento text := 'sin_cambio';
  v_abierto crm.lead_asignaciones%rowtype;
  v_hay_abierto boolean := false;
  v_old_debe_tener boolean := false;
  v_new_debe_tener boolean;
  v_entra_terminal boolean := false;
  v_reabierto boolean := false;
  v_reactivado boolean := false;
  v_motivo_apertura text;
  v_motivo_cierre text;
  v_episodio_n integer;
  v_abiertos integer;
  v_analista_abierto uuid;
begin
  v_new_debe_tener := new.activo = true
    and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and new.vendedor_id is not null;

  if tg_op = 'INSERT' then
    v_evento_en := new.creado_en;
    v_actor := coalesce(auth.uid(), new.creado_por);

    if v_new_debe_tener then
      perform set_config('crm.ledger_writer', 'on', true);
      insert into crm.lead_asignaciones (
        lead_id,
        ciclo_n,
        episodio_n,
        analista_id,
        motivo_apertura,
        asignado_en,
        asignado_por,
        monto_estimado,
        moneda,
        origen,
        categoria_interes
      )
      values (
        new.id,
        new.ciclo_actual,
        1,
        new.vendedor_id,
        'ingreso',
        v_evento_en,
        v_actor,
        new.monto_estimado,
        new.moneda,
        new.origen,
        new.categoria_interes
      );
      perform set_config('crm.ledger_writer', 'off', true);
    end if;
  else
    v_evento_en := statement_timestamp();
    v_actor := auth.uid();
    v_movimiento := private.clasificar_movimiento_tenencia(
      old.vendedor_id,
      new.vendedor_id,
      old.asignado_supervisor_id,
      new.asignado_supervisor_id
    );
    v_old_debe_tener := old.activo = true
      and old.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
      and old.vendedor_id is not null;
    v_entra_terminal := old.etapa not in ('convertido', 'descartado')
      and new.etapa in ('convertido', 'descartado');
    v_reabierto := old.etapa = 'descartado' and new.etapa = 'nuevo';
    v_reactivado := old.activo = false and new.activo = true;

    select la.*
      into v_abierto
    from crm.lead_asignaciones la
    where la.lead_id = new.id
      and la.finalizado_en is null
    for update;
    v_hay_abierto := found;

    if v_old_debe_tener and not v_hay_abierto then
      raise exception 'Invariante rota: falta el episodio abierto del lead %', new.id;
    end if;
    if v_old_debe_tener and v_abierto.analista_id is distinct from old.vendedor_id then
      raise exception 'Invariante rota: el episodio abierto no coincide con el analista del lead %', new.id;
    end if;
    if not v_old_debe_tener and v_hay_abierto then
      raise exception 'Invariante rota: existe un episodio abierto fuera de tenencia operativa para %', new.id;
    end if;

    if v_hay_abierto
       and (
         new.vendedor_id is distinct from old.vendedor_id
         or not v_new_debe_tener
       ) then
      v_motivo_cierre := case
        when v_entra_terminal then new.etapa
        when old.activo = true and new.activo = false then 'desactivado'
        when v_movimiento = 'transferido' then 'transferido'
        when v_movimiento in ('parqueado', 'sin_asignar') then 'parqueado'
        else null
      end;

      if v_motivo_cierre is null then
        raise exception 'No se pudo clasificar el cierre del episodio del lead %', new.id;
      end if;

      perform set_config('crm.ledger_writer', 'on', true);
      update crm.lead_asignaciones
      set finalizado_en = v_evento_en,
          finalizado_por = v_actor,
          motivo_cierre = v_motivo_cierre,
          analista_destino_id = case
            when v_motivo_cierre = 'transferido' then new.vendedor_id
            else null
          end,
          supervisor_destino_id = case
            when v_motivo_cierre = 'parqueado' then new.asignado_supervisor_id
            else null
          end,
          resultado = case
            when v_motivo_cierre in ('convertido', 'descartado') then v_motivo_cierre
            else null
          end,
          resultado_en = case
            when v_motivo_cierre in ('convertido', 'descartado') then v_evento_en
            else null
          end,
          motivo_descarte_cierre = case
            when v_motivo_cierre = 'descartado' then new.motivo_descarte
            else null
          end
      where id = v_abierto.id;
      perform set_config('crm.ledger_writer', 'off', true);
      v_hay_abierto := false;
    end if;

    if v_new_debe_tener
       and (
         not v_old_debe_tener
         or new.vendedor_id is distinct from old.vendedor_id
       ) then
      v_motivo_apertura := case
        when v_reabierto then 'reabierto'
        when v_reactivado then 'reactivado'
        when v_movimiento = 'transferido' then 'reasignado'
        else 'asignado'
      end;

      select coalesce(max(la.episodio_n), 0) + 1
        into v_episodio_n
      from crm.lead_asignaciones la
      where la.lead_id = new.id
        and la.ciclo_n = new.ciclo_actual;

      perform set_config('crm.ledger_writer', 'on', true);
      insert into crm.lead_asignaciones (
        lead_id,
        ciclo_n,
        episodio_n,
        analista_id,
        motivo_apertura,
        asignado_en,
        asignado_por,
        supervisor_origen_id,
        monto_estimado,
        moneda,
        origen,
        categoria_interes
      )
      values (
        new.id,
        new.ciclo_actual,
        v_episodio_n,
        new.vendedor_id,
        v_motivo_apertura,
        v_evento_en,
        v_actor,
        old.asignado_supervisor_id,
        new.monto_estimado,
        new.moneda,
        new.origen,
        new.categoria_interes
      );
      perform set_config('crm.ledger_writer', 'off', true);
    end if;
  end if;

  select count(*), (array_agg(la.analista_id))[1]
    into v_abiertos, v_analista_abierto
  from crm.lead_asignaciones la
  where la.lead_id = new.id
    and la.finalizado_en is null;

  if v_new_debe_tener
     and (v_abiertos <> 1 or v_analista_abierto is distinct from new.vendedor_id) then
    raise exception 'Invariante rota: el lead % debe terminar con un episodio abierto', new.id;
  end if;
  if not v_new_debe_tener and v_abiertos <> 0 then
    raise exception 'Invariante rota: el lead % no debe terminar con episodio abierto', new.id;
  end if;

  return new;
end;
$function$;

create trigger trg_leads_asignaciones
after insert or update on crm.leads
for each row
execute function private.trg_leads_asignaciones();

-- El audit append-only conserva cada apertura y cierre del ledger.
create trigger trg_audit_lead_asignaciones
after insert or update on crm.lead_asignaciones
for each row
execute function private.log_audit_crm();

revoke all on function private.clasificar_movimiento_tenencia(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.trg_leads_guard_tenencia()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_leads_reasignacion()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_lead_asignaciones_inmutables()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_leads_asignaciones()
  from public, anon, authenticated, service_role;

commit;
