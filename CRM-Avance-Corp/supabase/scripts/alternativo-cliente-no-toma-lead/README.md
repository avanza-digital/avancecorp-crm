# Ensayo de «El teléfono alternativo de un CLIENTE no puede ser el número de un lead que ya existe» (bloque 2.13)

Verifica la migración `20261022170700_crm_alternativo_cliente_no_toma_lead.sql` (la fecha definitiva se pone al integrar) **en el
banco Docker local (el laboratorio) y sin escribir nada**. Este ensayo **no se corre contra producción**: convierte clientes de verdad
por la puerta del formulario compartido, registra leads por el alta real, los retira y los descarta con la sesión de quien lo hace y
edita la ficha (`crm.editar_lead_fn`) o la fila (el UPDATE del PATCH, con y sin sesión, con y sin válvula), siempre dentro de una
transacción que termina en `rollback`. La base de partida es el laboratorio **igual a producción con los siete bloques de la fase 2
aplicados** (2.1, 2.6, 2.3, 2.2, 2.4, 2.7 y 2.8 en su ronda 4): la migración se apoya en el disparador de disponibilidad y en la pieza
`private.juicio_cliente_convertido` que deja el 2.8.

**Ronda 2** (10/10/2026; auditor de permisos r1, PASS con cinco P3, `fase-2/bloque-2.13/revision/CONCILIACION.md`; decisiones **D-64**,
**D-65** y **D-67** de Miguel): «es cliente» = la ficha ya era `convertido` o lo queda bajo la válvula privilegiada —una conversión
ilegal sin válvula no llega a la regla y la para después la guarda de la conversión SIN veredicto (P3-1; casos N14a/N14b, T15/T15b y
N7b/N7c bajo la válvula, mutantes MD12–MD17)—; la pieza solo mira leads vivos cuyo teléfono principal ve el verificador y el conjunto
real de veredictos queda declarado y probado (P3-3; T17 `ya_es_cliente` por un perfil del Portal, N12b, mutante MP12); lo que revela el
rechazo queda asentado por D-67 (P3-2); D-64, D-65 y el alternativo sin validar quedan declarados (P3-4, P3-5).

**Reselle C1** (13/10/2026; plan de la fase 4, paso C1): el censo de `private.assert_*()` del preflight pasa a la forma del 2.10: se fijan los
**29** que ningún bloque toca (`29|a11bf250ba574535d3f4dc2f8d1f6a14`, medido en el laboratorio de hoy) y de
`private.assert_gestion_diaria_resultado()` —que re-sella el 2.16— solo se exige que **exista**; así la migración entra igual sobre el
laboratorio sin el 2.16 y detrás del 2.9 → 2.11 → 2.16 (con la forma anterior, `30|bc19c770…`, el preflight se negaba detrás del 2.16). El
barrido y la foto antes/después del postflight (30 trinquetes, resultado por resultado) no cambian: comparan el RESULTADO, no la huella.
Derivas nuevas: el trinquete del 2.16 borrado o renombrado ⇒ se niega; otro de los 29 con otra definición ⇒ se niega; el trinquete del 2.16
re-sellado ⇒ ENTRA (control RS). La regla, los mensajes, los candados y las demás huellas no cambian.

**Reselle C2** (22/10/2026; plan AVANCE-BACKEND-1310-C2, encargo C2-a): el censo de los 29 `private.assert_*()` que ningún bloque toca pasa a la medida de producción del 22/10, `29|60a0851245859d8e1f0da6e2276a2594` (antes `29|a11bf250…`: mismos 29 nombres, 10 definiciones cambiadas por producción —SLA por filas del 17/10, pendientes recientes del 20/10 y otras—); la forma (29 + que exista el trinquete del 2.16) y el resto del kit no cambian. La conversión real del oráculo usa `vence_en` = hoy + 12 meses, que desde `20261016195003` (cooperativas: 360 días) se rechaza: desde la ronda 2 de C2-a (22/10) el fixture usa hoy + 360 días.

## Qué prueba

La regla de Miguel (decisión **D-49**, 09/10/2026; plan corto aprobado **D-50**; plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.13):
al poner o cambiar el teléfono **alternativo** de un **cliente** (la ficha queda `convertido`), con sesión, si el número nuevo —en su
**forma canónica**, la de `private.canonizar_contacto`— es el teléfono o el alternativo de **otro lead vivo** (activo, ni convertido ni
descartado: el dominio del «tomado» de la disponibilidad), el CRM lo **rechaza** con el **mismo** `P0481` «Contacto no disponible» y el
**mismo veredicto** que la disponibilidad da hoy al teléfono principal de ese lead —la pieza llama al verificador sellado—: «tomado» con
su asesor, «en_bolsa» si no tiene dueño o, si está vetado, el veto «no_contactar» sin asesor; byte a byte, para que la pantalla lo
muestre igual (D-36). La regla del 2.8 (el número de **otro cliente** ⇒ «ya es cliente de X») va antes y manda; si solo cambia el
alternativo y hay veredicto, primero el rol (42501 a quien no puede registrar leads). «Cliente» = la ficha ya era `convertido` o lo
queda bajo la válvula privilegiada `crm.op_privilegiada` (la conversión real); una conversión ilegal sin válvula no llega a la regla.

| Caso | Qué exige |
|---|---|
| T1 | El alternativo nuevo del cliente es el **teléfono** de un lead vivo ⇒ `P0481` con el veredicto exacto (`tomado`, asesor, `tenencia_desde` y `ultima_conversacion_en` de una conversación real), nada guardado, el otro lead intacto: **a** lo edita el dueño del cliente · **b** lo edita el supervisor del dueño. |
| T2 | … es el **alternativo** de un lead vivo (hoy la disponibilidad ni lo ve: «libre») ⇒ `P0481` con el veredicto de ese lead por su teléfono. |
| T3 | … es el teléfono de un lead **en la bolsa** (sin dueño) ⇒ `P0481` `{"estado":"en_bolsa"}`. |
| T4 | El cliente cambia a la vez su **teléfono** (libre) y su alternativo (de un lead vivo): la rama del cambio de teléfono ⇒ `P0481`. |
| T5 | **Forma canónica**: el número del lead vivo escrito **sin +51** (a) o **con espacios** (b) ⇒ `P0481` del lead vivo (hoy, el `23514` del CHECK de formato). |
| T6 | **El rol primero**: Coordinación (a) y un usuario sin rol CRM (b) ⇒ `42501` «Acceso CRM revocado», sin veredicto. |
| T7 | Bajo la válvula privilegiada `crm.op_privilegiada` (con sesión) se juzga igual ⇒ `P0481`. |
| T8 | **Precedencia**: el número es el teléfono de un lead vivo (id alto) y el alternativo de otro (id bajo) ⇒ manda el del teléfono. |
| T9 | **Desempate** entre dos leads vivos que lo tienen como alternativo ⇒ el de id menor. |
| T10 | Un cliente **retirado** también es cliente ⇒ `P0481`. |
| T11 | El número es el alternativo de **otro cliente** y el teléfono de un lead vivo ⇒ manda la regla del 2.8 («ya es cliente»), como hoy. |
| T12 | El cliente que YA comparte su alternativo con un lead vivo (heredado) no puede **cambiarlo** al número de otro lead vivo. |
| T13 | El lead vivo está en la **bandeja de un supervisor** (sin analista) ⇒ «tomado» a nombre del supervisor (el respaldo del verificador). |
| T14 | El lead vivo está **vetado** («No contactar») ⇒ `P0481` `{"estado":"no_contactar"}`: el veto, sin el nombre de quien lo tiene (lo que hoy da la disponibilidad para ese número). |
| T15 | **La propia ficha no tapa a otro lead** (ronda 2: bajo la válvula privilegiada, como la conversión real): un lead vivo que en el MISMO UPDATE pasa a convertido y pone como alternativo su propio teléfono, que es también el alternativo de otro lead vivo ⇒ el `P0481` de ese otro lead (si la propia ficha entrara en la búsqueda, la elegiría primero y el veredicto saldría «libre»). **T15b**: lo mismo por la rama del teléfono (cambia además su teléfono a uno libre). |
| T16 | **Un retirado no tapa a un vivo**: el número es el teléfono de un lead retirado y el alternativo de un lead vivo ⇒ manda el vivo. |
| T17 | **El lead vivo tiene el teléfono de un perfil ACTIVO del Portal** (ronda 2, P3-3; sembrado como 6a del 2.7: el lead nace por la puerta real y después el perfil cliente del banco `PASO08 CLI1`, asesor VEND1, recibe ese teléfono con los disparadores apagados) ⇒ `P0481` `{"estado":"ya_es_cliente","asesor":"PASO08 VEND1"}`: el verificador mira el Portal antes que el «tomado»; el asesor es el del perfil, no el dueño del lead ni quien edita. |
| N1 | El alternativo **libre** se guarda. |
| N2 | Un lead que **no es cliente** pone como alternativo el teléfono (a) o el alternativo (b) de un lead vivo, o cambia a la vez teléfono y alternativo (c) ⇒ se guarda (fuera de D-49). |
| N3 | **Retirado** (activo=false). **N3m** (medida que decide el caso): hoy la disponibilidad del teléfono principal da «libre» para un retirado y el cliente puede ponerse ese número como **teléfono** ⇒ la regla hace lo mismo: el alternativo del cliente = teléfono (a) o alternativo (b) de un retirado ⇒ se guarda. |
| N4 | **Descartado** en enfriamiento. **N4m** (medida): hoy el teléfono principal del cliente no puede ser el de un descartado en enfriamiento (`P0481` «enfriamiento», el verificador). **N4a**: el alternativo del cliente sí (no es «tomado»: fuera del encargo; ver «Límites»). |
| N5 | D-25, el **duplicado heredado**: el cliente ya comparte su alternativo con un lead vivo; lo que la edición no toca no se juzga: **a** nombre y nota · **b** reenvía su mismo alternativo · **c** cambia su teléfono (libre) y reenvía el alternativo · **d** pasa su alternativo a uno libre ⇒ todo se guarda. |
| N6 | **Sin sesión** (escritura interna) ⇒ se guarda, como hoy. |
| N7 | **La propia ficha**: **a** el cliente pone su propio teléfono como alternativo ⇒ se guarda · **b/c** (ronda 2: bajo la válvula privilegiada) un lead vivo que en el MISMO UPDATE pasa a convertido y pone como alternativo su propio teléfono (c: cambiando además el teléfono) ⇒ la respuesta de hoy bajo la válvula (`P0001` «Un lead convertido debe estar enlazado a un perfil de cliente», de `private.leads_before_update`, que corre después), nunca el `P0481` contra sí misma. |
| N8 | El número de **otro cliente**: lo juzga el 2.8, como hoy («ya es cliente»). |
| N9 | **Quitar** el alternativo se guarda. |
| N10 | El **INSERT** con sesión no cambia (un lead nuevo no es cliente). |
| N11 | **Forma canónica, el otro lado**: un internacional de 9 dígitos (`+924130199`) no es el móvil peruano con esos dígitos (`+51924130199`, de un lead vivo) ⇒ se guarda (la forma del candado, `normalizar_telefono`, los junta: una espera de más, nunca un rechazo de más). |
| N13 | **Medida, fuera del encargo (H-2; D-65: se cuenta antes de publicar)**: el cliente cambia su **teléfono principal** al **alternativo** de un lead vivo ⇒ se guarda, hoy y con la regla (la disponibilidad del principal solo mira los teléfonos principales de los otros leads; D-49 habla del alternativo). Y la medida **H1** (montaje de N5; D-65): un lead que nace por el alta real con el alternativo = el teléfono de un lead vivo y se convierte por la conversión real queda cliente con ese número (la regla no lo ve: la conversión no pone ni cambia el alternativo). |
| N14 | **Conversión ilegal sin válvula** (ronda 2, P3-1): un lead vivo propio que en el MISMO UPDATE pasa a convertido —sin `crm.op_privilegiada`, lo que haría un PATCH forjado— y pone como alternativo el teléfono de otro lead vivo ⇒ para la regla no es cliente: la respuesta de hoy (`P0001` «La conversión a cliente solo se hace vía la operación de conversión») **sin veredicto en el detalle**: no sirve para sondear de quién es un número. **a** rama del alternativo · **b** rama del teléfono. |
| N12 | **Límite declarado**: un lead vivo HEREDADO con su teléfono principal fuera de la forma canónica (sembrado: hoy el disparador ya no deja escribirlo) es invisible para la disponibilidad («libre» para su número) y la pieza no lo mira: si el alternativo nuevo de un cliente es el alternativo de ese lead, se guarda, como hoy. **N12b** (ronda 2, P3-3): el mismo heredado y OTRO lead vivo cuyo principal canónico es el suyo normalizado ⇒ se guarda igual: la pieza no hace nombrar a otro lead por el número normalizado (sin el filtro del principal visible, respondería «tomado» de ese otro lead). |
| K1 | **El candado por número** (ronda 4 del 2.8): cambiar el alternativo de un cliente pide `telefono:` + el número, la misma clave que pide quien pone ese número como teléfono; el disparador la toma antes de juzgar. |
| C | Catálogo: **1** la pieza (si existe) INVOKER de postgres, STABLE, `search_path` vacío, EXECUTE solo postgres · **2** el disparador DEFINER de postgres con su `proconfig` y EXECUTE solo postgres · **3** los disparadores de tabla del 2.8 · **4** la pieza del 2.8, el núcleo del alta y el verificador intactos · **5** el disparador llama tres veces a la pieza del 2.8 y dos a la del 2.13 (ninguna sin la migración). |

**Decisiones del ensayo (para el Director):** (1) «otro lead activo que no es cliente» = el dominio del «tomado» del verificador
(`activo = true` y etapa ni `convertido` ni `descartado`), con su veredicto (`tomado` o, sin dueño, `en_bolsa`); el **retirado** queda
fuera porque la disponibilidad del teléfono principal hoy lo da por libre (N3m, medido) —como pide el encargo, «haz lo mismo»—; el
**descartado** queda fuera porque no es «tomado» (el principal lo para con «enfriamiento»/«reutilizable»: N4m; extenderlo sería otra
decisión). (2) «Es cliente» = la ficha ya era `convertido` o lo queda bajo la válvula privilegiada (`new.etapa = 'convertido' and (old.etapa =
'convertido' or v_priv)`; ronda 2, auditor P3-1): así la conversión real que cambia el alternativo se juzga (T15/T15b), la exclusión de la
propia ficha tiene casos que la distinguen (N7b/N7c, T15) y una conversión ilegal sin válvula no recibe veredicto (N14a/N14b). (3) Forma canónica = la de
`private.canonizar_contacto` (la del alta y la del CHECK), no la del candado (`normalizar_telefono`, conservadora: N11). (4) El veredicto
NO se construye en la pieza: es el que el verificador da HOY al teléfono principal del lead encontrado (sin DNI y sin la ficha que se
edita), así que es el mismo byte a byte (cada caso lo compara contra `private.verificar_disponibilidad_lead_impl`) y sigue al verificador
si algún día cambia; el conjunto real (ronda 2, P3-3): `no_contactar` (T14, sin asesor), `ya_es_cliente` con el asesor del perfil del
Portal (T17), `en_bolsa` (T3) y `tomado` (T1a…). (5) La pieza solo mira leads vivos cuyo principal está en la forma que ve el verificador
(`private.normalizar_telefono(telefono) = telefono`): un heredado fuera de ella no se nombra (N12, como hoy) ni hace nombrar a otro lead
por su número normalizado (N12b); por eso nunca sale «libre» y la guarda de la ronda 1 desapareció (inalcanzable).

## Por qué así

El ensayo no prueba una copia: pega la **migración real** (preflight, postflight y comentario incluidos) dentro de la transacción. Los
clientes que se editan nacen por la **conversión real** del formulario compartido (cooperativa, sin cuenta del Portal): un convertido sin
perfil del Portal ni cierre externo no se puede editar (`private.leads_before_update`; medido en la primera corrida del ROJO, con clientes
sembrados, que recibieron «Un lead convertido debe estar enlazado a un perfil de cliente» en cada edición). Los «otros clientes» que solo
se leen (T11, N8) son convertidos sin persona sembrados con los disparadores apagados (estado heredado declarado). Los actores del banco
(`PASO08 …`) son **obligatorios** con su rol exacto y cada caso exige su precondición (p. ej. que hoy la disponibilidad dé «tomado» con el
asesor esperado: si no, el caso no mediría la regla y el ensayo aborta). La identidad se fija en las DOS formas de los claims; no se usa
`set role`, así que la RLS y los permisos por columna no se ensayan aquí.

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó escrito);
`EJECUTAR_SQL_ADMIN`, el mismo como `supabase_admin` (solo lo usan las derivas de cambio de dueño). Los SQL generados van a una carpeta
de trabajo (`$SALIDAS`), no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración (la medición del defecto).
node supabase/scripts/alternativo-cliente-no-toma-lead/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"; $EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 20 fallo(s) de 53: los veinte casos T («la edición / el UPDATE se ACEPTÓ → el cliente quedó con el número de
#      otro lead: 2 fichas con ese número»; T5a/T5b: hoy los rechaza el 23514 del CHECK de formato; T15/T15b, bajo la válvula: la guarda
#      del perfil del convertido, P0001); los 33 negativos, medidas y catálogo ya pasan. Nunca un error de montaje.
# 2. VERDE: la migración real + el oráculo.
node supabase/scripts/alternativo-cliente-no-toma-lead/armar-ensayo.mjs > "$SALIDAS/verde.sql"; $EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (53 comprobaciones)
# 3. Mutantes (catálogo en mutantes.py; cada uno debe morir nombrando sus casos):
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/alternativo-cliente-no-toma-lead/mutantes.sh
# 4. Derivas de la migración y de la reversa (y sus mutantes):
EJECUTAR_SQL="…" EJECUTAR_SQL_ADMIN="… --usuario supabase_admin" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/alternativo-cliente-no-toma-lead/derivas.sh
# 5. Reversa: aplicar → revertir → el disparador del 2.8 (cuerpo, definición y comentario), sin pieza, foto idéntica.
node supabase/scripts/alternativo-cliente-no-toma-lead/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"; $EJECUTAR_SQL "$SALIDAS/reversa.sql"
# 6. Trinquetes: los private.assert_*() (los 36) y el censo, sin y con la migración (tienen que ser idénticos).
node supabase/scripts/alternativo-cliente-no-toma-lead/armar-ensayo.mjs --trinquetes --sin-migracion > "$SALIDAS/t0.sql"
node supabase/scripts/alternativo-cliente-no-toma-lead/armar-ensayo.mjs --trinquetes > "$SALIDAS/t1.sql"
# 7. Los oráculos del 2.4 (modo 2.7 «con», sin el fixture B7), del 2.7 y del 2.8, sin y con esta migración (mismas respuestas):
node supabase/scripts/alternativo-cliente-no-toma-lead/armar-ensayo.mjs --oraculo 24 --sin-migracion > "$SALIDAS/o24-sin.sql"
node supabase/scripts/alternativo-cliente-no-toma-lead/armar-ensayo.mjs --oraculo 24 > "$SALIDAS/o24-con.sql"
#    (lo mismo con 27 y 28)
```

El ensayo se arma para una base que **todavía no tiene** esta migración y **sí** tiene el 2.8 en su ronda 4: su preflight exige el
disparador `50a6ff43…`/`418b0976…` y la pieza `346f48a8…`/`a2b38faf…`. En una base que ya la tiene, el oráculo se corre solo
(`--sin-migracion`) y entonces tiene que salir VERDE.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--oraculo 24\|27\|28 [--sin-migracion] [--mutante <archivo>]`, `--reversa`, `--reversa-deriva <archivo> [--espera "<texto>"]`, `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]`; modificadores `--migracion`, `--pruebas`, `--reversa-archivo`. Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo (casos de arriba; 53 comprobaciones). |
| `mutantes.py` / `mutantes.sh` | 35 mutantes: 12 de la pieza (sin excluir la propia ficha, sin mirar el alternativo del otro lead, sin forma canónica —crudo, solo recortar, la forma del candado—, también retirados, también descartados, sin la precedencia, el desempate al revés, un veredicto propio en vez del verificador, el veredicto del número tecleado en vez del teléfono del lead, sin el filtro del principal visible), 17 del disparador (sin «es cliente» en cada rama, sin la regla en cada rama, también si el alternativo no cambia, antes que el 2.8, el veredicto antes que el rol, también sin sesión, sin excluir la propia ficha en cada rama, el alternativo viejo; ronda 2: sin la calificación de la conversión en cada rama, sin «or v_priv» en cada rama, solo bajo válvula en cada rama) y 6 de catálogo. Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra sus fallos**. `DIR_ENSAYO` obligatoria. |
| `derivas.sh` | Derivas instaladas ANTES de la migración (ya aplicada; otra función con el nombre de la pieza; el disparador con otro cuerpo, otro SET, INVOKER, un GRANT, otro comentario; la pieza del 2.8 con otro cuerpo, un GRANT, otro comentario; el disparador de tabla con otra lista o deshabilitado; `canonizar_contacto` con otro cuerpo, un GRANT, otro dueño —como superusuario—; `bloquear_contactos_lead` con otro SET; `normalizar_telefono` con otra regla; `rol_crm` STRICT; el verificador con otro cuerpo; la ficha con otro cuerpo; un GRANT a `anon` sobre la ficha con documento; el CHECK del alternativo quitado, cambiado o sin validar; un trinquete distinto, uno más, uno menos; reselle C1: el que re-sella el 2.16 borrado o renombrado, otro de los 29 cambiado, y —control RS— el del 2.16 re-sellado, que ENTRA), el control y un **mutante del preflight** (sin comparar la pieza del 2.8, la pieza cambiada se da por buena). Al final, las **derivas de la reversa** (control; SET, GRANT, cambio de dueño —como superusuario— y comentario del disparador; GRANT, cuerpo y comentario de la pieza; disparador de tabla deshabilitado; otro llamador —PL/pgSQL, en MAYÚSCULAS, una vista, un `cron.job`, un comentario que la nombra: falso positivo conservador— y el **límite** medido: un llamador dinámico no se ve y la reversa entra) y dos mutantes de la reversa (RM1 sin la comprobación de llamadores: el llamador PL/pgSQL se cuela; RM2 sin la comprobación de la ficha del disparador en su preflight: el GRANT aborta igual en su postflight). `DIR_ENSAYO` y `EJECUTAR_SQL_ADMIN` obligatorias. |
| `reversa.sql` | GENERADA desde la migración (sus anclas y su comentario, byte a byte; generador en `fase-2/bloque-2.13/salidas/trabajo/generadores/`). **Falla cerrada:** exige la pieza y el disparador (cuerpo, definición, ficha, ACL y comentario) y los disparadores de tabla EXACTAMENTE como los deja la migración, y que **nadie más use la pieza** (otros cuerpos de función por texto sin distinguir mayúsculas; `cron.job`; vistas, policies, defaults, CHECK, disparadores y funciones `BEGIN ATOMIC` por `pg_depend`; búsqueda conservadora: un comentario con ese nombre también la bloquea); repone el disparador del 2.8 y su comentario y borra la pieza **sin CASCADE**; su postflight exige las huellas del 2.8 y que la pieza ya no exista. No deshace datos (la regla no escribe). **Límite:** una llamada construida en tiempo de ejecución o hecha desde fuera de la base no se ve. |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **La RLS y los permisos por columna no se ensayan** (todo corre como `postgres`, sin `set role`). Medido en el laboratorio:
   `authenticated` tiene UPDATE de tabla sobre `crm.leads` y la policy `leads_update` no distingue convertidos (solo `activo = true` y el
   ámbito), así que un usuario del CRM puede llegar a esta regla por el PATCH o por `crm.editar_lead_fn`. La parte HTTP es del banco.
2. **La pantalla no ofrece esta edición**: la ficha oculta «Editar» en un convertido (`app/src/components/app/lead-drawer.tsx`,
   `activa={!esTerminal}`) y el store la bloquea (`app/src/lib/store.tsx`, «Ya es cliente — sus datos se corrigen en la ficha del
   cliente»); la ficha del cliente muestra el alternativo sin editarlo. Si algún día se ofrece por `editarLeadFn`, D-36 ya presenta el
   veredicto: el detalle exacto del servidor cumple el contrato `tomado`/`en_bolsa` de la pantalla («Este contacto ya está asignado a X.»).
3. **Dos ediciones simultáneas.** El oráculo corre en una sola conexión. El candado por número es el de la ronda 4 del 2.8, sin cambios
   (K1: la clave `telefono:` + el número, pedida antes de juzgar); su espera entre dos sesiones la midió el `espera.sh` del 2.8. **No
   ensayado:** la carrera con COMMIT (es de la branch, F4.6).
4. **Decidido por Miguel y declarado (medido):** el alternativo de un cliente puede ser el número de un lead **descartado** (N4a; el
   principal lo para con «enfriamiento») o **retirado** (N3a/N3b): **D-64**, solo leads vivos; si alguien rescata ese descartado, el
   bloque 2.16 lo frena con «ya es cliente de X». El **teléfono principal** de un cliente puede ser el **alternativo** de un lead vivo
   (N13) y el segundo teléfono puesto ANTES de convertir sobrevive a la conversión (medida H1): **D-65**, se cuentan en producción antes
   de publicar el grupo C. El alternativo de un lead que no es cliente contra otro lead que tampoco lo es queda fuera del plan (D-50).
   Los duplicados que ya existen se dejan (D-25). **Límites declarados** (la regla no los nombra, como hoy la disponibilidad tampoco los
   ve; se cuentan, D-65): un lead vivo heredado con su teléfono principal fuera de la forma canónica (N12/N12b) y el segundo número que
   solo esté en `telefono_alternativo_crudo` (lo que el importador no pudo canonizar; no se compara, como en el 2.8: auditor P3-5).
8. **Lo que revela el rechazo (D-67, extensión de D-29; auditor P3-2):** de quién es el lead también por su SEGUNDO teléfono (asesor,
   desde cuándo, última conversación; o bolsa; o veto sin nombre; o el asesor del perfil del Portal), aunque esté fuera de la cartera o
   del subárbol de quien edita, y sin registro anti-pesca (`crm.verificaciones_lead`: la transacción se deshace). Aceptado por Miguel
   como hoy con el principal. Con P3-1, una conversión ilegal sin válvula ya no lo ve (N14a/N14b).
5. **Rendimiento**: la pieza busca el número entre los leads vivos por su teléfono o por su alternativo; el alternativo **no tiene
   índice** y la condición con OR hace un recorrido secuencial de `crm.leads` (solo cuando un cliente cambia su alternativo). Medido en el
   laboratorio con 50 030 leads vivos (50 000 sintéticos, todo deshecho): ~5 ms por llamada sin coincidencia y ~7 ms con coincidencia
   (incluye la llamada al verificador). Medido en la ronda 1, con la pieza sin el filtro del principal visible; en la ronda 2 no se
   repitió (laboratorio compartido): el filtro añade por fila una llamada a `private.normalizar_telefono` (IMMUTABLE) dentro del mismo
   recorrido.
6. **La huella de escritura** compara por contenido `crm.leads`, `crm.actividades` y `crm.lead_asignaciones`; las demás tablas que mira,
   solo por número de filas.
7. **El barrido de trinquetes de la migración excluye los `*_mutantes`** (30 de 36), como el 2.7 y el 2.8; el ensayo `--trinquetes` barre
   los 36.
