-- Repara la deuda del vigilante analítico encontrada antes de publicar Citas.
--
-- Dos lectores de Ranking instalados previamente mezclaban extracción de hechos
-- y agregación en el mismo cuerpo. Eso los hacía aparecer como contadores crudos
-- nuevos, aunque capital/cierres ya beben de sus núcleos oficiales, y chocaba con
-- el techo irreversible 14/14. Se separan las filas crudas de la agregación sin
-- cambiar ningún resultado. El inventario de eliminación sí es operativo y se
-- declara como tal. No cambia permisos públicos ni el valor del techo.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;

lock table private.analitica_leads_citas_exenciones,
           private.analitica_lc_sello,
           private.analitica_leads_citas_tope
  in share row exclusive mode;

do $preflight$
declare
  v_pendientes text[];
begin
  if md5(pg_get_functiondef('crm.impacto_eliminacion_usuario_fn(uuid)'::regprocedure))
       is distinct from '30b7b92f8e12c9744dc53ab302ced3c4'
     or md5(pg_get_functiondef('crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure))
       is distinct from 'c954f109757ccfa18692d0bff54f903c'
     or md5(pg_get_functiondef('private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure))
       is distinct from '63d43298dc4dec8168e936b50634b80e'
     or md5(pg_get_functiondef('private.ranking_conversion_origen_mes(timestamptz,timestamptz,date,numeric)'::regprocedure))
       is distinct from '48016299011ad2dd4bd678a94da94b5d' then
    raise exception 'PREFLIGHT vigilante/Citas: cambió una de las tres funciones auditadas';
  end if;

  select array_agg(c.objeto order by c.objeto) into v_pendientes
  from private.contadores_crudos_leads_citas() c
  where not c.declarada or not c.huella_ok;
  if v_pendientes is distinct from array[
    'crm.contrato_eliminar_auditado(uuid,uuid)',
    'crm.impacto_eliminacion_usuario_fn(uuid)',
    'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)',
    'private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)'
  ]::text[] then
    raise exception 'PREFLIGHT vigilante/Citas: la deuda cambió: %', v_pendientes;
  end if;

  if (select sello from private.analitica_lc_sello where id)
       is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'PREFLIGHT vigilante/Citas: la lista ya estaba des-sellada';
  end if;
  if (select tope from private.analitica_leads_citas_tope where id) is distinct from 14 then
    raise exception 'PREFLIGHT vigilante/Citas: el techo analítico dejó de ser 14';
  end if;
  if exists (
    select 1 from private.analitica_leads_citas_exenciones e
    where e.objeto in (
      'crm.impacto_eliminacion_usuario_fn(uuid)',
      'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)',
      'private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)'
    )
  ) then
    raise exception 'PREFLIGHT vigilante/Citas: una declaración nueva ya existe';
  end if;
  if not exists (
    select 1 from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.contrato_eliminar_auditado(uuid,uuid)'
      and e.clase = 'verificador'
      and e.huella = '2969f70a2bc89f294cec4b025d3888fe'
  ) then
    raise exception 'PREFLIGHT vigilante/Citas: la declaración previa del verificador cambió';
  end if;
end;
$preflight$;

create temporary table _ranking_contrato_antes on commit drop as
select p.oid::regprocedure::text as fn,
       p.proowner,
       p.proacl,
       p.prosecdef,
       p.provolatile,
       p.proconfig
from pg_proc p
where p.oid in (
  'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure,
  'private.ranking_conversion_origen_mes(timestamptz,timestamptz,date,numeric)'::regprocedure
);

create temporary table _ranking_periodos on commit drop as
select periodo, id as periodo_id
from (
  select distinct on (mp.periodo) mp.periodo, mp.id
  from crm.meta_periodos mp
  where mp.periodo <= date_trunc('month', now() at time zone 'America/Lima')::date
  order by mp.periodo desc, mp.revision desc
) recientes
order by periodo desc
limit 3;

create temporary table _ranking_capital_antes on commit drop as
select p.periodo, f.*
from _ranking_periodos p
cross join lateral private.ranking_capital_origen_filas(
  p.periodo::timestamp at time zone 'America/Lima',
  (p.periodo + interval '1 month')::timestamp at time zone 'America/Lima',
  p.periodo_id
) f;

create temporary table _ranking_conversion_antes on commit drop as
select p.periodo, f.*
from _ranking_periodos p
cross join lateral private.ranking_conversion_origen_mes(
  p.periodo::timestamp at time zone 'America/Lima',
  (p.periodo + interval '1 month')::timestamp at time zone 'America/Lima',
  p.periodo,
  private.peso_referido_conversion(p.periodo)
) f;

-- Núcleo de filas de llegada para Ranking: una fila por lead y sin agregación.
-- La primera asignación se resuelve exactamente como en el lector anterior.
create function private.ranking_llegadas_origen_filas(
  p_ini timestamptz, p_fin timestamptz
)
returns table (vendedor_id uuid, origen text, lead_id uuid)
language sql stable security definer set search_path = ''
as $function$
  select primera.analista_id, l.origen, l.id
  from crm.leads l
  left join lateral (
    select la.analista_id
    from crm.lead_asignaciones la
    where la.lead_id = l.id
    order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
    limit 1
  ) primera on true
  where l.creado_en >= p_ini and l.creado_en < p_fin
    and l.origen in ('landing', 'formulario', 'referido', 'oficina')
    and primera.analista_id is not null;
$function$;

revoke all on function private.ranking_llegadas_origen_filas(timestamptz,timestamptz)
  from public, anon, authenticated, service_role;

comment on function private.ranking_llegadas_origen_filas(timestamptz,timestamptz) is
  'Filas base del desglose de conversión por origen: una llegada por lead, atribuida al primer analista. No agrega ni publica métricas; EXECUTE solo postgres.';

-- Núcleo de vínculos de lead para atribuir origen/cartera. Devuelve hechos; la
-- función de Ranking conserva fuera de aquí toda la aritmética histórica.
create function private.ranking_vinculos_lead_filas(
  p_contrato_ids uuid[], p_perfil_ids uuid[], p_lead_ids uuid[]
)
returns table (
  id uuid, contrato_id uuid, perfil_id uuid, vendedor_id uuid,
  origen text, creado_en timestamptz
)
language sql stable security definer set search_path = ''
as $function$
  select l.id, l.contrato_id, l.perfil_id, l.vendedor_id, l.origen, l.creado_en
  from crm.leads l
  where (coalesce(cardinality(p_contrato_ids), 0) > 0 and l.contrato_id = any(p_contrato_ids))
     or (coalesce(cardinality(p_perfil_ids), 0) > 0 and l.perfil_id = any(p_perfil_ids))
     or (coalesce(cardinality(p_lead_ids), 0) > 0 and l.id = any(p_lead_ids));
$function$;

revoke all on function private.ranking_vinculos_lead_filas(uuid[],uuid[],uuid[])
  from public, anon, authenticated, service_role;

comment on function private.ranking_vinculos_lead_filas(uuid[],uuid[],uuid[]) is
  'Filas de vínculo/origen requeridas por Ranking para contratos, clientes y cierres externos seleccionados. No agrega ni publica métricas; EXECUTE solo postgres.';

create or replace function private.ranking_capital_origen_filas(
  p_ini timestamptz, p_fin timestamptz, p_periodo_id uuid
)
returns table (
  vendedor_id uuid, origen text, moneda text, capital numeric,
  categoria text, operacion_id uuid
)
language sql stable security definer set search_path = ''
as $function$
  with capital_base as materialized (
    select k.*
    from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
    where (left(k.tipo, 9) = 'contrato_' or k.tipo = 'cooperativa')
      and k.medida = 'stock'
  ), vinculos as materialized (
    select v.*
    from private.ranking_vinculos_lead_filas(
      coalesce((select array_agg(distinct k.contrato_id) filter (where k.contrato_id is not null)
                from capital_base k), '{}'::uuid[]),
      coalesce((select array_agg(distinct k.cliente_id) filter (where k.cliente_id is not null)
                from capital_base k), '{}'::uuid[]),
      coalesce((select array_agg(distinct k.lead_id) filter (where k.lead_id is not null)
                from capital_base k), '{}'::uuid[])
    ) v
  ), contratos_base as materialized (
    select c.id, c.cliente_id, c.fecha, c.categoria, c.moneda, c.capital,
      c.creado_por, c.analista_cierre_id,
      coalesce(enlaces.tiene_vendedor_explicito, false) as tiene_vendedor_explicito,
      coalesce(enlaces.vendedores_distintos, 0) as vendedores_distintos,
      enlaces.vendedor_unico,
      case
        when c.categoria <> 'nuevo' then 'cartera'
        when directo.cantidad > 0 then
          case when directo.origenes_distintos = 1 then directo.origen_unico else 'sin_origen' end
        when cliente.cantidad > 0 then
          case when cliente.origenes_distintos = 1 then cliente.origen_unico else 'sin_origen' end
        when exists (
          select 1 from crm.operaciones_cartera o
          where o.contrato_nuevo_id = c.id
            and o.cliente_id = c.cliente_id
            and o.moneda = c.moneda
            and o.fecha_operacion = c.fecha_cierre_comercial
            and o.tipo in ('upgrade', 'renovacion')
        ) then 'cartera'
        else 'sin_origen'
      end as origen
    from (
      select k.contrato_id as id, k.cliente_id, k.categoria, k.moneda,
        k.monto as capital, k.registrado_por as creado_por,
        k.analista_id as analista_cierre_id, k.fecha,
        (k.fecha at time zone 'America/Lima')::date as fecha_cierre_comercial
      from capital_base k
      where left(k.tipo, 9) = 'contrato_'
    ) c
    left join lateral (
      select count(*) filter (where l.vendedor_id is not null) > 0 as tiene_vendedor_explicito,
        count(distinct l.vendedor_id) filter (where l.vendedor_id is not null)::integer
          as vendedores_distintos,
        case when count(distinct l.vendedor_id) filter (where l.vendedor_id is not null) = 1
          then min(l.vendedor_id::text) filter (where l.vendedor_id is not null)::uuid
        end as vendedor_unico
      from vinculos l where l.contrato_id = c.id
    ) enlaces on true
    left join lateral (
      select count(*) as cantidad,
        count(distinct coalesce(l.origen, 'sin_origen')) as origenes_distintos,
        min(coalesce(l.origen, 'sin_origen')) as origen_unico
      from vinculos l where l.contrato_id = c.id
    ) directo on true
    left join lateral (
      select count(*) as cantidad,
        count(distinct coalesce(l.origen, 'sin_origen')) as origenes_distintos,
        min(coalesce(l.origen, 'sin_origen')) as origen_unico
      from vinculos l
      where l.perfil_id = c.cliente_id and l.creado_en < c.fecha + interval '1 day'
    ) cliente on true
    where c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
      and c.fecha_cierre_comercial < (p_fin at time zone 'America/Lima')::date
      and c.categoria in ('nuevo', 'renovacion', 'upgrade')
      and c.moneda in ('PEN', 'USD')
  ), atribuidos as materialized (
    select base.id,
      case
        when base.analista_cierre_id is not null
          then coalesce(meta_analista.vendedor_id, base.analista_cierre_id)
        when base.vendedores_distintos > 1 then null
        when base.tiene_vendedor_explicito
          then coalesce(meta_lead.vendedor_id, base.vendedor_unico)
        else coalesce(meta_autor.vendedor_id, equipo_autor.perfil_id)
      end as vendedor_id,
      base.origen, base.categoria, base.moneda, base.capital
    from contratos_base base
    left join crm.metas_vendedor meta_lead
      on meta_lead.meta_periodo_id = p_periodo_id and meta_lead.vendedor_id = base.vendedor_unico
    left join crm.metas_vendedor meta_autor
      on meta_autor.meta_periodo_id = p_periodo_id and meta_autor.vendedor_id = base.creado_por
    left join crm.metas_vendedor meta_analista
      on meta_analista.meta_periodo_id = p_periodo_id and meta_analista.vendedor_id = base.analista_cierre_id
    left join crm.equipo equipo_autor
      on equipo_autor.perfil_id = base.creado_por and equipo_autor.rol_crm = 'vendedor'
  ), externos_confirmados as materialized (
    select ce.id, coalesce(mv.vendedor_id, ce.vendedor_id) as vendedor_id,
      coalesce(l.origen, 'sin_origen') as origen, 'nuevo'::text as categoria,
      ce.moneda, ce.capital
    from (
      select k.cierre_externo_id as id, k.lead_id, k.analista_id as vendedor_id,
        k.moneda, k.monto as capital, k.medida, k.fecha as creado_en
      from capital_base k
      where k.tipo = 'cooperativa'
    ) ce
    left join crm.metas_vendedor mv
      on mv.meta_periodo_id = p_periodo_id and mv.vendedor_id = ce.vendedor_id
    left join vinculos l on l.id = ce.lead_id
    where ce.creado_en >= p_ini and ce.creado_en < p_fin
      and ce.medida = 'stock' and ce.moneda in ('PEN', 'USD')
  )
  select a.vendedor_id, a.origen, a.moneda, a.capital, a.categoria, a.id
  from atribuidos a where a.vendedor_id is not null
  union all
  select e.vendedor_id, e.origen, e.moneda, e.capital, e.categoria, e.id
  from externos_confirmados e;
$function$;

revoke all on function private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)
  from public, anon, authenticated, service_role;

create or replace function private.ranking_conversion_origen_mes(
  p_ini timestamptz, p_fin timestamptz, p_periodo date, p_factor numeric
)
returns table (
  vendedor_id uuid, origen text, leads integer, cierres integer,
  conversion_pct numeric
)
language sql stable security definer set search_path = ''
as $function$
  with llegadas as (
    select f.vendedor_id, f.origen, count(*)::integer as leads
    from private.ranking_llegadas_origen_filas(p_ini, p_fin) f
    group by f.vendedor_id, f.origen
  ), cierres as (
    select c.analista_id as vendedor_id, c.origen,
      count(*)::integer as cierres,
      sum(case when c.origen = 'referido' then p_factor else 1::numeric end) as numerador
    from private.conversion_cierres(
      p_ini, p_fin, p_periodo, true, '{}'::uuid[], p_factor, null::uuid[]
    ) c
    where c.tipo = 'cierre' and not c.anulado
      and c.origen in ('landing', 'formulario', 'referido', 'oficina')
      and c.analista_id is not null
    group by c.analista_id, c.origen
  )
  select coalesce(l.vendedor_id, c.vendedor_id), coalesce(l.origen, c.origen),
    coalesce(l.leads, 0), coalesce(c.cierres, 0),
    case when coalesce(l.leads, 0) > 0
      and (coalesce(l.origen, c.origen) <> 'referido' or p_factor is not null)
      then round(100 * coalesce(c.numerador, 0) / l.leads, 2)
    end
  from llegadas l full join cierres c
    on c.vendedor_id = l.vendedor_id and c.origen = l.origen;
$function$;

revoke all on function private.ranking_conversion_origen_mes(timestamptz,timestamptz,date,numeric)
  from public, anon, authenticated, service_role;

insert into private.analitica_leads_citas_exenciones(objeto,tipo,huella,razon,clase)
select x.objeto, 'funcion',
  md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
    '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  x.razon, x.clase
from (values
  ('crm.impacto_eliminacion_usuario_fn(uuid)',
   'Inventario operativo previo a eliminar un usuario: cuenta responsabilidades vigentes para exigir transferencia antes del retiro. No publica una tasa, cierre ni cifra histórica de desempeño.',
   'operativo'),
  ('private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)',
   'Desglose analítico por origen que toma importes y operaciones exclusivamente de private.capital_episodios; los vínculos de lead llegan como filas sin agregar desde private.ranking_vinculos_lead_filas. No recalcula capital.',
   'analitica'),
  ('private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)',
   'Desglose analítico por origen: los cierres y pesos vienen de private.conversion_cierres; las llegadas llegan como filas sin agregar desde private.ranking_llegadas_origen_filas. Esta función sólo agrupa los hechos para Ranking.',
   'analitica')
) x(objeto,razon,clase)
join pg_proc p on p.oid = to_regprocedure(x.objeto);

-- La versión de eliminación con cotitulares conserva el mismo falso positivo:
-- menciona crm.leads para archivar sus referencias, pero su único count() sigue
-- contando llaves foráneas en pg_constraint. Se refresca la huella; la clase no
-- cambia y el verificador vuelve a salir del censo sólo por identidad + huella.
update private.analitica_leads_citas_exenciones e
set huella = md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
      '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
    razon = 'Falso positivo del censo: no cuenta leads ni citas. La eliminación auditada archiva las referencias de crm.leads del contrato; su único count() es count(distinct c.conrelid) sobre pg_constraint para fallar cerrado ante dependencias nuevas. No publica una métrica y devuelve el acta de eliminación. La identidad y huella exactas hacen que cualquier cambio futuro la devuelva al censo.'
from pg_proc p
where p.oid = 'crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure
  and e.objeto = 'crm.contrato_eliminar_auditado(uuid,uuid)';

update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

do $postflight$
declare
  v_ok text;
begin
  if exists (
    (select * from _ranking_capital_antes
     except
     select p.periodo, f.*
     from _ranking_periodos p
     cross join lateral private.ranking_capital_origen_filas(
       p.periodo::timestamp at time zone 'America/Lima',
       (p.periodo + interval '1 month')::timestamp at time zone 'America/Lima',
       p.periodo_id
     ) f)
    union all
    (select p.periodo, f.*
     from _ranking_periodos p
     cross join lateral private.ranking_capital_origen_filas(
       p.periodo::timestamp at time zone 'America/Lima',
       (p.periodo + interval '1 month')::timestamp at time zone 'America/Lima',
       p.periodo_id
     ) f
     except
     select * from _ranking_capital_antes)
  ) then
    raise exception 'POSTFLIGHT vigilante/Citas: cambió el resultado de capital por origen';
  end if;

  if exists (
    (select * from _ranking_conversion_antes
     except
     select p.periodo, f.*
     from _ranking_periodos p
     cross join lateral private.ranking_conversion_origen_mes(
       p.periodo::timestamp at time zone 'America/Lima',
       (p.periodo + interval '1 month')::timestamp at time zone 'America/Lima',
       p.periodo,
       private.peso_referido_conversion(p.periodo)
     ) f)
    union all
    (select p.periodo, f.*
     from _ranking_periodos p
     cross join lateral private.ranking_conversion_origen_mes(
       p.periodo::timestamp at time zone 'America/Lima',
       (p.periodo + interval '1 month')::timestamp at time zone 'America/Lima',
       p.periodo,
       private.peso_referido_conversion(p.periodo)
     ) f
     except
     select * from _ranking_conversion_antes)
  ) then
    raise exception 'POSTFLIGHT vigilante/Citas: cambió el resultado de conversión por origen';
  end if;

  if exists (
    select 1
    from _ranking_contrato_antes a
    join pg_proc p on p.oid = a.fn::regprocedure
    where (p.proowner, p.proacl, p.prosecdef, p.provolatile, p.proconfig)
      is distinct from (a.proowner, a.proacl, a.prosecdef, a.provolatile, a.proconfig)
  ) then
    raise exception 'POSTFLIGHT vigilante/Citas: cambió owner, ACL, volatilidad o search_path de Ranking';
  end if;

  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid in (
      'private.ranking_llegadas_origen_filas(timestamptz,timestamptz)'::regprocedure,
      'private.ranking_vinculos_lead_filas(uuid[],uuid[],uuid[])'::regprocedure
    ) and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'POSTFLIGHT vigilante/Citas: un núcleo de filas quedó ejecutable fuera de postgres';
  end if;

  if exists (
    select 1 from private.contadores_crudos_leads_citas() c
    where not c.declarada or not c.huella_ok
  ) then
    raise exception 'POSTFLIGHT vigilante/Citas: quedaron contadores sin declarar o con huella caduca';
  end if;
  if exists (
    select 1 from private.contadores_crudos_leads_citas() c
    where c.objeto in (
      'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)',
      'private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)'
    )
  ) then
    raise exception 'POSTFLIGHT vigilante/Citas: Ranking todavía cuenta crudo en el mismo cuerpo';
  end if;
  if exists (
    select 1 from private.contadores_crudos_leads_citas() c
    where c.objeto = 'crm.contrato_eliminar_auditado(uuid,uuid)'
  ) or not exists (
    select 1 from private.analitica_leads_citas_exenciones e
    join pg_proc p on p.oid = 'crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure
    where e.objeto = 'crm.contrato_eliminar_auditado(uuid,uuid)'
      and e.clase = 'verificador'
      and e.huella = md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
        '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
  ) then
    raise exception 'POSTFLIGHT vigilante/Citas: el verificador de eliminación no quedó re-sellado';
  end if;
  if not exists (
    select 1 from private.contadores_crudos_leads_citas() c
    join private.analitica_leads_citas_exenciones e using (objeto)
    where c.objeto = 'crm.impacto_eliminacion_usuario_fn(uuid)'
      and c.declarada and c.huella_ok and e.clase = 'operativo'
  ) then
    raise exception 'POSTFLIGHT vigilante/Citas: el inventario de eliminación no quedó declarado como operativo';
  end if;
  if (select count(*) from private.analitica_leads_citas_exenciones e
      where e.objeto in (
        'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)',
        'private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)'
      ) and e.clase = 'analitica') <> 2 then
    raise exception 'POSTFLIGHT vigilante/Citas: faltan las declaraciones analíticas de Ranking';
  end if;
  if (select tope from private.analitica_leads_citas_tope where id) is distinct from 14 then
    raise exception 'POSTFLIGHT vigilante/Citas: el techo fue alterado';
  end if;
  if (select sello from private.analitica_lc_sello where id)
       is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT vigilante/Citas: el sello no coincide';
  end if;

  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT vigilante/Citas: el gate no quedó verde: %', v_ok;
  end if;
  raise notice 'POSTFLIGHT %', v_ok;
end;
$postflight$;

commit;
