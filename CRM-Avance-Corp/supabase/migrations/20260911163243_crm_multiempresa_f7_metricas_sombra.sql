-- F7 MULTIEMPRESA (distinta del antiguo reporte F7 de altas): lectura en sombra.
-- No reemplaza ningún núcleo, cierre firmado, fuente económica ni puerta F4-F6.
-- Instalar en una transacción. La bandera nace apagada.
do $preflight$
declare r record;
begin
  -- Huellas leídas de producción y ensayadas en la copia sintética. Si otro
  -- trabajo cambia un lector, revisar su contrato antes de instalar F7.
  for r in select * from (values
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])','c9e58c1da9dd7a5d52991c9e47dc19d5'),
    ('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)','8a2549dbfa59c732da04900ed90b6361'),
    ('private.cartera_f5_fuentes()','94fa33cfcca657f70a1a94f98c3bf482'),
    ('private.peso_referido_conversion(date)','3a80775b21767839e524880d419689f3')
  ) as base(firma,huella) loop
    if to_regprocedure(r.firma) is null
      or md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'La base cambió: revisar % antes de instalar F7',r.firma;
    end if;
  end loop;
end;
$preflight$;

insert into crm.multiempresa_flags(nombre,activo,descripcion)
values ('metricas_multiempresa_sombra',false,'F7: informe de Gerencia por empresa, solo lectura en sombra');

-- SECURITY DEFINER necesario: las relaciones privadas están cerradas por RLS.
-- La admisión depende de membresía VIGENTE; ni claims de usuario ni rol Portal
-- convierten a Directorio/Superadmin en Gerencia de cooperativas.
create function private.metricas_f7_autorizada()
returns boolean language sql stable security definer set search_path=''
as $f$
  select auth.uid() is not null and exists (
    select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.perfil_id=auth.uid() and e.activo and p.activo and e.rol_crm='gerencia'
  );
$f$;

create function crm.metricas_multiempresa_estado_fn()
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
begin
  if not private.metricas_f7_autorizada() then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  return jsonb_build_object('version',1,'habilitada',coalesce((
    select activo from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra'
  ),false));
end;
$f$;

-- Una fila por fuente: solo el núcleo aporta dinero/atribución/imputación.
-- El lector F5 aporta la identidad canónica y su señal de contradicción.
-- Ambos lectores siguen operativos aunque las escrituras F4/F5 estén OFF.
create function private.metricas_f7_fuentes()
returns table (
  fuente_tipo text,fuente_id uuid,empresa text,moneda text,capital numeric,
  fecha_imputacion date,fecha_comercial date,creado_en timestamptz,vence_en date,
  estado text,analista_id uuid,inversion_id uuid,inversionista_id uuid,
  identidad_coherente boolean,tipo_capital text,identidad_estado text
)
language sql stable security definer set search_path=''
as $f$
  select case when e.contrato_id is not null then 'contrato' else 'cierre' end,
    coalesce(e.contrato_id,e.cierre_externo_id),
    case when e.contrato_id is not null then 'avance' else ce.cooperativa end,
    e.moneda,e.monto,(e.fecha at time zone 'America/Lima')::date,
    f.fecha_comercial,f.creado_en,e.fecha_vencimiento,e.estado,e.analista_id,
    f.inversion_id,case when f.identidad_coherente then f.inversionista_id end,
    coalesce(f.identidad_coherente,false),e.tipo,
    case when f.identidad_coherente is true then 'coherente'
      when f.identidad_coherente is false then 'contradictoria' else 'ausente' end
  from private.capital_episodios('-infinity','infinity',true,'{}') e
  left join crm.cierres_externos ce on ce.id=e.cierre_externo_id
  left join private.cartera_f5_fuentes() f
    on f.fuente_id=coalesce(e.contrato_id,e.cierre_externo_id)
    and f.empresa=case when e.contrato_id is not null then 'avance' else ce.cooperativa end
  where e.medida='stock' and not coalesce(f.es_demo,false);
$f$;

create function crm.metricas_multiempresa_fn(p_mes date default null)
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
declare
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
  v_mes date := date_trunc('month',coalesce(p_mes,v_hoy))::date;
  v_hasta date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_payload jsonb;
begin
  if not private.metricas_f7_autorizada() then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if not coalesce((select activo from crm.multiempresa_flags
    where nombre='metricas_multiempresa_sombra'),false) then
    raise exception 'El informe multiempresa está en preparación' using errcode='P0409';
  end if;
  if not isfinite(v_mes) or v_mes>v_hoy or v_mes<date '2000-01-01' then
    raise exception 'Mes inválido' using errcode='22023';
  end if;
  v_hasta:=least(v_hoy,(v_mes+interval '1 month'-interval '1 day')::date);
  v_ini:=v_mes::timestamp at time zone 'America/Lima';
  v_fin:=(v_hasta+1)::timestamp at time zone 'America/Lima';
  v_factor:=private.peso_referido_conversion(v_mes);

  with fuentes as materialized (
    select * from private.metricas_f7_fuentes() where fecha_imputacion<=v_hoy
  ), ordenadas as (
    -- Ordenar sobre la propia fila evita multiplicarla con otro join.
    select f.*,case when inversionista_id is not null then row_number() over (
      partition by inversionista_id
      order by fecha_comercial nulls last,creado_en nulls last,empresa,fuente_id
    ) end as orden from fuentes f
  ), mes as materialized (
    select * from ordenadas where fecha_imputacion between v_mes and v_hasta
  ), produccion as materialized (
    select empresa,moneda,count(*) as operaciones,sum(capital) as capital,
      count(*) filter(where orden=1) as primeras,
      count(*) filter(where orden>1) as posteriores,
      count(*) filter(where orden is null) as sin_identidad
    from mes group by empresa,moneda
  ), tipos as (
    select empresa,moneda,tipo_capital,count(*) as operaciones,sum(capital) as capital
    from mes group by empresa,moneda,tipo_capital
  ), atribucion as materialized (
    select m.empresa,m.moneda,m.analista_id,p.nombre_completo as analista_nombre,
      count(*) as operaciones,sum(m.capital) as capital
    from mes m left join public.perfiles p on p.id=m.analista_id
    group by m.empresa,m.moneda,m.analista_id,p.nombre_completo
  ), participantes as materialized (
    select distinct empresa,inversionista_id from fuentes where inversionista_id is not null
    union
    select distinct f.empresa,private.inversionista_canonica(t.inversionista_id)
    from fuentes f join crm.inversion_titulares t on t.inversion_id=f.inversion_id
    where f.identidad_coherente and t.rol='cotitular'
  ), personas as materialized (
    select inversionista_id,count(*) as empresas
    from participantes where inversionista_id is not null group by inversionista_id
  ), capital_nucleo as (
    select case when e.contrato_id is not null then 'avance' else ce.cooperativa end as empresa,
      e.moneda,sum(e.monto) as capital,count(*) as operaciones
    from private.capital_episodios(v_ini,v_fin,true,'{}') e
    left join crm.cierres_externos ce on ce.id=e.cierre_externo_id
    where e.medida='stock' group by 1,2
  ), conciliacion as (
    select coalesce(n.empresa,p.empresa) as empresa,coalesce(n.moneda,p.moneda) as moneda,
      coalesce(n.capital,0) as capital_nucleo,coalesce(p.capital,0) as capital_informe,
      coalesce(n.operaciones,0) as operaciones_nucleo,coalesce(p.operaciones,0) as operaciones_informe,
      coalesce(p.capital,0)-coalesce(n.capital,0) as diferencia_capital,
      coalesce(p.operaciones,0)-coalesce(n.operaciones,0) as diferencia_operaciones,
      coalesce((select sum(a.capital) from atribucion a
        where a.empresa=coalesce(n.empresa,p.empresa) and a.moneda=coalesce(n.moneda,p.moneda)),0)
        -coalesce(n.capital,0) as diferencia_atribucion
    from capital_nucleo n full join produccion p using(empresa,moneda)
  ), conversion as materialized (
    select * from private.conversion_episodios(v_ini,v_fin,v_mes,true,'{}',v_factor)
  ), vencimientos as (
    select empresa,moneda,count(*) as operaciones,sum(capital) as capital
    from fuentes where vence_en between v_hoy and v_hoy+30
      and ((fuente_tipo='contrato' and estado='activo') or (fuente_tipo='cierre' and estado='vigente'))
    group by empresa,moneda
  ), oportunidades as (
    select e.clave as empresa,count(p.inversionista_id) as personas
    from crm.empresas e left join personas p on not exists (
      select 1 from participantes v where v.inversionista_id=p.inversionista_id and v.empresa=e.clave
    ) and exists(select 1 from crm.inversionistas i
      where i.id=p.inversionista_id and i.estado='activo' and not i.no_contactar
        and not exists(select 1 from crm.leads l
          where l.id in (select private.leads_de_persona_veto(i.id)) and l.no_contactar))
    where e.activa group by e.clave
  )
  select jsonb_build_object(
    'version',1,'modo','sombra','mes',v_mes,'hasta',v_hasta,'hoy',v_hoy,
    'generado_en',statement_timestamp(),'habilitada',true,
    'mes_sellado',exists(select 1 from crm.periodos_cerrados where periodo=v_mes),
    'produccion',coalesce((select jsonb_agg(p order by empresa,moneda) from produccion p),'[]'::jsonb),
    'tipos_capital',coalesce((select jsonb_agg(t order by empresa,moneda,tipo_capital) from tipos t),'[]'::jsonb),
    'atribucion',coalesce((select jsonb_agg(a order by empresa,moneda,analista_nombre nulls last,analista_id) from atribucion a),'[]'::jsonb),
    'personas',jsonb_build_object(
      'total',(select count(*) from personas),
      'una_empresa',(select count(*) from personas where empresas=1),
      'dos_empresas',(select count(*) from personas where empresas=2),
      'tres_empresas',(select count(*) from personas where empresas>=3),
      'por_empresa',coalesce((select jsonb_agg(x order by empresa) from (
        select empresa,count(*) as personas from participantes where inversionista_id is not null group by empresa
      ) x),'[]'::jsonb),
      'fuentes_sin_identidad',(select count(*) from fuentes where inversionista_id is null),
      'fuentes_coherentes',(select count(*) from fuentes where identidad_estado='coherente'),
      'fuentes_contradictorias',(select count(*) from fuentes where identidad_estado='contradictoria'),
      'fuentes_sin_enlace',(select count(*) from fuentes where identidad_estado='ausente')
    ),
    'conversion',(
      select jsonb_build_object('factor_referido',v_factor,'divisor',coalesce(sum(aporte_divisor),0),
        'numerador',coalesce(sum(aporte_numerador),0),
        'tasa_pct',case when sum(aporte_divisor)>0 then round(100*sum(aporte_numerador)/sum(aporte_divisor),2) end,
        'cierres',count(*) filter(where tipo='cierre' and aporte_numerador>0),
        'renovaciones',count(*) filter(where tipo='operacion' and categoria='renovacion'),
        'upgrades',count(*) filter(where tipo='operacion' and categoria='upgrade'),
        'anulados',count(*) filter(where tipo='cierre' and anulado)) from conversion
    ),
    'vencimientos',coalesce((select jsonb_agg(v order by empresa,moneda) from vencimientos v),'[]'::jsonb),
    'oportunidades',coalesce((select jsonb_agg(o order by empresa) from oportunidades o),'[]'::jsonb),
    'conciliacion',coalesce((select jsonb_agg(c order by empresa,moneda) from conciliacion c),'[]'::jsonb),
    'fuentes_duplicadas',(select count(*) from (
      select fuente_tipo,fuente_id from fuentes group by fuente_tipo,fuente_id having count(*)>1
    ) d)
  ) into v_payload;
  return v_payload;
end;
$f$;

alter function private.metricas_f7_autorizada() owner to postgres;
alter function private.metricas_f7_fuentes() owner to postgres;
alter function crm.metricas_multiempresa_estado_fn() owner to postgres;
alter function crm.metricas_multiempresa_fn(date) owner to postgres;
revoke all on function private.metricas_f7_autorizada() from public,anon,authenticated,service_role;
revoke all on function private.metricas_f7_fuentes() from public,anon,authenticated,service_role;
revoke all on function crm.metricas_multiempresa_estado_fn() from public,anon,authenticated,service_role;
revoke all on function crm.metricas_multiempresa_fn(date) from public,anon,authenticated,service_role;
grant execute on function crm.metricas_multiempresa_estado_fn() to authenticated;
grant execute on function crm.metricas_multiempresa_fn(date) to authenticated;

comment on function crm.metricas_multiempresa_fn(date) is
  'F7: lectura mensual en sombra de Gerencia. Dinero y atribución del núcleo; identidad neutral sin multiplicar fuentes. No sustituye ni reescribe fotos selladas. Comisiones externas.';

do $postflight$
declare v_oid regprocedure;
begin
  foreach v_oid in array array['private.metricas_f7_autorizada()'::regprocedure,
    'private.metricas_f7_fuentes()'::regprocedure,'crm.metricas_multiempresa_estado_fn()'::regprocedure,
    'crm.metricas_multiempresa_fn(date)'::regprocedure] loop
    if exists(select 1 from pg_proc p where p.oid=v_oid
      and (not p.prosecdef or p.provolatile<>'s' or p.proowner<>'postgres'::regrole
        or p.proconfig is distinct from array['search_path=""'])) then
      raise exception 'Función F7 sin endurecimiento: %',v_oid;
    end if;
    if exists(select 1 from pg_proc p,
      lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where p.oid=v_oid and a.grantee=0) then
      raise exception 'Función F7 accesible a PUBLIC: %',v_oid;
    end if;
  end loop;
  if (select activo from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra') then
    raise exception 'F7 debe instalarse apagada';
  end if;
end;
$postflight$;
