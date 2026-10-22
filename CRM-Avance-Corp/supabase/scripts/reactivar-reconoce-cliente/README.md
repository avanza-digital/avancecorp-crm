# Ensayo de «Reactivar una ficha retirada —o un lead de la base— también reconoce al cliente» (bloque 2.11)

Verifica la migración `20261022170600_crm_reactivar_reconoce_cliente.sql` (la fecha definitiva se pone al integrar) **en el banco Docker
local (el laboratorio) y sin escribir nada**. Este ensayo **no se corre contra producción**: registra altas por la puerta real (también
por la del documento), convierte clientes de verdad por el formulario compartido, carga bases y reactiva por las puertas reales de la
base para gestión, siempre dentro de una transacción que termina en `rollback`. La base de partida es el laboratorio **igual a
producción con los siete bloques de la fase 2 aplicados** (2.1, 2.6, 2.3, 2.2, 2.4, 2.7 y 2.8 ronda 4): la migración parchea el núcleo
del alta que deja el 2.8 (`private.alta_reactivar_retirado`) y el de la reactivación de la base de B10
(`private.base_gestion_reactivar_capital_core`, 20261004223253), y crea una pieza que usa la del 2.8 (`private.juicio_cliente_convertido`).

**Reselle C2** (22/10/2026; plan AVANCE-BACKEND-1310-C2, encargo C2-a): contra producción del 22/10. En la lista de lo que llama a los núcleos (preflight y postflight), en la reversa (regenerada con `generar-reversa.py` de la ronda 3) y en el catálogo del oráculo, el alta que deja el 2.4 re-asentado es `e06eca23…` (antes `94ec2bd7…`: cambió por `20261015171407` y `20261016183308`); y el censo de los 30 `private.assert_*()` que se barren es `30|3cefe40e…` (antes `30|bc19c770…`: mismos 30 nombres, 10 definiciones cambiadas por producción). Nada más cambia. Los oráculos del 2.7 y del 2.8 que este armador lee son las copias de esta carpeta (`../cliente-por-telefono/`, `../cliente-no-se-duplica-al-editar/`), iguales byte a byte a las de `fase2` desde la ronda 2 de C2-a. La conversión real del oráculo usa `vence_en` = hoy + 12 meses, que desde `20261016195003` (cooperativas: 360 días) se rechaza: desde la ronda 2 de C2-a (22/10) el fixture usa hoy + 360 días.

## Qué prueba

Las reglas de Miguel (decisiones **D-42**, **D-55** y **D-61**, 09/10/2026; plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.11): cuando el
CRM va a **reactivar** un lead, lo que ese lead **conserva** —su teléfono, su teléfono alternativo y su DNI— no puede ser de un cliente
ya convertido (activo o retirado), sin contarlo a él. Si lo es, no se reactiva ni se escribe nada y se responde «ya es cliente de X» con
el veredicto del alta (mismo formato y datos; D-29): el alta lo **devuelve** (como hoy cuando lo tecleado es de un cliente; también en un
reintento, D-61); la base para gestión lo lleva en el detalle del mismo **`P0481` «Contacto no disponible»** con el que la edición y el
INSERT responden esa regla desde el 2.8. Hoy (medido en ROJO) la ficha o el lead vuelven activos con el contacto del cliente.

| Caso | Qué exige |
|---|---|
| A (alta) | La ficha RETIRADA nace por el alta real y la retira Gerencia; el cliente llega DESPUÉS con un contacto que ella conserva (sembrado). Reingresa VEND2 con lo que casa con la ficha ⇒ EXACTAMENTE la referencia (lo que responde hoy el alta al teclear el contacto del cliente), la ficha intacta, nada escrito, ningún lead activo más con los contactos del cliente: **A1** R2 (el alternativo conservado es el teléfono de un cliente activo) · **A2** R2 con el cliente **retirado** · **A3** R2 alternativo contra **alternativo** · **A4** R3b (el teléfono conservado es de un cliente retirado; hallada por el DNI) · **A5** R3b con un cliente **con persona** · **A6** el **DNI** conservado de un cliente retirado (tecleado solo el teléfono) · **A14** por la **puerta del documento** · **A9** el **reintento** (mismo `p_id`, tras un segundo retiro) de una ficha que CONSERVA el contacto de un cliente (**D-61**). |
| A sin cambio | **A7** R3a (cliente activo por el teléfono conservado: lo para la regla de hoy, con su veredicto) · **A8** R1 (el reintento con el alternativo TECLEADO de un cliente: lo tecleado en un reintento sigue fuera de la regla 1b) · **A10** sin coincidencia · **A11** el alternativo de un lead vivo que no es cliente · **A12** un alternativo internacional de 9 dígitos que no es el móvil peruano de un cliente (comparación literal) · **A13** lo conservado choca con un lead vivo y con un cliente: manda el «tomado» de hoy. |
| B (base) | El contacto se cargó cuando su teléfono era libre (o es un descartado de la cartera); el cliente llegó DESPUÉS. Reactivar ⇒ `P0481` con EXACTAMENTE la referencia en el detalle, el lead intacto, nada escrito y, ronda 3, **ninguna fila de la operación en `crm.actividades`** (ni el intento ni la reactivación): **B1** H-1 del 2.9 (alternativo de un cliente activo, `v2`) · **B2** el principal de un cliente activo · **B3** el principal de un cliente retirado · **B4** el alternativo de un cliente retirado · **B5** el alternativo de un cliente con persona · **B6** el DNI de un cliente retirado · **B7** un descartado de la cartera cuyo ALTERNATIVO es de un cliente (lo reactiva su analista) · **B8** la puerta sin capital (`crm.reactivar_lead_base`) · **B9** el intento «agendó cita» (`crm.registrar_intento_base_v2`): no se registra ni el intento. |
| B sin cambio | **B10** sin coincidencia y **B11** el alternativo de un lead vivo que no es cliente (reactivan, con su fila `reactivacion_base` en `crm.actividades`) · **B12** otro equipo (P0002: nunca ve el veredicto), **B13** No contactar (P0429) y **B15** un lead que ya no está en la base (22023): el error de hoy y, ronda 3, con el **detalle vacío** (un rechazo anterior a la regla no puede filtrar el asesor) · **B14** el replay de una reactivación ya hecha · **B16** un intento que no reactiva («no contestó»): el lead sigue en la base y, ronda 3, su **fila `intento_base:no_contesto` en `crm.actividades`**. |
| U/K (pieza) | **U1** la pieza nunca juzga al lead contra sí mismo · **K1** toma los candados de contacto de lo que el lead conserva (teléfono, alternativo y DNI) con la misma clave que el disparador. El ORDEN candado → juicio no lo prueba el oráculo: lo prueba `espera.sh` (modo «orden»). |
| H (medidas) | Otras puertas que devuelven un descartado a la cartera, que van al bloque **2.16** (D-62): **HR** «Reabrir» (`crm.reabrir_lead_fn`) y **HT** «Tomar un lead libre» (`crm.tomar_lead_libre`) con el alternativo de un cliente: hoy reabren (igual con la migración: no las toca). |
| C (catálogo) | **C1** la pieza: INVOKER de postgres, volátil, `search_path` vacío, EXECUTE solo postgres, con comentario · **C2** los dos núcleos la llaman una vez y conservan su ficha · **C3** nadie más la usa · **C4** lo que no se toca, con su definición de hoy (incluye `crm.reabrir_lead_fn` y el disparador de disponibilidad: al integrar con el 2.16 y el 2.13 cambian de estado, ver «Integración»). |

**Decisiones (D-61, D-62 y D-E2):** (1) el **reintento** del 2.4 también se juzga (A9; **D-61** de Miguel, «al reactivar», D-42 al pie de la
letra); lo tecleado en un reintento sigue fuera de la regla 1b (A8). (2) En la base, el veredicto viaja en un `P0481` y no como dato: las
puertas de la base responden a la pantalla un objeto `ok` o un error (un veredicto como dato se leería como «el servidor no confirmó»;
mutante M16). La pantalla tiene que decirlo como el alta (**D-E2** del Director, precedente D-36): ese cambio de app es de otro bloque. (3)
La pieza toma los candados de contacto **antes** de juzgar (serializa con un cliente que se pone ese número a la vez): `espera.sh` mide la
espera y, ronda 3, el **orden**. (4) La pieza `private.juicio_cliente_conservado(p_lead_id)` es **común** (nombre, firma y comentario sin nada
de una puerta): el bloque **2.16** (**D-62**) la reutiliza en «Reabrir», «Tomar un lead libre», «rescatar descartes» y «deshacer».

## Integración (grupo C): lo que cambia de estado con los bloques de al lado

- **Orden de instalación:** 2.8 → 2.9 → **2.11** → 2.10 / 2.13 / 2.16. El 2.11 exige por huella el núcleo del alta que deja el 2.8 y 22
  dependencias; si el 2.10 cambiara alguna (`juicio_persona`, `inversionista_canonica`, `persona_vetada`, `juicio_reapertura`) y se aplicara
  antes, el preflight del 2.11 se negaría (H-7): por eso va después (y el preflight del propio 2.10 se verifica contra ese estado).
- **Orden de reversas (al revés que la instalación):** antes de revertir el 2.11, retirar lo que añada llamadores de la pieza o cambie una
  de sus 22 dependencias —el **2.16** y, si toca, el **2.10**—; después el **2.11 antes que el 2.8** (la reversa del 2.8 se niega mientras la
  pieza del 2.11 use la suya). La reversa del 2.11 se niega mientras algo use la pieza: es lo correcto.
- **Oráculos:** el del **2.7** cambia en **8a y 11i** (D-61: con el 2.11 responden «ya es cliente de X»; con el mutante M9 encima vuelve a ser
  idéntico, la única causa es D-61): se actualizan sus esperados al integrar; en esta copia no se toca. El **C3** de este oráculo («solo
  los dos núcleos usan la pieza») y la búsqueda de llamadores del postflight y de la reversa verán a los llamadores del 2.16. El **C4** de
  este oráculo fija `crm.reabrir_lead_fn` (la cambia el 2.16) y `private.trg_leads_disponibilidad_atomica` (la cambia el 2.13), y el C6
  del oráculo del 2.8 fija también `crm.reabrir_lead_fn`: expectativas por estado de integración.
- **`cron.job` en la branch:** el preflight y el postflight consultan `cron.job.command` por la pieza y por los dos núcleos; en la branch
  hay que comprobar que `postgres` ve TODAS las filas (una lectura filtrada por RLS devolvería cero sin error).
- **PATCH directo:** un PATCH de `activo` false→true por PostgREST no es una vía: la policy `leads_update` solo deja actualizar filas con
  `activo = true` (comprobado por el auditor). El PATCH directo de `etapa` sobre un descartado activo con la bandera `resolver_en_puertas`
  APAGADA sí lo sería (con la bandera encendida, como en producción, lo para `trg_leads_zz_reapertura_solo_rpc`): va al 2.16 / a la lista
  de integración (la configuración que lo bloquea se exige o se cubre).

## Por qué así

El ensayo no prueba una copia: pega la **migración real** (preflight, postflight y comentarios incluidos) dentro de la transacción. La
referencia de cada caso es **lo que responde hoy el alta** al teclear el contacto del cliente (y se anota lo que dice la regla sola, la
pieza del 2.8: coinciden en todos los casos). Los actores del banco (`PASO08 …`) son **obligatorios** con su rol y su equipo exactos, el
bloque de contactos (+51 924 11xxxx / 7531xxxx) tiene que estar libre y la identidad unificada encendida (como en producción). Lo que la
puerta real ya no deja montar (un cliente que llegó después con el contacto de una ficha; un descarte de hace 40 días; el teléfono de un
cliente en una ficha retirada) se siembra con los disparadores apagados y se declara. No se usa `set role` (tumba el Postgres de esta
imagen): la RLS no se ensaya aquí; las puertas son DEFINER y resuelven rol y ámbito con `auth.uid()`.

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó escrito);
`EJECUTAR_SQL_ADMIN`, el mismo como `supabase_admin` (solo las derivas «cambio de dueño»). Los SQL generados van a una carpeta de trabajo
(`$SALIDAS`), no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración (la medición del defecto).
node supabase/scripts/reactivar-reconoce-cliente/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"; $EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 22 fallo(s) de 36: 8 fichas que el alta REACTIVA con el contacto de un cliente (A1–A6, A9, A14), 9 reactivaciones de
#      la base que se ACEPTAN (B1–B9) y 5 de la pieza y el catálogo (no existe); los 14 controles ya pasan.
# 2. VERDE: la migración real + el oráculo.
node supabase/scripts/reactivar-reconoce-cliente/armar-ensayo.mjs > "$SALIDAS/verde.sql"; $EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (36 comprobaciones)
# 3. Mutantes (catálogo en mutantes.py; cada uno debe morir nombrando sus casos; 21):
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/reactivar-reconoce-cliente/mutantes.sh
# 4. Derivas de la migración y de la reversa (y sus mutantes):
EJECUTAR_SQL="…" EJECUTAR_SQL_ADMIN="… --usuario supabase_admin" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/reactivar-reconoce-cliente/derivas.sh
# 5. Reversa: aplicar → revertir → los dos núcleos de antes (cuerpo, definición, comentario), la pieza borrada y la foto idéntica.
node supabase/scripts/reactivar-reconoce-cliente/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"; $EJECUTAR_SQL "$SALIDAS/reversa.sql"
# 6. Trinquetes: los private.assert_*() (los 36) y el censo, sin y con la migración (tienen que ser idénticos).
node supabase/scripts/reactivar-reconoce-cliente/armar-ensayo.mjs --trinquetes --sin-migracion > "$SALIDAS/t0.sql"
node supabase/scripts/reactivar-reconoce-cliente/armar-ensayo.mjs --trinquetes > "$SALIDAS/t1.sql"
# 7. Los oráculos del 2.4 (modo 2.7 «con», sin el fixture B7), del 2.7, del 2.8 y del 2.9 (con su migración delante), sin y con esta:
node supabase/scripts/reactivar-reconoce-cliente/armar-ensayo.mjs --oraculo 24|27|28|29 [--sin-migracion] > "$SALIDAS/oNN-….sql"
#    → sin la migración, los cuatro VERDE. Con ella: 2.4 idéntico; 2.7 ROJO SOLO en 8a y 11i (D-61: al integrar se actualizan sus
#      esperados); 2.8 VERDE y solo cambian sus medidas R2 y R3b (ahora «ya es cliente»); 2.9 VERDE y solo cambia su medida H1 (ahora
#      P0481). Con el mutante M9 encima, el del 2.7 vuelve a ser idéntico (la causa es solo D-61).
# 8. La espera entre dos sesiones y el ORDEN candado → juicio (cada ejecutor con su paso):
EJECUTAR_SQL_A="… --paso espera-a" EJECUTAR_SQL_B="… --paso espera-b" DIR_ENSAYO="$SALIDAS/espera" bash supabase/scripts/reactivar-reconoce-cliente/espera.sh
```

El ensayo se arma para una base que **todavía no tiene** esta migración: su preflight exige el núcleo del alta del 2.8 ronda 4
(`2fe5fdac…`/`8d598eb4…`) y el núcleo de la base de B10 (`479683a9…`/`7b781842…`). En una base que ya la tiene, el oráculo se corre solo
(`--sin-migracion`) y entonces tiene que salir VERDE.

## La espera entre dos sesiones y el orden candado → juicio (`espera.sh`)

Dos conexiones a la vez, las dos con rollback. **Sesión A** toma el candado de contacto del número X (la misma clave que
`private.bloquear_contactos_lead`) y lo retiene; en cuanto ve a alguien esperando por él, lo retiene 2,5 s más y lo suelta. **Sesión B**,
con la migración, reactiva un lead que conserva X: `pieza` (la pieza sola), `alta` (una ficha retirada cuyo alternativo es X) y `base` (un
contacto cuyo teléfono es X) ⇒ B espera (~2,5 s; A ve la espera en `pg_locks`); con el mutante **M15** (la pieza sin el candado) la
pieza no espera.

**Ronda 3 (Codex r1, P3), modo `orden`:** un mutante que juzgue ANTES y tome los candados después (**M17**: guarda el veredicto, toma los
candados, devuelve lo guardado) esperaría igual y pediría las mismas claves (K1). Se distingue **sin confirmar nada**: el juicio
(`private.juicio_cliente_convertido`) es lo único de la pieza que lee `public.perfiles`, y Postgres retiene el candado de tabla
(`AccessShareLock`) de cada relación leída hasta el final de la transacción. B instala **solo la pieza** tal cual la crea la migración (sin
su postflight, cuyo barrido de trinquetes leería `perfiles`), inserta el lead con los disparadores apagados sin tocar `perfiles`, comprueba
que no la tiene, y llama a la pieza; A, mientras B espera por X, mira en `pg_locks` si B ya tiene `perfiles`. Con la pieza real (md5
`78208791…`, el que sella el postflight; `espera.sh` lo exige) ⇒ **no** (el candado fue antes; al terminar sí la tiene: el juicio la lee);
con M17 ⇒ **sí** (juzgó antes): **M17 muere**. Lo que NO prueba el laboratorio: el veredicto de quien llega segundo con lo que el otro
**confirmó** (exige un COMMIT): `f46-contencion-con-commit.sql` es el guion para la branch (F4.6).

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--oraculo 24\|27\|28\|29 [--sin-migracion] [--mutante <archivo>]`, `--reversa`, `--reversa-deriva <archivo> [--espera "<texto>"]`, `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` de la deriva se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]`, `--espera-a`, `--espera-b pieza\|alta\|base\|orden [--mutante <archivo>]`; modificadores `--migracion`, `--pruebas`, `--reversa-archivo`. Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo (casos de arriba; 36 comprobaciones y las medidas). |
| `mutantes.py` / `mutantes.sh` | 21 mutantes del oráculo: los del encargo —**M1** sin el alternativo conservado, **M2** sin los retirados, **M3** sin excluir la propia ficha— y **M4** sin el teléfono, **M5** sin el DNI, **M6** cualquier lead (no solo clientes), **M7** normalizando el alternativo, **M8** la regla del alta antes de lo de hoy, **M9** la regla solo en altas nuevas (lo que D-61 descartó), **M10/M11** sin la regla en el núcleo del alta / de la base, **M12/M13/M14** la regla de la base antes del ámbito / del No contactar / del replay, **M15** sin el candado, **M16** el veredicto como dato, **M18** el rechazo del ámbito con el veredicto en el detalle (ronda 3), **MC1–MC4** catálogo. Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra sus fallos**. Aparte, el de concurrencia **M17** (juzga antes del candado), que mata `espera.sh`. `DIR_ENSAYO` obligatoria. |
| `derivas.sh` | 51 derivas instaladas ANTES de la migración (los dos núcleos y la pieza del 2.8: cuerpo, `SET`, INVOKER, GRANT, dueño —como superusuario—, comentario; ya aplicada y la pieza con otra firma; las 22 dependencias; otro llamador de los núcleos —PL/pgSQL, MAYÚSCULAS, vista, `BEGIN ATOMIC`, `cron.job`, del alta—; ronda 3: un `cron.job` y una función que ya NOMBRAN la pieza nueva; los CHECK quitados o cambiados; un trinquete cambiado o de más), el control y los **mutantes del preflight** (MP1, MP2, MP3 y, ronda 3, MP2c/MP3c con el `cron.job` que nombra la pieza). Al final, 13 **derivas de la reversa** y su control, y dos **mutantes de la reversa** (RM1 aborta en el borrado; RM2 muere). `DIR_ENSAYO` y `EJECUTAR_SQL_ADMIN` obligatorias. |
| `espera.sh` / `espera-b.sql` / `espera-orden-b.sql` | La espera entre dos sesiones (pieza, alta, base; M15) y, ronda 3, el orden candado → juicio (modo `orden`; M17). |
| `f46-contencion-con-commit.sql` | El guion de F4.6 (branch): la contención real con COMMIT —A confirma el alternativo del cliente mientras B espera— que el laboratorio compartido no puede ensayar. NO se ejecuta aquí. |
| `reversa.sql` | GENERADA desde la migración (sus anclas y sus frases, byte a byte; generador en `fase-2/bloque-2.11/salidas/ronda2/trabajo/generadores/`). **Falla cerrada:** exige la pieza y los dos núcleos EXACTAMENTE como los deja la migración, que nadie más use la pieza (funciones, `pg_depend`, `cron.job`) y las dependencias intactas; repone los dos núcleos y sus comentarios y borra la pieza sin CASCADE. No deshace datos (la regla no escribe). Sin cambios desde la ronda 2 (la ronda 3 no toca las anclas). |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **La RLS no se ensaya** (todo corre como `postgres`, sin `set role`); las puertas son DEFINER y resuelven rol y ámbito en el servidor.
   La parte HTTP es del banco.
2. **Concurrencia con COMMIT.** La espera y el orden candado → juicio se ensayan (`espera.sh`), pero en el laboratorio compartido nada se
   confirma: que quien llega segundo juzgue con lo que el otro confirmó se ensaya en la branch (F4.6, `f46-contencion-con-commit.sql`).
3. **La pantalla.** El alta ya presenta el veredicto. La base para gestión enseña hoy, con un `P0481`, el texto fijo «Ese teléfono o DNI
   no está disponible para este lead.»: el veredicto viaja en el detalle; presentarlo como el alta (D-E2, precedente D-36) es un cambio de
   app de otro bloque (descrito en el informe de la ronda 2 del 2.11).
4. **Otras puertas** que devuelven un descartado a la cartera (`crm.reabrir_lead_fn`, `crm.tomar_lead_libre`; por lectura de código,
   también `crm.rescatar_descartes`, `crm.deshacer_descarte` y las de deshacer) no cambian aquí: van al bloque 2.16 (D-62), que reutiliza
   la pieza (medidas HR y HT).
5. **`huella_escritura()`** compara el contenido entero de `crm.leads`, `crm.actividades` y `crm.lead_asignaciones` pero solo el número de
   filas de tareas, personas, identificadores y ciclos SLA; los siete `assert_*` que caen antes y después de la migración son FAIL
   heredados del laboratorio (se exige que no cambien, no que pasen).
