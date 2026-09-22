-- Oráculo sobre el cuerpo INSTALADO, reloj sustituido sólo en pg_temp.
-- Preparación administrativa local; todas las lecturas de producto authenticated.
begin;
set local statement_timeout = '120s';
do $$ declare fuente text; begin
  if current_database() <> 'gestion_diaria_f4_vista_chvrqh' then raise exception 'Base no autorizada'; end if;
  fuente := pg_get_functiondef('private.gestion_diaria_equipo_core(date,uuid)'::regprocedure);
  if position('statement_timestamp()' in fuente)=0 then raise exception 'Reloj no encontrado'; end if;
  fuente := replace(fuente, 'private.gestion_diaria_equipo_core(', 'pg_temp.f43_equipo(');
  execute replace(fuente, 'statement_timestamp()', 'current_setting(''f43.reloj'')::timestamptz');
  fuente := pg_get_functiondef('crm.gestion_diaria_analista_fn(date,uuid)'::regprocedure);
  if position('now()' in fuente)=0 then raise exception 'Reloj F3 no encontrado'; end if;
  fuente := replace(fuente, 'crm.gestion_diaria_analista_fn(', 'pg_temp.f43_analista(');
  execute replace(fuente, 'now()', 'current_setting(''f43.reloj'')::timestamptz');
end $$;
grant execute on function pg_temp.f43_equipo(date,uuid) to authenticated;
grant execute on function pg_temp.f43_analista(date,uuid) to authenticated;
create temporary table f43_actores as
with vendedores as (select perfil_id, supervisor_id from crm.equipo
  where private.rol_crm(perfil_id)='vendedor' and private.rol_crm(supervisor_id)='supervisor'
  order by perfil_id)
select (select perfil_id from vendedores limit 1) vendedor,
  (select supervisor_id from vendedores limit 1) supervisor,
  (select perfil_id from vendedores where supervisor_id <> (select supervisor_id from vendedores limit 1) limit 1) ajeno,
  (select supervisor_id from vendedores where supervisor_id <> (select supervisor_id from vendedores limit 1) limit 1) supervisor_ajeno,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id)='gerencia' limit 1) gerente,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id)='coordinador' limit 1) coordinador,
  (select p.id from public.perfiles p where p.activo and p.rol='directorio'
    and (not exists(select 1 from crm.equipo e where e.perfil_id=p.id)
      or private.rol_crm(p.id)='directorio') limit 1) lector,
  gen_random_uuid() lead,
  date_trunc('week', statement_timestamp() at time zone 'America/Lima')::date + 7 as lunes;
grant select on f43_actores to authenticated;
create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'F4.3: %', mensaje; end if; end $$;
select pg_temp.afirmar(vendedor is not null and supervisor is not null and ajeno is not null
  and gerente is not null and coordinador is not null and lector is not null, 'Faltan identidades de prueba') from f43_actores;

-- Semilla histórica OFF: jamás juzgar un día previo como incumplimiento.
select set_config('request.jwt.claim.sub', supervisor::text, true) from f43_actores;
set local role authenticated;
select pg_temp.afirmar(crm.gestion_diaria_equipo_fn()#>>'{cortes,estado}'='desactivados', 'Semilla no está OFF');
select pg_temp.afirmar(crm.gestion_diaria_equipo_fn()#>>'{umbrales,politica_version}'='1', 'Versión de umbrales ausente');
reset role;

-- Crear un lead ficticio por la puerta legal; no se instala un nuevo fixture permanente.
select set_config('request.jwt.claim.sub', gerente::text, true) from f43_actores;
select crm.crear_lead_si_disponible(p_nombre_completo => 'ORACULO F43 CORTES', p_telefono => '999577772',
  p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => lead,
  p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
  p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => vendedor,
  p_nota => 'Fixture reversible F43', p_telefono_alternativo => null) from f43_actores;

insert into crm.politica_gestion_diaria(version, version_anterior_id, vigente_desde, motivo, cortes_activos)
select 2, p.id, a.lunes::timestamp at time zone 'America/Lima', 'Fixture: activar próxima semana', true
from crm.politica_gestion_diaria p cross join f43_actores a where p.version=1;
insert into crm.politica_gestion_diaria(version, version_anterior_id, vigente_desde, motivo, cortes_activos,
  corte_1_minimo, corte_2_incremento_pct, corte_2_piso, bien_min_pct, atencion_min_pct)
select 3, p.id, (a.lunes+4)::timestamp at time zone 'America/Lima', 'Fixture: redondeo y contacto', true,
  4, 30, 1, 70, 50 from crm.politica_gestion_diaria p cross join f43_actores a where p.version=2;
insert into crm.politica_gestion_diaria(version, version_anterior_id, vigente_desde, motivo, cortes_activos)
select 4, p.id, (a.lunes+7)::timestamp at time zone 'America/Lima', 'Fixture: apagado futuro', false
from crm.politica_gestion_diaria p cross join f43_actores a where p.version=3;

-- Sólo fixtures de este analista; ROLLBACK restaura sus datos originales y triggers.
alter table crm.actividades disable trigger user;
update crm.actividades set creado_en='2000-01-01T15:00:00Z' where creado_por=(select vendedor from f43_actores);
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select a.lead, case when i%2=0 then 'llamada_no_contestada' else 'llamada_realizada' end,
  a.vendedor, ((a.lunes+c.dia)+c.hora) at time zone 'America/Lima',
  case when i%3=0 then '{"resultado":"numero_errado"}'::jsonb
    when i%3=1 then '{"resultado":"no_es_la_persona"}'::jsonb else '{}'::jsonb end
from f43_actores a cross join (values
  (0,time '16:00',3),(0,time '16:30',20),
  (1,time '10:00',1),(1,time '11:30',2),(1,time '12:00',2),(1,time '16:30',6),
  (2,time '10:00',8),(2,time '15:59:59',11),(2,time '16:00',1),
  (3,time '08:30',4),(3,time '10:00',16),(3,time '15:00',10),
  (4,time '10:00',8),(4,time '15:00',3),
  (5,time '10:00',1),(5,time '12:00',2),(5,time '13:00',10),
  (6,time '10:00',40)
) c(dia,hora,cantidad) cross join lateral generate_series(1,c.cantidad) i;
alter table crm.actividades enable trigger user;

select set_config('request.jwt.claim.sub', supervisor::text, true) from f43_actores;
set local role authenticated;
do $$ declare a record; caso record; foto jsonb; fila jsonb; begin
  select * into a from f43_actores;
  for caso in select * from (values
    (0,time '08:59:59','pendiente',null::integer,null::integer,false),
    (0,time '11:29:59','pendiente',null,null,false),
    (0,time '11:30','incumplido',0,8,true),
    (0,time '15:59:59','incumplido',0,8,true),
    (0,time '16:00','incumplido',0,8,true),
    (0,time '17:00','incumplido',0,8,true),
    (0,time '18:00','incumplido',0,8,false),
    (1,time '11:30','incumplido',1,8,true),
    (1,time '11:30:00.000001','recuperado',1,8,false),
    (1,time '12:00:01','recuperado',1,8,false),
    (1,time '17:00','recuperado',1,8,false),
    (2,time '16:00','cumplido',8,20,false),
    (3,time '16:00','cumplido',20,30,false),
    (4,time '16:00','cumplido',8,11,false),
    (5,time '11:30','incumplido',1,null,true),
    (5,time '12:00:01','recuperado',1,null,false),
    (5,time '13:00','recuperado',1,null,false)
  ) t(dia,hora,estado1,base,objetivo2,aviso1) loop
    perform set_config('f43.reloj', (((a.lunes+caso.dia)+caso.hora) at time zone 'America/Lima')::text, true);
    foto := pg_temp.f43_equipo(null,null);
    perform pg_temp.afirmar(jsonb_array_length(foto#>'{cortes,equipo}')=jsonb_array_length(foto->'equipo')
      and not exists(select 1 from jsonb_array_elements(foto#>'{cortes,equipo}') c where not exists(
        select 1 from jsonb_array_elements(foto->'equipo') e where e->>'analista_id'=c->>'analista_id')),
      'Los cortes no cubren el roster completo');
    select e into fila from jsonb_array_elements(foto#>'{cortes,equipo}') e where e->>'analista_id'=a.vendedor::text;
    perform pg_temp.afirmar(fila#>>'{primer_corte,estado}'=caso.estado1, 'Primer corte '||caso.dia||' '||caso.hora);
    perform pg_temp.afirmar((fila#>>'{primer_corte,base}')::integer is not distinct from caso.base, 'Base fija '||caso.dia||' '||caso.hora);
    perform pg_temp.afirmar((fila#>>'{segundo_corte,objetivo}')::integer is not distinct from caso.objetivo2, 'Piso/techo/ceil '||caso.dia);
    perform pg_temp.afirmar((fila#>>'{primer_corte,puede_avisar}')::boolean=caso.aviso1, 'Aviso fuera de jornada o resuelto');
    if caso.dia=5 then
      perform pg_temp.afirmar(fila->'segundo_corte'='null'::jsonb and foto#>>'{cortes,segundo_corte_en}' is null, 'Segundo corte sábado');
      perform pg_temp.afirmar(fila#>>'{primer_corte,objetivo}'='3', 'Mínimo sábado independiente');
    end if;
  end loop;
  -- El corte 2 conserva la foto anterior a 16:00, aunque llame 20 veces después.
  perform set_config('f43.reloj', ((a.lunes+time '17:00') at time zone 'America/Lima')::text, true);
  foto := pg_temp.f43_equipo(null,null);
  select e into fila from jsonb_array_elements(foto#>'{cortes,equipo}') e where e->>'analista_id'=a.vendedor::text;
  perform pg_temp.afirmar(fila#>>'{segundo_corte,llamadas}'='0' and fila#>>'{segundo_corte,estado}'='incumplido'
    and fila#>>'{segundo_corte,aviso_pendiente}'='true', 'Segundo corte se borró por llamadas tardías');
  perform set_config('f43.reloj', (((a.lunes+2)+time '17:00') at time zone 'America/Lima')::text, true);
  foto := pg_temp.f43_equipo(null,null);
  select e into fila from jsonb_array_elements(foto#>'{cortes,equipo}') e where e->>'analista_id'=a.vendedor::text;
  perform pg_temp.afirmar(fila#>>'{segundo_corte,llamadas}'='19' and fila#>>'{segundo_corte,estado}'='incumplido', 'Incluyó llamada de 16:00 exactas');
  -- Domingo: las llamadas permanecen en el marcador, no hay evaluación de cortes.
  perform set_config('f43.reloj', (((a.lunes+6)+time '12:00') at time zone 'America/Lima')::text, true);
  foto := pg_temp.f43_equipo(null,null);
  perform pg_temp.afirmar(foto#>>'{cortes,estado}'='no_laborable' and foto#>'{cortes,equipo}'='[]'::jsonb, 'Domingo evaluado');
  select e into fila from jsonb_array_elements(foto->'equipo') e where e->>'analista_id'=a.vendedor::text;
  perform pg_temp.afirmar(fila#>>'{marcador,llamadas}'='40', 'Se ocultó actividad del domingo');
  -- Hoy OFF no cambia ayer ON; no popup histórico, F3/F4 mismo umbral diario.
  perform set_config('f43.reloj', (((a.lunes+7)+time '12:00') at time zone 'America/Lima')::text, true);
  perform pg_temp.afirmar(pg_temp.f43_equipo(null,null)#>>'{cortes,estado}'='desactivados', 'Apagado futuro no aplicado');
  foto := pg_temp.f43_equipo(a.lunes+1,null);
  perform pg_temp.afirmar(foto#>>'{cortes,politica_version}'='2' and foto#>>'{umbrales,bien_min_pct}'='45', 'Historia rejuzgada con política actual');
  perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(foto#>'{cortes,equipo}') e
    where e#>>'{primer_corte,puede_avisar}'='true' or e#>>'{segundo_corte,puede_avisar}'='true'), 'Aviso histórico');
  foto := pg_temp.f43_equipo(a.lunes+4,null);
  perform pg_temp.afirmar(foto#>>'{umbrales,politica_version}'='3' and foto#>>'{umbrales,bien_min_pct}'='70', 'Umbral nuevo no aplicado');
  perform pg_temp.afirmar(pg_temp.f43_analista(a.lunes+4,a.vendedor)->'umbrales'=foto->'umbrales',
    'Las puertas F3/F4 difieren en política de la misma jornada');
  -- Límites de Lima: 04:59Z pertenece al día anterior, 05:00Z inicia la jornada civil.
  perform set_config('f43.reloj', (((a.lunes+1)::timestamp at time zone 'America/Lima')-interval '1 second')::text, true);
  perform pg_temp.afirmar(pg_temp.f43_equipo(null,null)->>'dia'=a.lunes::text, 'Lima adelantó fecha');
  perform set_config('f43.reloj', ((a.lunes+1)::timestamp at time zone 'America/Lima')::text, true);
  perform pg_temp.afirmar(pg_temp.f43_equipo(null,null)->>'dia'=(a.lunes+1)::text, 'Lima no cambió fecha');
  -- Un id de otro equipo nunca aparece aunque se llame al helper privado.
  foto := private.gestion_diaria_cortes(a.lunes,array[a.vendedor,a.ajeno], (a.lunes+time '17:00') at time zone 'America/Lima');
  perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(foto->'equipo') e where e->>'analista_id'=a.ajeno::text), 'Fuga de otro equipo');
  begin perform pg_temp.f43_equipo(null,a.supervisor_ajeno); raise exception 'Aceptó supervisor ajeno';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Un mismo analista/día debe conservar cifras y elegibilidad entre supervisor,
-- gerencia y lector global; no acreditar cartera vacía por una brecha de RLS.
set local role authenticated;
do $$ declare a record; actor uuid; esperado jsonb; fila jsonb; foto jsonb; begin
  select * into a from f43_actores;
  perform set_config('f43.reloj', (((a.lunes+1)+time '17:00') at time zone 'America/Lima')::text,true);
  foreach actor in array array[a.supervisor,a.gerente,a.lector] loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    foto:=pg_temp.f43_equipo(a.lunes+1,a.supervisor);
    select e into fila from jsonb_array_elements(foto#>'{cortes,equipo}') e where e->>'analista_id'=a.vendedor::text;
    if esperado is null then esperado:=fila; end if;
    perform pg_temp.afirmar(fila=esperado and fila->>'cartera_abierta'='true', 'Cartera/cortes cambian entre roles autorizados');
    perform pg_temp.afirmar(pg_temp.f43_analista(a.lunes+1,a.vendedor)->'umbrales'=foto->'umbrales', 'Política F3/F4 difiere por rol');
  end loop;
  perform set_config('request.jwt.claim.sub',a.supervisor::text,true);
end $$;
reset role;

-- Sábado: llamadas al cierre NO recuperan un primer corte pendiente.
alter table crm.actividades disable trigger user;
update crm.actividades set creado_en=creado_en+interval '2 hours'
where creado_por=(select vendedor from f43_actores)
  and creado_en=(((select lunes from f43_actores)+5+time '12:00') at time zone 'America/Lima');
alter table crm.actividades enable trigger user;
select set_config('f43.reloj', (((lunes+5)+time '13:00') at time zone 'America/Lima')::text,true) from f43_actores;
set local role authenticated;
do $$ declare f jsonb; begin
  select e into f from jsonb_array_elements(pg_temp.f43_equipo(null,null)#>'{cortes,equipo}') e
    where e->>'analista_id'=(select vendedor::text from f43_actores);
  perform pg_temp.afirmar(f#>>'{primer_corte,estado}'='incumplido'
    and f#>>'{primer_corte,llamadas_recuperacion}'='1'
    and f#>>'{primer_corte,aviso_pendiente}'='true'
    and f#>>'{primer_corte,puede_avisar}'='false', 'Sábado: cierre cambió el corte o permite aviso');
end $$;
reset role;

-- Sin cartera: se excluye únicamente del corte, no del roster ni de inactividad.
alter table crm.leads disable trigger user;
update crm.leads set activo=false where vendedor_id=(select vendedor from f43_actores);
alter table crm.leads enable trigger user;
select set_config('request.jwt.claim.sub', supervisor::text, true),
  set_config('f43.reloj', ((lunes+time '11:30') at time zone 'America/Lima')::text,true) from f43_actores;
set local role authenticated;
do $$ declare f jsonb; j jsonb; begin
  j := pg_temp.f43_equipo(null,null);
  select e into f from jsonb_array_elements(j#>'{cortes,equipo}') e where e->>'analista_id'=(select vendedor::text from f43_actores);
  perform pg_temp.afirmar(f#>>'{primer_corte,estado}'='sin_cartera' and f#>>'{primer_corte,aviso_pendiente}'='false', 'Aviso sin cartera');
  select e into f from jsonb_array_elements(j->'equipo') e where e->>'analista_id'=(select vendedor::text from f43_actores);
  perform pg_temp.afirmar(f is not null and f->>'sin_llamar_2h'='true', 'Sin cartera desaparece o silenció otra alerta');
end $$;
reset role;

-- Matriz de lecturas/escrituras por identidad. Ni gerencia escribe por tabla.
-- Leads activos pero cerrados tampoco cuentan como cartera abierta.
alter table crm.leads disable trigger user;
update crm.leads set activo=true,etapa='descartado',motivo_descarte='sin_interes' where id=(select lead from f43_actores);
alter table crm.leads enable trigger user;
set local role authenticated;
select pg_temp.afirmar(e#>>'{primer_corte,estado}'='sin_cartera', 'Lead descartado cuenta como abierto')
from jsonb_array_elements(pg_temp.f43_equipo(null,null)#>'{cortes,equipo}') e
where e->>'analista_id'=(select vendedor::text from f43_actores);
reset role;
alter table crm.leads disable trigger user;
update crm.leads set etapa='convertido',motivo_descarte=null where id=(select lead from f43_actores);
alter table crm.leads enable trigger user;
set local role authenticated;
select pg_temp.afirmar(e#>>'{primer_corte,estado}'='sin_cartera', 'Lead convertido cuenta como abierto')
from jsonb_array_elements(pg_temp.f43_equipo(null,null)#>'{cortes,equipo}') e
where e->>'analista_id'=(select vendedor::text from f43_actores);
reset role;

set local role authenticated;
do $$ declare actor uuid; f jsonb; begin
  for actor in select unnest(array[supervisor,gerente,vendedor,coordinador]) from f43_actores loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    perform pg_temp.afirmar(exists(select 1 from crm.politica_gestion_diaria where version=1), 'Rol CRM perdió umbrales');
    begin perform motivo from crm.politica_gestion_diaria;
      raise exception 'Lectura directa de motivo admitida'; exception when insufficient_privilege then null; end;
    begin perform creado_por from crm.politica_gestion_diaria;
      raise exception 'Lectura directa de autor admitida'; exception when insufficient_privilege then null; end;
    begin insert into crm.politica_gestion_diaria(version,vigente_desde,motivo) values(99,now(),'Forjado');
      raise exception 'INSERT directo admitido'; exception when insufficient_privilege then null; end;
    begin update crm.politica_gestion_diaria set cortes_activos=true where version=1;
      raise exception 'UPDATE directo admitido'; exception when insufficient_privilege then null; end;
    begin delete from crm.politica_gestion_diaria where version=1;
      raise exception 'DELETE directo admitido'; exception when insufficient_privilege then null; end;
  end loop;
  for actor in select unnest(array[vendedor,coordinador]) from f43_actores loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    begin perform crm.gestion_diaria_equipo_fn(); raise exception 'Rol no supervisor admitido';
    exception when insufficient_privilege then null; end;
    begin perform private.gestion_diaria_cortes((select lunes from f43_actores),'{}',now()+interval '30 days');
      raise exception 'Helper admitió no supervisor'; exception when insufficient_privilege then null; end;
  end loop;
  perform set_config('request.jwt.claim.sub',(select gerente::text from f43_actores),true);
  f := pg_temp.f43_equipo(null,(select supervisor from f43_actores));
  perform pg_temp.afirmar(f->>'supervisor_id'=(select supervisor::text from f43_actores), 'Gerencia no puede seleccionar equipo');
  perform set_config('request.jwt.claim.sub','',true);
  perform pg_temp.afirmar(not exists(select 1 from crm.politica_gestion_diaria), 'Sin identidad lee política');
  begin perform crm.gestion_diaria_equipo_fn(); raise exception 'Sesión sin identidad admitida';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- La revocación CRM también retira lectura de configuración y acceso a cortes.
alter table crm.equipo disable trigger user;
update crm.equipo set activo=false where perfil_id=(select vendedor from f43_actores);
alter table crm.equipo enable trigger user;
select set_config('request.jwt.claim.sub',supervisor::text,true) from f43_actores;
set local role authenticated;
do $$ declare f jsonb; begin
  f:=pg_temp.f43_equipo(null,null);
  perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(f->'equipo') e
    where e->>'analista_id'=(select vendedor::text from f43_actores)), 'Analista revocado sigue en tabla');
  perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(f#>'{cortes,equipo}') e
    where e->>'analista_id'=(select vendedor::text from f43_actores)), 'Analista revocado sigue en cortes');
end $$;
reset role;
alter table crm.equipo disable trigger user;
update crm.equipo set activo=true where perfil_id=(select vendedor from f43_actores);
alter table crm.equipo enable trigger user;

alter table crm.equipo disable trigger user;
update crm.equipo set activo=false where perfil_id=(select supervisor from f43_actores);
alter table crm.equipo enable trigger user;
select set_config('request.jwt.claim.sub',supervisor::text,true) from f43_actores;
set local role authenticated;
select pg_temp.afirmar(not exists(select 1 from crm.politica_gestion_diaria), 'Supervisor revocado lee política');
do $$ begin perform crm.gestion_diaria_equipo_fn(); raise exception 'Revocado consulta cortes';
exception when insufficient_privilege then null; end $$;
reset role;
set local role anon;
do $$ begin perform * from crm.politica_gestion_diaria; raise exception 'Anon lee política';
exception when insufficient_privilege then null; end $$;
reset role;
set local role service_role;
do $$ begin perform * from crm.politica_gestion_diaria; raise exception 'Service lee política';
exception when insufficient_privilege then null; end $$;
reset role;

-- Inmutabilidad, vigencia futura, horas y cadena incluso con rol administrativo.
do $$ declare p crm.politica_gestion_diaria; begin
  select * into p from crm.politica_gestion_diaria where version=4;
  begin update crm.politica_gestion_diaria set motivo='Cambiar historia' where version=2;
    raise exception 'Historial mutable'; exception when sqlstate '55000' then null; end;
  begin delete from crm.politica_gestion_diaria where version=2;
    raise exception 'Historial borrable'; exception when sqlstate '55000' then null; end;
  begin insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,motivo)
    values(5,p.id,date_trunc('day',now()),'Retroactivo'); raise exception 'Vigencia retroactiva';
    exception when invalid_parameter_value then null; end;
  begin insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,motivo,corte_1_hora)
    values(5,p.id,p.vigente_desde+interval '1 day','Hora inválida','13:00'); raise exception 'Corte fuera de sábado';
    exception when check_violation then null; end;
  begin insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,motivo)
    values(7,p.id,p.vigente_desde+interval '1 day','Cadena inválida'); raise exception 'Cadena inválida admitida';
    exception when serialization_failure then null; end;
  begin insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,motivo)
    values(5,p.id,p.vigente_desde-interval '1 day','Revisión fuera de orden'); raise exception 'Revisión futura no monótona';
    exception when invalid_parameter_value then null; end;
  begin insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,motivo,creado_por)
    values(5,p.id,p.vigente_desde,'Sin autor',null); raise exception 'Revisión sin autor';
    exception when check_violation then null; end;
end $$;
-- Una revisión más nueva de la MISMA jornada futura gana por versión.
insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,motivo)
select 5,id,vigente_desde,'Fixture: sustituir revisión futura' from crm.politica_gestion_diaria where version=4;
select pg_temp.afirmar((select p.version from private.politica_gestion_diaria_vigente(
  ((lunes+7)::timestamp at time zone 'America/Lima')) p)=5, 'No desempata por versión') from f43_actores;
select private.assert_gestion_diaria();
select 'GESTION_DIARIA_CORTES_OK';
rollback;
