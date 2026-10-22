# Ensayo de «El cliente ya convertido también se reconoce por teléfono (y por DNI)»

Verifica la migración `20261022170300_crm_cliente_por_telefono.sql` **en el banco Docker local (el laboratorio) y sin escribir
nada**. Este ensayo **no se corre contra producción**: convierte clientes de verdad por la puerta del formulario compartido, los
vuelve a registrar como lead nuevo con los actores del banco por la puerta real `crm.crear_lead_si_disponible` (y por
`crm.crear_lead_documento_fn`), siempre dentro de una transacción que termina en `rollback`. La base de partida es el laboratorio
**con el bloque 2.4 aplicado** (`20261022170200`): la migración cambia el núcleo de ese bloque.

**Reselle C2** (22/10/2026; plan AVANCE-BACKEND-1310-C2, encargo C2-a): el 2.4 se re-asentó contra producción del 22/10 (el alta cambió por `20261015171407` y `20261016183308`) y deja el alta en `30109c53…`/`e06eca23…` (antes `01ebf089…`/`94ec2bd7…`); el preflight y el postflight de esta migración y el caso 10a del oráculo fijan esas huellas nuevas. Nada más cambia (el núcleo del 2.4, `bf0a7531…`/`65b400ec…`, es el mismo). En un laboratorio igual a producción hay que tener en cuenta dos cosas que no son de este bloque: el fixture B7 del oráculo del 2.4 sobra (ya está B7) y la conversión real de los clientes del oráculo usaba `vence_en` = hoy + 12 meses, que desde `20261016195003` (cooperativas: 12 meses = 360 días) se rechaza. Ronda 2 de C2-a (22/10): `--oraculo-24` exige B7 en vez de instalarlo y el fixture usa hoy + 360 días.

## Qué prueba

La regla de Miguel (decisiones D-22, D-25 y **D-27**, 08/10/2026; hallazgo H-28, caso `L9f-tel` del banco; plan
AVANCE-BACKEND-0710-P3, fase 2, bloque 2.7): si alguien registra como lead nuevo a una persona que **ya es cliente** —su lead está
**convertido**, activo o retirado— escribiendo **solo el teléfono** (o el teléfono con **otro** DNI), o **su DNI con otro teléfono**
(D-27, ronda 2), el alta responde «ya es cliente» y **no crea, no reactiva y no escribe nada**. Precedencia: **teléfono → DNI →
candidato retirado del 2.4**. Enlazado a una persona ⇒ el mismo juicio de identidad que da el DNI (`ya_es_cliente` con su asesor
y `via = identidad`, o `no_contactar` si la persona está vetada; si el juicio no dice nada, el respaldo de D-21: `ya_es_cliente`,
`sin asesor asignado`, `via = identidad`). Sin persona ⇒ `ya_es_cliente` a nombre del dueño de esa ficha, **sin `via`** (decisión
del ensayo, abajo). El convertido gana a cualquier retirado no convertido que case por teléfono o DNI. El reintento del 2.4, un
lead activo vivo, la cuenta del Portal, el teléfono con el DNI del cliente, «no contactar» y los roles siguen como hoy.

| Caso | Qué exige |
|---|---|
| 1 | Convertido **activo** enlazado a persona, sin cuenta del Portal (conversión real de VEND1); VEND2 lo registra **solo por teléfono** ⇒ `ya_es_cliente` EXACTAMENTE igual al juicio que da el verificador con el DNI (`asesor` = responsable de relación VEND1, `via = identidad`); un solo lead con ese teléfono; ficha y persona intactas byte a byte; ninguna escritura (huella de leads, actividades, episodios, tareas, personas, documentos y ciclos SLA). **1b** SUP1 (parquea) · **1c** Gerencia con destino VEND3 · **1d** su propio dueño VEND1 ⇒ igual. |
| 2 | Convertido **retirado** (conversión real + retiro de Gerencia por API) solo por teléfono ⇒ igual; sigue `convertido|false` (no se reactiva). Es `L9f-tel`. |
| 3 | Teléfono del cliente con **otro DNI** ⇒ `ya_es_cliente` (D-25); ningún lead con el DNI tecleado. |
| 4 | Convertido **sin persona** (alta real + conversión sembrada, como 3d del 2.4) ⇒ `{"estado":"ya_es_cliente","asesor":"PASO08 VEND1"}`: **4a** activo, solo teléfono · **4b** activo, teléfono + su DNI · **4c** retirado, teléfono + su DNI (el escenario exacto del **3d del oráculo del 2.4**, que hoy espera `creado`) · **4d** sin dueño ⇒ `sin asesor asignado` · **4e** enlazado a una persona **fusionada** cuya canónica no tiene leads (el juicio devuelve nulo) ⇒ el respaldo de D-21. |
| 5 | Persona **vetada**: **5a** bandera encendida, vetada por su puerta (`crm.marcar_no_contactar`) ⇒ `no_contactar` (lo da YA el verificador, antes del núcleo: medido); **5b** bandera APAGADA dentro del rollback, persona vetada y su lead sin veto (sembrado) ⇒ el verificador dice «libre» y la regla responde `no_contactar` (juicio de la persona). |
| 6 | **Negativos que no cambian** (respuesta exacta de hoy, nada escrito): **6a** cliente con cuenta del Portal (CLI1 con ese teléfono, sembrado) ⇒ el `ya_es_cliente` del Portal (asesor VEND1, sin `via`) aunque el convertido sea de VEND2 · **6b** teléfono y DNI del cliente ⇒ el camino de identidad · **6c** retirado no convertido ⇒ se reactiva (2.4 intacto) · **6d** teléfono nuevo ⇒ `creado` · **6e** un lead activo vivo comparte teléfono con el cliente (duplicado heredado, D-23/D-25) ⇒ `tomado` (VEND1). |
| 7 | **Precedencia**: **7a** cliente retirado + retirado no convertido del mismo teléfono (hoy: el 2.4 lo reactiva, `reutilizado`) · **7a2** el mismo con el cliente activo (hoy: `creado`) · **7b** el retirado casa solo por el DNI tecleado (cliente retirado; hoy `reutilizado`) · **7c** el retirado está descartado con la espera vigente (`enfriamiento`; D-15 lo reactivaría) · **7d** (decisión del ensayo) un descartado **activo** con la espera vigente comparte el teléfono: hoy `enfriamiento`, con la regla `ya_es_cliente`. Siempre: el otro lead intacto. |
| 8 | **Reintento del 2.4** con el mismo `p_id` ⇒ idéntico a hoy aunque el teléfono sea también de un cliente convertido (duplicado heredado sembrado sin persona): **8a** ficha aún activa ⇒ `reutilizado`; tras un segundo retiro ⇒ `reutilizado` con la misma ficha y su segundo rastro · **8b** con el cliente heredado ACTIVO ⇒ sigue en `22023` «el alta original ya no se puede repetir» (R4-1 del 2.4). |
| 9 | Coordinador, membresía inactiva y admin sin rol CRM ⇒ `42501` antes de mirar nada, ficha intacta. **9e** puerta del documento con CE y el teléfono de un cliente ⇒ `ya_es_cliente`, sin documento ni identidad nuevos. |
| 10 | Catálogo: el alta intacta (cuerpo `01ebf089…`/`94ec2bd7…`, ficha, ACL); el núcleo DEFINER de `postgres`, `search_path` vacío, `lock_timeout 5s`, EXECUTE solo `postgres`; el verificador con la huella que fija la carga de bases; huellas de lo que no se toca (`tomar_lead_libre`, `reabrir_lead_fn`, `reactivar_lead_base`, `crear_lead_documento_fn`, la pieza `alta_reactivar_bloqueo_conservado`, `juicio_persona`, `inversionista_canonica`, `leads_de_personas`, `persona_en_conversion`); el gate interno del núcleo (A-5 del 2.4) sigue. Huellas en la medida 10e. |
| 11 | **Ronda 2 (D-27): el DNI de un cliente convertido**, con un teléfono nuevo: **11a** sin persona, activo · **11b** sin persona, retirado ⇒ `ya_es_cliente` a nombre del dueño, ningún lead nuevo, un solo lead con ese DNI · **11c/11d** con persona, activo/retirado, con la bandera APAGADA (el verificador no mira identidades y dice «libre») ⇒ el juicio de la persona · **11e** con persona y bandera encendida ⇒ lo bloquea YA el verificador (camino de identidad, medido) · **11f** el DNI de quien NO es cliente sigue su camino de hoy: retirado no convertido ⇒ se reactiva; persona sin lead ⇒ `creado` enlazado; lead activo ⇒ `tomado` · **11g** el **teléfono manda** sobre el DNI (teléfono de un cliente con persona + DNI de otro convertido sin persona) · **11h** el **DNI manda** sobre el candidato retirado del 2.4 (teléfono de un retirado no convertido + DNI de un cliente retirado; hoy `reutilizado`) · **11i** el reintento del 2.4 no cambia aunque el DNI sea de un cliente convertido. |
| 12 | **Ronda 3 (Codex P2): prioridad entre varios convertidos** que casan, con asesores distintos (duplicados heredados sembrados; los enlazados por la conversión real), un criterio aislado por caso: **12a/12d** el ENLAZADO a persona gana aunque esté retirado y sea más antiguo (teléfono / DNI con la bandera apagada) · **12b/12e** entre dos sin persona, el ACTIVO gana al retirado más reciente · **12c/12f** entre dos sin persona activos, el convertido MÁS RECIENTE gana (ronda 4: ids fijos, el menor para el que debe perder, así que quitar el criterio de la fecha cae siempre) · **12g/12h** (ronda 4) un convertido SIN fecha frente a uno con fecha: gana el que la tiene (`convertido_en desc nulls last`), por teléfono y por DNI. |
| medida | El estado real del banco, si está: los convertidos que dejó la corrida (conversión real) con teléfono propio ⇒ lo que responde un alta solo por teléfono (hoy `creado`: la sonda del Director). |

**Decisiones del ensayo (validadas por el Director en la ronda 2):** (1) el `ya_es_cliente` de un convertido **sin persona** va **sin `via`**: es el formato que
el núcleo del 2.4 ya sintetiza para un convertido sin persona (R3-1, pieza B1) y en el contrato de la app (`disponibilidad-lead.ts`)
`via = identidad` significa «reconocido por su documento»; la pantalla pinta lo mismo con o sin él. (2) La regla actúa con
«libre» **y** con «enfriamiento» (está después del filtro del veredicto del 2.4): así gana a un retirado en espera (7c, que D-15
reactivaría), y con un descartado **activo** en espera del mismo teléfono responde `ya_es_cliente` en vez de `enfriamiento` (7d;
los dos bloquean). Con cualquier otro veredicto (`tomado`, `en_bolsa`, `reutilizable`, `no_contactar`, el `ya_es_cliente` del
Portal o de identidad) manda el de hoy. (3) Con varios convertidos de ese teléfono (o de ese DNI): primero el enlazado a persona,
luego el activo, luego el más reciente (uno sin fecha de conversión, detrás de los que la tienen; con todo igual, el id menor).

## Por qué así

El ensayo no prueba una copia: pega la **migración real** (preflight, postflight y comentario incluidos) dentro de la
transacción. Los clientes con persona nacen por la **conversión real** del formulario compartido (alta → persona → solicitud
`prodelco` → comprobante como objeto de Storage sintético → confirmar), como el banco (L9f) y `conversion-inversion/test-conversion.sql`;
así el enlace, el documento verificado, el responsable de relación y el cierre del episodio son los de verdad. Lo que la puerta
real ya no permite montar con la regla instalada (duplicados heredados del mismo teléfono, la persona vetada con el lead sin
veto, la cuenta del Portal con ese teléfono, la persona fusionada) se siembra con los disparadores apagados, como en el 2.4, y se
declara en cada caso. Los actores del banco (`PASO08 …`) son **obligatorios** con su rol exacto (si falta uno, `ENSAYO ABORTADO`,
nunca verde) y cada caso exige su precondición (p. ej. que el verificador diga «libre»: si no, el caso no mediría lo que dice y
el ensayo aborta). La identidad se fija en las DOS formas de los claims; no se usa `set role`.

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un archivo `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó
escrito). Los SQL generados van a una carpeta de trabajo (`$SALIDAS`), no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración. Es la medición del defecto (H-28).
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"; $EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 32 fallo(s): «1-activo-solo-telefono: estado=creado … el alta creó un SEGUNDO lead del cliente», los demás
#      positivos por la misma causa (o `reutilizado` en 7a/7b/7c/11h: el 2.4 reactiva al otro retirado), 7d `enfriamiento`; los
#      negativos (5a, 6a–6e, 8a, 8b, 9, 10, 11e, 11f, 11i) ya pasan. Nunca un error de montaje.
# 2. VERDE: la migración real + el oráculo (termina SIEMPRE en excepción: eso es el veredicto).
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs > "$SALIDAS/verde.sql"; $EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (54 comprobaciones)
# 3. Mutantes (rompen una defensa DESPUÉS de la migración; el oráculo tiene que gritar nombrando su fallo):
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/cliente-por-telefono/mutantes.sh
# 4. Derivas (rompen el catálogo ANTES de la migración; su preflight tiene que negarse sin dejar rastro) y, al final, las derivas de la
#    REVERSA. EJECUTAR_SQL_ADMIN es OBLIGATORIA: el mismo ejecutor del laboratorio como superusuario (`lab_sql.py --usuario
#    supabase_admin`). Solo la usa la deriva «cambio de dueño» del núcleo: en el laboratorio `postgres` no puede dar el núcleo a
#    otro rol (ninguno más que `supabase_admin` tiene CREATE en `private` y `postgres` no es miembro de `supabase_admin`), así que
#    esa deriva la instala un superusuario dentro de su transacción, que termina en rollback; no se concede nada a nadie. Sin
#    ella, el guion se para al llegar a las derivas de la reversa (`EJECUTAR_SQL_ADMIN: …`).
EJECUTAR_SQL="…" EJECUTAR_SQL_ADMIN="… --usuario supabase_admin" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/cliente-por-telefono/derivas.sh
# 5. Reversa: aplicar → revertir → el núcleo vuelve a ser el del 2.4 (bf0a7531…/65b400ec…, ficha y comentario idénticos).
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"; $EJECUTAR_SQL "$SALIDAS/reversa.sql"
# 6. Reversa con un SET añadido al núcleo después de migrar: tiene que ABORTAR y no dejar rastro (falla cerrada). Las demás derivas de la
#    reversa (GRANT a authenticated o a service_role, cambio de dueño, comentario) y sus dos mutantes van al final de derivas.sh.
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --reversa-con-set > "$SALIDAS/reversa-con-set.sql"; $EJECUTAR_SQL "$SALIDAS/reversa-con-set.sql"
# 7. Trinquetes: la foto de los private.assert_*() y del censo, sin y con la migración (tienen que ser idénticas).
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --trinquetes --sin-migracion > "$SALIDAS/t0.sql"
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --trinquetes > "$SALIDAS/t1.sql"
# 8. El oráculo del 2.4 (reactivar-lead-retirado/pruebas.sql) con y sin esta migración. Su caso 3d lee el MODO esperado
#    (`ensayo.modo_2_7` = `con` | `sin`; si nadie lo pone, `sin`), que este armador fija según arme con o sin la migración:
#    espera `ya_es_cliente` (con) o `creado` (sin) y cae si el modo no coincide con el cuerpo del núcleo (`v_convertido`).
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --oraculo-24 --sin-migracion > "$SALIDAS/o24-sin.sql"
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --oraculo-24 > "$SALIDAS/o24-con.sql"
#    → VERDE en los dos (67): modo `sin` y regla «ausente» ⇒ `creado`; modo `con` y regla «PRESENTE» ⇒ `ya_es_cliente` y un
#      solo lead. Con `--modo-2-7 con|sin` se fuerza el desacuerdo y 3d tiene que caer («el armador esperaba el modo …»).
#    En una base que YA tiene esta migración (y la del 2.4), el oráculo del 2.4 se arma así: el armador del 2.4 no pone el modo
#    y su 3d caería a propósito (falla cerrada). Genera lo mismo que `--oraculo-24` menos la migración (comprobado en la ronda 4).
node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --oraculo-24 --sin-migracion --modo-2-7 con > "$SALIDAS/o24-base-con-2.7.sql"
# 9. El mutante M4 del 2.4 («la rama reactiva convertidos») con y sin esta migración (más sus dos controles):
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/m4" bash supabase/scripts/cliente-por-telefono/m4-del-2.4.sh
#    → controles VERDE; M4 muere nombrando «3d-convertido-retirado:» sin el 2.7 (3d y su reintento, más R3-1a) y con él (el
#      reintento de 3d y R3-1a).
```

El ensayo se arma para una base que **todavía no tiene** esta migración y **sí** tiene la del 2.4: su preflight exige el núcleo del
2.4 (`md5(prosrc)` `bf0a7531…`, `md5(pg_get_functiondef)` `65b400ec…`). En una base que ya la tiene, el oráculo se corre solo
(`--sin-migracion`) y entonces tiene que salir VERDE; el del 2.4, con `--oraculo-24 --sin-migracion --modo-2-7 con` (paso 8).

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--reversa`, `--reversa-con-set`, `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` del archivo se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]`, `--oraculo-24 [--sin-migracion] [--mutante <archivo>] [--modo-2-7 con|sin]` (el oráculo del 2.4 con su fixture B7, extraído textualmente de la migración B7 como hace su armador; con `--mutante`, un mutante del 2.4 encima; el modo esperado del 3d, el armado salvo que `--modo-2-7` lo fuerce), `--reversa-deriva <archivo> [--espera "<texto>"]` (aplicar → deriva → reversa; sin `--espera`, el control); modificadores `--migracion <ruta>`, `--pruebas <ruta>` (otro oráculo) y `--reversa-archivo <ruta>` (otra reversa). Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo (casos de arriba). |
| `mutantes.sh` | 34 mutantes: 29 de cuerpo (regla quitada; búsqueda por teléfono solo de activos / solo de retirados; deja pasar con otro DNI; regla después del candidato retirado; escribe una actividad; reactiva al cliente retirado; aplicada también al reintento; no juzga a la persona; antes del filtro del veredicto; «sin persona» con `via`; «sin persona» sin el dueño; sin el respaldo de D-21; **ronda 2:** regla del DNI quitada; solo sin persona; solo activos; después del candidato retirado; el DNI antes que el teléfono; **ronda 3:** los tres criterios de prioridad invertidos en la búsqueda por teléfono y en la del DNI; la regla escribe en OTRA ficha —solo la ve la huella por contenido—; **ronda 4:** los convertidos sin fecha primero (`nulls first`, que es también quitar el `nulls last`) y sin el criterio de la fecha, por teléfono y por DNI —mueren siempre: el id menor es el del que debe perder—) y 5 de catálogo (verificador modificado; núcleo INVOKER, con EXECUTE para `authenticated`, sin `search_path` vacío; alta con EXECUTE para `anon`). Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra sus fallos**. `DIR_ENSAYO` obligatoria. |
| `derivas.sh` | 15 derivas instaladas ANTES de la migración (más, al final, **las derivas de la REVERSA** —control, `SET`, GRANT a authenticated, GRANT a service_role, cambio de dueño como superusuario con `EJECUTAR_SQL_ADMIN`, comentario— y dos mutantes de la reversa: sin su comprobación del preflight aborta en el postflight; sin ninguna, el GRANT se cuela) (núcleo: otro cuerpo, otro `SET`, INVOKER, `authenticated`/`service_role` con EXECUTE, otro comentario; alta: otro cuerpo, otro `SET`, `anon`, `WITH GRANT OPTION`; verificador de 3 y de 2 argumentos; `juicio_persona`; la pieza del 2.4; migración ya aplicada), un control y un **mutante del preflight** (sin comparar `is_grantable`, la deriva `WITH GRANT OPTION` se cuela). `DIR_ENSAYO` y `EJECUTAR_SQL_ADMIN` obligatorias (paso 4). |
| `reversa.sql` | Quita los dos bloques insertados del núcleo (ancla única) y repone el comentario del 2.4. **Falla cerrada:** exige `md5(prosrc)` `f74838f2…`, `md5(pg_get_functiondef)` `c56e4abd…` y, desde la ronda 3, la ficha exacta (dueño, DEFINER, `proconfig`, ACL sin opción de concesión, nadie más con EXECUTE) y el comentario de la 2.7; su postflight exige la ficha y la ACL exactas del 2.4. No deshace datos (la regla no escribe). |
| `m4-del-2.4.sh` | (Ronda 2) El mutante M4 del 2.4 —con sus mismos fragmentos— contra el oráculo del 2.4, sin y con esta migración, y sus dos controles. `DIR_ENSAYO` obligatoria. |

## Límites conocidos (lo que este ensayo NO garantiza)

0. **Vías abiertas hasta el bloque 2.8 (D-28) y divulgación aceptada (D-29).** La edición del teléfono o del DNI de un lead
   (`crm.editar_lead_fn`), el INSERT directo en `crm.leads` si sigue concedido y el teléfono alternativo de un cliente siguen
   juzgándose con el verificador: pueden dejar un segundo lead de un cliente (se cierran en el 2.8; aquí no se ensayan). El alta
   revela «ya es cliente» y el asesor sin asentar la consulta: aceptado por D-29. La matriz de `test-rls.mjs` del auditor de permisos
   es requisito de la fase 4 (`MIGRACIONES.md`, sección de esta migración).

1. **El oráculo del 2.4 y esta migración (rondas 2 y 3).** Su caso 3d (convertido retirado sin persona con teléfono y DNI)
   esperaba `creado` («como hoy», D-15); D-22 lo cambia. Desde la ronda 3, 3d lee el **modo explícito** `ensayo.modo_2_7`
   (`con` | `sin`; **si nadie lo pone, `sin`**): espera `ya_es_cliente` con `con` y `creado` con `sin`, y **cae** si el modo no
   coincide con el cuerpo del núcleo (que declara `v_convertido` cuando lleva esta regla). Lo pone este armador (`--oraculo-24`,
   según arme con o sin la migración; `--modo-2-7` lo fuerza). El armador del 2.4 no lo pone: **en una base que ya tiene esta
   migración, su oráculo da 3d ROJO a propósito** (falla cerrada); ahí se arma con
   `node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --oraculo-24 --sin-migracion --modo-2-7 con` (genera lo mismo que
   `--oraculo-24` menos la migración: comprobado en la ronda 4). 3d lleva además un subcaso de **reintento** sobre una ficha que
   quedó convertida —el único camino que el 2.7 no intercepta— para que su mutante M4 siga muriendo con y sin el 2.7
   (`m4-del-2.4.sh`). Del 2.4 solo se tocaron ese caso de su oráculo y una línea de su README que remite a este comando.
2. **Dos altas simultáneas** no se ensayan (una sola conexión). La regla solo lee: corre bajo los candados de contacto que el
   alta ya tomó (`private.bloquear_contactos_lead`) y no escribe nada.
3. **Otras puertas** (carga de bases, formulario web, tomar un lead libre) y el **aviso previo** de la pantalla (`verificar_disponibilidad_lead`,
   que usa el verificador sin tocar) no cambian: el aviso previo puede decir «libre» y el servidor responde «ya es cliente» al
   confirmar (la pantalla lo pinta: `app/src/lib/store.tsx`, `presentarDisponibilidadLead`).
4. **El laboratorio está en el corte B6** (+ los bloques de la fase 2): B7–B10 de producción no se ensayan aquí (el oráculo del 2.4
   instala B7 como fixture solo en el modo `--oraculo-24`).
5. **(Cerrado en la ronda 2, D-27.)** El convertido sin persona que casa solo por el DNI ya responde `ya_es_cliente` (11a/11b).
   Quedan fuera de este bloque el **teléfono alternativo** de un cliente y otras puertas de alta.
6. **Los mutantes de catálogo mueren solo por el caso 10**: en el laboratorio todo corre como `postgres`, dueño de las funciones.
7. **La huella de escritura por contenido** (ronda 3) compara todas las filas de `crm.leads`, `crm.actividades` y
   `crm.lead_asignaciones` (barato en el laboratorio); las otras cuatro que mira —`crm.tareas`, `crm.inversionistas`,
   `crm.inversionista_identificadores` y `crm.lead_sla_ciclos`— solo por número de filas: una actualización ahí no se vería.
8. **El barrido de trinquetes de la migración excluye los `*_mutantes`** (30 de 36); el ensayo `--trinquetes` barre los 36.
9. **El último desempate, `l.id`** (dos convertidos con el mismo enlace a persona, el mismo estado —activo o retirado— y la misma
   fecha exacta: gana el id menor), no tiene caso propio: solo da determinismo, no es una regla de negocio. Los ids fijos de 12c/12f/12g/12h lo usan para
   que quitar el criterio de la fecha caiga siempre.
