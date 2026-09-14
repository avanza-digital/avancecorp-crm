-- Lectura administrativa F8 sin PII. No configura ni activa el piloto.
begin isolation level repeatable read read only;
set local search_path='';
set local lock_timeout='1s';
set local statement_timeout='30s';

select clock_timestamp() as corte_utc,
  current_setting('TimeZone') as zona_servidor;

select nombre,activo,actualizado_en
from crm.multiempresa_flags
where nombre in ('resolver_en_puertas','inversiones_escritura',
  'ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra')
order by nombre;

select e.rol_crm,count(*) as miembros_activos
from crm.equipo e
join public.perfiles p on p.id=e.perfil_id
where e.activo and p.activo
group by e.rol_crm
order by e.rol_crm;

with fuentes as (select * from private.cartera_f5_fuentes())
select es_demo,count(*) as fuentes,
  count(*) filter(where not coalesce(identidad_coherente,false)) as no_coherentes,
  count(*) filter(where i.id is null) as sin_persona,
  count(*) filter(where i.inversionista_canonico_id is not null) as alias_no_canonico,
  count(*) filter(where not coalesce(identidad_coherente,false) or i.id is null
    or i.inversionista_canonico_id is not null) as brechas_identidad,
  count(*) filter(where (not coalesce(identidad_coherente,false) or i.id is null
    or i.inversionista_canonico_id is not null)
    and (es_demo is not true or to_regprocedure('private.cartera_f5_fuentes_reales()') is null))
    as bloqueos_f5_f8_segun_instalacion
from fuentes f
left join crm.inversionistas i on i.id=f.inversionista_id
group by es_demo
order by es_demo;

with fuentes as (select * from private.cartera_f5_fuentes())
select empresa,count(*) filter(where not es_demo) as fuentes_reales,
  count(distinct inversionista_id) filter(where not es_demo
    and coalesce(identidad_coherente,false)) as identidades_coherentes
from fuentes
group by empresa
order by empresa;

with personas as (
  select inversionista_id,count(distinct empresa) as empresas
  from private.cartera_f5_fuentes()
  where not es_demo and coalesce(identidad_coherente,false)
    and inversionista_id is not null
  group by inversionista_id
)
select count(*) filter(where empresas>=2) as personas_multiempresa,
  count(*) filter(where empresas=3) as personas_tres_empresas
from personas;

select count(*) as inversiones_relacionales from crm.inversiones;

rollback;
