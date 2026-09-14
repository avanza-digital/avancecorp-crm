VERDICT:
CHANGES_REQUESTED

SUMMARY:
La migración es acotada. Preflight MD5, anclas únicas, propietario del helper, ACL y `search_path` están bien resueltos. El candado conserva la herencia de renovaciones y upgrades, bloquea las rebajas en correcciones y mantiene el bloqueo por solicitudes pendientes, tanto en `validar_tasa_conversion_lead` como en `rentabilidad_exigir_respuesta` al INSERT. Con la evidencia adjunta no veo P0 ni P1.

Sí hay hallazgos accionables:
- el servidor no exige 2 decimales en el alta directa;
- el front puede cambiar sin avisar la tasa acordada en el lead;
- la reversa ignora las conversiones ya selladas a una tasa inferior;
- faltan pruebas de otras puertas que podrían seguir comparando contra la base.

No se afirma seguridad absoluta. Solo revisé lo adjunto.

FINDINGS:

[P2] El candado no exige 2 decimales en el alta de contrato
File: `supabase/migrations/20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql` (patch `$despues$` sobre `private.trg_contratos_observar_rentabilidad`)
Problem: la nueva excepción solo exige `categoria='nuevo'`, `tasa_anual >= rentabilidad_minimo_alta(...)` y que sea INSERT o que la tasa no cambie. No comprueba `tasa_anual = round(tasa_anual,2)`. Esa comprobación solo está en `validar_tasa_conversion_lead` (`v_tasa<>round(v_tasa,2)`).
Evidence: `test-tasa-baja.sql` prueba 12.345 solo en `$conversion$`, contra `validar_tasa_conversion_lead`. En `$limites$` no hay ningún `pg_temp.alta(12.345)`. Antes esto no importaba para tasas sin autorización, porque el candado exigía `tasa = base`.
Impact: un analista puede llamar a `crear_contrato_con_cuenta_pdf_v2` por la API autenticada con 12.345. Según el tipo de `contratos.tasa_anual` (no adjunto), pasan dos cosas. Si es `numeric` sin escala, se guarda 12.345 y se incumple la regla aprobada. Si es `numeric(p,2)`, se redondea sin aviso y ya no es la tasa elegida.
Recommendation: añadir `and v_c.tasa_anual = round(v_c.tasa_anual,2)` a la excepción, o confirmar con evidencia que existe un CHECK o una escala que rechace. Añadir en `$limites$` el caso `alta(12.345)`, que debe ser rechazado.

[P2] El front baja sin aviso la tasa del lead cuando queda por encima del rango
File: `app/src/components/app/tasa-politica.tsx`, `preseleccionIncompatible` y el primer `useEffect` (`inicialInvalida`)
Problem: `preseleccionIncompatible` solo detecta `tasaPreseleccionada < minimo`. Supongamos que la tasa acordada queda por encima de `base`/`maximo` al abrir el contrato: la política bajó la base entre la conversión y el contrato, o la autorización ya no aplica. Entonces `primera && valor > base` → `onTasaChange(String(base))` reemplaza la tasa sin bloquear.
Evidence: la condición es `tasaPreseleccionada < minimo`. El effect reinicia con `valor > base` en el primer contexto. El test `si el servidor deja de aceptar la tasa del lead…` solo cubre el caso por debajo del mínimo, en ambas variantes.
Hipótesis adicional: la tasa también puede cambiar sin aviso cuando se cumplen dos condiciones:
- otra parte del formulario escribe `tasa`; el comentario eliminado mencionaba «una condición de catálogo»;
- el formulario está bloqueado por incompatibilidad.

En ese caso `parseMonto(tasa) === tasaPreseleccionada` deja de cumplirse, el bloqueo desaparece y el effect aplica la base.
Impact: el cliente acordó una tasa en el lead y el contrato sale con otra sin que el analista lo revise. El pedido explícito era evitar «silencios sobre tasa elegida».
Recommendation:
- tratar como incompatible cualquier `tasaPreseleccionada` fuera de `[minimo, maximo]`;
- hacer el bloqueo pegajoso mientras exista la preselección, sin depender de que `tasa` coincida;
- añadir tests para una base menor que la tasa del lead y para una escritura externa de `tasa` durante el bloqueo.

[P2] La reversa solo detecta tasas inferiores ya escritas en el ledger
File: `supabase/scripts/tasa-baja/verificar-local.py`, bloque `rollback` (genera `revertir-antes-del-primer-uso.sql`)
Problem: el preflight de la reversa solo busca `ledger_rentabilidad.detalle->>'tasa_inferior_sin_excepcion'`. Con la migración aplicada, `validar_tasa_conversion_lead` acepta una tasa ≤ base, y la reserva y el sellado (`reservar_conversion_lead`, `marcar_efectos_conversion`) se completan sin crear ninguna fila de ledger. El contrato llega después.
Evidence: en `$conversion$` la secuencia es reservar → marcar efectos → perfil → `convertir_lead` → alta. El ledger solo se escribe al hacer el alta.
Impact: si se revierte entre la conversión y el alta, el candado anterior rechaza el contrato a 12.5 (P0410). El lead queda convertido, con perfil y efectos ya sellados, pero sin poder crear su contrato ni corregir su tasa pactada.
Recommendation: ampliar el preflight de la reversa para que también rechace estos dos casos:
- reservas o condiciones de lead vigentes con `tasa_anual < base` para `nuevo`, según `crm.conversion_reservas` y las condiciones guardadas del lead;
- solicitudes ligadas a esas reservas.

Documentarlo en la receta de reversa.

[P2] Faltan pruebas de otras puertas que podrían seguir exigiendo `tasa >= base` (hipótesis)
File: no adjuntos: Edge `crm-convertir-lead`, `public.crear_contrato` u otras RPC de alta, portal, `crm.solicitar_tasa_fn`, `rentabilidad_consumir_autorizacion`
Problem: la migración solo cambia 3 cuerpos. No se adjunta ninguna búsqueda de otros lugares que comparen contra `tasa_base`, como `< v_base` o `tasa_base`, en SQL, Edge o Deno.
Evidence:
- el E2E `tasas-bajas.spec.ts` intercepta `resolver_tasa_*`, y `crm-convertir-lead` / `crear_contrato_con_cuenta_pdf_v2` pasan por `ruta.fallback()` hacia `montarBackendReal`, que es un doble;
- el SQL prueba la reserva directamente, no a través del Edge;
- «Edge/Deno PASS» no dice qué se validó sobre la tasa.
Impact: si alguna de esas puertas compara contra la base, en producción la conversión o el alta a 12.5 fallaría aunque todos los tests locales pasen. El efecto contrario también sería posible: una puerta con su propia regla que no pase por el trigger.
Recommendation: adjuntar un grep o un extracto de CodeGraph con todas las referencias a `tasa_base`, `resolver_tasa` y `tasa_anual <` en migraciones vigentes y funciones Edge, y confirmar que ninguna compara contra la base. Añadir un test Deno del Edge de conversión con 12.5.

[P3] Una corrección hacia arriba pero por debajo de la base se rechaza con un mensaje engañoso
File: migración, patch del candado
Problem: corregir 12.5 → 14 cambia la tasa (`old.tasa_anual distinct`), así que se rechaza con «la fija la política: 15%, y no puede quedar por debajo». Corregir 12.5 → 15 sí pasa.
Impact: es conservador y coherente con «correcciones no adquieren permiso». Aun así, el texto contradice la nueva regla para `nuevo` y confunde al analista.
Recommendation: confirmar con Miguel si ese caso debe rechazarse. Si se mantiene, usar un mensaje específico: «Una corrección no puede cambiar una tasa pactada por debajo de la base».

[P3] La etiqueta «Tasa acordada» no refleja la tasa elegida
File: `app/src/components/app/condiciones-tasa-lead.tsx`, `estado`
Problem: la etiqueta aparece siempre que `minimo < base`, aunque la tasa sea exactamente 15.
Recommendation: condicionarla a `nTasa < base`, o usar un texto neutro.

[P3] Paso de demo a real con tasa inferior
File: migración, patch del candado (`old.es_demo is not true`)
Problem: pasar un contrato de demo a real a 12.5 se rechaza, aunque el código lo trate «como un alta».
Recommendation: es conservador y aceptable. Basta con documentarlo o añadir un test que fije la decisión.

[P3] El mínimo 0.01 está fijo en código
File: `private.rentabilidad_minimo_alta`
Problem: el valor 0.01 no vive en `crm.politica_rentabilidad`. Cambiarlo exige una migración y el ledger no guarda qué mínimo aplicó.
Recommendation: aceptable para esta fase. Registrar la deuda o anotar el mínimo en `detalle`.

TEST GAPS:
- Alta directa con 12.345 por la API autenticada, que debe ser rechazada, y verificación del tipo o CHECK de `contratos.tasa_anual`.
- Front: lead a 12.5 con la base de la política bajada a 12 al abrir el contrato; debe bloquear, no bajar la tasa.
- Front: escritura externa de `tasa` mientras está bloqueado por incompatibilidad.
- Reversa ejecutada tras sellar una reserva a 12.5 sin contrato.
- Edge `crm-convertir-lead` real (Deno) con 12.5.
- La variante 12.5 se generó con `replace('pg_temp.alta(15', ...)` sin revisar qué asserts cambiaron de significado. Conviene adjuntar el diff resultante.

ARCHITECTURE RISKS:
- La regla inferior vive en tres sitios (resolver, validación de lead y trigger) más la validación del cliente en `crm-api.ts`. El helper común ayuda, pero la regla de 2 decimales ya diverge entre la validación del lead y el trigger.

SECURITY RISKS:
- El helper es privado, con `revoke` a `anon`/`authenticated`/`service_role` y el mismo dueño que las funciones que lo llaman. No detecto escalada.
- La rebaja no deja rastro en `solicitudes_tasa`; solo en el ledger. Hipótesis: los tableros o reportes de Gerencia que marcan `tasa_final <> tasa_base` sin `solicitud_id` como anomalía empezarán a mostrar estos contratos. Conviene revisarlos.

REGRESSION RISKS:
- Orden de despliegue: con front nuevo y servidor viejo, el mínimo es la base (fallback cerrado); con servidor nuevo y front viejo, el comportamiento es el mismo que hoy. Es compatible en ambos sentidos.
- El effect de `TasaPolitica` ya no reinicia valores por encima de la base después del primer contexto. Queda `aria-invalid` y el submit bloquea, pero conviene confirmarlo en la corrección del catálogo.

RECOMMENDED NEXT ACTIONS:
1. Añadir la verificación de 2 decimales al candado del trigger, con su test en `$limites$`.
2. Ampliar `preseleccionIncompatible` a todo valor fuera de `[minimo, maximo]` y hacer el bloqueo independiente de `tasa`, con sus tests.
3. Extender el preflight de la reversa a reservas y condiciones de lead con tasa inferior.
4. Adjuntar evidencia (grep o CodeGraph) de que ninguna otra puerta SQL o Edge compara contra `tasa_base`, más un test Deno de conversión a 12.5.

CONFIDENCE:
MEDIUM. La lógica SQL y del front adjunta se revisó completa. Faltan el tipo de columna, el Edge y otras RPC.
