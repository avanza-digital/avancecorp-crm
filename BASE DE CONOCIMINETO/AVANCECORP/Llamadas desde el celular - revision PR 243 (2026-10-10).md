# Llamadas desde el celular - revisión PR 243 (2026-10-10)

Relacionado: [[Inicio]] · [[Llamadas desde el celular - correcciones PR 235 con Claude (2026-10-09)]] · [[Llamadas desde el celular - auditoria de fases y pruebas S1-S3 (2026-10-09)]].

Miguel pidió analizar [PR #243](https://github.com/avanza-digital/avancecorp-crm/pull/243) y decir si podemos seguir. Revisada cabeza **b0398d6bb3f9c298c72189d96b4bbff2ee505d30**, base main **141eb25f**. Nueve documentos; sin cambio de código/SQL/Edge. Dictamen **CHANGES_REQUESTED**, sin P0/P1: se puede continuar desarrollando, con tres ajustes antes de fusionar.

- **P2, SOPORTE:64:** la recuperación de H-ESPERA debe revisar Pendientes y descartar por Error de captura el evento falso de la entrante en espera, si existe. Cerrar la encuesta no lo retira. El caso de lead se deduce de código; la prueba física usó números sin lead.
- **P3, SOPORTE:63:** quitar «el número llega vacío» como causa demostrada de H-PERMISO. Está demostrado el fallo observable, no si se interrumpen disparadores o envío. Una traza focalizada antes de diseñar el detector; contar filas en la tabla de eventos no detectaría avisos ignorados antes de insertar.
- **P3, estado.json:48:** retirar Ahorro de energía de pendientes F0.3.3: S3, F3.4.1 y SEGUIMIENTO lo acreditan PASS. Regenerar documentos, no repetir pruebas.

Claude por wrapper, SECONDARY_REVIEWER: **CHANGES_REQUESTED**, coincide. Codex acepta los tres puntos y evita otra afirmación sin prueba («no manda aviso»). Primer intento restringido falló; el segundo terminó correctamente.

**PASS:** JSON, 102 IDs únicos, 45/102, 2/8; done/estado e historial previo intactos; regeneración sin diferencias; referencias y diff --check. GitHub preflight/cambios/app-check/verify PASS. **NOT RUN aquí:** build/suite local/E2E/C1 físico; solo documentación. Confirmada la falta de E2E de circuito y F4-c con dobles; los de demo sí existen.

Siguiente: F4.2.4 (enlace manual, sin duplicar actividad), H-P10 y contrato/oráculos F4-e pueden avanzar. H-PERMISO requiere traza; H-P5 captura focalizada. Ratificar exclusiones doble SIM/internacional, corregir aviso antes de C2/C3 y completar las pruebas físicas restantes/cinco días. Jev OFF. No se fusionó ni se comentó el PR; se preservó el checkout compartido.

Informe y evidencia: `/private/tmp/avancecorp-pr243-review-20261010/REVISION.md`, `VERIFICACION.txt`, `claude-review.txt` y `diff.patch`. Trabajo de lectura en copia aislada `/private/tmp/avancecorp-pr190-correcciones-20261006`, limpia.

## Actualización: correcciones comunicadas a Jhosep

Miguel autorizó informar a Jhosep. [Comentario único publicado en #243](https://github.com/avanza-digital/avancecorp-crm/pull/243#issuecomment-6099061758). Antes de publicarlo se comprobó la nueva cabeza **8b90129e**: F0.3.3 ya corrige ahorro de energía y registra noche 09→10 PASS; P5 focalizada también está entregada. El P3 de ahorro de energía queda RESUELTO.

Pendientes comunicados: P2 de recuperación del evento falso de H-ESPERA y P3 de distinguir el HTTP 202 de una prueba de número vacío. La nueva traza de las 18:37:41 ya acredita envío: no se pide repetirla para averiguar si hubo petición. Si el autor comprobó además la variable/cuerpo vacío, basta documentarlo sin PII; de otro modo, identificarlo como hipótesis. Pedidos dos ajustes y regeneración documental, sin repetir P1–P15, noche ni P5. Recomendaciones de continuidad no equivalen a aprobación de SQL ni cambios de alcance. No se fusionó.

## Revisión final solicitada por Miguel — PASS (10/10)

Cabeza **f6bbc7796b1d9e949de20a36af00432eacdce742**; correcciones propias en **b3def589**. GitHub confirma #243 **fusionado por miguejbs98 a las 15:53:42 UTC / 10:53:42 Lima**, commit main **8a71317c635baa0da1ec82c3d50224d7d9b7702f**. La integración de main trajo cambios ajenos de #247; el diff propio del #243 frente a su base 426499c3 sigue siendo solo los nueve documentos. No se atribuyen aquellos cambios al #243 ni se declara revisado #247.

Los tres hallazgos anteriores quedan resueltos: H-ESPERA incluye descarte por Error de captura; H-PERMISO identifica el número vacío como hipótesis y precisa qué demuestra el 202; ahorro de energía ya no figura pendiente. Documentos resultantes en main idénticos a la cabeza revisada.

**PASS:** JSON; 102 IDs, 45 hechas, 2/8 fases; estados e historial conservados; generador sin diferencias; diff --check. GitHub en la cabeza final: verify/app-check/cambios/preflight PASS, Preview omitido. NOT RUN local build/suite/E2E/C1: revisión de correcciones documentales. Sin nueva consulta a Claude: cambios pequeños aplican exactamente los hallazgos ya contrastados; no se le atribuye una segunda aprobación.

Propuesta de Jhosep para F7.2.3 (comentario 6099201393): reutilizar P11 para invalidez de clave/cola, P6/P7 para registro desde pestaña y P1 para envío retenido como evidencia parcial. No equivalen por sí solos a probar apagado independiente de captura, apertura y Jev, que es el texto de F7.2.3. Cerrar una encuesta no acredita apagar su apertura automática; detener envío no acredita apagar captura. Mantener pendiente F7.2.3 hasta cubrir únicamente lo que falta.

ACTIVAR-C1.md §6 nivel 1 todavía promete enlace manual que no existe: la limitación es previa, reconocida por Jhosep, y se debe corregir al continuar F4.2.4. Recomendación siguiente: enlace manual F4.2.4 y arreglo H-P5 con la captura ya recibida; H-P10 y contrato F4-e conforme al reparto. No repetir noche/P5/P1–P15 para cerrar este PR ni encender Jev. El plan completo sigue pendiente.

Evidencia final en `/private/tmp/avancecorp-pr243-review-20261010/revision-final/`. Checkout compartido preservado; no se modificó producto, se fusionó ni se publicó desde esta sesión.
