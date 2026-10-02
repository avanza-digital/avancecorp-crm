ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Segunda ronda (LEVEL 3) sobre la migración de `private.cartera_f5_personas_visibles(uuid)` que ya
revisaste (encargo `2026-09-29-codex-cartera-personas-visibles.md`, veredicto CHANGES_REQUESTED con
P1 «registrador transcrito no ejecutable» y P2 «la ruta idempotente omite dueño/ACL»). Comprueba que los
dos quedaron cerrados y refuta lo nuevo. Sin base ni red: todo está transcrito. Responde con VERDICT,
SUMMARY, FINDINGS P0–P3 con evidencia, RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Evidencia nueva
- P1: el registrador que viste estaba MUTILADO por el extracto (un filtro de líneas del encargo); abajo va
  el archivo COMPLETO tal cual. Ciclo ensayado en producción dentro de UNA transacción deshecha, con los
  archivos exactos: migración → migración repetida (ruta idempotente) → reversa → migración → registrador:
  huellas bca76d60… → bca76d60… → 45b18a6a… → bca76d60…, y fila `20260929230336 /
  crm_cartera_personas_visibles_cierre_sin_bucle / 1 sentencia(s)`. Después del rollback: huella viva
  45b18a6a… y 0 registros. (Un primer ciclo falló en el postflight porque comparaba `proconfig::text` con
  `{search_path=}` y el valor real lleva comillas `search_path=""`; corregido, y el fallo fue cerrado.)
- P2: la migración ahora exige dueño postgres, ACL `{postgres=X/postgres}`, SECURITY DEFINER, STABLE y
  `search_path` vacío en las DOS rutas (antes del `return` idempotente y en el postflight).
- Cobertura (solo lectura, como gerencia): 560 visibles; **0** personas cuyo nombre solo pueda salir del
  cierre externo (todas tienen perfil o lead con nombre); 0 «Identidad pendiente»; 37 personas con fuente
  coopac (la CTE nueva sí produce filas para ellas); `crm.inversionista_datos_contacto` tiene 0 filas.
  Además: `cartera_f5_listar` solo depende de la salida de `personas_visibles()` + `fuentes_reales`
  (sin cambios) + parámetros, así que si la salida completa de `personas_visibles()` es idéntica para un
  actor (md5 de todas las columnas, 4 actores), el listado es idéntico para CUALQUIER filtro de ese actor.
- Consumidores fuera del CRM: grep en edges compartidas, portal, Apps Script, edges del CRM y `cron.job`:
  ninguno. En el front solo `data/inversionistas-api.ts` y `data/inversionistas-queries.ts` (RPC, sin
  cambio de forma).
- Lector global: 0 perfiles `directorio` activos en producción; no se puede ejercitar con actor real.
  Se mantiene `and not i.lector` en el join nuevo, idéntico al del lateral.

## Migración completa `supabase/migrations/20260929230336_crm_cartera_personas_visibles_cierre_sin_bucle.sql`
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
-- Idempotente: si ya está la nueva, no hace nada (tras comprobar dueño/ACL/definer/search_path);
-- si el cuerpo vivo es otro, se niega.
-- Reversa: supabase/scripts/cartera-personas-visibles/reversa.sql (restaura el cuerpo
-- vivo del 29/09 tal cual; conserva la fila de schema_migrations: anotarlo en el ledger).

begin;
set local lock_timeout = '10s';

do $mig$
declare
  v_md5 text; v_oid oid := 'private.cartera_f5_personas_visibles(uuid)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  procedure_invariantes_ok boolean;
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que pg_get_functiondef NO cubre (Codex P2, 29/09): se exigen en las DOS rutas.
  -- search_path vacío se guarda como search_path="" (trampa conocida: lleva comillas).
  procedure_invariantes_ok := v_owner = 'postgres' and v_acl = '{postgres=X/postgres}' and v_secdef and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'));
  if not procedure_invariantes_ok then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función viva no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
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

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'bca76d60bd56905eff978357f539d300' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  if not (v_owner = 'postgres' and v_acl = '{postgres=X/postgres}' and v_secdef and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'cartera_personas_visibles_cierre_sin_bucle: aplicada (huella %)', v_md5;
end $mig$;

commit;
```

## Registrador completo `supabase/scripts/cartera-personas-visibles/registrar.sql` (el bloque `$stm$…$stm$` es la misma definición nueva de arriba; se abrevia)
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
  select md5(pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure)) into v_md5;
  if v_md5 <> 'bca76d60bd56905eff978357f539d300' then
    raise exception 'REGISTRO: la función no tiene la huella nueva (%); aplica primero la migración 20260929230336', v_md5;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260929230336' and coalesce(name,'') <> 'crm_cartera_personas_visibles_cierre_sin_bucle') then
    raise exception 'REGISTRO: la versión 20260929230336 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260929230336', 'crm_cartera_personas_visibles_cierre_sin_bucle',
        array[$stm$
<CREATE OR REPLACE FUNCTION … (la definición nueva completa, idéntica a la de la migración)>
$stm$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260929230336' and name = 'crm_cartera_personas_visibles_cierre_sin_bucle') then
    raise exception 'REGISTRO: tras el insert, la versión 20260929230336 no quedó con el nombre esperado';
  end if;
  raise notice 'REGISTRO_PERSONAS_VISIBLES_OK';
end $post$;
select version, name from supabase_migrations.schema_migrations where version = '20260929230336';
commit;

```

## Reversa completa `reversa.sql` (el bloque `$def$…$def$` es el cuerpo VIVO del 29/09 byte a byte, el que ya leíste entero en la primera ronda; se abrevia)
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
  execute $def$
<CREATE OR REPLACE FUNCTION … (cuerpo vivo del 29/09, con el lateral por persona)>
$def$;
  select md5(pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure)) into v_md5;
  if v_md5 <> '45b18a6af966f0ddfd137aec0b9b653d' then raise exception 'REVERSA: la huella restaurada no coincide (%)', v_md5; end if;
  raise notice 'REVERSA_PERSONAS_VISIBLES_OK (%)', v_md5;
end $rev$;
commit;

```

## Qué refutar ahora
1. ¿Quedan cerrados P1 y P2? ¿Alguna ruta de la migración, reversa o registro puede confirmar sin dejar
   la función exactamente como se espera (cuerpo, dueño, ACL, definer, volatilidad, search_path)?
2. El argumento «personas_visibles() idéntica ⇒ listar idéntica para cualquier filtro»: ¿tiene algún
   agujero (p. ej. `cartera_f5_listar` leyendo algo más, o efectos de `cartera_f5_registrar`)?
3. Con 0 nombres procedentes del cierre externo hoy, ¿qué prueba adicional pedirías antes de aplicar, si
   alguna, y sería proporcionada al riesgo (cambio de plan, no de reglas)?
