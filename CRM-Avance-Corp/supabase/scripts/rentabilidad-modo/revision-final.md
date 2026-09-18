VERDICT:
CHANGES_REQUESTED

SUMMARY:
Las correcciones del primer review están bien encaminadas y no encuentro regresiones P0/P1 en la evidencia adjunta. Estas piezas son coherentes entre backend y frontend:
- el techo `least(50, greatest(tope, base heredada))`;
- el mensaje P0410 sin formato ambiguo;
- el preflight con `pg_get_functiondef`;
- la invalidación explícita al volver al candado.

El nuevo enlace de identidad en observación es correcto por construcción. Pero sus tres ramas de salto (otra identidad, DNI desactualizado y huella en conflicto) no tienen pruebas deterministas. La única aserción negativa pasa sin que se sepa qué rama la produjo. Además, hay un posible reuso de una aprobación previa tras un contrato creado en observación, que conviene confirmar como decisión explícita. Por eso marco cambios accionables y no PASS.

FINDINGS:

[P2] Las ramas de salto del nuevo enlace no se prueban de forma aislada
File: `CRM-Avance-Corp/supabase/scripts/rentabilidad-modo/test-modo.sql` (bloque `$traza$`) y `20260918210543_crm_modo_rentabilidad_integral.sql` (`private.enlazar_tasa_lead`)
Problem: la protección de identidad y de conflictos, que es el cambio nuevo de mayor riesgo, solo se cubre por accidente.
Evidence:
- En `$traza$` (modo observación), `enlazar_tasa_lead(lead1, f3a…0001)` debe dejar `solicitud_lead.cliente_id is null`.
- Antes del cambio, esa aserción pasaba por el `return` temprano.
- Ahora puede pasar por dos vías distintas:
  - huella en conflicto: `solicitud_cliente` tiene la misma `intencion(20)` pendiente para ese cliente, así que se ejecuta el `continue`;
  - DNI desigual: el `documento_lead` '71809001' frente al DNI sembrado del perfil F3.
- El caso positivo (`$conversion_observacion$`) sí está cubierto.
- No hay ningún caso para `v_s.cliente_id is not null` en observación. Hoy el `select … where cliente_id is distinct from p_cliente` lo incluye y el `continue` lo salta; en enforcement lanza P0409.

Impact: un refactor que invierta o elimine una de las condiciones podría seguir pasando el banco. El riesgo concreto es enlazar la solicitud de otra persona, o de un DNI viejo, a un cliente nuevo.
Recommendation: agregar tres casos independientes en observación, cada uno con una sola causa de salto:
- (a) solicitud con `cliente_id` de otro cliente;
- (b) `documento_lead` distinto del `leads.dni` actual, sin huella en conflicto;
- (c) huella en conflicto con DNIs coincidentes.

En cada caso, afirmar que no hay excepción, que `cliente_id`, `huella` y `estado` no cambian, y que las demás filas compatibles sí se enlazan. Agregar también (d): la misma fila (a) en enforcement sigue lanzando P0409.

[P2] Una aprobación previa sobrevive a un contrato creado en observación y puede autorizar otro tras reactivar (hipótesis, confianza media)
File: migración, trigger `private.trg_contratos_observar_rentabilidad` y ruta de alta en observación; test `$observacion$` / `$contratar_despues_de_reactivar$`
Problem:
- En observación, el alta registra `ledger.solicitud_id is null` y no consume ninguna solicitud (aserción en `$traza$`).
- `$conversion_observacion$` enlaza una solicitud `aprobada` al cliente sin consumirla.
- Si en observación se crea el contrato de esa misma operación, la aprobación queda `aprobada` y vigente.
- Tras reactivar, un segundo contrato con la misma huella la consumiría (`$contratar_despues_de_reactivar$` demuestra que sigue siendo utilizable).

Evidence: el banco prueba "aprobación utilizable tras reactivar", pero no la secuencia "contrato en observación y luego otro contrato en enforcement con la misma huella".
Impact: una sola autorización de Gerencia podría respaldar dos contratos por encima de la base, dentro de `vigencia_solicitud_dias`.
Recommendation: decidirlo explícitamente.
- Si es aceptable, documentarlo y añadir un test que fije el comportamiento.
- Si no, que el alta en observación marque como consumida (o como "cubierta por observación") la solicitud activa con la misma huella del cliente.

[P3] Falta prueba de que el valor invalidado bloquea el envío y de que el botón lo repara
File: `CRM-Avance-Corp/app/src/components/app/tasa-politica.tsx` (`fueraDeRango` ahora incluye `soloLectura`, botón "Usar tasa vigente") y `e2e/rentabilidad-modo.spec.ts`
Evidence: el E2E del flip solo afirma `aria-invalid="true"` y `value='20'`. No comprueba:
- que "Convertir" o "Crear contrato" quede bloqueado;
- que el botón aparezca con nombre accesible;
- que al pulsarlo el valor pase a `15` y desaparezca `aria-invalid`.

Además, el cambio a `primera && valor !== base` también afecta a un cambio de `tasa_base_nueva` dentro del mismo contexto en enforcement. Antes la base se actualizaba en silencio; ahora queda inválida y se ofrece el botón. Es coherente con la intención, pero amplía el cambio más allá del flip de observación.
Recommendation: extender el E2E y el test unitario con esos tres pasos, más un caso de republicación de la base en enforcement sin flip.

[P3] Asimetría en la herencia entre la validación de conversión y el trigger
File: migración, en `validar_tasa_conversion_lead` y en el trigger
Evidence:
- `validar_tasa_conversion_lead` admite `v_base` solo por categoría.
- El trigger exige además `v_regla in ('heredada_renovacion','heredada_upgrade')`.
- El frontend usa `baseHeredada` solo si `!correccion`.

Impact: bajo. El trigger es la autoridad final y, si la regla no es heredada, `v_base` ≤ tope. Aun así, la conversión podría aceptar un valor que luego rechace el contrato si `resolver_tasa` devuelve una base alta sin regla heredada (hipótesis; no se adjunta `resolver_tasa`).
Recommendation: usar la misma condición de regla en `validar_tasa_conversion_lead`. Añadir un caso con `p_cliente = null` y un origen ajeno a 30% en observación, esperando P0410.

[P3] El panel de condiciones no se reinicializa tras un error en observación
File: `condiciones-tasa-lead.tsx`
Evidence: en observación con `q.isError` se monta `CondicionesEditables` con `inicial` indefinido. Si un refetch posterior trae la última solicitud, el formulario (estado inicial de `useState`) no se rehidrata porque no lleva `key`.
Impact: UX menor; el servidor sigue siendo la autoridad.
Recommendation: usar `key={ultima?.id ?? 'sin-solicitud'}` o dejarlo documentado como aceptado.

TEST GAPS:
- Las tres ramas de salto de `enlazar_tasa_lead` en observación y la rama `cliente_id` ajeno en enforcement (ver el primer P2).
- La secuencia de doble uso de la aprobación (ver el segundo P2).
- Corrección de un contrato renovacion/upgrade con tasa heredada mayor que el tope en observación: bajar de 30 a 29 (UI: máximo 28; backend: depende de `v_regla` en UPDATE, no adjunto).
- Test unitario de `maximo` con `baseHeredada` mayor que el tope y con el tope a 50.
- `$conversion_observacion$` y `$contratar…$` corren con `reset role` (superusuario), no como `authenticated`, así que no ejercitan RLS. Ya lo reconoces como pendiente remoto.

ARCHITECTURE RISKS:
- Los hashes de `pg_get_functiondef` dependen de la versión mayor de Postgres y del formateo del servidor. Hay que confirmar que el banco y producción comparten versión mayor, o el preflight fallará (fallo seguro, no silencioso).

SECURITY RISKS:
- Ninguno nuevo con la evidencia adjunta. `enlazar_tasa_lead` sigue siendo SECURITY DEFINER con `search_path ''`, y en observación nunca reasigna una fila con `cliente_id` ajeno.
- Detalle menor: se compara `documento_lead` con `perfiles.dni` sin `tipo_documento`.

REGRESSION RISKS:
- El cambio `primera &&` en modo base extiende el "no reemplazo silencioso" a republicaciones de la base en enforcement (ver el P3 correspondiente).
- El panel ahora espera la lectura inicial también en observación. Es correcto, y el error no bloquea.

RECOMMENDED NEXT ACTIONS:
1. Añadir los casos SQL aislados (a) a (d) para el enlace y ajustar la aserción de `$traza$` para que dependa de una sola causa.
2. Decidir y fijar con un test el destino de una aprobación activa cuando se contrata esa misma operación en observación.
3. Extender el E2E del flip: bloqueo de envío, botón "Usar tasa vigente" y limpieza de `aria-invalid`.
4. Opcional: alinear la condición de herencia de `validar_tasa_conversion_lead` con la del trigger.

CONFIDENCE:
MEDIUM. No tuve acceso a `resolver_tasa`, al cálculo de `v_base`/`v_regla` del trigger en UPDATE, a los tests unitarios modificados ni a la ruta de alta que consume solicitudes.
