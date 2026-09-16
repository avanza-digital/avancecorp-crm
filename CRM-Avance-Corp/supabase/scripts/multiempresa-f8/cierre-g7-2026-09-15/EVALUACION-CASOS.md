# Evaluación PRIMARY del segundo review G7

Claude actuó como SECONDARY_REVIEWER mediante `scripts/claude-review`, sin
herramientas ni modificaciones. Su [dictamen original](REVISION-CASOS-CLAUDE.md)
es **CHANGES_REQUESTED** y se conserva sin convertirlo en un PASS. Codex corrigió
los ejecutores y comprobó sus resultados. Esta es la segunda consulta de la
tarea; no se pidió otra para confirmar las correcciones.

## Hallazgos y resolución

| Hallazgo | Decisión y evidencia final |
|---|---|
| P1: reanudación con privilegios de servicio sin negativos | Corregido. En cada uno de los cuatro cortes: anónimo 401, analista ajeno 403 y cliente 403; contadores y estado invariables. Token de otra solicitud y token inventado rechazan 409 mientras la saga está pendiente. Una saga ya enlazada permite al supervisor autorizado leer el resultado idempotente con 200; no ejecuta efectos nuevos. `casos-http.mjs` verifica esa distinción |
| P1: inventario sin procedencia ni enlace al recibo | Corregido. `capturar-versiones.sql` se ejecutó en producción en transacción READ ONLY, corte 15/09 23:56:17 UTC. `captura-versiones.json` conserva proyecto, corte, modo y catálogo; `cotejo-casos.json` enlaza consulta, captura e inventario con SHA-256. El verificador comprueba también la fecha posterior a los ensayos |
| P2: PASS anterior sobrevivía a un fallo | Corregido. El cotejo escribe RUNNING antes de leer o consultar y FAIL ante error. Dos pruebas deliberadas —captura alterada y Docker ausente— sustituyen un PASS anterior. El test descubrió además que una ruta temporal con symlink saltaba el modo CLI; se corrigió su normalización |
| P2: DDL local sin cotejo | Corregido. Comparación exacta de nombres, tipos, nulabilidad, defaults y restricciones de las tres tablas modificadas. Se encontraron y alinearon solo en la copia el CHECK de sujeto de solicitud y el default PDF v9. Coinciden además 203 funciones y tres auxiliares, con propietario/ACL. No equivale a paridad de todos los triggers, políticas o tablas |
| P2: recibos desligados del ejecutor | Corregido. HTTP, finanzas, roles y cotejo guardan hashes de sus ejecutores y dependencias; el verificador exige los nombres esperados y sus hashes exactos. `roles-general-local.mjs` vincula el resultado al SQL ejecutado |
| P2: monedas y constantes presentadas como mediciones | Corregido. Fichas comparadas por fuente y por totales de empresa/moneda, con PEN y USD en Avance. El número de ajustes se lee después del reintento y se exige una única inversión. Los booleanos de los recibos resumen aserciones realizadas; no son observaciones humanas ni conciliación externa |
| P2: identidad validada por texto ambiguo | Corregido. Se exige SQLSTATE P0409 y el mensaje específico del documento no verificado, sin guardar solicitud |
| P2: segundo analista podía ser NULL | Corregido. Selecciones STRICT y comprobación explícita de dos analistas distintos antes de reasignar |
| P2: huella de reversión insuficiente | Corregido. Doce tablas comprobadas, incluyendo banderas, perfiles, inversiones, solicitudes, ajustes y objetos Storage. Operaciones SQL dentro de una única transacción terminada en ROLLBACK |
| P2: Directorio comprobado solo en la primera fila | Corregido. Se recorren todas las páginas y todas sus fichas; se comprueban empresas de las filas, totales, inversiones y ausencia de escritura. Se permiten perfiles del Portal sin contratos, conforme al núcleo vigente; no se exige erróneamente que cada perfil tenga inversión Avance |
| P2: herencia completa de configuración Auth | Corregido. Lista explícita de variables DB/API/JWT, sin SMTP, proveedores externos ni hooks; autoconfirmación activa y alta pública deshabilitada. Se conservan los algoritmos JWT configurados del banco para aceptar las claves locales de servicio |
| P2: clave inicial basada en documento | Observación de política preexistente, no cambio de esta tarea. El ensayo confirma `debe_cambiar_password=true` y acceso únicamente al contrato propio. No prueba imposición del cambio de contraseña en el navegador ni restricción de API hasta su cambio; eso no se declara demostrado |
| P3: orden inestable al comparar Capital | Corregido. Orden sobre la representación ya despojada de estado/anulado, que son los campos que debe cambiar una anulación |
| P3: limpieza y logs | Corregido. El cierre de contenedores se ejecuta aunque falle restaurar banderas; redacción de JWT, claves locales y conexiones en logs |

## Límites conservados

La configuración por base de `authenticator`, propietarios Auth/Storage,
teléfonos sintéticos faltantes, datos y archivos del ensayo permanecen en la
copia. Los contenedores HTTP propios se eliminan. La red Docker se comparte con
el banco local de origen: la separación se garantiza por destino fijo y
configuración, no por una red físicamente independiente.

El número de contextos de la matriz es descriptivo del estado acumulado del
banco, incluyendo corridas intermedias. No se cuenta como igual número de casos
de negocio independientes ni de usuarios reales. Se preservan seis casos
especiales, cuatro lecturas fuera de ámbito y dos contextos Directorio.

La comparación de fichas con el núcleo prueba consistencia interna. Los cortes
613/467 y 614/468 son fotografías distintas; no se impone monotonía artificial
porque la actividad del negocio puede cambiar entre cortes. Las fichas reales
siguen ligadas a su muestra original.

NOT RUN en este suplemento: reanudaciones HTTP simultáneas del mismo token,
negativos de lectura/sobrescritura Storage, confirmación HTTP con revisión
obsoleta, cambio obligatorio de contraseña por navegador, entrypoint Deno y UI
productiva. Las cinco carreras SQL previas siguen siendo evidencia de sus casos
concretos; no se extrapolan a esos casos HTTP. No se modifica el producto ni se
certifica todo el alcance de RLS.

## Verificación

PASS: 15 grupos HTTP, tres financieros, matriz sobre los 56 contextos presentes
(44 fichas y dos páginas por cada contexto Directorio), cotejo de catálogo y
`verificar-evidencia.mjs`. PASS: dos casos de `integridad-recibos.test.mjs`,
sintaxis de ocho scripts, parseo de 18 JSON, 45 enlaces documentales,
`npm run check:scripts` y `git diff --check`. No quedan contenedores HTTP propios.
La firma G7, soporte y el SQL exacto de apertura/reversa productiva permanecen
pendientes. Ninguna de estas pruebas autoriza abrir las banderas generales.
