# Evaluación de la revisión independiente

Codex es PRIMARY. Claude actuó como SECONDARY_REVIEWER mediante el wrapper del
proyecto, sin herramientas, MCP ni escritura. Dictamen del 09/09/2026:
**CHANGES_REQUESTED**, confianza media. No se pidió otro dictamen para obtener
un PASS. Los checks posteriores son del PRIMARY.

| Hallazgo | Decisión y evidencia |
| --- | --- |
| P1: posible omisión de guardias para cliente conocido; faltaba el wrapper | Hipótesis descartada con la definición viva: `crm.convertir_lead_con_domicilio(uuid,uuid,text)` llama primero a `crm.convertir_lead`. La firma de tres argumentos de `marcar_efectos_conversion` delega a la de uno tras validar identidad/claim/token. Se incluyeron el wrapper y `responder_tope_tasa_fn` en el preflight. Prueba de `ya_existia`, wrapper real, conversión y consumo de aprobación al contratar: PASS. |
| P1: posible fallo de Gerencia con `cliente_id=null` | La bandeja ya estaba modificada en el diff y usa `s.id` para resolver y `cliente_nombre` para mostrar. Se añadió un test de render y aprobación de lead sin cliente: PASS. El historial obtiene el nombre del lead desde el lector SQL. |
| P2: el autor pierde acceso al tope al reasignar | Aceptado. Se conserva su solicitud en su propia bandeja, como en el flujo anterior de clientes. No recupera acceso a la ficha ni puede el nuevo analista responder en su nombre. La UI identifica quién debe responder. Prueba de reasignación, lectura del autor/supervisor, rechazo de suplantación y aceptación: PASS. Se rechazó saltar el bloqueo según quién esté conectado. |
| P2: solicitud sin documento no fija identidad | Aceptado. La solicitud especial exige completar el DNI del lead; consultar/usar la base sigue disponible. La Edge rechaza un documento distinto antes de reservar o crear Auth. SQL sin DNI no deja petición parcial; ambos modos de Edge rechazan cambio de documento antes de efectos: PASS. |
| P2: pendientes de lead inactivo desaparecen de Gerencia | Aceptado. Gerencia y lector global conservan lectura de solicitudes de leads inactivos. La puerta de envío sigue exigiendo lead activo, abierto y asignado. Lectura y rechazo por Gerencia con lead inactivo: PASS. |
| P3: RLS fuera de preflight | Aceptado. Se comprueban comando, rol, carácter permisivo, ausencia de `WITH CHECK` y expresión exacta bajo `search_path=''`, con candados ya tomados. Política alterada rechazada antes de DDL; rollback y aplicación correcta posterior: PASS. |
| P3: error PGRST202 expuesto | Aceptado: 503 con texto de reintento, sin nombre de función interna y sin efectos en ambos modos. Pruebas Edge: PASS. |
| P3: vigencia sellada distinta de la actual | Se conserva la recuperación de la saga: iniciados los efectos, la conversión puede concluir con la validación del sello; el contrato exige vigencia actual en R4. El comentario de `private.validar_tasa_conversion_lead` lo explicita. No se amplía el plazo para contratar ni se consume la autorización al convertir. |
| P3: motivo del botón no asociado para accesibilidad | Aceptado: `aria-describedby` enlaza el botón de conversión con su motivo visible. |

No hubo una segunda revisión que certificara las correcciones. El PRIMARY cerró
los hallazgos con definiciones vivas y ejecución. El ensayo remoto sigue pendiente.

## Verificación posterior

- PASS: `npm run check`, 222 archivos y **3.136 pruebas**, lint, tipos, build,
  configuración de release, presupuesto de bundle y duplicación.
- PASS: **38 pruebas enfocadas** de condiciones, tasa y bandeja de Gerencia.
- PASS: Edge **67 Node + 5 Deno** y comprobación estática Deno.
- PASS: **15 grupos SQL**, incluido cliente reconocido, DNI, reasignación e inactivo.
- PASS: **dos sesiones SQL reales**; la conversión espera la solicitud rival,
  recibe P0411 y no deja reserva parcial.
- PASS: reversión sin uso, rechazo de política alterada y reaplicación.
- PASS: recorrido Playwright a 1.440/390 px tras los ajustes.
- NOT RUN: rama remota, matriz RLS completa, advisors y publicación de esta función.

Límite conservado: si el autor de un tope ya no puede operar, no se concede a otra
persona la facultad de responder en su nombre; rige la caducidad existente.
Añadir cancelación o transferencia de esa respuesta sería otra decisión.
