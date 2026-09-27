---
tags: [crm, auditoria, claude, plan, multiempresa, ranking]
fecha: 2026-09-26
estado: auditoría de plan recibida; ajustes documentados; producto pendiente
---

# Auditoría Claude — plan inversión por empresa

## Resultado y alcance

Miguel pidió una auditoría con Claude y un plan completo por fases. Codex actuó
como PRIMARY, único escritor; Claude fue SECONDARY_REVIEWER aislado por
`scripts/claude-review`, sin herramientas ni cambios de archivos.

**VERDICT: CHANGES_REQUESTED. Sin P0. Confianza MEDIA.**
Tres P1, cuatro P2 y dos P3 sobre diseño, alcance y comprobaciones pendientes.
No constituye un hallazgo probado de tres fallos productivos ni una aprobación de release.

Plan resultante: [[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]].

## Evidencia y límites

- Fuente de código inspeccionada: commit publicado del ranking
  `526d6d90c621e4072251818d1325b7bd0c01b2ca`, copia limpia existente.
- Root modificado por otras tareas: conservado. Solo se modificó el plan propio
  y se creó esta acta; no hubo implementación, commit, SQL ni publicación.
- CodeGraph consultado primero; devolvió principalmente símbolos ajenos a los
  escritores buscados. Se complementó con lecturas puntuales, sin reindexar.
- Se adjuntaron evidencia saneada, decisiones del vault y fuentes/rangos concretos.
  No se mandaron documentos de clientes, cuentas, correos ni secretos.
- No se consultó producción nuevamente para este plan. La evidencia de datos
  proviene de la intervención verificada del 26/09. F0 exige revalidación viva.
- Las migraciones citadas como base pueden tener cambios posteriores dinámicos:
  no se certifica que su cuerpo sea hoy idéntico al instalado.
- Hubo tres invocaciones técnicas: la primera no completó en el sandbox; la
  segunda fue rechazada por el wrapper por respuesta incompleta/sin VERDICT;
  la tercera entregó un resultado válido (exit 0). Solo un dictamen aceptado.
  No se insistió para obtener un PASS ni se omitió el wrapper.
- Encargos y salida originales locales: `/private/tmp/plan-empresa-review.BlPOE0/`.
  El dictamen íntegro se conserva abajo. La versión final del plan incorpora la
  evaluación de PRIMARY; no tuvo una segunda aprobación de Claude.

## Resolución de PRIMARY

| Hallazgo | Evaluación y tratamiento |
|---|---|
| P1: Cartera podría quitar el canal a los tres enlaces corregidos | Hipótesis, no regresión acreditada. El SQL aplicado previamente, `releases/ranking-enlaces-20260926/enlazar-produccion-v2.sql:75`, rechazaba cualquier operación de cartera para esos contratos; el resultado registrado fue 3 enlaces. F0 lo reconfirma. A queda acotada a Avance nuevo/sin origen con ledger inequívoco. Lead directo/canal conocido contradictorio sale a revisión, no se reclasifica silenciosamente. |
| P1: contexto interno COOPAC | Aceptado. Núcleo privado con modalidad/fuente validada, sin parámetro público de bypass; solicitud y vínculo atómicos. No insertar antes un vínculo cuya FK exige solicitud. Incluir el cruce con venta cruzada, cuya API da prioridad a otra puerta. |
| P1: orden de bloqueos | Aceptado como entregable obligatorio antes de implementar F3. Tabla de recursos/orden por todas las rutas, clave persona canónica/empresa y pruebas entre sesiones/fusión. No adoptar literalmente «replay antes de todo»: siempre exige autorización y guardas vigentes. El orden concreto se contrasta con cuerpos vivos; no se certifica seguridad por el pseudoflujo del reviewer. |
| P2: activación | Aceptado el control explícito y auditado. No aceptar automáticamente tabla nueva en `private` ni facultad nueva de Superadmin: el repo manda tablas nuevas en `crm`, RLS y mínimos privilegios. Reutilizar configuración si es apta y serializar encendido con confirmaciones. |
| P2: clave de join desconocida | La hipótesis de depender de inversiones se descarta en el schema inspeccionado: `20260824231133_crm_gestion_clientes_renovaciones_conversion.sql:86` declara `contrato_nuevo_id NOT NULL UNIQUE REFERENCES public.contratos(id)`. El SQL productivo anterior usa la misma columna. Se documenta esa clave y su verificación viva, no un join por espejo. |
| P2: rollback desde cuerpo vivo | Aceptado. F0 conserva definición exacta, hashes, owner, grants y dependencias; reversa ensayada. No reconstruirla desde una migración vieja. |
| P2: cooperativas en entrega A | Aceptado. A no modifica la rama COOPAC y prueba su igualdad; continuidad COOPAC se decide para B. |
| P3: recuperar pendientes | Aceptado. Acción independiente «Solicitudes pendientes» en ficha/contexto autorizado, aun sin botón de nueva inversión. |
| P3: corrección de solicitud | Aceptado. Inventariar comportamiento actual; conservar correcciones legítimas revalidadas y aprobar restricciones adicionales explícitamente. |

La ampliación añade línea base, matriz comercial, lectura única, escritores,
seguridad, compatibilidad de parsers, concurrencia, migraciones, todas las
entradas de pantalla, pruebas por entrega, activación, rollback y observación.

No quedan declaraciones de «listo para publicar». Quedan gates explícitos de
implementación, decisiones de regreso/historia válida y autorización de puertas
compartidas. Se puede ejecutar A sin esperar las decisiones comerciales de B.

## Verificación de esta tarea documental

- PASS: wrapper entregó VERDICT válido en el último intento.
- PASS: formato básico del plan, ausencia de whitespace final, enlaces del vault
  y existencia de los comandos npm citados (validación local).
- PASS: contraste de las dos hipótesis de datos con schema y evidencia guardada.
- NOT RUN: tests de producto, RLS, E2E, build, ensayo de migraciones y postflight
  nuevo; no hubo cambios ejecutables. Son gates futuros, no resultados heredados
  de otras entregas.
- La validación documental no acredita la implementación futura.

## Reanudación — comprobación de solo lectura, 26/09 19:14 Lima

Tras «sigamos», se releyó el punto de retoma y se consultó la base con
`BEGIN READ ONLY`. No se implementó ni aplicó SQL de cambio.

- Septiembre continúa sin sellar.
- Los contratos 001385, 001412 y 001420 conservan un lead directo cada uno,
  sin operación de cartera: la corrección excepcional no necesita repetirse.
- Los contratos 001400, 001425 y 001445 conservan categoría `nuevo` y operación
  `upgrade`, sin lead directo; suman PEN 150.000. El primero sigue sin espejo
  en `crm.inversiones`; los otros dos sí lo tienen.
- El lector vivo sigue clasificando por categoría contractual, sin consultar
  `operaciones_cartera`. MD5 del cuerpo: `52ecf49a1c698e135a531b38ab75e291`;
  definición completa: `238bf7b04b2d5df640ae45815344ccaa`.
- Los cuerpos de capital/producción conservan sus huellas de referencia:
  `214c6bada3dc63f553d7f9b62fd7963c` y `ecfdf7e030497af2f299ba327102a5ea`.
- El árbol principal tiene trabajo ajeno y avanzó a `4c3c1996`; se preservó.
  La copia publicada existente sigue limpia en `526d6d9`.
- El desglose vivo de Betzabeth confirma PEN 72.450 y USD 30.000 en Walking,
  PEN 283.000 en Referido y PEN 150.000 sin origen.
- Inventario preliminar de septiembre: 12 operaciones candidatas al mismo
  criterio (8 PEN por 2.092.254 y 4 USD por 54.971), incluidas las tres de
  Betzabeth. No son 12 correcciones aprobadas: faltan la validación individual,
  las exclusiones/contradicciones y el manifiesto definitivo exigidos por F0.

Esto cubre únicamente la revalidación inicial de A, no toda F0 ni el inventario
de puertas de B. Autorización de implementación/SQL/publicación no se da por
deducida de estas consultas. Las pruebas de producto siguen NOT RUN.

## Dictamen íntegro recibido

```text
VERDICT: CHANGES_REQUESTED

SUMMARY:
El plan es sólido en alcance, separación A/B y disciplina de release. No hay P0. Quedan huecos de diseño que, sin cerrarse antes de implementar, invalidan la aceptación: precedencia Cartera vs enlace directo de lead (riesgo de deshacer la corrección del 26/09), mecanismo concreto del contexto interno para la reinversión COOPAC, orden de bloqueos no definido, control de activación sin diseño, rollback de A sin captura del cuerpo vivo y clave de join de `operaciones_cartera` no verificada.

FINDINGS:

[P1] Precedencia de A puede reclasificar los enlaces ya corregidos
File: migrations/20260925190000_crm_ranking_origen_vendedor.sql
Lines: 49-56, 85
Problem: Hoy Cartera solo aplica si `categoria != nuevo`; después va lead directo, perfil y desconocido. El plan (Fase 2, «Implementación A») propone «evidencia de upgrade ligada a la operación → Cartera; luego reglas vigentes». Un contrato con lead directo recién enlazado Y operación upgrade cambiaría de Referido/Walking a Cartera.
Evidence: Sección «Ya completado»: S/ 60.000 Referido y S/ 32.450 Walking por enlaces puntuales. El plan dice «preservar los enlaces» pero la precedencia propuesta no lo garantiza.
Impact: Deshacer silenciosamente la corrección autorizada del 26/09; la aceptación «fuera del manifiesto idéntico» detectaría el efecto solo a posteriori.
Recommendation: Fijar la regla en F1: para contratos con lead directo enlazado y operación upgrade, decidir cuál gana; verificar en F0 si alguno de los tres contratos corregidos tiene fila upgrade en `operaciones_cartera`.

[P1] Contexto interno COOPAC sin mecanismo definido
File: migrations/20260910150039_crm_f6_postventa_persona.sql
Lines: 671-700
Problem: `preparar_reinversion_fn` llama a `preparar_inversion_fn` (697) antes de insertar el vínculo de origen (698-699). El plan (3.2) reconoce que un candado ingenuo rompe reinversiones, pero no dice cómo se distinguirá la llamada interna: la única pista disponible es `private.inversion_preparar_nucleo` (20260924, 649-695).
Evidence: El trigger 704-725 revalida el origen tras el insert, no antes de la preparación.
Impact: O la regla rompe reinversiones legítimas de Qorilazo/Prodelco, o se introduce un bypass reutilizable.
Recommendation: Especificar que el candado vive en el núcleo privado con parámetro interno no expuesto, o reordenar la reinversión para insertar el vínculo antes; añadir test de reinversión COOPAC con regla activa.

[P1] Orden de bloqueos y punto de aplicación no definidos
File: migrations/20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql
Lines: 565-598
Problem: La confirmación bloquea la solicitud `FOR UPDATE` y hace replay de confirmadas. El plan propone «bloqueo por persona canónica y empresa» y «coordinar orden con solicitud, fusión y cierre mensual», sin fijar ese orden ni la clave.
Evidence: Dos solicitudes «nuevo» preparadas antes de activar el control pueden confirmarse en sesiones distintas; la relectura sin lock común no evita dos primeras inversiones.
Impact: Interbloqueos o doble primera inversión en la misma empresa.
Recommendation: Definir: (1) replay de confirmada antes de todo; (2) `FOR UPDATE` de solicitud; (3) advisory lock transaccional por (persona canónica, empresa) resuelto tras el paso 2; (4) relectura de historia y escritura. Documentar interacción con fusión de identidad (el id canónico puede cambiar).

[P2] Control de activación sin diseño
File: Plan, Fase 6 «Orden de instalación y activación B», punto 1
Problem: «control explícito probado y auditado, si el diseño lo necesita». No se define tabla, RLS, quién puede alternarlo, auditoría ni si se lee dentro de la misma transacción.
Evidence: El plan exige a la vez rechazar booleanos del cliente (3.2) y transición para pestañas antiguas.
Impact: Riesgo de flag legible/escribible por rol inadecuado o de estados inconsistentes entre preparar y confirmar.
Recommendation: Decidir en F1 si el control existe; si sí, tabla `private` con lectura en el núcleo, cambio solo por Superadmin con evento de auditoría.

[P2] Clave de join de `operaciones_cartera` no verificada
File: Acta 26/09 (evidencia PRIMARY)
Problem: Un contrato de Betzabeth carece de espejo en `crm.inversiones`. Si `operaciones_cartera` vincula por inversión y no por contrato, el join de A pierde S/ 120.000, 10.000 o 20.000.
Evidence: La evidencia afirma que los tres están «linked», pero no indica la columna de enlace.
Impact: La aceptación de S/ 150.000 no se cumpliría o se cumpliría por casualidad.
Recommendation: Registrar en F0 la clave de enlace y verificar que las tres filas resuelven por contrato.

[P2] Rollback de A sin captura del cuerpo vivo
File: Plan, Fase 0 y Fase 6 «reversa compatible»
Problem: El plan advierte que la última migración no contiene el cuerpo vivo de `private.ranking_capital_origen_filas`, pero la reversa no exige capturarlo.
Impact: Revertir al cuerpo de la migración base reintroduciría cambios posteriores desconocidos.
Recommendation: En F0 guardar `pg_get_functiondef` del lector vivo y usarlo como script de reversa.

[P2] Alcance de la rama COOPAC en A
File: migrations/20260925190000, Lines 111-131
Problem: Si el criterio «upgrade en operaciones_cartera → Cartera» se aplica globalmente, reinversiones COOPAC cambiarían de canal aunque el plan las difiere.
Recommendation: Restringir A a la rama Avance salvo decisión explícita; incluir el conteo COOPAC en el manifiesto.

[P3] Recuperación de pendientes al ocultar el botón
File: app/src/components/app/inversion-nueva.tsx, Lines 316-322
Problem: La recuperación por referencia vive dentro del diálogo de «Nueva inversión». Ocultar el botón elimina esa entrada. El plan (F4) exige que siga accesible, sin nombrar la superficie.
Recommendation: Definir la superficie concreta antes de la preview.

[P3] Corrección de solicitud
File: app/src/data/inversion-solicitud-api.ts, Lines 49-55
Problem: El plan prohíbe cambiar persona/empresa/tipo al corregir. Si la RPC actual lo permite, es cambio de comportamiento que requiere inventario y aprobación.

TEST GAPS:
- Reinversión COOPAC con la regla activa (ruta interna y ruta directa manipulada).
- Dos sesiones confirmando dos solicitudes «nuevo» preparadas antes de la activación.
- Contrato con lead directo y operación upgrade: clasificación esperada explícita.
- Flag desactivado vs activado en la misma solicitud entre preparar y confirmar.
- Parsers JSON estrictos del frontend servido contra la salida real de A.
- Cierre mensual ejecutado entre instalación de A y postflight.

RECOMMENDED NEXT ACTIONS:
1. Cerrar en F1 la precedencia lead directo vs upgrade y verificar los tres contratos corregidos.
2. Diseñar el candado en el núcleo privado y el orden de bloqueos; añadir a 3.2 con casos de prueba.
3. En F0: clave de enlace de `operaciones_cartera`, cuerpo vivo del lector, inventario de `crear_contrato` y `crear_contrato_con_cuenta_pdf_v2`.

CONFIDENCE:
MEDIUM. Sin acceso al cuerpo vivo de las funciones ni al esquema de `operaciones_cartera`, varios hallazgos son hipótesis verificables en F0.
```

Relacionado con [[Ranking - enlaces excepcionales y propuesta por empresa (2026-09-26)]],
[[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]] y
[[Venta cruzada - servidor probado en banco y P1 del PDF (2026-09-24)]].
