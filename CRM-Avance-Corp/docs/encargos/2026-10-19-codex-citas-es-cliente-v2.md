ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 3, SEGUNDA Y ÚLTIMA pasada con evidencia nueva): REFUTA la versión 2 de la migración «Citas: marca es_cliente por cita» (20261019170214)

Tu primera revisión (CHANGES_REQUESTED) y la del auditor RLS se aceptaron. Cambios respecto a la v1 que revisaste:
- DEFINICIÓN explícita en cabecera, comentario y ledger: «ya era cliente» = conversión o cierre externo ESTRICTAMENTE ANTERIOR a la creación de la cita y VIGENTE HOY (una anulación posterior la quita, como quita la venta en todo el CRM; una rehabilitación la devuelve). Decisión del PRIMARY, no un defecto.
- La auxiliar pasa a plpgsql con camino rápido (el propio lead), `o.activo`, `il.hasta is null`, sin la afirmación falsa del comentario; en el lector se llama con `case when t.perfil_id is not null then true else … end`.
- El guardián global `assert_analitica_leads_citas()` está en ROJO en producción por nueve piezas ajenas (medido): la migración ya no lo llama; guarda la foto del censo (`contadores_crudos_leads_citas()`) y de atributos/ACL de las cuatro funciones de Citas y exige que queden idénticos; preflight exige sello consistente y los dos lectores `declarada and huella_ok`; postflight añade `has_function_privilege` para anon/authenticated/service_role y comprueba que la auxiliar no entra en los tres censos (analítico, vigencia, F7).
- Razón de las dos declaraciones ampliada con el rastro del cambio.
- Reversión escrita como script aparte y ENSAYADA.

## Evidencia nueva (banco Docker propio a paridad con producción, 19/10/2026)
- Banco: `supabase db dump --linked --schema public,crm,private` cargado en Postgres 17.6 de Supabase; 364 funciones `crm`, 778 `private`, 117 tablas `crm`, 33 `private`: iguales a producción. md5(prosrc) de los dos lectores y de `inversionista_canonica`, `cierre_anulado`, `contadores_crudos_leads_citas`, `huella_exenciones_analitica_lc`, `puertas_analista_sin_vigencia` IGUALES a producción. Censo sembrado con las 46 exenciones, el sello y el tope reales (exportados con `format(%L)`): `sello cuadra = true`, 47 contadores / 9 sin declarar, igual que producción.
- Migración aplicada en UN mensaje (`psql -c`): preflight, auxiliar, parche de los dos lectores, `UPDATE 2` huellas, `UPDATE 1` sello, postflight, COMMIT. Después: auxiliar existe, v1 md5 `676f078a…`, corte md5 `387c8f36…`, sello cuadra, lectores declarados y vigentes = 2, censo 47/9 intacto, auxiliar fuera del censo.
- Casos de la auxiliar con fixtures (transacción deshecha, disparadores apagados sólo para sembrar): 11/11 OK — lead sin persona → false; convertido antes → true; cita antes de convertirse → false; mismo instante → false; lead inactivo convertido → false; persona fusionada (`inversionista_canonico_id`) con otro lead convertido antes → true; cita anterior a esa conversión → false; cierre externo vigente → true; cierre externo anulado → false; convertido pero con cierre inicial anulado (`cierre_anulado`) → false; lead nulo → false.
- Lector de extremo a extremo con una gerencia sintética (`rol_crm = gerencia`) y tres citas de octubre: `citas_gerencia_consulta_fn` devuelve 3 citas con `es_cliente` true/true/false como se esperaba y las 24 claves previas intactas; `citas_gerencia_consulta_corte` con un corte inexistente devuelve lo mismo.
- Coste medido en producción a través de la función REAL (creada en `pg_temp` dentro de un `DO` que termina en `raise`, deshecho): 609 citas de octubre → 507 ms; 1 104 citas (ago–oct) → 764 ms. La lógica en línea tardaba 151 ms: el sobrecoste es plpgsql + 4 consultas por cita.
- Reversión ensayada en el banco: ambos lectores vuelven a `d07e19d9…` / `89ef3e8c…`, la auxiliar desaparece, el sello vuelve a `0262227b9139d20e821a41bd45a5339d` (el valor vivo de producción) y el censo queda idéntico; luego la migración se reaplicó limpia.

## Preguntas concretas
1. Con la definición «anterior y vigente hoy» ya explícita, ¿queda algún caso real mal clasificado que importe para el negocio? (Sé que `inversionista_leads.hasta` está siempre nulo hoy.)
2. ¿Ves un camino por el que el parche o la foto del censo deje producción distinta de lo ensayado (el banco es esquema puro: sin datos ni roles de usuario reales; `crm_metricas_bridge` existe pero tres `alter owner` fallaron en la carga)?
3. ¿Aceptarías el coste (≈0,5 s añadidos a un mes de 600 citas) o exiges el cálculo por conjunto antes de instalar? Argumenta con lo que sabes del lector (10 000 filas de tope, refresco de 60 s en pantalla).
4. ¿Algo en la reversión que deje el sello o las huellas mal si se ejecuta tras OTRA migración posterior que toque los lectores?
5. ¿Qué prueba te falta para dar APPROVE? Si no falta ninguna, dilo.

## Archivos (transcritos íntegros)

### supabase/migrations/20261019170214_crm_citas_es_cliente_por_cita.sql
```sql
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
  -- Persona enlazada: enlace vivo del lead o historial de identidad vigente.
  select array_agg(distinct private.inversionista_canonica(x.id)) into v_personas
  from (
    select l.inversionista_id as id from crm.leads l
     where l.id = p_lead and l.inversionista_id is not null
    union
    select il.inversionista_id from crm.inversionista_leads il
     where il.lead_id = p_lead and il.hasta is null
  ) x;
  if v_personas is null then
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
```

### supabase/scripts/revertir-20261019170214-citas-es-cliente.sql
```sql
-- Reversión de 20261019170214_crm_citas_es_cliente_por_cita.sql (ensayada en el banco
-- Docker el 19/10/2026). Deja los dos lectores de Citas con su cuerpo anterior exacto,
-- re-declara sus huellas, re-sella el censo y retira la auxiliar. Un solo mensaje.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;

create temporary table es_cliente_rev_censo_antes on commit drop as
  select * from private.contadores_crudos_leads_citas();

do $revertir$
declare
  v_objetos text[] := array[
    'private.citas_gerencia_consulta(date,date)',
    'private.citas_gerencia_consulta_corte(date,date,uuid)'];
  v_esperado text[] := array['d07e19d9731f3a7c6aef2a82f5745d58', '89ef3e8cc067c344641f247e519007a6'];
  v_clave text := $k$,
    'es_cliente',case when t.perfil_id is not null then true else private.cita_con_cliente(t.lead_id,t.creado_en) end$k$;
  v_i integer; v_def text; v_veces integer; v_md5 text;
begin
  for v_i in 1..2 loop
    v_def := pg_catalog.pg_get_functiondef(v_objetos[v_i]::regprocedure);
    v_veces := (length(v_def) - length(replace(v_def, v_clave, ''))) / length(v_clave);
    if v_veces is distinct from 1 then
      raise exception 'REVERSIÓN es_cliente: la clave aparece % veces en % (se esperaba 1)', v_veces, v_objetos[v_i];
    end if;
    execute replace(v_def, v_clave, '');
    select pg_catalog.md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p where p.oid = v_objetos[v_i]::regprocedure;
    if v_md5 is distinct from v_esperado[v_i] then
      raise exception 'REVERSIÓN es_cliente: % no volvió a su cuerpo anterior (md5 %)', v_objetos[v_i], v_md5;
    end if;
  end loop;
end;
$revertir$;

update private.analitica_leads_citas_exenciones e
set huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
      pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
    razon = replace(e.razon, ' Citas (19/10/2026): cada cita añade es_cliente (persona ya cliente antes de generarla, vía private.cita_con_cliente); sin cambio de alcance, población ni capital.', '')
from pg_catalog.pg_proc p
where e.objeto in ('private.citas_gerencia_consulta(date,date)',
                   'private.citas_gerencia_consulta_corte(date,date,uuid)')
  and p.oid = e.objeto::regprocedure;

update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

drop function private.cita_con_cliente(uuid,timestamptz);

do $postflight$
begin
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSIÓN es_cliente: el sello analítico no coincide';
  end if;
  if (select count(*) from private.contadores_crudos_leads_citas() c
      where c.objeto in ('private.citas_gerencia_consulta(date,date)',
                         'private.citas_gerencia_consulta_corte(date,date,uuid)')
        and c.declarada and c.huella_ok) <> 2 then
    raise exception 'REVERSIÓN es_cliente: los lectores no quedaron declarados con huella vigente';
  end if;
  if exists (
    (select * from es_cliente_rev_censo_antes except all select * from private.contadores_crudos_leads_citas())
    union all
    (select * from private.contadores_crudos_leads_citas() except all select * from es_cliente_rev_censo_antes)
  ) then
    raise exception 'REVERSIÓN es_cliente: cambió el censo analítico';
  end if;
end;
$postflight$;
commit;
```

## Protocolo de revisión (global)

# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.


## Formato de respuesta
VERDICT (APPROVE / CHANGES_REQUESTED / REJECT) · SUMMARY · FINDINGS P0–P3 (archivo:línea, evidencia, hipótesis separadas) · RISKS / TEST GAPS · NEXT ACTIONS · CONFIDENCE. Responde en español.
