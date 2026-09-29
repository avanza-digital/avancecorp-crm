ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Eres el revisor secundario (LEVEL 3: cambia el cuerpo de una función SECURITY DEFINER de `private`
que decide qué personas ve cada rol). Intenta REFUTAR; no confirmes por cortesía. No tienes base ni
red ni shell: todo está transcrito abajo. Responde con VERDICT (APPROVE / CHANGES_REQUESTED / BLOCK),
SUMMARY, FINDINGS P0–P3 con evidencia citada de este encargo, RISKS / TEST GAPS, NEXT ACTIONS,
CONFIDENCE. Sin hallazgo sin evidencia; distingue hipótesis de hecho.

## Contexto
CRM Supabase/Postgres 17.6. Paso 2 · fase 1 del refactor por módulos, aprobado por el dueño. La lista
«Cartera de inversionistas» (`crm.cartera_inversionistas_filtrada_fn` → `private.cartera_f5_listar` →
`private.cartera_f5_personas_visibles()` → `…(uuid)`) tardaba 2,3 s por página para gerencia.

EXPLAIN ANALYZE del cuerpo de `personas_visibles(null)` como gerencia (29/09, solo lectura):
```
Nested Loop Left Join ... (actual time=74.014..2383.520 rows=560 loops=1)          ← total 2.384 ms
  -> Nested Loop Left Join ... (actual time=70.274..89.380 rows=560 loops=1)        ← todo lo demás: 89 ms
  -> Limit (actual time=4.080..4.080 rows=0 loops=560)                              ← el lateral `ce`
       -> Incremental Sort ...
          -> Nested Loop (actual time=3.966..4.077 rows=0 loops=560)
               -> Index Scan Backward using idx_cierres_externos_creado_en on cierres_externos ce0 (rows=41 loops=560)
               -> CTE Scan on fuentes f (cost=0.00..12.50 rows=2) (actual time=0.099..0.099 rows=0 loops=22897)
Execution Time: 2384.924 ms
```
Datos: 565 inversionistas (560 canónicas visibles a gerencia), 41 cierres_externos, 718 filas en la
CTE `fuentes` (no demo). `crm.cierres_externos` tiene índices en (inversionista_id), (lead_id) y
(creado_en). Roles activos: 2 gerencia, 4 supervisores (1 con bandeja), 26 analistas (18 con cartera),
0 perfiles `directorio` activos (lector global no ejercitable con actor real).

## El cambio (diff exacto dentro de `private.cartera_f5_personas_visibles(p_inversionista uuid)`,
LANGUAGE sql, STABLE, SECURITY DEFINER, SET search_path TO '', dueño postgres, ACL {postgres=X/postgres})

ANTES (lateral por persona, al final del SELECT principal sobre `autorizadas i`):
```sql
  left join lateral (
    select ce0.nombre_completo from crm.cierres_externos ce0
      join fuentes f on f.fuente_id=ce0.id and f.empresa<>'avance'
    where f.inversionista_id=i.id and not i.lector
    order by ce0.creado_en desc,ce0.id limit 1
  ) ce on true
```
DESPUÉS (una CTE nueva justo después de `fuentes`, y un left join en su lugar):
```sql
  ), cierres_nombre as materialized (
    select distinct on (f.inversionista_id) f.inversionista_id,ce0.nombre_completo
    from fuentes f join crm.cierres_externos ce0 on ce0.id=f.fuente_id
    where f.empresa<>'avance'
    order by f.inversionista_id,ce0.creado_en desc,ce0.id
  ), demos as materialized (
  ...
  left join cierres_nombre ce on ce.inversionista_id=i.id and not i.lector
```
`ce.nombre_completo` se usa solo en `nombre`: `coalesce(nullif(btrim(p.nombre_completo),''), case when not
i.lector then nullif(btrim(datos.nombre_completo),'') end, nullif(btrim(l.nombre_completo),''),
nullif(btrim(ce.nombre_completo),''), 'Identidad pendiente de completar')`. `fuentes` =
`select * from todas_fuentes where es_demo is not true`; `todas_fuentes` = `private.cartera_f5_fuentes()`
(cuya columna `inversionista_id` puede ser NULL cuando el contrato no resuelve persona).

## Cuerpo VIVO completo (antes), para que juzgues el contexto
```sql
CREATE OR REPLACE FUNCTION private.cartera_f5_personas_visibles(p_inversionista uuid)
 RETURNS TABLE(inversionista_id uuid, nombre text, documento_tipo text, documento text, documento_verificado boolean, telefono text, correo text, estado text, no_contactar boolean, responsable_id uuid, responsable_nombre text, perfil_id uuid, perfil_ids uuid[], lead_ids uuid[], creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with destino as materialized (
    -- Conserva aliases/fusiones: el filtro siempre se aplica a la identidad canónica.
    select private.inversionista_canonica(p_inversionista) id
  ), actor as materialized (
    select (select auth.uid()) uid,private.rol_crm((select auth.uid())) rol,
      private.es_lector_global() lector,
      array(select private.vendedor_ids_visibles((select auth.uid()))) visibles
  ), identidades as materialized (
    -- La resolución recursiva canónica sigue siendo la autoridad de las fusiones.
    select i.id,private.inversionista_canonica(i.id) canonica,i.perfil_id
    from crm.inversionistas i
  ), contactos as materialized (
      select distinct on (x.canonica) x.canonica,d0.*
      from crm.inversionista_datos_contacto d0 join identidades x on x.id=d0.inversionista_id
      order by x.canonica,d0.actualizado_en desc,d0.inversionista_id
    ), todas_fuentes as materialized (
    select * from private.cartera_f5_fuentes()
  ), fuentes as materialized (
    select * from todas_fuentes where es_demo is not true
  ), demos as materialized (
    select * from todas_fuentes where es_demo is true
  ), con_historia as materialized (
    select i.canonica id from demos f join identidades i on i.perfil_id=f.perfil_id
    union select i.canonica from demos f
      join crm.inversiones iv on iv.id=f.inversion_id
      join identidades i on i.id=iv.inversionista_id
    union select i.canonica from demos f
      join crm.cierres_externos ce on ce.id=f.fuente_id
      join identidades i on i.id=ce.inversionista_id
    union select i.canonica from demos f
      join crm.leads l on l.id=f.lead_id
      join identidades i on i.id=l.inversionista_id
    union select i.canonica from demos f
      join crm.inversionista_leads il on il.lead_id=f.lead_id
      join identidades i on i.id=il.inversionista_id
  ), perfiles_lector as materialized (
    select v.cliente_id from actor a
      cross join lateral private.cliente_ids_visibles_crm() v where a.lector
  ), perfiles_cliente as materialized (
    select i.canonica,p.id perfil_id from identidades i
      join public.perfiles p on p.id=i.perfil_id and p.rol='cliente'
  ), perfiles_enlazados as materialized (
    select p.canonica,array_agg(distinct p.perfil_id order by p.perfil_id) perfiles
    from perfiles_cliente p cross join actor a
    where not a.lector or exists(select 1 from perfiles_lector v where v.cliente_id=p.perfil_id)
    group by p.canonica
  ), leads_enlazados as materialized (
    select x.canonica,array_agg(x.lead_id order by x.lead_id) leads from (
      select i.canonica,l.id lead_id from crm.leads l
        join identidades i on i.id=l.inversionista_id
      union select i.canonica,il.lead_id from crm.inversionista_leads il
        join identidades i on i.id=il.inversionista_id
    ) x group by x.canonica
  ), bandeja_supervisor as materialized (
    select distinct i.canonica from crm.leads l
      join identidades i on i.id=l.inversionista_id cross join actor a
    where a.rol='supervisor' and l.activo and l.vendedor_id is null
      and l.asignado_supervisor_id=a.uid
  ), autorizadas as materialized (
    select i.*,a.lector from crm.inversionistas i cross join actor a
    where a.uid is not null and i.inversionista_canonico_id is null
      -- Recorta antes de los laterales de presentación; no elimina ninguna regla de acceso.
      and (p_inversionista is null or i.id=(select id from destino))
      and (a.rol in ('vendedor','supervisor','gerencia') or a.lector)
      and (a.rol='gerencia'
        or (not a.lector and i.responsable_relacion_id=any(a.visibles))
        or (a.rol='supervisor' and i.responsable_relacion_id is null
          and exists(select 1 from bandeja_supervisor b where b.canonica=i.id))
        or (a.lector and exists(select 1 from perfiles_enlazados p where p.canonica=i.id)))
      and (exists(select 1 from fuentes f where f.inversionista_id=i.id)
        or (not exists(select 1 from con_historia h where h.id=i.id)
          and exists(select 1 from perfiles_cliente p where p.canonica=i.id)))
  )
  select i.id,
    coalesce(nullif(btrim(p.nombre_completo),''),case when not i.lector then nullif(btrim(datos.nombre_completo),'') end,nullif(btrim(l.nombre_completo),''),
      nullif(btrim(ce.nombre_completo),''),'Identidad pendiente de completar'),
    case when i.lector then p.tipo_documento else d.tipo_documento end,
    case when i.lector then p.dni else d.documento_normalizado end,
    coalesce(d.verificado and (not i.lector or (d.tipo_documento=p.tipo_documento
      and d.documento_normalizado=p.dni)),false),
    coalesce(p.telefono,case when not i.lector then case when p.id is null and datos.inversionista_id is not null then datos.telefono else l.telefono end end),
    coalesce(p.correo,case when not i.lector then l.correo end),
    i.estado,i.no_contactar or coalesce(l.no_contactar,false),
    i.responsable_relacion_id,r.nombre_completo,i.perfil_id,
    coalesce(pe.perfiles,'{}'::uuid[]),coalesce(le.leads,'{}'::uuid[]),i.creado_en
  from autorizadas i left join contactos datos on datos.canonica=i.id and not i.lector
  left join public.perfiles r on r.id=i.responsable_relacion_id
  left join perfiles_enlazados pe on pe.canonica=i.id
  left join leads_enlazados le on le.canonica=i.id
  left join lateral (
    select p0.* from public.perfiles p0 where p0.id=any(pe.perfiles)
      and (not i.lector or p0.rol='cliente')
    order by (p0.id=i.perfil_id) desc,p0.activo desc,p0.id limit 1
  ) p on true
  left join lateral (
    select l0.* from crm.leads l0 where l0.id=any(le.leads) and not i.lector
    order by (l0.inversionista_id=i.id) desc,l0.actualizado_en desc,l0.id limit 1
  ) l on true
  left join lateral (
    select ce0.nombre_completo from crm.cierres_externos ce0
      join fuentes f on f.fuente_id=ce0.id and f.empresa<>'avance'
    where f.inversionista_id=i.id and not i.lector
    order by ce0.creado_en desc,ce0.id limit 1
  ) ce on true
  left join lateral (
    select d0.* from crm.inversionista_identificadores d0
    where d0.inversionista_id=i.id and d0.estado='vigente'
    order by d0.verificado desc,
      case d0.tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,d0.id
    limit 1
  ) d on true;
$function$
```

## Oráculo de igualdad en producción (una transacción, deshecha con raise; READ COMMITTED obligatorio
por `resolver_en_puertas_bajo_candado`)
Actores: gerencia, el supervisor con bandeja, los 2 analistas con más cartera. Por actor: md5 de
`personas_visibles()` completa (string_agg ordenada por id, todas las columnas), listado en 11 variantes
para gerencia (pág. 1, 2, 3, texto 'a', empresa avance, estado vigente, por_vencer, sin_responsable,
contacto no_contactar, mes sin_fecha, tamaño 10) y 3 para los demás, `cartera_inversionistas_estado_fn`,
`inversionista_ficha_fn` (3 personas gerencia, 1 los demás), `inversionista_gestion_fn`,
`postventa_perfil_fn`, `postventa_vencimientos_fn`. Resultado: **46 casos iguales, 0 distintos**.
Tiempos antes → después (ms): gerencia pv 4527→157, l_p1 3216→228, l_p2 2438→227, l_texto 2407→229,
l_pv 2368→211; supervisor pv 2227→198, l_p1 1215→233; vendedor1 pv 612→132, l_p1 1282→162; ficha ~485→~480
(la ficha tiene otro coste, fuera de alcance). Huella nueva medida: bca76d60bd56905eff978357f539d300.
Ciclo migración → reversa → migración → registrador también ensayado en producción con rollback.

## Migración `supabase/migrations/20260929230336_crm_cartera_personas_visibles_cierre_sin_bucle.sql`
```sql
-- ============================================================================
-- Cartera de inversionistas: el nombre del cierre externo se resuelve en un solo
-- recorrido (private.cartera_f5_personas_visibles(uuid))
-- ============================================================================
-- Paso 2 · fase 1 del refactor por módulos, aprobado por Miguel el 29/09/2026 («dale,
-- arranca la Fase 1»). Nota del vault: «CRM - perfil de carga lectura vs escritura (2026-09-29)».
--
-- Problema medido en producción (EXPLAIN ANALYZE como gerencia, 29/09): de los 2.384 ms del
-- listado, 2.283 ms eran UN lateral: por cada una de las 560 personas se recorría
-- crm.cierres_externos (41 filas) y, por cada fila, la CTE `fuentes` (718 filas):
-- 22.897 recorridos de la CTE. El resto de la función cuesta ~100 ms.
--
-- Cambio: ese lateral pasa a una CTE `cierres_nombre` calculada UNA vez
-- (`distinct on (inversionista_id) … order by inversionista_id, creado_en desc, id`,
-- el mismo criterio de desempate que el `order by … limit 1` de antes) y un `left join`
-- con la misma condición `and not i.lector`. Nada más cambia: mismas CTEs, mismas reglas
-- de acceso (actor, lector global, bandeja del supervisor, demos, canónicas), misma
-- firma, mismo dueño y ACL (create or replace los conserva), STABLE, SECURITY DEFINER,
-- search_path vacío. Ninguna puerta ni el front cambian.
--
-- Oráculo de igualdad en producción (transacción deshecha, 29/09): 46/46 resultados
-- idénticos (md5) para gerencia, supervisor con bandeja y dos analistas con cartera:
-- personas_visibles() completa, listado en 11 variantes (páginas 1–3, texto, empresa,
-- estado, por vencer, sin responsable, contacto, mes, tamaño 10), estado, ficha (3),
-- gestión, postventa perfil y vencimientos. Tiempos: listado de gerencia 2.357–3.216 ms →
-- 181–232 ms; supervisor 1.215 → 185–233 ms; analista 377–1.282 → 159–162 ms.
--
-- Huellas (md5 de pg_get_functiondef): viva 45b18a6af966f0ddfd137aec0b9b653d → nueva bca76d60bd56905eff978357f539d300.
-- Idempotente: si ya está la nueva, no hace nada; si el cuerpo vivo es otro, se niega.
-- Reversa: supabase/scripts/cartera-personas-visibles/reversa.sql (restaura el cuerpo
-- vivo del 29/09 tal cual; conserva la fila de schema_migrations: anotarlo en el ledger).

begin;
set local lock_timeout = '10s';

do $mig$
declare v_md5 text;
begin
  select md5(pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure)) into v_md5;
  if v_md5 = 'bca76d60bd56905eff978357f539d300' then
    raise notice 'cartera_personas_visibles_cierre_sin_bucle: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> '45b18a6af966f0ddfd137aec0b9b653d' then
    raise exception 'PREFLIGHT: private.cartera_f5_personas_visibles(uuid) no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.cartera_f5_personas_visibles(p_inversionista uuid)
 RETURNS TABLE(inversionista_id uuid, nombre text, documento_tipo text, documento text, documento_verificado boolean, telefono text, correo text, estado text, no_contactar boolean, responsable_id uuid, responsable_nombre text, perfil_id uuid, perfil_ids uuid[], lead_ids uuid[], creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with destino as materialized (
    -- Conserva aliases/fusiones: el filtro siempre se aplica a la identidad canónica.
    select private.inversionista_canonica(p_inversionista) id
  ), actor as materialized (
    select (select auth.uid()) uid,private.rol_crm((select auth.uid())) rol,
      private.es_lector_global() lector,
      array(select private.vendedor_ids_visibles((select auth.uid()))) visibles
  ), identidades as materialized (
    -- La resolución recursiva canónica sigue siendo la autoridad de las fusiones.
    select i.id,private.inversionista_canonica(i.id) canonica,i.perfil_id
    from crm.inversionistas i
  ), contactos as materialized (
      select distinct on (x.canonica) x.canonica,d0.*
      from crm.inversionista_datos_contacto d0 join identidades x on x.id=d0.inversionista_id
      order by x.canonica,d0.actualizado_en desc,d0.inversionista_id
    ), todas_fuentes as materialized (
    select * from private.cartera_f5_fuentes()
  ), fuentes as materialized (
    select * from todas_fuentes where es_demo is not true
  ), cierres_nombre as materialized (
    -- Un solo recorrido (29/09/2026): el lateral por persona recorría la CTE fuentes
    -- 22.897 veces (2,3 s de los 2,4 s del listado). Mismo criterio que antes: el
    -- cierre externo más reciente (creado_en desc, id) entre las fuentes no demo
    -- de la persona con empresa distinta de 'avance'.
    select distinct on (f.inversionista_id) f.inversionista_id,ce0.nombre_completo
    from fuentes f join crm.cierres_externos ce0 on ce0.id=f.fuente_id
    where f.empresa<>'avance'
    order by f.inversionista_id,ce0.creado_en desc,ce0.id
  ), demos as materialized (
    select * from todas_fuentes where es_demo is true
  ), con_historia as materialized (
    select i.canonica id from demos f join identidades i on i.perfil_id=f.perfil_id
    union select i.canonica from demos f
      join crm.inversiones iv on iv.id=f.inversion_id
      join identidades i on i.id=iv.inversionista_id
    union select i.canonica from demos f
      join crm.cierres_externos ce on ce.id=f.fuente_id
      join identidades i on i.id=ce.inversionista_id
    union select i.canonica from demos f
      join crm.leads l on l.id=f.lead_id
      join identidades i on i.id=l.inversionista_id
    union select i.canonica from demos f
      join crm.inversionista_leads il on il.lead_id=f.lead_id
      join identidades i on i.id=il.inversionista_id
  ), perfiles_lector as materialized (
    select v.cliente_id from actor a
      cross join lateral private.cliente_ids_visibles_crm() v where a.lector
  ), perfiles_cliente as materialized (
    select i.canonica,p.id perfil_id from identidades i
      join public.perfiles p on p.id=i.perfil_id and p.rol='cliente'
  ), perfiles_enlazados as materialized (
    select p.canonica,array_agg(distinct p.perfil_id order by p.perfil_id) perfiles
    from perfiles_cliente p cross join actor a
    where not a.lector or exists(select 1 from perfiles_lector v where v.cliente_id=p.perfil_id)
    group by p.canonica
  ), leads_enlazados as materialized (
    select x.canonica,array_agg(x.lead_id order by x.lead_id) leads from (
      select i.canonica,l.id lead_id from crm.leads l
        join identidades i on i.id=l.inversionista_id
      union select i.canonica,il.lead_id from crm.inversionista_leads il
        join identidades i on i.id=il.inversionista_id
    ) x group by x.canonica
  ), bandeja_supervisor as materialized (
    select distinct i.canonica from crm.leads l
      join identidades i on i.id=l.inversionista_id cross join actor a
    where a.rol='supervisor' and l.activo and l.vendedor_id is null
      and l.asignado_supervisor_id=a.uid
  ), autorizadas as materialized (
    select i.*,a.lector from crm.inversionistas i cross join actor a
    where a.uid is not null and i.inversionista_canonico_id is null
      -- Recorta antes de los laterales de presentación; no elimina ninguna regla de acceso.
      and (p_inversionista is null or i.id=(select id from destino))
      and (a.rol in ('vendedor','supervisor','gerencia') or a.lector)
      and (a.rol='gerencia'
        or (not a.lector and i.responsable_relacion_id=any(a.visibles))
        or (a.rol='supervisor' and i.responsable_relacion_id is null
          and exists(select 1 from bandeja_supervisor b where b.canonica=i.id))
        or (a.lector and exists(select 1 from perfiles_enlazados p where p.canonica=i.id)))
      and (exists(select 1 from fuentes f where f.inversionista_id=i.id)
        or (not exists(select 1 from con_historia h where h.id=i.id)
          and exists(select 1 from perfiles_cliente p where p.canonica=i.id)))
  )
  select i.id,
    coalesce(nullif(btrim(p.nombre_completo),''),case when not i.lector then nullif(btrim(datos.nombre_completo),'') end,nullif(btrim(l.nombre_completo),''),
      nullif(btrim(ce.nombre_completo),''),'Identidad pendiente de completar'),
    case when i.lector then p.tipo_documento else d.tipo_documento end,
    case when i.lector then p.dni else d.documento_normalizado end,
    coalesce(d.verificado and (not i.lector or (d.tipo_documento=p.tipo_documento
      and d.documento_normalizado=p.dni)),false),
    coalesce(p.telefono,case when not i.lector then case when p.id is null and datos.inversionista_id is not null then datos.telefono else l.telefono end end),
    coalesce(p.correo,case when not i.lector then l.correo end),
    i.estado,i.no_contactar or coalesce(l.no_contactar,false),
    i.responsable_relacion_id,r.nombre_completo,i.perfil_id,
    coalesce(pe.perfiles,'{}'::uuid[]),coalesce(le.leads,'{}'::uuid[]),i.creado_en
  from autorizadas i left join contactos datos on datos.canonica=i.id and not i.lector
  left join public.perfiles r on r.id=i.responsable_relacion_id
  left join perfiles_enlazados pe on pe.canonica=i.id
  left join leads_enlazados le on le.canonica=i.id
  left join lateral (
    select p0.* from public.perfiles p0 where p0.id=any(pe.perfiles)
      and (not i.lector or p0.rol='cliente')
    order by (p0.id=i.perfil_id) desc,p0.activo desc,p0.id limit 1
  ) p on true
  left join lateral (
    select l0.* from crm.leads l0 where l0.id=any(le.leads) and not i.lector
    order by (l0.inversionista_id=i.id) desc,l0.actualizado_en desc,l0.id limit 1
  ) l on true
  left join cierres_nombre ce on ce.inversionista_id=i.id and not i.lector
  left join lateral (
    select d0.* from crm.inversionista_identificadores d0
    where d0.inversionista_id=i.id and d0.estado='vigente'
    order by d0.verificado desc,
      case d0.tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,d0.id
    limit 1
  ) d on true;
$function$
$def$;

  select md5(pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure)) into v_md5;
  if v_md5 <> 'bca76d60bd56905eff978357f539d300' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  if (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid='private.cartera_f5_personas_visibles(uuid)'::regprocedure) <> 'postgres'
     or (select p.proacl::text from pg_proc p where p.oid='private.cartera_f5_personas_visibles(uuid)'::regprocedure) is distinct from '{postgres=X/postgres}'
     or (select p.prosecdef and p.provolatile='s' and p.proconfig::text = '{search_path=}' from pg_proc p where p.oid='private.cartera_f5_personas_visibles(uuid)'::regprocedure) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, volatilidad, definer o search_path cambiaron';
  end if;
  raise notice 'cartera_personas_visibles_cierre_sin_bucle: aplicada (huella %)', v_md5;
end $mig$;

commit;
```

## Reversa `supabase/scripts/cartera-personas-visibles/reversa.sql` (el cuerpo restaurado es el vivo de arriba, byte a byte; se omite aquí)
```sql
-- REVERSA de 20260929230336_crm_cartera_personas_visibles_cierre_sin_bucle: restaura el cuerpo VIVO del 29/09/2026 de
-- private.cartera_f5_personas_visibles(uuid) tal cual (con el lateral por persona). Se niega si la
-- función no tiene la huella nueva. NO toca schema_migrations: si se revierte, anotarlo en MIGRACIONES.md
-- el mismo día (un replay por historial la daría por aplicada).
begin;
set local lock_timeout = '10s';
do $rev$
declare v_md5 text;
begin
  select md5(pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure)) into v_md5;
  if v_md5 = '45b18a6af966f0ddfd137aec0b9b653d' then raise notice 'REVERSA: ya está el cuerpo vivo del 29/09 (%)', v_md5; return; end if;
  if v_md5 <> 'bca76d60bd56905eff978357f539d300' then raise exception 'REVERSA: huella desconocida (%), no se toca', v_md5; end if;
  ... execute $def$ <cuerpo vivo> $def$; comprobación de huella 45b18a6a… ...
```

## Registrador `registrar.sql`
```sql
-- REGISTRO en supabase_migrations.schema_migrations de 20260929230336_crm_cartera_personas_visibles_cierre_sin_bucle.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega
-- si la función no tiene la huella nueva o si la versión ya está registrada con otro nombre; relee la fila
-- efectiva antes de confirmar (Codex P2 del 29/09).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_cartera_personas_visibles_cierre_sin_bucle'));
do $chk$
declare v_md5 text;
begin
    raise exception 'REGISTRO: la función no tiene la huella nueva (%); aplica primero la migración 20260929230336', v_md5;
             where version = '20260929230336' and coalesce(name,'') <> 'crm_cartera_personas_visibles_cierre_sin_bucle') then
    raise exception 'REGISTRO: la versión 20260929230336 ya está registrada con otro nombre';
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260929230336', 'crm_cartera_personas_visibles_cierre_sin_bucle',
        array[$stm$
CREATE OR REPLACE FUNCTION private.cartera_f5_personas_visibles(p_inversionista uuid)
 RETURNS TABLE(inversionista_id uuid, nombre text, documento_tipo text, documento text, documento_verificado boolean, telefono text, correo text, estado text, no_contactar boolean, responsable_id uuid, responsable_nombre text, perfil_id uuid, perfil_ids uuid[], lead_ids uuid[], creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
    -- Conserva aliases/fusiones: el filtro siempre se aplica a la identidad canónica.
    select private.inversionista_canonica(p_inversionista) id
  ), actor as materialized (
    select (select auth.uid()) uid,private.rol_crm((select auth.uid())) rol,
      private.es_lector_global() lector,
      array(select private.vendedor_ids_visibles((select auth.uid()))) visibles
  ), identidades as materialized (
    -- La resolución recursiva canónica sigue siendo la autoridad de las fusiones.
    select i.id,private.inversionista_canonica(i.id) canonica,i.perfil_id
    from crm.inversionistas i
  ), contactos as materialized (
      select distinct on (x.canonica) x.canonica,d0.*
      from crm.inversionista_datos_contacto d0 join identidades x on x.id=d0.inversionista_id
      order by x.canonica,d0.actualizado_en desc,d0.inversionista_id
    ), todas_fuentes as materialized (
    select * from private.cartera_f5_fuentes()
  ), fuentes as materialized (
```

Método de aplicación: `supabase db query --linked --file <migración>` (lo lanza el dueño con `!`) →
`registrar.sql` → `verificar.sql` (solo lectura, mide) → advisors. Sin cambio de front ni de tipos.

## Lo que debes intentar refutar
R1. Equivalencia semántica del lateral vs `distinct on`: empates (`creado_en` igual), `inversionista_id`
NULL en `fuentes`, personas con varias fuentes coopac, `not i.lector` (lector global: antes el lateral
devolvía ninguna fila; ahora el join no casa), demos (la CTE usa `fuentes`, ya sin demos, como antes).
R2. ¿Cambia algo del acceso? La función es SECURITY DEFINER con search_path vacío: ¿el nuevo código
introduce alguna referencia sin calificar o un objeto nuevo? ¿La CTE `materialized` altera el plan de
otras partes (p. ej. `autorizadas`)?
R3. ¿El oráculo deja huecos que importen? (lector global sin actor real; texto que solo casa por el nombre
del cierre externo; personas cuyo nombre sale SOLO del cierre externo: ¿cuántas hay y quedan cubiertas
por el md5 de `personas_visibles()` completa?).
R4. Migración: idempotencia, preflight/postflight, `create or replace` conserva dueño/ACL/`proconfig`;
riesgo de que `pg_get_functiondef` cambie su formato y la huella deje de coincidir (postflight y
registrador/reversa dependen de ella).
R5. ¿Hay consumidores fuera del CRM (edge functions, portal, cron) de `personas_visibles`/`listar` que
puedan ver una diferencia? (nombres de la casa: `crm-*` edges; el portal usa `public`).
