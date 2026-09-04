CREATE OR REPLACE FUNCTION crm.rescatar_descartes(p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_destinos_validos uuid[];
  v_total_episodios integer;
  v_total_destinos integer;
  v_candidatos integer := 0;
  v_orden integer := 0;
  v_intento integer;
  v_destino uuid;
  v_fila record;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
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

  v_total_destinos := pg_catalog.coalesce(pg_catalog.array_length(v_destinos_validos, 1), 0);
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
      (l.no_contactar or (v_flag and coalesce(inv.no_contactar, false))) as no_contactar  -- veto de la PERSONA
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
    left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
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
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
    where la.id = any(p_episodios)
      and la.resultado = 'descartado'
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
    order by la.resultado_en, la.id
  loop
    v_destino := null;
    for v_intento in 0..(v_total_destinos - 1) loop
      v_destino := v_destinos_validos[((v_orden + v_intento) % v_total_destinos) + 1];
      exit when not p_evitar_asesor_origen or v_destino is distinct from v_fila.asesor_origen_id;
    end loop;

    if v_destino is null
       or (p_evitar_asesor_origen and v_destino = v_fila.asesor_origen_id) then
      raise exception 'No hay otro asesor destino para uno de los descartes seleccionados'
        using errcode = '22023';
    end if;

    update crm.leads
       set etapa = 'nuevo',
           motivo_descarte = null,
           vendedor_id = v_destino,
           asignado_supervisor_id = null
     where id = v_fila.lead_id;

    v_orden := v_orden + 1;
  end loop;

  return pg_catalog.jsonb_build_object(
    'rescatados', v_candidatos,
    'asesores_destino', v_total_destinos
  );
end;
$function$

