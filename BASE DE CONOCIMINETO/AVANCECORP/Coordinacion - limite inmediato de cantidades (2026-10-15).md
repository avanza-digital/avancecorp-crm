# Coordinación — límite inmediato de cantidades

Miguel pidió impedir escribir cantidades que excedan los pendientes disponibles: si hay 90 y ya preparó 60, el resto de destinos comparte los 30 restantes.

La planilla descuenta lo preparado para otros supervisores del mismo origen y limita la celda editada al saldo. El aviso explica el ajuste; no cambia las otras celdas. Reducir o vaciar libera cupo. Landing, Formulario y Formulario 3 mantienen disponibilidades independientes, respetando las fechas de ingreso seleccionadas. Se muestra también el saldo sin preparar por origen.

El borrador no reserva leads en el servidor. Si otra persona reparte y se actualiza la cola, se conservan las cantidades para corregirlas y se bloquea la revisión mientras excedan el nuevo saldo. Permanecen la relectura previa, la confirmación explícita y las validaciones atómicas de la RPC.

Estado: corrección preparada y verificada, pendiente de integrar/publicar. La versión publicada de la planilla sigue siendo PR #296, commit 875054a2; la corrección no está todavía en producción. No se modifican asignaciones, n8n, SQL ni permisos.

Validación: gate integral PASS (6.952 tests, lint, TypeScript, cobertura, build y bundle); después se agregó una regresión de reducción externa de disponibilidad y pasaron 24/24 pruebas focalizadas. Docker E2E: 5/5, incluyendo escritura y flechas con 90 pendientes entre tres supervisores y dos orígenes. Suite E2E completa del CRM NOT RUN; alcance de planilla ejecutado. Se reutilizó el gate de realidad de solo lectura del mismo día (22:09 UTC, 0 errores; divergencias preexistentes ajenas al reparto).

Claude: PASS. Se incorporaron las recomendaciones de cobertura para disponibilidad reducida externamente, filtros de supervisor y saldo por origen. Se mantiene el cero explícito al no quedar cupo, y la interpretación de borradores locales válidos; no se amplía el cambio a entradas numéricas parciales propias del navegador, que no permiten sobre-reparto. El reviewer Codex recomendó el límite calculado desde el borrador vigente; aplicado dentro de la actualización funcional.

Figma actualizado y verificado visualmente: [Planilla](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=52-34). Evidencia técnica en `CRM-Avance-Corp/docs/plans/planilla-reparto/LIMITE-CANTIDADES.md`.

Relacionados: [[Coordinacion - planilla de reparto y equilibrio por fechas (2026-10-15)]], [[Reparto de Leads]].

## PR299 fusionada; paquete preparado, dependencia pendiente

Comprobación 15/10/2026 23:48–23:51 UTC: PR299 fusionada en `81480ebb475fc61b4a19f5b2cb17f30da88df815`; Main local y remoto iguales al construir. La PR298 ya estaba fusionada (`05c19efc`, 23:34 UTC) y viene incluida. El código de la planilla es idéntico al revisado; los cambios de PR298 requieren backend previo.

Main combinado: `npm run check` PASS, 433 archivos / 6.966 tests; E2E Docker de planilla, reparto, Coordinación-reportes y cartera/categoría 44/44 PASS. Artefacto verificado y preflight de ascendencia PASS: `crm-20261015T234847Z-81480ebb475f.zip`, SHA-256 `b59f6a93a29ebc245dd967dc2de2395e53920de58b8095ecfb3be2f0904ca2fe`. Esto NO acredita compatibilidad de backend ni publicación.

Consulta productiva READ ONLY: ninguna de las migraciones `20261015211217`, `20261015212939`, `20261015224848` está en el ledger; tampoco existen `crm.correcciones_categoria_contrato`, `private.es_coordinacion_consulta()` ni `private.operaciones_cartera_clasificadas()`. Las actas de PR298 las declaran pendientes, junto con matriz HTTP/Auth y gate de realidad. Reviewer Codex confirmó dependencia real sin feature flag.

**NO publicado.** Sigue vivo `build-20261015T225912394Z` / `875054a2`. No se tocó Hostinger ni se ejecutó SQL de escritura. Se conserva el paquete anterior y el candidato. Hace falta completar el ciclo backend autorizado de PR298 antes de desplegar Main; no publicar una rama alternativa ni omitir los cambios fusionados. Miguel indicó que no veía PR298; se le pasó enlace y se explicó que está entre fusionadas. Figma actualizado con este estado.

Relacionado: [[Coordinacion - cartera, leads y correccion de categoria (2026-10-15)]].

## Backend comprobado; una sola sesión publica

Miguel autorizó completar las validaciones, aplicar las tres migraciones y publicar. Se detectó otra sesión PRIMARY ejecutando precisamente PR298; Miguel confirmó que seguía trabajando. Esa sesión conserva la promoción y la publicación. Esta sesión comprueba el resultado mediante consultas de solo lectura y no repite migraciones ni despliegues.

El 15/10 a las 19:10 Lima se verificaron las tres versiones originales en el ledger productivo. Las 1.072 funciones de `crm` y `private` coinciden entre rama validada y producción en definición, firma, propietario y ACL. La nueva tabla de auditoría tiene RLS, sin privilegios de tabla para `anon`/`authenticated`, y sus dos triggers de auditoría/inmutabilidad están habilitados. Las policies de consulta están consolidadas. Advisors: el aviso informativo de auditoría sin policies corresponde al acceso exclusivo por RPC; sin avisos de rendimiento relativos a los objetos nuevos.

La evidencia de la sesión propietaria acredita 93 comprobaciones SQL y 61 puntos de control con Auth/PostgREST reales y SQL auxiliar, solo datos sintéticos. Incluye seis transiciones de categoría, roles permitidos/denegados, baja sin renovar JWT, mes sellado e idempotencia. El reviewer de esta sesión cotejó scripts, logs y huellas; esta matriz focalizada no se presenta como la matriz RLS general.

`gate:realidad` productivo a las 19:10 Lima: exit 0 y cero errores; las mismas dos divergencias preexistentes (45 ventas de analistas de baja y 273 clientes sin domicilio legal). Los cinco caminos de conversión coinciden: 6,16 %. No se modificaron datos para verificar.

Main avanzó a `2ed57674` por PR300 (n8n). La aplicación frontend y sus manifests de dependencias son idénticos a `81480ebb`: se reutilizan los 6.966 tests y los 44 E2E focalizados. Se preparó y verificó otro candidato desde Main limpio: `crm-20261015T235722Z-2ed57674b37e.zip`, SHA-256 `33517502c56bc4ebd2529ba232529f46cebfe26eefe7b7e2a93915f302f9d832`. Este paquete preparado todavía NO acredita publicación; el artefacto publicado se registrará tras comprobar los archivos servidos.

Figma actualizado en el mismo tablero `JB4jRdmLXZXS0hBhEHxRbV`, sección `52:34`, con backend aplicado y publicación de pantalla en curso.

## Visibilidad del avance en Figma

Miguel indicó que no veía los cambios: la actualización reciente estaba en el pie pequeño de la planilla. Se añadió el resumen grande «Qué está listo y qué falta» encima del plan principal, sección `75:126`, y se actualizaron 18 textos del plan `2:34`. Se distinguen integración activa, origen nativo, planilla publicada y tope de cantidades todavía pendiente. Los avisos antiguos de programación apagada en fases 4/5 se contextualizaron como hitos previos a la activación de fase 6. Se agregó un enlace desde el plan hacia la planilla `52:34`. Capturas de ambas secciones verificadas visualmente, sin recortes ni superposiciones.

Entrada directa al estado actual: https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=75-126. No se cambió la interfaz del CRM ni se marcó como publicada la mejora pendiente.
