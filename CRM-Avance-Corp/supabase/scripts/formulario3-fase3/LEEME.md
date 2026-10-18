# Formulario 3 — fase 3: integración real comprobada, sin publicar

Fecha local: 14/10/2026 (algunos registros UTC ya son del día 15). Codex PRIMARY; Miguel operó las pantallas. Ensayo en la rama autorizada `bxkborlvpmuwttzjrjqn`, retirada al terminar. No se importaron contactos ni se publicaron migraciones/Edge/frontend en producción. El flujo principal sigue inactivo.

## Evidencia del objetivo

| Comprobación | Resultado y evidencia |
|---|---|
| Instalación real | Dos migraciones y Edge real instalados en la rama. `antes.json`, `despues-instalar.json`; histórico y ACL preservados. |
| Contrato, permisos y filtro | **98 comprobaciones SQL PASS** con rollback: 36 contrato, 18 permisos, 1 regresión de ficha viva, 43 cartera/paginación. `sql-*.log`. |
| Auth y API | **49 casos PASS**: 3 fronteras, 33 permisos/compatibilidad y 13 reparto. Auth real para ocho roles; no sesiones simuladas. `http-frontera.json`, `http-permisos.json`, `http-reparto.json`. |
| Conversión y cliente reconocido | **6 casos adicionales PASS**. Importador HTTP → reconocimiento/reingreso → preparación de inversión → comprobante Storage → confirmación real y reintento. Legacy y Formulario 3 conservan una sola nota y una sola inversión. `conversion-real.json`. |
| Numerador y divisor | Ambas conversiones Qorilazo PEN 5.000 aportan **divisor 1 y numerador 1**, con origen FORMULARIO. `conversion-numerador.json`. No se afirma una nueva matriz exhaustiva de todos los productos financieros. |
| UI real | Cuatro roles comprobados en Chromium/Docker local: vendedor, supervisor, gerencia y directorio. Etiqueta, filtro, cifras, ficha, recarga y legacy. Primera corrida: 3 PASS / 1 timeout de espera del ensayo; Directorio repetido tras ampliar la espera: 1 PASS. Sin cambio de producto ni mocks HTTP. `ui-real.json`. |
| Google Sheets → n8n → Edge | Ejecución **36**: dos altas reales y recibos. **37 y 39**: repetir y mover filas genera cero llamadas al importador. **41**: duplicado y rechazo explícito. `ejecuciones-n8n.json`. |
| Fallo y recuperación | **43 y 45**: 401 controlado, fila pendiente sin recibo. **47**: recuperada. **49**: CRM confirma pero falla el guardado del recibo; **50**: reintento reconocido como duplicado y continúa la siguiente alta. Cinco leads únicos en la hoja de ensayo; siete recibos de resultados históricos. `conciliacion-final.json`. |
| Aviso automático | **44**, modo `error`, enviado por Gmail a Miguel desde una ejecución publicada del flujo aislado; ID `1a13cd4a1cb53998`. **46** suprimió el segundo aviso de la misma hora. Una entrada en la tabla de avisos. No fue un Manual Trigger del aviso. |
| Restauración y reproducción | Los **22 nodos, 26 conexiones y ajustes** del ensayo restaurado coinciden con `definicion({preparado:true})`. `n8n-comparacion.json`. |
| Regresión de producto | Las **44 huellas combinadas de fases 1 y 2 siguen idénticas**; se conserva el gate integral de fase 2 (6.700 tests y build) y sus 9 E2E Docker, sin presentarlos como una nueva ejecución. `huellas-producto.json`. |
| Pruebas n8n locales | **25/25 PASS**, parser, conciliación, recibos, rotación de lote y configuración; `n8n-unitarias.log`. |
| Advisors | Sin nuevas alertas respecto al proyecto padre. `advisors.json`. |

La ruta de solicitud de cliente sin ficha viva y la conservación de una sola nota/tarea se probaron mediante SQL real: `formulario3-fase1/contrato.sql`, bloque «Cliente sin ficha viva», repetido en esta rama con `sql-contrato.log` PASS. La regresión de una ficha cerrada frente a otra viva tiene prueba propia en `sql-reingreso.log`. La hoja actual no incluye DNI; no se inventó una columna para forzar ese reconocimiento.

El ensayo HTTP de conversión tuvo una primera ejecución parcial de Legacy: registró su reingreso y falló después en `preparar_inversion_fn` por faltar la referencia obligatoria del certificado. Se corrigió únicamente el fixture con `referencia: CERTIFICADO FICTICIO F3` y se repitió conservando ese lead. Por eso la primera respuesta Legacy de la evidencia final dice «ya anotado», mientras la primera de Formulario 3 dice «registrado»: no fueron dos altas desde cero en la misma corrida. Ambos terminaron con una nota y una inversión, y confirmación repetida idempotente. El archivo final reemplazó la evidencia parcial; no se afirma conservar su respuesta de alta. Se mejoró el script para registrar las altas en ensayos futuros; esa mejora de registro solo tiene comprobación de sintaxis, sin repetir el entorno ya retirado.

`conversion-numerador.sql` documenta una consulta equivalente para repetir la lectura sobre los mismos dos fixtures. Se reconstruyó al cerrar a partir de las fuentes y la respuesta conservada; no se presenta como transcripción exacta del comando ni como nueva ejecución tras retirar la rama.

## Estado de producción y corrección de credencial

La revisión del historial detectó una selección en pantalla de la credencial temporal `Ag61FRD4BJjGI4hZ` en el flujo principal. El cambio estaba en la versión autosalvada `6de7addb-5eb3-4267-b27f-ae9e7dd34637`; no fue una ejecución ni activación. Se restauró exclusivamente la credencial original `YNRHr2PjhfLXnKff`.

La primera versión restaurada `95f649de-8cdc-43af-ba89-5cd4a3d74840` tiene **cero diferencias de nodos/conexiones** respecto a `1dbc8d0d-7bed-465d-b33f-33c48f5cd953`, previa al ensayo. `active=false`, `activeVersionId=null`, `Importar en CRM.disabled=true`, `enviar_crm=false`. Los recibos productivos siguen en cero. Las alertas productivas conservan versión `82886ed4-7a9b-4371-bcef-221f031d38b1`. Evidencia: `n8n-estados.json`, `limpieza.json`.

También se comparó con la última versión nominal MCP anterior, `cbc1ce82-db6a-40c1-ba65-68de065c1f25`. Su autosave de UI de las 20:49 omitió parámetros por defecto y agregó objetos `options: {}` (21 nodos), sin cambiar credenciales ni conexiones. Se conserva el diff íntegro en `n8n-cierre.json`; no se afirma que esa comparación sea literalmente vacía. La definición del nodo confirma que el intervalo de minutos omitido vale 5 por defecto. La captura de ese momento mostró `95f649de` como última versión; el autosave posterior y su resolución se detallan a continuación. El MCP no devuelve `settings` históricos: los actuales son idénticos a la captura inmediatamente anterior a restaurar, pero no se atribuyen a una versión histórica que no los expone. Antes de fase 4 se volverán a comprobar versión, credencial, controles de envío y ajustes con las pestañas antiguas del editor cerradas o recargadas.

No afirmar que nunca hubo una modificación: hubo esa selección accidental y quedó corregida. La base productiva aún no tiene `campania_origen`; consulta final: cero leads sintéticos de este ensayo.

## Semántica y límites operativos

- La entrega es **al menos una vez**. Si el CRM guarda el alta y se pierde su recibo, el reintento queda como `duplicado`. No hay doble alta, pero contar recibos `importado` subestima las altas. Para contar contactos de origen Formulario 3, usar `crm.leads.campania_origen`; para conciliar un lote, cruzar la foto de filas/huellas con la evidencia del CRM. Ese campo no atribuye cada participación de un cliente antiguo.
- Una fila rechazada conserva su recibo. Corregir los datos cambia la huella y permite procesarla. Si cambia solo el parser, pausar envío/cron, exportar y revisar los recibos rechazados afectados, retirar únicamente esos recibos y reprocesar de forma supervisada. No vaciar toda la tabla.
- Los avisos se agrupan por hora de reloj. No es una ventana móvil ni un límite atómico: errores simultáneos o a ambos lados del cambio de hora pueden enviar más de un correo. Gmail o la caída completa de n8n requieren supervisión externa; no se prometió un canal alternativo.
- Los tres reintentos HTTP también se aplican a 4xx definitivos. Se conserva el comportamiento probado, sin rediseñar el importador.
- Los IDs del generador `formulario3.fase3.mjs`, incluido su modo `preparado`, son históricos y corresponden a recursos retirados. Reproduce la configuración auditada, no crea ni proporciona un entorno vivo. Repetir exige recursos nuevos y sustituir sus referencias.
- **NOT RUN en remoto:** fallo 5xx/timeout específico y respuesta `error_temporal` del Edge desde n8n; existe cobertura unitaria de conciliación, pero no se presenta como ejecución remota. Tampoco se repitió el fallo de recibo en modo trigger: fue manual; el Error Trigger automático sí quedó probado con el fallo HTTP.

## Gate de realidad y condición para fase 4

El gate original es **FAIL**, no PASS. Fallaron dos mediciones: lectura de sellos denegada a `service_role` y timeout de PostgREST. Se completaron mediante consultas de solo lectura: cero desviaciones respecto a sellos; cinco caminos de conversión coinciden en **6,3 % = 57,05 / 905**. Archivos `gate-realidad.json` y `gate-realidad-complemento.json`.

Las 45 ventas de analistas inactivos y 273 clientes sin domicilio son divergencias preexistentes, ajenas a esta campaña, que no se corrigieron. Antes de publicar, reparar o enmendar formalmente el verificador y resolver el criterio de sus advertencias. No ampliar permisos de negocio solo para poner verde el gate.

En fase 4 también hay que definir retención de ejecuciones fallidas (pueden guardar nombres/teléfonos), comprobar el aviso productivo mediante su trigger manual y seguir el procedimiento de release. Guardar entonces una versión nominal del aviso con el nombre actualizado: su texto «pendiente conectar Gmail» es anterior a la credencial Gmail ya conectada. Esta fase no autoriza publicar ni cargar la hoja real. Las fases 5 y 6 siguen pendientes.

## Recursos retirados

La rama Supabase fue eliminada y su ausencia comprobada; las otras ramas permanecen. La hoja ficticia fue eliminada con HTTP 204 y las dos tablas temporales con `success=true` (ejecución 51). Los tres workflows temporales están archivados y fuera de la búsqueda activa; el aviso temporal se despublicó antes de archivarlo.

Los seis archivos privados locales con claves/contraseñas fueron eliminados, sin coincidencias de sus valores en los artefactos de evidencia. El contenedor efímero de Playwright no persiste; `/f3-privado` fue un montaje temporal de solo lectura. Se conservan dos capturas de Directorio; las otras capturas se reemplazaron durante la repetición de Playwright y no se afirman conservadas.

La eliminación individual de los dos comprobantes de inversión fue rechazada por su FK, como protege el producto. Se retiró la rama completa mediante la API de Supabase; no se relajó la protección ni se borraron filas financieras para eludirla. No se afirma que el DELETE individual de Storage pasara.

**Limpieza de interfaz completada:** Miguel eliminó `Simplified Custom Auth account 2` (`Ag61FRD4BJjGI4hZ`); el listado MCP confirma su ausencia y conserva la original `YNRHr2PjhfLXnKff`. Durante esta comprobación se detectó un segundo autosave de UI (`907688a7`, 00:20 UTC) que había vuelto a seleccionar la temporal. Tras confirmar Miguel que cerró las pestañas del editor, se restauró únicamente la original: versión vigente `29940eb5-d36c-49c7-bf7f-686b66cc3f76`, con diff vacío frente a la primera restauración y ajustes idénticos. Principal inactivo, HTTP deshabilitado y envío apagado. Evidencia: `cierre-credencial.json`. No se ejecutó el importador.

Los correos e identificadores de `usuarios-sinteticos.json` y `http-*.json` son fixtures (`@pruebas.invalid`), sin contraseñas, JWT ni datos de clientes. La evidencia se conserva para auditoría, no como credenciales reutilizables.

## Revisión

Claude revisó la implementación y evidencia de forma aislada. Dictamen inicial: `CHANGES_REQUESTED`, sin P0/P1. Resolución del PRIMARY en `revision-resolucion.md`; las mejoras aceptadas añadieron evidencia, reproducibilidad y la prueba de numerador. La comprobación de credenciales detectó y corrigió el cambio descrito arriba.

La revisión final dirigida (`revision-cierre-claude.txt`) también fue `CHANGES_REQUESTED`, sin P0/P1: pidió ampliar historial/comparación, explicar el reintento Legacy y precisar procedencia/reutilización de las pruebas. Se incorporaron esas aclaraciones y verificaciones, con sus límites explícitos. Codex cierra el objetivo del ensayo aislado; no se atribuye a Claude un PASS ni una autorización para publicar.

Tablero: [Formulario 3 · plan por fases](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).
