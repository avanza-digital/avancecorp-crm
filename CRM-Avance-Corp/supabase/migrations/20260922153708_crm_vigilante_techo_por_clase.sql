-- El techo del vigilante medía la poblacion equivocada (Miguel, 22/09/2026).
--
-- ESTADO DE PARTIDA, medido en produccion el 22/09 (lectura, nada escrito):
--   tope 30 · sujetos al techo 30 · HOLGURA 0 · 4 auxiliares verificados.
--
-- El trinquete esta lleno al ras. Hoy CUALQUIER pantalla nueva que cuente leads
-- o citas lo pone en rojo, aunque sea una cola de trabajo que no puede
-- contradecir ninguna cifra publicada.
--
-- EL DIAGNOSTICO. El techo no distingue dos preguntas muy distintas que mete en
-- el mismo saco:
--   · contar lo que hay AHORA ("tengo 12 pendientes", "faltan 40 por repartir")
--     es INVENTARIO: no puede contradecir la conversion del mes porque no
--     responde esa pregunta;
--   · medir el PASADO ("el mes cerro en 4,23 %") es donde puede nacer una
--     segunda verdad.
-- De los 30 sujetos, 16 son inventario y 14 miden el pasado. El techo se lleno
-- de inventario, y por eso bloquea justo lo inofensivo mientras deja sin cupo
-- propio a lo que de verdad hay que vigilar.
--
-- LA CLASIFICACION. Jev (TypeSafe) leyo las 30 razones declaradas y acerto 21
-- con confianza >= 0,80 -- incluidas las TRES que se autodeclaran «MIXTA», que
-- encontro sin fallar una. Las 9 que quedaron bajo el umbral se decidieron a
-- mano, y se corrigio UNA de Jev: private.contratos_afectados_por_anulacion,
-- que puso en analitica con 0,81 y es operativo (devuelve SETOF uuid -- una
-- lista de ids, no una cifra -- y su propia razon dice que produccion y la
-- deuda de mes sellado ya no le preguntan). Jev propone, el humano verifica:
-- la clase decide QUE VIGILA el detector y eso no se delega.
--
-- QUE CAMBIA
--   (1) `clase` en las declaraciones, cuatro valores y NOT NULL: toda
--       declaracion futura nace clasificada o no entra.
--   (2) El techo cuenta SOLO analitica + mixta: 30 -> 14. Es BAJAR, asi que el
--       trinquete lo permite y NINGUN candado se toca: trg_analitica_lc_tope_-
--       solo_baja solo prohibe subir, y aqui se baja.
--   (3) El sello de la lista pasa a incluir la clase. Reetiquetar un contador
--       de analitica a operativo sin re-sellar en una migracion = ROJO. Esa era
--       la unica puerta por la que se podia esquivar el techo, y queda cerrada.
--   (4) Un sujeto DEL CENSO no puede llevar clase 'verificador'. Los dos
--       verificadores reales salen del censo por identidad exacta + huella
--       (migracion 20260921190145); la clase los describe, no los exime.
--   (5) LA CLASE ES UN TRINQUETE, como el tope: solo puede APRETAR. Pasar de
--       operativo a analitica se permite; de analitica a operativo REBOTA
--       (trg_analitica_lc_clase_solo_aprieta). Sin este candado quedaba un
--       hueco de verdad: reetiquetar y re-sellar habria hecho sitio bajo el
--       techo sin tocar el tope. El assert comprueba que el candado sigue
--       puesto y activo, y el postflight PRUEBA que rebota.
--
-- QUE NO CAMBIA
--   Las 16 operativas NO salen del vigilante: siguen censadas y siguen
--   exigiendo su declaracion firmada y su huella vigente, porque `declarada` y
--   `huella_ok` se comprueban sobre TODOS los candidatos, no solo sobre los del
--   techo. Lo unico que cambia es que dejan de consumir cupo.
--   Las 14 quedan a 14/14, holgura 0: nadie puede anadir un lugar numero 15 que
--   mida el pasado sin decidirlo en una migracion. El trinquete sigue siendo
--   trinquete; ahora aprieta donde importa.
--
-- LO QUE ESTO **NO** CIERRA, dicho sin adornos:
--   · `operativo` es una etiqueta AUTODECLARADA. Ninguna comprobacion de
--     maquina puede saber si un contador rotulado operativo publica en realidad
--     una cifra del pasado; eso lo decide quien escribe la razon, y se revisa
--     leyendola. Antes, un contador nuevo chocaba contra un techo sin holgura;
--     ahora, si se rotula operativo, entra. Ese es el precio elegido.
--   · EL TOPE NO SIGUE AL RE-ETIQUETADO. Si una migracion futura redefine el
--     candado y baja una fila de analitica a operativo, `v_n` cae a 13 y el
--     tope se queda en 14: holgura 1 creada en silencio. El assert solo mira
--     `v_n > v_tope`. Es la misma propiedad que ya tenia el trinquete cuando un
--     contador desaparecia, no una regresion -- pero queda escrito aqui para
--     que la proxima revision lo busque en vez de descubrirlo.
--
-- AVISO A LAS SESIONES EN PARALELO. Desde esta migracion, un
-- `insert into private.analitica_leads_citas_exenciones (objeto, tipo, huella,
-- razon)` FALLA: falta `clase`, que es NOT NULL. Es el efecto buscado -- ninguna
-- declaracion nace sin clasificar -- pero cualquier migracion ya escrita y sin
-- aplicar hay que retocarla.
--
-- COMO SE REVIERTE. No se revierte subiendo el techo de vuelta a 30: el
-- trinquete no deja subir, y es deliberado. Si hubiera que deshacerlo se
-- escribe una migracion nueva que reponga el conteo antiguo dentro del assert y
-- deje el tope donde este. La fila del tope tampoco se borra y se repone: el
-- trigger trg_analitica_lc_tope_no_truncar lo impide a proposito. Es decir:
-- esto se piensa antes, no despues.

-- EN UNA SOLA TRANSACCION, Y NO POR COSTUMBRE. Bajar el tope es IRREVERSIBLE:
-- si los statements se aplicaran sueltos y uno fallara entre el `update` del
-- tope y el assert nuevo, produccion quedaria con tope 14 y el assert viejo
-- contando 30 -> gate ROJO PERMANENTE, sin poder subir el tope ni reponer la
-- fila. Los cerrojos son los mismos de 20260921190145.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones,
           private.analitica_lc_sello,
           private.analitica_leads_citas_tope
  in share row exclusive mode;

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT: el mundo que esta migracion da por cierto.
-- ---------------------------------------------------------------------------
do $preflight$
declare v_tope integer; v_total integer; v_aux integer; v_filas integer; v_gate text;
begin
  if exists (select 1 from pg_attribute a
              where a.attrelid = 'private.analitica_leads_citas_exenciones'::regclass
                and a.attname = 'clase' and not a.attisdropped) then
    -- Distinguir «ya aplicada» de «aplicada A MEDIAS»: mandar al operador a
    -- buscar el problema al sitio equivocado, con el gate rojo e irreversible,
    -- es peor que no decir nada.
    select tope into v_tope from private.analitica_leads_citas_tope where id;
    begin v_gate := private.assert_analitica_leads_citas();
    exception when others then v_gate := 'ROJO: ' || sqlerrm; end;
    if v_tope = 14 and v_gate like 'OK:%' then
      raise exception 'PREFLIGHT: esta migracion YA SE APLICO por completo (tope %, gate verde)', v_tope;
    end if;
    raise exception 'PREFLIGHT: aplicacion PARCIAL detectada -- la columna clase existe pero tope=% y el gate dice «%». NO reaplicar a ciegas.', v_tope, v_gate;
  end if;

  select tope into v_tope from private.analitica_leads_citas_tope where id;
  if v_tope is distinct from 30 then
    raise exception 'PREFLIGHT: el tope esperado era 30 y es %', v_tope;
  end if;

  select count(*) into v_total from private.contadores_crudos_leads_citas();
  select count(*) into v_aux   from private.auxiliares_analitica_lc_auditados();
  if v_total <> 34 or v_aux <> 4 then
    raise exception 'PREFLIGHT: el censo esperado era 34 candidatos y 4 auxiliares; hay % y %', v_total, v_aux;
  end if;

  select count(*) into v_filas from private.analitica_leads_citas_exenciones;
  if v_filas <> 38 then
    raise exception 'PREFLIGHT: se esperaban 38 declaraciones y hay %', v_filas;
  end if;

  -- La lista tiene que estar sellada AHORA, antes de tocarla: si ya venia
  -- des-sellada, el re-sello de esta migracion taparia un cambio ajeno.
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'PREFLIGHT: la lista de exenciones ya estaba des-sellada; no se re-sella encima de un cambio ajeno';
  end if;

  -- Y el gate tiene que estar VERDE de partida.
  perform private.assert_analitica_leads_citas();
end;
$preflight$;

-- El contrato de seguridad de las dos funciones que se recrean, fotografiado
-- por la BASE antes de tocarlas. `create or replace` conserva owner, ACL y
-- comentarios, pero eso se COMPRUEBA en el postflight, no se da por sabido: un
-- md5 o un ACL escrito a mano en una migracion es un hallazgo esperando turno.
create temp table _contrato_fn_antes on commit drop as
select p.oid::regprocedure::text as fn,
       p.proowner::regrole::text  as duenio,
       p.prosecdef, p.provolatile, p.proconfig,
       coalesce(p.proacl, acldefault('f', p.proowner))::text as acl
  from pg_proc p
 where p.oid in ('private.assert_analitica_leads_citas()'::regprocedure,
                 'private.huella_exenciones_analitica_lc()'::regprocedure);

-- ---------------------------------------------------------------------------
-- (b) La clase, y la clasificacion de las 38 declaraciones.
-- ---------------------------------------------------------------------------
alter table private.analitica_leads_citas_exenciones add column clase text;

update private.analitica_leads_citas_exenciones e
   set clase = v.clase
  from (values
    ('crm.agenda_reparto_diaria(date,integer)', 'operativo'),
    ('crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)', 'operativo'),
    ('crm.cerrar_periodo(date)', 'analitica'),
    ('crm.cierres_externos_fn(date)', 'analitica'),
    ('crm.cola_accion_fn(integer)', 'operativo'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', 'analitica'),
    ('crm.derivar_leads_equipo_fn(uuid[],uuid[])', 'operativo'),
    ('crm.guardar_agenda_reparto_diaria(date,uuid,uuid)', 'operativo'),
    ('crm.impacto_desactivacion_usuario_fn(uuid)', 'operativo'),
    ('crm.ingresos_reparto_mes_fn(date)', 'operativo'),
    ('crm.metricas_sla_fn(date,date)', 'analitica'),
    ('crm.metricas_vendedores_fn()', 'mixta'),
    ('crm.panel_distribucion_reparto(uuid,uuid,text,boolean)', 'operativo'),
    ('crm.reporte_derivaciones_equipo_fn(date,date)', 'operativo'),
    ('crm.rescatar_descartes(uuid[],uuid[],boolean)', 'operativo'),
    ('crm.rescate_descartes_meses()', 'operativo'),
    ('crm.resumen_reparto_fn()', 'operativo'),
    ('crm.resumen_tareas_fn()', 'operativo'),
    ('crm.series_comerciales_fn(integer)', 'mixta'),
    ('private.citas_gerencia_consulta(date,date)', 'analitica'),
    ('private.contratos_afectados_por_anulacion(uuid)', 'operativo'),
    ('private.metricas_agenda_implementacion(date,date)', 'analitica'),
    ('private.metricas_conversiones_implementacion(date,date,text)', 'analitica'),
    ('private.metricas_distribucion_leads_core(date,date,timestamp with time zone)', 'mixta'),
    ('private.metricas_reuniones_implementacion(date,date)', 'analitica'),
    ('private.metricas_sla_global_core(date,date,timestamp with time zone)', 'analitica'),
    ('private.produccion_mes_por_vendedor(timestamp with time zone,timestamp with time zone,uuid)', 'analitica'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', 'analitica'),
    ('private.supervisores_para_reparto_implementacion()', 'operativo'),
    ('private.trg_leads_asignaciones()', 'operativo'),
    ('crm.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamp with time zone,uuid)', 'analitica'),
    ('crm.metricas_multiempresa_fn(date)', 'analitica'),
    ('private.inversion_historica_aplicar(uuid,jsonb)', 'operativo'),
    ('private.inversion_historica_estado(text,uuid)', 'operativo')
  ) as v(objeto, clase)
 where e.objeto = v.objeto;

-- Las cuatro declaraciones que hoy NO estan en el censo: los dos verificadores
-- (salen por identidad + huella, mig 20260921190145) y dos declaraciones
-- historicas que el censo ya no atrapa. Se clasifican igual: la columna es
-- obligatoria para todas, y una declaracion sin clase seria una puerta abierta.
update private.analitica_leads_citas_exenciones set clase = 'verificador'
 where objeto in ('crm.contrato_eliminar_auditado(uuid,uuid)',
                  'private.citas_testigo_mes(date,date)');
-- Se autodeclara «MIXTA:» en su razon sellada (medido en prod el 22/09), asi
-- que lleva esa clase aunque hoy este fuera del censo: con la clase DENTRO del
-- sello, una fila que contradiga su propia razon es deuda esperando a cobrarse.
update private.analitica_leads_citas_exenciones set clase = 'mixta'
 where objeto = 'crm.metricas_conversiones_equipo_fn(date,date)';
update private.analitica_leads_citas_exenciones set clase = 'operativo'
 where objeto = 'crm.resumen_cartera_fn()';

alter table private.analitica_leads_citas_exenciones
  add constraint clase_conocida
  check (clase in ('analitica','mixta','operativo','verificador'));
alter table private.analitica_leads_citas_exenciones
  alter column clase set not null;

comment on table private.analitica_leads_citas_exenciones is
  'Objetos que cuentan leads o citas EN CRUDO a proposito, por identidad exacta y con la huella de su '
  'cuerpo: si el cuerpo cambia, la razon caduca y el trinquete salta. Desde el 22/09/2026 cada fila '
  'lleva ademas su `clase`, que decide QUIEN CONSUME CUPO bajo el techo; la clase entra en el sello de '
  'la lista y solo puede APRETAR (trg_analitica_lc_clase_solo_aprieta).';

comment on column private.analitica_leads_citas_exenciones.clase is
  'Que PREGUNTA responde este contador, y por tanto si puede contradecir al nucleo. '
  '`analitica`: mide el PASADO (la cifra del mes, el sello, la produccion) -- cuenta para el techo. '
  '`mixta`: publica la cifra oficial del nucleo Y ademas cuenta por su cuenta -- cuenta para el techo. '
  '`operativo`: INVENTARIO y RASTRO DE FLUJO -- colas, reparto, validacion de un lote, y tambien el '
  'rastro de un periodo (derivaciones del mes, descartados por mes, ingresos al reparto), SIEMPRE que '
  'no publique una TASA ni una cifra de CIERRE. Sigue censado, declarado y con huella vigente, pero no '
  'consume cupo porque no responde la pregunta de la conversion y por tanto no puede darle otra respuesta. '
  '`verificador`: existe para comprobar cifras ajenas y no publica ninguna propia; solo vale para '
  'objetos que el censo ya excluye por identidad exacta y huella -- un sujeto del censo NO puede llevarla.';

-- ---------------------------------------------------------------------------
-- (b bis) EL CANDADO DE LA CLASE. La clase es un trinquete, igual que el tope.
--     Sin esto quedaba un hueco real: reetiquetar un contador de `analitica` a
--     `operativo` y re-sellar la lista haria sitio bajo el techo sin tocar el
--     tope -- el unico camino por el que el trinquete podria ceder sin una
--     migracion. Aqui se cierra: la clase solo puede APRETAR.
-- ---------------------------------------------------------------------------
create or replace function private.trg_analitica_lc_clase_solo_aprieta()
returns trigger language plpgsql security definer set search_path = ''
as $clase$
begin
  --   operativo/verificador -> analitica/mixta      se permite (queda MAS vigilado)
  --   analitica/mixta       -> operativo/verificador se RECHAZA (aflojaria el techo)
  if old.clase in ('analitica','mixta') and new.clase not in ('analitica','mixta') then
    raise exception 'La clase de % no puede aflojar (% -> %): eso haria sitio bajo el techo. Se corrige en una migracion que redefina este candado.',
      old.objeto, old.clase, new.clase using errcode = '42501';
  end if;
  return new;
end;
$clase$;

create trigger trg_analitica_lc_clase_solo_aprieta
  before update of clase on private.analitica_leads_citas_exenciones
  for each row execute function private.trg_analitica_lc_clase_solo_aprieta();

-- ---------------------------------------------------------------------------
-- (c) El sello de la lista pasa a cubrir la clase.
--     Sin esto, reetiquetar de analitica a operativo bajaria el techo en
--     silencio: seria la unica forma de esquivar el trinquete.
-- ---------------------------------------------------------------------------
create or replace function private.huella_exenciones_analitica_lc()
returns text language sql stable security definer set search_path = ''
as $huella$
  -- concat_ws y no `||`: con `||` una clase NULL volveria NULL la fila entera y
  -- string_agg la IGNORA -- esa declaracion desapareceria del sello sin rastro.
  -- Hoy es imposible (NOT NULL), pero el sello no debe depender de eso.
  select md5(string_agg(concat_ws('|', objeto, huella, coalesce(clase,'(sin clase)'), razon),
                        chr(10) order by objeto))
    from private.analitica_leads_citas_exenciones;
$huella$;

-- Re-sello. El valor lo CALCULA LA BASE: un md5 escrito a mano en una migracion
-- es un hallazgo esperando a ocurrir.
update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(),
       sellado_en = now()
 where id;

-- ---------------------------------------------------------------------------
-- (d) El techo baja a la poblacion que de verdad puede contradecir al nucleo.
--     El numero tambien lo calcula la base.
-- ---------------------------------------------------------------------------
update private.analitica_leads_citas_tope
   set tope = (select count(*)
                 from private.contadores_crudos_leads_citas() c
                 join private.analitica_leads_citas_exenciones e on e.objeto = c.objeto
                where c.objeto not in (select objeto from private.auxiliares_analitica_lc_auditados())
                  and e.clase in ('analitica','mixta'))
 where id;

-- ---------------------------------------------------------------------------
-- (e) El assert. Todo lo anterior se conserva palabra por palabra; lo unico
--     que cambia es COMO se cuenta el techo, mas tres controles nuevos sobre
--     la clase.
-- ---------------------------------------------------------------------------
create or replace function private.assert_analitica_leads_citas()
returns text language plpgsql stable security definer set search_path = ''
as $assert$
declare
  v_sin text; v_cad text; v_n integer; v_tope integer; v_total integer; v_auxiliares integer;
  v_operativos integer; v_malaclase text;
begin

  -- El inventario sigue completo. Sólo cuatro definiciones auxiliares conocidas
  -- se descuentan del techo; una deriva de cuerpo/owner/ACL invalida el gate.
  if not exists(select 1 from pg_proc p
    where p.oid=to_regprocedure('private.auxiliares_analitica_lc_auditados()')
      and md5(pg_get_functiondef(p.oid))='e43357800b6d79050c7ca7af6c6844b8'
      and p.proowner='postgres'::regrole
      and (select jsonb_agg(jsonb_build_array(a.grantee::regrole::text,a.privilege_type,a.is_grantable)
        order by a.grantee::regrole::text,a.privilege_type,a.is_grantable)
        from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a)
        ='[["postgres","EXECUTE",false]]'::jsonb) then
    raise exception 'La clasificación fija de auxiliares cambió o tiene permisos indebidos';
  end if;
  if (select array_agg(objeto order by objeto) from private.auxiliares_analitica_lc_auditados())
    is distinct from array['crm.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamp with time zone,uuid)','crm.metricas_multiempresa_fn(date)','private.inversion_historica_aplicar(uuid,jsonb)','private.inversion_historica_estado(text,uuid)']::text[] then
    raise exception 'El conjunto de auxiliares difiere de las cuatro identidades revisadas';
  end if;
  if exists(select 1 from private.auxiliares_analitica_lc_auditados() a
    where not a.vigente or not exists(select 1 from private.contadores_crudos_leads_citas() c
      where c.objeto=a.objeto and c.declarada and c.huella_ok)) then
    raise exception 'Un auxiliar auditado cambió, desapareció o perdió su declaración vigente';
  end if;
  -- Las lecturas acotadas comparten los núcleos, pero tampoco son puertas API.
  if to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])') is null
    or to_regprocedure('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])') is null then
    raise exception 'Desapareció una lectura acotada de los núcleos de Citas/Conversión';
  end if;
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid in (
      'private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'::regprocedure,
      'private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'::regprocedure)
      and a.grantee<>'postgres'::regrole::oid
  ) then raise exception 'Una lectura acotada de Citas/Conversión tiene EXECUTE fuera de postgres'; end if;
  select string_agg(tipo || ' ' || objeto, ', ' order by objeto)
    into v_sin from private.contadores_crudos_leads_citas() where not declarada;
  if v_sin is not null then
    raise exception 'Contadores crudos de leads/citas SIN declarar: %. O beben del nucleo, o se declaran con su razon.', v_sin;
  end if;

  select string_agg(tipo || ' ' || objeto, ', ' order by objeto)
    into v_cad from private.contadores_crudos_leads_citas() where declarada and not huella_ok;
  if v_cad is not null then
    raise exception 'Contadores exentos cuyo cuerpo CAMBIO desde que se declararon (la razon caduco): %', v_cad;
  end if;

  -- LA CLASE (22/09/2026). Toda declaracion nace clasificada y con uno de los
  -- cuatro valores. El CHECK de la tabla ya lo impone; esto lo repite SOBRE EL
  -- DATO a proposito, para que retirar el constraint no deje el gate ciego. Se
  -- comprueba el dato y no el texto del constraint: atarse a como Postgres
  -- reescribe un CHECK es un falso rojo esperando a ocurrir.
  select string_agg(objeto || ' => ' || coalesce(clase,'(sin clase)'), ', ' order by objeto)
    into v_malaclase from private.analitica_leads_citas_exenciones
   where clase is null or clase not in ('analitica','mixta','operativo','verificador');
  if v_malaclase is not null then
    raise exception 'Declaraciones sin clase o con clase desconocida: %', v_malaclase;
  end if;
  if exists (select 1 from pg_attribute a
              where a.attrelid='private.analitica_leads_citas_exenciones'::regclass
                and a.attname='clase' and not a.attnotnull) then
    raise exception 'La columna clase dejo de ser obligatoria: una declaracion podria nacer sin clasificar';
  end if;

  -- 'verificador' describe a quien YA sale del censo por identidad exacta y
  -- huella. Un sujeto DEL CENSO no puede llevarla: seria la unica forma de
  -- esquivar el techo con una etiqueta.
  select string_agg(c.objeto, ', ' order by c.objeto) into v_malaclase
    from private.contadores_crudos_leads_citas() c
    join private.analitica_leads_citas_exenciones e on e.objeto=c.objeto
   where e.clase='verificador';
  if v_malaclase is not null then
    raise exception 'Un contador DEL CENSO se declaro verificador: %. La clase describe, no exime.', v_malaclase;
  end if;

  -- El candado de la clase tiene que seguir puesto y ACTIVO: sin el, aflojar
  -- una etiqueta haria sitio bajo el techo con solo re-sellar la lista.
  if (select count(*) from pg_trigger t
       where t.tgrelid='private.analitica_leads_citas_exenciones'::regclass
         and t.tgname='trg_analitica_lc_clase_solo_aprieta'
         and t.tgenabled in ('O','A')) <> 1 then
    raise exception 'El candado de la clase no esta puesto o no esta activo';
  end if;

  select count(*) into v_total from private.contadores_crudos_leads_citas();
  select count(*) into v_auxiliares from private.auxiliares_analitica_lc_auditados();

  -- EL TECHO MIDE LO QUE PUEDE CONTRADECIR AL NUCLEO: lo que mide el PASADO
  -- (analitica) y lo que publica la cifra oficial ademas de contar por su
  -- cuenta (mixta). El INVENTARIO del ahora sigue censado, declarado y con
  -- huella vigente -- comprobado arriba sobre TODOS los candidatos -- pero no
  -- consume cupo: no responde la pregunta de la conversion, asi que no puede
  -- dar otra respuesta.
  select count(*) filter (where e.clase in ('analitica','mixta')),
         count(*) filter (where e.clase='operativo')
    into v_n, v_operativos
    from private.contadores_crudos_leads_citas() c
    join private.analitica_leads_citas_exenciones e on e.objeto=c.objeto
   where c.objeto not in (select objeto from private.auxiliares_analitica_lc_auditados());

  -- EL CENSO Y LAS DECLARACIONES TIENEN QUE CUADRAR. El conteo nuevo sale de un
  -- INNER JOIN, asi que un sujeto sin fila de exencion no sumaria en NINGUNA
  -- clase: se escurriria del techo en silencio. Hoy no puede pasar porque el
  -- control «SIN declarar» de arriba aborta antes -- pero eso es un argumento
  -- de tres saltos, no un invariante. Aqui se comprueba, para que el techo
  -- siga siendo una red INDEPENDIENTE y no una consecuencia de otra.
  if v_n + v_operativos <> v_total - v_auxiliares then
    raise exception 'El censo y las declaraciones dejaron de cuadrar: % sujetos y % clasificados. Alguien se escurrio del join.',
      v_total - v_auxiliares, v_n + v_operativos;
  end if;

  -- Anti-vacuidad: el tope es techo, no suelo. Un censo que devuelve 0 filas, o
  -- un techo que de pronto no vigila a nadie, es una regresion, no un exito.
  if v_total - v_auxiliares = 0 then
    raise exception 'El censo devolvio 0 contadores: eso es una regresion del censo, no la meta';
  end if;
  if v_n = 0 then
    raise exception 'No queda ningun contador de analitica bajo el techo: eso es una regresion de la clasificacion, no la meta';
  end if;
  select tope into v_tope from private.analitica_leads_citas_tope where id;
  if v_tope is null then raise exception 'No hay tope fijado'; end if;
  if v_n > v_tope then
    raise exception 'Los contadores de analitica subieron de % a %: el trinquete solo deja bajar.', v_tope, v_n;
  end if;

  -- El sello de la lista: si alguien la relavo sin re-sellar, rojo. Desde el
  -- 22/09 el sello INCLUYE LA CLASE, asi que reetiquetar tambien es rojo.
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'La lista de exenciones cambio sin re-sellarse en una migracion';
  end if;

  -- Los candados del tope tienen que seguir puestos y ACTIVOS: sin esto, un
  -- despliegue privilegiado podria deshabilitar el trigger, subir el tope y
  -- dejar el gate verde.
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'private.analitica_leads_citas_tope'::regclass
         and t.tgname in ('trg_analitica_lc_tope_solo_baja','trg_analitica_lc_tope_no_truncar')
         and t.tgenabled in ('O','A')) <> 2 then
    raise exception 'Los candados del tope no estan puestos o no estan activos';
  end if;

  -- Los dos nucleos tienen que seguir vivos y con su forma.
  if to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)') is null then
    raise exception 'El nucleo de citas desaparecio';
  end if;
  if to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)') is null then
    raise exception 'El nucleo de leads desaparecio';
  end if;
  -- Y la pantalla de reuniones tiene que seguir bebiendo del de citas - mirado
  -- SIN comentarios (un `-- citas_episodios` de senuelo no vale).
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure
       and regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
           ~ '\mcitas_episodios\s*\('
  ) then
    raise exception 'La pantalla de reuniones dejo de beber del nucleo de citas';
  end if;

  -- El nucleo devuelve FILAS de toda la empresa (DEFINER): cada llamador tiene
  -- que estar DECLARADO en las exenciones (su declaracion es su puerta escrita).
  if exists (
    select 1 from pg_proc p
     where p.prokind in ('f','p')
       and p.oid <> coalesce(to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)'),0)
       and p.oid <> coalesce(to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'),0)
       and p.oid <> coalesce(to_regprocedure('private.assert_analitica_leads_citas()'),0)
       and p.oid <> coalesce(to_regprocedure('private.contadores_crudos_leads_citas()'),0)
       and regexp_replace(regexp_replace(coalesce(p.prosrc,''),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
           ~ '\m(citas_episodios|conversion_cierres)\s*\('
       and not exists (select 1 from private.analitica_leads_citas_exenciones e
                        where e.objeto = p.oid::regprocedure::text)
  ) then
    raise exception 'Hay un consumidor de citas_episodios o conversion_cierres SIN declarar: los nucleos sirven filas de toda la empresa y cada llamador declara su puerta';
  end if;

  -- El ACL del nucleo, exacto: solo postgres (el mismo patron que
  -- conversion_episodios y capital_episodios). Un grant posterior es rojo.
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = 'private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure
       and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'citas_episodios tiene EXECUTE para alguien mas que postgres';
  end if;

  return 'OK: ' || v_total || ' candidatos declarados y con huella vigente; '
      || v_n || ' de analitica/mixta sujetos al techo ' || v_tope || ', '
      || v_operativos || ' de inventario censados fuera del techo, '
      || v_auxiliares || ' auxiliares verificados, 0 sin declarar';
end;
$assert$;

-- ---------------------------------------------------------------------------
-- (f) POSTFLIGHT: lo que esta migracion se compromete a dejar.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_null integer; v_a integer; v_m integer; v_o integer; v_tope integer; v_ok text;
  v_rebota boolean;
begin
  select count(*) into v_null from private.analitica_leads_citas_exenciones where clase is null;
  if v_null <> 0 then
    raise exception 'POSTFLIGHT: quedaron % declaraciones sin clase (nombre mal escrito en la lista)', v_null;
  end if;

  select count(*) filter (where e.clase='analitica'),
         count(*) filter (where e.clase='mixta'),
         count(*) filter (where e.clase='operativo')
    into v_a, v_m, v_o
    from private.contadores_crudos_leads_citas() c
    join private.analitica_leads_citas_exenciones e on e.objeto=c.objeto
   where c.objeto not in (select objeto from private.auxiliares_analitica_lc_auditados());
  if (v_a, v_m, v_o) is distinct from (11, 3, 16) then
    raise exception 'POSTFLIGHT: el reparto esperado era 11 analitica / 3 mixta / 16 operativo y salio % / % / %', v_a, v_m, v_o;
  end if;

  select tope into v_tope from private.analitica_leads_citas_tope where id;
  if v_tope <> 14 then
    raise exception 'POSTFLIGHT: el tope esperado era 14 y quedo en %', v_tope;
  end if;

  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT: la lista quedo des-sellada';
  end if;

  -- Las cuatro declaraciones de fuera del censo, en su sitio.
  select count(*) filter (where e.clase='verificador'),
         count(*) filter (where e.clase='mixta'),
         count(*) filter (where e.clase='operativo')
    into v_a, v_m, v_o
    from private.analitica_leads_citas_exenciones e
   where not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto=e.objeto);
  if (v_a, v_m, v_o) is distinct from (2, 1, 1) then
    raise exception 'POSTFLIGHT: fuera del censo se esperaban 2 verificador / 1 mixta / 1 operativo y hay % / % / %', v_a, v_m, v_o;
  end if;

  -- El contrato de seguridad de las dos funciones recreadas, INTACTO: mismo
  -- dueno, mismo ACL, definer, stable y search_path vacio.
  select string_agg(a.fn, ', ') into v_ok
    from _contrato_fn_antes a
    join pg_proc p on p.oid = a.fn::regprocedure
   where (p.proowner::regrole::text, p.prosecdef, p.provolatile,
          coalesce(p.proacl, acldefault('f', p.proowner))::text)
         is distinct from (a.duenio, a.prosecdef, a.provolatile, a.acl)
      or p.proconfig is distinct from a.proconfig;
  if v_ok is not null then
    raise exception 'POSTFLIGHT: el contrato (dueno/ACL/definer/volatilidad/search_path) cambio en: %', v_ok;
  end if;
  if exists (select 1 from pg_proc p
              where p.oid in ('private.assert_analitica_leads_citas()'::regprocedure,
                              'private.huella_exenciones_analitica_lc()'::regprocedure)
                and not (p.prosecdef and p.provolatile='s'
                         and p.proconfig @> array['search_path=""'])) then
    raise exception 'POSTFLIGHT: una de las dos funciones no quedo definer + stable + search_path vacio';
  end if;

  -- El candado no se da por puesto: se PRUEBA que rebota. Si dejara pasar el
  -- cambio, el `raise` de abajo deshace la migracion entera.
  v_rebota := false;
  begin
    update private.analitica_leads_citas_exenciones set clase='operativo'
     where objeto='crm.cerrar_periodo(date)';
  exception when others then v_rebota := true;
  end;
  if not v_rebota then
    raise exception 'POSTFLIGHT: el candado de la clase dejo aflojar una analitica a operativo';
  end if;

  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el gate no quedo verde: %', v_ok;
  end if;
  raise notice 'POSTFLIGHT %', v_ok;
end;
$postflight$;

commit;
