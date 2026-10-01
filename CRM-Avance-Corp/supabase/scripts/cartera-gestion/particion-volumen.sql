-- FRAGMENTO (sin transacción propia): la llamada del Pipeline (`p_etapa = 'nuevo'`) contra un
-- oráculo INDEPENDIENTE, sobre los 5 000 leads de `volumen.sql`. Lo compone `ensayar.mjs`.
--
-- El resultado esperado NO sale de la función ni repite su predicado: lo calcula `postgres`
-- leyendo las tablas (sin RLS) con otra formulación —el ÚLTIMO contacto NO deshecho del lead
-- frente a su tenencia— y con el alcance de cada actor escrito a mano. Después la función se recorre
-- entera por cursor (páginas de 200, con sellos repetidos) como cada actor, y se comparan los
-- conjuntos: ni una fila de más, ni una de menos, ni una repetida, y el total estable.
set local session_replication_role = origin;
set local statement_timeout = 0;

create temporary table esperado on commit drop as
with contacto as (
  select a.lead_id,
    max(a.creado_en) filter (where not (a.metadata ? 'deshecho_en')) as ultimo_vigente,
    max(a.creado_en) as ultimo_cualquiera
  from crm.actividades a
  where a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
  group by a.lead_id
), nuevos as (
  select l.id, l.vendedor_id, l.asignado_supervisor_id,
    coalesce(l.vendedor_id is not null and c.ultimo_vigente >= l.tenencia_desde, false) as gestionado,
    -- Para la no vacuidad: leads que serían «Gestionado» si lo deshecho contara.
    coalesce(l.vendedor_id is not null and c.ultimo_cualquiera >= l.tenencia_desde, false) as gestionado_si_lo_deshecho_contara
  from crm.leads l left join contacto c on c.lead_id = l.id
  where l.activo and l.etapa = 'nuevo'
), alcance(actor, ve) as (
  -- gerencia y directorio: todo · supervisor 11: sus analistas (101, 105, 109, 113, 117) y su
  -- bandeja · analista 101: lo suyo · coordinador: nada (la RLS de leads no le abre ninguno).
  select 1, n.id from nuevos n
  union all select 2, n.id from nuevos n
  union all select 11, n.id from nuevos n
    where n.vendedor_id in (select e.perfil_id from crm.equipo e where e.supervisor_id = pg_temp.vactor(11))
       or (n.vendedor_id is null and n.asignado_supervisor_id = pg_temp.vactor(11))
  union all select 101, n.id from nuevos n where n.vendedor_id = pg_temp.vactor(101)
)
select a.actor, case when n.gestionado then 'con_gestion' else 'sin_gestion' end as mitad, n.id,
  (n.gestionado_si_lo_deshecho_contara and not n.gestionado) as solo_deshecho
from alcance a join nuevos n on n.id = a.ve;
create temporary table recorrido (actor integer, mitad text, id uuid, pagina integer) on commit drop;
create temporary table totales_vistos (actor integer, mitad text, vivos integer) on commit drop;
-- `esperado` no se le abre a `authenticated`: el oráculo no puede contaminar lo que mide.
grant select, insert on recorrido, totales_vistos to authenticated;

set local role authenticated;
do $recorrer$
declare
  a integer; m text; p jsonb; fila jsonb; cursor_fecha timestamptz; cursor_id uuid; pagina integer;
begin
  foreach a in array array[1, 2, 3, 11, 101] loop
    perform set_config('request.jwt.claim.sub', pg_temp.vactor(a)::text, true),
            set_config('request.jwt.claims', json_build_object('sub', pg_temp.vactor(a), 'role', 'authenticated')::text, true);
    foreach m in array array['con_gestion', 'sin_gestion'] loop
      cursor_fecha := null; cursor_id := null; pagina := 0;
      loop
        p := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => m,
          p_antes_de => cursor_fecha, p_antes_id => cursor_id);
        insert into pg_temp.totales_vistos values (a, m, (p #>> '{resumen,totales,vivos}')::integer);
        exit when jsonb_array_length(p -> 'items') = 0;
        pagina := pagina + 1;
        for fila in select value from jsonb_array_elements(p -> 'items') loop
          insert into pg_temp.recorrido values (a, m, (fila ->> 'id')::uuid, pagina);
          cursor_fecha := (fila ->> 'actualizado_en')::timestamptz; cursor_id := (fila ->> 'id')::uuid;
        end loop;
      end loop;
    end loop;
  end loop;
end;
$recorrer$;
reset role;

select 'PARTICION ' || jsonb_build_object(
  'por_actor', (select jsonb_agg(to_jsonb(x) order by x.actor, x.mitad) from (
    select k.actor, k.mitad,
      (select count(*) from pg_temp.esperado e where e.actor = k.actor and e.mitad = k.mitad) as esperadas,
      (select count(*) from pg_temp.recorrido r where r.actor = k.actor and r.mitad = k.mitad) as servidas,
      (select coalesce(max(r.pagina), 0) from pg_temp.recorrido r where r.actor = k.actor and r.mitad = k.mitad) as paginas,
      (select count(*) from (select r.id from pg_temp.recorrido r where r.actor = k.actor and r.mitad = k.mitad
         group by r.id having count(*) > 1) d) as repetidas,
      (select count(*) from pg_temp.esperado e where e.actor = k.actor and e.mitad = k.mitad
         and not exists (select 1 from pg_temp.recorrido r where r.actor = e.actor and r.mitad = e.mitad and r.id = e.id)) as perdidas,
      (select count(*) from pg_temp.recorrido r where r.actor = k.actor and r.mitad = k.mitad
         and not exists (select 1 from pg_temp.esperado e where e.actor = r.actor and e.mitad = r.mitad and e.id = r.id)) as de_mas,
      (select count(distinct t.vivos) from pg_temp.totales_vistos t where t.actor = k.actor and t.mitad = k.mitad) as totales_distintos,
      (select min(t.vivos) from pg_temp.totales_vistos t where t.actor = k.actor and t.mitad = k.mitad) as total_declarado
    from (select a.actor, m.mitad from unnest(array[1, 2, 3, 11, 101]) a(actor)
          cross join unnest(array['con_gestion', 'sin_gestion']) m(mitad)) k) x),
  'filas_recorridas', (select count(*) from pg_temp.recorrido),
  'decididos_por_lo_deshecho', (select count(*) from pg_temp.esperado e where e.actor = 1 and e.solo_deshecho),
  'en_las_dos_mitades', (select count(*) from pg_temp.recorrido c join pg_temp.recorrido s
     on s.actor = c.actor and s.id = c.id and s.mitad = 'sin_gestion' where c.mitad = 'con_gestion'))::text;
