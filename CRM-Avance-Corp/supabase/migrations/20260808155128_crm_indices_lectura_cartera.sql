-- Indices de lectura de la cartera de leads.
--
-- Preparacion del terreno para paginar la cartera (Movimiento 3 del plan de
-- escalabilidad, 2026-08-08). Hoy no cambia ningun comportamiento: con ~300
-- leads el planner elige seq scan igual. Se aplica AHORA porque paginar sin el
-- indice de orden es PEOR que no paginar (reordena todo el conjunto visible en
-- cada pagina que se pide).
--
-- Solo agrega indices. No toca policies, funciones, grants, columnas ni datos.
-- Ningun objeto de `public` es alterado.
--
-- NO se elimina ningun indice existente: el advisor reporta varios sin uso,
-- pero `crm.tareas` y `crm.actividades` tienen 0 filas y `crm.leads` tiene 1,
-- de modo que "nunca escaneado" no prueba inutilidad a volumen real. Esa poda
-- se decide con trafico de produccion, no con estas estadisticas.

begin;

set local lock_timeout = '10s';

-- ============================================================================
-- 1. Orden de la cartera: (actualizado_en desc, id)
-- ============================================================================
-- Sirve al ORDER BY exacto de las dos lecturas de cartera del front
-- (app/src/data/crm-api.ts): `listarLeadsDelAmbito` (limit 2000) y
-- `listarLeads` (paginada con range). Ambas ordenan por
-- `actualizado_en desc, id asc`.
--
-- ⚠️ DELIBERADAMENTE NO PARCIAL. Un `where activo = true` seria mas pequeno,
-- pero `listarLeadsDelAmbito` NO envia ese predicado: confia en la RLS. Y la
-- expresion de `leads_select` lo tiene dentro de un OR
-- (`(activo = true and ...) or es_lector_global()`), de donde el planner no
-- puede deducir `activo = true` incondicionalmente. Con indice parcial la
-- consulta del ambito — justo la que hoy tiene el techo de 2000 — se quedaria
-- sin usarlo. El coste es incluir las filas con `activo = false` (leads
-- descartados, que ya salen del ambito por `crm.descartar_lead`).

create index leads_orden_cartera_idx
  on crm.leads (actualizado_en desc, id);

comment on index crm.leads_orden_cartera_idx is
  'Orden de las lecturas de cartera (actualizado_en desc, id). No parcial a proposito: la consulta del ambito no envia activo=true explicito.';

-- El indice de arriba resuelve el orden GLOBAL, que es el caso de gerencia
-- (ve toda la empresa por RLS). Vendedor y supervisor no leen global: la RLS
-- los recorta con `vendedor_id in (private.vendedor_ids_visibles(...))` y
-- DESPUES ordena. Con cartera grande eso es filtrar por indice y ordenar el
-- resultado a mano. Este compuesto entrega las dos cosas ya resueltas y evita
-- el sort por completo.
--
-- `idx_leads_vendedor` (existente) NO lo cubre: indexa solo `vendedor_id`, sin
-- el orden. Se conserva porque sigue siendo mas barato para los conteos y
-- filtros que no ordenan.

create index leads_vendedor_orden_idx
  on crm.leads (vendedor_id, actualizado_en desc)
  where vendedor_id is not null;

comment on index crm.leads_vendedor_orden_idx is
  'Cartera de un vendedor ya ordenada: evita el sort cuando la RLS recorta por vendedor_id antes de ordenar.';

-- ============================================================================
-- 2. Busqueda por texto: trigram sobre nombre / telefono / DNI
-- ============================================================================
-- `listarLeads` busca con `ilike '%texto%'` sobre las tres columnas unidas por
-- OR. Un btree no puede servir a un patron que empieza en comodin: hoy esa
-- busqueda recorre la tabla entera en cada tecleo. `pg_trgm` ya estaba
-- instalado en el proyecto pero sin un solo indice que lo usara.
--
-- Uno por columna (no uno compuesto) para que el planner pueda combinarlos con
-- BitmapOr, que es la forma del OR que arma la consulta.
--
-- `dni` es la unica nullable de las tres: su indice se restringe a las filas no
-- nulas. Ese predicado SI es deducible — `dni ilike '...'` implica
-- `dni is not null` — asi que el parcial no deja la consulta sin indice.

create index leads_nombre_trgm_idx
  on crm.leads using gin (nombre_completo gin_trgm_ops);

create index leads_telefono_trgm_idx
  on crm.leads using gin (telefono gin_trgm_ops);

create index leads_dni_trgm_idx
  on crm.leads using gin (dni gin_trgm_ops)
  where dni is not null;

comment on index crm.leads_nombre_trgm_idx is
  'Busqueda ilike %texto% por nombre en la cartera paginada.';
comment on index crm.leads_telefono_trgm_idx is
  'Busqueda ilike %digitos% por telefono en la cartera paginada.';
comment on index crm.leads_dni_trgm_idx is
  'Busqueda ilike %digitos% por DNI en la cartera paginada. Parcial: dni es nullable y el predicado se deduce del propio ilike.';

-- ============================================================================
-- 3. Llave foranea sin indice de cobertura (advisor 0001)
-- ============================================================================
-- Sin indice, cada UPDATE/DELETE sobre la fila padre obliga a un scan completo
-- de la hija para validar la referencia.
--
-- El advisor reportaba ADEMAS 3 FKs sin indice en crm.objetivos_vendedores,
-- pero esa tabla fue archivada el MISMO 2026-08-08 por la migracion de metas
-- versionadas (otra sesion; ahora es objetivos_vendedores_legacy_archivo, sin
-- Data API). El modelo nuevo (metas_vendedor*) nacio con sus indices. Solo
-- sobrevive la FK de enfriamiento_politica.

create index enfriamiento_politica_actualizado_por_idx
  on crm.enfriamiento_politica (actualizado_por)
  where actualizado_por is not null;

commit;

-- Nota de aplicacion: `create index` (sin CONCURRENTLY) toma un lock que
-- bloquea escrituras sobre la tabla mientras construye. Con el volumen actual
-- (1 lead, 0 objetivos) es instantaneo. Si esta migracion se replicara contra
-- una base ya poblada, pasar a `create index concurrently` FUERA de la
-- transaccion.
