-- REGISTRO en supabase_migrations.schema_migrations de 20261001212341_crm_cartera_filtro_potencial.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 7bc7f15233bd36657ee3f79b5e28f55c).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_cartera_filtro_potencial_registro'));
do $chk$
begin
  if (
    to_regprocedure('private.cartera_potencial_fn()') is not null
    and to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261001212341 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261001212341' and (coalesce(name, '') <> 'crm_cartera_filtro_potencial' or statements is distinct from array[$mig$-- 20261001212341_crm_cartera_filtro_potencial.sql
--
-- Potencial del lead · FASE 3, entrega B (servidor): filtrar y contar Leads por potencial.
-- Plan aprobado por Miguel el 01/10/2026 («ok dale con el plan B, todo lo recomendado»: el filtro va
-- solo en Leads, «Sin marcar» es una opción y se elige un nivel a la vez). Nota del vault:
-- «Potencial del lead - Frio Tibio Estrella (2026-09-30)», «Fase 3 · entrega B».
--
-- QUÉ. `crm.cartera_filtrada_fn` gana UN argumento al final, `p_potencial text default null`:
--   · null                          → no recorta;
--   · 'estrella' | 'tibio' | 'frio' → leads cuya marca VIGENTE es ese nivel;
--   · 'sin_marca'                   → leads sin marca;
--   · cualquier otro valor          → 22023, por el mismo bloque de validación que los demás filtros;
--   · con la bandera `potencial_lead` apagada, pedirlo → 55000 (igual que la puerta de marcar);
--     lo mismo para quien no tiene ámbito de filas (ni global ni analistas visibles: coordinación).
--   Y el resumen gana UNA clave, `resumen.potencial` = {filtro, estrella, tibio, frio, sin_marca}:
--   cuántos leads hay de cada nivel con los DEMÁS filtros puestos. Se cuenta ANTES de aplicar
--   `p_potencial`: los cuatro números no cambian al elegir un nivel, suman el total sin ese filtro
--   y el del nivel elegido coincide con `totales.vivos`. `filtro` es el eco del pedido. La clave
--   solo viaja con la bandera encendida y para quien tiene ámbito de filas.
--
-- CÓMO LEE LA MARCA. La función es INVOKER y las tablas del potencial no tienen grants de API
--   (fase 1, auditor-rls r1): nace `private.cartera_potencial_fn()`, un ayudante con el molde de
--   `private.cartera_recepciones_fn` (el otro ayudante de esta misma función). Devuelve
--   (lead_id, nivel) de las marcas vigentes de los leads que el actor PUEDE VER.
-- SECURITY DEFINER, justificación: una función INVOKER no puede leer `crm.lead_potencial` (sin
--   grants para nadie de la API, y así se queda). El ayudante verifica de forma explícita la sesión,
--   el gate del CRM (`private.puede_acceder_crm`, invocado) y el ÁMBITO, que es el ESPEJO EXACTO de
--   la policy `leads_select` (el mismo de `private.potencial_lectura`, fase 3A): ve la marca solo
--   quien ve el lead, en cualquier contexto. El preflight fija por md5 esa policy, el gate
--   restrictivo de `crm.leads` y los ayudantes en que se apoyan: si alguno cambió desde el ensayo,
--   la migración se niega. `search_path` vacío, dueño postgres, EXECUTE solo `authenticated`; el
--   esquema `private` no está expuesto en la API.
--   Consecuencia buscada (Codex f3b r1 y auditor-rls f3b, P2-1): `crm.resumen_cartera_fn`
--   (DEFINER) llama a la cartera SIN RLS y su base incluye, para quien opera el reparto
--   (coordinación), una bandeja que su RLS no deja ver. El ayudante NO entrega esas marcas, y la
--   cartera ni siquiera emite `resumen.potencial` para quien no tiene ámbito de filas: ningún
--   conteo por nivel revela la marca de un lead que el actor no puede leer. Si un actor con ámbito
--   de filas opera además el reparto, dentro del envoltorio las marcas que no ve cuentan como
--   «sin marca». Por la API (INVOKER) no hay diferencia: la RLS ya recorta la base.
--
-- QUÉ NO CAMBIA. Con la bandera apagada la respuesta es byte a byte la de la firma de 13 (y el
--   ayudante ni se llama). Con la bandera encendida y sin el filtro, solo se AÑADE `resumen.potencial` (clave nueva dentro del
--   resumen: los frentes publicados leen el resumen con un esquema que ignora las claves de más).
--   Las filas tienen la forma de siempre (la columna de trabajo `potencial_nivel` se quita antes
--   de serializar), no hay claves nuevas arriba, y siguen igual INVOKER, `stable`, `search_path`
--   vacío, dueño y ACL. Los demás filtros y la regla de gestión (anclas de 20261001154153) no se
--   tocan: el cuerpo nuevo sale del vivo por sustituciones exactas, no se reteclea. Una sola firma:
--   se retira la de 13 (dos candidatas romperían PostgREST) y su exención analítica se MUEVE a la
--   de 14 (misma clase, tipo y fecha de declaración) y se resella. El orden de las listas no cambia.
--
-- ORDEN DE PUBLICACIÓN: servidor primero, pantalla después. El frente nuevo envía `p_potencial` y
--   sin esta migración recibiría PGRST202; los frentes publicados no lo envían y siguen igual.
--
-- REVERSA: `supabase/scripts/potencial-lead/reversa-filtro.sql`, tras retirar el frente que envía
--   `p_potencial`. Quita la firma de 14 y el ayudante, reinstala la de 13 byte a byte (md5
--   bf06666f…), devuelve la exención analítica a su firma y resella. No toca datos.
--
-- Las huellas se midieron con `search_path` vacío y sin comillas forzadas, que se fijan abajo para
-- la transacción: el texto de `pg_get_functiondef` cambia con el `search_path` de la sesión y con
-- `quote_all_identifiers`.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
set local quote_all_identifiers = off;

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  v_huellas text;
  v_policies text;
begin
  -- 1. La función viva es la auditada: una sola firma (la de 13) y su cuerpo exacto.
  --    Guardas en positivo con `is not true`: un NULL también rechaza.
  if (
    to_regprocedure(f14) is null
    and to_regprocedure(f13) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f13))) = 'bf06666fb8ef533a39a50c7d70420153'
    and to_regprocedure('private.cartera_potencial_fn()') is null
  ) is not true then
    raise exception 'PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada';
  end if;
  -- 2. Su declaración analítica está vigente (huella al día), es de inventario y la lista está
  --    sellada: esta migración la mueve y resella; no se resella a ciegas una lista alterada.
  if (
    exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = f13_larga and c.declarada and c.huella_ok)
    and (select e.clase from private.analitica_leads_citas_exenciones e
          where e.objeto = f13_larga) = 'operativo'
    and (select s.sello from private.analitica_lc_sello s where s.id)
          = private.huella_exenciones_analitica_lc()
  ) is not true then
    raise exception 'PREFLIGHT: la declaracion analitica no esta vigente y sellada';
  end if;
  -- 3. La función sigue leyendo `crm.actividades` como INVOKER (reasignados, gestión, contacto).
  perform private.assert_actividades_de_lead_base();
  -- 4. El potencial está instalado como se ensayó: la tabla de la marca vigente con sus columnas,
  --    una fila por lead, RLS encendida, SIN grants para la API (por eso hace falta el ayudante),
  --    y su bandera.
  if (
    (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum)
       from pg_attribute a
      where a.attrelid = to_regclass('crm.lead_potencial') and a.attnum > 0 and not a.attisdropped)
      = 'id:uuid,lead_id:uuid,nivel:crm.nivel_potencial,origen:text,marcado_por:uuid,marcado_en:timestamp with time zone,creado_en:timestamp with time zone,actualizado_en:timestamp with time zone'
    and (select c.relrowsecurity from pg_class c where c.oid = to_regclass('crm.lead_potencial'))
    -- La premisa de la cartera INVOKER: la RLS de crm.leads está encendida.
    and (select c.relrowsecurity from pg_class c where c.oid = 'crm.leads'::regclass)
    -- Una fila por lead: la cartera une las marcas por `lead_id` y un duplicado repetiría el lead.
    and exists (select 1 from pg_index i
                 where i.indrelid = to_regclass('crm.lead_potencial') and i.indisunique and i.indisvalid
                   and i.indpred is null and i.indnkeyatts = 1
                   and i.indkey[0] = (select a.attnum from pg_attribute a
                                       where a.attrelid = i.indrelid and a.attname = 'lead_id'))
    and not has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_table_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and (select count(*) from crm.multiempresa_flags f where f.nombre = 'potencial_lead') = 1
    and (select array_agg(e.enumlabel::text order by e.enumsortorder)
           from pg_enum e where e.enumtypid = to_regtype('crm.nivel_potencial'))
        = array['frio', 'tibio', 'estrella']
  ) is not true then
    raise exception 'PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo';
  end if;
  -- 5. El ámbito del ayudante descansa en estos ayudantes, los mismos de `leads_select`:
  --    identidad por cuerpo + DEFINER + volatilidad + configuración + dueño.
  select string_agg(
           p.oid::regprocedure::text || '=' ||
           md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
               || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text),
           ' ' order by p.oid::regprocedure::text)
    into v_huellas
  from pg_proc p
  where p.oid in (to_regprocedure('private.rol_crm(uuid)'),
                  to_regprocedure('private.vendedor_ids_visibles(uuid)'),
                  to_regprocedure('private.es_lector_global()'),
                  to_regprocedure('private.puede_acceder_crm()'),
                  to_regprocedure('crm.bandera_activa(text)'));
  if v_huellas is distinct from
       'crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc'
    || ' private.es_lector_global()=5b8ac0c37dcbf5b82057d7b98c65c303'
    || ' private.puede_acceder_crm()=4e2c1caf7ead51be450d5018be4c6092'
    || ' private.rol_crm(uuid)=16960a2a21cc5c372431c2dd67acafe4'
    || ' private.vendedor_ids_visibles(uuid)=45ae492c03234b80336c0b8f5c8ac09b' then
    raise exception 'PREFLIGHT: un ayudante de visibilidad no es el ensayado: %', coalesce(v_huellas, '(ninguno)');
  end if;
  -- Las policies que deciden qué leads se LEEN: exactamente la permisiva `leads_select` (la que el
  -- ayudante copia) y el gate restrictivo `crm_actor_activo_gate` (el que invoca). Una policy de
  -- lectura nueva o un cambio en estas dos dejaría al ayudante viendo de más o de menos.
  select string_agg(
           pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
           || pol.polroles::regrole[]::text || '|' || md5(pg_get_expr(pol.polqual, pol.polrelid)),
           ' ## ' order by pol.polname)
    into v_policies
  from pg_policy pol
  where pol.polrelid = 'crm.leads'::regclass and pol.polcmd in ('r', '*');
  if v_policies is distinct from
       'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
    || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e' then
    raise exception 'PREFLIGHT: las policies de lectura de crm.leads no son las ensayadas: %', coalesce(v_policies, '(ninguna)');
  end if;
  -- 6. La función INVOKER debe poder llamar a la bandera, y la API no.
  if (
    has_function_privilege('authenticated', 'crm.bandera_activa(text)', 'EXECUTE')
    and not has_function_privilege('anon', 'crm.bandera_activa(text)', 'EXECUTE')
    and has_schema_privilege('authenticated', 'private', 'USAGE')
  ) is not true then
    raise exception 'PREFLIGHT: los permisos de crm.bandera_activa o del esquema private no son los ensayados';
  end if;
  -- 7. Quién llama a la cartera en el servidor: solo el envoltorio `crm.resumen_cartera_fn`, con el
  --    cuerpo ensayado (no pasa filtros del llamante). Otro consumidor, o un envoltorio distinto,
  --    recibiría `resumen.potencial` sin haberse revisado.
  if (
    (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
       from pg_proc p where p.prosrc ~* 'cartera_filtrada_fn') = 'crm.resumen_cartera_fn()'
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = '4a896597486e8b23788a2b2497f16309'
  ) is not true then
    raise exception 'PREFLIGHT: los consumidores de servidor de la cartera no son los ensayados';
  end if;
end;
$preflight$;

-- Foto de lo que NO debe cambiar: contrato de seguridad de la función, censo analítico,
-- declaraciones ajenas, la propia declaración (clase, tipo y fecha) y el consumidor.
create temporary table cartera_potencial_preflight on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

-- ── 1 · Ayudante: la marca vigente de los leads del ámbito ─────────────────────
create function private.cartera_potencial_fn()
returns table(lead_id uuid, nivel text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
begin
  -- El gate RESTRICTIVO de crm.leads (crm_actor_activo_gate) se INVOCA en vez de copiarse.
  if v_uid is null or private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Con la bandera apagada no se lee nada (igual que crm.potencial_leads_fn).
  if crm.bandera_activa('potencial_lead') is not true then
    return;
  end if;
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  -- Se resuelve UNA vez (la policy lo evalúa como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  return query
    select p.lead_id, p.nivel::text
    from crm.lead_potencial p
    join crm.leads l on l.id = p.lead_id
    -- ── ESPEJO EXACTO de la policy leads_select (fijada por md5 en el preflight) ──
    --   activo = true and ( vendedor_id in (vendedor_ids_visibles(uid))
    --                       or (vendedor_id is null and asignado_supervisor_id in (...))
    --                       or rol_crm(uid) = 'gerencia' or es_lector_global() )
    where l.activo = true
      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      );
end;
$$;
alter function private.cartera_potencial_fn() owner to postgres;
revoke all on function private.cartera_potencial_fn() from public, anon, authenticated, service_role;
grant execute on function private.cartera_potencial_fn() to authenticated;
comment on function private.cartera_potencial_fn() is
  'Ayudante de crm.cartera_filtrada_fn: (lead_id, nivel) de la marca de potencial vigente de los leads que el actor puede ver (espejo exacto de la policy leads_select: activos, de sus analistas visibles, parqueados en un supervisor visible, o todo para gerencia y lector global). SECURITY DEFINER porque crm.lead_potencial no tiene grants de API; exige sesion y el gate del CRM (42501). Con la bandera potencial_lead apagada no devuelve filas. No entrega la bandeja del reparto que la RLS no deja ver: dentro de crm.resumen_cartera_fn esas marcas cuentan como sin marca. No esta expuesto en la API (esquema private).';

-- ── 2 · La cartera: una sola firma, la de 14 ───────────────────────────────────
drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text);

create function crm.cartera_filtrada_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null,
  p_desde date default null,
  p_hasta date default null,
  p_origen text default null,
  p_procedencia text default null,
  p_reasignados boolean default false,
  p_gestion text default null,
  p_potencial text default null
)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
  v_potencial boolean;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     -- Mismo dominio que el CHECK de crm.leads.origen: los 5 vigentes y los 3
     -- históricos (web, campania, whatsapp) siguen siendo consultables.
     or (p_origen is not null and p_origen not in
       ('referido','landing','formulario','oficina','otro','web','campania','whatsapp'))
     -- Procedencia: 'sistema' (puente automático) o 'manual' (una persona).
     -- Otro valor se rechaza: nunca un «cero resultados» silencioso.
     or (p_procedencia is not null and p_procedencia not in ('sistema','manual'))
     -- Gestión: 'con_gestion' (el titular actual ya intentó el contacto) o
     -- 'sin_gestion' (el resto). Otro valor se rechaza, igual que arriba.
     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))
     -- Potencial: uno de los tres niveles o 'sin_marca' (leads sin marca). Otro valor se
     -- rechaza, igual que arriba.
     or (p_potencial is not null and p_potencial not in ('estrella','tibio','frio','sin_marca'))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();
  -- El potencial solo existe con su bandera encendida y para quien tiene ámbito de FILAS (global
  -- o con analistas visibles). Sin eso la respuesta es la de siempre (sin `resumen.potencial`) y
  -- pedir el filtro se rechaza como en la puerta de marcar. Quien solo opera el reparto no lee
  -- leads por su RLS: tampoco recibe conteos por nivel (ni dentro de crm.resumen_cartera_fn).
  v_potencial := crm.bandera_activa('potencial_lead') is true
    and (coalesce(v_global, false) or cardinality(v_visibles) > 0);
  if p_potencial is not null and not v_potencial then
    raise exception 'El potencial del lead no está habilitado' using errcode = '55000';
  end if;

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), marcas as materialized (
    -- Marca vigente de los leads que el actor puede ver. Ayudante DEFINER: las tablas del
    -- potencial no tienen grants de API. Sin potencial para este actor, ni se le llama.
    select m.lead_id, m.nivel from private.cartera_potencial_fn() m where v_potencial
  ), previa as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada,
      mk.nivel as potencial_nivel
    from crm.leads l
    -- Una primera entrega desde la cola tiene vendedor_anterior NULL. Solo
    -- cuenta un analista ANTERIOR, incluso si volvió al mismo titular tras
    -- pasar por la bandeja. El evento lo emite el trigger del servidor.
    left join lateral (
      select true as reasignado
      from crm.actividades a
      where l.vendedor_id is not null
        and a.lead_id = l.id
        and a.tipo = 'reasignacion'
        and a.metadata ->> 'vendedor_anterior' is not null
      limit 1
    ) mov on true
    left join recepciones r on r.lead_id = l.id
    left join marcas mk on mk.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      -- El origen acota la MISMA base: filas, totales, capital y embudo juntos.
      and (p_origen is null or l.origen = p_origen)
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      -- Gestión vigente: el titular ACTUAL ya intentó el contacto desde que
      -- recibió el lead (`tenencia_desde`, que se renueva al reasignar y al
      -- reabrir). Lo que gestionó un titular anterior no cuenta, ni un resultado
      -- de llamada deshecho (`deshecho_en`: no ocurrió); sin titular o sin
      -- tenencia no hay gestión. Acota la MISMA base; el payload no cambia.
      and (p_gestion is null or (l.vendedor_id is not null
        and l.tenencia_desde is not null
        and exists (select 1 from crm.actividades g
          where g.lead_id = l.id
            and g.tipo in ('llamada_realizada','llamada_no_contestada',
              'whatsapp_enviado','whatsapp_recibido','reunion_realizada')
            and g.creado_en >= l.tenencia_desde
            and not (g.metadata ? 'deshecho_en'))) = (p_gestion = 'con_gestion'))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), base as not materialized (
    -- El potencial recorta DESPUÉS de los demás filtros: `previa` alimenta los conteos por
    -- nivel (cuántos hay de cada uno con los demás filtros puestos, sin que cambien al elegir
    -- uno) y `base`, como siempre, las filas, los totales, el capital y el embudo.
    select pv.* from previa pv
    where p_potencial is null
      or (p_potencial = 'sin_marca' and pv.potencial_nivel is null)
      or pv.potencial_nivel = p_potencial
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where reasignado) as reasignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,'procedencia',p_procedencia,
    'reasignados',coalesce(p_reasignados,false),
    -- La columna de trabajo `potencial_nivel` no viaja: las filas tienen la forma de siempre.
    'items',coalesce((select jsonb_agg(to_jsonb(f) - 'potencial_nivel' order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord)))
      -- Conteos por nivel sobre `previa` (antes de `p_potencial`) y el eco del filtro. Solo con
      -- el potencial vigente para el actor: si no, el resumen es byte a byte el de antes.
      || case when v_potencial then jsonb_build_object('potencial',(select jsonb_build_object(
          'filtro',p_potencial,
          'estrella',count(*) filter(where pv.potencial_nivel='estrella'),
          'tibio',count(*) filter(where pv.potencial_nivel='tibio'),
          'frio',count(*) filter(where pv.potencial_nivel='frio'),
          'sin_marca',count(*) filter(where pv.potencial_nivel is null)) from previa pv))
        else '{}'::jsonb end)
  into v_salida;
  return v_salida;
end;
$$;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) is
  'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista), gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto) y potencial (p_potencial: estrella, tibio, frio o sin_marca; con la bandera potencial_lead apagada se rechaza con 55000). Listado y resumen salen de la misma base; resumen.potencial cuenta cada nivel con los demas filtros puestos, antes de aplicar p_potencial; solo viaja con la bandera encendida y para quien tiene ambito de filas (global o con analistas visibles), y cuenta solo las marcas que el actor puede ver por la RLS de crm.leads (una marca que no puede ver cuenta como sin_marca).';

-- La declaración analítica se MUEVE a la firma nueva (misma fila: conserva clase, tipo y
-- fecha), con la huella del cuerpo nuevo, y la lista se resella.
update private.analitica_leads_citas_exenciones e set
  objeto = p.oid::regprocedure::text,
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia, reasignacion entre analistas, gestion del titular actual y potencial del lead. No calcula conversion mensual.'
from pg_proc p
where p.oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'::regprocedure
  and e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  f14_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  ayudante constant text := 'private.cartera_potencial_fn()';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_potencial_preflight;
  -- 1. Una sola firma, la de 14, con el cuerpo ENSAYADO (md5 medido en el banco con
  --    search_path vacío) y el mismo contrato de seguridad que la que sustituye.
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f14) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f14))) = '23a63cc3965472b9db85aa81cadffbeb'
    and not has_function_privilege('anon', f14, 'EXECUTE')
    and not has_function_privilege('service_role', f14, 'EXECUTE')
    and has_function_privilege('authenticated', f14, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f14)) p) = pre.contrato
  ) is not true then
    raise exception 'POSTFLIGHT: firma, cuerpo, permisos o contrato invalido';
  end if;
  -- 2. El ayudante: el cuerpo ENSAYADO (md5 medido en el banco: gate, bandera y espejo de la
  --    policy; Codex f3b r1), DEFINER, STABLE, dueño postgres, configuración EXACTA (solo
  --    search_path vacío), ACL explícita (postgres y authenticated; authenticated solo EXECUTE y
  --    sin opción de concederlo), permisos EFECTIVOS (authenticated sí; anon y service_role no) y
  --    sin conteos.
  if (
    md5(pg_get_functiondef(to_regprocedure(ayudante))) = '73e993d618b203cdbe21e8127f7ea5b4'
    and exists (select 1 from pg_proc p
             where p.oid = to_regprocedure(ayudante) and p.prosecdef
               and p.proowner = 'postgres'::regrole and p.provolatile = 's'
               and p.proconfig = array['search_path=""']::text[] and p.proacl is not null
               and p.prosrc !~* '(count|sum)\s*\(')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                     where p.oid = to_regprocedure(ayudante)
                       and (a.grantee not in ('postgres'::regrole, 'authenticated'::regrole)
                            or (a.grantee = 'authenticated'::regrole
                                and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
    and has_function_privilege('authenticated', ayudante, 'EXECUTE')
    and not has_function_privilege('anon', ayudante, 'EXECUTE')
    and not has_function_privilege('service_role', ayudante, 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated';
  end if;
  -- 3. La tabla de la marca sigue sin grants para la API: esta migración no abre ninguno.
  if (
    not has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_table_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT')
  ) is not true then
    raise exception 'POSTFLIGHT: crm.lead_potencial quedo con algun grant de lectura para la API';
  end if;
  -- 4. El sello quedó vigente, la firma nueva está declarada con su huella y nada ajeno se
  --    movió: mismo censo, mismo conjunto en rojo (si lo había), mismas declaraciones ajenas,
  --    la propia conserva clase, tipo y fecha, y el consumidor `resumen_cartera_fn` intacto.
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f14_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f14_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f14_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
    and (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
           from pg_proc p where p.prosrc ~* 'cartera_filtrada_fn') = 'crm.resumen_cartera_fn()'
  ) is not true then
    raise exception 'POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  perform private.assert_actividades_de_lead_base();
  -- 5. La policy que el ayudante copia sigue siendo la del preflight al terminar.
  if (
    (select string_agg(pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
              || pol.polroles::regrole[]::text || '|' || md5(pg_get_expr(pol.polqual, pol.polrelid)),
              ' ## ' order by pol.polname)
       from pg_policy pol
      where pol.polrelid = 'crm.leads'::regclass and pol.polcmd in ('r', '*'))
    = 'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
      || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e'
  ) is not true then
    raise exception 'POSTFLIGHT: las policies de lectura de crm.leads cambiaron durante la instalacion';
  end if;
  -- 6. Sin sesión, el ayudante y la función se niegan (aquí no hay sesión de usuario).
  --    Y por SU guarda («No autorizado»), no por cualquier otro 42501.
  begin
    perform 1 from private.cartera_potencial_fn();
    raise exception 'POSTFLIGHT: el ayudante acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then
    if sqlerrm is distinct from 'No autorizado' then
      raise exception 'POSTFLIGHT: el ayudante rechazo por otro motivo: %', sqlerrm using errcode = 'P0001';
    end if;
  end;
  begin
    perform crm.cartera_filtrada_fn(p_limite => 1, p_potencial => 'estrella');
    raise exception 'POSTFLIGHT: la cartera acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then
    if sqlerrm is distinct from 'No autorizado' then
      raise exception 'POSTFLIGHT: la cartera rechazo por otro motivo: %', sqlerrm using errcode = 'P0001';
    end if;
  end;
  raise notice 'cartera_filtro_potencial OK: firma unica de 14 argumentos, ayudante DEFINER con el cuerpo ensayado y solo para authenticated, contrato de seguridad intacto, declaracion analitica movida y sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261001212341 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261001212341', 'crm_cartera_filtro_potencial', array[$mig$-- 20261001212341_crm_cartera_filtro_potencial.sql
--
-- Potencial del lead · FASE 3, entrega B (servidor): filtrar y contar Leads por potencial.
-- Plan aprobado por Miguel el 01/10/2026 («ok dale con el plan B, todo lo recomendado»: el filtro va
-- solo en Leads, «Sin marcar» es una opción y se elige un nivel a la vez). Nota del vault:
-- «Potencial del lead - Frio Tibio Estrella (2026-09-30)», «Fase 3 · entrega B».
--
-- QUÉ. `crm.cartera_filtrada_fn` gana UN argumento al final, `p_potencial text default null`:
--   · null                          → no recorta;
--   · 'estrella' | 'tibio' | 'frio' → leads cuya marca VIGENTE es ese nivel;
--   · 'sin_marca'                   → leads sin marca;
--   · cualquier otro valor          → 22023, por el mismo bloque de validación que los demás filtros;
--   · con la bandera `potencial_lead` apagada, pedirlo → 55000 (igual que la puerta de marcar);
--     lo mismo para quien no tiene ámbito de filas (ni global ni analistas visibles: coordinación).
--   Y el resumen gana UNA clave, `resumen.potencial` = {filtro, estrella, tibio, frio, sin_marca}:
--   cuántos leads hay de cada nivel con los DEMÁS filtros puestos. Se cuenta ANTES de aplicar
--   `p_potencial`: los cuatro números no cambian al elegir un nivel, suman el total sin ese filtro
--   y el del nivel elegido coincide con `totales.vivos`. `filtro` es el eco del pedido. La clave
--   solo viaja con la bandera encendida y para quien tiene ámbito de filas.
--
-- CÓMO LEE LA MARCA. La función es INVOKER y las tablas del potencial no tienen grants de API
--   (fase 1, auditor-rls r1): nace `private.cartera_potencial_fn()`, un ayudante con el molde de
--   `private.cartera_recepciones_fn` (el otro ayudante de esta misma función). Devuelve
--   (lead_id, nivel) de las marcas vigentes de los leads que el actor PUEDE VER.
-- SECURITY DEFINER, justificación: una función INVOKER no puede leer `crm.lead_potencial` (sin
--   grants para nadie de la API, y así se queda). El ayudante verifica de forma explícita la sesión,
--   el gate del CRM (`private.puede_acceder_crm`, invocado) y el ÁMBITO, que es el ESPEJO EXACTO de
--   la policy `leads_select` (el mismo de `private.potencial_lectura`, fase 3A): ve la marca solo
--   quien ve el lead, en cualquier contexto. El preflight fija por md5 esa policy, el gate
--   restrictivo de `crm.leads` y los ayudantes en que se apoyan: si alguno cambió desde el ensayo,
--   la migración se niega. `search_path` vacío, dueño postgres, EXECUTE solo `authenticated`; el
--   esquema `private` no está expuesto en la API.
--   Consecuencia buscada (Codex f3b r1 y auditor-rls f3b, P2-1): `crm.resumen_cartera_fn`
--   (DEFINER) llama a la cartera SIN RLS y su base incluye, para quien opera el reparto
--   (coordinación), una bandeja que su RLS no deja ver. El ayudante NO entrega esas marcas, y la
--   cartera ni siquiera emite `resumen.potencial` para quien no tiene ámbito de filas: ningún
--   conteo por nivel revela la marca de un lead que el actor no puede leer. Si un actor con ámbito
--   de filas opera además el reparto, dentro del envoltorio las marcas que no ve cuentan como
--   «sin marca». Por la API (INVOKER) no hay diferencia: la RLS ya recorta la base.
--
-- QUÉ NO CAMBIA. Con la bandera apagada la respuesta es byte a byte la de la firma de 13 (y el
--   ayudante ni se llama). Con la bandera encendida y sin el filtro, solo se AÑADE `resumen.potencial` (clave nueva dentro del
--   resumen: los frentes publicados leen el resumen con un esquema que ignora las claves de más).
--   Las filas tienen la forma de siempre (la columna de trabajo `potencial_nivel` se quita antes
--   de serializar), no hay claves nuevas arriba, y siguen igual INVOKER, `stable`, `search_path`
--   vacío, dueño y ACL. Los demás filtros y la regla de gestión (anclas de 20261001154153) no se
--   tocan: el cuerpo nuevo sale del vivo por sustituciones exactas, no se reteclea. Una sola firma:
--   se retira la de 13 (dos candidatas romperían PostgREST) y su exención analítica se MUEVE a la
--   de 14 (misma clase, tipo y fecha de declaración) y se resella. El orden de las listas no cambia.
--
-- ORDEN DE PUBLICACIÓN: servidor primero, pantalla después. El frente nuevo envía `p_potencial` y
--   sin esta migración recibiría PGRST202; los frentes publicados no lo envían y siguen igual.
--
-- REVERSA: `supabase/scripts/potencial-lead/reversa-filtro.sql`, tras retirar el frente que envía
--   `p_potencial`. Quita la firma de 14 y el ayudante, reinstala la de 13 byte a byte (md5
--   bf06666f…), devuelve la exención analítica a su firma y resella. No toca datos.
--
-- Las huellas se midieron con `search_path` vacío y sin comillas forzadas, que se fijan abajo para
-- la transacción: el texto de `pg_get_functiondef` cambia con el `search_path` de la sesión y con
-- `quote_all_identifiers`.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
set local quote_all_identifiers = off;

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  v_huellas text;
  v_policies text;
begin
  -- 1. La función viva es la auditada: una sola firma (la de 13) y su cuerpo exacto.
  --    Guardas en positivo con `is not true`: un NULL también rechaza.
  if (
    to_regprocedure(f14) is null
    and to_regprocedure(f13) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f13))) = 'bf06666fb8ef533a39a50c7d70420153'
    and to_regprocedure('private.cartera_potencial_fn()') is null
  ) is not true then
    raise exception 'PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada';
  end if;
  -- 2. Su declaración analítica está vigente (huella al día), es de inventario y la lista está
  --    sellada: esta migración la mueve y resella; no se resella a ciegas una lista alterada.
  if (
    exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = f13_larga and c.declarada and c.huella_ok)
    and (select e.clase from private.analitica_leads_citas_exenciones e
          where e.objeto = f13_larga) = 'operativo'
    and (select s.sello from private.analitica_lc_sello s where s.id)
          = private.huella_exenciones_analitica_lc()
  ) is not true then
    raise exception 'PREFLIGHT: la declaracion analitica no esta vigente y sellada';
  end if;
  -- 3. La función sigue leyendo `crm.actividades` como INVOKER (reasignados, gestión, contacto).
  perform private.assert_actividades_de_lead_base();
  -- 4. El potencial está instalado como se ensayó: la tabla de la marca vigente con sus columnas,
  --    una fila por lead, RLS encendida, SIN grants para la API (por eso hace falta el ayudante),
  --    y su bandera.
  if (
    (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum)
       from pg_attribute a
      where a.attrelid = to_regclass('crm.lead_potencial') and a.attnum > 0 and not a.attisdropped)
      = 'id:uuid,lead_id:uuid,nivel:crm.nivel_potencial,origen:text,marcado_por:uuid,marcado_en:timestamp with time zone,creado_en:timestamp with time zone,actualizado_en:timestamp with time zone'
    and (select c.relrowsecurity from pg_class c where c.oid = to_regclass('crm.lead_potencial'))
    -- La premisa de la cartera INVOKER: la RLS de crm.leads está encendida.
    and (select c.relrowsecurity from pg_class c where c.oid = 'crm.leads'::regclass)
    -- Una fila por lead: la cartera une las marcas por `lead_id` y un duplicado repetiría el lead.
    and exists (select 1 from pg_index i
                 where i.indrelid = to_regclass('crm.lead_potencial') and i.indisunique and i.indisvalid
                   and i.indpred is null and i.indnkeyatts = 1
                   and i.indkey[0] = (select a.attnum from pg_attribute a
                                       where a.attrelid = i.indrelid and a.attname = 'lead_id'))
    and not has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_table_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and (select count(*) from crm.multiempresa_flags f where f.nombre = 'potencial_lead') = 1
    and (select array_agg(e.enumlabel::text order by e.enumsortorder)
           from pg_enum e where e.enumtypid = to_regtype('crm.nivel_potencial'))
        = array['frio', 'tibio', 'estrella']
  ) is not true then
    raise exception 'PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo';
  end if;
  -- 5. El ámbito del ayudante descansa en estos ayudantes, los mismos de `leads_select`:
  --    identidad por cuerpo + DEFINER + volatilidad + configuración + dueño.
  select string_agg(
           p.oid::regprocedure::text || '=' ||
           md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
               || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text),
           ' ' order by p.oid::regprocedure::text)
    into v_huellas
  from pg_proc p
  where p.oid in (to_regprocedure('private.rol_crm(uuid)'),
                  to_regprocedure('private.vendedor_ids_visibles(uuid)'),
                  to_regprocedure('private.es_lector_global()'),
                  to_regprocedure('private.puede_acceder_crm()'),
                  to_regprocedure('crm.bandera_activa(text)'));
  if v_huellas is distinct from
       'crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc'
    || ' private.es_lector_global()=5b8ac0c37dcbf5b82057d7b98c65c303'
    || ' private.puede_acceder_crm()=4e2c1caf7ead51be450d5018be4c6092'
    || ' private.rol_crm(uuid)=16960a2a21cc5c372431c2dd67acafe4'
    || ' private.vendedor_ids_visibles(uuid)=45ae492c03234b80336c0b8f5c8ac09b' then
    raise exception 'PREFLIGHT: un ayudante de visibilidad no es el ensayado: %', coalesce(v_huellas, '(ninguno)');
  end if;
  -- Las policies que deciden qué leads se LEEN: exactamente la permisiva `leads_select` (la que el
  -- ayudante copia) y el gate restrictivo `crm_actor_activo_gate` (el que invoca). Una policy de
  -- lectura nueva o un cambio en estas dos dejaría al ayudante viendo de más o de menos.
  select string_agg(
           pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
           || pol.polroles::regrole[]::text || '|' || md5(pg_get_expr(pol.polqual, pol.polrelid)),
           ' ## ' order by pol.polname)
    into v_policies
  from pg_policy pol
  where pol.polrelid = 'crm.leads'::regclass and pol.polcmd in ('r', '*');
  if v_policies is distinct from
       'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
    || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e' then
    raise exception 'PREFLIGHT: las policies de lectura de crm.leads no son las ensayadas: %', coalesce(v_policies, '(ninguna)');
  end if;
  -- 6. La función INVOKER debe poder llamar a la bandera, y la API no.
  if (
    has_function_privilege('authenticated', 'crm.bandera_activa(text)', 'EXECUTE')
    and not has_function_privilege('anon', 'crm.bandera_activa(text)', 'EXECUTE')
    and has_schema_privilege('authenticated', 'private', 'USAGE')
  ) is not true then
    raise exception 'PREFLIGHT: los permisos de crm.bandera_activa o del esquema private no son los ensayados';
  end if;
  -- 7. Quién llama a la cartera en el servidor: solo el envoltorio `crm.resumen_cartera_fn`, con el
  --    cuerpo ensayado (no pasa filtros del llamante). Otro consumidor, o un envoltorio distinto,
  --    recibiría `resumen.potencial` sin haberse revisado.
  if (
    (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
       from pg_proc p where p.prosrc ~* 'cartera_filtrada_fn') = 'crm.resumen_cartera_fn()'
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = '4a896597486e8b23788a2b2497f16309'
  ) is not true then
    raise exception 'PREFLIGHT: los consumidores de servidor de la cartera no son los ensayados';
  end if;
end;
$preflight$;

-- Foto de lo que NO debe cambiar: contrato de seguridad de la función, censo analítico,
-- declaraciones ajenas, la propia declaración (clase, tipo y fecha) y el consumidor.
create temporary table cartera_potencial_preflight on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

-- ── 1 · Ayudante: la marca vigente de los leads del ámbito ─────────────────────
create function private.cartera_potencial_fn()
returns table(lead_id uuid, nivel text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
begin
  -- El gate RESTRICTIVO de crm.leads (crm_actor_activo_gate) se INVOCA en vez de copiarse.
  if v_uid is null or private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Con la bandera apagada no se lee nada (igual que crm.potencial_leads_fn).
  if crm.bandera_activa('potencial_lead') is not true then
    return;
  end if;
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  -- Se resuelve UNA vez (la policy lo evalúa como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  return query
    select p.lead_id, p.nivel::text
    from crm.lead_potencial p
    join crm.leads l on l.id = p.lead_id
    -- ── ESPEJO EXACTO de la policy leads_select (fijada por md5 en el preflight) ──
    --   activo = true and ( vendedor_id in (vendedor_ids_visibles(uid))
    --                       or (vendedor_id is null and asignado_supervisor_id in (...))
    --                       or rol_crm(uid) = 'gerencia' or es_lector_global() )
    where l.activo = true
      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      );
end;
$$;
alter function private.cartera_potencial_fn() owner to postgres;
revoke all on function private.cartera_potencial_fn() from public, anon, authenticated, service_role;
grant execute on function private.cartera_potencial_fn() to authenticated;
comment on function private.cartera_potencial_fn() is
  'Ayudante de crm.cartera_filtrada_fn: (lead_id, nivel) de la marca de potencial vigente de los leads que el actor puede ver (espejo exacto de la policy leads_select: activos, de sus analistas visibles, parqueados en un supervisor visible, o todo para gerencia y lector global). SECURITY DEFINER porque crm.lead_potencial no tiene grants de API; exige sesion y el gate del CRM (42501). Con la bandera potencial_lead apagada no devuelve filas. No entrega la bandeja del reparto que la RLS no deja ver: dentro de crm.resumen_cartera_fn esas marcas cuentan como sin marca. No esta expuesto en la API (esquema private).';

-- ── 2 · La cartera: una sola firma, la de 14 ───────────────────────────────────
drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text);

create function crm.cartera_filtrada_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null,
  p_desde date default null,
  p_hasta date default null,
  p_origen text default null,
  p_procedencia text default null,
  p_reasignados boolean default false,
  p_gestion text default null,
  p_potencial text default null
)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
  v_potencial boolean;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     -- Mismo dominio que el CHECK de crm.leads.origen: los 5 vigentes y los 3
     -- históricos (web, campania, whatsapp) siguen siendo consultables.
     or (p_origen is not null and p_origen not in
       ('referido','landing','formulario','oficina','otro','web','campania','whatsapp'))
     -- Procedencia: 'sistema' (puente automático) o 'manual' (una persona).
     -- Otro valor se rechaza: nunca un «cero resultados» silencioso.
     or (p_procedencia is not null and p_procedencia not in ('sistema','manual'))
     -- Gestión: 'con_gestion' (el titular actual ya intentó el contacto) o
     -- 'sin_gestion' (el resto). Otro valor se rechaza, igual que arriba.
     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))
     -- Potencial: uno de los tres niveles o 'sin_marca' (leads sin marca). Otro valor se
     -- rechaza, igual que arriba.
     or (p_potencial is not null and p_potencial not in ('estrella','tibio','frio','sin_marca'))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();
  -- El potencial solo existe con su bandera encendida y para quien tiene ámbito de FILAS (global
  -- o con analistas visibles). Sin eso la respuesta es la de siempre (sin `resumen.potencial`) y
  -- pedir el filtro se rechaza como en la puerta de marcar. Quien solo opera el reparto no lee
  -- leads por su RLS: tampoco recibe conteos por nivel (ni dentro de crm.resumen_cartera_fn).
  v_potencial := crm.bandera_activa('potencial_lead') is true
    and (coalesce(v_global, false) or cardinality(v_visibles) > 0);
  if p_potencial is not null and not v_potencial then
    raise exception 'El potencial del lead no está habilitado' using errcode = '55000';
  end if;

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), marcas as materialized (
    -- Marca vigente de los leads que el actor puede ver. Ayudante DEFINER: las tablas del
    -- potencial no tienen grants de API. Sin potencial para este actor, ni se le llama.
    select m.lead_id, m.nivel from private.cartera_potencial_fn() m where v_potencial
  ), previa as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada,
      mk.nivel as potencial_nivel
    from crm.leads l
    -- Una primera entrega desde la cola tiene vendedor_anterior NULL. Solo
    -- cuenta un analista ANTERIOR, incluso si volvió al mismo titular tras
    -- pasar por la bandeja. El evento lo emite el trigger del servidor.
    left join lateral (
      select true as reasignado
      from crm.actividades a
      where l.vendedor_id is not null
        and a.lead_id = l.id
        and a.tipo = 'reasignacion'
        and a.metadata ->> 'vendedor_anterior' is not null
      limit 1
    ) mov on true
    left join recepciones r on r.lead_id = l.id
    left join marcas mk on mk.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      -- El origen acota la MISMA base: filas, totales, capital y embudo juntos.
      and (p_origen is null or l.origen = p_origen)
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      -- Gestión vigente: el titular ACTUAL ya intentó el contacto desde que
      -- recibió el lead (`tenencia_desde`, que se renueva al reasignar y al
      -- reabrir). Lo que gestionó un titular anterior no cuenta, ni un resultado
      -- de llamada deshecho (`deshecho_en`: no ocurrió); sin titular o sin
      -- tenencia no hay gestión. Acota la MISMA base; el payload no cambia.
      and (p_gestion is null or (l.vendedor_id is not null
        and l.tenencia_desde is not null
        and exists (select 1 from crm.actividades g
          where g.lead_id = l.id
            and g.tipo in ('llamada_realizada','llamada_no_contestada',
              'whatsapp_enviado','whatsapp_recibido','reunion_realizada')
            and g.creado_en >= l.tenencia_desde
            and not (g.metadata ? 'deshecho_en'))) = (p_gestion = 'con_gestion'))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), base as not materialized (
    -- El potencial recorta DESPUÉS de los demás filtros: `previa` alimenta los conteos por
    -- nivel (cuántos hay de cada uno con los demás filtros puestos, sin que cambien al elegir
    -- uno) y `base`, como siempre, las filas, los totales, el capital y el embudo.
    select pv.* from previa pv
    where p_potencial is null
      or (p_potencial = 'sin_marca' and pv.potencial_nivel is null)
      or pv.potencial_nivel = p_potencial
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where reasignado) as reasignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,'procedencia',p_procedencia,
    'reasignados',coalesce(p_reasignados,false),
    -- La columna de trabajo `potencial_nivel` no viaja: las filas tienen la forma de siempre.
    'items',coalesce((select jsonb_agg(to_jsonb(f) - 'potencial_nivel' order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord)))
      -- Conteos por nivel sobre `previa` (antes de `p_potencial`) y el eco del filtro. Solo con
      -- el potencial vigente para el actor: si no, el resumen es byte a byte el de antes.
      || case when v_potencial then jsonb_build_object('potencial',(select jsonb_build_object(
          'filtro',p_potencial,
          'estrella',count(*) filter(where pv.potencial_nivel='estrella'),
          'tibio',count(*) filter(where pv.potencial_nivel='tibio'),
          'frio',count(*) filter(where pv.potencial_nivel='frio'),
          'sin_marca',count(*) filter(where pv.potencial_nivel is null)) from previa pv))
        else '{}'::jsonb end)
  into v_salida;
  return v_salida;
end;
$$;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) is
  'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista), gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto) y potencial (p_potencial: estrella, tibio, frio o sin_marca; con la bandera potencial_lead apagada se rechaza con 55000). Listado y resumen salen de la misma base; resumen.potencial cuenta cada nivel con los demas filtros puestos, antes de aplicar p_potencial; solo viaja con la bandera encendida y para quien tiene ambito de filas (global o con analistas visibles), y cuenta solo las marcas que el actor puede ver por la RLS de crm.leads (una marca que no puede ver cuenta como sin_marca).';

-- La declaración analítica se MUEVE a la firma nueva (misma fila: conserva clase, tipo y
-- fecha), con la huella del cuerpo nuevo, y la lista se resella.
update private.analitica_leads_citas_exenciones e set
  objeto = p.oid::regprocedure::text,
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia, reasignacion entre analistas, gestion del titular actual y potencial del lead. No calcula conversion mensual.'
from pg_proc p
where p.oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'::regprocedure
  and e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  f14_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  ayudante constant text := 'private.cartera_potencial_fn()';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_potencial_preflight;
  -- 1. Una sola firma, la de 14, con el cuerpo ENSAYADO (md5 medido en el banco con
  --    search_path vacío) y el mismo contrato de seguridad que la que sustituye.
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f14) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f14))) = '23a63cc3965472b9db85aa81cadffbeb'
    and not has_function_privilege('anon', f14, 'EXECUTE')
    and not has_function_privilege('service_role', f14, 'EXECUTE')
    and has_function_privilege('authenticated', f14, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f14)) p) = pre.contrato
  ) is not true then
    raise exception 'POSTFLIGHT: firma, cuerpo, permisos o contrato invalido';
  end if;
  -- 2. El ayudante: el cuerpo ENSAYADO (md5 medido en el banco: gate, bandera y espejo de la
  --    policy; Codex f3b r1), DEFINER, STABLE, dueño postgres, configuración EXACTA (solo
  --    search_path vacío), ACL explícita (postgres y authenticated; authenticated solo EXECUTE y
  --    sin opción de concederlo), permisos EFECTIVOS (authenticated sí; anon y service_role no) y
  --    sin conteos.
  if (
    md5(pg_get_functiondef(to_regprocedure(ayudante))) = '73e993d618b203cdbe21e8127f7ea5b4'
    and exists (select 1 from pg_proc p
             where p.oid = to_regprocedure(ayudante) and p.prosecdef
               and p.proowner = 'postgres'::regrole and p.provolatile = 's'
               and p.proconfig = array['search_path=""']::text[] and p.proacl is not null
               and p.prosrc !~* '(count|sum)\s*\(')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                     where p.oid = to_regprocedure(ayudante)
                       and (a.grantee not in ('postgres'::regrole, 'authenticated'::regrole)
                            or (a.grantee = 'authenticated'::regrole
                                and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
    and has_function_privilege('authenticated', ayudante, 'EXECUTE')
    and not has_function_privilege('anon', ayudante, 'EXECUTE')
    and not has_function_privilege('service_role', ayudante, 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated';
  end if;
  -- 3. La tabla de la marca sigue sin grants para la API: esta migración no abre ninguno.
  if (
    not has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_table_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT')
  ) is not true then
    raise exception 'POSTFLIGHT: crm.lead_potencial quedo con algun grant de lectura para la API';
  end if;
  -- 4. El sello quedó vigente, la firma nueva está declarada con su huella y nada ajeno se
  --    movió: mismo censo, mismo conjunto en rojo (si lo había), mismas declaraciones ajenas,
  --    la propia conserva clase, tipo y fecha, y el consumidor `resumen_cartera_fn` intacto.
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f14_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f14_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f14_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
    and (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
           from pg_proc p where p.prosrc ~* 'cartera_filtrada_fn') = 'crm.resumen_cartera_fn()'
  ) is not true then
    raise exception 'POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  perform private.assert_actividades_de_lead_base();
  -- 5. La policy que el ayudante copia sigue siendo la del preflight al terminar.
  if (
    (select string_agg(pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
              || pol.polroles::regrole[]::text || '|' || md5(pg_get_expr(pol.polqual, pol.polrelid)),
              ' ## ' order by pol.polname)
       from pg_policy pol
      where pol.polrelid = 'crm.leads'::regclass and pol.polcmd in ('r', '*'))
    = 'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
      || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e'
  ) is not true then
    raise exception 'POSTFLIGHT: las policies de lectura de crm.leads cambiaron durante la instalacion';
  end if;
  -- 6. Sin sesión, el ayudante y la función se niegan (aquí no hay sesión de usuario).
  --    Y por SU guarda («No autorizado»), no por cualquier otro 42501.
  begin
    perform 1 from private.cartera_potencial_fn();
    raise exception 'POSTFLIGHT: el ayudante acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then
    if sqlerrm is distinct from 'No autorizado' then
      raise exception 'POSTFLIGHT: el ayudante rechazo por otro motivo: %', sqlerrm using errcode = 'P0001';
    end if;
  end;
  begin
    perform crm.cartera_filtrada_fn(p_limite => 1, p_potencial => 'estrella');
    raise exception 'POSTFLIGHT: la cartera acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then
    if sqlerrm is distinct from 'No autorizado' then
      raise exception 'POSTFLIGHT: la cartera rechazo por otro motivo: %', sqlerrm using errcode = 'P0001';
    end if;
  end;
  raise notice 'cartera_filtro_potencial OK: firma unica de 14 argumentos, ayudante DEFINER con el cuerpo ensayado y solo para authenticated, contrato de seguridad intacto, declaracion analitica movida y sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261001212341' and name = 'crm_cartera_filtro_potencial' and cardinality(statements) = 1
                   and md5(statements[1]) = '7bc7f15233bd36657ee3f79b5e28f55c') then
    raise exception 'REGISTRO: la fila 20261001212341 / crm_cartera_filtro_potencial no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261001212341 / crm_cartera_filtro_potencial (1 sentencia: el archivo entero)';
end $post$;
commit;
