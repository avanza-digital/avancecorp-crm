-- ============================================================================
-- Base para gestión: descartes históricos del equipo
--
-- Los descartes de los asesores viven de forma inmutable en
-- crm.lead_asignaciones. Esta migración no crea una copia paralela: expone esa
-- evidencia por mes al supervisor dueño del equipo y permite reabrir un bloque
-- de casos con una única operación atómica.
--
-- Principios:
--   * el mes es el instante real del descarte (resultado_en, hora Lima);
--   * cada episodio permanece visible aunque el lead se reactive después;
--   * solo se rescata el episodio que coincide con el descarte vigente;
--   * una reactivación abre un ciclo nuevo y deja el descarte previo intacto;
--   * la interfaz nunca recibe teléfono, correo, DNI ni notas libres.
-- ============================================================================

begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';

-- La pantalla consulta por equipo + mes y ordena el bloque por su fecha real
-- de descarte. El índice no toca las conversiones ni los episodios abiertos.
create index if not exists lead_asignaciones_rescate_descartes_idx
  on crm.lead_asignaciones (analista_id, resultado_en desc)
  where resultado = 'descartado';

-- Gerencia no filtra por analista. Este segundo acceso evita recorrer todo el
-- ledger cuando abre un mes global y sirve también al orden cronológico.
create index if not exists lead_asignaciones_rescate_descartes_fecha_idx
  on crm.lead_asignaciones (resultado_en desc, id)
  where resultado = 'descartado';

-- ── Lecturas: franja mensual e historial del mes ───────────────────────────

create or replace function crm.rescate_descartes_meses()
returns table (
  mes date,
  total bigint,
  pendientes bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
begin
  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede consultar Base para gestión'
      using errcode = '42501';
  end if;

  return query
  select
    pg_catalog.date_trunc('month', la.resultado_en at time zone 'America/Lima')::date as mes,
    pg_catalog.count(*) as total,
    pg_catalog.count(*) filter (
      where l.activo = true
        and l.etapa = 'descartado'
        and l.descartado_en is not distinct from la.resultado_en
        and la.motivo_descarte_cierre <> 'datos_invalidos'
        and l.no_contactar is not true
    ) as pendientes
  from crm.lead_asignaciones la
  join crm.leads l on l.id = la.lead_id
  where la.resultado = 'descartado'
    and la.resultado_en is not null
    and (
      v_rol = 'gerencia'
      or la.analista_id in (
        select private.vendedor_ids_visibles(v_actor)
      )
    )
  group by 1
  order by 1 desc;
end;
$$;

comment on function crm.rescate_descartes_meses() is
  'Franja mensual de Base para gestión. Lee episodios descartados del ledger por el equipo actual del supervisor; pendientes solo cuenta el descarte vigente y recuperable.';

revoke all on function crm.rescate_descartes_meses() from public, anon;
grant execute on function crm.rescate_descartes_meses() to authenticated;

create or replace function crm.rescate_descartes_mes(p_mes date)
returns table (
  episodio_id uuid,
  lead_id uuid,
  nombre_completo text,
  distrito text,
  origen text,
  categoria_interes text,
  monto_estimado numeric,
  moneda text,
  motivo_descarte text,
  descartado_en timestamptz,
  asesor_id uuid,
  asesor_nombre text,
  puede_rescatar boolean,
  estado text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_mes date := pg_catalog.date_trunc('month', p_mes)::date;
begin
  if p_mes is null then
    raise exception 'El mes es obligatorio' using errcode = '22023';
  end if;

  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede consultar Base para gestión'
      using errcode = '42501';
  end if;

  return query
  select
    la.id as episodio_id,
    l.id as lead_id,
    l.nombre_completo,
    l.distrito,
    la.origen,
    la.categoria_interes,
    la.monto_estimado,
    la.moneda,
    la.motivo_descarte_cierre,
    la.resultado_en,
    la.analista_id,
    p_asesor.nombre_completo,
    (
      l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and l.no_contactar is not true
    ) as puede_rescatar,
    case
      when l.activo = true
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
        then 'pendiente'
      when exists (
        select 1
        from crm.lead_asignaciones la_posterior
        where la_posterior.lead_id = la.lead_id
          and la_posterior.asignado_en > la.resultado_en
      ) then 'rescatado'
      else 'historial'
    end as estado
  from crm.lead_asignaciones la
  join crm.leads l on l.id = la.lead_id
  join public.perfiles p_asesor on p_asesor.id = la.analista_id
  where la.resultado = 'descartado'
    and la.resultado_en is not null
    and la.resultado_en >= (v_mes::timestamp at time zone 'America/Lima')
    and la.resultado_en < ((v_mes + interval '1 month')::timestamp at time zone 'America/Lima')
    and (
      v_rol = 'gerencia'
      or la.analista_id in (
        select private.vendedor_ids_visibles(v_actor)
      )
    )
  order by la.resultado_en desc, la.id desc;
end;
$$;

comment on function crm.rescate_descartes_mes(date) is
  'Historial mensual sin PII de contacto para Base para gestión. Cada fila es un episodio inmutable del ledger, no el estado actual mutable del lead.';

revoke all on function crm.rescate_descartes_mes(date) from public, anon;
grant execute on function crm.rescate_descartes_mes(date) to authenticated;

-- ── Escritura: rescate y redistribución atómica de un bloque ───────────────

create or replace function crm.rescatar_descartes(
  p_episodios uuid[],
  p_analistas_destino uuid[],
  p_evitar_asesor_origen boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_destinos_validos uuid[];
  v_total_episodios integer;
  v_total_destinos integer;
  v_candidatos integer := 0;
  v_orden integer := 0;
  v_intento integer;
  v_salto integer;
  v_evitar_origen boolean := coalesce(p_evitar_asesor_origen, true);
  v_destino uuid;
  v_fila record;
begin
  if p_episodios is null
     or pg_catalog.array_length(p_episodios, 1) is null
     or pg_catalog.array_length(p_episodios, 1) = 0
     or pg_catalog.array_length(p_episodios, 1) > 100
     or pg_catalog.array_position(p_episodios, null) is not null then
    raise exception 'Selecciona entre 1 y 100 descartes válidos'
      using errcode = '22023';
  end if;

  if (select pg_catalog.count(*) from (
    select distinct id from pg_catalog.unnest(p_episodios) as u(id)
  ) episodios_unicos) <> pg_catalog.array_length(p_episodios, 1) then
    raise exception 'Un descarte no se puede enviar dos veces en el mismo reparto'
      using errcode = '22023';
  end if;

  if p_analistas_destino is null
     or pg_catalog.array_length(p_analistas_destino, 1) is null
     or pg_catalog.array_length(p_analistas_destino, 1) = 0
     or pg_catalog.array_length(p_analistas_destino, 1) > 30
     or pg_catalog.array_position(p_analistas_destino, null) is not null then
    raise exception 'Selecciona al menos un asesor destino'
      using errcode = '22023';
  end if;

  if (select pg_catalog.count(*) from (
    select distinct id from pg_catalog.unnest(p_analistas_destino) as u(id)
  ) destinos_unicos) <> pg_catalog.array_length(p_analistas_destino, 1) then
    raise exception 'No repitas un asesor destino'
      using errcode = '22023';
  end if;

  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede rescatar descartes'
      using errcode = '42501';
  end if;

  select pg_catalog.array_agg(destino.id order by destino.orden)
    into v_destinos_validos
  from (
    select u.id, u.orden
    from pg_catalog.unnest(p_analistas_destino) with ordinality as u(id, orden)
    join crm.equipo e on e.perfil_id = u.id
    join public.perfiles p on p.id = e.perfil_id
    where e.activo = true
      and p.activo = true
      and e.rol_crm = 'vendedor'
      and (
        v_rol = 'gerencia'
        or e.perfil_id in (
          select private.vendedor_ids_visibles(v_actor)
        )
      )
  ) destino;

  v_total_destinos := coalesce(pg_catalog.array_length(v_destinos_validos, 1), 0);
  if v_total_destinos <> pg_catalog.array_length(p_analistas_destino, 1) then
    raise exception 'Uno de los asesores destino no está activo o no pertenece a tu equipo'
      using errcode = '22023';
  end if;

  -- Se bloquean los leads antes de modificar alguno. Si una carrera ya los
  -- reabrió, toda la operación falla y no deja un reparto parcial.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id,
      l.no_contactar
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
    where la.id = any(p_episodios)
      and la.resultado = 'descartado'
      and la.resultado_en is not null
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and (
        v_rol = 'gerencia'
        or la.analista_id in (
          select private.vendedor_ids_visibles(v_actor)
        )
      )
    order by la.resultado_en, la.id
    for update of l
  loop
    v_candidatos := v_candidatos + 1;
    if v_fila.no_contactar then
      raise exception 'Uno de los leads tiene la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
  end loop;

  v_total_episodios := pg_catalog.array_length(p_episodios, 1);
  if v_candidatos <> v_total_episodios then
    raise exception 'Uno de los descartes ya no está disponible para rescate'
      using errcode = 'P0002';
  end if;

  -- Una segunda pasada usa los mismos locks. La vuelta redonda conserva el
  -- orden seleccionado y, si se pidió, salta al asesor que lo descartó.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id
    from pg_catalog.unnest(p_episodios) with ordinality as elegido(episodio_id, orden)
    join crm.lead_asignaciones la on la.id = elegido.episodio_id
    join crm.leads l on l.id = la.lead_id
    where la.resultado = 'descartado'
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
    order by elegido.orden
  loop
    v_destino := null;
    v_salto := null;
    for v_intento in 0..(v_total_destinos - 1) loop
      v_destino := v_destinos_validos[((v_orden + v_intento) % v_total_destinos) + 1];
      if not v_evitar_origen or v_destino is distinct from v_fila.asesor_origen_id then
        -- El contador del FOR es local al loop; se copia antes de salir para
        -- poder continuar la ronda desde el destino que sí se utilizó.
        v_salto := v_intento;
        exit;
      end if;
    end loop;

    if v_destino is null
       or v_salto is null then
      raise exception 'No hay otro asesor destino para uno de los descartes seleccionados'
        using errcode = '22023';
    end if;

    update crm.leads
       set etapa = 'nuevo',
           motivo_descarte = null,
           vendedor_id = v_destino,
           asignado_supervisor_id = null
     where id = v_fila.lead_id;

    -- Avanza desde el destino realmente usado. Si se saltó al asesor origen,
    -- el siguiente lead no vuelve a caer en el mismo destino por accidente.
    v_orden := v_orden + v_salto + 1;
  end loop;

  return pg_catalog.jsonb_build_object(
    'rescatados', v_candidatos,
    'asesores_destino', v_total_destinos
  );
end;
$$;

comment on function crm.rescatar_descartes(uuid[],uuid[],boolean) is
  'Reabre en nuevo y distribuye en ronda un bloque de descartes vigentes del equipo. Conserva el episodio descartado y abre uno nuevo en el ledger; supervisor solo usa destinos de su equipo, gerencia puede usar cualquier asesor activo.';

revoke all on function crm.rescatar_descartes(uuid[], uuid[], boolean) from public, anon;
grant execute on function crm.rescatar_descartes(uuid[], uuid[], boolean) to authenticated;

-- ── Postflight: contrato mínimo de seguridad y catálogo ────────────────────

do $postflight$
declare
  v_funcion regprocedure;
begin
  foreach v_funcion in array array[
    'crm.rescate_descartes_meses()'::regprocedure,
    'crm.rescate_descartes_mes(date)'::regprocedure,
    'crm.rescatar_descartes(uuid[],uuid[],boolean)'::regprocedure
  ]
  loop
    if not exists (
      select 1
      from pg_catalog.pg_proc p
      where p.oid = v_funcion
        and p.prosecdef
        and exists (
          select 1
          from pg_catalog.unnest(p.proconfig) configuracion
          where configuracion like 'search_path=%'
        )
    ) then
      raise exception 'Postflight Base para gestión: función insegura %', v_funcion;
    end if;

    if pg_catalog.has_function_privilege('anon', v_funcion, 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', v_funcion, 'EXECUTE') then
      raise exception 'Postflight Base para gestión: privilegios inválidos en %', v_funcion;
    end if;
  end loop;

  if pg_catalog.to_regclass('crm.lead_asignaciones_rescate_descartes_idx') is null
     or pg_catalog.to_regclass('crm.lead_asignaciones_rescate_descartes_fecha_idx') is null then
    raise exception 'Postflight Base para gestión: faltan índices parciales';
  end if;
end;
$postflight$;

commit;
