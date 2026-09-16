VERDICT:
CHANGES_REQUESTED

SUMMARY:
El diseño general es sólido. Resuelve la persona canónica antes de leer, bloquea la persona y luego la fuente, usa versión esperada, recibo idempotente, flags y exige de nuevo `cartera_f5_exigir`. La ventana de 5 h se toma del antecedente más antiguo, aliases de fusión incluidos, y el banco HTTP cubre bien los casos principales. No veo ningún P0.

Hay cuatro puntos que conviene corregir antes de autorizar el SQL:
- un riesgo de costo en el lector canónico modificado;
- una auditoría de negocio COOPAC incompleta en el caso de lead inactivo, que es justamente el que motiva el splice;
- divergencias entre los flags `puede_corregir` de contrato y los gates reales del escritor heredado;
- una posible exposición de columnas crudas a Directorio mediante `to_jsonb`.

Recibí fuentes completas sin poder abrir archivos. Las afirmaciones que dependen de objetos no adjuntos están marcadas como hipótesis.

FINDINGS:

[P1] Costo N×M en el lector canónico al añadir `gestion_contacto`
File: `supabase/migrations/20260916152851_crm_gestion_integral_multiempresa.sql`
Lines: 26-31, 55-56
Problem: El splice añade `left join lateral private.gestion_contacto(i.id)` a `cartera_f5_personas_visibles`.
- `gestion_contacto` es una función SQL `security definer`, así que no es inlinable.
- Por cada persona autorizada recorre toda `crm.inversionista_datos_contacto` y evalúa `private.inversionista_canonica(d.inversionista_id)`, una resolución recursiva, en cada fila.
Evidence:
- El lector acepta `p_inversionista is null` (`and (p_inversionista is null or i.id=(select id from destino))`), es decir, tiene modo de listado.
- `gestion_contacto` no tiene predicado indexable: `where private.inversionista_canonica(d.inversionista_id)=p_persona`.
Impact: Cualquier lectura existente de la cartera completa que pase por este lector crece de forma cuadrática a medida que se acumulan correcciones. Es una regresión de rendimiento sobre un camino ya publicado. Que el caller nuevo no haga fetch de toda la cartera no protege a los callers existentes.
Recommendation:
- Reutilizar el CTE materializado `identidades`, que ya contiene `canonica`. Por ejemplo: `left join lateral (select d0.* from crm.inversionista_datos_contacto d0 join identidades x on x.id=d0.inversionista_id where x.canonica=i.id and not i.lector order by d0.actualizado_en desc,d0.inversionista_id limit 1) datos on true`.
- Alternativa: materializar un CTE `contactos` una sola vez.
- Añadir al banco un `EXPLAIN ANALYZE` del modo listado con varios cientos de filas de contacto.

[P2] La auditoría neutral COOPAC no conserva antes/después económico cuando el lead está inactivo
File: misma migración
Lines: 64-75, 243-247
Problem: Con el splice, si el lead está inactivo, `corregir_cierre_externo` ya no escribe `crm.actividades`, que es el único rastro de negocio con `antes/despues` de monto, número de operación, referencia y nota. La fila `correccion_coopac` solo guarda `condiciones_antes/despues` (plazo, tasa y vencimiento).
Evidence: El metadata de la línea 245 omite `monto`, `numero_transaccion`, `referencia_externa` y `nota`. `v_ce` ya contiene los valores anteriores.
Impact: En este caso la trazabilidad de negocio del cambio financiero depende solo del trigger de tabla. Contradice "neutral business audit preserve trace". El camino heredado, llamado directamente con lead inactivo, antes fallaba y ahora confirma sin rastro de negocio. No es una regresión de escrituras exitosas, pero sí una auditoría más pobre.
Recommendation:
- Incluir en `correccion_coopac` un `antes/despues` completo, con el mismo shape que usa `corregir_cierre_externo`.
- Añadir un caso HTTP con lead `activo=false` que verifique que la corrección confirma y que existen el audit de tabla y la gestión con monto antes/después.

[P2] `inversion.puede_corregir` (Avance) no replica los gates de `public.actualizar_contrato`
File: misma migración
Lines: 123-126, comparadas con `public.actualizar_contrato` adjunto
Problem: Hay tres divergencias entre el flag y el escritor heredado:
- **Gerencia bloqueada de más:** el flag exige `private.puede_registrar_ventas()` también a los roles globales. El escritor heredado no lo exige a gerencia ni al gestor de cartera; solo lo pide en la rama analista/catalogado.
- **Rama global distinta:** el flag usa `v_rol='gerencia' or v_admin` (`public.es_admin()`). El escritor usa `public.es_gestor_cartera() or gerencia` y bloquea solo si `membresia_crm_revocada`. Si `es_admin` y `es_gestor_cartera` no son equivalentes (hipótesis, no adjunto), aparecen falsos positivos y falsos negativos.
- **Gate extra en la rama analista:** el flag añade `puede_gestionar_cuentas_cliente(v_c.cliente_id)`, que el escritor no exige.
Impact:
- La UI deshabilita "Corregir contrato" (`deshabilitado={!vigente || !i?.puede_corregir}`) a usuarios que la ruta heredada sí autoriza. Es una regresión funcional si se retira la entrada heredada.
- Donde el flag da un falso positivo, el servidor rechaza. Es seguro, pero confuso.
Recommendation:
- Derivar el flag exactamente de los predicados del escritor: gestor_cartera/gerencia y no revocado; o analista/catalogado con autor, menos de 5 h y `puede_registrar_ventas`; más la regla de estado cerrado.
- Añadir filas a la matriz del banco: gerencia sin `puede_registrar_ventas`, admin no gestor y gestor no admin.

[P2] (hipótesis) `to_jsonb` crudo hacia Directorio en `contrato` y `operaciones`
File: misma migración
Lines: 121, 130
Problem: `to_jsonb(c)` de `crm.contratos_cartera` y `to_jsonb(o)` de `crm.operaciones_cartera` se ejecutan dentro de una función `security definer` con owner `postgres`.
Evidence:
- Si esas vistas dependen de RLS o de `security_invoker` para acotar o redactar, aquí no aplican: en Supabase `postgres` tiene BYPASSRLS.
- El chequeo `if v_contrato is null → 42501` no es entonces un filtro de ámbito real. El ámbito lo dan solo `cartera_f5_fuentes_reales` y la visibilidad de la persona, lo cual está bien.
- Valibot descarta las claves desconocidas en el cliente, pero viajan igual por la red (por ejemplo `notas_internas` u otras columnas internas).
Impact: Directorio podría recibir en el payload campos que hoy le redacta otro lector.
Recommendation:
- Construir un `jsonb_build_object` explícito con las columnas que consume `ContratoRowSchema` y el schema de operaciones.
- Para `v_lector`, aplicar la misma redacción que el lector de contrato publicado.
- Añadir un test HTTP que compare las claves del payload de Directorio con una lista permitida.

[P3] Errores de cast devuelven códigos que dejan el envío pendiente indefinidamente
File: misma migración, líneas 226, 230 y 232; `app/src/data/postventa-envios.ts` línea 62
Problem: `(p_datos->>'monto')::numeric`, `::integer` (por ejemplo con plazo `12.5`) y `::date` lanzan 22P02 o 22007, no 22023. Esos códigos no están en la lista de rechazo definitivo del cliente.
Impact: El borrador queda como pendiente de recuperación. Al verificarlo aparece como no registrado, se reenvía y vuelve a fallar: el usuario entra en un bucle.
Recommendation: Validar con `jsonb_typeof` o regex, o envolver los casts y relanzar 22023. Otra opción es añadir 22P02 y 22007 a la lista del cliente. Conviene cubrirlo con un test.

[P3] La revocación de la ficha se dispara por "inversión no encontrada"
File: `gestion-inversionista-dialogo.tsx` líneas 80-81; migración líneas 117-118 y 122
Problem: Una fuente eliminada, o que deja de ser coherente, devuelve 42501. El diálogo lo trata como revocación y llama a `onRevocado`, que cierra la ficha completa.
Impact: Si otra sesión elimina o renueva el contrato, el usuario pierde la ficha de una persona que sigue visible.
Recommendation: Usar P0409 cuando la persona es visible pero la fuente no está disponible, y reservar 42501 para la persona.

[P3] Splices sin comprobación posterior y sin script de reversión
File: migración, líneas 50-57 y 72-73
Problem:
- `replace()` no comprueba que el texto resultante cambió. El guard md5 lo mitiga, pero conviene afirmar `v_def <> v_original`.
- No hay un `REVERTIR-20260916152851.sql` que restaure los cuerpos originales del lector y de `corregir_cierre_externo`, elimine las funciones y la tabla, y restaure el CHECK.
Recommendation: Añadir ambas cosas.

[P3] Inconsistencia de timestamp y posible FK bloqueante
File: migración, líneas 11, 16 y 195
Problem:
- El INSERT usa `now()` (hora de la transacción) y el UPDATE usa `clock_timestamp()`. La ordenación `actualizado_en desc` entre aliases fusionados puede resultar inconsistente. Conviene usar un único criterio.
- (Hipótesis) La FK `inversionista_id → crm.inversionistas` sin `on delete` puede bloquear cualquier flujo que borre identidades, por ejemplo el de eliminación auditada o la limpieza tras una fusión. Verificar que ningún flujo borra `crm.inversionistas`.

TEST GAPS:
- **Fusión:** alias con `creado_en` más antiguo y autor distinto. Verificar que la ventana y el autor se toman del alias, y que un `inversionista_datos_contacto` existente en el alias se lee y que el nuevo `revision=max+1` sube sobre él.
- **COOPAC con lead inactivo:** es el bug recién corregido y no tiene aserción explícita en `test-http.mjs`.
- **COOPAC histórica sin condiciones:** camino `vence_en` manual; y un intento de quitar condiciones ya existentes (debe rechazarse).
- **COOPAC anulada:** `puede_corregir=false` y rechazo del servidor.
- **Concurrencia mixta:** la corrección legacy `corregir_cierre_externo` entre la lectura y la escritura neutral debe dar PT409 por revisión.
- **Modo listado del lector (`p_inversionista null`):** que el nombre y teléfono corregidos aparezcan en la cartera y que Directorio no los vea. Incluir el rendimiento.
- **Paridad de flags de contrato:** gerencia, admin, gestor y analista contra el resultado real de `actualizar_contrato_con_cuenta_pdf_v3`.
- **Supervisor responsable:** con y sin autoría original.
- **Payloads mal tipados:** 22P02 y 22007.
- **Claves del payload de Directorio:** lista permitida.
- **UI:** `ClienteForm`/`ContratoCorregir` con `deshabilitado=true` no envían; refetch con error bloquea el guardado conservando el borrador.

ARCHITECTURE RISKS:
- Modificar por `replace()` textual dos funciones publicadas acopla esta migración a su texto exacto. Los guards md5 lo hacen seguro, pero frágil ante cualquier migración futura intermedia.
- Los flags `puede_corregir` duplican lógica de autorización de escritores heredados que no se modifican. Sin una tabla de paridad probada, divergen.
- Hay dos fuentes de datos actuales para la persona sin perfil: la fila neutral y la del lead. El nombre histórico del cierre se conserva, lo cual es correcto. Hay que documentar que `correo` no es corregible por esta vía.

SECURITY RISKS:
- Posible sobreexposición de columnas por `to_jsonb` bajo `security definer` (P2, hipótesis).
- La autorización de escritura de contacto se apoya en `inversionista_gestion_fn` invocada dentro de la misma transacción y con el mismo `auth.uid()`. Es correcto.
- El recibo se consulta antes del check de permiso. Es aceptable porque solo devuelve un resultado ya confirmado, siempre que `postventa_recibo` valide el actor y el hash del payload (no adjunto: verificarlo).
- La tabla nueva tiene RLS habilitado, permisos revocados (incluido `service_role`) y trigger de auditoría. Correcto.

REGRESSION RISKS:
- Rendimiento del lector canónico en los callers existentes (P1).
- La UI nueva bloquea correcciones de contrato que la ruta heredada permite (P2). No retirar la entrada heredada hasta cerrar la paridad.
- `corregir_cierre_externo` heredado ahora confirma sin actividad de negocio cuando el lead está inactivo (antes fallaba).
- Los hunks de eliminación (`inversion_id !== null` retirado en la ficha y en cartera) quedan fuera de alcance por instrucción del usuario. Aun así, requieren que `20260916160000` esté aplicada antes de publicar el frontend.

RECOMMENDED NEXT ACTIONS:
1. Reescribir el join de contacto del lector usando `identidades` o un CTE materializado, y medir el modo listado.
2. Completar el metadata `correccion_coopac` con antes/después económico y añadir el test de lead inactivo.
3. Alinear `inversion.puede_corregir` con los predicados exactos de `actualizar_contrato` y probar la paridad por rol.
4. Sustituir `to_jsonb(c)`/`to_jsonb(o)` por proyecciones explícitas, redactadas para Directorio.
5. Normalizar los errores de cast a 22023, añadir la comprobación posterior a los splices y el script `REVERTIR-20260916152851.sql`.

CONFIDENCE:
MEDIUM. El código SQL y TS adjunto es suficiente para los hallazgos P1 y P3. Los P2 de exposición y de paridad dependen de definiciones no adjuntas (`contratos_cartera`, `operaciones_cartera`, `es_admin` y `es_gestor_cartera`, `puede_registrar_ventas`, `postventa_recibo`).
