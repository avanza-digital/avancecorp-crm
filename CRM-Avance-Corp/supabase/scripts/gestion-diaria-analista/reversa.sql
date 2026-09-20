-- Reversa de 20260920041500_crm_gestion_diaria_analista.sql (Gestión Diaria F3).
-- Retira los objetos nuevos, devuelve el núcleo del registro (F1) y su gate al
-- cuerpo de F1 (huella d1c922eb…) y el paraguas al cuerpo de F2. No hay datos
-- que deshacer: la fase solo lee. Se ejecuta tras retirar el front que llama a
-- crm.gestion_diaria_analista_fn.
begin;
set local lock_timeout = '5s';
drop function if exists private.assert_gestion_diaria_analista_mutantes();
drop function if exists private.assert_gestion_diaria_analista();
drop function if exists crm.gestion_diaria_analista_fn(date, uuid);
drop function if exists private.gestion_diaria_analista_core(uuid, date, timestamptz, timestamptz, timestamptz, timestamptz);
drop function if exists private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]);
drop function if exists private.gestion_diaria_umbrales();

-- Núcleo del registro: cuerpo EXACTO de 20260919211958 (lista blanca de F1).
create or replace function private.registro_actividad_core(
  p_ini timestamptz,
  p_fin timestamptz,
  p_analista_ids uuid[],
  p_tipos text[],
  p_etapa text,
  p_limite integer,
  p_antes_de timestamptz,
  p_antes_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with pagina as (
    select a.id, a.lead_id, a.tipo, a.detalle, a.metadata, a.creado_por, a.creado_en,
           l.nombre_completo as lead_nombre, l.etapa as lead_etapa,
           -- La etapa del lead ANTES de esta actividad: el último cambio de etapa
           -- anterior. OJO con el reloj de los escritores (refutación del 19/09):
           -- las gestiones manuales llevan `clock_timestamp()` (sello de
           -- 20260820174320) pero los `cambio_etapa` automáticos nacen con el
           -- `now()` de la transacción, es decir unos milisegundos ANTES de la
           -- llamada que los causó. Por eso el cambio se considera «ya ocurrido»
           -- solo si es anterior en más de un segundo: así la llamada que subió
           -- el lead a «contactado» se ve todavía en «nuevo», y la conversión
           -- (misma transacción que su cambio) se ve en la etapa previa.
           (select c.metadata->>'etapa_nueva'
              from crm.actividades c
             where c.lead_id = a.lead_id
               and c.tipo = 'cambio_etapa'
               and c.creado_en < a.creado_en - interval '1 second'
             order by c.creado_en desc, c.id desc
             limit 1) as etapa_en_ese_momento
    from crm.actividades a
    join crm.leads l on l.id = a.lead_id
    where a.creado_en >= p_ini
      and a.creado_en <  p_fin
      and (p_analista_ids is null or a.creado_por = any (p_analista_ids))
      and (p_tipos is null or a.tipo = any (p_tipos))
      and (p_etapa is null or l.etapa = p_etapa)
      and (
        p_antes_de is null
        or a.creado_en < p_antes_de
        or (a.creado_en = p_antes_de and a.id > p_antes_id)
      )
    order by a.creado_en desc, a.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.now(),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pg.id,
          'lead_id', pg.lead_id,
          'lead_nombre', pg.lead_nombre,
          'lead_etapa', pg.lead_etapa,
          'etapa_en_ese_momento', pg.etapa_en_ese_momento,
          'tipo', pg.tipo,
          'detalle', pg.detalle,
          -- metadata por LISTA BLANCA: solo lo que la pantalla necesita. Fuera
          -- quedan montos y referencias de conversión, uuids de reasignación y
          -- cualquier clave futura que no se haya decidido mostrar (auditor-rls, 19/09).
          'metadata', coalesce((
            select jsonb_object_agg(m.clave, m.valor)
            from jsonb_each(pg.metadata) as m(clave, valor)
            where m.clave in ('evento', 'resultado', 'submotivo', 'intento_n', 'etapa_anterior', 'etapa_nueva',
                              'automatico', 'resultado_reunion', 'modalidad', 'motivo')
          ), '{}'::jsonb),
          'creado_por', pg.creado_por,
          'autor_nombre', coalesce(private.nombre_de_autor(pg.creado_por), '—'),
          'creado_en', pg.creado_en
        )
        order by pg.creado_en desc, pg.id asc
      )
      from pagina pg
    ), '[]'::jsonb)
  );
$function$;
comment on function private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid) is
  'NÚCLEO (Gestión Diaria): página keyset (creado_en desc, id asc) de actividades de una ventana [p_ini, p_fin) bajo la RLS del actor, filtrada por autores, tipos y etapa actual del lead, con la etapa del lead en ese momento (último cambio_etapa anterior) y metadata acotada a una lista blanca de claves. Puro: sin auth ni autoridad propia; sin count(.';

-- El gate de F1: cuerpo EXACTO de 20260919211958 (renombrado por F2).
create or replace function private.assert_gestion_diaria_registro() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_firma text;
  v_id oid;
begin
  foreach v_firma in array array[
    'crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)',
    'private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and not p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 's'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato de Gestion Diaria alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL de Gestion Diaria alterada: %', v_firma;
    end if;
  end loop;

  if not exists (select 1 from pg_indexes where schemaname = 'crm' and tablename = 'actividades'
                 and indexname = 'actividades_autor_fecha_idx') then
    raise exception 'Falta el indice actividades_autor_fecha_idx';
  end if;

  -- El CUERPO del núcleo, sellado: la lista blanca de metadata, la ventana y el
  -- keyset viven ahí y un `create or replace` conservaría forma, ACL y
  -- search_path. Huella medida en el banco el 19/09/2026 (dos pasadas del ensayo).
  if md5(pg_get_functiondef('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'::regprocedure))
     is distinct from 'd1c922eb5081e30f3581b95a95d74656' then
    raise exception 'El cuerpo de private.registro_actividad_core cambio: re-sellar Gestion Diaria';
  end if;

  -- El único salto privilegiado sigue en su forma (DEFINER con gate interno).
  v_id := to_regprocedure('private.nombre_de_autor(uuid)');
  if v_id is null or not exists (
    select 1 from pg_proc p
    where p.oid = v_id and p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
      and strpos(p.prosrc, 'puede_acceder_crm') > 0
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'private.nombre_de_autor(uuid) perdio su forma o su EXECUTE';
  end if;

  -- Las dos policies co-extensivas (huella, conjunto de permisivas, roles de la
  -- policy, restrictiva del actor activo, grants de la cadena invoker): UNA sola
  -- fuente, la base del historial por lead (20260919185718). Dos gates con las
  -- mismas constantes copiadas podrían divergir; llamándola no pueden.
  perform private.assert_actividades_de_lead_base();

  return 'OK: registro de Gestion Diaria bajo la RLS (puerta y nucleo INVOKER), EXECUTE solo authenticated, indice presente, policies selladas por la base del historial por lead';
end;
$function$;
comment on function private.assert_gestion_diaria_registro() is
  'Trinquete de Gestión Diaria · Fase 1 (registro): puerta y núcleo INVOKER con search_path vacío, EXECUTE solo para authenticated, índice actividades_autor_fecha_idx presente, nombre_de_autor en su forma, y las policies actividades_select/leads_select selladas vía private.assert_actividades_de_lead_base(). La llama private.assert_gestion_diaria().';

-- El paraguas: cuerpo EXACTO de 20260920005000 (F1 + F2).
create or replace function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_registro text;
  v_resultado text;
begin
  v_registro := private.assert_gestion_diaria_registro();
  v_resultado := private.assert_gestion_diaria_resultado();
  return 'OK: Gestion Diaria [' || v_registro || '] [' || v_resultado || ']';
end;
$function$;
comment on function private.assert_gestion_diaria() is
  'Paraguas del trinquete de Gestión Diaria: llama a assert_gestion_diaria_registro() (F1) y assert_gestion_diaria_resultado() (F2). Crecerá con cada fase.';

do $reversa$
begin
  if private.assert_gestion_diaria() not like 'OK: Gestion Diaria [OK%] [OK%]' then
    raise exception 'REVERSA: el paraguas de F1+F2 no volvio a verde';
  end if;
  if md5(pg_get_functiondef('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'::regprocedure))
     is distinct from 'd1c922eb5081e30f3581b95a95d74656' then
    raise exception 'REVERSA: el nucleo del registro no volvio a su cuerpo de F1';
  end if;
  perform private.assert_sla_comandos();
end;
$reversa$;
notify pgrst, 'reload schema';
commit;
