-- GESTIÓN DIARIA · Fase 1 — el REGISTRO CRUDO de actividad, por ámbito y por día.
--
-- Plan aprobado por Miguel el 19/09/2026 (docs/gestion-diaria/PLAN-POR-FASES-2026-09-19.md).
-- El supervisor tiene que poder leer HOY el texto íntegro de las llamadas de su
-- equipo (§4 Bloque 3 del planteamiento: «es donde va a encontrar el “NC LAS
-- LLAMADAS” marcado como realizada y corregir a la persona el mismo día»), y
-- gerencia «ver absolutamente todo» (§5 Nivel 4). Es SOLO LECTURA, no toca
-- ninguna puerta sellada y no depende del resultado tipificado (Fase 2): las
-- 13 645 actividades históricas se leen tal cual.
--
-- POR QUÉ NO SIRVE LO QUE HAY: `crm.actividades_del_ambito_fn()` no acepta
-- filtros, tiene ventana fija de 365 días y `limit 10000` (que PostgREST recorta
-- a 1 000), no devuelve `metadata` ni `creado_por`, y su predicado de ámbito
-- está COPIADO de la policy (ya se desincronizó una vez, `20260902050000`).
-- Y `crm.actividades_de_lead_fn` (historial por lead, 19/09) responde por UN
-- lead, no por un analista o un equipo en un día.
--
-- ── Las cuatro capas (estándar Avanza Digital) ───────────────────────────────
--   1. TABLA    `crm.actividades` — sin columnas nuevas. Se añade el índice
--               `actividades_autor_fecha_idx (creado_por, creado_en desc, id)`:
--               todas las lecturas de Gestión Diaria son «por analista y por
--               día» y ninguno de los seis índices vivos lidera por autor+fecha.
--   2. NÚCLEO   `private.registro_actividad_core(...)` — una página keyset
--               `(creado_en desc, id asc)` de actividades de una ventana Lima,
--               filtrada por autores, tipos y etapa actual del lead, con la
--               ETAPA DEL LEAD EN ESE MOMENTO derivada del último `cambio_etapa`
--               anterior (`metadata->>'etapa_nueva'`, presente en los 2 978
--               cambios de etapa vivos; nunca parseando prosa). PURO: sin
--               `auth.`, sin autoridad propia, `security invoker`.
--   3. PUERTA   `crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)`
--               — expuesta a `authenticated`. Valida el input, exige admisión
--               al CRM, exige que cada analista pedido esté en el roster
--               VISIBLE del actor (42501 explícito, nunca «vacío») y delega.
--   4. PANTALLA la vista nueva `gestion-diaria` del CRM, sección «Registro»
--               (analista: el suyo; supervisor: su equipo; gerencia: global y
--               por equipo, exportable).
--
-- POR QUÉ `SECURITY INVOKER` (misma decisión que el historial por lead del
-- 19/09): las filas llevan PII conversacional. El alcance lo pone la RLS
-- (`actividades_select` es co-extensiva con `leads_select`: quien ve el lead ve
-- sus actividades), no un predicado copiado. Las huellas de ambas policies se
-- sellan en el gate propio; el único salto privilegiado es el nombre del autor
-- (`private.nombre_de_autor`, DEFINER acotado a `crm.equipo`, ya en producción).
--
-- QUÉ SIGNIFICA «VISIBLE» PARA LA RLS: actividades sobre leads cuyo DUEÑO ACTUAL
-- está en el subárbol del actor (o parkeados a él). Una llamada de un analista
-- del equipo sobre un lead que luego se reasignó a otro equipo deja de verse en
-- este registro: es el contrato de la policy, aquí no se reescribe.
--
-- DEFINICIONES fijadas por el plan y que este registro NO reinterpreta: aquí no
-- se cuenta nada. Ninguna función de esta migración usa `count(` ni `sum(1)`
-- (vigía de contadores crudos): el «hay más» lo decide el front pidiendo
-- `limite + 1`, como el historial por lead y la cartera keyset.
--
-- COORDINADOR y DIRECTORIO: no entran al módulo. El coordinador recibe 42501
-- explícito (su ámbito de leads es ∅ por diseño C1); directorio lee bajo
-- `es_lector_global` como en toda lectura de la casa, pero la vista no se le
-- ofrece en el menú (vistas.ts).
--
-- REVERSIÓN:
--   drop function crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid);
--   drop function private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid);
--   drop function private.assert_gestion_diaria_mutantes();
--   drop function private.assert_gestion_diaria();
--   drop index crm.actividades_autor_fecha_idx;
--   create index idx_actividades_creado_por on crm.actividades (creado_por);
-- Nada de datos que deshacer: esta migración solo lee.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_huella text;
begin
  if to_regprocedure('crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)') is not null
     or to_regprocedure('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)') is not null
     or to_regprocedure('private.assert_gestion_diaria()') is not null then
    raise exception 'PREFLIGHT: el registro de Gestion Diaria ya esta instalado';
  end if;
  if exists (select 1 from pg_indexes where schemaname = 'crm' and indexname = 'actividades_autor_fecha_idx') then
    raise exception 'PREFLIGHT: el indice actividades_autor_fecha_idx ya existe';
  end if;
  -- Lo que la cadena INVOKER necesita, medido en producción el 19/09/2026.
  if to_regprocedure('private.nombre_de_autor(uuid)') is null
     or not has_function_privilege('authenticated', 'private.nombre_de_autor(uuid)', 'EXECUTE')
     or to_regprocedure('private.assert_actividades_de_lead_base()') is null then
    raise exception 'PREFLIGHT: falta el historial por lead (20260919185718): private.nombre_de_autor(uuid) o private.assert_actividades_de_lead_base()';
  end if;
  if not has_function_privilege('authenticated', 'private.puede_acceder_crm()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.equipo_visible_fn()', 'EXECUTE')
     or not has_schema_privilege('authenticated', 'private', 'USAGE')
     or not has_table_privilege('authenticated', 'crm.actividades', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'nombre_completo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'etapa', 'SELECT') then
    raise exception 'PREFLIGHT: la cadena invoker no tiene los permisos esperados';
  end if;
  -- Las dos policies co-extensivas, por huella (auditoría del 19/09/2026).
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol where pol.polrelid = 'crm.actividades'::regclass and pol.polname = 'actividades_select';
  if v_huella is distinct from 'e80e3af900b8d9616c28dcd836f1ac94' then
    raise exception 'PREFLIGHT: actividades_select cambio desde la auditoria (md5 %)', coalesce(v_huella, 'ausente');
  end if;
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol where pol.polrelid = 'crm.leads'::regclass and pol.polname = 'leads_select';
  if v_huella is distinct from '073deaeb5700bac14209ec795b71567e' then
    raise exception 'PREFLIGHT: leads_select cambio desde la auditoria (md5 %)', coalesce(v_huella, 'ausente');
  end if;
end;
$preflight$;

-- ── CAPA 1 · el índice ───────────────────────────────────────────────────────
-- (creado_por, creado_en desc, id): «este analista, este día», en el orden del
-- cursor. Sin predicado parcial: el registro lista los NUEVE tipos. La tabla
-- tiene ~13,6 k filas (19/09): se construye dentro de la transacción.
create index actividades_autor_fecha_idx
  on crm.actividades (creado_por, creado_en desc, id);
comment on index crm.actividades_autor_fecha_idx is
  'Gestión Diaria: lecturas por analista y por día (registro crudo, marcador, equipo). Orden = el del cursor keyset (creado_en desc, id).';
-- `idx_actividades_creado_por (creado_por)` (20260711000003) es prefijo exacto del
-- nuevo: se retira para no pagar dos índices por cada gestión escrita. La
-- reversa lo recrea. La vista por defecto de supervisor/gerencia (todos los
-- analistas) sigue usando `actividades_recientes_idx (creado_en desc, id)`.
drop index if exists crm.idx_actividades_creado_por;

-- ── CAPA 2 · NÚCLEO ─────────────────────────────────────────────────────────
create function private.registro_actividad_core(
  p_ini timestamptz,
  p_fin timestamptz,
  p_analista_ids uuid[],
  p_tipos text[],
  p_etapa text,
  p_limite integer,
  p_antes_de timestamptz,
  p_antes_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with pagina as (
    select a.id, a.lead_id, a.tipo, a.detalle, a.metadata, a.creado_por, a.creado_en,
           l.nombre_completo as lead_nombre, l.etapa as lead_etapa,
           -- La etapa del lead ANTES de esta actividad: el último cambio de etapa
           -- anterior. OJO con el reloj de los escritores (refutación del 19/09):
           -- las gestiones manuales llevan `clock_timestamp()` (sello de
           -- 20260820174320) pero los `cambio_etapa` automáticos nacen con el
           -- `now()` de la transacción, es decir unos milisegundos ANTES de la
           -- llamada que los causó. Por eso el cambio se considera «ya ocurrido»
           -- solo si es anterior en más de un segundo: así la llamada que subió
           -- el lead a «contactado» se ve todavía en «nuevo», y la conversión
           -- (misma transacción que su cambio) se ve en la etapa previa.
           (select c.metadata->>'etapa_nueva'
              from crm.actividades c
             where c.lead_id = a.lead_id
               and c.tipo = 'cambio_etapa'
               and c.creado_en < a.creado_en - interval '1 second'
             order by c.creado_en desc, c.id desc
             limit 1) as etapa_en_ese_momento
    from crm.actividades a
    join crm.leads l on l.id = a.lead_id
    where a.creado_en >= p_ini
      and a.creado_en <  p_fin
      and (p_analista_ids is null or a.creado_por = any (p_analista_ids))
      and (p_tipos is null or a.tipo = any (p_tipos))
      and (p_etapa is null or l.etapa = p_etapa)
      and (
        p_antes_de is null
        or a.creado_en < p_antes_de
        or (a.creado_en = p_antes_de and a.id > p_antes_id)
      )
    order by a.creado_en desc, a.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.now(),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pg.id,
          'lead_id', pg.lead_id,
          'lead_nombre', pg.lead_nombre,
          'lead_etapa', pg.lead_etapa,
          'etapa_en_ese_momento', pg.etapa_en_ese_momento,
          'tipo', pg.tipo,
          'detalle', pg.detalle,
          -- metadata por LISTA BLANCA: solo lo que la pantalla necesita. Fuera
          -- quedan montos y referencias de conversión, uuids de reasignación y
          -- cualquier clave futura que no se haya decidido mostrar (auditor-rls, 19/09).
          'metadata', coalesce((
            select jsonb_object_agg(m.clave, m.valor)
            from jsonb_each(pg.metadata) as m(clave, valor)
            where m.clave in ('evento', 'resultado', 'submotivo', 'intento_n', 'etapa_anterior', 'etapa_nueva',
                              'automatico', 'resultado_reunion', 'modalidad', 'motivo')
          ), '{}'::jsonb),
          'creado_por', pg.creado_por,
          'autor_nombre', coalesce(private.nombre_de_autor(pg.creado_por), '—'),
          'creado_en', pg.creado_en
        )
        order by pg.creado_en desc, pg.id asc
      )
      from pagina pg
    ), '[]'::jsonb)
  );
$function$;

comment on function private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid) is
  'NÚCLEO (Gestión Diaria): página keyset (creado_en desc, id asc) de actividades de una ventana [p_ini, p_fin) bajo la RLS del actor, filtrada por autores, tipos y etapa actual del lead, con la etapa del lead en ese momento (último cambio_etapa anterior) y metadata acotada a una lista blanca de claves. Puro: sin auth ni autoridad propia; sin count(.';

revoke all on function private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid)
  from public, anon, authenticated, service_role;
-- Lo llama una puerta INVOKER, así que corre como el actor: necesita EXECUTE.
-- `private` no está expuesto a la API: PostgREST no puede invocarlo directo.
grant execute on function private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid)
  to authenticated;

-- ── CAPA 3 · PUERTA ─────────────────────────────────────────────────────────
create function crm.registro_actividad_fn(
  p_desde date,
  p_hasta date,
  p_analista_ids uuid[] default null,
  p_tipos text[] default null,
  p_etapa text default null,
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare
  v_hoy_lima constant date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_tipos_validos constant text[] := array[
    'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido',
    'reunion_realizada', 'nota', 'cambio_etapa', 'reasignacion', 'conversion'];
  v_etapas_validas constant text[] := array[
    'nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada', 'convertido', 'descartado'];
begin
  -- EL INPUT SE VALIDA ANTES DE LEER NADA (22023, mensajes en lenguaje llano).
  if p_desde is null or p_hasta is null then
    raise exception 'Indica el rango de fechas' using errcode = '22023';
  end if;
  if p_desde > p_hasta then
    raise exception 'La fecha inicial no puede ser posterior a la final' using errcode = '22023';
  end if;
  if p_hasta > v_hoy_lima then
    raise exception 'El registro no admite fechas futuras' using errcode = '22023';
  end if;
  if p_hasta - p_desde > 365 then
    raise exception 'El rango no puede superar un año' using errcode = '22023';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 500 then
    raise exception 'Parametro p_limite invalido' using errcode = '22023';
  end if;
  -- Cursor A MEDIAS = páginas que se saltan filas en silencio.
  if (p_antes_de is null) <> (p_antes_id is null) then
    raise exception 'Cursor incompleto: p_antes_de y p_antes_id viajan juntos' using errcode = '22023';
  end if;
  if p_analista_ids is not null and (
       pg_catalog.cardinality(p_analista_ids) = 0
       or exists (select 1 from pg_catalog.unnest(p_analista_ids) x where x is null)) then
    raise exception 'Parametro p_analista_ids invalido' using errcode = '22023';
  end if;
  if p_tipos is not null and (
       pg_catalog.cardinality(p_tipos) = 0
       or exists (select 1 from pg_catalog.unnest(p_tipos) t where t is null or not (t = any (v_tipos_validos)))) then
    raise exception 'Parametro p_tipos invalido' using errcode = '22023';
  end if;
  if p_etapa is not null and not (p_etapa = any (v_etapas_validas)) then
    raise exception 'Parametro p_etapa invalido' using errcode = '22023';
  end if;

  -- Guardia de ADMISIÓN (P04: revocado ≠ ajeno al CRM). El ALCANCE lo pone la RLS.
  if not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- El coordinador no entra al mundo leads (C1, 20260721120000): su ámbito es ∅
  -- por diseño y ninguna pantalla suya abre este registro. Se le dice que no,
  -- en vez de devolverle un registro vacío que parezca «nadie llamó».
  if private.rol_crm((select auth.uid())) = 'coordinador' then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Denegación EXPLÍCITA por analista: cada id pedido tiene que estar en el
  -- roster VISIBLE del actor (`crm.equipo_visible_fn`: él mismo, su subárbol o
  -- todos para el lector global). Un analista ajeno responde 42501, nunca un
  -- registro vacío que se confunda con «no llamó». CONTRATO: el filtro admite
  -- solo analistas ACTIVOS del roster visible (equipo_visible_fn excluye a los
  -- dados de baja); sus gestiones siguen saliendo SIN filtro, con nombre, por
  -- la RLS. La pantalla solo ofrece activos en el selector.
  if p_analista_ids is not null and exists (
    select 1 from pg_catalog.unnest(p_analista_ids) x
    where x not in (select ev.perfil_id from crm.equipo_visible_fn() ev)
  ) then
    raise exception 'Solo puedes filtrar por analistas activos de tu equipo' using errcode = '42501';
  end if;

  -- Ventana semiabierta en Lima: [desde 00:00, hasta+1 00:00).
  v_ini := (p_desde::timestamp) at time zone 'America/Lima';
  v_fin := ((p_hasta + 1)::timestamp) at time zone 'America/Lima';

  return private.registro_actividad_core(v_ini, v_fin, p_analista_ids, p_tipos, p_etapa, p_limite, p_antes_de, p_antes_id)
         || jsonb_build_object('desde', p_desde, 'hasta', p_hasta, 'zona', 'America/Lima', 'limite', p_limite);
end;
$function$;

comment on function crm.registro_actividad_fn(date, date, uuid[], text[], text, integer, timestamptz, uuid) is
  'PUERTA (Gestión Diaria): registro crudo de actividad de una ventana de días Lima, por analistas (null = todo lo visible), tipos y etapa actual del lead, por cursor keyset (creado_en desc, id asc). SECURITY INVOKER: el alcance lo ponen actividades_select y leads_select; 42501 explícito si un analista pedido no está en el roster visible. Sin count(: el front pide limite+1.';

revoke all on function crm.registro_actividad_fn(date, date, uuid[], text[], text, integer, timestamptz, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.registro_actividad_fn(date, date, uuid[], text[], text, integer, timestamptz, uuid)
  to authenticated;

-- ── Gate propio ──────────────────────────────────────────────────────────────
-- Trinquete de Gestión Diaria (crecerá con cada fase): puerta y núcleo INVOKER,
-- estables, search_path vacío, owner postgres; EXECUTE exactamente para
-- authenticated; el índice presente; y las dos policies de las que depende el
-- diseño selladas por huella y por conjunto (la restrictiva del actor activo
-- incluida). Sin count(.
create function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_firma text;
  v_id oid;
begin
  foreach v_firma in array array[
    'crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)',
    'private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and not p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 's'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato de Gestion Diaria alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL de Gestion Diaria alterada: %', v_firma;
    end if;
  end loop;

  if not exists (select 1 from pg_indexes where schemaname = 'crm' and tablename = 'actividades'
                 and indexname = 'actividades_autor_fecha_idx') then
    raise exception 'Falta el indice actividades_autor_fecha_idx';
  end if;

  -- El CUERPO del núcleo, sellado: la lista blanca de metadata, la ventana y el
  -- keyset viven ahí y un `create or replace` conservaría forma, ACL y
  -- search_path. Huella medida en el banco el 19/09/2026 (dos pasadas del ensayo).
  if md5(pg_get_functiondef('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'::regprocedure))
     is distinct from 'd1c922eb5081e30f3581b95a95d74656' then
    raise exception 'El cuerpo de private.registro_actividad_core cambio: re-sellar Gestion Diaria';
  end if;

  -- El único salto privilegiado sigue en su forma (DEFINER con gate interno).
  v_id := to_regprocedure('private.nombre_de_autor(uuid)');
  if v_id is null or not exists (
    select 1 from pg_proc p
    where p.oid = v_id and p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
      and strpos(p.prosrc, 'puede_acceder_crm') > 0
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'private.nombre_de_autor(uuid) perdio su forma o su EXECUTE';
  end if;

  -- Las dos policies co-extensivas (huella, conjunto de permisivas, roles de la
  -- policy, restrictiva del actor activo, grants de la cadena invoker): UNA sola
  -- fuente, la base del historial por lead (20260919185718). Dos gates con las
  -- mismas constantes copiadas podrían divergir; llamándola no pueden.
  perform private.assert_actividades_de_lead_base();

  return 'OK: registro de Gestion Diaria bajo la RLS (puerta y nucleo INVOKER), EXECUTE solo authenticated, indice presente, policies selladas por la base del historial por lead';
end;
$function$;
comment on function private.assert_gestion_diaria() is
  'Trinquete de Gestión Diaria: puerta y núcleo INVOKER con search_path vacío, EXECUTE solo para authenticated, índice actividades_autor_fecha_idx presente, nombre_de_autor en su forma, y las policies actividades_select/leads_select selladas vía private.assert_actividades_de_lead_base().';
revoke all on function private.assert_gestion_diaria()
  from public, anon, authenticated, service_role;

-- ── Mutantes del trinquete (regla de la casa: por cada defensa, un mutante) ──
-- SOLO PARA EL BANCO. Cada mutante vive en su propia subtransacción que se
-- deshace grite o no el gate. Si un mutante NO es detectado, falla con su nombre.
create function private.assert_gestion_diaria_mutantes() returns text
language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_detectados integer := 0;
  v_mutacion text;
  v_nombre text;
begin
  -- Guarda de banco: solo corre con la marca de sesión que pone el ensayo
  -- (`set gestion_diaria.banco = on`). En producción una ejecución accidental
  -- tomaría ACCESS EXCLUSIVE sobre crm.actividades y abriría la policy dentro
  -- de la subtransacción: se niega.
  if coalesce(current_setting('gestion_diaria.banco', true), '') <> 'on' then
    raise exception 'Los mutantes solo corren en el banco (set gestion_diaria.banco = on)';
  end if;
  for v_nombre, v_mutacion in select * from (values
    ('1 puerta definer',           'alter function crm.registro_actividad_fn(date, date, uuid[], text[], text, integer, timestamptz, uuid) security definer'),
    ('2 policy actividades abierta','alter policy actividades_select on crm.actividades using (true)'),
    ('3 nucleo concedido a anon',   'grant execute on function private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid) to anon'),
    ('4 sin indice',                'drop index crm.actividades_autor_fecha_idx'),
    ('5 permisiva nueva en leads',  'create policy leads_mutante_gestion_diaria on crm.leads for select to authenticated using (true)'),
    ('6 leads_select para public',  'alter policy leads_select on crm.leads to public'),
    ('7 puerta sin EXECUTE',        'revoke execute on function crm.registro_actividad_fn(date, date, uuid[], text[], text, integer, timestamptz, uuid) from authenticated'),
    ('8 puerta volatile',           'alter function crm.registro_actividad_fn(date, date, uuid[], text[], text, integer, timestamptz, uuid) volatile'),
    ('9 nucleo sin search_path',    'alter function private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid) reset search_path'),
    ('10 nucleo sin lista blanca',  $m$create or replace function private.registro_actividad_core(p_ini timestamptz, p_fin timestamptz, p_analista_ids uuid[], p_tipos text[], p_etapa text, p_limite integer, p_antes_de timestamptz, p_antes_id uuid) returns jsonb language sql stable security invoker set search_path to '' as $b$ select jsonb_build_object('version', 1, 'items', '[]'::jsonb) $b$$m$)
  ) as m(nombre, sql) loop
    begin
      -- La MUTACIÓN va aparte: si ella misma falla (objeto renombrado, permiso),
      -- no cuenta como «detectada»: se grita.
      begin
        execute v_mutacion;
      exception when others then
        raise exception 'MUTANTE % NO APLICABLE: %', v_nombre, sqlerrm;
      end;
      perform private.assert_gestion_diaria();
      raise exception 'MUTANTE % NO DETECTADO: paso el gate', v_nombre;
    exception when others then
      if sqlerrm like 'MUTANTE %' then raise; end if;
      -- La excepción viene del gate: detectado. La subtransacción deshace la mutación.
      v_detectados := v_detectados + 1;
    end;
  end loop;
  return format('OK: %s mutantes detectados por private.assert_gestion_diaria()', v_detectados);
end;
$function$;
comment on function private.assert_gestion_diaria_mutantes() is
  'Mutantes del trinquete de Gestión Diaria (solo banco, exige set gestion_diaria.banco = on): cada mutación vive en una subtransacción que se deshace; falla si el gate no la detecta o si la mutación no aplica.';
revoke all on function private.assert_gestion_diaria_mutantes()
  from public, anon, authenticated, service_role;

do $postflight$
begin
  perform private.assert_gestion_diaria();
  -- Los gates del mundo SLA, que también lee crm.actividades. Los otros
  -- cuatro controles del servidor (auditoría, analítica de leads/citas,
  -- vigencia de analistas y piezas F7) están en ROJO en producción desde
  -- antes y por trabajos ajenos: llamarlos aquí abortaría una migración que
  -- no los empeora ni los arregla. Esta migración no añade contadores crudos
  -- (sin count( ni sum(1)).
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
