-- SOLO LECTURA, datos sintéticos (VALUES): el cálculo viejo (canónica igual, recorriendo a todas) y el nuevo (familia +
-- mismo predicado) deben dar el mismo array para CADA persona. Casos: cadena de 17 (supera el tope 16), ciclo A<->B,
-- padre inexistente, perfil repetido en dos personas, persona sin perfil, singleton. La función inversionista_canonica
-- se replica tal cual (tope n<16 y coalesce(..., p_id)).
with recursive personas(id, padre, perfil) as (values
  -- cadena c00 (raíz) <- c01 <- ... <- c16 (17 nodos; c16 está a 16 saltos de la raíz)
  ('c00', null, 'P-c00'), ('c01','c00','P-c01'), ('c02','c01',null), ('c03','c02','P-c03'), ('c04','c03',null),
  ('c05','c04','P-c05'), ('c06','c05',null), ('c07','c06','P-c07'), ('c08','c07',null), ('c09','c08','P-c09'),
  ('c10','c09',null), ('c11','c10','P-c11'), ('c12','c11',null), ('c13','c12','P-c13'), ('c14','c13',null),
  ('c15','c14','P-c15'), ('c16','c15','P-c16'),
  ('a', 'b', 'P-a'), ('b', 'a', 'P-b'),            -- ciclo
  ('rota', 'no-existe', 'P-rota'),                 -- padre inexistente
  ('d1', null, 'P-dup'), ('d2', 'd1', 'P-dup'),    -- perfil repetido en la familia
  ('s', null, 'P-s'), ('sinperfil', 's', null)),
canon as (  -- réplica de private.inversionista_canonica para cada persona
  select p.id, (with recursive c as (
      select i.id, i.padre, 1 as n from personas i where i.id = p.id
      union all select i.id, i.padre, c.n+1 from c join personas i on i.id = c.padre where c.n < 16)
    select coalesce((select c.id from c where c.padre is null order by c.n desc limit 1), p.id)) as v
  from personas p),
viejo as (
  select x.id, array(select i.perfil from personas i join canon ci on ci.id=i.id join canon cx on cx.id=x.id
                     where i.perfil is not null and ci.v = cx.v order by i.perfil) v
  from personas x),
nuevo as (
  select x.id, (with recursive familia as (
      select i.id, 1 as n from personas i where i.id = (select v from canon where id = x.id)
      union all select i.id, f.n+1 from personas i join familia f on i.padre = f.id where f.n < 16)
    select array(select i.perfil from personas i join canon ci on ci.id=i.id join canon cx on cx.id=x.id
                 where i.id in (select f.id from familia f) and i.perfil is not null and ci.v = cx.v order by i.perfil)) v
  from personas x)
select json_build_object(
  'personas', (select count(*) from personas),
  'distintas', (select count(*) from viejo o join nuevo n using (id) where o.v is distinct from n.v),
  'muestra', (select json_agg(json_build_array(o.id, o.v, n.v) order by o.id) from viejo o join nuevo n using (id) where o.id in ('c00','c16','a','b','rota','d2','sinperfil','c15'))
)::text v;
