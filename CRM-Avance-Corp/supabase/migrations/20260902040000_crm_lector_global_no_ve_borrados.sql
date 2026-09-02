-- P-055 · El lector global deja de ver lo soft-borrado.
--
-- EL HALLAZGO (01/09, primera corrida ejecutable de test:rls contra el banco a
-- paridad): la politica `leads_select` exige `activo = true` para analistas,
-- supervisores y gerencia, pero la rama del lector global va FUERA de ese
-- candado:
--
--     ( activo = true AND (propio | bandeja | gerencia) )
--     OR es_lector_global()                     <- sin filtro de activo
--
-- Consecuencia medida: con 7 leads vivos, gerencia veia 7 y el Directorio veia
-- 55 — todos los soft-borrados incluidos, con su PII (DNI, fecha de
-- nacimiento, genero). La MISMA forma esta copiada en `tareas_select` (qual
-- byte a byte identica, md5 4fc91b80…) y en `actividades_select` (el predicado
-- de leads copiado dentro del EXISTS — el «predicado copiado se desincroniza
-- en silencio» del que la propia suite avisa). Un arreglo solo en leads
-- dejaria las conversaciones y tareas del lead borrado legibles: se corrigen
-- LAS TRES en el mismo acto.
--
-- LO QUE NO SE TOCA, Y POR QUE: `equipo_select` tambien deja al lector global
-- ver filas con `activo = false`, pero ahi es SEMANTICA DELIBERADA del P04
-- (offboarding = activo=false, «revocado ≠ ajeno»): el roster historico se ve,
-- el dato comercial borrado no.
--
-- DECISION: Miguel, 01/09 («arregla las dos: la policy del directorio y el
-- fuera-de-roster»). Regla que instala: el lector global ve TODO lo vivo y
-- NADA de lo borrado — exactamente lo que ya valia para gerencia.
--
-- Marcha atras: supabase/scripts/rollback-lector-global-borrados.sql
begin;

set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 0. Preflight: el mundo es EXACTAMENTE el que se midio al escribir esto.
-- ---------------------------------------------------------------------------
do $preflight$
declare v_fila record;
begin
  for v_fila in
    select * from (values
      ('leads',       'leads_select',       '4fc91b80d5486cb2d7bff5e0abf29eab'),
      ('tareas',      'tareas_select',      '4fc91b80d5486cb2d7bff5e0abf29eab'),
      ('actividades', 'actividades_select', '40b0cd1967e8b20a426407c0975094f9')
    ) as t(tabla, politica, md5_esperado)
  loop
    if (select pg_catalog.md5(p.qual)
          from pg_catalog.pg_policies p
         where p.schemaname = 'crm' and p.tablename = v_fila.tabla
           and p.policyname = v_fila.politica and p.cmd = 'SELECT')
       is distinct from v_fila.md5_esperado then
      raise exception 'crm.%.% cambio bajo los pies (se esperaba %): re-medir antes de aplicar',
        v_fila.tabla, v_fila.politica, v_fila.md5_esperado;
    end if;
  end loop;
end
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Las tres politicas, con `activo` mandando sobre TODAS las ramas.
--    La forma interior se conserva letra a letra (initplans `(select ...)`
--    incluidos); lo unico que cambia es que el lector global entra al mismo
--    candado de `activo` que el resto.
-- ---------------------------------------------------------------------------
alter policy leads_select on crm.leads using (
  activo = true
  and (
    vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
    or (vendedor_id is null
        and asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    or (select private.es_lector_global())
  )
);

alter policy tareas_select on crm.tareas using (
  activo = true
  and (
    vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
    or (vendedor_id is null
        and asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    or (select private.es_lector_global())
  )
);

alter policy actividades_select on crm.actividades using (
  exists (
    select 1 from crm.leads l
    where l.id = actividades.lead_id
      and l.activo = true
      and (
        l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
        or (l.vendedor_id is null
            and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
        or (select private.rol_crm((select auth.uid()))) = 'gerencia'
        or (select private.es_lector_global())
      )
  )
);

-- ---------------------------------------------------------------------------
-- 2. Postflight de CONDUCTA, en la misma transaccion.
--    No se compara texto: se pregunta al mundo. Como postgres se cuenta lo
--    vivo; con los claims de un lector global REAL se comprueba que ve todo lo
--    vivo y ni una fila borrada. Si no hay ningun perfil de directorio activo,
--    la sonda lo dice con NOTICE y quedan las anclas estructurales (el ALTER
--    ya corrio y el preflight fijo el punto de partida).
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_lector uuid;
  v_leads_vivos int; v_leads_total int;
  v_ve_vivos int; v_ve_borrados int;
  v_tareas_borradas_visibles int;
  v_acts_de_borrados_visibles int;
begin
  select count(*) into v_leads_vivos from crm.leads where activo;
  select count(*) into v_leads_total from crm.leads;

  select p.id into v_lector
    from public.perfiles p
   where p.rol = 'directorio' and p.activo
   limit 1;

  if v_lector is null then
    raise notice 'POSTFLIGHT: sin perfil directorio activo para la sonda; quedan las anclas estructurales (vivos=%, total=%)',
      v_leads_vivos, v_leads_total;
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_lector, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);

    select count(*) into v_ve_vivos from crm.leads;
    select count(*) into v_ve_borrados from crm.leads where not activo;
    select count(*) into v_tareas_borradas_visibles from crm.tareas where not activo;
    select count(*) into v_acts_de_borrados_visibles
      from crm.actividades a
      join crm.leads l on l.id = a.lead_id and not l.activo;

    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);

    if v_ve_vivos <> v_leads_vivos then
      raise exception 'POSTFLIGHT: el lector global ve % leads y hay % vivos — la rama viva se rompio',
        v_ve_vivos, v_leads_vivos;
    end if;
    if v_ve_borrados <> 0 then
      raise exception 'POSTFLIGHT: el lector global sigue viendo % leads borrados', v_ve_borrados;
    end if;
    if v_tareas_borradas_visibles <> 0 then
      raise exception 'POSTFLIGHT: el lector global sigue viendo % tareas borradas', v_tareas_borradas_visibles;
    end if;
    if v_acts_de_borrados_visibles <> 0 then
      raise exception 'POSTFLIGHT: el lector global sigue viendo % actividades de leads borrados', v_acts_de_borrados_visibles;
    end if;
    raise notice 'POSTFLIGHT OK: lector global ve % vivos de % totales y 0 borrados (tareas y actividades incluidas)',
      v_ve_vivos, v_leads_total;
  end if;
end
$postflight$;

commit;
