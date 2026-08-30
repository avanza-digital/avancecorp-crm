-- P-055 Fase 6.a - EL NUCLEO DE CITAS y EL CENSO SELLADO de contadores.
--
-- QUE, en una linea: nace la calculadora unica de CITAS
-- (`private.citas_episodios`), la pantalla de reuniones pasa a beber de ella, y
-- TODO contador crudo de leads o citas queda o convertido o DECLARADO por
-- escrito con su razon y sellado por huella - con trinquete, vigia y gate, como
-- el capital (F4) y la autoridad (F5.a).
--
-- AUTORIZACION DE MIGUEL (30/08): arranco la Fase 6 con su objetivo fijado por
-- /goal - "que cada pregunta sobre leads y citas tenga una sola respuesta en
-- todo el sistema" - y las 5 decisiones del contrato firmadas en el vault
-- («Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)»).
--
-- LO QUE LA MEDICION DEL 30/08 CAMBIO DEL PLAN (todo verificado en vivo):
--   · El nucleo de LEADS ya existia (`private.conversion_episodios`, de la
--     «conversion unica») y las pantallas de metricas ya beben de el, directa o
--     transitivamente: el SELLO pasa por `conversion_mensual_por_vendedor` ->
--     nucleo; `metricas_vendedores_fn` lee `crm.conversion_mensual_fn`.
--   · La ventana de 45 dias de vendedores/cartera es de la VISTA (que
--     convertidos siguen visibles), NO de la metrica: la metrica ya es mensual
--     y esta rotulada (`ventana_metrica: mes_calendario`). La decision 5 del
--     contrato queda cumplida EN LA METRICA; la vista no se toca.
--   · Para CITAS no habia nucleo: la definicion canonica vivia INCRUSTADA en
--     `private.metricas_reuniones_implementacion`. Aqui se EXTRAE literal.
--   · 30 objetos cuentan leads/citas en crudo. Los que responden OTRA pregunta
--     (vista, actividad del periodo, inventario operativo, roster, sello) se
--     DECLARAN con razon; nada pasa en silencio.
--
-- PARIDAD YA ENSAYADA (30/08, transaccion deshecha): el resumen de agosto
-- recalculado solo desde el nucleo = el vivo 11/11 campos; y la pantalla de
-- reuniones ENTERA convertida = payload identico byte a byte (6 011 bytes).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: anclas por huella (cuerpo SIN comentarios, la misma
--    normalizacion que usa el censo).
-- =====================================================================
do $$
declare v_h text;
begin
  select md5(regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
    into v_h from pg_proc p
   where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  if v_h is distinct from 'b2afc1ef6e48d95f6547cfc91b8885d9' then
    raise exception 'F6.a preflight: metricas_reuniones_implementacion cambio desde la medicion (huella %)', v_h;
  end if;

  if to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)') is not null then
    raise exception 'F6.a preflight: private.citas_episodios ya existe';
  end if;
  if to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)') is null then
    raise exception 'F6.a preflight: falta el nucleo de leads (conversion_episodios)';
  end if;
end $$;

-- =====================================================================
-- 1) EL NUCLEO DE CITAS.
-- =====================================================================
-- Una fila por cita (tarea tipo reunion, viva) con TODAS las banderas que hoy
-- viven incrustadas en la pantalla de reuniones. Extraccion LITERAL: mismas
-- expresiones, mismo huso. Decision firmada: la cita anulada QUEDA (pactadas la
-- incluye y tiene columna propia).
create or replace function private.citas_episodios(
  p_ini timestamptz,
  p_fin timestamptz,
  p_ahora timestamptz default now()
)
returns table (
  tarea_id uuid,
  lead_id uuid,
  vendedor_id uuid,
  cancelada_por_id uuid,
  vence_en timestamptz,
  estado text,
  modalidad text,
  resultado text,
  debio_ocurrir boolean,
  realizada boolean,
  no_show boolean,
  cancelada_asesor boolean,
  cancelada_sistema boolean,
  reprogramada boolean,
  pendiente_cierre boolean,
  programada_futura boolean
)
language sql
stable
security definer
set search_path to ''
as $function$
  select t.id,
         t.lead_id,
         t.vendedor_id,
         t.cancelada_por_id,
         t.vence_en,
         t.estado,
         coalesce(t.modalidad_reunion, 'sin_clasificar'),
         coalesce(t.resultado_reunion, 'sin_clasificar'),
         t.vence_en <= p_ahora,
         t.estado = 'completada',
         t.estado = 'no_show',
         (t.estado = 'cancelada' and t.cancelada_por = 'asesor'),
         (t.estado = 'cancelada' and t.cancelada_por is distinct from 'asesor'),
         t.estado = 'reprogramada',
         (t.estado = 'pendiente' and t.vence_en <= p_ahora),
         (t.estado = 'pendiente' and t.vence_en > p_ahora)
  from crm.tareas t
  where t.tipo = 'reunion'
    and t.activo
    and t.vence_en >= p_ini
    and t.vence_en < p_fin;
$function$;

comment on function private.citas_episodios(timestamptz, timestamptz, timestamptz) is
  'P-055 F6.a. La calculadora unica de citas: una fila por cita con sus banderas canonicas. Toda metrica de citas por VENCIMIENTO bebe de aqui; contar citas a crudo exige declaracion en private.analitica_leads_citas_exenciones.';

revoke all on function private.citas_episodios(timestamptz, timestamptz, timestamptz) from public;

-- =====================================================================
-- 2) LA PANTALLA DE REUNIONES BEBE DEL NUCLEO (reemplazo anclado, 4 anclas;
--    paridad de payload ENTERO ya ensayada: identico byte a byte).
-- =====================================================================
do $$
declare
  v_def text; v_veces integer; v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure;

  v_ancla := $a$t.vence_en <= v_ahora as metrica_debio_ocurrir,
      t.estado = 'completada' as metrica_realizada,
      t.estado = 'no_show' as metrica_no_show,
      (t.estado = 'cancelada' and t.cancelada_por = 'asesor')
        as metrica_cancelada_asesor,
      (t.estado = 'cancelada' and t.cancelada_por is distinct from 'asesor')
        as metrica_cancelada_sistema,
      t.estado = 'reprogramada' as metrica_reprogramada,
      (t.estado = 'pendiente' and t.vence_en <= v_ahora)
        as metrica_pendiente_cierre,
      (t.estado = 'pendiente' and t.vence_en > v_ahora)
        as metrica_programada_futura$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.a: ancla 1 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$ce.debio_ocurrir as metrica_debio_ocurrir,
      ce.realizada as metrica_realizada,
      ce.no_show as metrica_no_show,
      ce.cancelada_asesor as metrica_cancelada_asesor,
      ce.cancelada_sistema as metrica_cancelada_sistema,
      ce.reprogramada as metrica_reprogramada,
      ce.pendiente_cierre as metrica_pendiente_cierre,
      ce.programada_futura as metrica_programada_futura$b$);

  v_ancla := $a$coalesce(t.modalidad_reunion, 'sin_clasificar') as modalidad,$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.a: ancla 2 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, 'ce.modalidad as modalidad,');

  v_ancla := $a$from crm.tareas t
    left join crm.leads l on l.id = t.lead_id$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.a: ancla 3 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$from private.citas_episodios(v_ini, v_fin, v_ahora) ce
    join crm.tareas t on t.id = ce.tarea_id
    left join crm.leads l on l.id = t.lead_id$b$);

  -- El ancla se lleva TAMBIEN el salto y la sangria previos: si no, queda una
  -- linea huerfana de espacios y la marcha atras no vuelve al byte.
  v_ancla := e'\n    ' || $a$where t.tipo = 'reunion' and t.activo
      and t.vence_en >= v_ini and t.vence_en < v_fin$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F6.a: ancla 4 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, '');

  execute v_def;
end $$;

-- =====================================================================
-- 3) EL CENSO Y LAS EXENCIONES SELLADAS.
-- =====================================================================
create table if not exists private.analitica_leads_citas_exenciones (
  objeto       text primary key,
  tipo         text not null,
  huella       text not null,
  razon        text not null,
  declarado_en timestamptz not null default now(),
  constraint tipo_conocido check (tipo in ('funcion','vista')),
  constraint razon_de_verdad check (length(btrim(razon)) >= 40)
);
alter table private.analitica_leads_citas_exenciones enable row level security;
comment on table private.analitica_leads_citas_exenciones is
  'P-055 F6.a. Objetos que cuentan leads o citas EN CRUDO a proposito, por identidad exacta y con la huella del cuerpo (sin comentarios) al declararlos: si el cuerpo cambia, la razon caduca y el gate se pone rojo. Sin pases automaticos: tambien los consumidores mixtos del nucleo se declaran.';

create table if not exists private.analitica_leads_citas_tope (
  id             boolean primary key default true,
  tope           integer not null,
  actualizado_en timestamptz not null default now(),
  constraint una_sola_fila check (id is true),
  constraint tope_no_negativo check (tope >= 0)
);
alter table private.analitica_leads_citas_tope enable row level security;

create or replace function private.trg_analitica_lc_tope_solo_baja()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'La fila del tope no se borra: borrarla y reinsertarla reiniciaria el trinquete.' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.tope > old.tope then
    raise exception 'El tope de contadores crudos solo puede BAJAR (% -> %).', old.tope, new.tope using errcode = '42501';
  end if;
  new.actualizado_en := now();
  return new;
end;
$function$;

drop trigger if exists trg_analitica_lc_tope_solo_baja on private.analitica_leads_citas_tope;
create trigger trg_analitica_lc_tope_solo_baja
  before update or delete on private.analitica_leads_citas_tope
  for each row execute function private.trg_analitica_lc_tope_solo_baja();

create or replace function private.trg_analitica_lc_tope_no_truncar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception 'La tabla del tope no se vacia.' using errcode = '42501';
end;
$function$;

drop trigger if exists trg_analitica_lc_tope_no_truncar on private.analitica_leads_citas_tope;
create trigger trg_analitica_lc_tope_no_truncar
  before truncate on private.analitica_leads_citas_tope
  for each statement execute function private.trg_analitica_lc_tope_no_truncar();

-- El censo: quien cuenta leads o citas EN CRUDO. Mide LLAMADAS, no texto:
-- comentarios fuera antes de mirar, ancla con inicio de palabra, y SIN pase
-- automatico por "usa el nucleo" (un mixto tambien se declara). Los dos nucleos
-- y las piezas del propio trinquete se excluyen por identidad/nombre.
create or replace function private.contadores_crudos_leads_citas()
returns table (tipo text, objeto text, declarada boolean, huella_ok boolean)
language sql
stable
security definer
set search_path to ''
as $function$
  with fn as (
    -- TODOS los esquemas de usuario (fail-closed: lo del sistema se excluye por
    -- lista, no al reves - un esquema nuevo entra al censo solo); el cuerpo
    -- viene de prosrc O de pg_get_functiondef (funciones con prosqlbody);
    -- la exclusion de los nucleos y de las piezas del trinquete es por
    -- IDENTIDAD exacta, no por nombre (un overload malicioso no se cuela).
    select 'funcion'::text as tipo,
           p.oid::regprocedure::text as objeto,
           regexp_replace(regexp_replace(
             lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
             '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g') as cuerpo
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where p.prokind in ('f','p')
       and n.nspname not in ('pg_catalog','information_schema','pg_toast',
                             'auth','storage','vault','realtime','extensions',
                             'graphql','graphql_public','pgbouncer','net',
                             'supabase_functions','supabase_migrations','cron','pgsodium')
       and n.nspname not like 'pg\_%'
       and p.oid not in (
             coalesce(to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)')::oid, 0),
             coalesce(to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)')::oid, 0),
             coalesce(to_regprocedure('private.contadores_crudos_leads_citas()')::oid, 0),
             coalesce(to_regprocedure('private.assert_analitica_leads_citas()')::oid, 0))
  ),
  vw as (
    select 'vista'::text,
           c.relnamespace::regnamespace::text || '.' || c.relname,
           lower(pg_get_viewdef(c.oid))
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where c.relkind in ('v','m')
       and n.nspname not in ('pg_catalog','information_schema','pg_toast',
                             'auth','storage','vault','realtime','extensions',
                             'graphql','graphql_public','pgbouncer','net',
                             'supabase_functions','supabase_migrations','cron','pgsodium')
       and n.nspname not like 'pg\_%'
  ),
  todo as (select * from fn union all select * from vw),
  crudos as (
    -- Insensible a mayusculas (el cuerpo va en lower), tolera espacio tras el
    -- punto (un comentario borrado deja hueco: `crm. leads`), y caza tambien
    -- `sum(` ademas de `count(`. El SQL dinamico que nombre leads/tareas se
    -- censa entero: si su conteo no es demostrable, se declara.
    select t.tipo, t.objeto, md5(t.cuerpo) as huella
      from todo t
     where (t.cuerpo ~ '\mcrm\.\s*leads\M'
            or t.cuerpo ~ '\mreunion'
            or (t.cuerpo ~ '\mcrm\.\s*tareas\M' and t.cuerpo ~ '\mexecute\M'))
       and (t.cuerpo ~ '\mcount\s*\(' or t.cuerpo ~ '\msum\s*\(\s*1\s*\)')
  )
  select cr.tipo,
         cr.objeto,
         (e.objeto is not null) as declarada,
         (e.objeto is not null and e.huella = cr.huella) as huella_ok
    from crudos cr
    left join private.analitica_leads_citas_exenciones e on e.objeto = cr.objeto
   order by 3, 4, 1, 2;
$function$;

revoke all on function private.contadores_crudos_leads_citas() from public;

-- El gate ENTERO vive aqui: el vigia por cron (`crm-analitica-lc-vigia`, 06:49),
-- el guion del repo (`npm run gate:analitica`), el postflight y el mutante
-- ejecutan ESTA MISMA funcion.
create or replace function private.assert_analitica_leads_citas()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_sin text; v_cad text; v_n integer; v_tope integer;
begin
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

  select count(*) into v_n from private.contadores_crudos_leads_citas();
  -- Anti-vacuidad: el tope es techo, no suelo. Un censo que devuelve 0 filas es
  -- una regresion del propio censo, no un exito.
  if v_n = 0 then
    raise exception 'El censo devolvio 0 contadores: eso es una regresion del censo, no la meta';
  end if;
  select tope into v_tope from private.analitica_leads_citas_tope where id;
  if v_tope is null then raise exception 'No hay tope fijado'; end if;
  if v_n > v_tope then
    raise exception 'Los contadores crudos subieron de % a %: el trinquete solo deja bajar.', v_tope, v_n;
  end if;

  -- El sello de la lista: si alguien la relavo sin re-sellar, rojo.
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
       and p.oid <> coalesce(to_regprocedure('private.assert_analitica_leads_citas()'),0)
       and p.oid <> coalesce(to_regprocedure('private.contadores_crudos_leads_citas()'),0)
       and regexp_replace(regexp_replace(coalesce(p.prosrc,''),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
           ~ '\mcitas_episodios\s*\('
       and not exists (select 1 from private.analitica_leads_citas_exenciones e
                        where e.objeto = p.oid::regprocedure::text)
  ) then
    raise exception 'Hay un consumidor de citas_episodios SIN declarar: el nucleo sirve filas de toda la empresa y cada llamador declara su puerta';
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

  return 'OK: ' || v_n || ' contadores declarados y con su huella intacta, tope ' || v_tope || ', 0 sin declarar';
end;
$function$;

revoke all on function private.assert_analitica_leads_citas() from public;

comment on function private.assert_analitica_leads_citas() is
  'P-055 F6.a. El trinquete de la analitica de leads y citas. Devuelve una FILA con el veredicto y revienta si nace un contador crudo sin declarar, si un exento cambia de cuerpo, si un nucleo desaparece o si la pantalla de reuniones deja de beber del nucleo.';

-- Las exenciones: la huella se toma del cuerpo VIVO al declarar (post-conversion
-- donde aplica). Cada razon dice QUE OTRA PREGUNTA responde ese contador.
with razones(objeto, razon) as (values
  ('crm.agenda_reparto_diaria(date,integer)',
   'Operativa de reparto: cuenta la carga del dia para proponer la agenda; es inventario del momento, no una metrica historica de leads.'),
  ('crm.cerrar_periodo(date)',
   'El MOTOR DEL SELLO: su conversion viene de conversion_mensual_por_vendedor, que bebe del nucleo (transitividad verificada el 30/08); sus counts propios son cobertura del ledger (suelo, mes parcial), no otra conversion.'),
  ('crm.cierres_externos_fn(date)',
   'Lista las cooperativas del mes para gerencia: es un listado operativo con su conteo de apoyo, no una calculadora de conversion; el capital de coops ya vive en capital_episodios.'),
  ('crm.cola_accion_fn(integer)',
   'La cola de accion del vendedor: cuenta lo pendiente AHORA (inventario de trabajo), no responde ninguna pregunta historica de metricas.'),
  ('crm.conversion_mensual_sin_cartera_fn(date)',
   'Nucleo por TRANSITIVIDAD (llama a conversion_mensual_por_vendedor): sirve el mes sellado desde las tablas del cierre y, con el mes ABIERTO, calcula en vivo por el mismo puente; sus counts propios son cobertura y altas del periodo.'),
  ('crm.derivar_leads_equipo_fn(uuid[],uuid[])',
   'Operativa de derivacion: cuenta para validar el lote que se deriva y dejar rastro; no es una pregunta de metricas.'),
  ('crm.guardar_agenda_reparto_diaria(date,uuid,uuid)',
   'Operativa de reparto: valida y persiste la agenda del dia; sus counts son de consistencia del lote, no metricas.'),
  ('crm.impacto_desactivacion_usuario_fn(uuid)',
   'Previa de offboarding: cuenta que dejaria huerfano una desactivacion (leads, tareas) como inventario del momento; no es metrica historica.'),
  ('crm.ingresos_reparto_mes_fn(date)',
   'Panel de reparto: cuenta ingresos de leads del mes al reparto (inventario de flujo de entrada), pregunta distinta de la conversion.'),
  ('crm.metricas_conversiones_equipo_fn(date,date)',
   'MIXTA: la conversion sale del nucleo; sus counts crudos son los numeros del RANKING por vendedor (leads y clientes de la cohorte de entrada), pregunta de flujo distinta de la conversion mensual; el rotulo del front se afina en la F6.b.'),
  ('crm.metricas_sla_fn(date,date)',
   'Mide TIEMPOS de etapas (SLA), no cuantas citas o leads hay: sus counts agrupan hitos de SLA por etapa, incluida la etapa de reunion.'),
  ('crm.metricas_vendedores_fn()',
   'MIXTA: la metrica es MENSUAL y viene de crm.conversion_mensual_fn (nucleo por transitividad), rotulada ventana_metrica=mes_calendario; sus counts crudos son la VISTA de 45 dias (que convertidos siguen visibles en cartera) y estan rotulados como vista.'),
  ('crm.panel_distribucion_reparto(uuid,uuid,text,boolean)',
   'Panel operativo del reparto: cuenta lo repartible AHORA por supervisor; inventario del momento, no metrica historica.'),
  ('crm.reporte_derivaciones_equipo_fn(date,date)',
   'Reporte operativo de derivaciones: cuenta derivaciones y su estado en el periodo; es el rastro del reparto, no una calculadora de conversion.'),
  ('crm.rescatar_descartes(uuid[],uuid[],boolean)',
   'Operativa de rescate: valida el lote de descartados que se rescata; sus counts son de consistencia, no metricas.'),
  ('crm.rescate_descartes_meses()',
   'Apoyo del rescate: cuenta descartados por mes para elegir de donde rescatar; inventario operativo, no metrica de conversion.'),
  ('crm.resumen_cartera_fn()',
   'MIXTA: convertidos y operaciones del MES salen del nucleo (F2.4/D1); sus counts crudos son la VISTA de 45 dias (embudo, capital estimado, % espejo del front) y estan rotulados como vista.'),
  ('crm.resumen_reparto_fn()',
   'Resumen operativo del reparto: cuenta lo por repartir AHORA; inventario del momento.'),
  ('crm.resumen_tareas_fn()',
   'Resumen de tareas del vendedor: cuenta pendientes y vencidas AHORA (citas incluidas como carga de trabajo); inventario, no metrica de citas por vencimiento.'),
  ('crm.series_comerciales_fn(integer)',
   'MIXTA CON DEUDA: los cierres salen del nucleo, PERO su conversion_pct es una SEGUNDA formula - cohorte por mes de entrada SIN peso de referido, calculada aqui en crudo (2,8 pct vs 7,0 pct del nucleo en agosto, medido). Deuda declarada del Bloque B: convertirla o renombrar la clave a conversion_cohorte.'),
  ('private.contratos_afectados_por_anulacion(uuid)',
   'Operativa de la anulacion: localiza contratos/leads afectados para retroceder etapa; no responde preguntas de metricas.'),
  ('private.metricas_agenda_implementacion(date,date)',
   'Cuenta ACTIVIDAD del periodo (tareas cerradas por actualizado_en, creadas por creado_en, foto de pendientes): que HIZO el vendedor en el periodo, pregunta deliberadamente distinta de que citas VENCIAN (esa la responde el nucleo). Hallazgo D8 documentado.'),
  ('private.metricas_conversiones_implementacion(date,date,text)',
   'MIXTA: la conversion mensual bebe del nucleo. PERO su bloque de citas cuenta LEADS DEL PERIODO CON ALGUNA CITA (embudo de cohorte), no citas: es OTRA pregunta que el front rotula mal como citas pactadas/realizadas (83/7 vs 40/6 medido el 30/08). La correccion es de ROTULO y va en la F6.b del front; el numero es correcto para su pregunta.'),
  ('private.metricas_distribucion_leads_core(date,date,timestamp with time zone)',
   'MIXTA: la conversion sale del nucleo; sus counts crudos miden el REPARTO del periodo (cuantos entraron y a quien) y el embudo de cohorte por lead - preguntas de flujo de entrada, distintas de la conversion mensual y de las citas por vencimiento; el rotulo del front las nombra sin apellido y se corrige en la F6.b.'),
  ('private.metricas_reuniones_implementacion(date,date)',
   'CONSUME LOS DOS NUCLEOS (citas_episodios para banderas, conversion_episodios para cierres): sus counts agregan filas ya servidas por los nucleos, no calculan a crudo.'),
  ('private.metricas_sla_global_core(date,date,timestamp with time zone)',
   'Mide TIEMPOS de etapas (SLA global), no cuantas citas o leads: counts de hitos por etapa.'),
  ('private.produccion_mes_por_vendedor(timestamp with time zone,timestamp with time zone,uuid)',
   'Consumidor del nucleo de CAPITAL (F4): su join a crm.leads es para atribuir episodios, no para contar leads como metrica.'),
  ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',
   'CON DEUDA: el capital sale de capital_episodios, PERO el numerador del ajuste se recalcula LOCALMENTE (peso_referido a mano) y su rama de coops replica condicion por condicion a produccion_mes_por_vendedor. Deuda declarada del Bloque B: que beba del puente del sello.'),
  ('private.supervisores_para_reparto_implementacion()',
   'Apoyo del reparto: cuenta la carga actual por supervisor para proponer destino; inventario del momento.'),
  ('private.trg_leads_asignaciones()',
   'Trigger del LEDGER de asignaciones: sus counts mantienen la secuencia y la consistencia del ledger que alimenta al nucleo; es la fuente, no un consumidor.')
)
insert into private.analitica_leads_citas_exenciones (objeto, tipo, huella, razon)
select c.objeto, c.tipo,
       case c.tipo
         -- Por to_regprocedure, INMUNE al search_path de la sesion (la trampa
         -- conocida: ::text cualifica o no segun el search_path); la huella con
         -- la MISMA normalizacion del censo (lower + sin comentarios).
         when 'funcion' then
           (select md5(regexp_replace(regexp_replace(
                    lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                    '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
              from pg_proc p where p.oid = to_regprocedure(c.objeto))
         else md5(lower(pg_get_viewdef(c.objeto::regclass)))
       end,
       r.razon
  from private.contadores_crudos_leads_citas() c
  join razones r on r.objeto = c.objeto
on conflict (objeto) do update set huella = excluded.huella, razon = excluded.razon;

-- Candado y SELLO de la lista de exenciones (leccion F1.6: una lista blanca sin
-- sello se relava sin que el gate se entere). El sello es el md5 del agregado
-- ordenado objeto||huella||razon y SOLO una migracion que lo re-selle puede
-- tocar la lista.
create or replace function private.trg_analitica_lc_exenciones_no_borrar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception 'Una exencion no se borra por fuera: se retira en una migracion que re-selle la lista.' using errcode = '42501';
  return null;
end;
$function$;

drop trigger if exists trg_analitica_lc_exenciones_no_borrar on private.analitica_leads_citas_exenciones;
create trigger trg_analitica_lc_exenciones_no_borrar
  before delete or truncate on private.analitica_leads_citas_exenciones
  for each statement execute function private.trg_analitica_lc_exenciones_no_borrar();

create table if not exists private.analitica_lc_sello (
  id boolean primary key default true,
  sello text not null,
  sellado_en timestamptz not null default now(),
  constraint una_sola_fila check (id is true)
);
alter table private.analitica_lc_sello enable row level security;

create or replace function private.huella_exenciones_analitica_lc()
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select md5(string_agg(objeto || '|' || huella || '|' || razon, chr(10) order by objeto))
    from private.analitica_leads_citas_exenciones;
$function$;
revoke all on function private.huella_exenciones_analitica_lc() from public;

-- El tope se fija con el censo de HOY y solo puede bajar.
insert into private.analitica_leads_citas_tope (id, tope)
select true, (select count(*) from private.contadores_crudos_leads_citas())
on conflict (id) do update
  set tope = least(private.analitica_leads_citas_tope.tope, excluded.tope);

insert into private.analitica_lc_sello (id, sello)
select true, private.huella_exenciones_analitica_lc()
on conflict (id) do update set sello = excluded.sello, sellado_en = now();

-- =====================================================================
-- 4) EL VIGIA - con su tabla de alertas PROPIA.
-- =====================================================================
-- 🔴 P0 de la auditoria RLS: el borrador escribia en `crm.audit_log`, que NO
-- EXISTE (la real es `public.audit_log` y con otras columnas). Como el insert
-- vive dentro del `exception`, todo parecia verde... hasta la primera alerta
-- real, que habria reventado SIN guardarse en ninguna parte. Y el vigia de la
-- F5.a (`vigia_analista_vigencia`) tiene el MISMO defecto vivo en produccion:
-- se repara aqui tambien.
create table if not exists private.vigia_alertas (
  id          uuid primary key default gen_random_uuid(),
  fase        text not null,
  motivo      text not null,
  creado_en   timestamptz not null default now(),
  resuelta_en timestamptz
);
alter table private.vigia_alertas enable row level security;
comment on table private.vigia_alertas is
  'P-055. Alertas de los vigias de trinquete (F5.a vigencia, F6.a analitica). Deny-by-default: la lee quien opere como postgres/service_role.';

create or replace function private.vigia_analitica_leads_citas()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  begin
    perform private.assert_analitica_leads_citas();
  exception when others then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6a_analitica_leads_citas', sqlerrm);
  end;
end;
$function$;

revoke all on function private.vigia_analitica_leads_citas() from public;

-- El vigia de la F5.a, reparado con la misma tabla (defecto identico, vivo).
create or replace function private.vigia_analista_vigencia()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  begin
    perform private.assert_analista_vigencia();
  exception when others then
    insert into private.vigia_alertas (fase, motivo)
    values ('f5a_analista_vigencia', sqlerrm);
  end;
end;
$function$;

revoke all on function private.vigia_analista_vigencia() from public;

do $$
declare v_jobid bigint;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('crm-analitica-lc-vigia')
      where exists (select 1 from cron.job where jobname = 'crm-analitica-lc-vigia');
    v_jobid := cron.schedule('crm-analitica-lc-vigia', '49 6 * * *',
                             'select private.vigia_analitica_leads_citas()');
    if not exists (select 1 from cron.job where jobname = 'crm-analitica-lc-vigia' and active) then
      raise exception 'F6.a: el vigia no quedo activo';
    end if;
  else
    raise exception 'F6.a: falta pg_cron y el trinquete se quedaria sin vigia';
  end if;
end $$;

-- =====================================================================
-- 5) POSTFLIGHT.
-- =====================================================================
do $$
declare v_veredicto text; v_src text;
begin
  -- La pantalla de reuniones quedo convertida de verdad: bebe del nucleo y no
  -- conserva ninguna bandera cruda.
  select regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
    into v_src from pg_proc p
   where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  if strpos(v_src, 'citas_episodios') = 0 then
    raise exception 'F6.a postflight: la pantalla de reuniones no bebe del nucleo';
  end if;
  if v_src ~ $r$t\.estado\s*=\s*'completada'\s+as\s+metrica$r$ then
    raise exception 'F6.a postflight: la pantalla conserva banderas crudas';
  end if;

  -- Permisos: nada de la fase al alcance de PUBLIC o anon.
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid in ('private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure,
                     'private.contadores_crudos_leads_citas()'::regprocedure,
                     'private.assert_analitica_leads_citas()'::regprocedure,
                     'private.vigia_analitica_leads_citas()'::regprocedure)
       and a.privilege_type = 'EXECUTE'
       and a.grantee in (0, 'anon'::regrole::oid)
  ) then
    raise exception 'F6.a postflight: alguna funcion quedo abierta a PUBLIC o anon';
  end if;

  -- Las dos tablas con RLS (deny-by-default).
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'private'
         and c.relname in ('analitica_leads_citas_exenciones','analitica_leads_citas_tope')
         and c.relrowsecurity) <> 2 then
    raise exception 'F6.a postflight: las tablas del trinquete quedaron sin RLS';
  end if;

  if not exists (select 1 from cron.job where jobname = 'crm-analitica-lc-vigia' and active) then
    raise exception 'F6.a postflight: el vigia no quedo activo';
  end if;

  -- Y el trinquete, ejecutado de verdad.
  select private.assert_analitica_leads_citas() into v_veredicto;
  if v_veredicto not like 'OK:%' then
    raise exception 'F6.a postflight: el trinquete no dio OK: %', v_veredicto;
  end if;
end $$;

commit;
