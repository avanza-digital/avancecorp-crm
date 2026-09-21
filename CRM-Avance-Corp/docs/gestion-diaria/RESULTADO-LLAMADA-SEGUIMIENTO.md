# Resultado de llamada y próxima acción — 21/09/2026

## Estado y alcance

**PUBLICADO el 21/09/2026**, PR #62, fuente
`526e728e31ff64adaf9b737fa5e408ebe32005a2`, release
`crm-20260921T170501Z-526e728e31ff`. SQL v4 instalado y registrado antes del front.
Preparado en `/private/tmp/avancecorp-gd-f4-vista.chvRqh`; Main se sincronizó con
`avancecorp/main` preservando los trabajos ajenos. Evidencia y límites vigentes:
[PUBLICACION-2026-09-21.md](PUBLICACION-2026-09-21.md).

Miguel pidió contraer las otras seis opciones al seleccionar un resultado y poder
agendar desde el mismo formulario, como en la ficha del lead. Confirmó expresamente
«Sí, separar el resultado del descarte» y «Sí, probar únicamente en local».
Después autorizó expresamente ambas SQL productivas y `$release-crm`, y aprobó
e integró el PR #62. El permiso local inicial ya no es el estado de autorización vigente.

Es una ampliación transversal de F2 y de la pantalla del analista F3. No cierra F4.
En esta publicación se instaló también el SQL de su etapa 1; las etapas posteriores
conservan los pendientes del [plan principal](GESTION-DIARIA.md).

## Comportamiento entregado

Al elegir una de las siete opciones se conserva solo la elegida, con su foco y el
botón «Cambiar resultado». Abrir/cerrar la lista no borra la edición. Los atajos
1–7 funcionan con las opciones abiertas y no sustituyen el resultado cuando ya
está plegado, ni mientras se escribe o hay un guardado por confirmar.

«No le interesa» y «Pide otro producto» exigen motivo, pero no descartan por sí solos.
El analista puede conservar el lead y agendar llamada, WhatsApp, cita o tarea, o
solo registrar el resultado. Tipo, título, fecha y hora siguen el formulario de
la ficha; las citas reutilizan sus campos y validación de modalidad. Un título
editado por la persona no se pisa al cambiar de tipo.

La guía frontend-design ayudó a conservar el estilo del CRM y compactar el motivo
en un selector, dejando más espacio para la agenda, con texto de al menos 16 px,
footer siempre accesible y una sola columna en móvil.

Descartar requiere marcar «Descartar y enviar al Centro de rescate». No se envía
próxima acción junto al descarte; se conserva el motivo real y el deshacer admitido
por el servidor. Marcar «No volver a contactar» tampoco descarta automáticamente,
pero impide crear una próxima acción y no se revierte desde aquí. El oráculo
comprueba que un lead activo vetado no aparece como contacto recomendado en la cola.

Supervisor y gerencia conservan su ámbito y pueden registrar sin agendar por el
analista. Solo el dueño puede crear una próxima acción. Las restricciones
anteriores de los otros cinco resultados se mantienen.

## Servidor y compatibilidad

Migración instalada: `supabase/migrations/20260921153654_crm_resultado_llamada_seguimiento.sql`.
Puerta `crm.registrar_llamada_v4`, núcleo privado `private.llamada_registrar_v4`.
Componen los writers existentes de actividad/cierre y agenda en una transacción:
un error revierte todo. No se reescriben datos históricos, tablas, policies ni
objetos de `public`.

V3 y su núcleo siguen byte a byte. Los clientes anteriores conservan su contrato.
Un guardado v3 incierto se confirma desde «Guardados por confirmar», usando
directamente el comando, UUID y payload originales; no atraviesa el registrador
v4 ni se convierte en una nueva intención. No hay fallback silencioso a v3 si
falta instalar v4.

El gate nuevo sella cuerpos, propietario, search_path, volatilidad y privilegios.
Se compone desde F2, conservando todos los sellos previos y los paraguas F3/F4.
Los tipos v4 se obtuvieron del banco instalado, sin sustituir contratos ajenos.

La reversa restaura literalmente el gate F2 y retira solo las funciones nuevas.
Se ensayó con actividad, tarea y lead v4 reales: sus huellas no cambiaron. En
producción sería necesario coordinar antes el frontend y resolver recibos v4
inciertos. La instalación fue autorizada y completada; una reversa productiva
no está autorizada automáticamente por ese permiso y no se ejecutó.

## Verificación de implementación (previa a publicación)

Banco autorizado exclusivo: `gestion_diaria_f4_vista_chvrqh`, contenedor
`supabase_db_avancecorp-f5-bank`. Evidencia reproducible:
`supabase/scripts/resultado-llamada-seguimiento/ensayar.mjs`,
`test-seguimiento.sql`, `reversa.sql` y `verificacion.json`.

- PASS: oráculo v4 con rol real `authenticated`: conservar/agendar, los cuatro tipos,
  cierre de llamada más siguiente, descarte/deshacer, veto, permisos, replay exacto,
  tarea cambiada, cambio cierre→actividad libre, recibos v3 y horario de tarea interna.
- PASS: regresiones F2/F3/F4; 48 mutantes F1–F3, nueve de F4 y cinco nuevos v4;
  gates SLA, censo intacto, reversa con historia v4 y reinstalación determinista.
- PASS: generación local de la firma TypeScript v4.
- PASS: `check:scripts` y `test:edge-preflight`.
- PASS: `npm run check`: lint, tipos, 4.016 tests en 270 archivos, cobertura,
  configuración de release, build, bundle y duplicación (0,50 %).
  Las cuatro advertencias de accesibilidad preexistentes en coverflow no se tocaron.
- PASS: última corrida completa de `npm run test:e2e -- --workers=4`:
  231 recorridos aprobados, 26 omitidos por la suite, 0 fallos (4,3 minutos).
  Antes pasaron 52 recorridos focalizados. Los dobles HTTP y selectores antiguos
  se actualizaron a v4; el cierre se acredita con la corrida completa final,
  no con las corridas intermedias fallidas.
- PASS: capturas de escritorio (1440 px) y móvil (390 px) inspeccionadas;
  foco, contracción, título conservado, tipografía mínima y no desbordamiento.
- FAIL previo: el oráculo histórico F1 falla en J por su whitelist de metadata,
  anterior a F3. Se reprodujo con v4 retirada y tras reinstalarla. El gate F1 y
  sus diez mutantes sí pasan; no se presenta ese oráculo histórico como aprobado.
- NOT RUN: `seed:preflight`, `test:rls:preflight` y `gate:realidad` fuera del
  banco fijo, por falta de `SUPABASE_URL`. La validación SQL local no se confunde
  con Auth/HTTP remoto, datos reales ni una autorización para producción.

SHA-256 de la candidata:
`d863988a96bba84482b1ee0b387d5218dce44b896e69abfb6f2d1479778d8fc8`.
SHA-256 de reversa:
`96f83e4cfd718c4dbcbb95c333c9fb7c84cc1391b1346b75fc45e89189706fe3`.

## Revisión de Claude y decisión del PRIMARY

LEVEL 3. Se usó el wrapper restringido del repositorio, sin herramientas ni
escrituras del reviewer. La primera respuesta fue inválida/incompleta. El único
reintento terminó en `CHANGES_REQUESTED`, confianza MEDIA. No se atribuye un
PASS final de Claude.

Aceptado y corregido: la validación del dueño no puede bloquear un replay por
estado mutable; ahora exige `!reintento`. Test real del store con propietario
cambiado. También se conserva `p_tarea_id` y el contexto de una tarea que el
resync ya retiró de pendientes. La protección de atajos plegados y la región
de aviso de veto persistente se incorporaron.

La sospecha de bloqueo sin salida para v3 no se confirma:
`GuardadosSlaPendientes.verificar` llama a `confirmarPendienteSla`, que reenvía
`dato.comando` y `dato.argumentos` a `ejecutarComandoSla`, no al store.
El test MSW conserva la puerta y el UUID v3, después permite una operación v4 nueva.

La sospecha de replay con otra tarea se contrastó en PostgreSQL: el writer sellado
rechaza otra tarea existente y el cambio de cierre a actividad libre con 23505.
Una tarea inexistente queda rechazada antes por ámbito, 42501. No se duplicó esa
regla del writer en el núcleo v4.

`proximoSlotSugerido` ya propone las 10:00 de Lima y salta domingo; su código y
tests contradicen la hipótesis de una sugerencia ilegal. El oráculo confirma
que los CHECK/triggers existentes permiten el seguimiento nuevo sin descarte.
La cola excluye los leads con veto; no se forzó un descarte contra la decisión
expresa del usuario. La reversa y reinstalación acreditan el sello F2 literal.

El gate nuevo no se sella a sí mismo, como los otros gates compuestos del proyecto;
permanece privado y el control de cuerpos/ACL y sus mutantes pasa. No se amplió
esta tarea a rediseñar todo el sistema de sellos. El aviso de «Cambiar resultado»
controla las seis alternativas realmente retiradas del DOM y conserva la selección.

## Publicación y continuación

Instalación, registro, integración, CI y despliegue completados; no repetirlos.
Gates productivos F1–F4/v4 y SLA PASS, v3 y catálogo previo intactos. La revisión
adicional de Claude para publicar y su contraste con evidencia están en el acta
de publicación; no se atribuye un PASS final al reviewer.

Queda el recorrido de uso normal con analista y supervisor, no un guardado ficticio
en producción. Retomar F4 etapa 2 desde el plan, aprovechando el detalle y registro
ya disponibles. No retirar v3 mientras existan clientes o recibos que dependan de
ella; una reversión requiere coordinar guardados inciertos. F4 completa sigue abierta.
