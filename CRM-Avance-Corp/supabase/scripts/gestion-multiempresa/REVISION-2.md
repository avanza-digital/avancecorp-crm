VERDICT:
CHANGES_REQUESTED

SUMMARY:
Las correcciones cubren la revisión anterior. El lector usa un único CTE materializado con identidades canónicas, y la auditoría neutral registra el antes y después económico y las condiciones. `v_global_contrato` quedó alineado con `es_gestor_cartera`, y mantener `puede_registrar_ventas` es correcto según `crm.actualizar_contrato_con_cuenta`. La exposición a Directorio queda refutada por la prueba HTTP de igualdad con la vista. No encuentro P0 ni P1. Queda un cambio acreditado en el diff sobre una RPC pública existente que no tiene prueba ni evidencia de auditoría. Además hay dos dependencias no demostradas que conviene cerrar antes de autorizar el SQL.

FINDINGS:

[P2] El cambio en `crm.corregir_cierre_externo` también afecta a quienes la llaman directamente
File:
`CRM-Avance-Corp/supabase/migrations/20260916152851_crm_gestion_integral_multiempresa.sql`
Lines:
72-85; original en `REVERTIR-20260916152851.sql:217-242`
Problem:
El `replace` añade `and exists(... crm.leads ... activo)` al cuerpo compartido de la RPC, y esa RPC sigue concedida a `authenticated` según la firma `cierre` de la evidencia SQL (`authenticated=X/postgres`). Solo `inversionista_corregir_coopac_fn` compensa con una fila en `crm.inversionista_gestiones`. Una llamada directa, como el flujo de corrección de cierres existente, sobre un cierre cuyo lead está archivado ahora:
- no escribe `crm.actividades`;
- tampoco escribe una gestión neutral.
Evidence:
- El hunk 80-81 no distingue quién llama.
- La afirmación "conserva su auditoría de tabla" (línea 69) no tiene respaldo: no se adjunta ningún trigger de auditoría sobre `crm.cierres_externos`.
- `test-http.mjs:151-154` solo comprueba el camino neutral.
Impact:
Si antes el insert fallaba para leads inactivos, la ruta antigua pasa de rechazar a aceptar con menos rastro de negocio. Si antes funcionaba, la ruta antigua pierde el antes/después en `actividades`. En ambos casos es un cambio de comportamiento de una RPC pública fuera del flujo nuevo.
Recommendation:
Aplicar el salto solo cuando llama el wrapper neutral, por ejemplo con un `set_config('crm.gestion_neutral','on',true)` local puesto por `inversionista_corregir_coopac_fn` y comprobado en la condición. Otra opción es adjuntar evidencia del trigger de auditoría de `cierres_externos` y del comportamiento previo. Añadir una prueba de llamada directa con lead archivado.

[P2] La seguridad frente a concurrencia depende de un lock no evidenciado en `private.postventa_persona`
File:
mismo archivo
Lines:
191-219
Problem:
`inversionista_corregir_contacto_fn` compara `p_revision` con un contexto leído sin un `FOR UPDATE` propio y después hace upsert. Bajo READ COMMITTED, el resultado "uno confirma y otro recibe PT409" (`test-http.mjs:65-67`) solo es posible si `postventa_persona(...,false)` bloquea una fila compartida antes de la línea 192. No se adjuntó su cuerpo.
Además, la prueba de fusión (`test-http.mjs:191-192`) llama con el id del alias. Da `revision=42` tanto si `v_i` es el alias como si es la canónica, así que no demuestra cuál fila se bloquea ni en cuál se escribe.
Impact:
Hipótesis: si el lock recae sobre el id recibido y no sobre la canónica, dos escrituras concurrentes (una por alias y otra por canónica) pasan ambas la comprobación de revisión. Eso produce una actualización perdida y dos filas con `revision` duplicada.
Recommendation:
Adjuntar `private.postventa_persona`, o bloquear explícitamente la fila canónica (`select ... from crm.inversionistas where id=private.inversionista_canonica(p_inversionista) for update`) antes de leer el contexto. En la prueba de fusión, comprobar el `inversionista_id` de la fila escrita en `inversionista_datos_contacto` y en `inversionista_gestiones`.

[P3] La capacidad Avance puede dar falsos negativos para autores vendedor/supervisor
File:
mismo archivo
Lines:
140-144
Problem:
`puede_registrar_ventas()` admite a vendedor, supervisor y gerencia mediante `puede_gestionar_contratos_crm()`. Sin embargo, la rama no global de `v_corregir` exige `es_analista_vigente()`. Si `public.actualizar_contrato` permite corregir en 5 h a cualquier autor (no se adjuntó), la UI ocultaría una corrección que el escritor sí acepta.
Evidence:
El cuerpo de `puede_registrar_ventas` está en la evidencia. `test-http.mjs:130-140` solo prueba un autor con rol `analista`.
Impact:
Solo afecta a la usabilidad; no es un problema de seguridad (falla cerrado).
Recommendation:
Contrastar con `public.actualizar_contrato`. Si admite a cualquier autor, sustituir `es_analista_vigente()` por la misma condición, y añadir un caso de vendedor autor dentro y fuera de la ventana.

[P3] La `revision` de contacto se devuelve a Directorio aunque depende del domicilio oculto
File:
mismo archivo
Lines:
172
Problem:
El hash incluye `to_jsonb(v_d)`, que contiene el domicilio, y se devuelve también a `v_lector`. Directorio puede detectar cambios en un dato que no ve y que nunca podrá corregir.
Recommendation:
Devolver `revision` nula cuando `v_lector`.

TEST GAPS:
- La prueba de rendimiento (`test-sql.mjs:27-38`) no comprueba que `count(*)` sea igual antes y después de insertar los 600 contactos. Así no se demuestra que el join no amplía la visibilidad.
- No se prueba `contacto.domicilio === null` para Directorio; solo se prueba en `perfiles`.
- No hay un caso de rol `operaciones`: debería tener `sin_limite=true` y `puede_corregir=false` por `puede_registrar_ventas`.
- No se prueba `corregir_cierre_externo` llamado directamente con lead archivado (ver P2).
- No se prueba COOPAC sin condiciones con el payload sin `vence_en`: la línea 256 anularía el vencimiento existente. Verificar que el frontend siempre lo envía.

ARCHITECTURE RISKS:
- Reescribir el lector con `replace` está bien protegido por md5 y comprobaciones de posición, y la reversa verifica el md5 instalado. Cualquier cambio futuro al lector debe regenerar ambos hashes.

SECURITY RISKS:
- No hay riesgos nuevos acreditados. La tabla queda privada y sin acceso para `service_role` desde PostgREST. Las RPC están revocadas para `anon`, y el escritor COOPAC verifica Gerencia antes de tocar datos. El recibo idempotente solo devuelve la respuesta propia del actor (clave `actor_id,clave`) y va después de la comprobación de visibilidad de `gestion_fn`.

REGRESSION RISKS:
- Ruta directa de `corregir_cierre_externo` (P2).
- La reversa elimina deliberadamente del lector los nombres y teléfonos corregidos; debe quedar documentado para operación.

RECOMMENDED NEXT ACTIONS:
1. Limitar el cambio de `corregir_cierre_externo` al wrapper neutral, o adjuntar evidencia de la auditoría de tabla y del comportamiento previo, con su prueba.
2. Adjuntar `private.postventa_persona` o añadir un lock explícito sobre la identidad canónica, y reforzar las aserciones de la prueba de fusión.
3. Añadir la aserción de conteo en la prueba de 600 contactos y el caso de domicilio de contacto para Directorio.

CONFIDENCE:
MEDIUM. Alta para el diff revisado; limitada por no disponer de `postventa_persona`, `public.actualizar_contrato` ni los triggers de `cierres_externos`.
