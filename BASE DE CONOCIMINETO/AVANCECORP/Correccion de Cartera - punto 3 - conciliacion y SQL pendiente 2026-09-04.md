---
tags: [crm, gerencia, cartera, metricas, conciliacion, sql]
requerimiento: REQ-GER-MET-001
punto: 3
fecha: 2026-09-04
corte_datos: "2026-09-04 22:30:08 America/Lima"
estado: completado-sql-aplicado-frontend-publicado-verificado
verificado: "2026-09-04 23:23 America/Lima"
---

# Corrección de Cartera — punto 3: SQL aplicado y frontend publicado

Relacionado con [[Inicio]], [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]], [[Inventario de indicadores de Gerencia - Cartera y configuracion]], [[Auditoria de metricas de Gerencia - hallazgos y plan 2026-09-04]] y [[Gestión comercial de clientes - renovaciones y upgrades]].

**Publicación posterior — 4 de septiembre, 23:49 Lima:** autorizado por Miguel, frontend publicado desde `50f33a5`, Main sincronizado antes del build/deploy y Cartera verificada con sesión de Gerencia: 420 clientes, saldos globales finales coherentes con la conciliación y 3 por vencer. No se reaplicó SQL. Evidencia, observación de transición visual para el punto 5 y reversión en [[Publicacion frontend metricas Gerencia 2026-09-04]]. Los apartados siguientes conservan el corte histórico de implementación local y de aplicación SQL; «sin deploy» describe ese momento anterior.

## Mandato y estado real

Miguel autorizó comenzar el punto 3 con «ok hazlo». Sigue vigente la condición de **mostrar el SQL exacto y esperar confirmación antes de cambiar la base de datos**.

Se completó la revisión de fuentes y la conciliación agregada de la lectura global de Gerencia. Miguel confirmó el SQL con «sí» después de recibir la propuesta exacta y la condición de prueba aislada. **Punto 3 completado: SQL aplicado y verificado; frontend implementado y verificado localmente, todavía sin publicar.** Ver resultados y límites al final de esta nota. Los puntos 4 y 5 siguen pendientes.

## Aplicación autorizada y verificación — 4 de septiembre, 22:50 Lima

- Banco desechable PostgreSQL 16.14, socket Unix privado, sin TCP ni datos productivos. Fixtures poblados antes de aplicar; siete contextos de acceso (dobles controlados del contexto de autorización), V1/V2/vista, 56 lecturas de cronograma y 56 de titulares, ACL, datos intactos, reversión y reaplicación: `CARTERA_SIN_DEMO_LOCAL_OK`. No equivale a ejecutar toda la matriz RLS en una réplica completa.
- SQL de migración y reversión comprobados frente a los dos bloques aprobados. El registro remoto contiene exactamente el SQL aprobado (MD5 `b44d8f5bdfd090a2be367bf37b1e263b`); el archivo local sólo añade el salto de línea final. El banco detectó y se corrigió una ambigüedad de alias en la aserción de la prueba, no en el SQL aprobado.
- Aplicación única por MCP, sin `db push`, sin otras migraciones: versión registrada **`20260905034917_crm_cartera_excluir_contratos_demo.sql`**. El archivo creado con CLI se renombró al timestamp registrado realmente por el servidor; conserva el mismo contenido.
- Lectura posterior bajo `authenticated` y contexto transaccional de un miembro activo de Gerencia, dentro de `begin read only` / `rollback`. Sólo agregados; no se abrió ni modificó una sesión de autenticación. V2 devuelve 517 contratos: 447 PEN y 70 USD. Capital vigente **PEN 19.485.413,12 / USD 1.075.193,33**, idéntico a la llamada real de `resumen_cartera_clientes_fn`. 420 clientes en gestión, 393 con capital y 3 contratos por vencer.
- Catálogo antes/después de 38 funciones: cambió únicamente la definición de `crm.contratos_cartera_fn`; ningún cambio de propietario, ACL, opciones o modo de ejecución. Núcleos intactos.
- Ambos clusters locales se detuvieron. Los directorios temporales conservan sólo fixtures y logs; no se borró información del usuario.

Se preservaron todas las correcciones locales del punto 2 y el trabajo concurrente. HEAD avanzó durante esta ejecución de `c477fec` a `ed2b7ea`, Main siguiendo `avancecorp/main`; esta tarea no hizo commit, push ni deploy de frontend. Los cambios concurrentes de F2.b y altas nuevas no pertenecen a este punto.

## Conciliación previa — corte 22:30 Lima, antes de aplicar

Consultas agregadas en producción, bajo `begin read only`, límite de tiempo y `rollback`. No se consultaron nombres, documentos, contactos ni cuentas. Se compararon los conjuntos fuente con el ámbito global de Gerencia; **no fue una prueba de la RPC mediante la sesión de un usuario ni una prueba UI**.

| Lectura global de contratos activos de clientes en gestión | PEN | USD |
|---|---:|---:|
| Listado anterior, incluidas pruebas | 19.585.413,12 | 1.175.193,33 |
| Mismo listado sin contratos de prueba | 19.485.413,12 | 1.075.193,33 |
| Fuente de `resumen_cartera_clientes_fn` | 19.485.413,12 | 1.075.193,33 |

- Dos contratos de prueba activos: uno PEN 100.000, cerrado comercialmente el 12/08, y otro USD 100.000, cerrado el 22/08. No explican diferencias de septiembre.
- 519 contratos en el listado anterior; 517 reales después de excluir pruebas: 447 PEN y 70 USD. **Cero identificadores distintos** frente a los hechos contractuales del núcleo para el mismo ámbito.
- 420 clientes en gestión, ninguno de baja en este corte. 393 con capital real activo; coinciden entre listado sin pruebas y fuente del resumen.
- Tres contratos reales por vencer en 30 días, todos PEN; coincide la población. El resumen usa el día de Lima.
- El resumen sirve cuatro clientes activos con `asesor_perfil_id IS NULL`. Esto **no se certifica como el indicador UI «Sin analista»**: la UI aplica dueño/fallback y pertenencia al roster.
- Cero contratos reales de titulares cuyo rol no sea cliente, en este corte.
- `public.contratos.es_demo` es no nulo. El núcleo excluye con `not c.es_demo`; la propuesta utiliza exactamente ese predicado.

No se borran perfiles. La exclusión es contractual: no se inventa una regla para eliminar personas de las listas ni se afirma que «contrato de prueba» sea equivalente a «perfil de prueba».

## Mapeo implementado en el frontend local

| Indicador | Fuente existente | Precaución |
|---|---|---|
| Capital vigente PEN/USD | `resumen_cartera_clientes_fn.capital_activo.pen/usd` | Conciliado para Gerencia global; excluye bajas y contratos de prueba, no incluye cooperativas. |
| Clientes en gestión, de baja y con capital | `clientes.en_gestion/de_baja/con_capital` | Mismo universo global de perfiles; mantener cada categoría. |
| Por vencer y subconjunto de baja | `contratos.por_vencer_30/por_vencer_30_de_baja` | Global, incluso al elegir mes; reloj Lima también para el listado alcanzado desde el aviso. |
| Sin analista | Criterio actual sobre listado confirmado completo | No sustituir por `clientes.sin_asesor`: pregunta distinta. No crear otra fórmula. |
| Cerrado en el mes y filtros | Lectura contractual existente completa y agrupador existente | No conectar directamente `contratos_por_periodo_comercial_fn.totales`: incluye cooperativas y no aplica filtros locales de analista/estado/texto. No confundir capital nominal contractual con dinero nuevo/adicional. |
| Ficha, subfilas, cronograma e historial | Lecturas actuales | Validación/completitud explícitas; no presentar filas omitidas como lectura completa. |

La lectura anterior de clientes, contratos y operaciones limitaba a 2.000 filas y algunas validaciones omitían filas. Se sustituyó por descarga paginada en la **capa de transporte existente**, sin nuevas calculadoras de negocio: páginas de 200, conteo exacto del servidor, orden estable con ID como desempate y avance por filas realmente recibidas. Conteo ausente o cambiante, página faltante, IDs repetidos y filas inválidas invalidan la respuesta completa. El fusible de tráfico produce error, nunca una lista truncada exitosa. No se cambió el `max_rows` remoto.

La descarga verificada no es una transacción atómica entre peticiones HTTP: no promete una fotografía única si cambian filas conservando el mismo total. Sí elimina el corte silencioso y detecta las inconsistencias observables sin ampliar el servidor. Las lecturas de clientes y contratos tampoco se entregan al agrupador si hay contratos sin su cliente.

Para roles no globales hay otra diferencia: el resumen existente no aplica el fallback por `creado_por` de la lista. **No extender automáticamente la conexión conciliada para Gerencia a esos roles.** No modificar esa semántica ni permisos dentro de este arreglo.

## Por qué se necesita este SQL

**Comercialmente:** el dinero de prueba no debe aparecer como inversión real ni contradecir el resumen del servidor.

**Técnicamente:** `crm.contratos_cartera` lee `contratos_cartera_v2_fn()`, que delega en `contratos_cartera_fn()`. Esa fachada no filtraba ni exponía `es_demo`. El frontend no podía distinguir con fiabilidad las pruebas de los contratos reales. Ocultarlas por monto, nombre, fecha o ID de cliente sería una regla inventada.

Se modifica **sólo `crm.contratos_cartera_fn()`**, añadiendo `not c.es_demo` por fuera de todo el OR de autorización. No se crea ninguna función persistente ni RPC nueva; los bloques `DO` son controles de la operación, no lógica comercial. No cambia la firma, las 24 columnas, el dueño, los grants, el `SECURITY DEFINER` ya existente, el `search_path` vacío ni los controles de rol/ámbito. No se tocan núcleos, fechas, monedas, conversiones, cuotas, contratos o perfiles almacenados.

**Efectos de lectura aplicados:** las dos pruebas dejan de figurar para todos los consumidores de esa fachada. Además de V2, `cronograma_contrato_fn` y `titulares_contrato_fn` la usan para comprobar visibilidad; esas consultas dejan de devolver datos de los contratos de prueba. Las lecturas que autorizan por la vista heredan la misma exclusión. Los documentos y datos subyacentes se conservan. Contratos reales: misma autorización y mismo contenido. No se cambiaron las funciones consumidoras.

## SQL exacto aprobado y aplicado

Este bloque contiene la definición completa, sin elipsis. Sus comprobaciones abortan si la fachada, su dueño o permisos dejaron de coincidir con lo revisado. La huella prevista se confirmó primero en el banco aislado y después en el servidor.

```sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $revision$
begin
  if (
    select md5(pg_get_functiondef(p.oid))
    from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
  ) is distinct from '6ed1e840295a31bc3c464418411c773c' then
    raise exception 'La fachada cambio o no existe. Revalidar antes de continuar.';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
      and p.proowner = 'postgres'::regrole
      and p.proacl::text =
        '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
      and p.proconfig = array['search_path=""']
      and p.provolatile = 's' and p.prosecdef
  ) then
    raise exception 'Los permisos o atributos cambiaron. Revalidar antes de continuar.';
  end if;
end;
$revision$;

CREATE OR REPLACE FUNCTION crm.contratos_cartera_fn()
 RETURNS TABLE(id uuid, numero_contrato text, cliente_id uuid, cliente_nombre text, asesor_perfil_id uuid, capital numeric, moneda text, tasa_anual numeric, modalidad text, tipo_interes text, categoria text, estado text, fecha_inicio date, fecha_vencimiento date, notas_internas text, creado_por uuid, creado_en timestamp with time zone, producto_condicion_id uuid, producto_id uuid, producto_codigo text, producto_version_id uuid, producto_version integer, producto_nombre text, producto_version_estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    c.id, c.numero_contrato, c.cliente_id, cli.nombre_completo,
    cli.asesor_perfil_id, c.capital, c.moneda, c.tasa_anual, c.modalidad,
    c.tipo_interes, c.categoria, c.estado, c.fecha_inicio,
    c.fecha_vencimiento, c.notas_internas, c.creado_por, c.creado_en,
    c.producto_condicion_id, p.id, p.codigo, v.id, v.numero_version,
    v.nombre, v.estado
  from public.contratos c
  join public.perfiles cli on cli.id = c.cliente_id
  join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
  join crm.producto_versiones v on v.id = pc.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where not c.es_demo
    and (
    (select private.es_lector_global())
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    or cli.asesor_perfil_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    )
    or (
      cli.asesor_perfil_id is null
      and cli.creado_por in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
  );
$function$;

do $verificacion$
begin
  if (
    select md5(pg_get_functiondef(p.oid))
    from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
  ) is distinct from 'afa02c967897b50312d1a963deed0d44' then
    raise exception 'La definicion resultante no coincide con la aprobada.';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
      and p.proowner = 'postgres'::regrole
      and p.proacl::text =
        '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
      and p.proconfig = array['search_path=""']
      and p.provolatile = 's' and p.prosecdef
  ) then
    raise exception 'No se conservaron los permisos o atributos de la fachada.';
  end if;
end;
$verificacion$;

commit;
```

No ejecutar `db push` global ni incluir migraciones ajenas. La confirmación requerida se limita a esta corrección; no autoriza nuevas salidas, cambios del núcleo ni publicación del frontend.

## Reversión exacta — sólo si fuera necesaria y autorizada

Restaura únicamente la definición anterior de la misma fachada, sin borrar datos. La guarda exige que siga instalada la definición propuesta; si hay un cambio posterior, aborta para no sobrescribirlo. **Restaurar vuelve a hacer visibles los contratos de prueba.**

```sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $revision$
begin
  if (
    select md5(pg_get_functiondef(p.oid))
    from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
  ) is distinct from 'afa02c967897b50312d1a963deed0d44' then
    raise exception 'La fachada cambio o no existe. Revalidar antes de continuar.';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
      and p.proowner = 'postgres'::regrole
      and p.proacl::text =
        '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
      and p.proconfig = array['search_path=""']
      and p.provolatile = 's' and p.prosecdef
  ) then
    raise exception 'Los permisos o atributos cambiaron. Revalidar antes de continuar.';
  end if;
end;
$revision$;

CREATE OR REPLACE FUNCTION crm.contratos_cartera_fn()
 RETURNS TABLE(id uuid, numero_contrato text, cliente_id uuid, cliente_nombre text, asesor_perfil_id uuid, capital numeric, moneda text, tasa_anual numeric, modalidad text, tipo_interes text, categoria text, estado text, fecha_inicio date, fecha_vencimiento date, notas_internas text, creado_por uuid, creado_en timestamp with time zone, producto_condicion_id uuid, producto_id uuid, producto_codigo text, producto_version_id uuid, producto_version integer, producto_nombre text, producto_version_estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    c.id, c.numero_contrato, c.cliente_id, cli.nombre_completo,
    cli.asesor_perfil_id, c.capital, c.moneda, c.tasa_anual, c.modalidad,
    c.tipo_interes, c.categoria, c.estado, c.fecha_inicio,
    c.fecha_vencimiento, c.notas_internas, c.creado_por, c.creado_en,
    c.producto_condicion_id, p.id, p.codigo, v.id, v.numero_version,
    v.nombre, v.estado
  from public.contratos c
  join public.perfiles cli on cli.id = c.cliente_id
  join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
  join crm.producto_versiones v on v.id = pc.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where (
    (select private.es_lector_global())
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    or cli.asesor_perfil_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    )
    or (
      cli.asesor_perfil_id is null
      and cli.creado_por in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
  );
$function$;

do $verificacion$
begin
  if (
    select md5(pg_get_functiondef(p.oid))
    from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
  ) is distinct from '6ed1e840295a31bc3c464418411c773c' then
    raise exception 'La definicion resultante no coincide con la aprobada.';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
      and p.proowner = 'postgres'::regrole
      and p.proacl::text =
        '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
      and p.proconfig = array['search_path=""']
      and p.provolatile = 's' and p.prosecdef
  ) then
    raise exception 'No se conservaron los permisos o atributos de la fachada.';
  end if;
end;
$verificacion$;

commit;
```

## Evidencia de invariantes

Se compararon 34 funciones protegidas contra el cierre del punto 2: **sin diferencias** en definición, propietario, ACL, opciones, volatilidad ni modo de ejecución. Se añadió a la lectura de catálogo `private.cliente_ids_visibles_crm` sólo para conciliar ámbitos, no para modificarla.

Huellas `md5(pg_get_functiondef(...))`:

| Objeto | Huella |
|---|---|
| `crm.contratos_cartera_fn` antes de aplicar | `6ed1e840295a31bc3c464418411c773c` |
| Misma fachada aplicada y verificada | `afa02c967897b50312d1a963deed0d44` |
| `crm.contratos_cartera_v2_fn` | `0543dfd4fbbc933d5fdea1cf8385a527` |
| `crm.resumen_cartera_clientes_fn` | `d8551a70db3ac32e150e417648585a8a` |
| `private.capital_episodios` | `b8f375fbb377582835f4cfe222240c5b` |
| `private.conversion_episodios` | `8a2549dbfa59c732da04900ed90b6361` |
| `private.citas_episodios` | `ea636888a266941e959f26c6a5727216` |

Herramientas: CodeGraph primero; lecturas complementarias de código y vault; documentación vigente de [Supabase](https://supabase.com/changelog.md) y del [cliente oficial, consultado mediante Context7](https://github.com/supabase/supabase-js). No se encontró un cambio anunciado que obligue a migrar dependencias para esta corrección. La guía de Supabase/Postgres orientó la conservación de privilegios y la revisión de límites/paginación, no un cambio de autorización.

La relectura final de las 38 funciones coincidió sin diferencias con el catálogo posterior a la aplicación. Otra consulta agregada como Gerencia encontró 517 contratos, cero contratos sin su cliente en el listado, cero capitales/tasas inválidos y cero fechas contractuales requeridas ausentes. No se ejecutaron semillas, mutantes ni pruebas de escritura en producción.

## Implementación local y verificación

- `app/src/data/crm-api.ts`: transporte paginado para las tres lecturas existentes, validación íntegra de filas/importes/fechas y adaptador del RPC **ya existente** `resumen_cartera_clientes_fn`. No se creó una RPC ni una fórmula comercial.
- `app/src/data/crm-queries.ts` y `lib/clientes-tipos.ts`: contrato tipado, consulta por identidad del actor, refresco periódico e invalidación bajo la familia existente de métricas.
- `app/src/screens/mi-cartera.tsx`: Gerencia/Directorio conectan sólo los campos equivalentes del resumen global. Mes/filtros y «Sin analista» conservan sus agrupadores y criterios. Un error sin resumen no presenta ceros; un refresco fallido conserva datos con aviso/reintento. Resumen y listado cargan por separado. Una lectura vacía confirmada sí puede mostrar cero. Correcciones/altas actualizan la caché pertinente.
- `app/src/lib/cartera-vista.ts`: el cálculo existente de vencimientos usa el día de Lima mediante `fechaLima`; no depende de la zona del navegador.
- Pruebas de contrato, consultas e interfaz: más de 2.000 clientes con límite remoto simulado menor que la página, filas/total inválidos, duplicados, cancelación, RPC sin datos, permisos, monedas separadas, mes frente a saldo, roles, listado huérfano, caché fallida y reintento.
- Banco SQL reproducible: `supabase/scripts/test-cartera-sin-demo-local.mjs` y `test-cartera-sin-demo-fixtures.sql`; sólo acepta socket temporal local sin TCP. Reversión conservada en `rollback-cartera-excluir-demo.sql` y en esta nota; **no ejecutarla en producción sin autorización**.

**Validación final — 23:23 Lima:** 2.741 pruebas aprobadas en 191 archivos; 120 E2E aprobadas y 26 omisiones previas, cero fallos. Incluye 102 casos de la pantalla Cartera y tres recorridos nuevos del resumen/completitud. Typecheck, compilación, comprobación del bundle y duplicación aprobados (0,69 %, umbral 0,8 %). Lint conserva únicamente cuatro avisos previos en `coverflow-carousel.tsx`, ninguno nuevo de Cartera. La compilación mantiene los avisos previos de tamaño de chunk/importación demo. `git diff --check` sin errores.

El primer E2E general dio 119 aprobadas, 26 omisiones previas y un fallo ajeno a Cartera: el fixture aún simulaba `metricas_altas_analista_fn`, mientras el trabajo concurrente ya consumía `altas_nuevas_por_analista_fn`. Se actualizó sólo la ruta simulada en `_helpers.ts`, sin tocar la función real ni la implementación concurrente.

Una pasada posterior coincidió con cambios transitorios en los archivos compartidos durante el commit concurrente `ed2b7ea`: 23 pruebas y typecheck fallaron por ausencia temporal de los exports de Cartera. Aunque los archivos reaparecieron y el E2E de esa pasada acabó en verde, **no se aceptó como validación final**. Se repitieron todos los gates sobre código estable. Huella SHA-256 del manifiesto ordenado de `src/` y `e2e/`, idéntica antes y después de la pasada final: `6293c89519375126421178978072b38099b06271e118f6200f04ce80090d7212`.

Advisors consultados: seguridad 141 WARN / 39 INFO / 0 ERROR; rendimiento 5 WARN / 77 INFO / 0 ERROR. La fachada y el resumen conservan el aviso genérico de [función SECURITY DEFINER ejecutable por authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable): el modo y ACL ya eran éstos y se preservaron. No hay avisos de rendimiento que nombren esas funciones. Esto no certifica ni corrige los demás avisos del proyecto.

## Continuación

1. Punto 3 cerrado; no reaplicar la migración. Siguiente punto del plan: 4, explicar y acordar los datos faltantes antes de ampliar nada.
2. Mantener pendiente el punto 5 (conciliación integral); las pruebas de este arreglo no lo sustituyen.
3. No publicar por esta continuidad. Un deploy posterior requiere autorización y artefacto construido desde Main sincronizado con `avancecorp/main`; el árbol actual contiene trabajo local y concurrente, por lo que este build de prueba no es un artefacto autorizado para publicar.
