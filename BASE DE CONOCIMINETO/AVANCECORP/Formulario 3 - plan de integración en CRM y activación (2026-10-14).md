# Formulario 3 - plan de integración en CRM y activación

Fecha: 2026-10-14. Continuación de **N8N-AVANCE-141026**. Estado vigente: **fases 1–3 implementadas y validadas; sin publicar**. El recorrido integrado y sus fallos fueron comprobados en una rama temporal, ya retirada. Sigue fase 4; publicación y carga real pendientes. Codex PRIMARY; Miguel opera el navegador. Claude revisó el plan, las implementaciones y la evidencia integrada; Codex incorporó las mejoras justificadas. Evidencia y cierre: [[Formulario 3 - fase 3 integrada y validada sin publicar (2026-10-14)]].

Relacionado: [[n8n - Formulario 3 preparado y avisos conectados (2026-10-14)]] · [[Canales de origen de leads CRM]] · [[Carga de leads desde hoja de Google]].

## Resultado que debe ver Miguel

Los contactos nuevos de esta hoja mostrarán **Formulario 3** como campaña y se podrán filtrar por ella. Su canal seguirá siendo **FORMULARIO**, con el mismo turno de reparto y las mismas reglas de conversión de las altas automáticas.

Se conservan el historial y responsable de contactos existentes. Una coincidencia no autoriza reclasificar su origen ni crear otro lead. Para clientes reconocidos, la campaña acompañará la actividad o solicitud que ya produce el importador. Los duplicados ordinarios seguirán identificados como tales en el registro de importación; no se promete que sean altas nuevas ni que aparezcan retroactivamente en el filtro de campaña de origen.

## Punto de partida comprobado

- Fuente vigente: https://docs.google.com/spreadsheets/d/1lPvJ-65PNY1d4eme5xpcJ8ITVazkQRdjtkgW4ZLoIsI/edit#gid=0.
- Última lectura: **127 leads** ya filtrados. Actualizar esta foto antes de cargar, porque la hoja puede cambiar.
- Flujo n8n **Avance Corp — Formulario 3 → CRM**, ID `BjI5m1PKVWhO0NDb`: inactivo, envío apagado, HTTP deshabilitado; recibos de producción en cero al cierre anterior.
- Payload ya preparado con `canal=formulario` y `campania_origen=Formulario 3`. El importador actual ignora la campaña; el CRM todavía no tiene ese campo.
- Avisos a **miguel@miavance.com** comprobados automáticamente en el flujo aislado: ejecución 44 enviada y 46 suprimida por repetición de la misma hora. Se conserva la prueba manual del aviso productivo como control previo a activar.
- Se mantienen las decisiones de mapeo ya cerradas: capital, moneda, teléfonos y consentimiento. Esta etapa no rediseña esas reglas.

## Orden de trabajo y condiciones para avanzar

### 1. Guardar la campaña sin cambiar las reglas comerciales

**COMPLETADA EN BANCO, SIN PUBLICAR (14/10):** 36 comprobaciones de contrato y 18 de permisos PASS en local y remoto; regresión de ficha viva corregida; histórico conservado, advisors sin avisos nuevos y rama temporal retirada. Detalle en [[Formulario 3 - fase 1 validada sin publicar (2026-10-14)]].

Agregar un campo opcional `campania_origen` en `crm.leads`, con escritura controlada por el servidor. Usar texto de 1 a 80 caracteres una vez recortado, o NULL cuando no se proporciona; la integración enviará el valor canónico **Formulario 3**. Rechazar valores explícitos inválidos en vez de descartarlos silenciosamente. Evitar un enum de base que obligue a migrar por cada campaña futura. Los registros históricos quedan sin campaña, sin reclasificación masiva.

Extender el contrato de `crm-importar-leads` y la misma transacción de `crm.importar_lead_fn` para persistirlo al crear el lead. Para esta integración, validar la combinación **Formulario 3 + formulario**. Mantener compatibles los envíos del Apps Script que omiten el campo.

No hacer una segunda actualización después de importar: la campaña y el alta deben confirmarse juntas. Conservar `alta_manual`, procedencia, responsables, reglas de turno y conversión existentes.

En clientes reconocidos con lead vivo, propagar `campania_origen` en los metadatos del reingreso y ampliar expresamente la lista permitida de `crm.registrar_reingreso_lead_fn`: actualmente eliminaría esa clave. Usar exactamente el mismo objeto para comparar la repetición y guardarlo.

Para clientes sin lead vivo, `private.registrar_solicitud_cliente_fn` ya deduplica mediante una huella de los datos sin número de fila y una ventana de siete días, bajo candado por cliente. Conservar esa protección. Su actividad y tarea se guardan como texto, no como nuevos metadatos JSON: incluir la campaña en el detalle visible antes de truncar la nota, preservando el sufijo de huella usado para deduplicar.

Probar el caso de veredicto con lead cerrado y otra ficha viva: el importador actual detecta `v_lead_vivo`, pero consulta y escribe el reingreso usando `v_lead`. Si el caso confirma el desvío, la corrección mínima de búsqueda y escritura a la ficha viva forma parte de esta entrega y bloquea la activación hasta pasar el test. No introducir una clave nula cuando no venga campaña: podría cambiar la comparación de igualdad de la guarda de reingreso de siete días. Probar repetición de la misma campaña y contactos por campañas diferentes.

**Salida exigida:** un alta nueva guarda la campaña; un envío antiguo sigue funcionando; las coincidencias conservan su tratamiento e historial.

### 2. Mostrar y filtrar la campaña en el CRM

**PREPARADA Y VALIDADA LOCALMENTE, SIN PUBLICAR (14/10):** 6.700 pruebas de app, 9 E2E Docker y 43 SQL PASS. Revisión de Claude resuelta; consultas y metadatos compatibles, permisos y etiquetas comprobados. Auth/HTTP integrado y ensayo remoto final completados en fase 3; ver su nota de cierre. Cierre: [[Formulario 3 - fase 2 validada sin publicar (2026-10-14)]].

Actualizar tipos, validadores, mapeos, proyecciones SQL y lecturas. Incorporar una etiqueta de campaña por contacto en Cartera, ficha y las vistas pertinentes que ya muestran el origen, manteniendo **FORMULARIO** como agrupación de turno y métricas.

Añadir el filtro **Campaña → Formulario 3** a la cartera principal, con las opciones iniciales **Todas** y **Formulario 3**. Aplicarlo en servidor a toda la consulta, incluida la paginación y sus totales. Actualizar claves de caché y el comportamiento de demostración para que no contradigan la vista real.

Inspeccionar las funciones SQL y sus envoltorios vigentes antes de cambiar parámetros o respuestas. Los contratos vivos no son idénticos a todas las opciones de llamada locales. `cartera_filtrada_fn` tiene 14 parámetros; añadir uno con CREATE OR REPLACE dejaría otra firma y podría volver ambiguas las llamadas. Tras resolver dependencias, reemplazar la firma exacta y restaurar sus permisos en la misma transacción, sin DROP CASCADE. Si una dependencia requiere mantenerla, definir una RPC versionada compatible antes de implementar. Incluir un eco del filtro solicitado y validarlo. La ruta antigua no integrada no debe ignorar el filtro: usar la ruta integrada que sí lo implementa.

La columna necesita permisos de lectura bajo el ámbito de cada rol. La inspección de fase 1 confirmó UPDATE de tabla para authenticated en la base viva: la migración preparada conserva los permisos efectivos anteriores mediante grants por columna y excluye la campaña de la edición humana. Ejecutar ADD COLUMN, GRANT SELECT y las adaptaciones SQL dependientes en una sola migración transaccional; nunca dejar una ventana sin permisos. Revisar proyecciones `SELECT *` y validadores estrictos, además del `LeadRowSchema` actual que usa `v.object`. Mantenerla fuera de la edición manual y no ampliar el acceso a otros contactos.

**Salida exigida:** la misma campaña se ve en listado y ficha; filtrar y cambiar de página mantiene resultados y cifras coherentes; registros sin campaña conservan su apariencia actual.

### 3. Probar y revisar antes de publicar

**Objetivo:** demostrar que Google Sheets → n8n → importador → CRM funciona de principio a fin en un entorno aislado, con autenticación real, campaña visible, reparto y cifras correctos, y recuperación comprobada ante reintentos y fallos. Verificar el aviso automático a Miguel y dejar evidencia suficiente para decidir el paso a publicación.

**Estado: VALIDADA EN ENTORNO AISLADO (14/10).** 98 SQL, 49 casos HTTP/Auth/reparto, 6 casos adicionales de reingreso/conversión y cuatro roles de UI real. Sheets → n8n → Edge pasó; repetición, movimiento, rechazo, fallo, aviso automático y recuperación comprobados. Evidencia y límites: [[Formulario 3 - fase 3 integrada y validada sin publicar (2026-10-14)]]. No se publicó ni se cargó la hoja real. El gate de realidad original permanece FAIL con complemento SQL; se exige repararlo o enmendarlo antes de fase 4.

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

**Estado: PLANIFICADA, NO EJECUTADA.** Detalle ampliado el 14/10 tras cerrar la limpieza de fase 3. **Objetivo:** llevar al CRM real el soporte de campaña Formulario 3, su etiqueta y filtro, manteniendo las reglas comerciales de FORMULARIO y la compatibilidad con contactos existentes. Al terminar quedará preparado para la prueba de una fila de fase 5; el envío periódico permanece apagado.

1. **Resolver el control previo de publicación.** Reparar o enmendar formalmente el verificador de realidad: lectura de sellos denegada y timeout. Volver a medir el estado vigente y guardar resultados. Clasificar las advertencias preexistentes de datos y dejar explícito su criterio de bloqueo; el complemento SQL de fase 3 no convierte el FAIL original en PASS. Conservar permisos de negocio y no alterar datos ajenos a la campaña para forzar un resultado favorable.
2. **Preparar una versión verificable.** Integrar los cambios remotos sin sobrescribirlos y conservar el trabajo ajeno. Comprobar Main local y `avancecorp/main` en el mismo commit; construir el artefacto desde ese commit. Ejecutar las comprobaciones pertinentes al cambio final, incluidos permisos, contratos y E2E locales Docker cuando corresponda. Adjuntar a Claude las correcciones y evidencia relevantes, evaluar sus mejoras justificadas y resolver bloqueos antes de publicar. Preparar la vuelta a artefactos compatibles con el esquema aditivo.
3. **Revisar la configuración operativa.** Releer historial, credencial original, destino del importador y ajustes de n8n con las pestañas antiguas cerradas o recargadas. Confirmar importación inactiva. Definir cuánto tiempo conservar ejecuciones fallidas y verificar el aviso productivo a Miguel mediante su trigger manual; actualizar su nombre antiguo. La prueba del correo no requiere importar leads.
4. **Publicar en orden compatible.** Primero la base y permisos que admiten la campaña; después el importador que la guarda; por último la pantalla que la muestra y filtra. Comprobar capacidad y versión antes de cada paso: el importador nuevo no debe quedar conectado a una función antigua que ignore el campo. La publicación se inicia mediante `$release-crm`, conforme a `CRM-Avance-Corp/CLAUDE.md`; este detalle del plan no ejecuta ni autoriza esa publicación.
5. **Verificar el CRM publicado.** Confirmar que la versión accesible corresponde al artefacto previsto, revisar acceso y lecturas de los roles pertinentes, disponibilidad del campo y filtro de campaña, compatibilidad de contactos sin campaña y coherencia de las cifras existentes. Verificar también la transición para pantallas que permanecieran abiertas. Registrar evidencia y cualquier límite. Si falla un control obligatorio, detener el avance y aplicar la recuperación compatible preparada; no borrar campañas ni contactos como mecanismo de reversión.
6. **Cerrar y entregar.** Guardar versión, comprobaciones, decisiones sobre advertencias y procedimiento de recuperación; actualizar Figma y vault. Mantener n8n detenido y los recibos correctos conservados. La primera fila real corresponde a fase 5; la carga supervisada y activación cada cinco minutos, a fase 6.

**Salida exigida:** controles de publicación resueltos, versión publicada verificada, accesos y lecturas existentes operativos, soporte Formulario 3 disponible y avisos comprobados. La publicación requiere la invocación humana indicada; Codex prepara primero el paquete concreto y revisable.

### 5. Importar una fila real de forma controlada

Con cron apagado y ninguna ejecución simultánea, fijar explícitamente el límite en **una fila**. Seleccionar una fila real pendiente que se espere nueva y registrar su identidad/fingerprint; usar la misma identidad y tabla de recibos que se usarán después.

Comprobar respuesta, campaña visible, procedencia automática, tratamiento de reparto y recibo confirmado. Repetir la misma selección para confirmar que se omite y no produce otro alta o reparto. Si resulta duplicado o cliente reconocido, verificar ese camino y elegir una alta nueva para comprobar también el resultado visible de creación.

Si una comprobación falla, detener los envíos y corregir antes de cargar más.

**Salida exigida:** prueba de extremo a extremo aceptada con evidencia de repetición segura.

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
- Fases 1–3 validadas; publicación y carga real corresponden a fases 4–6. No se afirmó prueba remota específica de 5xx/timeout ni de fallo de recibo en modo trigger: la recuperación y el aviso se verificaron con los casos descritos en el cierre.
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
2. `crm.registrar_reingreso_lead_fn` **sí filtra las claves** de `p_datos` y hoy no incluye campaña. Es obligatorio ampliar su lista y verificar igualdad entre lo comparado y lo guardado.
3. El uso de `v_lead` después de localizar `v_lead_vivo` está presente en la definición viva. La fase 1 reprodujo el defecto y verificó la corrección mínima en banco local y remoto; no se ha publicado.
4. `LeadRowSchema` usa `v.object` en `app/src/data/crm-api.ts:244`. Esto no acredita por sí solo todos los lectores: el gate revisará también envoltorios y esquemas estrictos.

No se repreguntó si debían aplicar las reglas normales de FORMULARIO: Miguel ya lo autorizó expresamente. Se explicita la fecha de recepción y el tratamiento de duplicados, en lugar de introducir otra aprobación para una decisión ya tomada. El ritmo se mantiene supervisado; no se promete una duración fija para cargar 127 filas.

Revisión de flujos que reactivan o reconstruyen leads: comprobar su impacto y preservar la campaña al reactivar el mismo registro. No propagar automáticamente la campaña a un contacto nuevo o una fusión sin una regla respaldada por el negocio; no ampliar esta tarea a un sistema general de atribución.



## Versión visual en Figma

**Regla permanente solicitada por Miguel (14/10/2026):** actualizar este tablero con cada avance relevante del plan: objetivo de la fase, trabajo realizado, evidencia, pendientes y siguiente paso. Distinguir siempre preparado, probado, publicado y activado; no marcar una fase completada por haber definido su objetivo.

Miguel pidió trasladar el plan por fases a Figma. Tablero editable creado el 14/10/2026 en el equipo de Avance Corp:

[Formulario 3 · Plan de desarrollo](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).

Contiene el punto de partida, la regla FORMULARIO, el mapa secuencial y seis fichas con trabajo, criterio de cierre y responsables: guardar campaña; mostrar y filtrar; pruebas y revisión; publicar CRM; probar un lead real; cargar y activar. Incluye conciliación de filas, actuación ante fallos y avisos a Miguel. Actualizado al cierre de fase 3: fases 1–3 validadas sin publicar; fase 4 siguiente, con gate de publicación pendiente; fases 5–6 pendientes. n8n principal permanece apagado.

Archivo FigJam: `JB4jRdmLXZXS0hBhEHxRbV`. Sección principal: `2:34`. Verificación estructural: seis fases, sin desbordamientos ni marcadores de trabajo pendientes. Captura visual revisada: texto legible, tarjetas y conexiones completas, sin solapamientos. El tablero se creó al planificar y se actualizó tras cada fase, incluida la integración real de fase 3. No se publicó ni activó la integración.

Actualización del objetivo de fase 3 (14/10/2026): tarjeta `2:52` con recorrido aislado, campaña/reparto/cifras/permisos, reintentos, duplicados, recuperación, aviso automático, ensayo remoto y acceso del verificador. Cierre: recorrido y fallos comprobados, pruebas obligatorias aprobadas, revisión resuelta y evidencia guardada. Ese fue el estado inicial. Al cierre de fase 3, tarjeta, mapa y pie se actualizan a validada, con recursos de ensayo retirados y publicación pendiente.
