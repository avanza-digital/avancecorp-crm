# Ensayo de «El cliente ya convertido tampoco se duplica al editar un lead ni por su teléfono alternativo» (bloque 2.8)

Verifica la migración `20261022170400_crm_cliente_no_se_duplica_al_editar.sql` (la fecha definitiva se pone al integrar) **en el
banco Docker local (el laboratorio) y sin escribir nada**. Este ensayo **no se corre contra producción**: convierte clientes de verdad
por la puerta del formulario compartido, edita leads por la ficha (`crm.editar_lead_fn`), registra altas por la puerta real, hace
INSERT y UPDATE con y sin sesión, carga una base y prepara una conversión, siempre dentro de una transacción que termina en
`rollback`. La base de partida es el laboratorio **igual a producción con los seis bloques de la fase 2 aplicados** (2.1, 2.6, 2.3,
2.2, 2.4 y 2.7): la migración se apoya en el núcleo del 2.4 + 2.7 y en el disparador de disponibilidad de bases cargadas (B8).

**Ronda 3** (09/10/2026; revisiones del auditor de permisos y de Codex, `fase-2/bloque-2.8/revision/CONCILIACION.md`): el teléfono
alternativo **sin validar** (`telefono_alternativo_crudo`) no se pone ni cambia con sesión; **bajo la válvula privilegiada solo el DNI**
queda fuera de la regla (el teléfono y el alternativo se juzgan); la salida de la corrección de documento solo vale si cambia
únicamente el DNI; el preflight fija también la definición, el dueño y la ACL de las dependencias, los CHECK del alternativo y del DNI
y el inventario de los trinquetes; la reversa se niega si otra función, vista o policy usa la pieza. Casos F, V, E8, A7/A8 y R nuevos.

**Ronda 4** (09/10/2026; Codex r2 y auditor de permisos r2, la última ronda): el disparador **toma candado también por el teléfono
alternativo viejo y nuevo**, con la **misma clave** que el teléfono principal para el mismo número (la carrera del alternativo queda
serializada; casos K y el ensayo de **espera con dos sesiones**, `espera.sh`); el preflight fija además `private.bloquear_contactos_lead`
y `private.normalizar_telefono` y el CHECK `_crudo_cordura` tiene sus derivas; la reversa busca llamadores **sin distinguir
mayúsculas** y también en `cron.job.command` («posible llamador: inspeccionar antes de revertir»; los falsos positivos bloquean de
forma conservadora); E8g2 comprueba la persona del pasaporte, E8l exige el `P0481` con la migración y F2/F3a/F3b/F4/F7u usan cada uno
su lead.

**Reselle C2** (22/10/2026; plan AVANCE-BACKEND-1310-C2, encargo C2-a): contra producción del 22/10. El alta que deja el 2.4 re-asentado es `30109c53…`/`e06eca23…` (antes `01ebf089…`/`94ec2bd7…`: cambió por `20261015171407` y `20261016183308`) en el preflight, el postflight y el caso C4 del oráculo; el censo de los 30 `private.assert_*()` que se barren es `30|3cefe40e…` (antes `30|bc19c770…`: mismos 30 nombres, 10 definiciones cambiadas por producción); y el caso C6 fija las huellas de hoy de `crm.importar_lead_fn` (`5ba1ab45…`, Formulario 3 del 14 y el 15/10) y de la puerta de conversión `crm.preparar_persona_lead_inversion_fn` (`4eebf912…`, recorrido del 19/10), que este bloque no toca. Nada más cambia. En un laboratorio igual a producción, la conversión real de los clientes del oráculo usa `vence_en` = hoy + 12 meses, que desde `20261016195003` (cooperativas: 12 meses = 360 días) se rechaza: desde la ronda 2 de C2-a (22/10) el fixture usa hoy + 360 días.

## Qué prueba

La regla de Miguel (decisiones **D-28** y **D-30**, 08/10/2026; plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.8) sobre la del 2.7
(D-22, D-25, D-27): el teléfono, el teléfono **alternativo** o el DNI de un cliente ya convertido no pueden acabar en **otro** lead.
**Editar** un lead poniéndole uno de ellos se rechaza con el mismo `P0481` «Contacto no disponible» de hoy y el veredicto «ya es
cliente» (el de la regla del 2.7) en el detalle; lo mismo un **INSERT con sesión** que no sea el alta; y el **alta** cuenta ahora el
alternativo. El alternativo cuenta **en las dos direcciones**: lo tecleado (principal o alternativo) contra los dos teléfonos de cada
cliente. Se juzga **lo que la edición pone** (los valores que cambian), no lo que el lead ya tenía: los dos leads que ya comparten
teléfono con un cliente (D-23/D-25) siguen editándose. Con sesión, el alternativo **sin validar** (solo lo escribe la importación) no se
pone ni cambia a un valor no nulo (`42501` «El alternativo sin validar solo lo pone la importación»); conservarlo o borrarlo, como hoy.

| Caso | Qué exige |
|---|---|
| E1 | **Editar el teléfono** hacia el de un cliente ⇒ `P0481` con el veredicto exacto, nada guardado, ningún lead más con los contactos del cliente: **a** con persona y activo (el juicio de identidad: asesor y `via`) · **b** con persona y retirado (lo edita SUP1) · **c** sin persona (Gerencia; a nombre del dueño, sin `via`) · **d** sin persona y retirado · **e** sin dueño («sin asesor asignado») · **g** persona vetada con la bandera apagada (`no_contactar`) · **h** persona fusionada sin juicio (respaldo de D-21). |
| E2 | **Editar el DNI**: **a** con persona y la bandera encendida ⇒ lo rechaza YA la puerta del DNI (`P0409`, como hoy) · **b** con persona y la bandera apagada ⇒ `P0481` · **c/d** sin persona, activo/retirado ⇒ `P0481` · **e** el DNI de quien NO es cliente ⇒ se guarda como hoy. |
| E3 | **Editar el alternativo** hacia el teléfono de un cliente (hoy el disparador ni se dispara): **a** solo el alternativo · **b** con el nombre · **c/d** INACTIVO y COORD ⇒ `42501` «Acceso CRM revocado» (nunca ven el veredicto). |
| E4 / E5 | El teléfono hacia el **alternativo** de un cliente · el alternativo hacia el alternativo de un cliente ⇒ `P0481`. |
| E6 | **Negativos (la respuesta de hoy, exacta):** **a** edición ajena a los contactos · **b** el DUPLICADO HEREDADO (lead vivo con el teléfono de un cliente): b1 nombre y nota, b2 reenvía su mismo teléfono, b3 cambia su DNI a uno libre, b4 su alternativo a uno libre, b5 su teléfono a uno libre ⇒ todo se guarda · **c** teléfono libre · **d** teléfono de un lead vivo ⇒ el `tomado` de hoy · **d2** cliente con duplicado vivo ⇒ manda el `tomado` · **e** lead vetado ⇒ manda el `no_contactar` · **f** el propio cliente se edita (nota; intercambia sus dos teléfonos) · **g/h** quitar el alternativo / ponerlo libre · **i** INACTIVO, COORD y ADMIN ⇒ `42501` de hoy. |
| E7 | **Precedencia y prioridad** (edición): **a–c** entre teléfonos, lo tecleado como principal antes que el alternativo tecleado y, para cada uno, el principal del cliente antes que su alternativo (el que debe perder es el más reciente, para que una prioridad «plana» también caiga) · **d–g** por teléfono: enlazado → activo → más reciente → sin fecha detrás (ids fijos) · **h–k** lo mismo por DNI (j con la bandera apagada) · **l** el teléfono manda sobre el DNI (bandera apagada: un solo UPDATE). Medida: con la bandera encendida, `editar_lead_fn` pasa ANTES el DNI por su puerta y responde el cliente del DNI (los dos bloquean). |
| E8 | **Ronda 3, huecos de la edición:** **a** teléfono LIBRE + alternativo de un cliente en el mismo UPDATE ⇒ `P0481` · **b/c** desempate FINAL por `id`, por teléfono y por DNI (misma vinculación, actividad y fecha exacta; gana el id menor) · **d** el propio lead, excluido en la rama del alternativo (el cliente pone su principal como su alternativo ⇒ se guarda) · **e** `crm.editar_lead_documento_fn` real con DNI + teléfono de un cliente ⇒ `P0481` y **el DNI tampoco queda** · **f** con CE + alternativo de un cliente ⇒ `P0481`, **ni persona ni documento nuevos** · **g** DNI libre ⇒ se guarda · **g2** pasaporte libre ⇒ se guarda y se enlaza **a la persona que tiene ESE pasaporte** (ronda 4: lead ↔ persona ↔ identificador `PASAPORTE / E8G2X92408`, y la respuesta nombra esa persona y ese identificador) · **h/i** alternativo **internacional** y **fijo** de un cliente ⇒ `P0481` · **j** internacional libre ⇒ se guarda · **k** formato inválido (el teléfono de un cliente sin `+51`) ⇒ el `23514` del CHECK de hoy · **l** con espacios alrededor del teléfono de un cliente ⇒ se rechaza sin escribir; ronda 4: **con la migración se exige el `P0481`** del cliente (la pieza recorta), sin ella el `23514` de hoy. |
| A | **El alta con el alternativo** (respuesta, no error, nada creado): **1** el alternativo tecleado es el teléfono de un cliente · **2** el teléfono tecleado es el alternativo de un cliente · **3** alternativo contra alternativo · **4** (negativo) alternativo libre ⇒ `creado` · **5** (el 2.7) solo el teléfono de un cliente ⇒ respuesta · **6** el alternativo manda sobre el DNI · **7/8** (ronda 3) el **fijo** y el **internacional** de un cliente tecleados en otra forma (`019240866`; con espacios): el alta los canoniza y los reconoce. |
| I | **INSERT con sesión** que no es el alta (permisos de hoy en la medida I0: `authenticated` no tiene INSERT sobre `crm.leads`): **1** teléfono, **2** alternativo, **3** teléfono = alternativo del cliente, **4** DNI de un cliente sin persona ⇒ `P0481` · **5** contacto libre ⇒ entra. |
| B | **La carga de bases no cambia** (corre con la sesión de quien carga, pero su contacto nace dormido bajo su válvula): **1** una fila con el ALTERNATIVO de un cliente ⇒ `cargada` (como hoy: la carga no mira el alternativo) · **2** con el teléfono de un cliente ⇒ `ya_existia`. |
| S | **Sin sesión no cambia:** **1** el importador `crm.importar_lead_fn` con el teléfono de un cliente ⇒ `importado` (su contrato: no consulta la disponibilidad comercial) · **2/3** UPDATE sin sesión del teléfono / del alternativo ⇒ entran. |
| P | **Bajo la válvula privilegiada, el DNI no se juzga** (hasta D-38): **1** un UPDATE del DNI con sesión bajo `crm.op_privilegiada` hacia el DNI de un cliente ⇒ entra · **2** (medida) la preparación REAL de la conversión con el DNI de un cliente retirado sin persona. |
| F | **Ronda 3, el alternativo sin validar** (`telefono_alternativo_crudo`; el valor que se intenta es el teléfono de un cliente): **1** un UPDATE cuyo SET trae SOLO la cruda (prueba la lista de columnas) · **1b** el PATCH del auditor (quita el alternativo y pone la cruda) · **2** de una cruda heredada a otra · **5** un INSERT con cruda · **7u/7i** el UPDATE y el INSERT bajo CADA válvula (`op_privilegiada`; `op_privilegiada` + `correccion_documento`; `dni_por_puerta`; `op_bases_carga`) · **8** el DNI + la cruda bajo las dos válvulas de la corrección ⇒ todos `42501`, nada escrito · **3a/3b** conservar la heredada (el mismo valor en el SET; sin tocarla mientras la ficha cambia el teléfono) · **4/4b** borrarla (o cambiarla por un alternativo validado) · **6a/6b** sin sesión (UPDATE; el importador) ⇒ como hoy. Ronda 4: **F2, F3a, F3b, F4 y cada F7u usan su propio lead** y afirman antes su estado inicial (`exigir_cruda`): en ROJO cada uno es un cambio real a no nulo (o una conservación real), no un reenvío sobre lo que aceptó el caso anterior. |
| V | **Ronda 3, la válvula privilegiada:** **1/2** un UPDATE con sesión bajo `crm.op_privilegiada` que pone el teléfono / el alternativo de un cliente ⇒ `P0481` · con las dos válvulas de la corrección de documento, sobre un lead enlazado a su persona: **5** DNI + alternativo de un cliente y **6** DNI + teléfono de un cliente ⇒ `P0481` · **4** SOLO el DNI ⇒ entra (la salida de la corrección, como hoy). |
| R | **El reintento del 2.4 no cambia** aunque el alternativo tecleado sea ya el teléfono de un cliente ⇒ `reutilizado` con la misma ficha. Ronda 3: con precondiciones que distinguen **conservar** de **reescribir** el alternativo (**R1a**: la ficha nace con W, se teclea Z, conserva W; **R1**: tras el reintento sigue con W y ningún lead lleva el teléfono del cliente). **Medidas (sin arreglar, D-25):** **R2** un alta nueva reactiva un retirado cuyo **alternativo** conservado es el teléfono de un cliente activo ⇒ `reutilizado` (la ficha vuelve activa con ese alternativo) · **R3a** uno hallado por DNI que conserva el **teléfono** de un cliente activo ⇒ `ya_es_cliente` (lo para C-1 del 2.4) · **R3b** el mismo con el cliente retirado ⇒ `reutilizado` (la ficha vuelve activa con el teléfono del cliente). |
| K | **Ronda 4, las claves de candado** (auditor P3-4; se leen en `pg_locks` dentro de una subtransacción que se deshace; cada lead nace por la puerta real y recibe los contactos del caso con los disparadores apagados, para que sus claves no estuvieran tomadas): **1** solo el teléfono (el alternativo, que no cambia, también se bloquea) · **2** el alternativo de W a X (el viejo y el nuevo) · **3** de nada a X · **4** de W a nada · **5** teléfono y alternativo a la vez · **6** un INSERT con alternativo · **7a/7** la MISMA clave: la que pide X como teléfono es la que pidió X como alternativo en K2 · **8** un fijo · **9** un internacional · **10** un internacional de 9 dígitos (comparte clave con el móvil peruano «+51» + esos dígitos: espera de más, conservadora; medido). La clave es `telefono:` + `private.normalizar_telefono(<número>)`, la del teléfono principal. |
| C | Catálogo: **1** la pieza (si existe) INVOKER de postgres, STABLE, `search_path` vacío, EXECUTE solo postgres · **2** el núcleo y **3** el disparador DEFINER de postgres con su `proconfig` y EXECUTE solo postgres · **4** el alta, **5** el verificador y **6** lo que no se toca (ficha, puerta del DNI, otras puertas, carga, importador, piezas) con su huella · **7** los disparadores de tabla (con la migración, la de la edición con EXACTAMENTE sus ocho columnas) · **8** el gate interno del núcleo (A-5 del 2.4). |

**Decisiones del ensayo (para el Director):** (1) se juzga **lo que la edición pone** —el teléfono, el alternativo y el DNI que
cambian—, no la combinación resultante: así los duplicados que ya existen (D-25) pueden seguir corrigiendo su DNI o su alternativo
(E6b3/E6b4) y solo se impiden duplicados nuevos; juzgar la combinación entera los congelaría (mutante MD7). (2) Entre teléfonos,
**lo tecleado como principal primero y el principal del cliente antes que su alternativo** (grados 1–4): sin alternativos de por
medio es exactamente la búsqueda del 2.7 (los oráculos del 2.4 y del 2.7 dan lo mismo con y sin el 2.8); dentro de un grado, la
prioridad del 2.7. (3) La regla va **después** de todo lo que el disparador ya juzga hoy (vetos propios, enfriamiento propio,
verificador): esos veredictos siguen mandando (E6d2, E6e; mutante MD9). No es cierto, en cambio, que **ningún** código de hoy cambie:
el UPDATE directo del DNI hacia un cliente responde el `P0481` de la regla antes que el `P0409` de la identidad (H-7); con la identidad
encendida, la puerta del DNI decide a qué cliente se nombra (medida de E7l); y un alternativo con espacios alrededor del teléfono de un
cliente pasa del `23514` de formato al `P0481` (E8l, medido). (4) Solo **con sesión**; en el UPDATE, **bajo la válvula privilegiada se
juzgan el teléfono y el alternativo y solo el DNI queda fuera** (ronda 3; la conversión fija el documento de la persona: hasta D-38), y
la salida de la corrección de documento (`crm.correccion_documento`) solo vale si cambia únicamente el DNI; en el INSERT, todo lo que
nace con sesión salvo el contacto dormido de la carga de bases. (5) Si solo cambia el alternativo y es de un cliente, primero el rol
(42501 a quien no puede registrar) y después el veredicto; si no es de un cliente, nada cambia (ni rol, ni vetos, ni verificador).
(6) El alternativo **sin validar** no se juzga como teléfono (no es canónico): con sesión, simplemente no se pone ni cambia a otro valor
(`42501`, antes que todo lo demás, también bajo cualquier válvula); conservarlo o borrarlo, y todo lo que corre sin sesión, como hoy.

## Por qué así

El ensayo no prueba una copia: pega la **migración real** (preflight, postflight y comentarios incluidos) dentro de la transacción.
Los clientes con persona nacen por la **conversión real** del formulario compartido (como en el oráculo del 2.7); los sin persona,
por el alta real y una conversión sembrada; lo que la puerta real ya no permite montar (duplicados heredados, convertidos con id o
fecha fijos, la persona vetada o fusionada, un lead vetado) se siembra con los disparadores apagados y se declara en cada caso (el
duplicado que se EDITA nace por la puerta real —con su episodio y su SLA— y recibe el teléfono del cliente con los disparadores
apagados). Los actores del banco (`PASO08 …`) son **obligatorios** con su rol exacto y cada caso exige su precondición (p. ej. que
hoy el verificador diga «libre»: si no, el caso no mediría la regla y el ensayo aborta). La identidad se fija en las DOS formas de
los claims; no se usa `set role`, así que la RLS y los permisos por columna no se ensayan aquí (sección C y ronda del banco).

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó escrito);
`EJECUTAR_SQL_ADMIN`, el mismo como `supabase_admin` (solo la usan las derivas «cambio de dueño»). Los SQL generados van
a una carpeta de trabajo (`$SALIDAS`), no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración (la medición del defecto).
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"; $EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 72 fallo(s) de 124: «la edición se ACEPTÓ → nació un SEGUNDO lead del cliente» (E1–E5, E7, E8), «estado=creado
#      → el alta creó un SEGUNDO lead» (A1–A3, A7, A8), A6 (hoy responde por el cliente del DNI), «el INSERT con sesión se ACEPTÓ»
#      (I1–I4, F5, F7i), «el UPDATE con sesión se ACEPTÓ» (F1, F1b, F2, F7u, F8, V1, V2, V5, V6) y, ronda 4, «el disparador no pide
#      las claves de candado esperadas» (K1–K6, K7–K10: hoy el alternativo no se bloquea); los 52 negativos y de catálogo ya pasan
#      (también K7a: X como teléfono ya se bloquea hoy). Nunca un error de montaje.
# 2. VERDE: la migración real + el oráculo.
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs > "$SALIDAS/verde.sql"; $EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (124 comprobaciones)
# 3. Mutantes (catálogo en mutantes.py; cada uno debe morir nombrando sus casos):
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/cliente-no-se-duplica-al-editar/mutantes.sh
# 4. Derivas de la migración y de la reversa (y sus mutantes):
EJECUTAR_SQL="…" EJECUTAR_SQL_ADMIN="… --usuario supabase_admin" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/cliente-no-se-duplica-al-editar/derivas.sh
# 5. Reversa: aplicar → revertir → el núcleo del 2.7, el disparador de B8, la lista de columnas de hoy, sin pieza, foto idéntica.
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"; $EJECUTAR_SQL "$SALIDAS/reversa.sql"
# 6. Trinquetes: los private.assert_*() (los 36) y el censo, sin y con la migración (tienen que ser idénticos).
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs --trinquetes --sin-migracion > "$SALIDAS/t0.sql"
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs --trinquetes > "$SALIDAS/t1.sql"
# 7. Los oráculos del 2.4 (modo 2.7 «con», sin el fixture B7: el laboratorio ya lo tiene) y del 2.7, sin y con esta migración:
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs --oraculo 24 --sin-migracion > "$SALIDAS/o24-sin.sql"
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs --oraculo 24 > "$SALIDAS/o24-con.sql"
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs --oraculo 27 --sin-migracion > "$SALIDAS/o27-sin.sql"
node supabase/scripts/cliente-no-se-duplica-al-editar/armar-ensayo.mjs --oraculo 27 > "$SALIDAS/o27-con.sql"
#    → los cuatro VERDE (2.4: 67 comprobaciones; 2.7: 54) y las mismas respuestas sin y con (solo cambia la huella del núcleo).
# 8. Ronda 4 — la ESPERA ENTRE DOS SESIONES (dos ejecutores a la vez, cada uno con su paso; los dos con rollback):
EJECUTAR_SQL_A="… --paso espera-a" EJECUTAR_SQL_B="… --paso espera-b" DIR_ENSAYO="$SALIDAS/espera" \
  MIGRACION_RONDA3="<la migración de la ronda 3, opcional: el ROJO de la carrera>" bash supabase/scripts/cliente-no-se-duplica-al-editar/espera.sh
#    → con la migración B ESPERA a A (~2 s) poniendo X como alternativo y como teléfono; con la de la ronda 3 y con MK1 (sin el
#      alternativo en el candado) NO espera; con MK2 (el alternativo con la clave del DNI) solo espera alternativo contra alternativo.
```

El ensayo se arma para una base que **todavía no tiene** esta migración y **sí** tiene la del 2.7: su preflight exige el núcleo del
2.7 (`f74838f2…`/`c56e4abd…`) y el disparador de B8 (`5543c41f…`/`bfd4679b…`). En una base que ya la tiene, el oráculo se corre solo
(`--sin-migracion`) y entonces tiene que salir VERDE; los del 2.4 y del 2.7, con `--oraculo 24|27 --sin-migracion`.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--oraculo 24\|27 [--sin-migracion] [--mutante <archivo>]`, `--reversa`, `--reversa-deriva <archivo> [--espera "<texto>"]`, `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]`; modificadores `--migracion`, `--pruebas`, `--reversa-archivo`. Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo (casos de arriba; 124 comprobaciones). |
| `espera.sh` | Ronda 4: la **espera entre dos sesiones** (`armar-ensayo.mjs --espera-a` / `--espera-b alt\|tel`). La sesión B aplica la migración REAL y la ficha REAL pone X como alternativo o como teléfono de otro lead; la sesión A, a la vez, cambia el alternativo de un cliente a X y lo retiene. A no puede aplicar la migración ni escribir en `crm.leads` (el `CREATE TRIGGER` de B retiene `SHARE ROW EXCLUSIVE` y B reemplaza el cuerpo del disparador: B esperaría por la tabla o el catálogo, no por el contacto): ejecuta el disparador NUEVO como **copia** en `pg_temp`, generada desde el mismo bloque `$disparador$` de la migración (solo cambian su nombre y el de la pieza), sobre un clon temporal de un cliente real, y toma los candados reales; las dos sesiones imprimen el md5 del cuerpo que ejecutan y tiene que ser el MISMO. Mide la espera en B, la petición en espera en `pg_locks` (con `pg_blocking_pids`) y `pg_stat_activity` desde A. Modos: VERDE, ROJO (la migración de la ronda 3), MK1 y MK2. La carrera con COMMIT es de la branch (F4.6). |
| `mutantes.py` / `mutantes.sh` | 75 mutantes (ronda 4: **MK1** sin el alternativo en el candado del UPDATE, **MK2** el alternativo con otra clave, **MK3** sin él en el INSERT, **MK4** solo el nuevo; **ME5** el documento enlaza a OTRA persona; **MP29** la pieza sin recortar). De la ronda 3, 69: 30 de la pieza (el alternativo en cada dirección, los grados, la prioridad por teléfono y por DNI con su desempate final por `id`, el teléfono que manda, el DNI, la exclusión del propio lead, el formato, el juicio de la persona, activos/retirados), 3 del núcleo (sin el alternativo, sin la regla, también en el reintento), 28 del disparador (sin la regla del UPDATE, del alternativo o del INSERT; sin la columna en el disparador de tabla; también la carga de bases; también sin sesión, en el UPDATE y en el INSERT; la combinación entera; cualquier edición; antes de los vetos y del verificador; sin el rol; sin excluir el propio lead —en cada rama—; sin el alternativo en la rama del teléfono; sin el veredicto en el detalle; otro código; **ronda 3**: la cruda —lógica del UPDATE, lista de columnas, INSERT, también sin sesión en el UPDATE y en el INSERT, borrar, conservar—; la válvula —la exclusión COMPLETA de antes, cada rama por separado, también el DNI, la salida de la corrección sin sus condiciones nuevas—) y 8 de catálogo. Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra sus fallos**. `DIR_ENSAYO` obligatoria. |
| `derivas.sh` | 39 derivas instaladas ANTES de la migración (ronda 4: el CHECK `_crudo_cordura` quitado y cambiado; `private.bloquear_contactos_lead` con otro cuerpo y con un GRANT; `private.normalizar_telefono` con otra regla; de la ronda 3, las 34 de antes: núcleo: cuerpo, `SET`, INVOKER, `authenticated`, comentario; disparador: cuerpo, `SET`, `authenticated`, comentario; disparadores de tabla: otra lista, deshabilitados; alta: cuerpo, `anon`; verificador; `juicio_persona`; `bases_carga_nace_dormido`; `editar_lead_fn`; `fijar_dni_lead_fn`; `fijar_documento_lead_fn`; **ronda 3**: `editar_lead_fn` a DEFINER, `juicio_persona` STRICT, GRANT sobre `juicio_persona`, sobre el verificador y sobre `editar_lead_documento_fn`, cambio de dueño de `juicio_persona` —como superusuario—, el CHECK del formato del alternativo quitado, el del DNI cambiado, el de exclusión sin validar, un trinquete con otro cuerpo, uno más y uno menos; otra función con el nombre de la pieza; la migración ya aplicada), el control y un **mutante del preflight** (sin comparar los disparadores de tabla, la otra lista se pisa sin aviso). Al final, las **derivas de la reversa** (**18 escenarios = 1 control + 16 rechazos + 1 límite que entra**: control; `SET`, GRANT, cambio de dueño —como superusuario— y comentario del disparador; `SET` y comentario del núcleo; GRANT y cuerpo de la pieza; disparador de tabla deshabilitado; **ronda 3**: otro llamador de la pieza —una función PL/pgSQL, una vista, una función SQL `BEGIN ATOMIC`, una policy— y el **límite** medido: un llamador dinámico no se ve y la reversa entra; **ronda 4**: un llamador estático en MAYÚSCULAS, un `cron.job` que la nombra y un comentario que la nombra —falso positivo conservador—) y cinco mutantes de la reversa (RM1 aborta en el postflight; RM2 deja colar el GRANT; RM3, sin la comprobación de llamadores, deja roto al llamador PL/pgSQL; ronda 4: RM4, con la búsqueda de la ronda 3 que distingue mayúsculas, y RM5, sin mirar `cron.job`, dejan colar los suyos). `DIR_ENSAYO` y `EJECUTAR_SQL_ADMIN` obligatorias. |
| `reversa.sql` | GENERADA desde la migración (sus anclas, byte a byte; generador de la ronda 4 en `fase-2/bloque-2.8/salidas/ronda4/trabajo/generadores/`). **Falla cerrada:** exige la pieza, el núcleo, el disparador (cuerpo, definición, ficha, ACL y comentario) y los disparadores de tabla EXACTAMENTE como los deja la migración, y que **nadie más use la pieza** (otros cuerpos de función por texto **sin distinguir mayúsculas** —ronda 4—; los comandos de `cron.job`, si la tabla existe —ronda 4; con pg_cron, solo los trabajos que ve el rol que revierte—; vistas, policies, defaults, CHECK, disparadores y funciones `BEGIN ATOMIC` por `pg_depend`). La búsqueda textual es **conservadora**: un comentario, una cadena o el nombre de otra función con esa subcadena también la bloquean («posible llamador: inspeccionar antes de revertir»: se mira la referencia antes de seguir; nunca se borra a ciegas lo señalado); repone el núcleo del 2.7, el disparador de B8, la lista de columnas de hoy y los comentarios, y borra la pieza **sin CASCADE**; su postflight exige las huellas, fichas, ACL y comentarios del 2.7 y de B8. No deshace datos (la regla no escribe). **Límite:** una llamada construida en tiempo de ejecución o hecha desde fuera de la base no se ve. |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **La RLS y los permisos por columna no se ensayan** (todo corre como `postgres`, sin `set role`). `crm.editar_lead_fn` es INVOKER:
   en producción, quien no ve el lead recibe P0002 antes de llegar al disparador. La parte HTTP (la ficha de verdad) es la ronda del
   banco del 2.8.
2. **Dos ediciones simultáneas.** El oráculo corre en una sola conexión. Desde la ronda 4 el disparador bloquea también el
   **alternativo** viejo y nuevo con la misma clave que el teléfono principal (casos K): quien pone X como alternativo o como teléfono
   espera a quien está poniendo X como alternativo, y la regla juzga después con lo que el otro confirmó. `espera.sh` lo mide con dos
   conexiones en el laboratorio, las dos con rollback (B espera ~2 s; sin la clave del alternativo, no espera). **No ensayado aquí:**
   la carrera con COMMIT (que quien llega segundo reciba el `P0481`), que es de la branch (F4.6); y los **controles secuenciales**: la
   regla juzga lo que se escribe contra clientes YA convertidos, así que un cliente que pone como alternativo el teléfono de un lead
   ordinario no es «otro lead del cliente» para ella (dirección inversa, Codex r2: medir en F4.6; si importa, decisión de Miguel).
   Un internacional de 9 dígitos comparte clave con el móvil peruano «+51» + esos dígitos (espera de más, conservadora: K10).
3. **La pantalla**: desde la ronda 2 (D-36) la **edición** presenta el veredicto como el alta (`app/src/data/crm-api.ts`:
   `aErrorEditarLead` y la pieza común `presentacionDelP0481`); en la ronda 3, `aErrorInsertarLead` conserva el alcance del `try` de
   antes de D-36 (si registrar el bloqueo lanza, cae al error genérico; Codex F6, con su prueba).
4. **Otras puertas** (D-30, no se amplía el alcance): tomar un lead libre, reabrir, reactivar un contacto de base, la carga de bases (no
   mira el alternativo: B1 carga como dormido un contacto con el alternativo de un cliente), el importador sin sesión (S1) y la
   preparación de la conversión (P2) siguen como hoy.
5. **`telefono_alternativo_crudo`** (lo que el importador no pudo canonizar) no se compara: no es un teléfono canónico. Desde la ronda
   3, con sesión no se pone ni cambia a un valor no nulo (`42501`), así que nadie con sesión puede esconder ahí el teléfono de un
   cliente; lo que ya existe (lo puso la importación) se conserva o se borra. Un alternativo tecleado sin formato E.164 no casa con nada,
   pero el CHECK `leads_telefono_alternativo_formato` lo rechaza igual al guardar (E8k): por eso la migración fija ese CHECK como premisa.
6. **La huella de escritura** compara por contenido `crm.leads`, `crm.actividades` y `crm.lead_asignaciones`; las demás tablas que mira
   (`crm.tareas`, `crm.inversionistas`, `crm.inversionista_identificadores`, `crm.lead_sla_ciclos`), solo por número de filas.
7. **El barrido de trinquetes de la migración excluye los `*_mutantes`** (30 de 36), como el 2.7; el ensayo `--trinquetes` barre los 36.
   Desde la ronda 3, el preflight fija ANTES del primer barrido su inventario y sus definiciones (no exige que pasen).
8. **Instalación y rendimiento** (ronda 3, medidos en el laboratorio; la medida de verdad es la de la branch, F4.6): la transacción de la
   migración dura ~2–3 s y retiene el `SHARE ROW EXCLUSIVE` de `CREATE TRIGGER` sobre `crm.leads` ~0,9–1,6 s (seis corridas; el
   postflight barre los 30 trinquetes con el candado puesto); las consultas de la pieza recorren el índice parcial
   `idx_leads_convertido_en` (solo los convertidos): con 50 000 leads sintéticos y 5 000 convertidos, ~0,7–1,1 ms por llamada.
9. **Los ensayos de la ronda 3 que siembran estado heredado** (el alternativo sin validar de F, el lead enlazado a su persona de V5/V6/F8/V4)
   lo hacen con los disparadores apagados y lo declaran; la importación real con alternativo sin validar se prueba en F6b.
