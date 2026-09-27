-- Diferencias entre dos fotos del medidor (SOLO banco). Uso: psql -v a=E0 -v b=E1 -f diferencias.sql
-- Aplana cada resultado jsonb a (ruta, valor) y lista lo que cambió, sin marcas de tiempo del payload.
\set ON_ERROR_STOP 1
create schema if not exists ensayo;
create or replace function ensayo.aplanar(j jsonb) returns table(ruta text, valor text)
language sql immutable as $f$
  with recursive r(ruta, v) as (
    select ''::text, j
    union all
    select r.ruta || k.sub, k.val
    from r cross join lateral (
      select '.' || e.clave as sub, e.contenido as val
        from jsonb_each(case when jsonb_typeof(r.v) = 'object' then r.v else '{}'::jsonb end) e(clave, contenido)
      union all
      select '[' || (a.ord - 1) || ']', a.contenido
        from jsonb_array_elements(case when jsonb_typeof(r.v) = 'array' then r.v else '[]'::jsonb end)
             with ordinality a(contenido, ord)
    ) k
  )
  select ruta, v::text from r where jsonb_typeof(v) not in ('object', 'array')
$f$;
drop table if exists ensayo.dif;
create table ensayo.dif as
with x as (select f.actor, f.rpc, f.ok, t.ruta, t.valor from ensayo.foto f
           left join lateral ensayo.aplanar(f.resultado) t on true where f.etapa = :'a'),
     y as (select f.actor, f.rpc, f.ok, t.ruta, t.valor from ensayo.foto f
           left join lateral ensayo.aplanar(f.resultado) t on true where f.etapa = :'b')
select coalesce(x.actor, y.actor) actor, coalesce(x.rpc, y.rpc) rpc, coalesce(x.ruta, y.ruta) ruta,
       x.ok ok_a, y.ok ok_b, x.valor antes, y.valor despues
from x full join y on x.actor = y.actor and x.rpc = y.rpc and x.ruta is not distinct from y.ruta
where (x.valor is distinct from y.valor or x.ok is distinct from y.ok)
  and coalesce(x.ruta, y.ruta, '') !~ '\.(generado_en|ahora|calculado_en|consultado_en|hora_servidor)$';
select :'a' || ' → ' || :'b' as comparacion, count(*) as diferencias,
       count(distinct actor || rpc) as llamadas_afectadas from ensayo.dif;
select actor, rpc, count(*) n from ensayo.dif group by 1, 2 order by 2, 1;
