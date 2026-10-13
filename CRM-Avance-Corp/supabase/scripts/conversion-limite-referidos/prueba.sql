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
select pg_temp.cierre(null,'referido','2026-11-01',1);
select pg_temp.cierre(null,'referido','2026-11-01',2);
select pg_temp.exigir(pg_temp.aporte(null,'2026-11-01','2026-12-01')=0.30,'09 sin analista comparte su propio límite');

-- Un referido anulado sale de la base y un cierre de otro origen no la altera.
insert into anulados select lead_id from mundo where analista='a0000000-0000-4000-8000-00000000000a' and mes='2026-10-01' and dia=14;
select pg_temp.exigir(pg_temp.aporte('a0000000-0000-4000-8000-00000000000a')=10.45,'10 anulación de referido reduce base a tres');
delete from anulados;
insert into excluidos select ca.fuente_id from crm.conversion_acreditaciones ca join mundo m using(lead_id)
where m.analista='a0000000-0000-4000-8000-00000000000a' and m.mes='2026-10-01' and m.dia=14;
select pg_temp.exigir(pg_temp.aporte('a0000000-0000-4000-8000-00000000000a')=10.45,'11 fuente retirada no aumenta límite');
delete from excluidos;

-- Cien llegadas automáticas asignadas al analista. Otros canales no aumentan divisor.
do $$ declare a uuid:='a0000000-0000-4000-8000-00000000000a'; l uuid; i int;
begin
  for i in 1..104 loop
    l:=pg_temp.cierre(a,case when i<=100 then 'landing' else 'referido' end,'2026-12-01',1);
    update crm.leads set creado_en='2026-10-05 10:00 America/Lima' where id=l;
  end loop;
end $$;
select pg_temp.exigir((select sum(e.aporte_divisor) from private.conversion_episodios(
  '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima','2026-10-01',false,
  array['a0000000-0000-4000-8000-00000000000a'::uuid],1) e)=100,'12 divisor solo cien automáticos');
select pg_temp.exigir((select round(100*sum(e.aporte_numerador)/sum(e.aporte_divisor),2) from private.conversion_episodios(
  '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima','2026-10-01',false,
  array['a0000000-0000-4000-8000-00000000000a'::uuid],1) e)=10.60,'13 fórmula completa 10,60 %');
select pg_temp.exigir(private.peso_renovacion_conversion('2026-10-01')=0,'14 renovaciones permanecen cero');

-- El mes comercial manda incluso si el ledger y la confirmación cruzan a noviembre.
create temp table borde as select pg_temp.cierre('c0000000-0000-4000-8000-00000000000c','referido','2026-10-01',31) lead_id;
update crm.leads set convertido_en='2026-11-01 01:00 America/Lima' where id=(select lead_id from borde);
update crm.lead_asignaciones set resultado_en='2026-11-01 01:00 America/Lima',finalizado_en='2026-11-01 01:00 America/Lima'
where lead_id=(select lead_id from borde);
update crm.conversion_acreditaciones set confirmado_en='2026-11-01 01:00 America/Lima',
 vinculado_en='2026-11-01 01:00 America/Lima',acreditado_en='2026-11-01 01:00 America/Lima' where lead_id=(select lead_id from borde);
select pg_temp.exigir(pg_temp.aporte('c0000000-0000-4000-8000-00000000000c')=0.15,'22 borde Lima: fecha comercial octubre, confirmación noviembre');
do $$ begin
  begin
    update crm.conversion_acreditaciones set periodo_comercial='2026-11-01',plazo_hasta=private.conversion_plazo_hasta('2026-11-01')
    where lead_id=(select lead_id from borde);
    raise exception 'Debió rechazar mes comercial discordante';
  exception when check_violation then
    perform pg_temp.exigir(true,'23 CHECK impide mes distinto de fecha comercial');
  end;
end $$;
create temp table invalido as select pg_temp.cierre('c0000000-0000-4000-8000-00000000000c','referido','2026-10-01',30) lead_id;
update crm.conversion_acreditaciones set estado='fuente_demo' where lead_id=(select lead_id from invalido);

-- Se prueba el trigger real del sello mediante la fila sintética de octubre.
-- No se afirma que cerrar_periodo permita sellar el mes en curso.
set local session_replication_role=origin;
insert into crm.periodos_cerrados(periodo,ponderacion_referido,ponderacion_renovacion,tope_referidos_pct,meta_revision,cobertura,automatico)
values('2026-10-01',1,0,15,1,'{}',true);
select pg_temp.exigir((select sum(ca.ajuste_anulacion_en_sello) from crm.conversion_acreditaciones ca
  where ca.analista_id='a0000000-0000-4000-8000-00000000000a' and ca.periodo_comercial='2026-10-01')=10.60,'15 sello conserva aporte exacto');
select pg_temp.exigir((select ca.ajuste_anulacion_en_sello from crm.conversion_acreditaciones ca join mundo m using(lead_id)
  where m.analista='a0000000-0000-4000-8000-00000000000a' and m.mes='2026-10-01' and m.dia=11)=0.15,'16 referido parcial congela descuento marginal 0,15');
select pg_temp.exigir((select count(*) from crm.conversion_acreditaciones ca join mundo m using(lead_id)
  where m.analista='a0000000-0000-4000-8000-00000000000a' and m.mes='2026-10-01' and m.origen='referido' and ca.incluida_en_sello)=4,'17 todos los referidos válidos sostienen el límite sellado');
set local session_replication_role=replica;
create temp table ajustes(caso text,id uuid);
insert into ajustes select 'parcial',private.registrar_ajuste_si_mes_cerrado(
  (select lead_id from mundo where analista='a0000000-0000-4000-8000-00000000000a' and mes='2026-10-01' and dia=11),'prueba parcial','a0000000-0000-4000-8000-00000000000a');
insert into ajustes select 'exceso',private.registrar_ajuste_si_mes_cerrado(
  (select lead_id from mundo where analista='a0000000-0000-4000-8000-00000000000a' and mes='2026-10-01' and dia=14),'prueba exceso','a0000000-0000-4000-8000-00000000000a');
select pg_temp.exigir((select j.numerador from crm.ajustes_mes_cerrado j join ajustes a on j.id=a.id where a.caso='parcial')=0.15,'18 anulación del admitido descuenta reducción de límite 0,15');
select pg_temp.exigir((select j.numerador from crm.ajustes_mes_cerrado j join ajustes a on j.id=a.id where a.caso='exceso')=0.15,'19 referido fuera de admisión también descuenta reducción de límite 0,15');
select pg_temp.exigir(not has_column_privilege('authenticated','crm.conversion_acreditaciones','ajuste_anulacion_en_sello','SELECT'),'20 dato sellado sin lectura directa');
select pg_temp.exigir(not has_function_privilege('authenticated','private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)','EXECUTE'),'21 núcleo sin ejecución directa');
-- Cuatro anulaciones sucesivas descuentan en total 0,60, sin depender del orden.
select pg_temp.exigir((select private.registrar_ajuste_si_mes_cerrado(
  (select lead_id from mundo where analista='a0000000-0000-4000-8000-00000000000a' and mes='2026-10-01' and dia=11),
  'intento repetido','a0000000-0000-4000-8000-00000000000a')) is null,'24 anulación repetida no duplica deuda');
update crm.conversion_pesos set tope_referidos_pct=20 where vigente_desde='2026-10-01';
select private.registrar_ajuste_si_mes_cerrado(lead_id,'anulación sucesiva','a0000000-0000-4000-8000-00000000000a')
from mundo where analista='a0000000-0000-4000-8000-00000000000a' and mes='2026-10-01' and dia in(12,13) and origen='referido';
select pg_temp.exigir((select count(*)=4 and sum(numerador)=0.60 and bool_and(numerador=0.15)
 from crm.ajustes_mes_cerrado where vendedor_id='a0000000-0000-4000-8000-00000000000a') ,
 '25 cuatro anulaciones = 0,60, incluso si cambia porcentaje después del sello');
update crm.conversion_pesos set tope_referidos_pct=15 where vigente_desde='2026-10-01';
insert into ajustes select 'borde',private.registrar_ajuste_si_mes_cerrado((select lead_id from borde),'anular borde','c0000000-0000-4000-8000-00000000000c');
select pg_temp.exigir((select j.numerador=0.15 and j.periodo_origen='2026-10-01' from crm.ajustes_mes_cerrado j join ajustes a on a.id=j.id where a.caso='borde'),
 '26 borde: deuda de octubre aunque el ledger y convertido_en sean noviembre');
select pg_temp.exigir((select ajuste_anulacion_en_sello=0 and not incluida_en_sello from crm.conversion_acreditaciones where lead_id=(select lead_id from invalido)),
 '27 cierre no acreditado queda fuera del sello');
select pg_temp.exigir(not has_column_privilege('anon','crm.conversion_acreditaciones','ajuste_anulacion_en_sello','SELECT'),'28 anon tampoco lee descuento congelado');
select count(*) as comprobaciones,'PASS' as resultado from comprobaciones;
rollback;
