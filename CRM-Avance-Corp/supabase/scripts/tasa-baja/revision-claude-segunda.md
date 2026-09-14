VERDICT:
CHANGES_REQUESTED

SUMMARY:
Las cuatro correcciones cierran los P2 de la revisión previa en lo esencial:

- **Precisión:** se valida en `public.crear_contrato` antes del INSERT a `numeric(5,2)`, con prueba desde `crear_contrato_con_cuenta_pdf_v2` como `authenticated`.
- **Preselección:** la incompatibilidad cubre ambos extremos y es pegajosa.
- **Reversa:** detecta reservas comprometidas sin contrato.
- **Edge:** transporta `condiciones_tasa` sin comparar contra la base.

Con lo adjunto no veo P0 ni P1. Si otra puerta aún compara contra la base, fallaría cerrada (rechaza) y no abierta; el riesgo residual es de disponibilidad, no de seguridad.

Quedan tres cosas:

- **P2 (hipótesis):** una carrera en la reversa. Contradice el comentario «Impide que una escritura se confirme…».
- **P3 (hecho):** una regresión de mensaje introducida por la corrección 2.
- **P3 (hipótesis):** otras rutas de INSERT sin la validación de precisión.

Nada de esto exige cambiar la migración.

FINDINGS:

[P2] La reversa puede dejar pasar una reserva a 12.5 ya validada por la versión nueva (hipótesis)
File: `supabase/scripts/tasa-baja/verificar-local.py`, bloque `rollback` (genera `revertir-antes-del-primer-uso.sql`)
Lines: `lock table public.contratos,crm.conversion_reservas,crm.ledger_rentabilidad in share row exclusive mode;` y el `$preflight$` siguiente
Problem: `SHARE ROW EXCLUSIVE` bloquea el INSERT/UPDATE (`ROW EXCLUSIVE`) en `crm.conversion_reservas`, pero no bloquea lo que ocurre antes. Supongamos que `crm.reservar_conversion_lead` o `reservar_conversion_lead_tasa_fn` ejecutan `private.validar_tasa_conversion_lead` antes de su primera escritura a `conversion_reservas`. Si además solo toman `FOR UPDATE` (`ROW SHARE`, que no entra en conflicto) sobre `crm.leads` o sobre la propia tabla, pasa esto:
1. Una transacción concurrente valida 12.5 con el cuerpo nuevo.
2. Se queda esperando el lock.
3. La reversa confirma.
4. El INSERT de la reserva se confirma después.

Resultado: una reserva a 12.5 bajo el candado antiguo, justo el estado varado que este preflight quería impedir.
Evidence: con la migración aplicada, la secuencia del test `$conversion$` es validar → reservar. No se adjunta el cuerpo de `reservar_conversion_lead`, así que no puedo confirmar el orden validación/escritura ni si toma un lock que choque con `SHARE ROW EXCLUSIVE`. `contratos` no tiene el problema: el trigger se reevalúa al adquirir el lock, tras procesar la invalidación del catálogo, y usaría el cuerpo restaurado.
Impact: la ventana es pequeña, la operación es manual y ocurre antes del primer uso. Aun así, el efecto sería un lead convertido o sellado sin posibilidad de crear su contrato (P0410).
Recommendation: elegir una de estas opciones:
- confirmar con el `prosrc` de `reservar_conversion_lead` y `reservar_conversion_lead_tasa_fn` que escriben o bloquean en modo conflictivo antes de validar;
- en la receta, congelar primero la escritura con la bandera existente (`inversiones_escritura`, que usa `private.inversiones_escritura_bajo_candado()`) y reejecutar la consulta del preflight después del `commit`, como verificación posterior.

En cualquier caso, suavizar el comentario del lock.

[P3] Con una preselección mayor que la base, el bloqueo muestra el motivo equivocado mientras cargan o fallan las solicitudes
File: `app/src/components/app/tasa-politica.tsx`, `preseleccionIncompatible` y la cadena `bloqueoContrato`
Problem: `maximo = autorizada ? solicitud!.tasa_maxima_autorizada : base`, y `solicitud` es `null` mientras `solicitudes.isPending` o `solicitudes.isError`. Con `tasaPreseleccionada=17` y una autorización real a 18, `preseleccionIncompatible` es `true` en esos estados. Como esa rama va antes que `solicitudes.isPending` y `solicitudes.isError` en `bloqueoContrato`, se ven dos mensajes a la vez:
- el texto «La tasa acordada ya no está dentro del rango vigente. Cierra este formulario…», también anunciado en `role="status"`;
- el botón «Reintentar solicitudes».
Evidence: antes de esta corrección solo existía `tasaPreseleccionada < minimo`, que no se activaba para 17. El test nuevo «una autorización que ya no cubre la tasa acordada…» renderiza sin solicitudes y fija este mensaje. Ningún test cubre 17 con `solicitudesPending` o `solicitudesError`, a diferencia del test de 12.5.
Impact: no altera la tasa, porque ambos effects retornan temprano. Pero ordena abandonar el formulario ante un fallo de red transitorio. Además, en el caso real de base bajada, existe una salida: «Solicitar tasa superior» (`puedePedir` no depende de `bloqueoContrato`). El texto «Cierra este formulario» la contradice.
Recommendation:
- evaluar la incompatibilidad por encima de la base solo cuando `!solicitudes.isPending && !solicitudes.isError`, o poner esos dos mensajes antes en la cadena; el bloqueo se mantiene igual;
- añadir un test con 17 en pending/error: el mensaje debe ser el de solicitudes y `onTasaChange` no debe llamarse;
- ajustar el texto para mencionar la opción de solicitar autorización.

[P3] La precisión solo se valida en `public.crear_contrato` (hipótesis)
File: migración, patch `$despues$` sobre `public.crear_contrato`; `test-tasa-baja.sql` `$traza$`
Problem: el trigger aplica el mínimo en cualquier INSERT, pero los 2 decimales solo se exigen en esta función. El test `$traza$` inserta directamente en `public.contratos`, lo que demuestra que existen rutas de INSERT fuera de la RPC, aunque ahí como superusuario. Otra RPC, una importación o un INSERT con permisos del cliente redondearían 12.345 a 12.35 sin error.
Evidence: no se adjunta inventario de otras rutas de INSERT en `public.contratos`, ni los GRANT o RLS de INSERT para `authenticated`.
Impact: bajo; no rompe el candado de rango.
Recommendation: registrarlo como deuda, o adjuntar una búsqueda de `insert into public.contratos` en `prosrc` y de los GRANT de la tabla. El comportamiento existente de renovación/upgrade (redondeo silencioso) no cambia y no es regresión.

TEST GAPS:
- Reversa con reserva activa sin sellar (`expira_en>now()`) y con lead `convertido` en el flujo de bandera OFF (`reservar_conversion_lead_tasa_fn`). Solo se ensayó la reserva sellada con bandera ON.
- Carrera de la reversa descrita arriba, o evidencia del orden validación/escritura en `reservar_conversion_lead`.
- Front: preselección 17 con `solicitudesPending` o `solicitudesError`.
- Edge VM: los positivos a 12.5 recorren el DEDUP de bandera OFF y `ya_existia` de bandera ON, pero no la saga de cliente nuevo (líneas 411–523, no adjuntas completas). Es transporte con dobles, no HTTP/Auth real, como indica PRIMARY.

ARCHITECTURE RISKS:
- La reversa depende de que ninguna tarea fuera de `prosrc` borre filas de `crm.conversion_reservas`: jobs de `pg_cron` (`cron.job.command`) o Edge con `service_role`. La búsqueda en `prosrc` no cubre esas fuentes. Conviene una consulta de solo lectura a `cron.job` antes de publicar.

SECURITY RISKS:
- Sin cambios respecto de la revisión previa. Firma, ACL, owner, DEFINER y `search_path` de las cuatro funciones se verifican por fingerprint antes y después de migrar y de revertir. El helper sigue privado.

REGRESSION RISKS:
- Solo la del mensaje P3 del front. Las variantes de regresión a 12.5 (`variantes-regresion.patch`) conservan su significado: los pendientes bloquean también a 12.5.

RECOMMENDED NEXT ACTIONS:
1. Adjuntar el orden de locks y validación de `reservar_conversion_lead` y `reservar_conversion_lead_tasa_fn`. Si confirma la carrera, añadir a la receta el congelamiento previo y la verificación posterior al commit.
2. Reordenar o condicionar `preseleccionIncompatible` frente a solicitudes pending/error, y añadir su test.
3. Consulta de solo lectura a `cron.job` y a las rutas de INSERT en `public.contratos`; documentar el resultado.

CONFIDENCE:
MEDIUM. El SQL del patch, los tests adjuntos y la lógica del front se revisaron completos. El P2 depende de cuerpos no adjuntos.
