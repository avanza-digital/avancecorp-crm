-- Banco propio, nunca producción. Datos sintéticos y rollback.
begin;
set local session_replication_role=replica;
set local search_path='';
create temp table comprobaciones (nombre text primary key);
create function pg_temp.exigir(p_ok boolean,p_nombre text) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'FALLA: %',p_nombre; end if;
  insert into comprobaciones values(p_nombre);
end $$;
create temp table excluidos (id uuid);
create temp table anulados (id uuid);
create or replace function private.conversion_exclusion_fuente(p_tipo text,p_id uuid) returns text
language sql stable set search_path='' as $$
select case when exists(select 1 from pg_temp.excluidos where id=p_id) then 'retirada' else 'elegible' end $$;
create or replace function private.cierre_externo_anulado(p_lead_id uuid) returns boolean
language sql stable set search_path='' as $$ select exists(select 1 from pg_temp.anulados where id=p_lead_id) $$;

create function pg_temp.cierre(p_analista uuid,p_origen text,p_mes date,p_dia int) returns uuid language plpgsql as $$
declare l uuid:=gen_random_uuid(); ep uuid; f timestamptz:=(p_mes+p_dia-1)::timestamp at time zone 'America/Lima';
begin
  insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,creado_en,etapa,convertido_en,alta_manual)
  values(l,'SINTETICO LIMITE','9'||substr(replace(l::text,'-',''),1,8),p_origen,1000,
    (p_mes-40)::timestamp at time zone 'America/Lima','convertido',f,false);
  insert into crm.lead_asignaciones(lead_id,ciclo_n,episodio_n,analista_id,motivo_apertura,asignado_en,moneda,origen,
    sla_global_iniciado_en,sla_politica_asignacion_id,primera_gestion_limite_en,primer_contacto_limite_en,
    resultado,resultado_en,finalizado_en,motivo_cierre)
  values(l,1,1,coalesce(p_analista,'f0000000-0000-4000-8000-00000000000f'::uuid),'asignado',f-interval '20 days','PEN',p_origen,f-interval '20 days',gen_random_uuid(),
    f,f,'convertido',f,f,'convertido') returning id into ep;
  insert into crm.conversion_acreditaciones(lead_id,episodio_id,analista_id,origen,fuente_tipo,fuente_id,fecha_comercial,
    confirmado_en,vinculado_en,acreditado_en,periodo_comercial,plazo_hasta,estado,politica_desde,motivo)
  values(l,ep,p_analista,p_origen,'contrato',gen_random_uuid(),p_mes+p_dia-1,f,f,f,p_mes,
    private.conversion_plazo_hasta(p_mes),'acreditada','2026-09-01','prueba sintetica del limite');
  return l;
end $$;
create function pg_temp.aporte(a uuid,ini date default '2026-10-01',fin date default '2026-11-01',global boolean default true)
returns numeric language sql as $$
select coalesce(sum(e.aporte_numerador),0) from private.conversion_episodios(
  ini::timestamp at time zone 'America/Lima',fin::timestamp at time zone 'America/Lima',null,global,array[a],1) e
where e.analista_id is not distinct from a and e.tipo<>'recibido' $$;
create temp table mundo(analista uuid,origen text,dia int,lead_id uuid,mes date);
do $$ declare a uuid:='a0000000-0000-4000-8000-00000000000a'; b uuid:='b0000000-0000-4000-8000-00000000000b'; i int; l uuid;
begin
  for i in 1..10 loop l:=pg_temp.cierre(a,'formulario','2026-10-01',i); insert into mundo values(a,'formulario',i,l,'2026-10-01'); end loop;
  for i in 1..4 loop l:=pg_temp.cierre(a,'referido','2026-10-01',10+i); insert into mundo values(a,'referido',10+i,l,'2026-10-01'); end loop;
  for i in 1..8 loop l:=pg_temp.cierre(b,'referido','2026-10-01',10+i); insert into mundo values(b,'referido',10+i,l,'2026-10-01'); end loop;
  for i in 1..4 loop l:=pg_temp.cierre(a,'referido','2026-09-01',10+i); insert into mundo values(a,'referido',10+i,l,'2026-09-01'); end loop;
end $$;
select pg_temp.exigir(pg_temp.aporte('a0000000-0000-4000-8000-00000000000a')=10.60,'01 ejemplo: 10 automáticos + 4 referidos = 10,60');
select pg_temp.exigir(pg_temp.aporte('b0000000-0000-4000-8000-00000000000b')=1.20,'02 sin automáticos: 8 referidos admiten 1,20');
select pg_temp.exigir((select array_agg(e.aporte_numerador order by e.fecha_numerador) from private.conversion_episodios(
  '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima','2026-10-01',true,'{}',1) e
  where e.analista_id='b0000000-0000-4000-8000-00000000000b' and e.tipo='cierre')=array[1,0.2,0,0,0,0,0,0]::numeric[],
  '03 límite agregado: primer cierre 1, siguiente parcial 0,20, resto 0');
select pg_temp.exigir(pg_temp.aporte('a0000000-0000-4000-8000-00000000000a','2026-10-01','2026-11-01',false)=10.60,'04 ámbito propio no altera límite');
select pg_temp.exigir(pg_temp.aporte('a0000000-0000-4000-8000-00000000000a','2026-10-12','2026-10-15')=0,'05 rango tardío no reinicia cupo');
select pg_temp.exigir(pg_temp.aporte('a0000000-0000-4000-8000-00000000000a','2026-10-01','2026-10-12')=10.60,'06 rango temprano conserva límite mensual');
select pg_temp.exigir(pg_temp.aporte('a0000000-0000-4000-8000-00000000000a','2026-09-01','2026-10-01')=0.60,'07 septiembre conserva ponderación histórica');

-- Bordes exactos: el porcentaje no se redondea hacia arriba a cierres enteros.
do $$ declare r int; a uuid; i int; esperado numeric; begin
  foreach r in array array[0,1,2,4,6,7,10,13,20] loop
    a:=gen_random_uuid(); esperado:=r*0.15;
    for i in 1..r loop perform pg_temp.cierre(a,'referido','2026-11-01',i); end loop;
    perform pg_temp.exigir(pg_temp.aporte(a,'2026-11-01','2026-12-01')=esperado,format('08 borde %s referidos = %s',r,esperado));
  end loop;
end $$;

select count(*) as comprobaciones,'PASS ORACULO EXACTO VIGENTE' as resultado from comprobaciones;rollback;
