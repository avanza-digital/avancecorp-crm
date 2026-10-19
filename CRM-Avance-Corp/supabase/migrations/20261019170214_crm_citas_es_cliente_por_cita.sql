-- Proyección de citas (19/10/2026), Fase 0: cada cita dice si la persona YA ERA
-- CLIENTE cuando el analista la generó. Hasta hoy el lector de Citas sólo
-- entregaba el total `citas_clientes`; la pestaña «Proyección» separa por
-- analista Referidos · Clientes · Leads y necesita la marca por cita.
-- Plan en el vault: «Citas - proyeccion semanal y diaria por analista, plan
-- (2026-10-19)», Fase 0 (decisión de Miguel, 19/10: «las dos: referidos y clientes»).
--
-- DEFINICIÓN (decisión del PRIMARY tras la revisión de Codex, 19/10): «ya era
-- cliente» = la persona del lead —o cualquier identidad fusionada con ella— tenía,
-- estrictamente antes del instante en que se creó la cita, una conversión o un
-- cierre externo que SIGUE VIGENTE HOY. Una anulación posterior la quita (igual
-- que la anulación quita la venta en todo el CRM) y una rehabilitación la
-- devuelve. `convertido_en = creado_en` cuenta como «no era cliente». Una tarea
-- de perfil (`tareas.perfil_id`) es por construcción una cita con cliente.
-- Supervisión recibe el booleano calculado sobre toda la persona (puede
-- depender de ventas de otro equipo); no recibe cifras ni filas nuevas.
--
-- Qué cambia: se añade la clave `es_cliente` a cada elemento de `citas[]` en los
-- dos lectores privados de Citas (v1 y el de cortes valorados), por reemplazo
-- anclado único sobre la definición viva, como en 20260927172931. No cambia el
-- alcance por rol, la población, el capital ni la forma pública de las puertas.
-- El censo analítico global está en ROJO por piezas ajenas (medido el 19/10:
-- nueve contadores sin declarar, ninguno de Citas), así que, como 20261017043000,
-- esta migración NO llama al guardián: guarda la foto del censo y exige que
-- quede idéntica.
--
-- Cómo se revierte (en una transacción): (1) comprobar que los dos lectores
-- contienen exactamente una vez la expresión `'es_cliente',case when
-- t.perfil_id is not null then true else private.cita_con_cliente(t.lead_id,
-- t.creado_en) end` precedida de `,\n    `; (2) `execute replace(pg_get_functiondef(...),
-- <esa expresión con su coma y salto>, '')` en ambos y comprobar que md5(prosrc)
-- vuelve a `d07e19d9731f3a7c6aef2a82f5745d58` / `89ef3e8cc067c344641f247e519007a6`;
-- (3) recalcular la `huella` normalizada de ambas declaraciones y el sello
-- (`private.huella_exenciones_analitica_lc()`); (4) `drop function
-- private.cita_con_cliente(uuid,timestamptz)`; (5) foto del censo idéntica.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;

-- Fotos previas: censo entero y atributos/permisos de lo que se toca.
create temporary table es_cliente_censo_antes on commit drop as
  select * from private.contadores_crudos_leads_citas();
create temporary table es_cliente_atributos_antes on commit drop as
  select p.oid, p.proowner, p.proacl, p.prosecdef, p.provolatile, p.proconfig
  from pg_catalog.pg_proc p
  where p.oid in ('private.citas_gerencia_consulta(date,date)'::regprocedure,
                  'private.citas_gerencia_consulta_corte(date,date,uuid)'::regprocedure,
                  'crm.citas_gerencia_consulta_fn(date,date)'::regprocedure,
                  'crm.citas_gerencia_consulta_v2_fn(date,date)'::regprocedure);

do $preflight$
begin
  if pg_catalog.md5((select p.prosrc from pg_catalog.pg_proc p
      where p.oid = 'private.citas_gerencia_consulta(date,date)'::regprocedure))
     is distinct from 'd07e19d9731f3a7c6aef2a82f5745d58' then
    raise exception 'PREFLIGHT es_cliente: el lector v1 de Citas cambió; conciliar antes de aplicar';
  end if;
  if pg_catalog.md5((select p.prosrc from pg_catalog.pg_proc p
      where p.oid = 'private.citas_gerencia_consulta_corte(date,date,uuid)'::regprocedure))
     is distinct from '89ef3e8cc067c344641f247e519007a6' then
    raise exception 'PREFLIGHT es_cliente: el lector de cortes de Citas cambió; conciliar antes de aplicar';
  end if;
  if pg_catalog.to_regprocedure('private.cita_con_cliente(uuid,timestamptz)') is not null then
    raise exception 'PREFLIGHT es_cliente: la función auxiliar ya existe';
  end if;
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'PREFLIGHT es_cliente: el sello de exenciones ya era inconsistente';
  end if;
  -- Los dos lectores tienen que estar declarados y con huella vigente: re-sellar
  -- no puede bendecir una declaración caducada.
  if (select count(*) from private.contadores_crudos_leads_citas() c
      where c.objeto in ('private.citas_gerencia_consulta(date,date)',
                         'private.citas_gerencia_consulta_corte(date,date,uuid)')
        and c.declarada and c.huella_ok) <> 2 then
    raise exception 'PREFLIGHT es_cliente: los lectores de Citas no están declarados con huella vigente';
  end if;
  if (select count(*) from es_cliente_atributos_antes) <> 4 then
    raise exception 'PREFLIGHT es_cliente: falta alguna de las cuatro funciones de Citas';
  end if;
end;
$preflight$;

-- Auxiliar. plpgsql con camino rápido: primero el propio lead (dos lecturas por
-- índice); sólo si el lead tiene una persona enlazada se recorre la identidad
-- (fusiones hasta 16 niveles, mismo tope que private.inversionista_canonica).
-- SECURITY INVOKER a propósito: sólo la ejecuta postgres desde los lectores
-- DEFINER de Citas; nadie más tiene EXECUTE.
create function private.cita_con_cliente(p_lead uuid, p_antes timestamptz)
returns boolean
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_personas uuid[];
begin
  if p_lead is null or p_antes is null then
    return false;
  end if;
  -- Camino rápido: el propio lead ya convertido (y vigente) o con cierre externo vigente, antes de la cita.
  if exists (
       select 1 from crm.leads o
       where o.id = p_lead and o.activo and o.etapa = 'convertido'
         and o.convertido_en < p_antes and not private.cierre_anulado(o.id))
     or exists (
       select 1 from crm.cierres_externos ce
       where ce.lead_id = p_lead and ce.anulado_en is null and ce.creado_en < p_antes) then
    return true;
  end if;
  -- Persona enlazada: el enlace vivo del lead manda; el historial de identidad
  -- sólo se consulta cuando el enlace vivo está vacío (nunca se mezclan dos personas).
  select array[private.inversionista_canonica(coalesce(
           (select l.inversionista_id from crm.leads l where l.id = p_lead),
           (select il.inversionista_id from crm.inversionista_leads il
             where il.lead_id = p_lead and il.hasta is null
             order by il.desde desc limit 1)))]
    into v_personas;
  if v_personas[1] is null then
    return false;
  end if;
  return exists (
    with recursive miembros as (
      select pg_catalog.unnest(v_personas) as id, 1 as n
      union all
      select i.id, m.n + 1
      from crm.inversionistas i join miembros m on i.inversionista_canonico_id = m.id
      where m.n < 16
    ), leads_persona as (
      select l.id from crm.leads l where l.inversionista_id in (select id from miembros)
      union
      select il.lead_id from crm.inversionista_leads il
       where il.inversionista_id in (select id from miembros) and il.hasta is null
    )
    select 1 from crm.leads o
    where o.id in (select id from leads_persona) and o.id <> p_lead
      and o.activo and o.etapa = 'convertido' and o.convertido_en < p_antes
      and not private.cierre_anulado(o.id)
    union all
    select 1 from crm.cierres_externos ce
    where ce.anulado_en is null and ce.creado_en < p_antes
      and (ce.lead_id in (select id from leads_persona)
           or ce.inversionista_id in (select id from miembros))
  );
end;
$function$;
alter function private.cita_con_cliente(uuid,timestamptz) owner to postgres;
revoke all on function private.cita_con_cliente(uuid,timestamptz) from public, anon, authenticated, service_role;
comment on function private.cita_con_cliente(uuid,timestamptz) is
  'Citas: true si la persona del lead (o una identidad fusionada con ella) tenía, estrictamente antes del instante dado, una conversión o un cierre externo que sigue vigente hoy. Auxiliar de los lectores de Citas (clave es_cliente); SECURITY INVOKER, sólo postgres.';

-- Reemplazo anclado único en los dos lectores. Si el ancla no aparece
-- exactamente una vez, no se instala nada.
do $parche$
declare
  v_objetos text[] := array[
    'private.citas_gerencia_consulta(date,date)',
    'private.citas_gerencia_consulta_corte(date,date,uuid)'];
  v_ancla text := $a$'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false)$a$;
  v_nuevo text := $n$'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false),
    'es_cliente',case when t.perfil_id is not null then true else private.cita_con_cliente(t.lead_id,t.creado_en) end$n$;
  v_objeto text;
  v_def text;
  v_veces integer;
begin
  foreach v_objeto in array v_objetos loop
    v_def := pg_catalog.pg_get_functiondef(v_objeto::regprocedure);
    v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
    if v_veces is distinct from 1 then
      raise exception 'es_cliente: el ancla aparece % veces en % (se esperaba 1)', v_veces, v_objeto;
    end if;
    if strpos(v_def, 'es_cliente') > 0 then
      raise exception 'es_cliente: % ya contiene la clave', v_objeto;
    end if;
    execute replace(v_def, v_ancla, v_nuevo);
  end loop;
end;
$parche$;

-- Los dos lectores siguen declarados con su clase; cambia la huella del cuerpo,
-- la razón deja rastro del cambio y el sello de la lista se vuelve a calcular.
update private.analitica_leads_citas_exenciones e
set huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
      pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
    razon = e.razon || ' Citas (19/10/2026): cada cita añade es_cliente (persona ya cliente antes de generarla, vía private.cita_con_cliente); sin cambio de alcance, población ni capital.'
from pg_catalog.pg_proc p
where e.objeto in ('private.citas_gerencia_consulta(date,date)',
                   'private.citas_gerencia_consulta_corte(date,date,uuid)')
  and p.oid = e.objeto::regprocedure;

update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

do $postflight$
declare
  v_objeto text;
  v_fn record;
  v_veces integer;
  v_md5_esperado text;
  v_clave text := $k$'es_cliente',case when t.perfil_id is not null then true else private.cita_con_cliente(t.lead_id,t.creado_en) end$k$;
begin
  foreach v_objeto in array array[
    'private.citas_gerencia_consulta(date,date)',
    'private.citas_gerencia_consulta_corte(date,date,uuid)'] loop
    select p.prosecdef, p.provolatile, p.proconfig, r.rolname, p.prosrc
      into v_fn
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    where p.oid = v_objeto::regprocedure;
    if v_fn.rolname is distinct from 'postgres' or not v_fn.prosecdef
       or v_fn.provolatile is distinct from 's'
       or v_fn.proconfig is distinct from array['search_path=""']::text[] then
      raise exception 'POSTFLIGHT es_cliente: atributos inesperados en %', v_objeto;
    end if;
    v_veces := (length(v_fn.prosrc) - length(replace(v_fn.prosrc, v_clave, ''))) / length(v_clave);
    if v_veces is distinct from 1 then
      raise exception 'POSTFLIGHT es_cliente: % no quedó con la clave exactamente una vez', v_objeto;
    end if;
    if strpos(v_fn.prosrc, 'v_rol not in (''gerencia'',''supervisor'')') = 0
       or strpos(v_fn.prosrc, 'private.vendedor_ids_visibles(v_uid)') = 0 then
      raise exception 'POSTFLIGHT es_cliente: la verja por rol de % no está intacta', v_objeto;
    end if;
    -- El cuerpo final es EXACTAMENTE el ensayado en el banco (cierra la ventana
    -- entre el preflight y la lectura de pg_get_functiondef).
    v_md5_esperado := case v_objeto
      when 'private.citas_gerencia_consulta(date,date)' then '676f078a7755583c10cb2611bc88eb0c'
      else '387c8f36aa5a24dd6ee3fde66bd98349' end;
    if pg_catalog.md5(v_fn.prosrc) is distinct from v_md5_esperado then
      raise exception 'POSTFLIGHT es_cliente: % no quedó con el cuerpo ensayado (md5 %)', v_objeto, pg_catalog.md5(v_fn.prosrc);
    end if;
    if not exists (
      select 1
      from private.analitica_leads_citas_exenciones e
      join pg_catalog.pg_proc p on p.oid = v_objeto::regprocedure
      where e.objeto = v_objeto
        and e.huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
          pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
    ) then
      raise exception 'POSTFLIGHT es_cliente: % no quedó declarado con su huella instalada', v_objeto;
    end if;
  end loop;
  -- Atributos y permisos de las cuatro funciones de Citas, idénticos a la foto.
  if exists (
    select 1 from es_cliente_atributos_antes a
    join pg_catalog.pg_proc p on p.oid = a.oid
    where (a.proowner, a.proacl, a.prosecdef, a.provolatile, a.proconfig)
      is distinct from (p.proowner, p.proacl, p.prosecdef, p.provolatile, p.proconfig)
  ) then
    raise exception 'POSTFLIGHT es_cliente: cambiaron atributos o permisos de una función de Citas';
  end if;
  -- La auxiliar: INVOKER, estable, search_path vacío, sólo postgres.
  select p.prosecdef, p.provolatile, p.proconfig, r.rolname, p.prosrc
    into v_fn
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'private.cita_con_cliente(uuid,timestamptz)'::regprocedure;
  if v_fn.rolname is distinct from 'postgres' or v_fn.prosecdef
     or v_fn.provolatile is distinct from 's'
     or v_fn.proconfig is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT es_cliente: atributos inesperados en la auxiliar';
  end if;
  if exists (
    select 1 from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where p.oid = 'private.cita_con_cliente(uuid,timestamptz)'::regprocedure
      and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'POSTFLIGHT es_cliente: la auxiliar tiene EXECUTE fuera de postgres';
  end if;
  if pg_catalog.has_function_privilege('anon', 'private.cita_con_cliente(uuid,timestamptz)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'private.cita_con_cliente(uuid,timestamptz)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'private.cita_con_cliente(uuid,timestamptz)', 'EXECUTE') then
    raise exception 'POSTFLIGHT es_cliente: un rol de la API puede ejecutar la auxiliar';
  end if;
  if pg_catalog.has_function_privilege('anon', 'crm.citas_gerencia_consulta_fn(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.citas_gerencia_consulta_v2_fn(date,date)', 'EXECUTE') then
    raise exception 'POSTFLIGHT es_cliente: anon no debe ejecutar las puertas de Citas';
  end if;
  -- El sello cuadra y el censo analítico queda EXACTAMENTE como estaba.
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT es_cliente: el sello analítico no coincide';
  end if;
  if exists (
    (select * from es_cliente_censo_antes except all select * from private.contadores_crudos_leads_citas())
    union all
    (select * from private.contadores_crudos_leads_citas() except all select * from es_cliente_censo_antes)
  ) then
    raise exception 'POSTFLIGHT es_cliente: cambió el censo analítico fuera de su estado previo';
  end if;
  -- La auxiliar no entra en ninguno de los tres censos.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = 'private.cita_con_cliente(uuid,timestamp with time zone)'
                or c.objeto = 'private.cita_con_cliente(uuid,timestamptz)') then
    raise exception 'POSTFLIGHT es_cliente: la auxiliar entró al censo analítico';
  end if;
  if exists (select 1 from private.puertas_analista_sin_vigencia() c
             where c.objeto in ('private.cita_con_cliente(uuid,timestamp with time zone)',
                                'private.cita_con_cliente(uuid,timestamptz)')) then
    raise exception 'POSTFLIGHT es_cliente: la auxiliar entró al censo de vigencia del analista';
  end if;
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and p.oid = 'private.cita_con_cliente(uuid,timestamptz)'::regprocedure
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT es_cliente: la auxiliar nombra una pieza cerrada de F7';
  end if;
end;
$postflight$;
commit;
