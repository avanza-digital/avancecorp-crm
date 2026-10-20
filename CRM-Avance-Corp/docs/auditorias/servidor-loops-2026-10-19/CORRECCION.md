# Corrección del bucle de solicitudes de tasa — 20/10/2026

Miguel confirmó que Coordinación no debe ver condiciones ni solicitudes de tasa y autorizó aplicar la solución. Se parte de Main `a980bb719bdefa8939f8ff4fe205395edc62c4d7`, igual a `avancecorp/main`, en la copia limpia existente `/private/tmp/crm-citas-fecha-comercial-20261017`. No se creó un worktree ni se modificaron los trabajos ajenos de la carpeta original.

## Cambios

- Capacidad de interfaz `verSolicitudesTasa`: Analista, Supervisión, Gerencia y Directorio pueden leer; Coordinación e identidad ausente no. La ficha comprueba esa capacidad antes de montar el apartado, conservando sus condiciones de lead asignado/no terminal y el permiso de edición existente. Ocultarlo no deja consultas en segundo plano.
- Una denegación de permisos detiene las consultas automáticas de solicitudes (intervalo, foco, reconexión e invalidación). El reintento explícito sigue disponible. La caché se limpia al cambiar de sesión.
- `retryOnMount` se desactiva solo para consultas con `leadId`, donde padre e hijo comparten el mismo resultado. Las bandejas sin lead conservan su recuperación al remontarse.
- En observación, solo la primera lectura muestra la espera inicial; una recuperación posterior conserva el formulario y su borrador. Enforcement conserva su bloqueo ante errores y su botón de reintento.
- `CrmApiError.codigoOrigen` conserva el código del servidor sin cambiar `code`, mensaje ni identificador de correlación. Esto distingue el error de autenticación `PGRST301` del rechazo `42501`, aunque ambos se presenten como `SIN_PERMISO`: un token renovado puede recuperar la lectura automáticamente.

No hay migraciones, cambios de RLS, funciones, políticas financieras ni datos productivos. No se amplía el permiso del servidor. Los 401 de cron, 502 de tipo de cambio y rechazos de conversión del diagnóstico siguen siendo asuntos separados.

## Revisión de Claude y decisión del PRIMARY

[Revisión de implementación](revision-correccion-claude.txt): `CHANGES_REQUESTED`. Es la segunda consulta de la tarea, posterior al diagnóstico; no se pidió otro dictamen favorable tras corregir.

- P2-1 aceptado: preservar el código original distingue autenticación de autorización. Prueba real del hook y recorrido de navegador con HTTP 401/PGRST301, seguido de respuesta correcta, sin cerrar el formulario. La distinción 401/403 está documentada por [PostgREST](https://docs.postgrest.org/en/stable/references/errors.html).
- P2-2 aceptado: protección de remontaje limitada a `leadId`. Nueva prueba de recuperación al volver a una bandeja sin lead. Inventario: `solicitudes-tasa-gerencia` refresca periódicamente y tiene reintento; `tasas-autorizadas-analista`, cada 60 s; `resumen-gerencia-movil`, cada 45 s y reintento; `TasaPolitica`, cada 30/60 s. El padre del lead se recupera mediante su hijo o el reintento de enforcement.
- P3-1: la clave sí contiene el segmento literal `solicitudes` (`crmQueryKeys.solicitudesTasa`). Se refuerza la prueba con el control positivo: los cuatro roles autorizados registran exactamente una consulta compartida, y Coordinación ninguna.
- P3-2 aceptado: los conteos negativos del navegador esperan además que termine la actividad de red tras avanzar el reloj y reabrir la ficha.
- P3-3 ajustado: comentario fiel al refresco periódico opcional; no afirma que todos los consumidores refresquen únicamente cuando hay pendientes.

## Verificación

- `npm run check`: **PASS**; lint, tipos, **464 archivos / 7.479 pruebas**, cobertura, configuración de release, service worker, build, bundle y duplicación.
- Regresiones focalizadas: **105/105 PASS** (consultas reales, ficha y capacidades), incluidas 11 pruebas de consultas con doble observador, errores, borrador, recuperación, cambio de lead y sesión.
- E2E Docker local: **21/21 PASS**; cinco roles, cero consultas de Coordinación, 403 estable tras varios minutos y reapertura, 401 recuperable, solicitudes/aprobaciones, avisos y otras operaciones de Coordinación.
- `git diff --check`: **PASS**.
- Navegador con sesión personal en producción y VoiceOver: **NOT RUN**. Los recorridos anteriores usan API sintética local.

La primera ejecución de navegador reveló que la API normaliza `42501` a `SIN_PERMISO`; la protección se corrigió y se verifican ambos códigos. Una ejecución intermedia de la suite general falló en `pipeline-columnas-demo.test.tsx:130`, sin cambios en ese código; el archivo pasó 11/11 aislado y una repetición integral pasó 7.477/7.477 antes del ajuste final de autenticación. Se conserva esa limitación como antecedente, sin ocultar la ejecución fallida.

Control negativo: tres regresiones nuevas ejecutadas sobre Main sin la corrección fallaron, como se esperaba. No se usó producción como banco de pruebas.

`gate:realidad` completo: NOT RUN; la credencial administrativa local fue rechazada con HTTP 401. El estado relevante (Coordinación denegada y política de observación) se acreditó con las lecturas productivas del diagnóstico y se reproduce en los bancos. Context7 no estaba disponible; se consultó la [documentación oficial de TanStack Query](https://tanstack.com/query/latest/docs/framework/react/reference/functions/useQuery). No se actualizaron dependencias.

## Publicación

Corrección verificada y preparada para construir desde el commit limpio de Main. El acta posterior registrará el artefacto y la verificación productiva.

Recuperación conservada: `crm-20261020T035800Z-a980bb719bde.zip` y su manifiesto en el repositorio original. La publicación debe pasar el preflight que comprueba que el candidato contiene el commit vivo. No se declara solucionado en producción hasta comprobar versión y archivos servidos.
