# Solicitud de tasa: motivo editable y espera obligatoria

Fecha: 08/09/2026. Petición directa de Miguel.

Relacionado: [[Inicio]], [[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]], [[RETOMAR-63 - CARTERA F4 pausada y guardada (2026-09-08)]].

## Estado

**SQL aprobado y aplicado a producción el 08/09/2026 a las 11:57 de Lima. Frontend todavía sin publicar.** Miguel respondió «ok dale sii esta bien» al SQL mostrado. La validación general volvió a ejecutarse y pasó con 216 archivos / 3098 tests; el error ajeno de Citas ya estaba resuelto en el árbol actualizado, sin editarlo en esta tarea.

## Decisión de negocio

El analista puede escribir el motivo comercial en un campo amplio, de tres líneas, con saltos de línea y límite visible de 500 caracteres. La grilla anterior reservaba 9 rem para la tasa dentro de media columna del diálogo y comprimía el motivo a una franja difícil de utilizar; el control de texto sí actualizaba su valor. Ambos campos ahora se apilan.

Enviada una solicitud pendiente vigente, no puede crearse un contrato para el mismo cliente, categoría y origen, ni siquiera a la tasa base. Cambiar capital/plazo, reabrir el formulario o usar otro analista no evita el bloqueo del servidor. Otros clientes/categorías/orígenes conservan su comportamiento. La caducidad existente de la solicitud se conserva: una petición caducada deja de bloquear. No se altera R4: una aprobación debe coincidir con la intención y consumirse una vez; un tope necesita aceptación para usar una tasa superior; un rechazo permite continuar a la base.

En el formulario se bloquea también durante la preparación/envío de la solicitud y mientras no puede comprobarse su estado. Cancelar el borrador libera la preparación, sin cancelar solicitudes enviadas. El fallo de una relectura muestra un reintento y conserva texto/foco. El resultado del envío mantiene el candado hasta que la consulta reconoce la solicitud.

## Implementación

- `app/src/components/app/tasa-politica.tsx`: distribución, seguimiento, bloqueo y aviso accesible; se consulta cada 30 segundos mientras hay una petición pendiente.
- `app/src/components/app/contrato-nuevo.tsx`: botón deshabilitado y comprobación dentro de guardar, incluyendo estados sin resolución de política.
- `app/src/components/app/contrato-corregir.tsx`: el formulario que reutiliza el selector respeta su bloqueo antes de guardar. La garantía nueva del servidor se limita a INSERT, como exige el alta; no se amplía la política de UPDATE de contratos existentes.
- `supabase/migrations/20260908165706_crm_bloquear_contrato_tasa_pendiente.sql`: dos helpers privados y dos inserciones con anclas exactas en las funciones instaladas. Conserva cambios posteriores, firmas, propietarios y ACL; aborta si no reconoce las anclas o no encuentra el trigger diferido activo de R4. El archivo fue creado por CLI como `20260908160127` y se renombró sin cambiar el SQL al conocer la versión asignada por Supabase, para mantener alineado el historial.
- `private.rentabilidad_exigir_respuesta` produce P0411 fuera del manejador que registra errores del observador. La transacción revierte sus altas relacionadas. El emisor y el alta comparten un advisory lock por operación para resolver envíos concurrentes.
- El origen ya resuelto por R4 se reutiliza; no se consume por segunda vez el GUC del upgrade. No cambian tasas ni contratos históricos, tablas ni triggers públicos, ni tipos del API expuesto.

## Verificación

| Control | Resultado |
| --- | --- |
| Pruebas unitarias finales de TasaPolitica, ContratoNuevo y ContratoCorregir | PASS, 67 |
| E2E Chromium a 1280 y 390 px | PASS, 2; escritura real con teclado, foco, salto de línea, envío, cierre/reapertura, capital distinto, bloqueo por Enter y liberación tras rechazo |
| Inspección visual de ambas capturas | PASS; campo amplio y utilizable |
| SQL `test-tasa-pendiente.sql` | PASS, 10 grupos, `plpgsql.check_asserts=on`; todo dentro de BEGIN/ROLLBACK |
| RLS del nuevo bloqueo con rol authenticated | PASS; analista B no ve la petición de A, pero su RPC de alta falla con P0411 |
| Dos conexiones simultáneas | PASS; alta espera el envío sin commit, luego P0411 y cero contratos |
| Reversa y reaplicación | PASS; definiciones originales idénticas, control negativo permite el alta al retirar la migración y P0411 tras reaplicarla |
| `git diff --check` | PASS |
| `npm run check`, corridas anteriores | PASS, primero 214 archivos/3084 tests y luego 216/3093 |
| `npm run check`, corrida anterior a la aprobación | FAIL transitorio: TS2375 en `src/prototypes/citas-crm/depositos.test.ts:61`, trabajo ajeno sin modificar |
| `npm run check`, corrida final tras la aprobación | PASS, 216 archivos / 3098 tests, typecheck, cobertura, configuración de release, build, bundle y duplicación |
| Lint final | PASS sin errores; cuatro avisos preexistentes en `coverflow-carousel.tsx` |
| Gate de realidad y preflights RLS/seed | NOT RUN: falta SUPABASE_URL en el entorno; no sustituir por las pruebas SQL locales |
| Suite RLS global, Storage/PDF real, matriz completa de renovación/upgrade por sus puertas, release | NOT RUN |
| Postflight de producción | PASS; definiciones instaladas contienen exactamente el cambio aprobado, propietarios/ACL conservados, helpers cerrados a API y trigger diferido activo |
| Helper sobre solicitudes productivas en transacción READ ONLY | PASS; una operación pendiente devuelve P0411; no crea ni modifica contratos/solicitudes |
| Advisors seguridad antes/después | 211→211, cero hallazgos nuevos |

Banco `qa_tasa_pendiente_20260908_v2`, base independiente dentro de Docker local. Snapshot sintético del banco F4 más siete definiciones R4 leídas de producción; la base `postgres` original del banco F4 solo se leyó. Restauración parcial sin Storage, con su FK ausente; no es una réplica íntegra de producción. Los ensayos fuerzan `resolver_en_puertas=false` e `inversiones_escritura=false` dentro de sus transacciones. Lectura productiva confirmó `resolver_en_puertas=true`, `inversiones_escritura=false`: no se declara cubierta toda la integración F4. La barrera probada es el trigger diferido de cualquier alta real.

Las definiciones originales restauradas por la reversa tienen MD5 `33c6fe802fdceed5b1f00992a5b7374d` (`solicitar_tasa_fn`) y `1cbdc79c0eae0cc22adc640f5161ab7f` (observador). Las pruebas de navegador usan backend simulado en loopback; no enviaron solicitudes a Gerencia ni crearon contratos reales.

## Revisión independiente y decisión del PRIMARY

Nivel 3 por regla financiera y SQL. Una consulta read-only a Claude mediante `scripts/claude-review`, sin herramientas ni delegación, con protocolos y evidencia saneada. Dictamen: **CHANGES_REQUESTED**. No hubo una segunda consulta ni se declara PASS del reviewer.

Aceptados y corregidos: desmontaje del borrador ante fallo de relectura (se conserva); límite de motivo sin explicación (se muestra rango y contador); mocks de refetch compartidos (se separan y reinician); asserts SQL desactivables (se habilitan explícitamente). La objeción sobre actor/API se comprobó adicionalmente con `SET LOCAL ROLE authenticated`, y el contrato siguió bloqueado. Se ensayaron también concurrencia y reversión con control negativo.

No se aceptaron estas hipótesis como fallos demostrados:

- **RLS omite solicitudes ajenas en el helper invoker:** el trigger existente es SECURITY DEFINER, propiedad de postgres; hereda ese contexto al helper. Lectura de `pg_proc` y prueba authenticated lo confirman, sin conceder EXECUTE a roles API.
- **Una respuesta RPC sin columnas derivadas libera el bloqueo:** `crm-api.ts` normaliza la respuesta con `aSolicitudTasa`; el E2E final quita `es_mia`, `vigente` y `estado_efectivo` de la respuesta de envío y verifica el candado. Una respuesta inválida no completa la mutación.
- **Una política ausente elude la validación:** la solicitud exige una política vigente y la publicada es inmutable. Producción tiene `trg_politica_rentabilidad_inmutable`, que rechaza UPDATE/DELETE con 55000; la búsqueda vigente no tiene fecha de finalización. El caso requeriría una intervención administrativa fuera de las puertas autorizadas. No se duplica la resolución de origen de R4 para ese supuesto.
- **Query deshabilitada mantiene isPending:** el diálogo real siempre recibe cliente; mantener cerrado un estado desconocido es deliberado. Cambiarlo a una condición que permita crear sin conocer solicitudes sería contrario a la petición.

La modificación con anclas está versionada y evita reponer definiciones antiguas sobre las instaladas. Es una limitación de mantenimiento: futuras migraciones que sustituyan esas funciones deberán conservar las dos llamadas y ejecutar el banco de este cambio. No se declara que una comprobación textual por sí sola pruebe el comportamiento. El error genérico P0411 no expone el motivo ni la tasa solicitada por otro analista.

## Siguiente paso

El SQL ya está aplicado; no pedir nuevamente esa aprobación ni volver a ejecutarlo. Evidencia saneada en `CRM-Avance-Corp/supabase/scripts/evidencia-tasa-pendiente/2026-09-08-produccion.json`.

Miguel invocó `/release-crm` y autorizó la publicación de esta corrección. Guardar sus archivos en un commit, integrar los cambios remotos sin sobrescribir trabajo y comprobar Main igual a `avancecorp/main`. Construir y verificar desde una copia limpia de ese commit; conservar los cambios locales ajenos fuera del artefacto. No volver a pedir la aprobación ya recibida.
