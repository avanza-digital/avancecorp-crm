-- Volumen mayor que agosto/septiembre productivos (155/119 contratos), sin PII.
begin;
set local timezone='America/Lima';
set local statement_timeout='25s';
do $$ begin if (select count(*) from crm.leads)<>2048 then raise exception 'Banco incorrecto';end if;end $$;
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,fecha_vencimiento,fecha_cierre_comercial,categoria,analista_cierre_id,creado_por,producto_condicion_id)
select md5('ranking-carga-'||i)::uuid,'RANKING-CARGA-'||i,'b0000000-0000-4000-8000-000000000007',1000.37,'PEN','anual',
'2026-08-15','2027-08-15','2026-08-15','nuevo',('b0000000-0000-4000-8000-'||lpad((8+i%32)::text,12,'0'))::uuid,
'b0000000-0000-4000-8000-000000000003',md5('ranking-condicion')::uuid from generate_series(1,256) i;
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
do $$ declare t timestamptz:=clock_timestamp();j jsonb;begin
j:=crm.cerrar_periodo('2026-08-01');
if (j->>'vendedores')::int<>34 then raise exception 'Cierre incompleto';end if;
raise notice 'PASS carga: 272 contratos del mes, 2048 leads, 34 vendedores: % ms',extract(epoch from clock_timestamp()-t)*1000;
end $$;
reset role;
do $$ begin
if exists(select 1 from crm.cierre_mes_vendedor where (origenes_ranking->>'disponible')::boolean is distinct from true) then raise exception 'Carga con fotos degradadas';end if;
raise notice 'PASS carga: 34 fotos disponibles, cero degradadas';
end $$;
rollback;
