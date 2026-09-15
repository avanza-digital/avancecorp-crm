VERDICT:
PASS

SUMMARY:
Cambiar los 4 `RAISE` manuales de `40001` a `PT409` corrige la causa raíz documentada. PostgREST 14.5 reintenta `40001` sin límite (MainTx.hs 89-94, hasql-transaction, issue #3673, fix en 16.0), y un conflicto de revisión obsoleta nunca se resuelve reintentando. La migración cumple lo que pide: el guard MD5 por firma y el conteo exacto de 2 abortan el `DO` completo si hay drift. `CREATE OR REPLACE` a partir de `pg_get_functiondef` conserva la firma, `SECURITY DEFINER`, `SET`, el owner y las ACL. La evidencia HTTP cubre la ruta obsoleta en ambas funciones (PT409 inmediato, sin cuelgue) y el camino feliz. No encuentro cambios obligatorios en el SQL ni en el cliente. Sí hay dos gates de despliegue y cobertura que conviene cerrar antes de producción.

FINDINGS:

[P2] El mismo bug puede existir fuera de inversiones
File: esquemas expuestos por PostgREST (crm y cualquier otro en `db-schemas`)
Lines: N/A. La evidencia solo cubre "componentes de inversión".
Problem: La verificación de "no hay otros 40001" se limita a las funciones de inversión. Cualquier otra función RPC, trigger o función invocada desde una RPC que lance `errcode = '40001'` manualmente provoca el mismo reintento infinito.
Evidence: Se reprodujeron 3 sesiones `authenticator` activas con xact_age <0.03s en bucle, hasta el timeout de 20s y 60s del cliente. El mecanismo no depende de la función concreta.
Impact: Peticiones colgadas y slots del pool de PostgREST ocupados indefinidamente. Varias peticiones concurrentes degradan todo el API, no solo el flujo afectado.
Recommendation: Antes de publicar, consultar el catálogo del branch con algo como `select oid::regprocedure from pg_proc where prosrc ~* '40001|serialization_failure'` en todos los esquemas no de sistema. Revisar también los cuerpos de triggers. Es una consulta de solo lectura.

[P2] Acoplamiento de despliegue con las 2 migraciones ya aprobadas
File: `CRM-Avance-Corp/supabase/migrations/20260915015315_crm_f4_conflictos_sin_reintento.sql` y las 2 migraciones previas que definen las funciones con 40001
Problem: Cada migración se aplica en su propia transacción. Si producción aplica las 2 aprobadas y esta aborta (guard MD5 o conteo ante cualquier diferencia), producción queda con la versión que cuelga.
Evidence: El guard exige exactamente la definición post-migración COOPAC (hashes `0b258ad5…` y `014ef6ae…`), y el SQL nuevo aún no está en el ledger ni en prod.
Impact: Si el guard falla, la aplicación es parcial y deja en prod el cuelgue que se quiere evitar. El fail-closed protege los datos, no la disponibilidad.
Recommendation: Tratar las tres migraciones como una unidad de release. Antes del push a prod, verificar en el destino que ambas funciones, tras las previas, producen esos MD5. Si el push falla en esta migración, no dejar producción en ese estado: aplicarla o revertir el despliegue de las funciones.

[P3] El MD5 de `pg_get_functiondef` depende de `search_path`
File: migración nueva, bloque `DO`
Problem: `pg_get_functiondef` escribe los tipos y el tipo de retorno no visibles en `search_path` con su esquema. Los argumentos actuales son de `pg_catalog`, pero si el retorno es un tipo o tabla de `crm`, el texto puede variar según el `search_path` de la sesión que ejecute la migración.
Evidence: La migración no fija `search_path`. El hash se calculó en una sesión concreta. Es una hipótesis, porque no se adjuntó la cláusula `RETURNS`.
Impact: Solo produce un aborto falso (fail-closed), no un cambio incorrecto. Agrava el P2 anterior.
Recommendation: Confirmar que el guard pasa con el mismo mecanismo que usará producción (CLI `db push`), no solo desde el SQL editor. Si no, fijar `set local search_path` al valor con el que se calcularon los hashes.

[P3] Callers SQL que capturen 40001 dejan de capturar
Problem: Si alguna función o wrapper, incluido el legacy de 11 argumentos, llama internamente a `corregir` o `confirmar` dentro de `exception when serialization_failure` o `sqlstate '40001'`, ahora el error se propaga distinto.
Evidence: Las 4 pruebas legacy pasaron con condiciones null, pero no se adjunta una prueba legacy con revisión obsoleta.
Recommendation: Incluirlo en la consulta de catálogo del primer hallazgo. Si el wrapper legacy delega en estas funciones, añadir un caso HTTP legacy con revisión obsoleta que espere PT409.

TEST GAPS:
- Falta un test de base de datos (pgTAP o script) que afirme SQLSTATE `PT409` con revisión obsoleta y con empresa cambiada en `corregir_solicitud_inversion_fn`. La evidencia HTTP cubre las revisiones obsoletas, pero no se ve un caso de "La empresa cambió" ni de "La solicitud cambió" (inversionista distinto) en `confirmar`.
- Falta un test de regresión que falle si alguna función de esquemas expuestos vuelve a contener `40001` literal. Es barato y previene la reintroducción en migraciones futuras.
- Falta un caso de concurrencia real: dos confirmaciones simultáneas sobre la misma revisión. Una debe terminar OK y la otra PT409 sin colgarse, lo que comprueba que los `FOR UPDATE` y la nueva comprobación no se bloquean mutuamente.
- Falta un caso legacy con revisión obsoleta (ver el último P3).

SECURITY RISKS:
- Ninguno introducido. Firma, ACL, `SECURITY DEFINER` y `SET` se conservan vía `CREATE OR REPLACE`. El caso de actor ajeno sigue en 42501, verificado por HTTP.
- El reintento infinito existente es un vector de agotamiento del pool. Por eso el primer P2 importa más allá de la corrección funcional.

REGRESSION RISKS:
- Cliente: `respuestaInversionistas` no ramifica por `40001` y propaga `code` y `message`. `PT409` muestra el mismo mensaje de negocio. Riesgo bajo, cubierto por MSW.
- Si la telemetría o dashboards clasifican errores por código, `40001` pasa a `PT409`. Hipótesis, no hay evidencia de que exista esa clasificación.
- `notify pgrst, 'reload schema'` es innecesario porque la firma no cambia, pero es inocuo y se entrega en el `COMMIT`.

RECOMMENDED NEXT ACTIONS:
1. Ejecutar la consulta de catálogo de solo lectura para `40001` y `serialization_failure` en todos los esquemas expuestos y en triggers, y documentar el resultado.
2. Tras el rebase, confirmar en el branch los hashes post-PT409 y que el guard pasa ejecutado por el mismo mecanismo que se usará en producción.
3. Publicar las 2 migraciones aprobadas y esta como una unidad, con plan explícito si el guard aborta en producción.
4. Añadir un test DB de SQLSTATE PT409 (4 ramas) y un test que prohíba `40001` literal.

CONFIDENCE:
MEDIUM-HIGH. Alta sobre el SQL y el cliente adjuntos. Media sobre el alcance global, porque no vi el catálogo completo de funciones ni el wrapper legacy.
