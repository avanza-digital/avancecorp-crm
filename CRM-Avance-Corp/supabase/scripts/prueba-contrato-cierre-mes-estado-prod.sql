-- ---------------------------------------------------------------------------
-- Prueba de contrato contra PRODUCCIÓN: crm.cierre_mes_estado_fn
-- ---------------------------------------------------------------------------
-- Ejecuta la función REAL (solo lectura, todo en begin…rollback) impersonando
-- a un rol CRM, y compara el juego de claves del payload real con el que
-- declara `app/src/lib/cierre-de-mes.ts`. Corrida el 2026-08-15: 6/6 ok.
--
-- POR QUÉ EXISTE: el contrato es fail-closed (strictObject) — una clave que el
-- bundle no declara apaga el aviso del ciclo. Antes de mergear una migración
-- que toque esta función, correr esto contra la BRANCH; antes de publicar un
-- front, contra producción. Leer no es ejecutar.
--
-- USO:
--   npx supabase db query --linked --file supabase/scripts/prueba-contrato-cierre-mes-estado-prod.sql
--
-- Los bloques anulables (`pendiente`, `ultimo_cerrado`) solo se comparan si
-- vienen: null = ok — esa rama no está viva ese día y sus claves las cubre el
-- generador local `fixture-cierre-mes-estado.sql`.
-- Si algún *_ok sale false: enumerar con jsonb_object_keys y actualizar
-- contrato + este fichero EN EL MISMO cambio.
-- ---------------------------------------------------------------------------
begin;

-- Un perfil con rol CRM (cualquiera: el payload no varía por rol).
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', (
      select p.id from public.perfiles p
      where private.rol_crm(p.id) in ('gerencia', 'coordinador', 'supervisor', 'vendedor')
      limit 1
    ),
    'role', 'authenticated'
  )::text,
  true
);

-- 1) El payload entero, para el registro.
select jsonb_pretty(crm.cierre_mes_estado_fn()) as payload_prod;

-- 2) El veredicto: claves de cada nivel contra lo que el bundle declara.
with p as (
  select crm.cierre_mes_estado_fn() as j
),
raiz as (
  select array_agg(k order by k) as claves
  from p, jsonb_object_keys(p.j) as k
),
mec as (
  select array_agg(k order by k) as claves
  from p, jsonb_object_keys(p.j->'mes_en_curso') as k
),
pend as (
  select case when (select j->'pendiente' from p) is null
              or jsonb_typeof((select j->'pendiente' from p)) = 'null'
    then null
    else (select array_agg(k order by k) from p, jsonb_object_keys(p.j->'pendiente') as k)
  end as claves
),
ult as (
  select case when (select j->'ultimo_cerrado' from p) is null
              or jsonb_typeof((select j->'ultimo_cerrado' from p)) = 'null'
    then null
    else (select array_agg(k order by k) from p, jsonb_object_keys(p.j->'ultimo_cerrado') as k)
  end as claves
)
select
  (select claves from raiz) = array['generado_en','hoy','mes_en_curso','pendiente','ultimo_cerrado','version','zona']
    as raiz_ok,
  (select claves from mec) = array['cierra_el','mes','mes_nombre'] as mes_en_curso_ok,
  coalesce((select claves from pend) = array['cierra_el','dias_para_cierre','estado','mes','mes_nombre'],
           (select claves from pend) is null) as pendiente_ok,
  coalesce((select claves from ult) = array['automatico','cerrado_en','mes','mes_nombre'],
           (select claves from ult) is null) as ultimo_cerrado_ok,
  (select j->>'version' from p) = '1' as version_ok,
  (select j->>'zona' from p) = 'America/Lima' as zona_ok;

rollback;
