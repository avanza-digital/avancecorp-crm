VERDICT:
CHANGES_REQUESTED

SUMMARY:
El artefacto está bien construido: una sola transacción, guardas fail-closed sobre banderas, control/miembros, equipo+auth, lectores, 211 firmas (cuerpo/dueño/ACL), catálogo anti-función-nueva, 8 triggers, y conservación de fuentes antes/después. La reversa y el postflight son coherentes con eso.

Confirmo de forma independiente la refutación del P1 de la revisión 1: `private.postventa_modo()` llama `resolver_en_puertas_bajo_candado()` (advisory shared F3) **antes** del `for share nowait`, y ese `nowait` impide que un lector espere con filas tomadas. Todos los caminos mostrados toman advisory→filas en el mismo sentido, y ACTIVAR/REVERTIR usan idéntico orden de los cinco advisory. No hay ciclo ABBA; el 55P03 observado es `lock_timeout` al *adquirir*, no un deadlock.

También conviene explicitar un resultado fuerte que la evidencia ya contiene y que el EVALUACION no aprovecha: como el ensayo ejecutó `ACTIVAR.sql` **literal** contra el banco y pasó, entonces el banco coincide con producción en las 211 definiciones+ACL+owner pinneadas (incluidas `cartera_f5_fuentes_reales`, `postventa_modo`, `es_lector_global`, `cartera_inversionistas_estado_fn`, `postventa_estado_fn`), en los 8 triggers con su `tgenabled`, y no tiene funciones crm/private fuera del catálogo de 608. Eso hace el ensayo mucho más representativo de lo que sugiere la nota «local567sinextras».

Respuesta directa a la pregunta: **no queda ningún P0, y no hay P1 en el texto del SQL.** Sí queda un P1 operativo —el canal de ejecución no está especificado ni ensayado— que se descarga con una frase, no con un cambio de artefacto. Los demás hallazgos son P2/P3 y en su mayoría se cierran con disciplina de ejecución (sesión fresca, `ON_ERROR_STOP=1`, preflight de lectura con medición) más un fallback de reversa preaprobado.

FINDINGS:

[P1] Canal de ejecución no especificado; el único canal ensayado es psql directo
File:
CRM-Avance-Corp/supabase/scripts/multiempresa-f9/apertura-2026-09-15/banco.mjs (`args`), activar.plantilla.sql (`begin;` … `commit;` … `select … evidencia`)
Problem:
`ACTIVAR.sql` depende de control de transacción explícito y de que la última `select` corra **después** del COMMIT (`confirmado_despues_commit:true`). El ensayo usó `psql -X -qAt -v ON_ERROR_STOP=1 -f -` en sesión propia. La evidencia no dice por qué canal se ejecutará en producción.
Evidence:
`banco.mjs` fija el canal ensayado; el prompt solo dice «ejecutar este SQL exacto». Un editor SQL alojado, un `execute_sql` de MCP o una conexión al pooler en modo transacción pueden envolver el script en su propia transacción, partirlo por statement, no detenerse en el primer error o reutilizar sesión.
Impact:
Si el canal envuelve la transacción, el `commit;` no es final y la verificación «post-COMMIT» se vuelve intra-transacción: el recibo PASS dejaría de acreditar durabilidad. Si no se detiene en el primer error, se encadenan errores confusos sobre un estado ya revertido.
Recommendation:
Ejecutar con `psql -X -v ON_ERROR_STOP=1 -f ACTIVAR.sql` sobre conexión directa en **modo sesión** (no el pooler transaccional), sesión nueva por script, y guardar la salida completa como evidencia. Declararlo en el acta.

[P2] El recibo PASS puede reutilizar el resultado de una corrida anterior de la misma sesión
File:
activar.plantilla.sql
Lines:
`perform set_config('f9.resultado', …, false)` y el `select current_setting('f9.resultado')::jsonb || …`
Problem:
El GUC se fija con `is_local=false`, así que sobrevive al COMMIT (correcto para el diseño), pero también sobrevive a la corrida siguiente en la misma sesión.
Evidence:
Si en una sesión se ejecuta ACTIVAR con éxito y luego se vuelve a ejecutar, la segunda aborta por «Segunda activación…»; sin `ON_ERROR_STOP` el script sigue a `commit;` (que es ROLLBACK de la transacción abortada) y a la `select` final, que lee el `f9.resultado` **viejo** y recalcula `estado` contra el estado vivo —ya abierto— produciendo `PASS` con `fecha`/`milisegundos` de la corrida anterior. El ensayo no puede detectarlo porque `banco.mjs` abre un proceso psql por llamada.
Impact:
Recibo falsamente tranquilizador en el escenario más probable de reintento.
Recommendation:
Sesión nueva por ejecución + `ON_ERROR_STOP=1` (suficiente sin tocar el artefacto). Si se prefiere endurecer el SQL: incluir un nonce en `cfg` y exigir en la `select` final que `evidencia->>'referencia'` y ese nonce coincidan con los de esta corrida.

[P2] La garantía de «aborta si supera 3 s» es posterior al trabajo; la ventana real de bloqueo la acota `statement_timeout=30s`
File:
activar.plantilla.sql
Lines:
`set local lock_timeout='3s'` / `set local statement_timeout='30s'`; `inicio_bloqueo:=clock_timestamp()` tras el primer advisory; comprobación `clock_timestamp()-inicio_bloqueo>interval '3 seconds'` al final del bloque.
Problem:
`lock_timeout` solo acota la espera por *adquirir*. Mientras ACTIVAR retiene `pg_advisory_xact_lock('crm_flag_resolver_en_puertas')` en exclusivo, **todo** llamador de `resolver_en_puertas_bajo_candado()` (F2/F3, camino muy transitado) queda en espera. El chequeo de 3 s se evalúa al final: si el bloque tarda 12 s, se bloqueó 12 s y luego aborta.
Evidence:
El único dato productivo es 96,188 ms para una lectura de 614 fuentes (`revision-1/evidencia-complementaria.json`). No hay medición productiva de: el loop de 211 `pg_get_functiondef`+`md5`, el escaneo `select … from public.perfiles p where private.rol_crm(p.id)='directorio' …` (una llamada de función por fila de `public.perfiles`, cuya cardinalidad no consta), ni la segunda lectura de fuentes. El banco midió 64,267 ms con 231 fuentes, no 614.
Impact:
Latencia visible o errores de `lock_timeout` en usuarios reales durante la ventana; y un aborto tardío consume la captura de 2 h.
Recommendation:
Antes de ejecutar, correr en producción un preflight **de solo lectura** con exactamente los mismos SELECT (sin advisory y sin UPDATE) y reportar su duración; ajustar `statement_timeout` a un valor cercano al medido (p. ej. 10 s) y ejecutar en ventana de baja carga. Si el escaneo de `perfiles` domina, considerar reescribirlo como anti-join contra `crm.equipo` en vez de `rol_crm` por fila.

[P2] Precondiciones productivas no verificadas al momento de ejecutar; caducidad de captura vs. hash ensayado
File:
config.json (`captura` 2026-09-16T01:45:31Z, `vence_sql` 2026-09-16T03:45:31Z), activar.plantilla.sql (guarda `incoherentes<>0`)
Problem:
Cualquier deriva —una fusión que deje `inversionista_canonico_id` no nulo, una cuenta de equipo, un ACL, un trigger, un Directorio nuevo— aborta la apertura. Nada de eso está verificado contra producción *hoy*; y si se recaptura, `ACTIVAR.sql` deja de ser el byte-idéntico ensayado (`sha256 72a4f4c0…`).
Evidence:
`ensayo.json.sha256` fija los bytes ensayados; `crear-sql.mjs` reescribe los tres SQL con cada `config.json`. La guarda `incoherentes` no tiene contraparte medida en producción en la evidencia adjunta.
Impact:
Aborto que quema la ventana de 2 h, o ejecución de un artefacto no ensayado.
Recommendation:
(1) Preflight de lectura que devuelva el `count(*) filter (…)` de incoherentes, el `jsonb` de banderas/control/miembros/equipo/lectores/triggers y el diff del loop de 211, todo comparado contra `config.json`. (2) Verificar `shasum -a 256` de los tres SQL contra `ensayo.json` inmediatamente antes de ejecutar. (3) Si se regenera `config.json`, **volver a correr `ensayo.mjs`** (≈12 s) y registrar los hashes nuevos.

[P2] REVERTIR es apagado total, no retorno al estado previo, y su restauración caduca el 2026-09-21
File:
revertir.plantilla.sql
Problem:
Está aceptado y documentado que no restaura el piloto. La consecuencia operativa no está dimensionada: tras la reversa, las 4 personas del piloto pierden capacidades que **sí tenían antes** de F9 (`ensayo.json.estadosReversa`: las 24 con `habilitada:false`). Además los guardas de REVERTIR son estrictos (motivo exacto + las cinco banderas exactas); en un incidente en el que algo más haya cambiado, la reversa preparada se niega.
Evidence:
`config.json.control.vence_en = 2026-09-21T18:23:51Z`. Pasada esa fecha, reactivar el piloto a mano probablemente choque con `trg_piloto_f8_control_00_validar` (huella `47585a27…`), cuyo cuerpo no se adjuntó.
Impact:
El único rollback disponible es más restrictivo que el statu quo, y su ventana de restauración tiene fecha.
Recommendation:
Antes de ejecutar: (a) avisar a las 4 personas del piloto de qué significa una reversa; (b) preparar y dejar aprobado un fallback manual mínimo (los tres UPDATE de banderas bajo los mismos cinco advisory, en el mismo orden) para el caso de que los guardas de `REVERTIR.sql` se nieguen durante un incidente; (c) decidir explícitamente si antes del 21/09 se quiere además un `restaurar-piloto.sql`.

[P2 — hipótesis, confianza baja] Las pruebas de rol suplantado ocurren dentro de la transacción que se confirma
File:
activar.plantilla.sql (bucle `for actor in select distinct on(rol_crm) …`, previo al `commit;`)
Problem:
Se ejecutan `crm.cartera_inversionistas_estado_fn()` y `crm.postventa_estado_fn()` bajo `set local role authenticated` y claims de 4 personas reales, dentro de la transacción que **sí** se confirma. Si alguna de esas funciones registra acceso/auditoría, quedarán filas productivas atribuidas a personas que no hicieron ninguna petición.
Evidence:
Existen en el catálogo patrones de registro (`private.cartera_f5_registrar(text,uuid)`, `crm.acceso_inversion_fn`, `private.postventa_recibo`). El ensayo compara 18 superficies y sale igual (`hechos()`=`conservadas`), pero ninguna tabla de auditoría está entre esas 18. POSTFLIGHT no tiene este problema porque termina en `rollback`.
Impact:
Si se confirma, ruido de auditoría no explicable por sesiones humanas, justo en un sistema donde la trazabilidad es el argumento central.
Recommendation:
Un solo query cierra la hipótesis: `select oid::regprocedure, provolatile from pg_proc where oid in ('crm.cartera_inversionistas_estado_fn()'::regprocedure,'crm.postventa_estado_fn()'::regprocedure)`. Si ambas son `s`/`i`, el hallazgo queda refutado y basta anotarlo. Si alguna es `v`, revisar su cuerpo o mover las 4 pruebas a POSTFLIGHT (que ya cubre las 24).

[P3] El guard anti-función-nueva solo vigila `crm` y `private`
File:
activar.plantilla.sql (`where pronamespace in('crm'::regnamespace,'private'::regnamespace)`)
Problem:
`config.json.funciones` pinnea ~21 funciones `public.*` por cuerpo, pero el esquema `public` no se vigila contra firmas nuevas.
Impact:
Coherente con lo declarado en EVALUACION; solo conviene que el acta lo diga con esas palabras, no como «ninguna función nueva se acepta».
Recommendation:
Dejarlo como límite declarado, o extender el `in(...)` y el `catalogo_firmas` a `public` en un artefacto futuro.

[P3] Comparación de ACL por división en comas
File:
activar.plantilla.sql (`string_to_array(trim(both '{}' from p.proacl::text),',')`)
Problem:
Un grantee con coma en el nombre rompería el split. El manejo null/`{}` sí está bien resuelto por `(p.proacl is null)=(v_fn.acl is null)`.
Impact:
Marginal en este entorno; la comparación es determinista y falla cerrada.
Recommendation:
Si se reusa la plantilla, comparar `aclexplode(proacl)` agregado y ordenado en vez de texto.

[P3] `crear-sql.mjs` no descarta los delimitadores dollar-quote en el JSON inyectado
File:
crear-sql.mjs (`plantilla.replace('__CONFIG__', JSON.stringify(config).replaceAll("'","''"))`)
Recommendation:
Añadir `assert.ok(!/\$f9(_reversa|_verificar)?\$/.test(serializado))` junto a los asserts ya presentes. Hoy no aplica; es higiene del generador.

[P3] POSTFLIGHT sin `lock_timeout`
File:
postflight.plantilla.sql
Problem:
Solo fija `statement_timeout='30s'`. Si corre solapado con una reversa o un cambio de banderas, `postventa_modo()` devuelve 40001 y el bloque aborta con «Postventa falló para …», que se lee como fallo de capacidad y no como contención.
Recommendation:
Ejecutarlo secuencialmente tras ACTIVAR y, si aborta con 40001, reintentar antes de concluir nada.

[P3] Atribución `actualizado_por`
File:
activar.plantilla.sql / config.json (`responsable_id` `ebb19751…`, gerencia/admin)
Problem:
Queda registrada una persona responsable que no abrió sesión. El `motivo` nombra la autorización y la ejecución administrativa, lo que mitiga.
Recommendation:
Que el acta la firme quien autorizó, y que cite el `motivo` literal y el UUID, para que la atribución no dependa de la lectura del campo.

TEST GAPS:
- No hay ninguna **escritura** real de postventa por una persona recién habilitada. El ensayo cubre `postventa_estado_fn().habilitada` (bueno: es el indicador propio del producto, y muestra `false` para coordinación aun con la bandera global encendida) pero no una operación. Sugerido en banco, barato: tras la apertura, `crm.postventa_agendar_fn`/`postventa_solicitar_retiro_fn` como un vendedor **no** miembro del piloto → debe pasar; el mismo intento como coordinación → debe ser rechazado. Eso ataca exactamente lo que este cambio amplía (F6 de 4 actores a todos los que pasen `postventa_visible`).
- Las dos inversiones F4 del ensayo acreditan conservación bajo reversa, no capacidad nueva: `inversiones_escritura_bajo_candado()` ya devolvía `true` con el piloto *control* activo, para cualquier actor. Conviene no presentar ese caso como prueba de la ampliación.
- No se ensaya una segunda ejecución de ACTIVAR **en la misma sesión** (ver P2 del recibo).

ARCHITECTURE RISKS:
- Todo el camino F2/F3 se serializa por un único advisory global (`crm_flag_resolver_en_puertas`). Es correcto y es lo que da la atomicidad, pero convierte cualquier trabajo caro dentro de la transacción en latencia para toda la operación. La mitigación estructural para futuras aperturas es sacar del bloqueo las comparaciones de solo lectura (catálogo de funciones, triggers, lectores) a un preflight separado y dejar bajo candado únicamente lecturas de configuración + UPDATE + verificación.
- El banco cubre 567 de 608 firmas. Con el ensayo literal queda probado que coincide en las 211 pinneadas y en los 8 triggers; lo no cubierto son helpers transitivos fuera de esas 211. Riesgo residual real pero acotado.

SECURITY RISKS:
- `lectores_globales=[]` verificado y re-verificado dentro de ACTIVAR; la lectura del script reproduce fielmente las dos ramas de `es_lector_global()` (incluida la ausencia de `p.activo` en la primera). Sin objeción.
- La exclusión de coordinación se comprueba por dos vías (42501 en cartera, `habilitada:false` en postventa) para las 24 cuentas en POSTFLIGHT. Sin objeción.
- La suplantación por claims dentro de la transacción confirmada es el único punto donde el script actúa «como» personas reales: ver el P2 hipotético.

REGRESSION RISKS:
- 19 personas pasan de F6 apagado a F6 encendido en un instante, con el frontend publicado sin cotejar (ya listado como pendiente por PRIMARY). El código ejercitado es el mismo del piloto, así que el riesgo es de volumen, no de ruta nueva.
- Reversa = apagado total (P2 arriba).
- Comparación conservadora de fuentes bajo READ COMMITTED: una venta legítima entre las dos lecturas aborta todo. Aceptado y correcto; nótese que las escrituras F4 sí quedan bloqueadas durante la ventana (pasan por F3), así que la fuente realista de cambio son rutas de contratos/cierres que no toman F3.

RECOMMENDED NEXT ACTIONS:
1. Declarar y usar el canal ensayado: `psql -X -v ON_ERROR_STOP=1 -f`, conexión directa en modo sesión, sesión nueva por script (cierra P1 y el P2 del recibo).
2. Preflight de solo lectura en producción que devuelva, en una sola corrida: incoherentes=0, banderas/control/miembros/equipo/lectores/triggers idénticos a `config.json`, el diff del loop de 211, el `provolatile` de las dos RPC de estado, y **la duración** del conjunto. Ajustar `statement_timeout` con ese número y elegir ventana de baja carga.
3. Verificar `shasum -a 256` de `ACTIVAR.sql`/`REVERTIR.sql`/`POSTFLIGHT.sql` contra `ensayo.json` justo antes de ejecutar; si hubo recaptura, re-correr `ensayo.mjs` y registrar hashes nuevos.
4. Dejar aprobado el fallback manual de reversa y decidir hoy si se prepara `restaurar-piloto.sql` (la ventana del piloto vence 2026-09-21).
5. Ejecutar ACTIVAR → POSTFLIGHT inmediato → lectura real de cartera/fichas → acta con el recibo completo; si algún guarda aborta, revisar la causa y recapturar, sin reintentar a ciegas.
6. Opcional para cerrar el gap de tests, en banco y sin tocar producción: una escritura de postventa por un vendedor no-piloto y el mismo intento por coordinación.

CONFIDENCE:
MEDIUM — alta sobre la lectura del SQL, los órdenes de candado y la interpretación de `ensayo.json`; media sobre lo que depende de cuerpos no adjuntados (`trg_piloto_f8_control_00_validar`, `trg_multiempresa_flags_serializa_puertas`, `cartera_inversionistas_estado_fn`, `postventa_estado_fn`), de la cardinalidad de `public.perfiles` y del estado productivo actual, que no puedo consultar.
