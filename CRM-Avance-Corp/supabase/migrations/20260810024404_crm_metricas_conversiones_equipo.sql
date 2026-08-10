-- DECISIÓN DE ÁMBITO — CERRADA por Miguel (2026-08-09)
--
--   «El ranking del supervisor cuenta a su gente de HOY, con toda su historia».
--
-- Es decir: atribución por DUEÑO ACTUAL (`crm.leads.vendedor_id` vigente), que es
-- lo que ya hace el resto de F1 y lo que esta función implementa. Consecuencia
-- aceptada y consciente: si gerencia traspasa un vendedor, su nuevo supervisor
-- recibe el año entero de esa persona —incluido lo que produjo bajo otro— y el
-- ranking se reordena solo cuando alguien cambia de equipo. La alternativa
-- descartada era atribuir por el ledger `crm.lead_asignaciones`.
--
-- =========================================================================

-- ============================================================================
-- crm.metricas_conversiones_equipo_fn — ranking de conversion del EQUIPO
-- Decision #10 (Miguel, 2026-08-09): el SUPERVISOR ve el ranking de SU equipo,
-- incluida la pestana «Conversion general».
-- ============================================================================
--
-- POR QUE EXISTE ESTA FUNCION Y POR QUE NO REUTILIZA LA GLOBAL
-- -----------------------------------------------------------
-- `crm.metricas_conversiones_fn(date,date)` (wrapper en 20260807203757:1836,
-- cuerpo en `private.metricas_conversiones_implementacion`, versionado en
-- 20260805200000) esta cerrada a gerencia|lector global. Relajar ese gate NO
-- es una opcion, por dos razones verificadas leyendo el SQL:
--
--   1. FUGA. De las 9 claves de su payload, CINCO son agregados de TODA la
--      empresa: `cohorte`, `produccion`, `embudo`, `origenes` y `categorias`.
--      Se calculan sobre `cohorte_base`, que filtra unicamente por ventana de
--      fechas y no tiene NINGUN predicado de ambito; `produccion` es aun peor,
--      porque son cuatro subconsultas independientes contra `crm.leads` y
--      `public.contratos` que ni siquiera pasan por la cohorte y devuelven el
--      capital PEN/USD de la empresa entera. Un agregado global NO se puede
--      desagregar a posteriori: `private.filtrar_desglose_sujetos_crm` solo
--      reescribe la clave `responsables` y, ademas, filtra por ROL EFECTIVO
--      (`private.rol_crm(id) = any(roles)`), no por visibilidad — dejaria pasar
--      el desglose de TODOS los vendedores activos de la empresa. Hay que
--      RECALCULAR con scope, no recortar despues.
--   2. NI SIQUIERA FUNCIONARIA. La implementacion conserva su propio gate de
--      gerencia|lector dentro del cuerpo (20260805200000:19-26, y lo evalua
--      leyendo `crm.equipo` en crudo, fuera del canon de rol efectivo). Un
--      supervisor recibiria 42501 desde dentro aunque el wrapper lo dejara
--      pasar.
--
-- La regla estructural de la casa es la que ya demuestran `metricas_agenda_fn`
-- (gate abierto a supervisor porque su unica clave de datos, `vendedores`, sale
-- de una CTE `visibles` scopeada) y `crm.metricas_vendedores_fn` (as-built
-- 20260809144920:509-697, tres capas scopeadas y CERO agregados empresa-wide):
--
--     gate relajado a supervisor  <=>  payload SIN ningun agregado global.
--
-- Por eso esta funcion NACE con la superficie minima del ranking y con el
-- ambito dentro de las CTE. No toca `crm.metricas_conversiones_fn`: gerencia y
-- directorio siguen recibiendo su payload actual byte a byte (cero regresion).
--
-- QUE DEVUELVE (y que NO)
-- -----------------------
-- Devuelve exactamente {version, generado_en, alcance, periodo, responsables[]}
-- y cada responsable trae {vendedor_id, leads, clientes, conversion_pct}: los
-- tres unicos campos que pinta `app/src/screens/hoy/ranking-vendedores.tsx`
-- (lineas 113, 131, 138-139, 153, 162), mas el id con el que el front une el
-- nombre desde su roster.
-- Quedan DELIBERADAMENTE FUERA, por ser superficie que no se usa y si habria
-- que auditar: `cohorte`, `produccion`, `embudo`, `origenes`, `categorias`
-- (globales por construccion), `capital_pen`/`capital_usd` (el dato mas
-- sensible del desglose; el tab «Capital total» los toma de metas/cumplimientos,
-- no de aqui), `tendencia_semanal` (solo la consumen inteligencia-comercial.tsx
-- y resumen-gerencia.tsx, ambas de gerencia) y `contactados`/
-- `reuniones_realizadas` (hoy no se pintan). Al no necesitar esas dos ultimas
-- señales, la funcion NO lee `crm.actividades` ni `crm.tareas`: su superficie de
-- datos es `crm.equipo` + `crm.leads`, y de `crm.leads` solo lee id, vendedor_id,
-- contrato_id y creado_en.
--
-- SIN PII. La salida son UUIDs, enteros y un numeric de porcentaje. Ningun
-- nombre, telefono, correo, DNI, distrito, genero ni fecha de nacimiento entra
-- siquiera en las CTE (a diferencia de la global, cuyo `cohorte_base` hace
-- `select l.*`). Los nombres los pone el front uniendo por id con
-- `crm.equipo_visible_fn`.
--
-- PARIDAD CON GERENCIA (invariante que el gate debe custodiar)
-- ------------------------------------------------------------
-- Para el mismo vendedor y el mismo periodo, esta funcion devuelve los MISMOS
-- `leads`, `clientes` y `conversion_pct` que la clave `responsables` de
-- `crm.metricas_conversiones_fn`. Se replican al pie de la letra:
--   · el roster: `rol_crm='vendedor' and crm.equipo.activo and perfiles.activo`;
--   · la cohorte por FECHA DE ALTA, ventana semiabierta [v_ini, v_fin) en Lima;
--   · la convencion de nombres AS-BUILT, que es enganosa y se CONSERVA a
--     proposito: la clave JSON `clientes` NO son los leads convertidos a
--     cliente — son los leads de la cohorte CON CONTRATO
--     (`contrato_id is not null`), y `conversion_pct = 100*contratos/leads`
--     (20260805200000:216-217). Cambiarla aqui haria que el mismo vendedor
--     tuviera dos porcentajes distintos segun quien mire;
--   · `crm.leads.activo` NO se filtra. Es divergencia as-built de la global
--     respecto de las RPC de F1, y se conserva por la misma razon de paridad.
--     Riesgo acotado: el descarte NO desactiva el lead (20260723120000:20), asi
--     que la poblacion afectada es residual, siempre del propio subarbol, y
--     llega solo como CONTEO agregado.
--
-- AMBITO: DUENO ACTUAL, subarbol RECURSIVO
-- ----------------------------------------
-- El scope sale de `private.vendedor_ids_visibles(auth.uid())` (as-built
-- 20260803164348:38-77): recursivo a N niveles, incluye al propio supervisor y
-- conserva miembros INACTIVOS como objetos historicos. La atribucion es por
-- DUENO ACTUAL (`crm.leads.vendedor_id` vigente), igual que todo F1, no por el
-- ledger `crm.lead_asignaciones`.
-- NO lleva la rama de parkeados (`vendedor_id is null and
-- asignado_supervisor_id = any(...)`) del predicado canonico: aqui seria CODIGO
-- MUERTO — el unico agregado del payload se construye por LEFT JOIN sobre
-- `vendedor_id`, asi que un lead sin dueno no puede sumar en ninguna fila. Es
-- el mismo hallazgo del auditor sobre `metricas_vendedores_fn` (20260809144920,
-- nota b). Los numeros de parkeados viven en `resumen_cartera_fn` y
-- `resumen_reparto_fn`. Por lo mismo tampoco hay rama de coordinador.
--
-- CONTRATO DE DENEGACION (fijado ANTES de codificar los tests):
--   supervisor  -> payload scopeado a su subarbol
--   gerencia    -> payload global
--   lector global (Directorio CRM activo / Directorio Portal sin membresia)
--               -> payload global
--   vendedor / coordinador / membresia inactiva / ajeno al CRM / anon
--               -> 42501 DURO. Nunca payload de ceros: un cero es un numero y
--                  se leeria como «0 % de conversion».
--   periodo invalido -> 22023, pero SOLO despues de pasar el gate.
-- «Subarbol ajeno» no es un 42501 sino una AUSENCIA: la RPC no tiene parametro
-- de sujeto, el ambito se deriva exclusivamente de auth.uid(). Si algun dia se
-- anade p_vendedor_id/p_supervisor_id, ese renglon deja de ser estructural y
-- necesita su propia rama 42501.
--
-- No altera ningun objeto de `public`: solo LEE `public.perfiles` (id, activo),
-- exactamente como ya lo hace la implementacion global. No abre excepcion en el
-- «Registro de excepciones a public» del ledger.
-- ============================================================================

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight: dependencias del ambito y del filtro de sujetos
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.es_lector_global()') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])') is null
     or to_regclass('crm.equipo') is null
     or to_regclass('crm.leads') is null
     or to_regclass('public.perfiles') is null then
    raise exception 'Falta una dependencia del ambito CRM o del filtro de sujetos';
  end if;

  -- La paridad con gerencia se apoya en que la implementacion global siga
  -- existiendo con esta firma: si desaparece, el caso de anti-regresion del
  -- gate deja de ser comparable y hay que revisarlo antes de aplicar.
  if to_regprocedure('crm.metricas_conversiones_fn(date,date)') is null then
    raise exception 'crm.metricas_conversiones_fn(date,date) no existe: revisar la paridad antes de aplicar';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Indice de apoyo: (vendedor_id, creado_en)
-- ---------------------------------------------------------------------------
-- El predicado caliente de esta RPC es «dueno + ventana de alta»:
--   vendedor_id = any(v_visibles) AND creado_en >= v_ini AND creado_en < v_fin
-- Ninguno de los indices existentes lo sirve bien:
--   · idx_leads_vendedor (20260709000001:195) es PARCIAL `where activo = true`,
--     y esta funcion NO filtra `activo` (paridad con gerencia, ver cabecera):
--     el planner no puede deducir el predicado del indice y lo descarta.
--   · leads_vendedor_orden_idx (20260808155128:55) es (vendedor_id,
--     actualizado_en desc): su segunda columna no acota una ventana sobre
--     `creado_en`, obliga a leer todas las filas del vendedor.
--   · idx_leads_creado_en (20260809144930) sirve la rama GLOBAL (gerencia y
--     lector), pero en la rama scopeada obliga a BitmapAnd + recheck.
-- Parcial `where vendedor_id is not null`: ese predicado SI es deducible
-- (`vendedor_id = any(array)` implica no nulo), asi que el parcial no deja la
-- consulta sin indice y ademas excluye los parkeados, que esta RPC nunca mira.
--
-- Sin CONCURRENTLY a proposito, mismo criterio que 20260809144930: el ciclo
-- aplica en branch y el merge lo reproduce en prod con la tabla aun pequena.

create index if not exists idx_leads_vendedor_creado_en
  on crm.leads (vendedor_id, creado_en)
  where vendedor_id is not null;

comment on index crm.idx_leads_vendedor_creado_en is
  'Dueno + ventana de alta: sirve el ambito scopeado de metricas_conversiones_equipo_fn. Parcial por vendedor_id not null (deducible del = any(array)); NO parcial por activo, porque esa RPC no filtra activo para conservar paridad con gerencia.';

-- ---------------------------------------------------------------------------
-- 2. La RPC
-- ---------------------------------------------------------------------------

create or replace function crm.metricas_conversiones_equipo_fn(
  p_desde date,
  p_hasta date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
begin
  -- 1) GATE EXPLICITO, ANTES DE TOCAR NINGUN DATO. Nunca RLS implicita: esta
  --    funcion es SECURITY DEFINER y las policies de crm.leads no se evaluan.
  --    Orden deliberado: un actor denegado recibe 42501 aunque el periodo sea
  --    basura, para que el codigo de error no funcione como oraculo.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- 2) Validacion de parametros (identica a la global, para que el front no
  --    tenga que distinguir dos contratos de periodo).
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;

  -- 3) Ambito. Capturado UNA vez en array para que `= any(...)` sea indexable
  --    (el `in (select private.vendedor_ids_visibles(...))` se ejecuta como
  --    SubPlan por fila y nunca usa indice — razon documentada en
  --    20260809144920:8-16).
  --    Para gerencia y para el lector global el ambito es la empresa entera:
  --    v_global corta el predicado sin depender de v_visibles (un Directorio
  --    Portal sin membresia no tiene subarbol y vendedor_ids_visibles le
  --    devuelve vacio).
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  -- Solo se materializa cuando de verdad recorta: para gerencia/lector,
  -- `vendedor_ids_visibles` devuelve TODA crm.equipo (20260803164348:56) y el
  -- predicado ya cortocircuita por v_global, asi que seria trabajo tirado.
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  with roster as materialized (
    -- SUJETOS scopeados: el ranking no puede nombrar a quien no este en el
    -- ambito. Mismas condiciones que `vendedores_base` de la global
    -- (20260805200000:34-39) MAS el predicado de visibilidad.
    -- Los supervisores del subarbol NO aparecen como fila aunque lleven
    -- cartera propia: es exactamente lo que ve gerencia hoy (la global filtra
    -- rol_crm='vendedor' y el wrapper vuelve a filtrar por rol efectivo).
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.rol_crm = 'vendedor'
      and e.activo is true
      and p.activo is true
      and (v_global or e.perfil_id = any(v_visibles))
  ),
  cohorte as materialized (
    -- DATOS scopeados: leads RECIBIDOS en la ventana (por fecha de alta), del
    -- dueno actual dentro del ambito. Sin rama de parkeados: seria codigo
    -- muerto (ver cabecera).
    --
    -- `activo is true` (hallazgo MAYOR del auditor-rls): el predicado canonico
    -- `leads_select` (20260709000001:412-419) lleva el filtro DENTRO de la rama
    -- de ambito, y `leads_update` (:440-459) concede el soft-delete a
    -- supervisor/gerencia. Sin este filtro, un supervisor que apaga un lead deja
    -- de verlo en crm.leads y en las CINCO RPC de F1 —todas filtran activo— y
    -- SEGUIRIA contandolo en el denominador de su propio ranking, bajandole el
    -- porcentaje al vendedor. Ademas rompe el oraculo autoconsistente del gate
    -- (test-rls.mjs:3937-3946), que compara agregados contra lo que la sesion
    -- puede SELECTear por RLS.
    -- DIVERGENCIA DECLARADA con la global: `metricas_conversiones_fn` NO filtra
    -- `activo` (as-built). Se acepta a proposito: entre «espejo exacto de
    -- leads_select» (regla de la tanda 1, 20260809043802:17) y «paridad con
    -- gerencia» manda la primera, porque es la que impide contar como propio lo
    -- que la RLS ya no deja ver. La diferencia solo aparece con leads
    -- soft-borrados en la ventana.
    select l.id as lead_id,
           l.vendedor_id,
           (l.contrato_id is not null) as contrato
    from crm.leads l
    where l.creado_en >= v_ini
      and l.creado_en < v_fin
      and l.activo is true
      and l.vendedor_id is not null
      and (v_global or l.vendedor_id = any(v_visibles))
  ),
  responsables_resumen as (
    -- LEFT JOIN: un vendedor del ambito sin leads en la ventana conserva su
    -- fila en ceros. El front exige la coleccion COMPLETA del roster visible;
    -- una fila ausente marca todo el bloque como indisponible.
    select r.vendedor_id,
      count(c.lead_id)::int as leads,
      count(c.lead_id) filter (where c.contrato)::int as clientes
    from roster r
    left join cohorte c on c.vendedor_id = r.vendedor_id
    group by r.vendedor_id
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    -- El chip «Mi equipo» / «Equipo completo» lo decide el SERVIDOR, que es
    -- quien conoce el ambito aplicado; el front no debe inferirlo de su rol.
    'alcance', case when v_global then 'global' else 'equipo' end,
    'periodo', jsonb_build_object(
      'desde', p_desde,
      'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1,
      'zona', 'America/Lima'
    ),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', rr.vendedor_id,
          'leads', rr.leads,
          -- AS-BUILT: `clientes` = leads de la cohorte CON CONTRATO. Nombre
          -- enganoso conservado a proposito para no partir la paridad.
          'clientes', rr.clientes,
          'conversion_pct', case when rr.leads > 0
            then round(100.0 * rr.clientes / rr.leads, 1) end
        )
        order by rr.clientes desc, rr.leads desc, rr.vendedor_id
      )
      from responsables_resumen rr
    ), '[]'::jsonb)
  ) into v_payload;

  -- Defensa en profundidad, identica a la del wrapper global: quita del
  -- desglose a cualquier sujeto que ya no tenga ROL EFECTIVO de vendedor
  -- (p. ej. un Superadmin de portal con membresia de vendedor, al que
  -- private.rol_crm() devuelve NULL aunque crm.equipo diga otra cosa).
  -- Exige que 'responsables' sea SIEMPRE un array: el coalesce a '[]' de
  -- arriba es lo que evita el 55000.
  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

comment on function crm.metricas_conversiones_equipo_fn(date, date) is
  'Ranking de conversion por vendedor RECALCULADO sobre el ambito del actor (decision #10, 2026-08-10). Supervisor: su subarbol recursivo. Gerencia y lector global: la empresa. Resto: 42501. Superficie minima a proposito — solo responsables{vendedor_id, leads, clientes, conversion_pct}, sin cohorte/embudo/origenes/categorias/produccion (agregados globales que no se pueden desagregar filtrando despues) ni capital ni tendencia. Sin PII: el front une los nombres con crm.equipo_visible_fn. Cohorte por fecha de alta, ventana semiabierta en America/Lima; clientes = leads con contrato (convencion as-built) para que el numero de un vendedor sea el mismo lo mire quien lo mire.';

revoke all on function crm.metricas_conversiones_equipo_fn(date, date)
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_conversiones_equipo_fn(date, date)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Postflight: la triada que el auditor exige de toda RPC nueva
-- ---------------------------------------------------------------------------
do $postflight$
begin
  if not exists (
    select 1
    from pg_catalog.pg_proc pr
    join pg_catalog.pg_namespace n on n.oid = pr.pronamespace
    where n.nspname = 'crm'
      and pr.proname = 'metricas_conversiones_equipo_fn'
      and pr.prosecdef
      and pr.provolatile = 's'
      and pr.proconfig @> array['search_path=""']
  ) then
    raise exception 'La RPC nueva debe ser SECURITY DEFINER, STABLE y con search_path vacio';
  end if;

  -- El revoke a service_role es la pata que un copy-paste incompleto rompe en
  -- SILENCIO: sin este guard, la RPC quedaria ejecutable por la clave de
  -- servicio sin que ningun test lo notara (canon: test-metricas-servidor.sql
  -- M09, que cuenta las tres juntas).
  if pg_catalog.has_function_privilege(
       'service_role', 'crm.metricas_conversiones_equipo_fn(date,date)', 'execute'
     ) then
    raise exception 'service_role no debe ejecutar la RPC nueva';
  end if;

  if pg_catalog.has_function_privilege(
       'anon', 'crm.metricas_conversiones_equipo_fn(date,date)', 'execute'
     ) then
    raise exception 'anon no puede ejecutar la RPC nueva';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.metricas_conversiones_equipo_fn(date,date)', 'execute'
     ) then
    raise exception 'authenticated debe poder ejecutar la RPC nueva';
  end if;
end;
$postflight$;

commit;

-- Nota de aplicacion:
--   · Nombre del archivo: `$(date -u +%Y%m%d%H%M%S)_crm_conversion_equipo_supervisor.sql`
--     (timestamp UTC del momento; dos migraciones en el mismo segundo colisionan
--     la PK de supabase_migrations.schema_migrations).
--   · `create index` sin CONCURRENTLY toma lock de escritura sobre crm.leads.
--     Instantaneo al volumen actual; a escala, sacarlo de la transaccion.
--   · Ciclo obligatorio: branch de Supabase -> aplicar -> `npm run seed:demo`
--     (el branch nace vacio) -> `supabase/scripts/test-rls.mjs` -> advisors
--     (0 ERROR; el WARN «definer ejecutable» de la familia de metricas ya esta
--     aceptado) -> merge. Prohibido apply_migration directo a produccion.
--   · Despues: `npm run gen:types` en `app/` y delta A MANO en
--     `database.types.ts` (el regen completo contra prod rompe el build).