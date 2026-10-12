# Llamadas desde el celular - revision conjunta PR 232 y 249 (2026-10-10)

Relacionado: [[Inicio]], [[Llamadas desde el celular - instalacion y publicacion (2026-10-07)]], [[Llamadas desde el celular - revision PR 243 (2026-10-10)]], [[Llamadas desde el celular - reparto con Jhosep y analisis H-P5 H-P10 (2026-10-09)]].

## Estado verificado

- #232 cerrado/fusionado (`a0784659`), H-WA publicado y aceptación física ya registrada. El comentario 6098858656 aporta la repetición P5 solicitada: PWA carga completa al abrir B, pierde encuesta/nota A; ambas llamadas permanecen pendientes. Turno nuestra sesión para H-P5 y H-P10. No implementados aún; no pedir otra repetición diagnóstica igual. Conservar leads de prueba.
- #249 abierto, cabeza `e428da3abf980b115cc133c4268c45b469be235f`, documentos F4-e y soporte F7.2.2. Main remoto `5616d1e8`. Veredicto Codex CHANGES_REQUESTED. No hubo comentario, aprobación, merge ni despliegue en esta revisión.

## Correcciones requeridas

1. P2: contrato exige `requiere_resultado` para pendientes, pero Deshacer conserva `registrado` y enlace a resultado deshecho; una llamada de hoy queda total1/categorías0. Definir clasificación derivada, prueba O9 y retención de antiguas deshechas.
2. P2: SOPORTE §2.2c promete volver a «Elegir el lead», pero `accionPrincipal` oculta la opción tras identificar. Documentar límite o implementar en otro PR.
3. P2: SOPORTE §2.2a presenta como completo registrar llamada reasignada del analista anterior. La pantalla usa v5 y el enlace exacto devuelve `celular_ajeno`; guardar actividad no resuelve la llamada. Aclarar y diseñar el recorrido, sin relajar permisos por la redacción.
4. D4 debe exigir misma cifra del mismo analista entre supervisor y gerencia. Diferentes conjuntos de equipo pueden cambiar totales; no los conteos individuales. Agregar caso de supervisores anidados.
5. La purga no limita toda la tabla a30 días/~60k: las registradas incluso deshechas se conservan. O13 de1h/8h no detecta umbral6hvs7h; usar6h30/límites.

## Decisiones recomendadas (aún no respuestas de Miguel)

- Sí a construir F4.2.4 por Jhosep; nuestra sesión mantiene H-P5/H-P10.
- H-PERMISO: diagnóstico dentro de F4-e/F6; «número vacío» sigue hipótesis.
- Ratificar alcance unaSIM/sin internacionales y trasladar ocultos/entrantes a#14; no contarlos como pruebas realizadas.
- Sí a redactar aviso de tratamiento antes de C2/C3, para revisión posterior.
- Miguel debe indicar disponibilidad/fecha C2/C3; Pro corporativo hastaS/57 ya autorizado. Piloto5d sigue pendiente.
- F7.2.3: reconocer evidencia parcial, no cerrar apagados independientes con P11/P6/P7/P1.
- D1–D3 recomendados sí; D4 corregir; D5 precisar retención existente y excepción de enlazadas/deshechas. Primero corregir contrato, luego preparar/probar migración. No autorización implícita de producción.
- Jev sigue apagado.

## Evidencia y límites

Checks CI PASS4; diffcheck/JSON/regeneración idéntica PASS. Conteo46/102 consistente (solo añadeF7.2.2), pero el cierre documental requiere corregir sus instrucciones. Modelo de predicados reproduce total1/suma0; no es SQL nuevo ejecutado. No se repitió suite completa ni pruebas físicas por PR documental. CodeGraph consultado y complementado al no devolver SQL pedido. Claude wrapper falló sin dictamen dentro/fuera sandbox: NOT RUN, nuncaPASS.

Informe detallado local: `/private/tmp/avancecorp-pr249-review-20261010/REVISION.md` y `checks.json`. Checkout compartido preservado.

- https://github.com/avanza-digital/avancecorp-crm/pull/232#issuecomment-6098858656
- https://github.com/avanza-digital/avancecorp-crm/pull/249#issuecomment-6100294484

## Confirmaciones de Miguel — 10/10/2026

Miguel confirmó expresamente en esta conversación:

- **Alcance del piloto:** una sola SIM por celular corporativo y sin llamadas internacionales. Esta ratificación permite documentar doble SIM e internacionales como fuera de alcance; no equivale a pruebas ejecutadas. Ocultos/entrantes continúan en el alcance pendiente de #14.
- **Disponibilidad C2 y C3:** **lunes 12 de octubre de 2026**. Primero indicó «lunes 13»; se aclaró que el 13 es martes y respondió explícitamente «Lunes 12 de octubre». Usar el 12 como fecha confirmada. Disponibilidad no significa activación, aceptación ni piloto terminado.

Estas respuestas confirman únicamente alcance y fecha. Las restantes recomendaciones del review no se convierten por ello en una aprobación general de #249, de su fusión ni del despliegue de la futura migración. No se envió comentario a GitHub con estas confirmaciones en este turno.

## Informe enviado a Jhosep — 10/10/2026, 13:51 Lima

Miguel pidió «ok mandale todo». Se publicó **un único comentario en #249** con los tres P2, ajustes D4/retención/O13, recomendaciones a los siete puntos, confirmaciones de una SIM/sin internacionales y disponibilidad C2/C3 el lunes12/10/2026, reparto H-P5/H-P10/F4.2.4 y resultados/límites de verificación. Las recomendaciones técnicas quedaron identificadas aparte de las dos confirmaciones personales.

https://github.com/avanza-digital/avancecorp-crm/pull/249#issuecomment-6100999198

Cabeza remota comprobada antes de enviar: `e428da3abf980b115cc133c4268c45b469be235f` (abierto). El cuerpo publicado se volvió a leer y coincide íntegramente con el preparado. Turno de Jhosep: corregir #249 y devolver cabeza para revisión focalizada. Sin aprobación formal, merge ni despliegue; no se duplicó el comentario en #232.
