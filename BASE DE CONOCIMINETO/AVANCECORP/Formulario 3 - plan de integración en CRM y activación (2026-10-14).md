# Formulario 3 - plan de integración en CRM y activación

Fecha inicial: 2026-10-14. Actualización: 2026-10-15. Continuación de **N8N-AVANCE-141026**. Estado vigente: **fases 1–5 completadas; CRM publicado y una fila real comprobada**. Una alta y un recibo confirmados; repetir la fila no produjo otro envío, duplicado ni reasignación. n8n principal sigue apagado. Sigue la carga supervisada y activación de fase 6. Codex PRIMARY; Miguel opera el navegador. Claude revisó el plan, las implementaciones y la evidencia relevante; Codex incorporó las mejoras justificadas. Estado publicado: [[Formulario 3 - fase 4 publicada y verificada (2026-10-14)]]. Las notas de fases 1–4 conservan la evidencia histórica de cada cierre.

Relacionado: [[n8n - Formulario 3 preparado y avisos conectados (2026-10-14)]] · [[Canales de origen de leads CRM]] · [[Carga de leads desde hoja de Google]].

## Resultado que debe ver Miguel

Los contactos nuevos de esta hoja mostrarán **Formulario 3** como campaña y se podrán filtrar por ella. Su canal seguirá siendo **FORMULARIO**, con el mismo turno de reparto y las mismas reglas de conversión de las altas automáticas.

Se conservan el historial y responsable de contactos existentes. Una coincidencia no autoriza reclasificar su origen ni crear otro lead. Para clientes reconocidos, la campaña acompañará la actividad o solicitud que ya produce el importador. Los duplicados ordinarios seguirán identificados como tales en el registro de importación; no se promete que sean altas nuevas ni que aparezcan retroactivamente en el filtro de campaña de origen.

## Punto de partida comprobado

- Fuente vigente: https://docs.google.com/spreadsheets/d/1lPvJ-65PNY1d4eme5xpcJ8ITVazkQRdjtkgW4ZLoIsI/edit#gid=0.
- Última lectura: **127 leads** ya filtrados. Actualizar esta foto antes de cargar, porque la hoja puede cambiar.
- Flujo n8n **Avance Corp — Formulario 3 → CRM**, ID `BjI5m1PKVWhO0NDb`: inactivo, envío apagado, HTTP deshabilitado; un recibo confirmado en la prueba de fase 5.
- Payload preparado con `canal=formulario` y `campania_origen=Formulario 3`. Desde fase 4 el importador v24 guarda la campaña y el CRM la muestra y filtra; 3.687 leads históricos sin reclasificar en el postflight.
- Avisos a **miguel@miavance.com** comprobados automáticamente en el flujo aislado: ejecución 44 enviada y 46 suprimida por repetición de la misma hora. Aviso productivo manual de fase 4: ejecución 52 SUCCESS, Gmail confirmó envío.
- Se mantienen las decisiones de mapeo ya cerradas: capital, moneda, teléfonos y consentimiento. Esta etapa no rediseña esas reglas.

## Orden de trabajo y condiciones para avanzar

### 1. Guardar la campaña sin cambiar las reglas comerciales

**PUBLICADA Y VERIFICADA EN FASE 4 (14/10 Lima):** migración exacta `20261014210146` e importador v24. Ensayo previo: 36 comprobaciones de contrato y 18 de permisos PASS en local y remoto; regresión de ficha viva corregida; histórico conservado, advisors sin avisos nuevos y rama temporal retirada. Detalle del ensayo en [[Formulario 3 - fase 1 validada sin publicar (2026-10-14)]]. Los párrafos siguientes conservan el contrato implementado.

Agregar un campo opcional `campania_origen` en `crm.leads`, con escritura controlada por el servidor. Usar texto de 1 a 80 caracteres una vez recortado, o NULL cuando no se proporciona; la integración enviará el valor canónico **Formulario 3**. Rechazar valores explícitos inválidos en vez de descartarlos silenciosamente. Evitar un enum de base que obligue a migrar por cada campaña futura. Los registros históricos quedan sin campaña, sin reclasificación masiva.

Extender el contrato de `crm-importar-leads` y la misma transacción de `crm.importar_lead_fn` para persistirlo al crear el lead. Para esta integración, validar la combinación **Formulario 3 + formulario**. Mantener compatibles los envíos del Apps Script que omiten el campo.

No hacer una segunda actualización después de importar: la campaña y el alta deben confirmarse juntas. Conservar `alta_manual`, procedencia, responsables, reglas de turno y conversión existentes.

En clientes reconocidos con lead vivo, propagar `campania_origen` en los metadatos del reingreso y ampliar expresamente la lista permitida de `crm.registrar_reingreso_lead_fn`: actualmente eliminaría esa clave. Usar exactamente el mismo objeto para comparar la repetición y guardarlo.

Para clientes sin lead vivo, `private.registrar_solicitud_cliente_fn` ya deduplica mediante una huella de los datos sin número de fila y una ventana de siete días, bajo candado por cliente. Conservar esa protección. Su actividad y tarea se guardan como texto, no como nuevos metadatos JSON: incluir la campaña en el detalle visible antes de truncar la nota, preservando el sufijo de huella usado para deduplicar.

Probar el caso de veredicto con lead cerrado y otra ficha viva: el importador actual detecta `v_lead_vivo`, pero consulta y escribe el reingreso usando `v_lead`. Si el caso confirma el desvío, la corrección mínima de búsqueda y escritura a la ficha viva forma parte de esta entrega y bloquea la activación hasta pasar el test. No introducir una clave nula cuando no venga campaña: podría cambiar la comparación de igualdad de la guarda de reingreso de siete días. Probar repetición de la misma campaña y contactos por campañas diferentes.

**Salida exigida:** un alta nueva guarda la campaña; un envío antiguo sigue funcionando; las coincidencias conservan su tratamiento e historial.

### 2. Mostrar y filtrar la campaña en el CRM

**PUBLICADA Y VERIFICADA EN FASE 4 (14/10 Lima):** migración exacta `20261014215453`, frontend `build-20261015T041350920Z`. Ensayo de fase 2: 6.700 pruebas de app, 9 E2E Docker y 43 SQL PASS. Revisión de Claude resuelta; consultas y metadatos compatibles, permisos y etiquetas comprobados. Auth/HTTP integrado y ensayo remoto final completados en fase 3. Evidencia histórica: [[Formulario 3 - fase 2 validada sin publicar (2026-10-14)]]. Los párrafos siguientes conservan el contrato implementado; la firma final de cartera tiene 15 argumentos.

Actualizar tipos, validadores, mapeos, proyecciones SQL y lecturas. Incorporar una etiqueta de campaña por contacto en Cartera, ficha y las vistas pertinentes que ya muestran el origen, manteniendo **FORMULARIO** como agrupación de turno y métricas.

Añadir el filtro **Campaña → Formulario 3** a la cartera principal, con las opciones iniciales **Todas** y **Formulario 3**. Aplicarlo en servidor a toda la consulta, incluida la paginación y sus totales. Actualizar claves de caché y el comportamiento de demostración para que no contradigan la vista real.

Inspeccionar las funciones SQL y sus envoltorios vigentes antes de cambiar parámetros o respuestas. Los contratos vivos no son idénticos a todas las opciones de llamada locales. `cartera_filtrada_fn` tiene 14 parámetros; añadir uno con CREATE OR REPLACE dejaría otra firma y podría volver ambiguas las llamadas. Tras resolver dependencias, reemplazar la firma exacta y restaurar sus permisos en la misma transacción, sin DROP CASCADE. Si una dependencia requiere mantenerla, definir una RPC versionada compatible antes de implementar. Incluir un eco del filtro solicitado y validarlo. La ruta antigua no integrada no debe ignorar el filtro: usar la ruta integrada que sí lo implementa.

La columna necesita permisos de lectura bajo el ámbito de cada rol. La inspección de fase 1 confirmó UPDATE de tabla para authenticated en la base viva: la migración preparada conserva los permisos efectivos anteriores mediante grants por columna y excluye la campaña de la edición humana. Ejecutar ADD COLUMN, GRANT SELECT y las adaptaciones SQL dependientes en una sola migración transaccional; nunca dejar una ventana sin permisos. Revisar proyecciones `SELECT *` y validadores estrictos, además del `LeadRowSchema` actual que usa `v.object`. Mantenerla fuera de la edición manual y no ampliar el acceso a otros contactos.

**Salida exigida:** la misma campaña se ve en listado y ficha; filtrar y cambiar de página mantiene resultados y cifras coherentes; registros sin campaña conservan su apariencia actual.

### 3. Probar y revisar antes de publicar

**Objetivo:** demostrar que Google Sheets → n8n → importador → CRM funciona de principio a fin en un entorno aislado, con autenticación real, campaña visible, reparto y cifras correctos, y recuperación comprobada ante reintentos y fallos. Verificar el aviso automático a Miguel y dejar evidencia suficiente para decidir el paso a publicación.

**Estado: VALIDADA EN ENTORNO AISLADO (14/10).** 98 SQL, 49 casos HTTP/Auth/reparto, 6 casos adicionales de reingreso/conversión y cuatro roles de UI real. Sheets → n8n → Edge pasó; repetición, movimiento, rechazo, fallo, aviso automático y recuperación comprobados. Evidencia y límites: [[Formulario 3 - fase 3 integrada y validada sin publicar (2026-10-14)]]. En esa fase no se publicó ni se cargó la hoja real. El fallo del gate de realidad se resolvió y documentó en fase 4: diez mediciones completas, con dos advertencias históricas ajenas a campaña, sin alterar datos para ocultarlas.

Usar un entorno de datos autorizado y aislado, con fixtures, sin contactos ficticios en producción. Casos mínimos:

- Alta automática con campaña; payload anterior sin campaña.
- Reintento de la misma fila y fila cambiada de posición, sin otro lead ni otro reparto.
- Duplicado ordinario y cliente reconocido, conservación de responsable/origen y campaña en su actividad cuando corresponda.
- Guarda de reingreso y de solicitud de cliente compatible con datos anteriores; campaña conservada por la lista permitida; misma fila repetida sin otra nota/tarea; lead del veredicto cerrado frente a otra ficha viva.
- Mismos efectos de reparto y conversión que un FORMULARIO automático.
- Lectura permitida por rol, escritura de campaña restringida y ausencia de acceso fuera del ámbito.
- Filtro de campaña con varias páginas, totales, capital y embudo correctos; firma RPC inequívoca, permisos restaurados y compatibilidad durante la publicación.
- Fallo del importador: pendiente recuperable, recibo solo tras resultado confirmado y continuación de las otras filas.
- Aviso automático ante fallo real de ejecución programada en un flujo de prueba aislado, sin importar clientes.

Aplicar los gates de `CLAUDE.md`, `supabase/migrations/LEEME.md` y `../.ai/VERIFICATION.md`: migración nueva y ledger, rama de base autorizada, dependencias SQL, auditoría de permisos, matriz RLS y advisors; tipos generados; checks de scripts/Edge; `npm run check` en `app` y E2E pertinentes mediante `npm run test:e2e:docker`. Verificar igualdad del Edge canónico y su espejo.

Claude revisa los riesgos y la implementación relevante con evidencia saneada; Codex evalúa y aplica las mejoras justificadas, ejecuta los checks y reporta PASS/FAIL/NOT RUN. Una opinión de Claude no sustituye las pruebas.

**Salida exigida:** evidencia suficiente y comprobaciones aplicables aprobadas; los checks no ejecutados se explicitan y se resuelven antes de avanzar cuando sean obligatorios.

### 4. Publicar el soporte de CRM

**Estado: PUBLICADA Y VERIFICADA (14/10, 23:17 Lima).** **Objetivo cumplido:** el CRM real recibe, guarda, identifica y filtra la campaña Formulario 3, manteniendo las reglas comerciales de FORMULARIO, Coordinación y la compatibilidad con contactos existentes. Queda preparado para la prueba de una fila de fase 5; el envío periódico permanece apagado. [Acta técnica](../../CRM-Avance-Corp/docs/N8N-FORMULARIO3-FASE4-PUBLICADA.md) y [[Formulario 3 - fase 4 publicada y verificada (2026-10-14)]].

1. **Control previo resuelto.** Diez mediciones completas; salida 0 sin modo estricto. Persisten 45 ventas de analistas inactivos y 273 clientes sin domicilio, advertencias anteriores y ajenas a campaña. El modo estricto retorna 1 ante ellas; no se presenta como PASS ni se alteran datos comerciales. Sellos y cinco caminos de conversión medidos completaron.
2. **Artefacto verificable.** PR 280 fusionada; Main limpio y `avancecorp/main` iguales a `0fa4a39892c1b38946d06b7a0e03d57b83b013c9` al construir. App 6.707 tests y controles relevantes PASS; E2E en Docker local, ensayos SQL/Auth en rama y 44 huellas de producto conservadas. Claude revisó; observaciones resueltas con evidencia. ZIP anterior y manifiesto conservados para recuperación compatible.
3. **Operación comprobada.** Credencial original y destino productivo conservados; n8n inactivo, envío false, nodo HTTP deshabilitado y cero ejecuciones pendientes/en curso al cierre. Aviso productivo renombrado y envío manual 52 SUCCESS. Política definida de contenido fallido: máximo siete días; configuración efectiva del VPS NOT RUN, pendiente antes de la primera fila real.
4. **Publicación ordenada.** SQL exacto `20261014210146` y `20261014215453` → capacidad/permisos/firma/caché → `crm-importar-leads` v24 → frontend `build-20261015T041350920Z`. Se siguió el procedimiento release-crm y su preflight obligatorio, bajo la autorización explícita del objetivo de publicación y su reanudación por Miguel. La rama de pago ya había sido retirada; no se recreó.
5. **Producción verificada.** 124 archivos HTTP exactos y acceso público Chromium/Docker PASS. Cuatro contextos SQL authenticated (Coordinación, Supervisor, Vendedor y Gerencia), lectura anterior y filtro nuevo PASS en READ ONLY; esto no se presenta como inicio de sesión HTTP de producción. HTTP/Auth reales y el frontend anterior contra esquema nuevo se probaron en la rama. Columna/ACL, RLS y firma única de 15 argumentos correctas; 3.687 leads históricos sin campaña y sin reclasificación.
6. **Cierre registrado.** Acta con evidencia, ledger, vault y Figma actualizados. n8n detenido y recibos conservados. Ninguna fila real importada. La primera fila corresponde a fase 5; la carga supervisada y activación cada cinco minutos, a fase 6.

**Salida acreditada:** controles de publicación resueltos, versión publicada verificada, lecturas y permisos existentes operativos, soporte Formulario 3 disponible y avisos comprobados. Recuperación compatible documentada; no se borran datos ni se revierte SQL automáticamente.

### 5. Importar una fila real de forma controlada

**COMPLETADA (15/10, 00:25 Lima; confirmación visual de Miguel a las 00:28).** Una fila real recorrió Sheets → n8n → CRM y quedó visible en Repartir con **Campaña: Formulario 3**. Se compararon 20 campos/invariantes: todos correctos. El origen comercial visible sigue siendo **FORMULARIO**. [Evidencia saneada](../../CRM-Avance-Corp/docs/N8N-FORMULARIO3-FASE5-EVIDENCIA.json).

- **53 — vista previa, SUCCESS:** una fila preparada, cero envíos; SHA-256 del nodo comprobado con cálculo independiente.
- **54 — importación, SUCCESS:** preflight sin coincidencias; una alta y un recibo confirmados. Total de CRM 3.687 → 3.688, campaña 0 → 1. Lead en cola global para Coordinación, sin vendedor/supervisor y sin episodios de asignación.
- **55 — repetición, SUCCESS:** misma fila y huella; `Omitir filas confirmadas` devolvió cero pendientes. HTTP y registro no ejecutados; lead completo, responsables, recibo y asignaciones idénticos.
- **Coordinación:** RPC bajo rol SQL authenticated de un coordinador activo en transacción READ ONLY antes y después de 55. Esto acredita autorización, no un login HTTP. La captura de Miguel muestra una sola tarjeta y la campaña en el comentario; no se infiere el rol de su sesión. No hay turno guardado y no se hizo reparto humano.
- **Retención: PASS_CONFIGURACION.** Miguel aplicó y verificó `true / 144 / 1` dentro del contenedor. Imagen fijada `2.43.5`, comparación previa y recreación solo del servicio sin descargar otra imagen. Ciclo real de poda y borrado forense: NOT RUN. Revisar envejecimiento de 53–55 después del 21/10 a las 06:30 UTC, considerando el intervalo de poda; no se creó un recordatorio automático.
- **Estado al cierre:** workflow sin publicar/inactivo, cron y HTTP deshabilitados, envío false, simulación true, cero ejecuciones pendientes. Se conserva la selección de fila 2 y el código que exige una fila/huella; `huella_objetivo=null` al cierre, por lo que la guarda rechaza cualquier intento de enviar sin volver a fijarla. Fase 6 debe sustituir expresamente esa selección antes de procesar lotes.
- **Calidad:** 30 tests locales PASS y validación MCP PASS. Dos revisiones de Claude, ambas CHANGES_REQUESTED sin P0/P1; correcciones aceptadas aplicadas. La segunda pidió precisar la evidencia y completar documentación, sin otra consulta. Los controles efectivos de 53/54/55 se recuperaron de las propias ejecuciones. Las versiones se vinculan a lecturas previas del workflow; el MCP no devuelve el workflow histórico completo.

El protocolo ejecutado se conserva a continuación. No implica volver a importar la fila de prueba.

Con cron apagado y ninguna ejecución simultánea, fijar explícitamente el límite en **una fila**. Seleccionar una fila real pendiente que se espere nueva y registrar su identidad/fingerprint; usar la misma identidad y tabla de recibos que se usarán después.

Comprobar respuesta, campaña visible, procedencia automática, tratamiento de reparto y recibo confirmado. Repetir la misma selección para confirmar que se omite y no produce otro alta o reparto. Si resulta duplicado o cliente reconocido, verificar ese camino y elegir una alta nueva para comprobar también el resultado visible de creación.

La repetición solo procede tras comprobar una ejecución exitosa, un recibo definitivo para la huella elegida y una única alta que coincida con la identidad esperada. Guardar antes y después la evidencia de responsable, cola y asignaciones, sin publicar datos personales. Una discrepancia exige detenerse y conciliar mediante lecturas; no repetir el POST a ciegas. La entrada habitual de FORMULARIO queda inicialmente en la cola de Coordinación y no implica asignar un analista automáticamente al importar.

Si una comprobación falla, detener los envíos y corregir antes de cargar más.

**Salida acreditada:** alta real, campaña visible, acceso de Coordinación, entrada a su cola con reglas de FORMULARIO, recibo confirmado y repetición sin envío, alta ni asignación adicional. Figma actualizado; programación automática apagada.

### 6. Cargar el resto y activar el funcionamiento periódico

Con cron todavía apagado, ejecutar lotes supervisados de hasta **25 pendientes**. Conciliar por filas de la foto de origen, manteniendo la relación con sus fingerprints (una edición crea otra huella), con resultados: importadas, duplicadas, clientes reconocidos, rechazadas y pendientes. Las 127 filas de la lectura inicial no equivalen necesariamente a 127 contactos nuevos.

Revisar rechazos y resolver pendientes; las filas nuevas que lleguen después de la foto se distinguen del lote inicial. Ejecutar la carga supervisada en una ventana acordada y observar su efecto en el turno antes de cada lote siguiente. Estas entradas se procesan con la fecha real de recepción y las reglas automáticas de FORMULARIO ya autorizadas; no se retrofechan según la captura en la hoja. Evitar una importación manual concurrente con el cron. Verificar si la versión/plan de n8n permite limitar a una ejecución simultánea por flujo y usarlo si está disponible; no dar esa opción por configurada. El timeout actual de 180 s es menor que el intervalo de 300 s.

Tras aceptar la carga, restaurar configuración operativa, activar cada **5 minutos**, verificar la primera ejecución programada y comprobar el enlace con las alertas. Registrar IDs de ejecución y estado final sin datos personales ni secretos.

Si aparecen fallos, apagar envío y cron, conservar recibos y altas correctas, y corregir solo los pendientes. No borrar contactos ni reiniciar toda la importación.

**Salida exigida:** campaña visible, carga conciliada, ejecución periódica comprobada y avisos automáticos comprobados.

## Límites y pendientes conocidos

- La entrega de n8n es al menos una vez. Se comprobó que un alta cuyo recibo se pierde se recupera como duplicado sin repetirla. Contar altas desde CRM por campaña; no sumar recibos importado como total de altas. Para un lote, cruzar la foto de filas/huellas con CRM.
- La campaña de origen del lead no es un historial de todas las campañas en que participó una persona. Los reingresos/clientes existentes conservan su historia mediante los mecanismos existentes; una eventual vista de participación múltiple sería otro alcance.
- Los avisos que dependen de n8n no detectan por sí solos la caída completa del VPS.
- Fases 1–5 completadas; carga restante y activación corresponden a fase 6. No se afirmó prueba remota específica de 5xx/timeout ni de fallo de recibo en modo trigger: la recuperación y el aviso se verificaron con los casos descritos en el cierre.
- **Diferido por Miguel (15/10):** adaptar la pantalla **Supervisores dentro de Coordinación** para distinguir Formulario 3. Se aborda después de terminar el plan principal. El turno de negocio sigue siendo FORMULARIO; no se introduce otro turno ni se cambia el reparto por esta decisión. En Repartir la campaña se identifica actualmente en el comentario; en Cartera/ficha/Pipeline persiste el campo y etiqueta desplegados.
- Avisos agrupados por hora de reloj, sin exclusión atómica: pueden coincidir varios en una carrera o cambio de hora. Gmail no tiene canal alternativo.
- Tras cambiar únicamente el parser, revisar y retirar solo recibos rechazados afectados antes de reprocesar; no vaciar el registro.

## Revisión de Claude y decisiones del PRIMARY

Revisión de arquitectura del 14/10/2026 mediante `scripts/claude-review`, solo lectura y sin herramientas. **VERDICT: CHANGES_REQUESTED; CONFIDENCE: MEDIUM.** Se le adjuntaron requisitos, estado de n8n, exploración CodeGraph, contratos Edge/frontend y definición SQL viva. No hubo un segundo review para buscar un dictamen favorable.

Enmiendas aceptadas en este plan:

- Columna y permisos en la misma transacción; comprobar lectores antiguos y nuevos.
- Evitar sobrecarga ambigua al modificar la firma de cartera; restaurar permisos y filtrar también cifras.
- Examinar los dos ayudantes SQL y probar idempotencia, listas permitidas y ficha destinataria.
- Definir validación de campaña, origen de las opciones del filtro y compatibilidad con datos históricos.
- Conciliar por filas de la foto inicial y sus huellas, explicar el resultado de duplicados y supervisar el ritmo.
- Comprobar soporte de límite de concurrencia en n8n, sin afirmarlo disponible.

Evidencia adicional obtenida después del review, mediante lecturas de definiciones SQL:

1. `private.registrar_solicitud_cliente_fn` **sí** tiene candado e idempotencia de siete días con huella sin `fila`. La ausencia de esa protección era una duda del reviewer, no un defecto confirmado. Se conserva y se prueba con campaña.
2. `crm.registrar_reingreso_lead_fn` **sí filtra las claves** de `p_datos`; al inicio no incluía campaña. La fase 1 amplió su lista y verificó igualdad entre lo comparado y lo guardado; está publicada desde fase 4.
3. El uso de `v_lead` después de localizar `v_lead_vivo` estaba presente en la definición inicial. La fase 1 reprodujo el defecto y verificó la corrección mínima en banco local y remoto; está publicada desde fase 4.
4. `LeadRowSchema` usa `v.object` en `app/src/data/crm-api.ts:244`. Esto no acredita por sí solo todos los lectores: el gate revisará también envoltorios y esquemas estrictos.

No se repreguntó si debían aplicar las reglas normales de FORMULARIO: Miguel ya lo autorizó expresamente. Se explicita la fecha de recepción y el tratamiento de duplicados, en lugar de introducir otra aprobación para una decisión ya tomada. El ritmo se mantiene supervisado; no se promete una duración fija para cargar 127 filas.

Revisión de flujos que reactivan o reconstruyen leads: comprobar su impacto y preservar la campaña al reactivar el mismo registro. No propagar automáticamente la campaña a un contacto nuevo o una fusión sin una regla respaldada por el negocio; no ampliar esta tarea a un sistema general de atribución.



## Versión visual en Figma

**Regla permanente solicitada por Miguel (14/10/2026):** actualizar este tablero con cada avance relevante del plan: objetivo de la fase, trabajo realizado, evidencia, pendientes y siguiente paso. Distinguir siempre preparado, probado, publicado y activado; no marcar una fase completada por haber definido su objetivo.

Miguel pidió trasladar el plan por fases a Figma. Tablero editable creado el 14/10/2026 en el equipo de Avance Corp:

[Formulario 3 · Plan de desarrollo](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).

Contiene el punto de partida, la regla FORMULARIO, el mapa secuencial y seis fichas con trabajo, criterio de cierre y responsables: guardar campaña; mostrar y filtrar; pruebas y revisión; publicar CRM; probar un lead real; cargar y activar. Incluye conciliación de filas, actuación ante fallos y avisos a Miguel. Actualizado al cierre de fase 5: fases 1–5 completadas, una alta y un recibo, repetición sin duplicados ni reasignación; fase 6 siguiente. n8n principal permanece apagado. El pie registra la adaptación de Supervisores diferida por Miguel.

Archivo FigJam: `JB4jRdmLXZXS0hBhEHxRbV`. Sección principal: `2:34`. Verificación estructural: seis fases, tarjetas y conexiones conservadas. Captura visual revisada para cada actualización. El tablero se creó al planificar y se actualizó tras cada fase. El CRM está publicado; la automatización de importación todavía no está activada.

Historial del tablero: fase 3 incorporó recorrido aislado, campaña/reparto/cifras/permisos, reintentos, duplicados, recuperación y aviso automático. Fase 4 actualizó mapa, estados, resultado de publicación y siguiente paso; la pausa intermedia quedó superada al reanudar el objetivo.
