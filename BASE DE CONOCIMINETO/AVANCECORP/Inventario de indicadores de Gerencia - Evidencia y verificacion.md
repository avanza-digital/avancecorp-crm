---
tags: [crm, gerencia, inventario, evidencia]
requerimiento: REQ-GER-MET-001
estado: verificado-punto-1-completo
---

# Inventario de indicadores de Gerencia — evidencia y verificación

Complemento de [[Inventario de indicadores de Gerencia - Contrato de lectura]] y [[Plan de correccion de metricas de Gerencia - requerimiento vigente]]. Este registro documenta lecturas; no contiene migraciones ni instrucciones para modificar el servidor.

## Estado inicial del código

- HEAD al iniciar: `2742bf88fd14356bfe046311b0967738871f2df7`.
- Árbol de aplicación: `ed23ef494093755055f1b236a37d9830fe3220f9`.
- Durante la ejecución otro trabajo incorporó `ecbb7b97ad79124e34f1a924227d27dd8585c737`, limitado a `supabase/scripts/test-rls.mjs` y `supabase/migrations/MIGRACIONES.md`; se comprobó que el árbol de aplicación permaneció idéntico.
- No se ejecutó ese script de pruebas ni se aplicaron sus migraciones. Los cambios previos del vault se preservan. Esta tarea sólo escribe documentos de inventario y seguimiento.

## Registro productivo inicial de fuentes

Proyecto `dctqcbznekcyxhjujuci`. Consulta de catálogo en `begin read only`, `statement_timeout='15s'`, `rollback`; sin extraer usuarios, secretos o datos personales. Las34 filas incluyen funciones privadas y públicas de métricas: **estar aquí no demuestra consumo por una pantalla**; las notas C/O/K trazan los consumidores efectivos.

Huella = `md5(pg_get_functiondef(oid))`. Además se comparan propietario, ACL, configuración, volatilidad y definidor/invocador. Todos son `STABLE`; `SD` significa SECURITY DEFINER y `SI` SECURITY INVOKER.

| Función y firma | Huella inicial | Propietario | Modo | ACL y configuración |
|---|---|---|---|---|
| `crm.cola_accion_fn(p_limite integer)` | `91ea0a30ba6f65a9433cd6c417a7f58c` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.conversion_mensual_fn(p_periodo date)` | `e8b7bbfa62e46bcd5a680a9a5996a8d0` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`; `search_path=""` |
| `crm.cumplimiento_metas_fn(p_periodo date)` | `0bde18875efbb757801633571e558ca2` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`; `search_path=""` |
| `crm.metricas_agenda_fn(p_desde date, p_hasta date)` | `1a5f2938a6c42f44b511e53f48edf963` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.metricas_altas_analista_fn(p_meses integer)` | `f439e788e16a49fa23d8b52c0047f929` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=private, public, crm` |
| `crm.metricas_capital_mes_fn(p_meses integer)` | `c872d4be13e8284a64e70861318cb9be` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.metricas_cartera_fn(p_periodo date)` | `0bfcc0d49bec2f6fda3cc844b813118c` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=""` |
| `crm.metricas_conversiones_equipo_fn(p_desde date, p_hasta date)` | `d67db4c1204456b57d3271d6c94064b6` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.metricas_conversiones_fn(p_desde date, p_hasta date, p_origen text)` | `5edb160355011bd0485661485c9317df` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.metricas_distribucion_leads_fn(p_desde date, p_hasta date)` | `3614ce10ba27543b9e6289b949c8aea9` | `crm_metricas_bridge` | SD | `{crm_metricas_bridge=X/crm_metricas_bridge}`; `search_path=""` |
| `crm.metricas_distribucion_leads_v2_fn(p_desde date, p_hasta date)` | `4f9186ab5d73f9f4e9114f271aa78a15` | `crm_metricas_bridge` | SD | `{crm_metricas_bridge=X/crm_metricas_bridge}`; `search_path=""` |
| `crm.metricas_distribucion_leads_v3_fn(p_desde date, p_hasta date)` | `4d443467e82f589f5e5059de97230c42` | `crm_metricas_bridge` | SD | `{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}`; `search_path=""` |
| `crm.metricas_pagos_mes_fn(p_meses integer)` | `e067033e5051e7da3d5c8ecbdfecd9b8` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=private, public, crm` |
| `crm.metricas_reuniones_fn(p_desde date, p_hasta date)` | `de328143bd9221fb19bfa6af46695290` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.metricas_sla_fn(p_desde date, p_hasta date)` | `6789ae330d883912bdf1d7d6bbb67246` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.metricas_vencimientos_fn(p_dias integer)` | `1d0a9f6e4e262f57fc94057c7246ca6d` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.metricas_vendedores_fn()` | `7462d4e1736ebe22fc2268b1cb71e105` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.resumen_cartera_clientes_fn()` | `d8551a70db3ac32e150e417648585a8a` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.resumen_cartera_fn()` | `e69c9eb25ef352150404875f3b5687c5` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.resumen_reparto_fn()` | `af9cc1965a8384d40b4f0d440de14f4e` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.resumen_tareas_fn()` | `a09cd13c79eb9c073ed55efd168c6808` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `crm.series_comerciales_fn(p_meses integer)` | `91ea3ad984ce63060e21d8da51b75255` | `postgres` | SD | `{postgres=X/postgres,authenticated=X/postgres}`; `search_path=""` |
| `private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])` | `b8f375fbb377582835f4cfe222240c5b` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=""` |
| `private.citas_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_ahora timestamp with time zone)` | `ea636888a266941e959f26c6a5727216` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=""` |
| `private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)` | `8a2549dbfa59c732da04900ed90b6361` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=""` |
| `private.metricas_agenda_implementacion(p_desde date, p_hasta date)` | `5cb341dc430b7441ff8abdd3c8110c60` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=""` |
| `private.metricas_cartera_por_vendedor(p_periodo date)` | `c1a0bab01e474af758f0feff8819414f` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=""` |
| `private.metricas_conversiones_implementacion(p_desde date, p_hasta date, p_origen text)` | `372a4cfaf71bbbfcc1c921ca48096125` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=""` |
| `private.metricas_distribucion_leads_autorizada(p_desde date, p_hasta date, p_version smallint)` | `8d4abfc9625c0c48ae39564db84cda0a` | `postgres` | SD | `{postgres=X/postgres,crm_metricas_bridge=X/postgres}`; `search_path=""` |
| `private.metricas_distribucion_leads_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)` | `f8748197c550484ae59b6257397a5013` | `postgres` | SI | `{postgres=X/postgres}`; `search_path=""` |
| `private.metricas_distribucion_leads_v2_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)` | `7408cb964af34dfb091108c5a7062cc4` | `postgres` | SI | `{postgres=X/postgres}`; `search_path=""` |
| `private.metricas_distribucion_leads_v3_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)` | `be2290576ef7f8947f3b4d3a9db846a7` | `postgres` | SI | `{postgres=X/postgres}`; `search_path=""` |
| `private.metricas_reuniones_implementacion(p_desde date, p_hasta date)` | `7f4f885e2d044afdd2fd0766991517a0` | `postgres` | SD | `{postgres=X/postgres}`; `search_path=""` |
| `private.metricas_sla_global_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)` | `2353b10e1ff2104ffb14441485eb7dde` | `postgres` | SI | `{postgres=X/postgres}`; `search_path=""` |

## Comprobaciones exigidas al cierre

- Cobertura de las20 rutas permitidas de Gerencia, alias y componentes transversales.
- Identificadores únicos por nota; fuentes de código existentes y campos/semánticas trazados.
- Dimensiones de cada indicador: unidad, fecha, ámbito/atribución, exclusiones y disponibilidad, heredadas de la sección cuando son comunes.
- Diferencias de definición y datos faltantes explícitos; no confundir ausencia de campo con cero.
- Comparación completa de las34 filas del catálogo inicial/final, incluidas firmas/permisos.
- Árbol de aplicación igual y sin modificaciones de aplicación o SQL en el worktree por esta tarea.
- Notas enlazadas al requerimiento e Inicio; punto1 cerrado sólo después de validar el entregable.

## Comparación final del servidor y código

Comprobación del 4 de septiembre de 2026, **21:09:42 America/Lima** (5 de septiembre, 02:09:42 UTC):

- Se repitió la misma consulta de catálogo de solo lectura: **34 filas iniciales y 34 finales, sin diferencias** de definición, firma, propietario, ACL, configuración, volatilidad ni modo definidor/invocador.
- Los siete núcleos/fuentes privadas protegidos de la nota principal conservan exactamente sus huellas iniciales. Esta comparación no es una auditoría general de todos los permisos de la base de datos.
- HEAD permanece en `ecbb7b97ad79124e34f1a924227d27dd8585c737`; árbol de aplicación `ed23ef494093755055f1b236a37d9830fe3220f9`, idéntico al inicial. Se preservaron los cambios concurrentes de pruebas/documentación.
- `git diff --check` no informó errores en cambios rastreados. La comprobación documental de archivos nuevos se registra al consolidar las tres notas.
- Catálogo de rutas comprobado contra `router.ts`, `vistas.ts`, `roles.ts` y `config.ts`: 21 rutas, 20 permitidas para Gerencia; `derivaciones` queda expresamente fuera, y los alias conservan sus destinos.

## Resultado de cierre

**Punto 1 completo, 4 de septiembre de 2026, 21:21 America/Lima.**

- Se repitió nuevamente el catálogo a las **02:21:00 UTC del 5 de septiembre**: mismas 34 filas y metadatos completos, sin diferencias frente al inicio.
- Lectura completa de las tres notas y verificación de correspondencias: **C01–C80 (80), O01–O140 (140), K01–K116 (116)**; 336 registros, prefijos únicos y sin huecos. Incluyen indicadores, contadores, estados y parámetros expresamente distinguidos.
- Comprobación documental de enlaces Obsidian, rutas fuente explícitas y límites de línea de localizadores abreviados: sin referencias faltantes; se retiró un ejemplo de ruta con puntos suspensivos que el comprobador identificaba como ruta literal. Sin espacios finales en las notas nuevas.
- Cobertura contrastada con catálogo/permisos: 20 rutas permitidas; alias y fichas incluidas. Rendimiento sólo inventaría la variante efectivamente montada (`mostrarOperacion=false`), no paneles de reparto ocultos.
- Definiciones ambiguas quedaron separadas: llegada/base/asignación; cita/lead inferido; cierre de mes/inventario/cohorte; capital estimado/producción/saldo; parámetros/resultados. Unidad, fecha, ámbito/atribución, exclusiones y disponibilidad se especifican por fila o contrato común.
- Vista adicional de Compromisos leída sin filas de negocio: `crm.alertas_reconocimientos_vigentes`, `md5(pg_get_viewdef)=339b01e24dfab12540f42ffb062a9eb6`. Su lectura no forma parte de las 34 funciones; no se atribuye a esa comparación una cobertura que no tiene.
- HEAD y árbol de aplicación al cierre siguen siendo los registrados arriba; `git diff --name-only` y archivos nuevos de aplicación/SQL vacíos. `git diff --check` sin errores. Se preservaron todos los cambios concurrentes ajenos.
- Requerimiento actualizado únicamente para cerrar el punto 1 y enlazado con el inventario e Inicio; puntos 2–5 pendientes.

**Límite de esta verificación:** auditoría estática de consumidores y definiciones de servidor, más comprobación documental y huellas. No se ejecutaron suite de integración, pruebas visuales de todas las combinaciones, semillas ni mutaciones productivas. No se implementó corrección ni se hizo commit, push, sincronización remota o deploy. Las cifras de la auditoría anterior mantienen su fecha y no se publican como recuento actualizado por este inventario.
