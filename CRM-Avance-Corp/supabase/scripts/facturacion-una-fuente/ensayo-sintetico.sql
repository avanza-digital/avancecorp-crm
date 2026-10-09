-- SOLO banco vacío a paridad, como postgres. psql -X -v ON_ERROR_STOP=1 -f <archivo>.
-- Siembra propia, migración íntegra, cuatro mutantes, verja sin llamada y reversa.
-- Los marcadores de huella deben medirse antes; nunca se omite el POSTFLIGHT.
-- Sin COMMIT ni apagado de triggers: TODO termina en ROLLBACK.
\set ON_ERROR_STOP on
begin;
-- READ COMMITTED a propósito, no el REPEATABLE READ de la migración: la siembra da de alta personas y el trigger de
-- identidad unificada lo exige («requiere READ COMMITTED»). En un banco propio no hay escrituras concurrentes, así que
-- la foto de antes y la de después ven los mismos datos igual que en la migración.
set local lock_timeout = '10s';
set local statement_timeout = '180s';
do $guardia$
begin
  if (current_user = 'postgres' and current_setting('session_replication_role') = 'origin'
      and not exists (select 1 from public.contratos)
      and not exists (select 1 from crm.cierres_externos)) is not true then
    raise exception 'ENSAYO: solo banco vacío, postgres y triggers encendidos';
  end if;
  if ((select md5(pg_get_functiondef(to_regprocedure('crm.facturacion_diaria_fn(date)'))))
      = '4b11e1da336f2f296c81f064ce30e35b') is not true then
    raise exception 'ENSAYO: comenzar con la puerta viva, antes de migrar';
  end if;
end $guardia$;
do $siembra$
declare
  v_g uuid := gen_random_uuid();
  v_d uuid := gen_random_uuid();
  v_s1 uuid := gen_random_uuid();
  v_s2 uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_cliente uuid := gen_random_uuid();
  v_persona uuid := gen_random_uuid();
  v_lead uuid := gen_random_uuid();
  v_cierre uuid := gen_random_uuid();
  v_fila record;
  v_id uuid;
  v_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mes date := (v_actual - interval '1 month')::date;
begin
  if (not exists (select 1 from crm.periodos_cerrados where periodo in (v_mes, v_actual))) is not true then
    raise exception 'ENSAYO: preparar banco con mes actual y anterior abiertos; no se alteran sellos';
  end if;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('crm.op_privilegiada', 'on', true);
  for v_fila in select * from (values
    (v_g, 'GERENCIA', 'admin'), (v_d, 'DIRECTORIO', 'directorio'),
    (v_s1, 'SUPERVISOR UNO', 'comercial'), (v_s2, 'SUPERVISOR DOS', 'comercial'),
    (v_a, 'ANALISTA HISTORIA', 'comercial'), (v_b, 'ANALISTA CAIDA', 'comercial'),
    (v_cliente, 'CLIENTE', 'cliente')
  ) personas(id, nombre, rol) loop
    insert into auth.users(id, email) values (v_fila.id, v_fila.id::text || '@facturacion-3a.test');
    insert into public.perfiles(id, nombre_completo, correo, rol, activo, tipo_documento,
      debe_cambiar_password, titular_distinto, titular_distinto_usd)
    values (v_fila.id, 'ENSAYO 3A ' || v_fila.nombre, v_fila.id::text || '@facturacion-3a.test',
      v_fila.rol, true, 'DNI', false, false, false);
  end loop;
  insert into crm.equipo(perfil_id, rol_crm, activo) values
    (v_g, 'gerencia', true), (v_d, 'directorio', true),
    (v_s1, 'supervisor', true), (v_s2, 'supervisor', true);
  insert into crm.equipo(perfil_id, rol_crm, supervisor_id, activo) values
    (v_a, 'vendedor', v_s2, true), (v_b, 'vendedor', v_s1, true);
  update public.perfiles set asesor_perfil_id = v_a where id = v_cliente;
  -- Fechas comerciales las fija el trigger vigente, como en el ensayo de baja.
  for v_fila in select * from (values
    (v_a, v_mes + 4, 'PEN', 1000::numeric), (v_a, v_mes + 19, 'USD', 200::numeric),
    (v_b, v_mes + 4, 'PEN', 1500::numeric), (v_b, v_mes + 19, 'PEN', 1700::numeric),
    (v_s1, v_mes + 6, 'PEN', 3300::numeric),
    (v_a, v_actual, 'PEN', 2000::numeric), (v_a, v_actual, 'PEN', 3000::numeric)
  ) ventas(analista, fecha, moneda, capital) loop
    v_id := gen_random_uuid();
    insert into public.contratos(id, numero_contrato, cliente_id, capital, moneda, tasa_anual,
      modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, estado, categoria,
      creado_por, analista_cierre_id, es_demo)
    values (v_id, 'F3A-' || v_id::text, v_cliente, v_fila.capital, v_fila.moneda, 15,
      'mensual', 'simple', v_fila.fecha, (v_fila.fecha + interval '12 months')::date,
      'activo', 'nuevo', v_g, v_fila.analista, false);
  end loop;
  insert into crm.inversionistas(id, perfil_id, responsable_relacion_id, creado_por)
    values (v_persona, v_cliente, v_a, v_g);
  insert into crm.leads(id, nombre_completo, telefono, origen, etapa, vendedor_id,
    convertido_en, inversionista_id, creado_por, monto_estimado)
  values (v_lead, 'ENSAYO 3A COOPERATIVA', '+51999817031', 'oficina', 'convertido',
    v_b, v_mes::timestamp at time zone 'America/Lima', v_persona, v_g, 22000);
  -- Cierre legado: sin fecha_imputacion, 02:00 UTC = 21:00 del día anterior en Lima.
  -- Es un estado admitido y real del núcleo; garantiza que UTC y Lima difieran.
  insert into crm.cierres_externos(id, lead_id, cooperativa, monto, moneda, documento_tipo,
    documento, nombre_completo, numero_transaccion, vendedor_id, creado_por, inversionista_id,
    creado_en, fecha_comercial, fecha_imputacion, es_cierre_inicial, vence_en)
  values (v_cierre, v_lead, 'qorilazo', 22000, 'PEN', 'DNI', '99817031',
    'ENSAYO 3A COOPERATIVA', 'F3A-' || v_cierre::text, v_b, v_g, v_persona,
    ((v_mes + 1)::timestamp at time zone 'UTC') + interval '2 hours', null, null, true,
    (v_mes + interval '12 months')::date);
  -- A: dos cambios el mismo día, incluido tramo vacío; B: tramo NULL y luego sin supervisor.
  -- La siembra de fase 2 puede haber producido eventos hoy: SOLO reemplazar los de nuestros actores.
  delete from crm.usuario_eventos where objetivo_id in (v_a, v_b, v_s1, v_s2)
    and accion = 'jerarquia_actualizada';
  insert into crm.usuario_eventos(actor_id, objetivo_id, accion, detalle, idempotencia, creado_en) values
    (v_g, v_a, 'jerarquia_actualizada', jsonb_build_object('supervisor_anterior', v_s1, 'supervisor_nuevo', v_s1),
      gen_random_uuid(), ((v_mes + 9)::timestamp at time zone 'America/Lima') + interval '9 hours'),
    (v_g, v_a, 'jerarquia_actualizada', jsonb_build_object('supervisor_anterior', v_s1, 'supervisor_nuevo', v_s2),
      gen_random_uuid(), ((v_mes + 9)::timestamp at time zone 'America/Lima') + interval '17 hours'),
    (v_g, v_b, 'jerarquia_actualizada', jsonb_build_object('supervisor_anterior', null, 'supervisor_nuevo', null),
      gen_random_uuid(), (v_mes + 9)::timestamp at time zone 'America/Lima');
  perform set_config('crm.op_privilegiada', '', true);
  set constraints all immediate;
end $siembra$;
-- INICIO MIGRACION
do $migracion$
declare
  v_funcion record;
  v_catalogo record;
  v_identidad record;
  v_mes date;
  v_primero date;
  v_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_uid uuid;
  v_aplicada boolean;
  v_inicio timestamptz := clock_timestamp();
  v_etapa text := 'PREFLIGHT';
begin
  -- PRECONDICIÓN: la fase 2. Su registrador y su reversa fijan la huella VIEJA de esta puerta, así que tras la 3A las
  -- reversas van en orden inverso: primero la de la 3A.
  if ((select md5(pg_get_functiondef(p.oid)) from pg_proc p
       where p.oid = to_regprocedure('private.trg_equipo_evento_jerarquia()'))
      = '93906f654ba2e4c358ecfe6da1c95f77') is not true then
    raise exception 'PREFLIGHT: falta la fase 2 (20261009223000) aplicada; la 3A va después';
  end if;
  create temporary table f3a_funciones (
    firma text primary key, anterior text, nueva text not null,
    definidor boolean not null, acl text not null
  ) on commit drop;
-- INICIO HUELLAS
  insert into pg_temp.f3a_funciones values
    ('crm.facturacion_diaria_fn(date)', '4b11e1da336f2f296c81f064ce30e35b', '3753d03552e26eb7e61117a3baab6f78', true, '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.facturacion_operaciones(timestamptz,timestamptz)', null, '5d63cb537b0b286ad47feb7f5b26d161', false, '{postgres=X/postgres}'),
    ('private.facturacion_operaciones_visibles(timestamptz,timestamptz)', null, '17c2ca27996adad88f685896915953e3', false, '{postgres=X/postgres}');
-- FIN HUELLAS
  -- La dependencia viva también queda sellada por huella, dueño y permisos.
  insert into pg_temp.f3a_funciones values
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])',
     '2ed07da302e9a1b881a4962724234dd7', '2ed07da302e9a1b881a4962724234dd7', true, '{postgres=X/postgres}');
  select md5(pg_get_functiondef(p.oid)) = f.nueva into v_aplicada
  from pg_temp.f3a_funciones f join pg_proc p on p.oid = to_regprocedure(f.firma)
  where f.firma = 'crm.facturacion_diaria_fn(date)';
  for v_funcion in select * from pg_temp.f3a_funciones loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if v_funcion.anterior is null and v_aplicada is not true then
      if (to_regprocedure(v_funcion.firma) is null) is not true then
        raise exception 'PREFLIGHT: ya existe % sin la puerta migrada; no se sobrescribe', v_funcion.firma;
      end if;
      continue;
    end if;
    if (v_catalogo.huella = case when v_aplicada then v_funcion.nueva else v_funcion.anterior end
        and v_catalogo.dueno = 'postgres' and v_catalogo.acl = v_funcion.acl
        and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = 'sql'
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception 'PREFLIGHT: huella/contrato inesperado en %: %', v_funcion.firma, row_to_json(v_catalogo);
    end if;
  end loop;
  if v_aplicada is true then
    perform set_config('request.jwt.claims', '{}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    drop table pg_temp.f3a_funciones;
    raise notice 'Facturación 3A ya aplicada: cuatro huellas y contratos verificados';
    return;
  end if;

  create temporary table f3a_identidades (
    identidad integer generated always as identity primary key, clase text not null, uid uuid
  ) on commit drop;
  select e.perfil_id into v_uid from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if (v_uid is not null) is not true then
    raise exception 'ORÁCULO: se necesita una Gerencia activa';
  end if;
  insert into pg_temp.f3a_identidades(clase, uid) values ('gerencia', v_uid);
  -- Directorio se comprueba con su capacidad real, incluido el fallback Portal.
  for v_uid in select p.id from public.perfiles p
    left join crm.equipo e on e.perfil_id = p.id
    where p.activo is true and (p.rol = 'directorio' or e.rol_crm = 'directorio')
    order by p.id
  loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
    if private.es_lector_global() is true then
      insert into pg_temp.f3a_identidades(clase, uid) values ('directorio', v_uid);
      exit;
    end if;
  end loop;
  insert into pg_temp.f3a_identidades(clase, uid)
    select 'supervisor', e.perfil_id from crm.equipo e
    where private.rol_crm(e.perfil_id) = 'supervisor' order by e.perfil_id;
  select e.perfil_id into v_uid from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'vendedor' order by e.perfil_id limit 1;
  if (v_uid is not null) is not true then
    raise exception 'ORÁCULO: se necesita un vendedor activo';
  end if;
  insert into pg_temp.f3a_identidades(clase, uid) values ('vendedor', v_uid), ('sin sesión', null);
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);

  -- Solo los meses CON operaciones, más el mes en curso. Un mes vacío da vacío antes y después, y una fecha mal
  -- tecleada (año 0202) no convierte el oráculo en miles de llamadas. Cubre también meses futuros con datos.
  create temporary table f3a_meses on commit drop as
    select distinct date_trunc('month', (e.fecha at time zone 'America/Lima'))::date as mes
    from private.capital_episodios('-infinity', 'infinity', true, '{}'::uuid[]) e
    where e.medida = 'stock' and isfinite(e.fecha);
  select min(mes) into v_primero from pg_temp.f3a_meses;
  if (v_primero is not null and isfinite(v_primero)) is not true then
    raise exception 'ORÁCULO: no hay meses finitos con operaciones';
  end if;
  insert into pg_temp.f3a_meses
    select v_actual where not exists (select 1 from pg_temp.f3a_meses where mes = v_actual);
  create temporary table f3a_antes (
    identidad integer, mes date, dia date, tipo text, moneda text,
    analista_id uuid, analista_nombre text, supervisor_id uuid, supervisor_nombre text,
    operaciones bigint, capital numeric
  ) on commit drop;
  create temporary table f3a_despues (like pg_temp.f3a_antes) on commit drop;
  for v_identidad in select * from pg_temp.f3a_identidades order by identidad loop
    perform set_config('request.jwt.claims', case when v_identidad.uid is null then '{}' else
      jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(v_identidad.uid::text, ''), true);
    for v_mes in select mes from pg_temp.f3a_meses order by mes loop
      insert into pg_temp.f3a_antes select v_identidad.identidad, v_mes, f.*
      from crm.facturacion_diaria_fn(v_mes) f;
    end loop;
  end loop;
  if (not exists (select 1 from pg_temp.f3a_antes f join pg_temp.f3a_identidades i using (identidad)
      where i.clase in ('vendedor', 'sin sesión'))) is not true then
    raise exception 'ORÁCULO: vendedor o sin sesión ya recibían filas antes del cambio';
  end if;

-- INICIO CUERPOS GENERADOS
  execute $def$
CREATE OR REPLACE FUNCTION private.facturacion_operaciones(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, anulado boolean, fecha_vencimiento date)
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
  with episodios as (
    select (e.fecha at time zone 'America/Lima')::date as dia, e.*
    from private.capital_episodios(p_desde, p_hasta, true, '{}'::uuid[]) e
    where e.medida = 'stock'
  ),
  eventos as (
    select
      ue.objetivo_id as analista_id,
      (ue.creado_en at time zone 'America/Lima')::date as dia_cambio,
      (ue.detalle->>'supervisor_anterior')::uuid as antes,
      (ue.detalle->>'supervisor_nuevo')::uuid as despues,
      -- `ue.id` desempata: sin él, dos eventos en el mismo instante numerarían
      -- de forma no determinista y los tramos podrían solaparse.
      row_number() over (partition by ue.objetivo_id order by ue.creado_en, ue.id) as n
    from crm.usuario_eventos ue
    where ue.accion = 'jerarquia_actualizada'
  ),
  tramos as (
    -- Antes del primer cambio registrado.
    select e.analista_id, '-infinity'::date as desde, e.dia_cambio as hasta, e.antes as supervisor_id
    from eventos e
    where e.n = 1
    union all
    -- Entre un cambio y el siguiente (o hasta hoy, si fue el último). El día del
    -- cambio cuenta ya para el supervisor NUEVO; con dos cambios el mismo día, el
    -- tramo intermedio queda vacío y manda el último.
    select e.analista_id, e.dia_cambio, coalesce(sig.dia_cambio, 'infinity'::date), e.despues
    from eventos e
    left join eventos sig
      on sig.analista_id = e.analista_id and sig.n = e.n + 1
  )
  select
    coalesce(ep.contrato_id, ep.cierre_externo_id) as operacion_id,
    ep.dia, ep.fecha, ep.tipo, ep.moneda, ep.monto, ep.analista_id,
  -- LOS DOS CAMINOS AL EQUIPO DE HOY, y son deliberados: no hay tramo (nunca se
  -- registró un cambio) o el tramo dice NULL («no constaba jerarquía entonces»).
  -- Ver la nota de la cabecera de 20260910230000: en un informe de dinero «no
  -- consta» no deja el importe sin dueño.
    coalesce(t.supervisor_id, eq.supervisor_id) as supervisor_id,
    ep.contrato_id, ep.cierre_externo_id, ep.cliente_id, ep.lead_id,
    ep.registrado_por, ep.categoria, ep.estado, ep.anulado, ep.fecha_vencimiento
  from episodios ep
  -- Los tramos de un analista son disjuntos y cubren toda la línea temporal, así
  -- que este join casa como mucho una fila. `crm.equipo.perfil_id` es PK.
  left join tramos t
    on t.analista_id = ep.analista_id
   and ep.dia >= t.desde
   and ep.dia <  t.hasta
  left join crm.equipo eq on eq.perfil_id = ep.analista_id;
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION private.facturacion_operaciones_visibles(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, anulado boolean, fecha_vencimiento date)
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
  with quien as materialized (
    -- Una sola vez: quién pregunta y con qué rol. `private.rol_crm` devuelve
    -- NULL para quien no es miembro del CRM.
    select
      (select auth.uid()) as uid,
      private.rol_crm((select auth.uid())) as rol,
      private.es_lector_global() as lector
  ),
  ambito as materialized (
    -- La verja, en tres columnas. NULL = 'gerencia' es NULL, y el coalesce lo
    -- cierra en false. `ok` abre el núcleo; `es_global` y `subarbol` recortan.
    select
      q.uid,
      coalesce(q.uid is not null and (q.rol = 'gerencia' or q.lector), false) as es_global,
      coalesce(q.uid is not null and (q.rol in ('gerencia', 'supervisor') or q.lector), false) as ok,
      -- El subárbol de HOY del supervisor (él incluido). Para cualquier otro
      -- rol queda VACÍO a propósito: así el predicado final no puede abrirse
      -- por accidente para nadie más.
      case when coalesce(q.uid is not null and q.rol = 'supervisor', false)
           then array(select private.vendedor_ids_visibles(q.uid))
           else '{}'::uuid[] end as subarbol
    from quien q
  )
  select ep.*
  from (select * from ambito a where a.ok) a
  -- La dependencia de a.ok mantiene el lateral detrás de la verja incluso si
  -- el planificador reordena joins: con cero actores autorizados no se llama.
  cross join lateral private.facturacion_operaciones(
    case when a.ok then p_desde end, p_hasta
  ) ep
  -- EL RECORTE DEL SUPERVISOR (ver cabecera): el supervisor de entonces es él o
  -- alguien de su subárbol, o la venta es suya. Gerencia y el lector global
  -- pasan enteros. Un `= any('{}')` es false y un supervisor NULL da NULL: para
  -- quien no es supervisor solo queda `es_global`, que para él es false — y de
  -- todos modos `episodios` ya salió vacío por `a.ok`.
  where a.es_global
     or ep.supervisor_id = any(a.subarbol)
     or ep.analista_id = a.uid;
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION crm.facturacion_diaria_fn(p_mes date DEFAULT NULL::date)
 RETURNS TABLE(dia date, tipo text, moneda text, analista_id uuid, analista_nombre text, supervisor_id uuid, supervisor_nombre text, operaciones bigint, capital numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with
  mes as (
    -- Se normaliza en vez de rechazar: una fecha a mitad de mes solo puede querer
    -- decir ese mes. Y sin argumento vale el mes EN CURSO de Lima — un NULL que
    -- devolviera vacío en silencio sería indistinguible de «no se vendió nada».
    select coalesce(
      date_trunc('month', p_mes),
      date_trunc('month', (now() at time zone 'America/Lima'))
    )::date as ini
  )
  select
    ep.dia,
    ep.tipo,
    ep.moneda,
    ep.analista_id,
    coalesce(pf.nombre_completo, 'Sin analista') as analista_nombre,
    ep.supervisor_id as supervisor_id,
    coalesce(ps.nombre_completo, 'Sin supervisor') as supervisor_nombre,
    count(*)::bigint as operaciones,
    sum(ep.monto) as capital
  from mes m
  cross join lateral private.facturacion_operaciones_visibles(
    (m.ini::timestamp at time zone 'America/Lima'),
    (((m.ini + interval '1 month')::date)::timestamp at time zone 'America/Lima')
  ) ep
  left join public.perfiles pf on pf.id = ep.analista_id
  left join public.perfiles ps on ps.id = ep.supervisor_id
  group by ep.dia, ep.tipo, ep.moneda, ep.analista_id, pf.nombre_completo,
           ep.supervisor_id, ps.nombre_completo
  -- PEN y USD no comparten escala: la moneda ordena ANTES que el importe, para no
  -- rankear US$ 10 000 por debajo de S/ 50 000.
  order by ep.dia, ep.moneda, sum(ep.monto) desc;
$function$
$def$;

-- FIN CUERPOS GENERADOS
  alter function private.facturacion_operaciones(timestamptz,timestamptz) owner to postgres;
  alter function private.facturacion_operaciones_visibles(timestamptz,timestamptz) owner to postgres;
  alter function crm.facturacion_diaria_fn(date) owner to postgres;
  revoke execute on function private.facturacion_operaciones(timestamptz,timestamptz),
    private.facturacion_operaciones_visibles(timestamptz,timestamptz) from public, anon, authenticated, service_role;
  revoke execute on function crm.facturacion_diaria_fn(date) from public, anon, service_role;
  grant execute on function crm.facturacion_diaria_fn(date) to authenticated;
  comment on function private.facturacion_operaciones(timestamptz,timestamptz) is
    'SIN VERJA: devuelve TODAS las operaciones de stock de la empresa (capital vivo, también en meses sellados), una fila por operación, con día de Lima y supervisor de entonces (caída al de hoy: 20260910230000). Su ÚNICO llamador es private.facturacion_operaciones_visibles; ninguna puerta la llama directo (el gate censa sus llamadores). Única fuente de la cifra y de la lista de Facturación. Sin EXECUTE para la API.';
  comment on function private.facturacion_operaciones_visibles(timestamptz,timestamptz) is
    'Única fuente VISIBLE de la cifra y de la lista de Facturación: la verja y el recorte del supervisor (supervisor de entonces en su subárbol de hoy, o ventas propias; ver 20260916205617) viven aquí. Sin autorización no llama al núcleo. Devuelve ids crudos (cliente, lead, registrado_por): la puerta de la lista DEBE aplicar la capa de datos (cliente de otro equipo sin nombre ni N.º, DNI nunca). Sus llamadores son una lista cerrada que censa el gate. Sin EXECUTE para la API.';

  for v_identidad in select * from pg_temp.f3a_identidades order by identidad loop
    perform set_config('request.jwt.claims', case when v_identidad.uid is null then '{}' else
      jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(v_identidad.uid::text, ''), true);
    for v_mes in select mes from pg_temp.f3a_meses order by mes loop
      insert into pg_temp.f3a_despues select v_identidad.identidad, v_mes, f.*
      from crm.facturacion_diaria_fn(v_mes) f;
    end loop;
  end loop;
  if (not exists (
    (select * from pg_temp.f3a_antes except all select * from pg_temp.f3a_despues)
    union all
    (select * from pg_temp.f3a_despues except all select * from pg_temp.f3a_antes)
  )) is not true then
    raise exception 'ORÁCULO: cambió la salida completa (incluidos nombres o multiplicidad); se deshace todo';
  end if;
  -- Materializar UNA llamada por mes permite comprobar tanto las claves como el agregado.
  create temporary table f3a_operaciones on commit drop as
    select null::date as mes, o.* from private.facturacion_operaciones(null, null) o with no data;
  for v_mes in select mes from pg_temp.f3a_meses order by mes loop
    insert into pg_temp.f3a_operaciones select v_mes, o.*
    from private.facturacion_operaciones(
      v_mes::timestamp at time zone 'America/Lima',
      ((v_mes + interval '1 month')::date)::timestamp at time zone 'America/Lima'
    ) o;
  end loop;
  if (not exists (select 1 from pg_temp.f3a_operaciones
      group by operacion_id having operacion_id is null or count(*) > 1)) is not true then
    raise exception 'ORÁCULO: operacion_id nulo o repetido (incluidos solapamientos entre meses)';
  end if;
  create temporary table f3a_agregado on commit drop as
    select mes, dia, tipo, moneda, analista_id, supervisor_id,
      count(*)::bigint as operaciones, sum(monto) as capital
    from pg_temp.f3a_operaciones group by mes, dia, tipo, moneda, analista_id, supervisor_id;
  create temporary table f3a_gerencia on commit drop as
    select f.mes, f.dia, f.tipo, f.moneda, f.analista_id, f.supervisor_id, f.operaciones, f.capital
    from pg_temp.f3a_despues f join pg_temp.f3a_identidades i using (identidad) where i.clase = 'gerencia';
  if (not exists (
    (select * from pg_temp.f3a_agregado except all select * from pg_temp.f3a_gerencia)
    union all
    (select * from pg_temp.f3a_gerencia except all select * from pg_temp.f3a_agregado)
  )) is not true then
    raise exception 'ORÁCULO: el agregado directo del núcleo no coincide con Gerencia';
  end if;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'ORÁCULO PASS: % meses (% a %), % identidades (% Directorio), % filas antes / % después, % operaciones únicas; % ms',
    (select count(*) from pg_temp.f3a_meses), (select min(mes) from pg_temp.f3a_meses),
    (select max(mes) from pg_temp.f3a_meses),
    (select count(*) from pg_temp.f3a_identidades),
    (select count(*) from pg_temp.f3a_identidades where clase = 'directorio'),
    (select count(*) from pg_temp.f3a_antes), (select count(*) from pg_temp.f3a_despues),
    (select count(*) from pg_temp.f3a_operaciones),
    round(extract(epoch from clock_timestamp() - v_inicio) * 1000, 2);
  v_etapa := 'POSTFLIGHT';
  -- Imprimir todas antes de rechazar los marcadores; medir no desactiva el candado.
  for v_funcion in select * from pg_temp.f3a_funciones loop
    raise notice 'HUELLA % = %', v_funcion.firma, md5(pg_get_functiondef(to_regprocedure(v_funcion.firma)));
  end loop;
  for v_funcion in select * from pg_temp.f3a_funciones loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if (v_catalogo.huella = v_funcion.nueva
        and v_catalogo.dueno = 'postgres' and v_catalogo.acl = v_funcion.acl
        and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = 'sql'
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception '%: huella/contrato inesperado en %: %; esperada %; se deshace todo',
        v_etapa, v_funcion.firma, row_to_json(v_catalogo), v_funcion.nueva;
    end if;
  end loop;
  raise notice 'Facturación 3A aplicada: cifra intacta y fuente única preparada para 3B';
end $migracion$;
-- FIN MIGRACION

-- La foto es la tomada POR LA MIGRACIÓN antes de reemplazar la puerta.
create function pg_temp.f3a_comparar_foto() returns void language plpgsql as $comparar$
declare v_identidad record; v_mes date;
begin
  create temporary table if not exists f3a_prueba (like pg_temp.f3a_antes) on commit drop;
  truncate pg_temp.f3a_prueba;
  for v_identidad in select * from pg_temp.f3a_identidades order by identidad loop
    perform set_config('request.jwt.claims', case when v_identidad.uid is null then '{}' else
      jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(v_identidad.uid::text, ''), true);
    for v_mes in select mes from pg_temp.f3a_meses order by mes loop
      insert into pg_temp.f3a_prueba select v_identidad.identidad, v_mes, f.*
        from crm.facturacion_diaria_fn(v_mes) f;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  if (not exists (
    (select * from pg_temp.f3a_antes except all select * from pg_temp.f3a_prueba)
    union all (select * from pg_temp.f3a_prueba except all select * from pg_temp.f3a_antes)
  )) is not true then
    raise exception using errcode = 'P3A01', message = 'ORÁCULO: salida diferente de la foto viva anterior';
  end if;
end $comparar$;
select pg_temp.f3a_comparar_foto();
do $mutantes$
declare
  v_mutante record;
  v_original text;
  v_cazado boolean;
begin
  for v_mutante in select * from (values
    ('sin cooperativas', 'private.facturacion_operaciones(timestamptz,timestamptz)',
      'where e.medida = ''stock''', 'where e.medida = ''stock'' and e.tipo <> ''cooperativa'''),
    ('sin caída al supervisor de hoy', 'private.facturacion_operaciones(timestamptz,timestamptz)',
      'coalesce(t.supervisor_id, eq.supervisor_id)', 't.supervisor_id'),
    ('día UTC', 'private.facturacion_operaciones(timestamptz,timestamptz)',
      '(e.fecha at time zone ''America/Lima'')::date', '(e.fecha at time zone ''UTC'')::date'),
    ('sin ventas propias del supervisor', 'private.facturacion_operaciones_visibles(timestamptz,timestamptz)',
      'or ep.analista_id = a.uid', 'or false')
  ) mutantes(nombre, firma, antes, despues) loop
    v_original := pg_get_functiondef(to_regprocedure(v_mutante.firma));
    if ((length(v_original) - length(replace(v_original, v_mutante.antes, ''))) / length(v_mutante.antes) = 1) is not true then
      raise exception 'MUTANTE %: ancla no única', v_mutante.nombre;
    end if;
    v_cazado := false;
    begin
      execute replace(v_original, v_mutante.antes, v_mutante.despues);
      perform pg_temp.f3a_comparar_foto();
    exception when sqlstate 'P3A01' then
      -- SOLO este error acredita que falló la comparación; no se tragan errores SQL.
      -- La subtransacción revierte también el cuerpo mutado.
      v_cazado := true;
    end;
    if v_cazado is not true then raise exception 'MUTANTE SOBREVIVIÓ: %', v_mutante.nombre; end if;
    if (pg_get_functiondef(to_regprocedure(v_mutante.firma)) = v_original) is not true then
      raise exception 'MUTANTE %: no se restauró el cuerpo', v_mutante.nombre;
    end if;
    perform pg_temp.f3a_comparar_foto();
    raise notice 'MUTANTE CAZADO contra foto viva: %', v_mutante.nombre;
  end loop;
end $mutantes$;

-- Prueba de EJECUCIÓN: sustituir temporalmente el núcleo por una bomba.
-- Vendedor y sin sesión deben seguir vacíos sin tocarla; Gerencia debe detonarla.
do $verja$
declare v_cuerpo text; v_identidad record; v_detonada boolean := false; v_mes date;
begin
  select min(mes) into v_mes from pg_temp.f3a_meses;
  v_cuerpo := pg_get_functiondef(to_regprocedure('private.facturacion_operaciones(timestamptz,timestamptz)'));
  begin
    execute replace(split_part(v_cuerpo, 'AS $function$', 1), 'LANGUAGE sql', 'LANGUAGE plpgsql')
      || 'AS $bomba$ begin raise exception using errcode = ''P3A02'', message = ''NÚCLEO LLAMADO''; end $bomba$';
    for v_identidad in select * from pg_temp.f3a_identidades where clase in ('vendedor', 'sin sesión') loop
      perform set_config('request.jwt.claims', case when v_identidad.uid is null then '{}' else
        jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text end, true);
      perform set_config('request.jwt.claim.sub', coalesce(v_identidad.uid::text, ''), true);
      if ((select count(*) = 0 from crm.facturacion_diaria_fn(v_mes))) is not true then
        raise exception 'VERJA: devuelve filas sin autorización';
      end if;
    end loop;
    -- Control positivo en otro bloque: la bomba no puede pasar por falta de datos.
    select * into v_identidad from pg_temp.f3a_identidades where clase = 'gerencia';
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_identidad.uid::text, true);
    begin
      perform count(*) from crm.facturacion_diaria_fn(v_mes);
    exception when sqlstate 'P3A02' then v_detonada := true;
    end;
    if v_detonada is not true then raise exception 'VERJA: la bomba no se ejecutó para Gerencia'; end if;
    -- Provocar rollback de la sustitución tras comprobar ambos caminos.
    raise exception using errcode = 'P3A03', message = 'VERJA comprobada';
  exception when sqlstate 'P3A03' then null;
  end;
  if (pg_get_functiondef(to_regprocedure('private.facturacion_operaciones(timestamptz,timestamptz)')) = v_cuerpo) is not true then
    raise exception 'VERJA: núcleo no restaurado';
  end if;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'VERJA PASS: cero llamadas sin autorización; Gerencia sí llama';
end $verja$;
-- INICIO REVERSA
do $reversa$
declare
  v_funcion record;
  v_catalogo record;
  v_revertida boolean;
begin
  -- Puede ejecutarse tras el ensayo en la MISMA transacción.
  drop table if exists pg_temp.f3a_funciones;
  create temporary table f3a_funciones (
    firma text primary key, anterior text, nueva text not null,
    definidor boolean not null, acl text not null
  ) on commit drop;
-- INICIO HUELLAS
  insert into pg_temp.f3a_funciones values
    ('crm.facturacion_diaria_fn(date)', '4b11e1da336f2f296c81f064ce30e35b', '3753d03552e26eb7e61117a3baab6f78', true, '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.facturacion_operaciones(timestamptz,timestamptz)', null, '5d63cb537b0b286ad47feb7f5b26d161', false, '{postgres=X/postgres}'),
    ('private.facturacion_operaciones_visibles(timestamptz,timestamptz)', null, '17c2ca27996adad88f685896915953e3', false, '{postgres=X/postgres}');
-- FIN HUELLAS
  insert into pg_temp.f3a_funciones values
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])',
     '2ed07da302e9a1b881a4962724234dd7', '2ed07da302e9a1b881a4962724234dd7', true, '{postgres=X/postgres}');
  select md5(pg_get_functiondef(p.oid)) = f.anterior into v_revertida
  from pg_temp.f3a_funciones f join pg_proc p on p.oid = to_regprocedure(f.firma)
  where f.firma = 'crm.facturacion_diaria_fn(date)';
  for v_funcion in select * from pg_temp.f3a_funciones loop
    if v_funcion.anterior is null and v_revertida is true then
      if (to_regprocedure(v_funcion.firma) is null) is not true then
        raise exception 'REVERSA PREFLIGHT: queda % con la puerta viva; estado mixto', v_funcion.firma;
      end if;
      continue;
    end if;
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if (v_catalogo.huella = case when v_revertida then v_funcion.anterior else v_funcion.nueva end
        and v_catalogo.dueno = 'postgres' and v_catalogo.acl = v_funcion.acl
        and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = 'sql'
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception 'REVERSA PREFLIGHT: huella/contrato inesperado en %: %', v_funcion.firma, row_to_json(v_catalogo);
    end if;
  end loop;
  if v_revertida is true then
    drop table pg_temp.f3a_funciones;
    raise notice 'REVERSA 3A ya completa: cuerpo vivo, ACL y ausencia de piezas comprobados';
    return;
  end if;
  -- Las funciones SQL con cuerpo en texto no registran dependencias: un DROP sin CASCADE no ve a sus llamadores.
  if (exists (select 1 from pg_proc p
      where p.prosrc ~* 'private\.facturacion_operaciones(_visibles)?\s*\('
        and p.oid not in (select x from unnest(array[
              to_regprocedure('crm.facturacion_diaria_fn(date)'),
              to_regprocedure('private.facturacion_operaciones_visibles(timestamptz,timestamptz)'),
              to_regprocedure('private.facturacion_operaciones(timestamptz,timestamptz)')]::oid[]) x
            where x is not null))) is true then
    raise exception 'REVERSA PREFLIGHT: otra función usa las piezas de la 3A (¿la puerta de la 3B?); revierte primero esa';
  end if;
-- INICIO CUERPOS GENERADOS
  execute $def$
CREATE OR REPLACE FUNCTION crm.facturacion_diaria_fn(p_mes date DEFAULT NULL::date)
 RETURNS TABLE(dia date, tipo text, moneda text, analista_id uuid, analista_nombre text, supervisor_id uuid, supervisor_nombre text, operaciones bigint, capital numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with quien as materialized (
    -- Una sola vez: quién pregunta y con qué rol. `private.rol_crm` devuelve
    -- NULL para quien no es miembro del CRM.
    select
      (select auth.uid()) as uid,
      private.rol_crm((select auth.uid())) as rol,
      private.es_lector_global() as lector
  ),
  ambito as materialized (
    -- La verja, en tres columnas. NULL = 'gerencia' es NULL, y el coalesce lo
    -- cierra en false. `ok` abre el núcleo; `es_global` y `subarbol` recortan.
    select
      q.uid,
      coalesce(q.uid is not null and (q.rol = 'gerencia' or q.lector), false) as es_global,
      coalesce(q.uid is not null and (q.rol in ('gerencia', 'supervisor') or q.lector), false) as ok,
      -- El subárbol de HOY del supervisor (él incluido). Para cualquier otro
      -- rol queda VACÍO a propósito: así el predicado final no puede abrirse
      -- por accidente para nadie más.
      case when coalesce(q.uid is not null and q.rol = 'supervisor', false)
           then array(select private.vendedor_ids_visibles(q.uid))
           else '{}'::uuid[] end as subarbol
    from quien q
  ),
  mes as (
    -- Se normaliza en vez de rechazar: una fecha a mitad de mes solo puede querer
    -- decir ese mes. Y sin argumento vale el mes EN CURSO de Lima — un NULL que
    -- devolviera vacío en silencio sería indistinguible de «no se vendió nada».
    select coalesce(
      date_trunc('month', p_mes),
      date_trunc('month', (now() at time zone 'America/Lima'))
    )::date as ini
  ),
  episodios as (
    -- El ámbito va HACIA DENTRO del núcleo: sin autorización no se escanea el mes
    -- entero para tirarlo después. El supervisor entra GLOBAL aquí a propósito:
    -- su recorte es por el supervisor DE ENTONCES, que solo existe tras el
    -- rebobinado de abajo (ver cabecera).
    select
      (e.fecha at time zone 'America/Lima')::date as dia,
      e.tipo,
      e.moneda,
      e.analista_id,
      e.monto
    from ambito a
    cross join mes m
    cross join lateral private.capital_episodios(
      (m.ini::timestamp at time zone 'America/Lima'),
      (((m.ini + interval '1 month')::date)::timestamp at time zone 'America/Lima'),
      a.ok, '{}'::uuid[]
    ) e
    where a.ok
      and e.medida = 'stock'
  ),
  eventos as (
    select
      ue.objetivo_id as analista_id,
      (ue.creado_en at time zone 'America/Lima')::date as dia_cambio,
      (ue.detalle->>'supervisor_anterior')::uuid as antes,
      (ue.detalle->>'supervisor_nuevo')::uuid as despues,
      -- `ue.id` desempata: sin él, dos eventos en el mismo instante numerarían
      -- de forma no determinista y los tramos podrían solaparse.
      row_number() over (partition by ue.objetivo_id order by ue.creado_en, ue.id) as n
    from crm.usuario_eventos ue
    where ue.accion = 'jerarquia_actualizada'
  ),
  tramos as (
    -- Antes del primer cambio registrado.
    select e.analista_id, '-infinity'::date as desde, e.dia_cambio as hasta, e.antes as supervisor_id
    from eventos e
    where e.n = 1
    union all
    -- Entre un cambio y el siguiente (o hasta hoy, si fue el último). El día del
    -- cambio cuenta ya para el supervisor NUEVO; con dos cambios el mismo día, el
    -- tramo intermedio queda vacío y manda el último.
    select e.analista_id, e.dia_cambio, coalesce(sig.dia_cambio, 'infinity'::date), e.despues
    from eventos e
    left join eventos sig
      on sig.analista_id = e.analista_id and sig.n = e.n + 1
  )
  select
    ep.dia,
    ep.tipo,
    ep.moneda,
    ep.analista_id,
    coalesce(pf.nombre_completo, 'Sin analista') as analista_nombre,
    coalesce(t.supervisor_id, eq.supervisor_id) as supervisor_id,
    coalesce(ps.nombre_completo, 'Sin supervisor') as supervisor_nombre,
    count(*)::bigint as operaciones,
    sum(ep.monto) as capital
  from episodios ep
  cross join ambito a
  -- Los tramos de un analista son disjuntos y cubren toda la línea temporal, así
  -- que este join casa como mucho una fila. `crm.equipo.perfil_id` es PK.
  left join tramos t
    on t.analista_id = ep.analista_id
   and ep.dia >= t.desde
   and ep.dia <  t.hasta
  left join crm.equipo eq on eq.perfil_id = ep.analista_id
  left join public.perfiles pf on pf.id = ep.analista_id
  -- LOS DOS CAMINOS AL EQUIPO DE HOY, y son deliberados: no hay tramo (nunca se
  -- registró un cambio) o el tramo dice NULL («no constaba jerarquía entonces»).
  -- Ver la nota de la cabecera de 20260910230000: en un informe de dinero «no
  -- consta» no deja el importe sin dueño.
  left join public.perfiles ps
    on ps.id = coalesce(t.supervisor_id, eq.supervisor_id)
  -- EL RECORTE DEL SUPERVISOR (ver cabecera): el supervisor de entonces es él o
  -- alguien de su subárbol, o la venta es suya. Gerencia y el lector global
  -- pasan enteros. Un `= any('{}')` es false y un supervisor NULL da NULL: para
  -- quien no es supervisor solo queda `es_global`, que para él es false — y de
  -- todos modos `episodios` ya salió vacío por `a.ok`.
  where a.es_global
     or coalesce(t.supervisor_id, eq.supervisor_id) = any(a.subarbol)
     or ep.analista_id = a.uid
  group by ep.dia, ep.tipo, ep.moneda, ep.analista_id, pf.nombre_completo,
           coalesce(t.supervisor_id, eq.supervisor_id), ps.nombre_completo
  -- PEN y USD no comparten escala: la moneda ordena ANTES que el importe, para no
  -- rankear US$ 10 000 por debajo de S/ 50 000.
  order by ep.dia, ep.moneda, sum(ep.monto) desc;
$function$
$def$;

-- FIN CUERPOS GENERADOS
  alter function crm.facturacion_diaria_fn(date) owner to postgres;
  revoke execute on function crm.facturacion_diaria_fn(date) from public, anon, service_role;
  grant execute on function crm.facturacion_diaria_fn(date) to authenticated;
  drop function private.facturacion_operaciones_visibles(timestamptz,timestamptz);
  drop function private.facturacion_operaciones(timestamptz,timestamptz);
  for v_funcion in select * from pg_temp.f3a_funciones loop
    if v_funcion.anterior is null then
      if (to_regprocedure(v_funcion.firma) is null) is not true then
        raise exception 'REVERSA POSTFLIGHT: no desapareció %', v_funcion.firma;
      end if;
      continue;
    end if;
    if ((select md5(pg_get_functiondef(p.oid)) = v_funcion.anterior
        and pg_get_userbyid(p.proowner) = 'postgres' and p.proacl::text = v_funcion.acl
        and p.prosecdef = v_funcion.definidor and p.provolatile = 's' and l.lanname = 'sql'
        and cardinality(p.proconfig) = 1 and p.proconfig[1] in ('search_path=', 'search_path=""')
      from pg_proc p join pg_language l on l.oid = p.prolang
      where p.oid = to_regprocedure(v_funcion.firma))) is not true then
      raise exception 'REVERSA POSTFLIGHT: no se restauró exactamente %', v_funcion.firma;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  drop table pg_temp.f3a_funciones;
  raise notice 'REVERSA 3A PASS: huella viva y ACL exactas; dos piezas eliminadas';
end $reversa$;
-- FIN REVERSA
select pg_temp.f3a_comparar_foto();
set constraints all immediate;
do $fin$
begin
  raise notice 'ENSAYO 3A PASS: cuatro mutantes cazados, verja sin llamada, reversa exacta y foto íntegra; ROLLBACK';
end $fin$;
rollback;
