# Errores del CRM y bucle de consultas — 19/10/2026

Diagnóstico de solo lectura solicitado por Miguel, con énfasis posterior en «revisa los loops» y revisión de solución con Claude. No se modificó código del producto, permisos, datos ni configuración del servidor. Las pruebas se ejecutaron en una copia temporal con respuestas simuladas.

## Resultado principal

**Hay un bucle reproducible en la ficha del lead al consultar solicitudes de tasa.** Una sesión de Coordinación acumuló **1.757 respuestas HTTP 403**, entre **12:08:30 y 12:33:43 de Lima**, con un máximo de **153 rechazos por minuto**. Representa **86,3 % de los 2.036 errores HTTP registrados con origen en la web del CRM** durante la ventana auditada.

El código responsable sigue presente en el release observado a las 23:29. La ausencia de nuevos rechazos después de las 12:33 no acredita que el defecto esté corregido.

## Alcance y fuentes

- Ventana de logs: **19/10/2026 00:00:00–23:29:35, America/Lima**; UTC `2026-10-19T05:00:00Z` a `2026-10-20T04:29:35Z`.
- Proyecto Supabase compartido con el portal: `dctqcbznekcyxhjujuci`. Para las cifras HTTP del CRM se filtró `request.headers.referer = https://crm.miavance.com/`.
- Se registraron 131.679 peticiones HTTP del CRM, incluidas 7.230 comprobaciones OPTIONS. No equivalen a operaciones comerciales ni personas únicas.
- Código consultado: `avancecorp/main`, commit `a980bb719bdefa8939f8ff4fe205395edc62c4d7`. Versión web observada: `build-20261020T035759531Z`, documentada como publicada a las 22:58 de Lima.
- Los archivos `condiciones-tasa-lead.tsx`, `tasa-politica.tsx` y `query-client.ts` no tienen diferencias entre el commit del mediodía `6479402d` y ese Main. Se confirmó también la identidad de `useSolicitudesTasa`, su clave y la condición de montaje en `lead-drawer.tsx`. [Comparación de la cadena completa](comparacion-cadena.json). Se evitó usar como referencia de producción el trabajo sin publicar del árbol compartido.
- Después de la revisión de Claude se compararon por SHA-256 portada y cinco JS relevantes servidos en producción, incluidos los componentes afectados, React, TanStack, las consultas y su configuración: **6/6 idénticos al ZIP y manifiesto de Main limpio**. [Verificación del release servido](verificacion-publicada.json).
- CodeGraph se consultó primero. Para símbolos nuevos que su índice no resolvía se complementó con `git grep` y `git show` del commit publicado.
- Logs HTTP, PostgreSQL, Auth, funciones, Realtime y pool de conexiones; catálogo de funciones, política de tasas, rol del actor y cron consultados sin escrituras. No se guardaron JWT, correos, nombres ni identificadores personales directos; los actores de los agregados están seudonimizados.

## P1 — Bucle de tasas en la ficha

La cadena observada y reproducida es:

1. Coordinación abre un lead asignado y no terminal. `lead-drawer.tsx:310` monta el panel de tasas sin comprobar capacidad de lectura de tasas; `puedeEditar` solo controla edición.
2. `condiciones-tasa-lead.tsx:77` consulta las solicitudes. El servidor deniega la operación con `42501 / HTTP 403` a este actor. El contexto de PostgreSQL identifica `private.solicitudes_tasa_impl`, línea 13, llamada desde `crm.solicitudes_tasa_lead_fn`.
3. La política de tasas vigente es `observacion` (versión 18, vigente desde el 23/09). En ese modo, un error de lectura permite montar `CondicionesEditables` (`condiciones-tasa-lead.tsx:75–87`).
4. Ese hijo monta `TasaPolitica`, que vuelve a observar **la misma consulta** (`condiciones-tasa-lead.tsx:147`, `tasa-politica.tsx:141`, clave en `crm-queries.ts:165–166`).
5. El reintento al montar vuelve a poner la consulta sin datos en pendiente. El padre muestra su estado de carga (`condiciones-tasa-lead.tsx:81`) y retira al hijo. Al fallar de nuevo vuelve a montarlo: se repite el ciclo sin intervención humana.

`retry: false` ya existe en `query-client.ts:29`, pero no desactiva el reintento al montar un observador con error. Son opciones diferentes según la [documentación de TanStack Query](https://tanstack.com/query/latest/docs/framework/react/reference/functions/useQuery).

Los logs de PostgreSQL contienen además 2.089 registros «No autorizado» de esa cadena. **No se suman a los 1.757 HTTP**: son fuentes diferentes y no se estableció una correspondencia individual entre todos sus registros.

El permiso del servidor cumplió su función. La solución debe corregir el cliente sin ampliar acceso a tasas para Coordinación.

**Decisión de negocio confirmada por Miguel:** ante la pregunta de si Coordinación debía poder consultar las condiciones y solicitudes de tasa sin modificarlas, respondió «no debe ver eso». Por tanto, ese apartado debe estar oculto para Coordinación y no debe montar componentes ni efectuar consultas de tasas para ese rol. Esta decisión confirma el alcance de la propuesta; todavía no se ha implementado la corrección.

## Reproducción y controles

Se extrajo el código exacto de Main mediante `git archive` en `/private/tmp/crm-loops-20261019/CRM-Avance-Corp/app`, sin `.env` ni credenciales. Se utilizaron React 19.2.7, TanStack Query 5.101.2 y Vitest 4.1.11, iguales al lockfile publicado.

Se conservaron los componentes y el hook `useSolicitudesTasa` reales. La API se sustituyó por un rechazo `42501` con 20 ms de demora; los demás hooks proporcionaron el modo de política. Esto verifica el ciclo de los observadores, no una sesión autenticada contra producción.

| Escenario | Resultado |
| --- | --- |
| Observación + permiso denegado + configuración actual | 12 llamadas en 299 ms; bucle reproducido |
| Mismo escenario con `retryOnMount: false` en el cliente **de prueba** | 1 llamada durante 500 ms |
| Enforcement + permiso denegado | 1 llamada durante 500 ms; el padre muestra el error |

**PASS: 3/3 pruebas diagnósticas.** Esto confirma el defecto y dos controles, no una corrección publicada. Los tests existentes de `condiciones-tasa-lead.test.tsx` sustituyen `useSolicitudesTasa` por un doble estático, por lo que no prueban esta interacción de montaje y reintento.

Evidencia: [salida de Vitest](reproduccion.log), [prueba conservada como texto](reproduccion.test.tsx.txt), [agregados](evidencia-agregada.json) y [comprobación de métodos HTTP](evidencia-complementaria.json). Para repetir la prueba se copia el archivo de texto como `src/loop-diagnostico.test.tsx` dentro de una copia aislada del mismo commit y se ejecuta `node_modules/.bin/vitest run src/loop-diagnostico.test.tsx --reporter=verbose`. Requiere las dependencias del lockfile.

## Otros errores del día

| Hallazgo | Evidencia y límite |
| --- | --- |
| Recorrido del lead: 123 HTTP 404, 12 actores | Último POST 404 a las 09:39:04; primer POST 200 a las 09:39:20. Los 200 anteriores eran OPTIONS. Cronología compatible con publicación de pantalla anterior a disponibilidad del backend. No se conservó el cuerpo de cada 404 para distinguir ausencia, firma o caché. |
| Conversión: 84 HTTP 500 en preparar identidad, 9 en confirmar inversión y otros 4 entre preparar/consultar solicitud | PostgreSQL muestra rechazos por requisitos de cita/entrevista y otros conflictos con SQLSTATE `P0409`. No se atribuyen todos los 500 a un bucle: preparar identidad se llama desde `onSubmit`, protegido por `enviando.current`. |
| 1 HTTP 500 de métricas y 2 timeouts en PostgreSQL | Un timeout identifica la cadena de conversión y métricas; el otro no trae contexto de función. No hay evidencia de agotamiento general de conexiones. |
| 14 HTTP 502 de `crm-tipo-cambio` | Distribuidos durante el día. La causa interna no quedó establecida en esta auditoría. |
| Dos tareas automáticas reciben HTTP 401 | `notificar-pagos` a las 09:00 y `ciclo-contratos` a las 09:10; ambas desde `pg_net`. Su ejecución SQL figura como exitosa, pero eso no acredita éxito de la llamada HTTP posterior. Causa de autenticación pendiente de verificar. |
| Auth y pool | 39 registros de credenciales inválidas y 1 fallo inesperado de Auth; 3 fallos de contraseña de `cli_login_postgres` en el pool. No se atribuyen al bucle de tasas. |

La familia `P0*` se traduce a HTTP 500; para una respuesta 409 explícita PostgREST utiliza `PT409`. La revisión de esos conflictos de negocio debe ser una corrección separada y compatible con los consumidores, según la [documentación de PostgREST](https://docs.postgrest.org/en/stable/references/errors.html). No se ha cambiado ninguna función SQL.

## Estado del servidor y tareas

Al consultar a las 23:29 de Lima: proyecto `ACTIVE_HEALTHY`, base de 398 MB, 26 conexiones sobre un máximo de 120, cero otras consultas activas y cero esperas por bloqueo. PostgreSQL lleva iniciado desde el 14/10. La web entregó `version.json` con HTTP 200.

Las 13 tareas activas de cron mostraron cadencias acordes con su programación y ninguna ejecución SQL fallida al corte cercano de las 23:31. Las tareas por minuto/cada cinco minutos son periódicas por diseño; no se observó un bucle descontrolado de cron. Los dos 401 anteriores impiden declarar éxito funcional de todas las tareas.

Esta es una fotografía actual, no una certificación de disponibilidad de todo el día. No se obtuvieron series históricas de CPU/RAM ni logs de acceso de Hostinger. El análisis confirma un bucle del cliente que carga el backend; no acredita que explique cada problema reportado por el equipo.

## Propuesta de solución

1. **Romper el ciclo de observadores:** estabilizar carga/error para que el hijo no se monte y desmonte al fallar la consulta que comparte con el padre. Preferir una única responsabilidad sobre la consulta; acotar `retryOnMount: false` a esta consulta como protección adicional. No cambiar globalmente la recuperación de todas las consultas del CRM.
2. **Cortar el origen:** condicionar montaje y consulta del panel a la capacidad de leer tasas. Conforme a la decisión explícita de Miguel, Coordinación no debe ver el apartado de condiciones y solicitudes de tasa ni efectuar esas consultas; debe conservar la consulta general de leads. Ocultar visualmente un componente que sigue montado no basta. Mantener la lectura autorizada de Directorio y el comportamiento del resto de roles; no usar simplemente «puede editar» o «ver todo» como permiso de lectura. Estas dos protecciones deben viajar en el mismo cambio focalizado.
3. **Controlar reintentos y recuperación:** un 403 debe quedar en estado estable, sin consulta periódica ni reintento por remontaje. Conservar un reintento explícito y recuperaciones justificadas por cambio de sesión/capacidad. Con autorización y respuesta correcta deben seguir actualizándose las decisiones de tasa y caducidades.
4. **Probar antes de publicar:** QueryClient real con 403/observación, 403/enforcement, error transitorio y recuperación, éxito con tasa pendiente, cambio de lead y apertura/cierre. Comprobar los cinco roles, panel plegado y que siguen operativos los bloqueos de conversión. Ejecutar el gate del proyecto y E2E focalizado **en Docker local**. No usar producción como banco.
5. **Verificar después del release autorizado:** comprobar versión y archivos publicados, refrescar la sesión afectada y observar tráfico durante varios minutos. Aceptación: cero consultas de tasas para quien no tiene capacidad, ausencia de ráfagas y funcionamiento normal de las decisiones de tasa para roles autorizados.

Separadamente: corregir el contrato HTTP de los rechazos de negocio, investigar los dos 401 de cron, revisar los 502 de tipo de cambio y exigir disponibilidad del backend antes de activar pantallas que consumen nuevas funciones.

## Verificación y revisión

- Lectura de producción y correlación de fuentes: **PASS**, con los límites indicados.
- Reproducción local y controles: **PASS, 3/3**.
- Corrección del producto: **NO IMPLEMENTADA**; el encargo es análisis y propuesta.
- Lint, typecheck, build y E2E del producto: **NOT RUN**, sin cambio de producto.
- Revisión independiente de Claude: **entregada**, `VERDICT: CHANGES_REQUESTED`, confianza alta en mecanismo y remedio; [dictamen completo](revision-claude.txt). Hubo dos intentos sin dictamen válido antes de la entrega final por el wrapper del repositorio; no se modificó su configuración ni se invocó una revisión directa fuera del wrapper.

### Evaluación del PRIMARY sobre Claude

- **Aceptados:** los dos P1 (ciclo de observadores y consulta sin capacidad); solución focalizada en frontend; protección local `retryOnMount`; probar roles legítimos, recuperación y error con un QueryClient real; separar los 401 de cron y el contrato HTTP de conversiones. No se amplían permisos.
- **P2 de evidencia atendido:** se compararon también el hook, su clave y el montaje de la ficha, todos idénticos entre el mediodía y Main. El lockfile del commit resuelve exactamente TanStack 5.101.2, React 19.2.7, Supabase 2.110.2 y Vitest 4.1.11. Se añadió cotejo HTTP de seis archivos al byte contra ZIP/manifiesto. Esto sustenta que el código responsable sigue servido; no afirma que hubiera otra sesión ejecutándolo durante el corte nocturno.
- **Ajuste al remedio:** `retryOnMount: false` es una defensa, no la solución completa. No se acepta recuperar un 403 mediante consultas automáticas periódicas indefinidas. El estado de permiso denegado debe permanecer estable hasta recuperación explícita o cambio válido de capacidad/sesión; los errores transitorios y las consultas autorizadas requieren comportamiento propio.
- **Precisión del incidente:** Claude describe «25 minutos continuos». Los logs acreditan una ventana de aproximadamente 25 minutos con ráfagas, no actividad uniforme en cada segundo; el informe conserva esa distinción. Tampoco se atribuye CPU medida al bucle: no hubo métricas históricas de CPU/RAM.
- **Complementos posteriores:** se verificó en documentación oficial el mapeo de la clase `P0*` a HTTP 500. Los tres errores del pool eran rechazos de contraseña de `cli_login_postgres`; no se confunden con saturación ni con el bucle. No se abrió otra revisión para repetir conclusiones ya comprobadas.
