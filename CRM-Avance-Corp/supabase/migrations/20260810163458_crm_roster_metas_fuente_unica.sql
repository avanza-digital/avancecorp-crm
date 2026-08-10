-- Metas mensuales: una sola definición de «a quién se le fija meta».
--
-- El bug que arregla
-- ------------------
-- Publicar metas era IMPOSIBLE en producción. El editor y el publicador tenían
-- DOS definiciones distintas del roster del mes:
--
--   · crm.configuracion_metas_fn mostraba los vendedores activos CON supervisor
--     activo (join interno contra crm.equipo s);
--   · crm.publicar_metas_vendedores exigía una meta por CADA vendedor activo,
--     tuviera supervisor o no, y además abortaba con 23514 si alguno no lo tenía.
--
-- Con una sola analista sin supervisor (IVETT TEEVIN, 2026-08-10) el editor
-- ofrecía 16 metas y el servidor exigía 17: gerencia no podía publicar NINGUNA
-- meta del mes, y el mensaje de error no decía a quién le faltaba el supervisor.
-- Por eso `crm.meta_periodos` llevaba 0 filas desde que existe la pantalla.
--
-- La decisión
-- -----------
-- Un vendedor sin supervisor NO CABE en crm.metas_vendedor: supervisor_id es
-- NOT NULL con FK a crm.equipo. Exigir su meta era pedir algo que el esquema no
-- puede almacenar. Así que el roster de metas es «vendedor activo con supervisor
-- activo», queda definido UNA vez en private.roster_metas_vendedores(), y las dos
-- funciones lo comparten. Quien se quede fuera ya no bloquea el mes: sale
-- señalado en el payload del editor (`sin_supervisor`) para que gerencia lo
-- corrija en Configuración → Usuarios.
--
-- Silenciar la exclusión sería el bug de siempre: una pantalla que no dice lo
-- que se está dejando fuera.

begin;

set local lock_timeout = '10s';

-- ============================================================================
-- 1. Fuente única del roster de metas
-- ============================================================================

-- private.rol_crm ya exige equipo.activo Y perfiles.activo en los dos extremos,
-- así que aquí «activo» no se vuelve a comprobar: se hereda de esa definición.
create or replace function private.roster_metas_vendedores()
returns table (vendedor_id uuid, supervisor_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  select e.perfil_id, e.supervisor_id
  from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'vendedor'
    and private.rol_crm(e.supervisor_id) = 'supervisor';
$function$;

comment on function private.roster_metas_vendedores() is
  'Analistas a los que se les puede fijar meta: vendedor activo con supervisor activo. Fuente unica del editor y del publicador.';

revoke all on function private.roster_metas_vendedores()
  from public, anon, authenticated, service_role;

-- Vendedores activos que quedan FUERA del roster por no tener supervisor
-- valido. Existe para que la exclusion sea visible, no para filtrar nada.
--
-- `motivo` NO es decoracion: «no tiene supervisor», «lo tiene pero esta de baja»
-- y «lo tiene pero no es supervisor» son tres arreglos distintos. Una sola
-- etiqueta para los tres manda a Gerencia a asignarle supervisor a alguien que
-- en pantalla ya tiene uno — el mismo error de usar un predicado como proxy de
-- dos preguntas que costo el incidente P04.
create or replace function private.vendedores_sin_supervisor()
returns table (vendedor_id uuid, nombre text, motivo text)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    e.perfil_id,
    -- nombre_completo es NULLABLE en public.perfiles. Sin este coalesce, un
    -- solo nombre vacio rompe el contrato del front (TextoNoVacio dentro de un
    -- strictObject) y Gerencia se queda sin PANTALLA, no sin una fila.
    coalesce(nullif(pg_catalog.btrim(p.nombre_completo), ''),
             '(sin nombre · ' || pg_catalog.left(e.perfil_id::text, 8) || ')'),
    case
      when e.supervisor_id is null then 'sin_supervisor'
      when exists (
        select 1 from crm.equipo s
        where s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor'
      ) then 'supervisor_inactivo'
      else 'supervisor_no_es_supervisor'
    end
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where private.rol_crm(e.perfil_id) = 'vendedor'
    and private.rol_crm(e.supervisor_id) is distinct from 'supervisor';
$function$;

comment on function private.vendedores_sin_supervisor() is
  'Vendedores activos fuera de las metas por supervisor ausente/inactivo/con otro rol, con el motivo para que Gerencia sepa que arreglar.';

revoke all on function private.vendedores_sin_supervisor()
  from public, anon, authenticated, service_role;

-- ============================================================================
-- 2. Publicacion: se exige el roster, no «todos los vendedores»
-- ============================================================================

create or replace function crm.publicar_metas_vendedores(
  p_periodo date,
  p_expected_revision integer,
  p_metas jsonb
)
returns setof crm.meta_periodos
language plpgsql security definer set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_revision_actual integer;
  v_revision_nueva integer;
  v_anterior_id uuid;
  v_periodo_id uuid;
  v_total_roster integer;
  v_total_enviadas integer;
  v_item record;
  v_detalle record;
  v_vendedor_id uuid;
  v_supervisor_id uuid;
  v_meta_vendedor_id uuid;
  v_conversion numeric;
  v_capital numeric;
  v_contratos numeric;
  v_categoria text;
  v_moneda text;
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa puede publicar metas comerciales'
      using errcode = '42501';
  end if;
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode = '22023';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'expected_revision debe ser cero o positivo' using errcode = '22023';
  end if;
  if p_metas is null or jsonb_typeof(p_metas) <> 'object' then
    raise exception 'Las metas deben ser un objeto por vendedor' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.meta_periodos'),
    (p_periodo - date '2000-01-01')::integer
  );
  -- La publicacion fotografía un roster completo. El lock evita que una alta,
  -- baja o reasignacion concurrente lo cambie entre la validacion y el INSERT.
  lock table crm.equipo in share mode;
  -- Antes esto era `lock table public.perfiles in share mode`, y eso congelaba
  -- las escrituras del PORTAL EN PRODUCCION —altas y ediciones de perfil— cada
  -- vez que Gerencia publicaba metas del CRM. El aislamiento que hace falta es
  -- solo sobre el flag `activo` de la gente del equipo comercial (21 filas),
  -- porque es lo que puede cambiar `private.rol_crm` a mitad de transaccion;
  -- nadie puede entrar al roster sin fila en crm.equipo, que ya esta bloqueada.
  perform 1 from public.perfiles p
  where p.id in (select e.perfil_id from crm.equipo e)
  for share;

  select mp.id, mp.revision into v_anterior_id, v_revision_actual
  from crm.meta_periodos mp where mp.periodo = p_periodo
  order by mp.revision desc limit 1;
  v_revision_actual := coalesce(v_revision_actual, 0);
  if p_expected_revision <> v_revision_actual then
    raise exception 'Conflicto de revision: esperada %, vigente %',
      p_expected_revision, v_revision_actual using errcode = '40001';
  end if;
  v_revision_nueva := v_revision_actual + 1;

  -- El conjunto exigido es EXACTAMENTE el que el editor ofrece. Un vendedor sin
  -- supervisor activo no cabe en crm.metas_vendedor (supervisor_id NOT NULL):
  -- antes se exigia su meta igual y eso hacia imposible publicar el mes entero.
  select count(*)::integer into v_total_roster from private.roster_metas_vendedores();
  select count(*)::integer into v_total_enviadas from jsonb_object_keys(p_metas);

  if v_total_roster = 0 then
    raise exception 'No hay analistas con supervisor activo a los que fijarles meta'
      using errcode = '22023';
  end if;

  -- Sin claves faltantes y con los totales iguales, tampoco puede sobrar
  -- ninguna: el conjunto enviado es el roster exacto.
  if v_total_enviadas <> v_total_roster
     or exists (
       select 1 from private.roster_metas_vendedores() r
       where not (p_metas ? r.vendedor_id::text)
     ) then
    raise exception
      'Debe enviarse exactamente una meta por analista del roster (esperadas %, recibidas %); recarga la pantalla',
      v_total_roster, v_total_enviadas using errcode = '22023';
  end if;

  insert into crm.meta_periodos (
    periodo, revision, revision_anterior_id, publicada_por
  ) values (p_periodo, v_revision_nueva, v_anterior_id, v_uid)
  returning id into v_periodo_id;

  -- Los mensajes de este bucle NO nombran al vendedor. Antes interpolaban su
  -- UUID, que viaja al cliente con el 22023 y de ahi a Sentry (el scrub de
  -- observabilidad limpia correos y tokens, no UUID). Nadie los necesita: el
  -- payload lo construye el propio front, asi que un fallo de formato es un
  -- bug del cliente, no un dato que Gerencia deba leer.
  for v_item in select key, value from jsonb_each(p_metas) loop
    begin v_vendedor_id := v_item.key::uuid;
    exception when invalid_text_representation then
      raise exception 'Identificador de vendedor invalido' using errcode = '22023';
    end;

    if jsonb_typeof(v_item.value) <> 'object'
       or not (v_item.value ?& array['conversion_objetivo','detalles'])
       or (v_item.value - array['conversion_objetivo','detalles']) <> '{}'::jsonb
       or jsonb_typeof(v_item.value->'conversion_objetivo') is distinct from 'number'
       or jsonb_typeof(v_item.value->'detalles') is distinct from 'array'
       or jsonb_array_length(v_item.value->'detalles') <> 6 then
      raise exception 'Formato de meta invalido en el payload enviado' using errcode = '22023';
    end if;
    v_conversion := (v_item.value->>'conversion_objetivo')::numeric;
    if v_conversion < 0 or v_conversion > 100 then
      raise exception 'Conversion fuera de rango en el payload enviado' using errcode = '22023';
    end if;

    select r.supervisor_id into v_supervisor_id
    from private.roster_metas_vendedores() r
    where r.vendedor_id = v_vendedor_id;
    if not found then
      raise exception 'Vendedor o supervisor fuera de jerarquia activa' using errcode = '23503';
    end if;

    insert into crm.metas_vendedor (
      meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo
    ) values (v_periodo_id, v_vendedor_id, v_supervisor_id, v_conversion)
    returning id into v_meta_vendedor_id;

    for v_detalle in select value from jsonb_array_elements(v_item.value->'detalles') loop
      if jsonb_typeof(v_detalle.value) <> 'object'
         or not (v_detalle.value ?& array['categoria','moneda','capital_objetivo','contratos_objetivo'])
         or (v_detalle.value - array['categoria','moneda','capital_objetivo','contratos_objetivo']) <> '{}'::jsonb
         or jsonb_typeof(v_detalle.value->'categoria') is distinct from 'string'
         or jsonb_typeof(v_detalle.value->'moneda') is distinct from 'string'
         or jsonb_typeof(v_detalle.value->'capital_objetivo') is distinct from 'number'
         or jsonb_typeof(v_detalle.value->'contratos_objetivo') is distinct from 'number' then
        raise exception 'Detalle de meta invalido en el payload enviado' using errcode = '22023';
      end if;
      v_categoria := v_detalle.value->>'categoria';
      v_moneda := v_detalle.value->>'moneda';
      v_capital := (v_detalle.value->>'capital_objetivo')::numeric;
      v_contratos := (v_detalle.value->>'contratos_objetivo')::numeric;
      if v_categoria not in ('nuevo','renovacion','upgrade')
         or v_moneda not in ('PEN','USD')
         or v_capital < 0 or v_capital > 100000000
         or v_contratos < 0 or v_contratos > 1000 or trunc(v_contratos) <> v_contratos then
        raise exception 'Detalle de meta fuera de rango en el payload enviado' using errcode = '22023';
      end if;
      begin
        insert into crm.metas_vendedor_detalle (
          meta_vendedor_id,categoria,moneda,capital_objetivo,contratos_objetivo
        ) values (v_meta_vendedor_id,v_categoria,v_moneda,v_capital,v_contratos::integer);
      exception when unique_violation then
        raise exception 'Categoria/moneda repetida en el payload enviado' using errcode = '22023';
      end;
    end loop;
  end loop;

  return query select mp.* from crm.meta_periodos mp where mp.id = v_periodo_id;
end;
$function$;

comment on function crm.publicar_metas_vendedores(date,integer,jsonb) is
  'Publica revision mensual del roster (vendedor activo con supervisor activo); expected_revision evita ultimo-escritor-gana.';

revoke all on function crm.publicar_metas_vendedores(date,integer,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.publicar_metas_vendedores(date,integer,jsonb) to authenticated;

-- ============================================================================
-- 3. Editor: mismo roster + los que quedan fuera
-- ============================================================================

-- Lectura atomica del editor: siempre devuelve el roster activo completo. Si el
-- mes aun no tiene publicacion, revision=0 y las seis dimensiones nacen en cero.
create or replace function crm.configuracion_metas_fn(p_periodo date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_publicada_por uuid;
  v_publicada_por_nombre text;
  v_puede_editar boolean;
  v_ve_todo boolean;
  v_payload jsonb;
begin
  if v_uid is null
     or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_periodo is null or p_periodo <> date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode = '22023';
  end if;

  v_puede_editar := coalesce(private.rol_crm(v_uid) = 'gerencia', false);
  v_ve_todo := v_puede_editar or private.es_lector_global();

  select mp.id,mp.revision,mp.publicada_en,mp.publicada_por,p.nombre_completo
    into v_periodo_id,v_revision,v_publicada_en,v_publicada_por,v_publicada_por_nombre
  from crm.meta_periodos mp
  left join public.perfiles p on p.id=mp.publicada_por
  where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision := coalesce(v_revision,0);

  with dimensiones as (
    select * from (values
      ('nuevo'::text,'PEN'::text),('nuevo','USD'),
      ('renovacion','PEN'),('renovacion','USD'),
      ('upgrade','PEN'),('upgrade','USD')
    ) d(categoria,moneda)
  ), roster as (
    -- Misma fuente que usa la publicacion: lo que se ve aqui es exactamente lo
    -- que el servidor va a aceptar.
    -- Mismo coalesce que en los excluidos: nombre_completo es nullable y el
    -- contrato del front exige texto no vacio en un strictObject, asi que un
    -- nombre en blanco tumbaria la pantalla entera en vez de una fila.
    select r.vendedor_id,
           coalesce(nullif(pg_catalog.btrim(p.nombre_completo), ''),
                    '(sin nombre · ' || pg_catalog.left(r.vendedor_id::text, 8) || ')')
             as nombre_completo,
           r.supervisor_id,
           coalesce(nullif(pg_catalog.btrim(ps.nombre_completo), ''),
                    '(sin nombre · ' || pg_catalog.left(r.supervisor_id::text, 8) || ')')
             as supervisor_nombre
    from private.roster_metas_vendedores() r
    join public.perfiles p on p.id = r.vendedor_id
    join public.perfiles ps on ps.id = r.supervisor_id
    where private.es_lector_global()
       or r.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
  )
  select jsonb_build_object(
    'version',1,
    'periodo',p_periodo,
    'revision',v_revision,
    'publicada_en',v_publicada_en,
    'publicada_por',v_publicada_por,
    'publicada_por_nombre',v_publicada_por_nombre,
    'puede_editar',v_puede_editar,
    -- Solo para quien gobierna el roster entero: a un supervisor no le
    -- corresponde enumerar analistas fuera de su subarbol.
    'sin_supervisor', case when v_ve_todo then coalesce((
      select jsonb_agg(jsonb_build_object(
               'vendedor_id',s.vendedor_id,'nombre',s.nombre,'motivo',s.motivo)
             order by s.nombre)
      from private.vendedores_sin_supervisor() s
    ),'[]'::jsonb) else '[]'::jsonb end,
    'vendedores',coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id',r.vendedor_id,
        'nombre',r.nombre_completo,
        'supervisor_id',r.supervisor_id,
        'supervisor_nombre',r.supervisor_nombre,
        'conversion_objetivo',coalesce(mv.conversion_objetivo,0),
        'detalles',(
          select jsonb_agg(jsonb_build_object(
            'categoria',d.categoria,
            'moneda',d.moneda,
            'capital_objetivo',coalesce(md.capital_objetivo,0),
            'contratos_objetivo',coalesce(md.contratos_objetivo,0)
          ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
          from dimensiones d
          left join crm.metas_vendedor_detalle md
            on md.meta_vendedor_id=mv.id
           and md.categoria=d.categoria and md.moneda=d.moneda
        )
      ) order by r.supervisor_nombre,r.nombre_completo)
      from roster r
      left join crm.metas_vendedor mv
        on mv.meta_periodo_id=v_periodo_id and mv.vendedor_id=r.vendedor_id
    ),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$;

comment on function crm.configuracion_metas_fn(date) is
  'Editor de metas del periodo: roster con supervisor activo + los vendedores excluidos por no tenerlo.';

revoke all on function crm.configuracion_metas_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.configuracion_metas_fn(date) to authenticated;

commit;
