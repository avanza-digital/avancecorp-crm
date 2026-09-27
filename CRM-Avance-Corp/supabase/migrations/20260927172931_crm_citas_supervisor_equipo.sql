-- Citas para Supervisión, limitado al subárbol comercial vigente.
--
-- La pantalla muestra PII y hechos comerciales. La autorización vive en la
-- misma puerta SECURITY DEFINER que Gerencia: no basta con habilitar la ruta.
-- Se conserva el contrato público y la lectura global de Gerencia; Supervisión
-- recibe solamente tareas, asignaciones, cierres y capital de su subárbol.
-- El testigo independiente sigue siendo exclusivo de Gerencia: aun agregado,
-- revelar el total de toda la empresa sería una fuga de información.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;

do $preflight$
declare
  v_envoltorio text;
begin
  if pg_catalog.md5((select p.prosrc from pg_catalog.pg_proc p
      where p.oid = 'private.citas_gerencia_consulta(date,date)'::regprocedure))
     is distinct from 'c651d60710ec3f45f428fe3b68617210' then
    raise exception 'PREFLIGHT Citas/Supervisión: el lector privado cambió; conciliar el alcance antes de aplicarlo';
  end if;
  select p.prosrc into v_envoltorio
  from pg_catalog.pg_proc p
  where p.oid = 'crm.citas_gerencia_consulta_fn(date,date)'::regprocedure;
  if strpos(v_envoltorio, 'private.citas_gerencia_consulta(p_desde, p_hasta)') = 0
     or strpos(v_envoltorio, 'private.citas_testigo_mes(p_desde, p_hasta)') = 0 then
    raise exception 'PREFLIGHT Citas/Supervisión: el envoltorio no compone lector y testigo auditados';
  end if;
  perform private.assert_analitica_leads_citas();
end;
$preflight$;

-- La función ha recibido extensiones de capital e identidad por sustitución
-- puntual. Repetir aquí sus 17 KB desharía esas extensiones. Se parte de la
-- huella preflight y cada reemplazo exige una coincidencia única: si cambia el
-- contrato interno, falla sin instalar una lectura parcial.
do $alcance$
declare
  v_def text;
  v_buscar text[];
  v_nuevo text[];
  v_esperadas integer[] := array[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];
  v_i integer;
  v_veces integer;
begin
  v_def := pg_catalog.pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure);
  v_buscar := array[
    $b0$declare
  v_uid uuid := (select auth.uid());
  v_ahora timestamptz := now();$b0$,
    $b1$  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia'
  then raise exception 'No autorizado' using errcode='42501'; end if;$b1$,
    $b2$where l.activo and t.creado_en<=v_ahora
    union
    -- Citas generadas en el mes aunque su fecha prevista esté en otro mes.$b2$,
    $b3$where t.tipo='reunion' and t.activo and l.activo
      and t.creado_en>=v_ini and t.creado_en<v_fin and t.creado_en<=v_ahora
    union
    -- Entrevistas registradas este mes, aun cuando se programaron antes.$b3$,
    $b4$where t.tipo='reunion' and t.activo and l.activo and t.estado='completada'
      and a.tipo='reunion_realizada' and a.creado_en>=v_ini and a.creado_en<v_fin and a.creado_en<=v_ahora
    union
    select la.lead_id from crm.lead_asignaciones la$b4$,
    $b5$select la.lead_id from crm.lead_asignaciones la
    where la.asignado_en>=v_ini and la.asignado_en<v_fin and la.asignado_en<=v_ahora
    union
    select c.lead_id from private.conversion_cierres$b5$,
    $b6$p_desde,true,'{}'::uuid[],1,null::uuid[]) c where not c.anulado
  ), limites_historial as ($b6$,
    $b7$where t.creado_en<=v_ahora
    -- La fila extra dispara un error; nunca se entrega un historial truncado.$b7$,
    $b8$where t.perfil_id is not null and t.creado_en<=v_ahora;$b8$,
    $b9$from crm.lead_asignaciones la join crm.leads l on l.id=la.lead_id
    where la.asignado_en>=v_ini and la.asignado_en<v_fin and la.asignado_en<=v_ahora
    order by la.lead_id,la.analista_id,la.asignado_en,la.id$b9$,
    $b10$p_desde,true,'{}'::uuid[],1,null::uuid[]) c where not c.anulado
    -- Leads vinculados al capital del mes aunque no tengan actividad comercial en
    -- el mes: así los filtros de persona pueden acotar también ese capital.$b10$,
    $b11$where k.medida='stock' and not k.anulado
  ), personas as ($b11$,
    $b12$array(select (p->>'lead_id')::uuid from jsonb_array_elements(v_poblacion) p)) c
    where not c.anulado
  )
  select coalesce(jsonb_agg($b12$,
    $b13$where k.medida='stock' and not k.anulado
  ), vinculo as ($b13$,
    $b14$'analista_origen_id',p.analista_origen,'primera_asignacion_en',p.primera_asignacion,
    'analista_origen_nombre',coalesce(pa.nombre_completo,'Sin analista'),
    'supervisor_origen_id',coalesce(e.supervisor_id,p.supervisor_origen_id),
    'supervisor_origen_nombre',coalesce(ps.nombre_completo,'Sin supervisor')$b14$
  ];
  v_nuevo := array[
    $n0$declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_visibles uuid[];
  v_ahora timestamptz := now();$n0$,
    $n1$  if v_uid is null or v_rol not in ('gerencia','supervisor')
  then raise exception 'No autorizado' using errcode='42501'; end if;
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  if coalesce(cardinality(v_visibles), 0) = 0 then
    raise exception 'No autorizado' using errcode='42501';
  end if;$n1$,
    $n2$where l.activo and t.creado_en<=v_ahora
      and (v_rol='gerencia' or t.vendedor_id=any(v_visibles)
        or (t.vendedor_id is null and t.asignado_supervisor_id=any(v_visibles)))
    union
    -- Citas generadas en el mes aunque su fecha prevista esté en otro mes.$n2$,
    $n3$where t.tipo='reunion' and t.activo and l.activo
      and t.creado_en>=v_ini and t.creado_en<v_fin and t.creado_en<=v_ahora
      and (v_rol='gerencia' or t.vendedor_id=any(v_visibles)
        or (t.vendedor_id is null and t.asignado_supervisor_id=any(v_visibles)))
    union
    -- Entrevistas registradas este mes, aun cuando se programaron antes.$n3$,
    $n4$where t.tipo='reunion' and t.activo and l.activo and t.estado='completada'
      and a.tipo='reunion_realizada' and a.creado_en>=v_ini and a.creado_en<v_fin and a.creado_en<=v_ahora
      and (v_rol='gerencia' or t.vendedor_id=any(v_visibles)
        or (t.vendedor_id is null and t.asignado_supervisor_id=any(v_visibles)))
    union
    select la.lead_id from crm.lead_asignaciones la$n4$,
    $n5$select la.lead_id from crm.lead_asignaciones la
    where la.asignado_en>=v_ini and la.asignado_en<v_fin and la.asignado_en<=v_ahora
      and (v_rol='gerencia' or la.analista_id=any(v_visibles))
    union
    select c.lead_id from private.conversion_cierres$n5$,
    $n6$p_desde,true,'{}'::uuid[],1,null::uuid[]) c where not c.anulado
      and (v_rol='gerencia' or c.analista_id=any(v_visibles))
  ), limites_historial as ($n6$,
    $n7$where t.creado_en<=v_ahora
      and (v_rol='gerencia' or t.vendedor_id=any(v_visibles)
        or (t.vendedor_id is null and t.asignado_supervisor_id=any(v_visibles)))
    -- La fila extra dispara un error; nunca se entrega un historial truncado.$n7$,
    $n8$where t.perfil_id is not null and t.creado_en<=v_ahora
      and (v_rol='gerencia' or t.vendedor_id=any(v_visibles)
        or (t.vendedor_id is null and t.asignado_supervisor_id=any(v_visibles)));$n8$,
    $n9$from crm.lead_asignaciones la join crm.leads l on l.id=la.lead_id
    where la.asignado_en>=v_ini and la.asignado_en<v_fin and la.asignado_en<=v_ahora
      and (v_rol='gerencia' or la.analista_id=any(v_visibles))
    order by la.lead_id,la.analista_id,la.asignado_en,la.id$n9$,
    $n10$p_desde,true,'{}'::uuid[],1,null::uuid[]) c where not c.anulado
      and (v_rol='gerencia' or c.analista_id=any(v_visibles))
    -- Leads vinculados al capital del mes aunque no tengan actividad comercial en
    -- el mes: así los filtros de persona pueden acotar también ese capital.$n10$,
    $n11$where k.medida='stock' and not k.anulado
      and (v_rol='gerencia' or k.analista_id=any(v_visibles))
  ), personas as ($n11$,
    $n12$array(select (p->>'lead_id')::uuid from jsonb_array_elements(v_poblacion) p)) c
    where not c.anulado
      and (v_rol='gerencia' or c.analista_id=any(v_visibles))
  )
  select coalesce(jsonb_agg($n12$,
    $n13$where k.medida='stock' and not k.anulado
      and (v_rol='gerencia' or k.analista_id=any(v_visibles))
  ), vinculo as ($n13$,
    $n14$'analista_origen_id',case when v_rol='gerencia' or p.analista_origen=any(v_visibles)
      then p.analista_origen else null end,
    'primera_asignacion_en',case when v_rol='gerencia' or p.analista_origen=any(v_visibles)
      then p.primera_asignacion else null end,
    'analista_origen_nombre',case when v_rol='gerencia' or p.analista_origen=any(v_visibles)
      then coalesce(pa.nombre_completo,'Sin analista') else 'Sin analista' end,
    'supervisor_origen_id',case when v_rol='gerencia' or p.analista_origen=any(v_visibles)
      then coalesce(e.supervisor_id,p.supervisor_origen_id) else null end,
    'supervisor_origen_nombre',case when v_rol='gerencia' or p.analista_origen=any(v_visibles)
      then coalesce(ps.nombre_completo,'Sin supervisor') else 'Sin supervisor' end$n14$
  ];

  for v_i in 1..array_length(v_buscar, 1) loop
    v_veces := (length(v_def) - length(replace(v_def, v_buscar[v_i], '')))
      / nullif(length(v_buscar[v_i]), 0);
    if v_veces is distinct from v_esperadas[v_i] then
      raise exception 'Citas/Supervisión: no se reconoce el punto de alcance % (esperado %, encontrado %)',
        v_i, v_esperadas[v_i], v_veces;
    end if;
    v_def := replace(v_def, v_buscar[v_i], v_nuevo[v_i]);
  end loop;
  execute v_def;
end;
$alcance$;

-- La forma pública no cambia. El testigo global se compone únicamente cuando
-- el actor es Gerencia; para Supervisión la clave queda ausente (es opcional
-- en Valibot), por lo que no fuga cifras agregadas de otros equipos.
create or replace function crm.citas_gerencia_consulta_fn(p_desde date, p_hasta date)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with consulta as materialized (
    select private.citas_gerencia_consulta(p_desde, p_hasta) as payload
  )
  select payload || case when private.rol_crm((select auth.uid())) = 'gerencia'
    then jsonb_build_object('testigo', private.citas_testigo_mes(p_desde, p_hasta))
    else '{}'::jsonb
  end
  from consulta;
$function$;

comment on function crm.citas_gerencia_consulta_fn(date, date) is
  'Puerta de Citas para Gerencia y Supervisión. Gerencia recibe toda la empresa y el testigo global; Supervisión recibe solo su subárbol comercial vigente, sin testigo global.';

update private.analitica_leads_citas_exenciones e
set huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
      pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
    razon = 'Detalle operativo de Citas: Gerencia lee el universo comercial; Supervisión queda restringida en cada fuente (tareas, ledger de asignaciones, cierres y capital) al subárbol que private.vendedor_ids_visibles entrega para el actor. El lector devuelve PII solo del ámbito autorizado; el testigo global sigue exclusivo de Gerencia.'
from pg_catalog.pg_proc p
where p.oid = 'private.citas_gerencia_consulta(date,date)'::regprocedure
  and e.objeto = 'private.citas_gerencia_consulta(date,date)';

update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

do $postflight$
declare
  v_privada record;
  v_publica record;
begin
  select p.prosecdef, p.provolatile, p.proconfig, r.rolname, p.prosrc
    into v_privada
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'private.citas_gerencia_consulta(date,date)'::regprocedure;
  if v_privada.rolname is distinct from 'postgres' or not v_privada.prosecdef
     or v_privada.provolatile is distinct from 's'
     or v_privada.proconfig is distinct from array['search_path=""']::text[]
     or strpos(v_privada.prosrc, 'v_rol not in (''gerencia'',''supervisor'')') = 0
     or strpos(v_privada.prosrc, 'v_visibles := array(select private.vendedor_ids_visibles(v_uid))') = 0 then
    raise exception 'POSTFLIGHT Citas/Supervisión: atributos o verja del lector privado inesperados';
  end if;
  select p.prosecdef, p.provolatile, p.proconfig, p.prosrc
    into v_publica
  from pg_catalog.pg_proc p
  where p.oid = 'crm.citas_gerencia_consulta_fn(date,date)'::regprocedure;
  if v_publica.prosecdef or v_publica.provolatile is distinct from 's'
     or v_publica.proconfig is distinct from array['search_path=""']::text[]
     or strpos(v_publica.prosrc, 'private.citas_gerencia_consulta(p_desde, p_hasta)') = 0
     or strpos(v_publica.prosrc, 'private.rol_crm((select auth.uid())) = ''gerencia''') = 0 then
    raise exception 'POSTFLIGHT Citas/Supervisión: el envoltorio o el aislamiento del testigo es inesperado';
  end if;
  if pg_catalog.has_function_privilege('anon', 'crm.citas_gerencia_consulta_fn(date,date)', 'EXECUTE') then
    raise exception 'POSTFLIGHT Citas/Supervisión: anon no debe ejecutar la puerta de Citas';
  end if;
  if not exists (
    select 1
    from private.analitica_leads_citas_exenciones e
    join pg_catalog.pg_proc p on p.oid = 'private.citas_gerencia_consulta(date,date)'::regprocedure
    where e.objeto = 'private.citas_gerencia_consulta(date,date)'
      and e.huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
        pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
  ) then
    raise exception 'POSTFLIGHT Citas/Supervisión: el lector no quedó declarado con su huella instalada';
  end if;
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT Citas/Supervisión: el sello analítico no coincide';
  end if;
end;
$postflight$;

commit;
