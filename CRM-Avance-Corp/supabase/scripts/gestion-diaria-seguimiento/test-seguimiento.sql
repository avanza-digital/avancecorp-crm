-- Se ejecuta dentro de la transacción reversible de ensayar.mjs.
create temporary table f44_actores as
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
  date_trunc('week', statement_timestamp() at time zone 'America/Lima')::date + 7 lunes;
grant select on f44_actores to authenticated;
create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'F4.4/5: %', mensaje; end if; end $$;
select pg_temp.afirmar(vendedor is not null and supervisor is not null and ajeno is not null
  and gerente is not null and coordinador is not null and lector is not null, 'Faltan identidades') from f44_actores;

select set_config('request.jwt.claim.sub', supervisor::text, true) from f44_actores;
set local role authenticated;
select pg_temp.afirmar(crm.gestion_diaria_avisos_fn()->>'estado_cortes'='desactivados', 'Cortes OFF');
select pg_temp.afirmar(crm.gestion_diaria_avisos_fn()->'alertas'='[]'::jsonb, 'OFF sin avisos');
reset role;

select set_config('request.jwt.claim.sub', gerente::text, true) from f44_actores;
set local role authenticated;
select pg_temp.afirmar((crm.configuracion_gestion_diaria_fn()->>'puede_editar')::boolean, 'Gerencia puede editar');
select pg_temp.afirmar(crm.configuracion_gestion_diaria_fn()#>>'{vigente,configuracion,cortes_activos}'='false', 'Política OFF');
select pg_temp.afirmar((crm.publicar_politica_gestion_diaria(1,
  (a.lunes::timestamp at time zone 'America/Lima'),
  jsonb_set(crm.configuracion_gestion_diaria_fn()#>'{vigente,configuracion}', '{cortes_activos}', 'true'),
  'Fixture reversible de avisos') ->>'expected_version')::integer=2, 'Publicación futura') from f44_actores a;
reset role;

-- Lead propio con cero llamadas, solo dentro de esta transacción.
select crm.crear_lead_si_disponible(p_nombre_completo => 'ORACULO F44 AVISOS', p_telefono => '999577773',
  p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => lead,
  p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
  p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => vendedor,
  p_nota => 'Fixture reversible F44', p_telefono_alternativo => null) from f44_actores;

-- Reloj privado explícito: NO se agregan puertas ni parámetros al API.
select set_config('request.jwt.claim.sub', supervisor::text, true) from f44_actores;
do $$ declare a record; r jsonb; caso record; begin
  select * into a from f44_actores;
  for caso in select * from (values
    (0,time '11:29:59',0,false), (0,time '11:30',1,true),
    (0,time '15:59:59',1,true), (0,time '16:00',2,true),
    (0,time '18:00',2,false), (5,time '11:30',1,true),
    (5,time '12:59:59',1,true), (5,time '13:00',1,false),
    (6,time '12:00',0,false)
  ) c(dia,hora,cantidad,presentar) loop
    r := private.gestion_diaria_avisos(((a.lunes+caso.dia)+caso.hora) at time zone 'America/Lima');
    perform pg_temp.afirmar(jsonb_array_length(r->'alertas')=caso.cantidad, 'Cantidad: '||caso.dia||' '||caso.hora);
    perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(r->'alertas') x
      where (x->>'puede_presentar')::boolean<>caso.presentar), 'Horario de aviso');
    perform pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(r->'alertas') x,
      jsonb_array_elements(x->'miembros') m where m->>'analista_id'=a.ajeno::text), 'Ámbito ajeno');
    if caso.cantidad > 0 then
      perform pg_temp.afirmar(exists(select 1 from jsonb_array_elements(r->'alertas') x,
        jsonb_array_elements(x->'miembros') m where m->>'analista_id'=a.vendedor::text), 'Falta miembro propio');
    end if;
  end loop;
end $$;
select 'PASS: OFF, publicación futura, reloj Lima, sábado/domingo, ámbitos y rol puente bajo RLS';

create function pg_temp.error_esperado(p_sql text, p_estado text) returns void language plpgsql as $$
declare recibido text;
begin
  begin execute p_sql; exception when others then recibido := sqlstate; end;
  if recibido is distinct from p_estado then raise exception 'F4.4/5: error esperado %, recibido %', p_estado, recibido; end if;
end $$;

-- Funciones de prueba de sesión: el cuerpo instalado se copia, cambiando
-- únicamente el reloj. Nunca se agrega un reloj controlable a la API real.
do $$ declare firma text; fuente text; nombre text; begin
  for firma, nombre in select * from (values
    ('private.sellar_reconocimiento_corte(crm.alertas_reconocimientos)','sellar_reconocimiento_corte'),
    ('crm.gestion_diaria_presentar_corte(text,uuid)','gestion_diaria_presentar_corte'),
    ('crm.gestion_diaria_reconocer_corte(text,text,uuid)','gestion_diaria_reconocer_corte')
  ) f(firma,nombre) loop
    fuente := pg_get_functiondef(firma::regprocedure);
    perform pg_temp.afirmar(strpos(fuente, 'clock_timestamp()')>0, 'Falta reloj en '||firma);
    fuente := replace(fuente, split_part(firma,'(',1)||'(', 'pg_temp.'||nombre||'(');
    execute replace(fuente, 'clock_timestamp()', 'current_setting(''f44.reloj'')::timestamptz');
  end loop;
  fuente := pg_get_functiondef('crm.alertas_reconocimientos_sellar()'::regprocedure);
  execute replace(fuente, 'private.sellar_reconocimiento_corte(', 'pg_temp.sellar_reconocimiento_corte(');
end $$;

select set_config('f44.reloj', ((lunes+time '12:00') at time zone 'America/Lima')::text, true) from f44_actores;
create temporary table f44_peticiones as select
  'grupo:corte_manana:'||supervisor||':'||to_char(lunes,'YYYY-MM-DD') aviso,
  'grupo:corte_tarde:'||supervisor||':'||to_char(lunes,'YYYY-MM-DD') aviso_tarde,
  'grupo:corte_manana:'||supervisor_ajeno||':'||to_char(lunes,'YYYY-MM-DD') ajeno,
  gen_random_uuid() entrega, gen_random_uuid() posponer, gen_random_uuid() reaviso,
  gen_random_uuid() reconocer from f44_actores;
grant select on f44_peticiones to authenticated;
set local role authenticated;
select pg_temp.error_esperado('select private.gestion_diaria_avisos(now())','42501');
select pg_temp.error_esperado('select * from crm.gestion_diaria_entregas','42501');
select pg_temp.error_esperado('select * from crm.gestion_diaria_control_avisos','42501');
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso,entrega)->'aviso'<>'null'::jsonb,'Primera presentación') from f44_peticiones;
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso,gen_random_uuid())->'aviso'='null'::jsonb,'No duplica en otro dispositivo') from f44_peticiones;
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso,entrega)->'aviso'<>'null'::jsonb,'Reintento idempotente') from f44_peticiones;
select pg_temp.error_esperado(format('select pg_temp.gestion_diaria_presentar_corte(%L,%L)',ajeno,entrega),'22023') from f44_peticiones;
select pg_temp.error_esperado(format('select pg_temp.gestion_diaria_reconocer_corte(%L,''reconocer'',gen_random_uuid())',ajeno),'42501') from f44_peticiones;

select pg_temp.afirmar(pg_temp.gestion_diaria_reconocer_corte(aviso,'posponer',posponer)#>>'{alertas,0,estado}'='pospuesto','Posponer confirmado') from f44_peticiones;
select pg_temp.afirmar(pg_temp.gestion_diaria_reconocer_corte(aviso,'posponer',posponer)#>>'{alertas,0,estado}'='pospuesto','Posponer idempotente') from f44_peticiones;
select pg_temp.error_esperado(format('select pg_temp.gestion_diaria_reconocer_corte(%L,''reconocer'',%L)',aviso,posponer),'22023') from f44_peticiones;
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso,entrega)->'aviso'='null'::jsonb,'Reintento no salta posposición') from f44_peticiones;
reset role;
select pg_temp.afirmar(count(*)=1 and min(hasta)=current_setting('f44.reloj')::timestamptz+interval '1 hour',
  'Una sola fila y plazo exacto') from crm.alertas_reconocimientos where solicitud_corte_id=(select posponer from f44_peticiones);
select set_config('f44.reloj', ((lunes+time '13:00') at time zone 'America/Lima')::text, true) from f44_actores;
set local role authenticated;
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso,entrega)->'aviso'='null'::jsonb,'Entrega inicial no captura reaviso') from f44_peticiones;
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso,reaviso)#>>'{aviso,entrega}'='1','Reaviso una hora después') from f44_peticiones;
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso,gen_random_uuid())->'aviso'='null'::jsonb,'Reaviso único entre dispositivos') from f44_peticiones;
select pg_temp.error_esperado(format('select pg_temp.gestion_diaria_reconocer_corte(%L,''posponer'',gen_random_uuid())',aviso),'22023') from f44_peticiones;
select pg_temp.afirmar(pg_temp.gestion_diaria_reconocer_corte(aviso,'reconocer',reconocer)#>>'{alertas,0,estado}'='reconocido','Reconocimiento persistente') from f44_peticiones;
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso,reaviso)->'aviso'='null'::jsonb,'Reintento no revive reconocimiento') from f44_peticiones;
reset role;

-- POST directo: el trigger ignora hora, autor, severidad, miembros y plazo falsos.
select set_config('f44.reloj', ((lunes+time '17:30') at time zone 'America/Lima')::text, true) from f44_actores;
set local role authenticated;
insert into crm.alertas_reconocimientos(perfil_id,alerta_id,accion,miembros,severidad,hasta,creado_en)
select auth.uid(),aviso_tarde,'posponer',array['miembro-falso'],'critica',now()+interval '7 days',now()-interval '1 day' from f44_peticiones;
reset role;
select pg_temp.afirmar(hasta=((a.lunes+time '18:30') at time zone 'America/Lima') and severidad='atencion'
  and creado_en=((a.lunes+time '17:30') at time zone 'America/Lima')
  and not ('miembro-falso'=any(miembros)) and a.vendedor::text=any(miembros), 'Sello de POST directo')
from crm.alertas_reconocimientos r cross join f44_actores a where alerta_id=(select aviso_tarde from f44_peticiones);
select set_config('f44.reloj', ((lunes+time '18:30') at time zone 'America/Lima')::text, true) from f44_actores;
set local role authenticated;
select pg_temp.afirmar(pg_temp.gestion_diaria_presentar_corte(aviso_tarde,gen_random_uuid())->'aviso'='null'::jsonb,'Sin reaviso fuera de jornada') from f44_peticiones;
reset role;

-- El reloj avanza a mañana: el aviso del día anterior ya no se puede reconocer.
select set_config('f44.reloj', (((lunes+1)+time '12:00') at time zone 'America/Lima')::text, true) from f44_actores;
set local role authenticated;
select pg_temp.error_esperado(format('select pg_temp.gestion_diaria_reconocer_corte(%L,''reconocer'',gen_random_uuid())',aviso),'42501') from f44_peticiones;
reset role;
select 'PASS: entrega/reintentos, reconocimiento, posponer 1 hora una sola vez, POST falsificado, cierre y siguiente jornada';

-- Matriz de roles con el rol SQL authenticated real, no con postgres saltando RLS.
do $$ declare identidad uuid; begin
  for identidad in select vendedor from f44_actores union all select gerente from f44_actores
    union all select coordinador from f44_actores union all select lector from f44_actores
    union all select gen_random_uuid() loop
    perform set_config('request.jwt.claim.sub',identidad::text,true);
    set local role authenticated;
    perform pg_temp.error_esperado('select crm.gestion_diaria_avisos_fn()','42501');
    perform pg_temp.error_esperado('select crm.gestion_diaria_presentar_corte(''no-autorizado'',gen_random_uuid())','42501');
    perform pg_temp.error_esperado('select crm.gestion_diaria_reconocer_corte(''no-autorizado'',''reconocer'',gen_random_uuid())','42501');
    reset role;
  end loop;
  for identidad in select vendedor from f44_actores union all select supervisor from f44_actores
    union all select coordinador from f44_actores union all select lector from f44_actores loop
    perform set_config('request.jwt.claim.sub',identidad::text,true);
    set local role authenticated;
    perform pg_temp.error_esperado('select crm.publicar_politica_gestion_diaria(2,now(),''{}'',''Sin permiso'')','42501');
    perform pg_temp.error_esperado('select crm.controlar_avisos_gestion_diaria(1,false,''Sin permiso'')','42501');
    reset role;
  end loop;
end $$;
select set_config('request.jwt.claim.sub', lector::text, true) from f44_actores;
set local role authenticated;
select pg_temp.afirmar(crm.configuracion_gestion_diaria_fn()->>'puede_editar'='false','Directorio solo lectura');
reset role;

select set_config('request.jwt.claim.sub', gerente::text, true) from f44_actores;
create temporary table f45_config as select
  crm.configuracion_gestion_diaria_fn()#>'{historial,0,configuracion}' config,
  ((lunes+1)::timestamp at time zone 'America/Lima') vigencia from f44_actores;
grant select on f45_config to authenticated;
set local role authenticated;
do $$ declare c record; variante jsonb; fecha timestamptz; begin
  select * into c from f45_config;
  for variante in select * from (values
    (c.config-'sabado_minimo'), (c.config||'{"extra":1}'),
    (c.config||'{"cortes_activos":"true"}'), (c.config||'{"corte_1_minimo":3.5}'),
    (c.config||'{"corte_2_hora":"25:00"}'), (c.config||'{"corte_1_minimo":null}'),
    (c.config||'{"sabado_minimo":"3"}'), (c.config||'{"tasa_baja_diferencia_pp":20}')
  ) variantes(config) loop
    perform pg_temp.error_esperado(format('select crm.publicar_politica_gestion_diaria(2,%L,%L,''Inválido'')',c.vigencia,variante),'22023');
  end loop;
  perform pg_temp.error_esperado(format('select crm.publicar_politica_gestion_diaria(1,%L,%L,''Versión antigua'')',c.vigencia,c.config),'PT409');
  perform pg_temp.error_esperado(format('select crm.publicar_politica_gestion_diaria(2,%L,%L,''Demasiado lejos'')',now()+interval '91 days',c.config),'22023');
  perform pg_temp.error_esperado(format('select crm.publicar_politica_gestion_diaria(2,%L,%L,''Retroactivo'')',now()-interval '1 day',c.config),'22023');
  perform pg_temp.error_esperado(format('select crm.publicar_politica_gestion_diaria(2,%L,%L,''Piso inválido'')',c.vigencia,c.config||'{"corte_2_piso":501}'),'23514');
  perform pg_temp.afirmar((crm.publicar_politica_gestion_diaria(2,c.vigencia,c.config||'{"corte_1_minimo":3.0}',
    'Entero JSON equivalente')->>'expected_version')::integer=3,'Entero JSON 3.0 aceptado');
  perform pg_temp.afirmar(crm.configuracion_gestion_diaria_fn()#>>'{vigente,configuracion,cortes_activos}'='false','La versión futura no cambia hoy');
  perform pg_temp.afirmar(crm.controlar_avisos_gestion_diaria(1,false,'Pausa de ensayo')#>>'{control_avisos,habilitados}'='false','Apagado inmediato');
  perform pg_temp.error_esperado('select crm.controlar_avisos_gestion_diaria(1,true,''Versión obsoleta'')','PT409');
  perform pg_temp.afirmar(crm.controlar_avisos_gestion_diaria(2,true,'Reanudar ensayo')#>>'{control_avisos,version}'='3','Reanudar con versión');
end $$;
reset role;
select 'PASS: matriz de roles, claves/tipos/rangos, versiones obsoletas, horizonte, 3.0 e historial futuro';
