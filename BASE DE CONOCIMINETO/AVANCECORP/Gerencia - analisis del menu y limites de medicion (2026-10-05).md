---
fecha: 2026-10-05
estado: publicado y verificado; Main sincronizado
tags: [crm, gerencia, navegacion, analisis]
---

# Gerencia: análisis del menú y límites de medición

Miguel pidió analizar qué módulos consulta más Gerencia para precisar su menú lateral. Se revisaron código local, pruebas existentes y decisiones del vault. No se observaron sesiones humanas ni se midió tráfico productivo: la prioridad propuesta es una hipótesis de trabajo, no un ranking de uso real.

## Hechos comprobados

- Antes de la propuesta, el menú de Gerencia tenía **18 accesos**: Dirección (Resumen, Ranking, Rendimiento, Conversiones, Citas, Facturación, Empresas); Operación (Seguimiento, Gestión Diaria, Pipeline, Leads, Agenda, Cartera, Repartir leads, Base para gestión, Gestión de equipo); Administración (Metas, Configuración).
- Fuentes: `CRM-Avance-Corp/app/src/components/app/sidebar.tsx`, `sidebar.test.tsx`, `app/src/lib/vistas.ts` y `router.ts`. CodeGraph se consultó primero; se completaron los fragmentos que su salida no mostraba.
- La instrumentación revisada no ofrece un historial central de visitas por usuario/rol/módulo. `app/src/lib/sentry.ts:48` configura solo errores, tracing a cero, elimina usuario y descarta migas UI. La búsqueda complementaria en frontend y migraciones no localizó instrumentación de pageviews. Esto no certifica ausencia de cualquier fuente externa; no se consultaron logs productivos.
- `visita-sin-movimiento.ts` conserva una foto local de los leads vistos por el supervisor; no es analítica de navegación de Gerencia.
- `app/src/screens/hoy/gerencia.tsx:739` muestra que Metas contiene consulta de cumplimiento (capital confirmado e índice mensual) además de edición. Mover todo Metas a Configuración escondería una consulta gerencial.
- Seguimiento y Gestión Diaria siguen presentes en el menú local. La decisión de absorber Seguimiento existe, pero su retirada exige acreditar la observación y el cierre de F6; el calendario transcurrido por sí solo no acredita esos requisitos.

## Organización aprobada por Miguel

Siete accesos directos, en este orden:

1. **Resumen:** situación global y asuntos que requieren decisión.
2. **Facturación:** capital comercial por día, equipo, analista y tipo de operación.
3. **Ranking:** comparación de resultados entre analistas.
4. **Citas:** avance de citas, entrevistas y resultados comerciales.
5. **Gestión Diaria:** actividad, pendientes y desempeño operativo de los equipos.
6. **Metas y cumplimiento:** consulta del avance frente al objetivo; distinguirla de configurar objetivos.
7. **Cartera:** consulta de inversionistas, contratos y vencimientos.

Los otros once accesos se conservan en grupos desplegables:

- **Análisis:** Rendimiento, Conversiones y Empresas.
- **Operación:** Leads, Pipeline, Agenda, Repartir leads, Base para gestión y Seguimiento mientras siga vigente.
- **Administración:** Gestión de equipo y Configuración.

Es una propuesta de organización visual. No concede ni revoca permisos, no fusiona cálculos y no declara redundantes los módulos agrupados. Ranking compara resultados; Rendimiento analiza distribución/capacidad; Gestión Diaria supervisa la ejecución; Gestión de equipo administra personas.

## Cómo confirmar qué se usa más

Si se decide instrumentar, medir 30 días incluyendo el cierre mensual: entradas deliberadas por módulo, usuarios de Gerencia distintos, días de consulta y tiempo activo. Distinguir la apertura automática de Resumen; excluir cuentas demo, pruebas, precargas y recargas automáticas de datos. Medir solo identificador seudónimo, rol, módulo y tiempo, sin nombres de clientes ni búsquedas. No inferir preferencias a partir de volumen de consultas SQL o errores.

La frecuencia debe complementarse con la importancia de la tarea: una pantalla de cierre mensual o una aprobación excepcional puede ser esencial aunque se abra pocas veces. La instrumentación no se implementó en este análisis.

## Verificación del análisis inicial

- **PASS:** `npm run test:run -- src/components/app/sidebar.test.tsx src/lib/vistas.test.ts` — 2 archivos, 31 pruebas.
- **NOT RUN:** build, E2E y navegación productiva; no hubo cambios de código ni auditoría visual.
- No se modificaron pantallas, permisos, datos ni producción. Solo se guardó esta nota. La pregunta sobre la prioridad observada por Miguel quedó sin respuesta al preparar la propuesta; no se presupone confirmación.

Relacionadas: [[Plan de mejora UX de Gerencia - revision 2026-09-05]], [[Facturacion - modulo del dueno en produccion (2026-09-13)]], [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]], [[Gestion Diaria - UX gerencial publicada y verificada (2026-09-25)]], [[Telemetria del CRM tiene dos extremos]], [[Inicio]].

## Vista previa dentro del CRM solicitada después (antes de aprobar)

Miguel pidió ver la propuesta dentro de la aplicación completa, no como menú aislado. Se preparó una copia local del código guardado en `CRM-Avance-Corp/output/crm-menu-local/base/CRM-Avance-Corp/app`, con la propuesta en su `sidebar.tsx`; en ese momento el componente del proyecto principal permanecía intacto. Vista en `http://127.0.0.1:5177/#/hoy`, abierta en Chrome con **Gerencia demo** y datos de ejemplo. No es producción ni una implementación aprobada para publicar.

La copia evita interferir con un cambio local en curso que importa el módulo ausente `@/lib/use-etapa-visible` desde `leads-recibidos-hoy.tsx`. Ese árbol de trabajo falló su comprobación de tipos; no se corrigió como parte de esta propuesta.

Verificación de la copia: TypeScript, lint del componente y build **PASS**; recorrido específico E2E en Docker **1 passed / 0 failed**, cubriendo Resumen, apertura por teclado de Análisis, Conversiones, Pipeline, Administración y regreso. Navegación visible comprobada también en Chrome. Suite integral **NOT RUN**: es una vista previa aislada, no un release. Para arrancar de nuevo: `node output/crm-menu-local/servidor.mjs` desde la raíz del CRM. El servidor permanece local y no se publicaron cambios.


## Implementación aprobada

Después de ver la aplicación completa en local, Miguel respondió **«me encanta, hagamos eso»**. Se aplicó la organización aprobada en `app/src/components/app/sidebar.tsx` del proyecto principal. Se conserva el filtro `vistaPermitida`; el cambio es de navegación, no de permisos ni de datos. Los otros roles conservan sus accesos históricos.

Los grupos se abren con clic, teclado o toque. Una ruta directa, una subruta de Configuración o el regreso por historial revela el destino dentro de su grupo. En tablet el riel permite abrir un grupo y se repliega al elegir una pantalla, cancelando los temporizadores de hover. El orden de accesos refleja una decisión de producto aprobada; **no acredita frecuencia de uso medida**.

Validación de esta implementación:

- **PASS:** 40 pruebas de Sidebar y autorización de vistas en el árbol principal (22 del menú + 18 de vistas), además de lint sin errores nuevos y `git diff --check`.
- **PASS:** `npm run check` en copia aislada del commit `92c4554a` con el mismo Sidebar y sus cambios de pruebas: lint (avisos preexistentes), TypeScript, 4.909 pruebas unitarias, cobertura, configuración de release, service worker, build, bundle y duplicación.
- **FAIL ajeno al menú:** el typecheck del árbol principal conserva cinco errores del trabajo en curso en `leads-recibidos-hoy.tsx` y su prueba (importación ausente `use-etapa-visible`, campos `gestion_vigente` y `carteraPaginas`). No se corrigieron ni se descartaron esos cambios como parte de esta tarea.
- **PASS:** revisión independiente mediante `scripts/claude-review`. Se preservó la preferencia de riel al abrir grupos y se reforzaron las pruebas de navegación. No se cambiaron permisos.
- **E2E integral Docker, primera corrida:** 283 passed / 4 failed / 26 skipped. Los cuatro fallos eran selectores antiguos que buscaban Equipo sin desplegar Administración; se actualizaron al recorrido visible.
- **E2E Docker, verificación final de cuatro specs:** 23 passed / 1 failed. Pasan menú de Gerencia (teclado, historial y tablet), demo de los cuatro roles, accesos y reparto. El único fallo restante es `gerencia-operativa.spec.ts`, caso «comparativa y chips»: espera «Aún no hay supervisores activos», pero la pantalla informa error al cargar métricas. **Reproducido sin cambios en una copia exacta de HEAD `92c4554a`: 1 failed en la misma aserción.** Se registra como fallo previo, no como regresión del menú; no se altera la lógica de métricas como parte de esta tarea.
- **NOT RUN en el árbol principal:** build y E2E completos, bloqueados por la dependencia ausente de Hoy. Los resultados de la copia no acreditan el conjunto de cambios locales ajenos a esta tarea.

La vista local de `http://127.0.0.1:5177/#/hoy` usa una copia de la base confirmada con el **mismo componente final** y datos demo. **No se publicó a producción.**


Evidencia local: `CRM-Avance-Corp/output/crm-menu-local/verificacion/` conserva logs, review, evaluación del PRIMARY, parche aislado de los 18 archivos de esta tarea y SHA-256 del código verificado. Capturas finales: `menu-gerencia-desktop.png` y `menu-gerencia-tablet.png`. El Sidebar de la copia se comprobó idéntico al componente aplicado al proyecto principal. No se hizo commit, push ni despliegue.

## Publicación solicitada y preparada · 05/10/2026, 15:20 Lima

Miguel pidió **«publica»**. **TODAVÍA NO PUBLICADO.** Paquete limpio `crm-20261005T202010Z-38ad8fcb8b19`, commit `38ad8fcb8b19`, ZIP SHA-256 `8508eb5a196e78c888924c7063b0f979af86939d6321a519490ed9b58d3498d7`. Manifiesto y ZIP conservados en `CRM-Avance-Corp/releases/`.

- Vivo identificado: `5002b2972594`, build `build-20261005T172100476Z`; árbol idéntico al remoto `618cf7ce`, pero ascendencia diferente por squash. El candidato desde remoto fue rechazado por preflight. Se siguió el rescate desde el vivo en copia limpia; además integra Main local `92c4554a` y remoto sin perder sus historiales. PR [#194](https://github.com/avanza-digital/avancecorp-crm/pull/194).
- `npm run check` PASS: 378 archivos, 6.109 tests. Revisión de integración por Claude, wrapper read-only: PASS. Preflights offline de scripts, seed, RLS y Edge: PASS. Artefacto verificado y preflight del ZIP final PASS contra el vivo.
- E2E Docker completa: **337 passed / 2 failed / 26 skipped**. Ambos fallos venían de fechas en fixtures: métricas fijas en septiembre y reloj de servidor distinto del navegador en vuelta diaria. Corregidos en `38ad8fcb`; repetición Equipo+Gerencia **13/13 PASS**, vuelta+clientes **2/2 PASS**. Ningún cambio adicional de producto. El código de aplicación y dependencias son idénticos al check de 6.109 pruebas.
- Main local compartido conserva sus archivos pendientes y sigue en `92c4554a`. Hay respaldo tar, snapshot `refs/backups/menu-gerencia-trabajo-local-20261005` y reaplicación ensayada en `/tmp/avancecorp-menu-preservacion-20261005`. Los cambios de aplicación locales ya están contenidos en el código integrado; se preservan las actualizaciones documentales/configuración pendientes. **No aplicar el stash completo a ciegas.**
- GitHub Actions tiene una [incidencia de asignación de runners](https://www.githubstatus.com/incidents/3q1yb5m7ltvb) y los checks de la PR están en cola. No se modificó ninguna regla de protección, ni se declaró un check remoto como aprobado con la evidencia local. Se preguntó a Miguel si espera o autoriza publicar desde rescate dejando la integración de Main para cuando GitHub se recupere; respuesta pendiente al escribir esta nota.
- Conector Hostinger por cliente MCP oficial: handshake y esquema `hosting_deploy-static-website` verificados; **no se invocó deploy**. No se aplicó SQL, no se publicaron Edge ni portal.

Retoma: `CRM-Avance-Corp/output/crm-menu-local/verificacion/release-estado.json` (paquete, logs, copias y límites). Si se autoriza rescate con Main diferido, reconfirmar vivo/preflight antes de subir y verificar HTTP/hash con `verificar-publicado.py`. Si se espera a GitHub: checks reales → fusión preservando padres de la PR → Main local/remoto iguales, reaplicación selectiva del WIP → artefacto desde commit limpio integrado → preflight → Hostinger → HTTP y acceso. Después registrar lo efectivamente publicado aquí y en [[Deploy a Hostinger]].

**Decisión de Miguel (05/10, tras preparar el paquete): «Esperar a GitHub (recomendado)».** La publicación continúa cuando los checks alojados permitan cerrar la integración; no se autorizó diferir Main después del deploy.

- 15:26 Lima: `npm run check` completo repetido sobre el commit final limpio `38ad8fcb8b19871186baf6a1426f6578c36a2095`: PASS; 378 archivos / 6109 tests, lint, typecheck, release-config, push-tasa, build, bundle y duplicación. Evidencia: `output/crm-menu-local/verificacion/release-check-final.log`. GitHub continúa pendiente.

- Espera posterior a la decisión de Miguel: `preflight` de GitHub PASS (run `37369048621`, 1m29s). `CRM app quality` run `37369048668` continúa en cola, job `cambios` `111964205210`. La ejecución anterior `37367735859` del commit superado `081dfdf` quedó cancelada (cancelación normal seguida de `--force` porque su job `always()` retenía la concurrencia). Esto liberó la ejecución vigente; no se cancelaron ni suplantaron controles del commit final.
- Se verificó que la cuenta tiene membresía OrganizationAdmin activa; el ruleset `proteccion-main` ya permite a ese actor excepción mediante PR, necesaria para conservar ancestría con merge. El ruleset de `preflight` no tiene excepciones y ya está aprobado. Esperar también `verify` antes de fusionar. No se modificaron reglas ni workflows.
- Estado de reanudación: `output/crm-menu-local/verificacion/release-estado.json` y `github-estado-espera.json`. `git apply --check` del WIP reconciliado contra el commit final PASS. Los archivos originales siguen preservados; solo esta nota cambió desde el respaldo. Main local, Main remoto y producción permanecen sin modificar por esta publicación.

## PUBLICADO · 05/10/2026, 16:44 Lima

El menú aprobado de Gerencia quedó publicado en https://crm.miavance.com/.

- PR #194 integrada por squash (`7da57c97`), con `app-check`, `verify` y `preflight` PASS. Como el squash perdía la ascendencia del build vivo, se integró la misma rama de rescate mediante **merge commit** en la PR #196 (solo acta en el diff; `verify` y `preflight` PASS). No se modificaron reglas ni workflows.
- Main local y `avancecorp/main` sincronizados en `8fca20bf1215240fdfd2722e9a9b77f234c1b8ea`; conserva el Main local anterior, el Main remoto y el vivo `5002b297`. El código, tests y dependencias son idénticos al `38ad8fcb` verificado; solo se añadió el acta de integración.
- Fuente limpia; artefacto `crm-20261005T214347Z-8fca20bf1215.zip`, 2456820 bytes; SHA-256 `70a71b02d7f5e39e9d9621987c6a051414262dbfdf33f0510157eaa5bbd330ce`. Manifiesto hermano en `CRM-Avance-Corp/releases/`.
- Build vivo comprobado: `build-20261005T214345995Z`. Preflight obligatorio PASS antes de subir; Hostinger confirmó `success` con una sola invocación. No se ejecutó SQL ni Edge Functions, ni se publicó el portal.
- Smoke **PASS**: portada, versión, 95 archivos de entrada/JS/CSS (HTTP 200 + tamaño + SHA-256), acceso autenticado a Hoy como Analista y consola sin errores. El ZIP no queda público (404 en CRM y portal).
- Comparación binaria ampliada: 119/131 archivos públicos exactos. Los 12 restantes son PNG servidos por `hcdn`; siete tienen píxeles idénticos (recompresión), cinco logos pasan de 3508×3253 a 1600×1484. Los doce PNG originales son idénticos a los del release anterior; no se cambió la configuración CDN ni se reintentó el deploy. Se conserva la evidencia del FAIL binario ampliado junto con su diagnóstico.
- Gerencia en sesión productiva: **NOT RUN**, pues la sesión disponible es de Analista. Menú de Gerencia probado en Docker (escritorio, teclado, historial y tablet) y bundle publicado idéntico al verificado. E2E completa previa: 337 passed / 2 failed / 26 skipped; fixtures corregidos y repetición 13/13 + 2/2 PASS. `npm run check` completo en commit final: 6109 PASS.
- WIP local preservado y reconciliado, incluyendo los cuatro archivos de reexpresión de agosto que cambiaron durante la espera. Código de aplicación local coincide con Main. Respaldo íntegro: `refs/backups/menu-gerencia-antes-sync-final-20261005` (`25024584ec6393d20ffe147477aa17abcb9cb84b`) y `output/crm-menu-local/verificacion/trabajo-local-antes-sync-final.tar.gz`; respaldo inicial también conservado. No se hizo pop del WIP viejo sobre el código nuevo.
- Evidencia final: `output/crm-menu-local/verificacion/verificacion-publicacion-final.json`, `smoke-publicado-main.json`, `smoke-imagenes-pixeles.json`, `hostinger-deploy-main.log`, `preflight-main-final.log` y `sincronizacion-main-final.log`.
- Rollback conservado: `crm-20261005T172101Z-5002b2972594.zip` y manifiesto. Ningún rollback ejecutado.

Relacionado: [[Inicio]] · [[Base para gestion del analista - F0 y decisiones (2026-10-01)]].
