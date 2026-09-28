-- Banco sintético de componentes, en una BD vacía dedicada, nunca producción.
-- El runner compila el lector anterior real y aplica el mismo bloque de cambio.
begin;
create schema crm;
create schema private;
create function private.test_id(n integer) returns uuid language sql immutable as
$$ select ('00000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid $$;
create table private.test_capital (
  tipo text, medida text, contrato_id uuid, cliente_id uuid, lead_id uuid,
  cierre_externo_id uuid, categoria text, moneda text, monto numeric,
  registrado_por uuid, analista_id uuid, fecha timestamptz
);
create function private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])
returns setof private.test_capital language sql stable as
$$ select * from private.test_capital where fecha >= $1 and fecha < $2 $$;
create table crm.leads(id uuid,contrato_id uuid,perfil_id uuid,vendedor_id uuid,origen text,creado_en timestamptz);
create table crm.operaciones_cartera(contrato_nuevo_id uuid,cliente_id uuid,moneda text,fecha_operacion date,tipo text);
create table crm.metas_vendedor(meta_periodo_id uuid,vendedor_id uuid);
create table crm.equipo(perfil_id uuid,rol_crm text);
create table crm.conversion_acreditaciones(fuente_tipo text,fuente_id uuid,origen text,fecha_comercial date,periodo_comercial date,estado text);
create table crm.conversion_politica(activada_en timestamptz);
create table private.test_excluidos(id uuid);
create function private.conversion_exclusion_fuente(text,uuid) returns text language sql stable as
$$ select case when exists(select 1 from private.test_excluidos where id=$2) then 'excluida' else 'elegible' end $$;
insert into crm.conversion_politica values(now());
insert into private.test_capital
select 'contrato_nuevo','stock',private.test_id(n),private.test_id(n+100),null,null,
  case when n=8 then 'upgrade' else 'nuevo' end,
  case when n=2 then 'USD' else 'PEN' end,
  n * 1000.01,private.test_id(1000),private.test_id(1000),
  case when n=1 then timestamptz '2026-09-10 15:30-05'
    when n=2 then timestamptz '2026-09-10 23:30-05'
    else timestamptz '2026-09-10 00:00-05' end
from generate_series(1,13) n;
-- 1 y 2: canales acreditados pese al lead cargado después del cierre.
-- 3: fuera de plazo; 4: fecha distinta; 5: conflicto de canales acreditados.
-- 6: canal directo existente; 7: directo ambiguo; 8: categoría upgrade.
-- 9: cartera legada; 10: fuente excluida; 11: nunca acreditada.
-- 12: cliente anterior válido; 13: cliente anterior ambiguo.
insert into crm.conversion_acreditaciones
select 'contrato',private.test_id(n),case when n=1 then 'formulario' else 'referido' end,
  case when n=4 then date '2026-09-09' else date '2026-09-10' end,date '2026-09-01',
  case when n=3 then 'fuera_de_plazo' else 'acreditada' end
from generate_series(1,13) n where n<>11;
insert into crm.conversion_acreditaciones values('contrato',private.test_id(5),'landing','2026-09-10','2026-09-01','acreditada');
insert into crm.leads
select private.test_id(200+n),null,private.test_id(n+100),private.test_id(1000),
  case when n=1 then 'formulario' else 'referido' end,'2026-09-23 00:00-05'
from generate_series(1,2) n;
insert into crm.leads values
  (private.test_id(206),private.test_id(6),null,private.test_id(1000),'oficina','2026-09-01'),
  (private.test_id(207),private.test_id(7),null,private.test_id(1000),'oficina','2026-09-01'),
  (private.test_id(208),private.test_id(7),null,private.test_id(1000),'landing','2026-09-01'),
  (private.test_id(212),null,private.test_id(112),private.test_id(1000),'landing','2026-09-01'),
  (private.test_id(213),null,private.test_id(113),private.test_id(1000),'landing','2026-09-01'),
  (private.test_id(214),null,private.test_id(113),private.test_id(1000),'oficina','2026-09-01');
insert into crm.operaciones_cartera values(private.test_id(9),private.test_id(109),'PEN','2026-09-10','upgrade');
insert into private.test_excluidos values(private.test_id(10));
