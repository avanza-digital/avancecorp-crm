VERDICT:
CHANGES_REQUESTED

SUMMARY:
La migración cumple el contrato principal. En observación, la tasa se registra sin aprobación, las solicitudes pendientes no bloquean y `solicitar_tasa_fn` rechaza pedidos nuevos. La autorización se comprueba antes de leer el JSON. El historial no se toca. Al reactivar, vuelven los dos bloqueos, y `test-modo.sql` lo prueba. No veo cambios de ACL, grants ni RLS en el SQL adjunto.

Encontré tres problemas de correctitud o regresión que surgen al cruzar el nuevo rango de observación con reglas existentes:
- Las tasas heredadas por encima del tope quedan bloqueadas.
- Las autorizaciones sin enlazar quedan huérfanas cuando el modo cambia entre la conversión y el contrato.
- Un campo en solo lectura puede quedar fuera de rango al volver a enforcement.

También señalo tres puntos menores: un defecto de inicialización en el panel del lead, un mensaje SQL mal formateado y un preflight incompleto.

Aviso de rol: la sesión me indicó plan mode y un archivo de plan. Como SECONDARY_REVIEWER sin herramientas, según el protocolo, no escribo archivos ni invoco herramientas. Entrego el review aquí.

FINDINGS:

[P1] Observación rechaza renovaciones y upgrades cuya tasa heredada supera el tope técnico; enforcement los acepta
File: `supabase/migrations/20260918210543_crm_modo_rentabilidad_integral.sql`; `app/src/components/app/tasa-politica.tsx`
Lines: SQL 562-568 (rango fuera del manejador), 660 (`v_base := v_origen.tasa_anual`, sin límite); TSX 204-207
Problem: en observación, el trigger exige `tasa_anual <= least(tope_tecnico,50)` en todo INSERT, sin importar la categoría. En enforcement, una renovación o un upgrade a la tasa heredada cumple `tasa_anual = v_base`: no entra en las ramas 473 ni 485 y no se compara con el tope. En la UI pasa lo mismo: `maximo = Math.max(tope, …)` solo exime a la corrección (`tasaHistoricaConservada`), no a la base heredada.
Evidence: resolver_tasa 641-660 fija la base como la tasa del contrato origen, sin tope. El tope bajó a 28 (ver test-modo línea 14; los fixtures anteriores usaban 50).
Impact: con la política en observación, que se supone el modo permisivo, no se puede renovar ni ampliar un contrato histórico con tasa mayor a 28%, ni en SQL ni desde la UI. Observación queda más estricta que enforcement, al revés de lo que pidió el usuario. La gravedad depende de los datos; es hipótesis hasta consultar producción.
Recommendation:
- En SQL (trigger) y en la UI, usar como máximo `greatest(least(tope,50), base_heredada)` cuando la categoría sea renovación o upgrade y exista `v_base`.
- Verificar con `select count(*) from public.contratos where tasa_anual > 28 and estado in ('activo','vencido') and not es_demo`.
- Añadir un caso de renovación con origen al 30% en `test-modo.sql`.

[P2] En observación, `enlazar_tasa_lead` no enlaza nada; si el modo cambia antes del contrato, la aprobación del lead queda inutilizable
File: migración, `private.enlazar_tasa_lead`
Lines: 113-114 (early return), frente a 115-127; test-modo 108-109 afirma ese comportamiento
Problem: el enlace (`cliente_id` + huella de cliente) es mantenimiento de identidad, no una puerta de aprobación. Al omitirlo, las solicitudes del lead conservan la huella del lead y `cliente_id` nulo. Si la conversión ocurre en observación y el contrato se crea en enforcement, falla:
- El candado del trigger (485-493) busca la autorización con `rentabilidad_consumir_autorizacion` por cliente y huella, y no la encuentra.
- El mismo fallo aparece dentro de una sola transacción: la validación de conversión lee el modo en su sentencia y el trigger diferido lo lee en el `statement_timestamp()` del commit.
Evidence: líneas 114 y 126; el trigger es constraint diferido (test-modo 26/33 usa `set constraints all deferred`).
Impact: falla cerrado (no es un agujero de seguridad), pero una aprobación vigente de Gerencia queda huérfana tras reactivar. El analista tiene que pedirla de nuevo.
Recommendation:
- Mantener el enlace también en observación. En ese modo, cambiar los `raise` de conflicto (116, 123) por "no enlazar esa fila" en lugar de abortar.
- Si se prefiere mantener el diseño actual, documentar el riesgo y añadir una prueba de conversión en observación seguida de contrato en enforcement con una aprobación previa.

[P2] Al volver a enforcement, un campo en solo lectura puede quedarse con una tasa fuera de rango sin marcarla
File: `app/src/components/app/tasa-politica.tsx`
Lines: 246-251 (`vuelveDeObservacion`), 347-350 (`editable`, `fueraDeRango`)
Problem: al volver de observación, el reset a la base se omite siempre. Con `permiteInferior=false` (renovación, upgrade, corrección, o servidor sin `tasa_minima_sin_autorizacion`), `modo='base'` deja `editable=false` y `soloLectura=true`. `fueraDeRango` solo se evalúa si el campo es `editable`, así que un 20 heredado de observación se muestra en solo lectura, sin `aria-invalid` y sin forma de corregirlo. `modoAnterior` pasa a `'base'` en ese mismo efecto, y el reset solo ocurre si más tarde cambia otra dependencia.
Evidence: el test "apagar y encender" (diff tasa-politica.test) solo cubre `tasa_minima_sin_autorizacion: 0.01`, es decir `permiteInferior=true`.
Impact: según cómo valide el formulario padre (contrato-nuevo o corrección usan min/max del rango), el usuario queda bloqueado sin poder editar, o el guardado lo rechaza el servidor sin explicación en la UI. En corrección, el reset devolvería `tasaActual`, lo cual es seguro.
Recommendation:
- Omitir el reset solo si el campo sigue siendo editable (`permiteInferior`). Si no lo es, restaurar la base (o `tasaActual`) y avisar.
- Alternativa: calcular `fueraDeRango` también en solo lectura.
- Añadir un test del flip con `permiteInferior=false` y otro con corrección.

[P2] El panel del lead se inicializa sin la última solicitud si la política responde antes que la bandeja
File: `app/src/components/app/condiciones-tasa-lead.tsx`
Lines: 31-43; 47-55 (el `useState` inicial se lee una sola vez)
Problem: en observación, el panel ya no espera a `q`. Si `politica_rentabilidad_fn` resuelve antes que `solicitudes_tasa_lead_fn` (ambas se lanzan a la vez), `CondicionesEditables` monta con `inicial=undefined`. Capital, fechas, modalidad, tasa y `producto_condicion_id` se inicializan desde el lead y no se recalculan cuando llega `q.data`.
Impact: en observación importa poco. Pero si el modo vuelve a enforcement con el panel abierto, la intención ya no coincide con la huella de la aprobación viva. La aprobación aparece como "otra viva" y el analista debe re-editar o volver a pedirla.
Recommendation: cuando haya que conservar datos previos, esperar también a `q` (sin bloquear si falla), o poner `key={ultima?.id}` en `CondicionesEditables` para remontarlo cuando llegue la solicitud. Añadir un test con `q` pendiente y luego resuelto.

[P3] Mensaje de error del trigger mal formateado
File: migración
Lines: 567
Problem: en el formato de `RAISE`, `'…tope configurado de %%%.'` produce `%` literal seguido del valor, es decir "de %28.". Además muestra `tope_tecnico`, pero se compara con `least(tope,50)`.
Recommendation: usar `'… de %%%'` → `'… de % %%'` con `rentabilidad_tasa_txt(least(v_pol.tope_tecnico,50))`, siguiendo la convención de `solicitar_tasa_fn` (líneas 218, 221).

[P3] El preflight solo compara `prosrc`; no protege atributos que `CREATE OR REPLACE` sobrescribe
File: migración
Lines: 8-35
Problem: `CREATE OR REPLACE` sobrescribe `prosecdef`, `proconfig` y `provolatile`, y el preflight no los compara. Por ejemplo, `rentabilidad_exigir_respuesta` (269-273) se declara sin `SECURITY DEFINER`. Si producción difiere en esos atributos pero no en `prosrc`, el cambio pasaría en silencio. Según PRIMARY, el banco verificó esto con un overlay, pero producción no está en ese bucle.
Recommendation: incluir `prosecdef`, `proconfig`, `provolatile` y `pg_get_function_identity_arguments` en la huella del preflight, o comparar `md5(pg_get_functiondef(oid))`.

[P3] Portal: el refresco cada 30 s bloquea el guardado mientras corre, y queda por verificar cómo se limpia `bloqueaGuardado`
File: `js/admin/analista.js`, `js/admin/contratos.js`
Lines: hunk de `aplicarTasaPolitica` y `refrescarModoTasa`
Problem:
- Cada refresco (30 s y al recuperar el foco) vuelve a pasar el input a `readOnly=true` y marca `pendiente`. Un guardado en ese momento recibe "Espera un momento…".
- El `catch` fija `bloqueaGuardado=true`, y en el hunk no se ve dónde vuelve a `false` tras un refresco exitoso. Es hipótesis: puede que se limpie antes, en código no adjunto.
Recommendation: en el refresco con `conservar`, no tocar `readOnly` ni `pendiente` hasta tener respuesta. Confirmar que `bloqueaGuardado` se resetea al inicio de `aplicarTasaPolitica` (categoría nuevo con cliente).

TEST GAPS:
- Renovación o upgrade en observación con origen por encima del tope (P1), tanto en SQL como en UI.
- Transición de modo entre reserva de conversión y alta del contrato, en la misma transacción o en transacciones separadas, con una aprobación previa del lead (P2).
- Corrección real vía RPC (UPDATE de `tasa_anual` en un contrato sin PDF sellado) en observación: pasa dentro del rango, se rechaza por encima del tope, y conserva una tasa histórica mayor al tope si no se cambia.
- Flip de observación a enforcement en la UI con `permiteInferior=false` y en corrección.
- `CondicionesTasaLeadPanel` con la política resuelta antes que la bandeja.
- Comprobar que un upgrade con origen declarado no reintroduce la lectura del GUC en `exigir_respuesta` (573 usa `coalesce(v_origen, v_origen_dec)`; parece correcto, pero no hay test en observación).
- E2E: `_helpers.ts` solo simula enforcement; falta un escenario de observación con backend simulado.
- Portal: sin test de `refrescarModoTasa` ni de recuperación tras un fallo.

ARCHITECTURE RISKS:
- El modo se lee en cada función con `statement_timestamp()` y sin lock contra la publicación. Una transacción puede mezclar modos (conversión en uno, trigger diferido en otro). Hoy falla cerrado, pero conviene documentarlo en el acta.
- Hay dos fuentes de modo en el cliente (`resolver_tasa*_fn` y `politica_rentabilidad_fn`) con polling independiente. Pueden discrepar durante hasta 30 s. El servidor sigue siendo la autoridad, así que el riesgo es de UX y no de seguridad.
- `politica_rentabilidad_fn` devuelve el historial completo. Ahora se consulta cada 30 s por formulario de corrección o lead abierto; un endpoint ligero de "modo vigente" sería más barato.
- El flag `observacion_sin_aprobacion: true` es constante. Sirve como señal de capacidad, pero no identifica versión. Si hace falta otra transición, conviene un `capacidades` versionado.

SECURITY RISKS:
- No encontré escalamiento de privilegios. `solicitar_tasa_fn` comprueba la autoridad antes de revelar el modo. Las funciones mantienen `search_path ''`. No hay grants nuevos ni DML de negocio.
- Por diseño, observación omite la comprobación de identidad P0409 ("documento cambió") en la conversión (59-64). Es coherente porque no se consume ninguna aprobación, pero conviene dejarlo explícito en el acta de decisión del usuario.
- RLS, advisors y la rama remota NO se ejecutaron. No se puede afirmar nada sobre el catálogo productivo más allá del preflight de `prosrc` (ver P3).

REGRESSION RISKS:
- Corrección: antes no dependía de ninguna consulta; ahora `modo='error'` bloquea toda corrección, incluso solo de notas, si `politica_rentabilidad_fn` falla (tasa-politica 191-195, 213-214). Confirmar que todos los roles que corrigen cumplen `rol_crm is not null or es_lector_global`.
- En observación, el trigger ahora lanza excepciones (562-568); antes nunca abortaba. Esto afecta a todas las rutas de alta: portal `crear_contrato`, jobs e imports. Ligado al P1.
- Los 2 fallos del portal (regex de versiones) parecen previos. Además, este diff sube 42→43, 27→28 y v117→118, así que los tests desactualizados seguirán fallando. Actualizarlos o registrarlos como deuda.

RECOMMENDED NEXT ACTIONS:
1. Resolver el P1: acotar el máximo en observación con `greatest(tope, base heredada)` en SQL y UI, y consultar en producción los contratos con tasa > 28.
2. Decidir el P2 de enlace: enlazar en observación sin abortar, o documentar el riesgo y probar la transición de modo.
3. Corregir el reset al volver de observación cuando el campo no es editable, y la inicialización del panel del lead.
4. Arreglar el mensaje 567 y ampliar el preflight a `prosecdef`, `proconfig` y `provolatile`.
5. Con autorización, ejecutar la rama remota, RLS y advisors antes de aplicar la migración. Cerrar la suite E2E completa y el baseline del portal.

CONFIDENCE:
MEDIUM. Alta para los hallazgos de lógica SQL y TSX visibles en la evidencia. Media o baja para el impacto real del P1 (depende de los datos), para el comportamiento del formulario padre (P2 del campo en solo lectura) y para el reset de `bloqueaGuardado` en el portal, porque no tengo esos fragmentos.
