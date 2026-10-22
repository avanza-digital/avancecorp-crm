# Ensayo de «No asistió espera a la hora de la cita»

Verifica la migración `20261022170100_crm_no_asistio_espera_hora.sql` **en el banco Docker local
(el laboratorio) y sin escribir nada**. Este ensayo **no se corre contra producción**: siembra un
lead, citas y una reunión de postventa, y espera unos segundos con una transacción abierta.

## Qué prueba

La regla de Miguel (2026-10-05): una reunión realizada antes de la hora pactada se marca realizada en
el acto; **solo «No asistió» espera a que pase la hora** (`crm.tareas.vence_en`). La regla vive en el
candado de la tabla, `private.trg_tareas_before_update()`, que corre en todo UPDATE de `crm.tareas`:
hoy es por donde entran las seis entradas que cierran una reunión.

## Qué NO garantiza (límites conocidos)

1. **La regla compara contra la hora guardada; no impide mover esa hora al pasado.** El oráculo lo
   mide sin exigirlo (línea `medida P2-1` del informe). Medido el 06/10/2026, con y sin la migración:
   el dueño reprograma una cita futura a «hace un minuto» por `crm.reprogramar_reunion_v2` —el
   servidor responde `ok` y la cita nueva nace `pendiente` con su hora 60 s atrás— y «No asistió»
   sobre esa cita nueva por `crm.cerrar_reunion_v3` responde `ok`. Crear directamente una reunión de
   lead con la hora ya pasada y marcarla también entra (lo ejerce el caso 4a). Postventa sí exige hora
   futura al agendar y al reprogramar. Queda fuera de este cambio: **lo decide Miguel**.
2. **La regla vive en BEFORE UPDATE: un INSERT con `crm.op_tarea = on` no pasa por ella.** Hoy
   ninguna función inserta una tarea en `no_show` (censo por catálogo del 06/10: insertan en
   `crm.tareas` solo `private.crear_siguiente_tarea`, `private.registrar_solicitud_cliente_fn`,
   `crm.reprogramar_reunion` y `private.postventa_insertar_tarea`, y ninguna menciona `no_show`).

## Por qué así

El ensayo no prueba una copia de la función: pega la **migración real** (preflight, postflight y
comentario incluidos) dentro de una transacción que termina en `rollback`. Si alguien toca la
migración, el oráculo prueba lo tocado — no hay copia que se desactualice sola.

Y no usa un fixture inventado: levanta el escenario contra la **forma real** del esquema (los CHECK,
los triggers, la jerarquía de equipo y los actores del banco) y llama a las puertas de verdad.

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un archivo `.sql` al banco local
(`psql -v ON_ERROR_STOP=1 -f` contra el contenedor, o la herramienta del laboratorio). Los SQL
generados van a una carpeta de trabajo, no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración. Es la medición del defecto.
node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"
$EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 9 fallo(s), todos «el servidor ACEPTÓ «No asistió» antes de la hora»:
#      las seis entradas (1 ×3, 2 ×2 y 3), v3 con supervisor, v3 con gerencia y la frontera 5-antes

# 2. VERDE: la migración real + el oráculo. Termina SIEMPRE en excepción: eso es el veredicto.
node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs > "$SALIDAS/verde.sql"
$EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (con las medidas de H-10, del rodeo por la hora, de la frontera
#      y del mismo identificador)

# 3. Los mutantes: rompen la regla o la ficha del candado DESPUÉS de la migración y exigen que el
#    oráculo lo grite nombrando el fallo que corresponde.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/no-asistio-espera-hora/mutantes.sh
#    → MUTANTES: los 13 murieron, cada uno por su fallo.

# 4. Las derivas previas: rompen el catálogo ANTES de la migración y exigen que su preflight se niegue.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/no-asistio-espera-hora/derivas.sh
#    → DERIVAS: las 7 abortan en el preflight y dejan la huella original; el control entra.

# 5. La reversa: aplicar → revertir → el candado vuelve a ser el de antes.
node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"
$EJECUTAR_SQL "$SALIDAS/reversa.sql"
#    → REVERSA VERDE: huella del cuerpo ded27e36… y ficha (definición, dueño, ACL, comentario) idéntica
```

El ensayo se arma para una base que **todavía no tiene** la migración: su preflight exige la huella
anterior del candado. En una base que ya la tiene, el oráculo se corre solo (`--sin-migracion`) y
entonces tiene que salir VERDE.

Después de cualquier corrida conviene comprobar que el banco quedó intacto:

```sql
select md5(prosrc) from pg_proc where oid = 'private.trg_tareas_before_update()'::regprocedure;
select count(*) from crm.leads where nombre_completo like 'ENSAYO%';
-- la huella de antes de correr, y 0
```

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion` (solo el oráculo), `--mutante <archivo>` (migración + mutante + oráculo), `--reversa` (migración + reversa + comparación de la ficha del candado) y `--deriva <archivo> [--espera "<texto>"]` (deriva de catálogo + migración capturada + veredicto). Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo. 1 y 2: rechazo (22023 y su mensaje) por `cerrar_reunion_v3`, `cerrar_reunion_v2`, `cerrar_reunion`, `cerrar_tarea_v2` y `cerrar_tarea`, con la cita intacta — pendiente, sin actividad, sin tarea siguiente y sin recibo —. 3: lo mismo por `postventa_tarea_fn` sobre una reunión de cliente. 4: lo que debe seguir entrando — «No asistió» con la hora pasada por las cinco entradas, «Se realizó», cancelar y reprogramar antes de la hora —. 5: la frontera con reloj real y el **mismo identificador**: el envío rechazado justo antes de la hora se repite idéntico con la hora cumplida y entra, y un tercer envío idéntico devuelve la misma respuesta sin duplicar nada (lead y postventa). 6: la misma regla para supervisor y gerencia. 7: llamadas, WhatsApp y tareas, igual que antes. 8: H-10, **medido**. P2-1: el rodeo por la hora, **medido** (no suma fallos). 9: ficha del candado (9a), forma del trigger (9b), permisos de las seis entradas (9c) y `vence_en` NOT NULL (9d). 10: gates de los writers. 11: las restricciones diferidas se fuerzan antes del veredicto (`set constraints all immediate`). |
| `mutantes.sh` | Trece mutantes, instalados DESPUÉS de la migración. Diez de **cuerpo**: la regla neutralizada, la comparación invertida, la frontera adelantada y retrasada, el reloj de la transacción, la regla aplicada de más (a «Se realizó», a cancelar y reprogramar, a lo que no es reunión) y el rechazo con otro código o con otro mensaje. Tres de **catálogo**, con el cuerpo intacto: EXECUTE concedido a `authenticated` (9a), el candado sin `security definer` (9a) y el trigger deshabilitado (9b). Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra los fallos que le corresponden** (caso y motivo). |
| `derivas.sh` | Siete derivas de catálogo instaladas ANTES de la migración, más un control sin deriva. Con cada una la migración tiene que abortar en su **preflight** con el mensaje que corresponde y dejar el candado con la huella original: EXECUTE previo a `authenticated`, candado sin `security definer`, otro `SET` además del `search_path`, `vence_en` anulable, trigger con WHEN, con lista de columnas y deshabilitado. |
| `reversa.sql` | Restaura el cuerpo anterior del candado y le quita el comentario. Ver «La reversa, con exactitud». |

## La reversa, con exactitud

- **Qué comprueba:** solo la huella del cuerpo. Se niega si `md5(prosrc)` no es `4a0a6b00…` (la
  migración no está aplicada, o alguien cambió el cuerpo después). No comprueba dueño, ACL, atributos,
  comentario ni la forma del trigger. Es deliberado: una reversa no debe negarse por una deriva ajena
  justo cuando hace falta revertir.
- **Qué restaura:** el cuerpo anterior (`md5(prosrc)` = `ded27e36…`), con `security definer` y
  `search_path` vacío, y la función sin comentario.
- **Qué conserva:** firma, dueño y ACL (`create or replace` no los toca) y el trigger.
- **Qué sobrescribiría** si alguien lo hubiera cambiado después de la migración sin tocar el cuerpo
  (la huella seguiría coincidiendo): los `SET` añadidos con `ALTER FUNCTION … SET …` —queda solo el
  `search_path` vacío— y el comentario, que queda nulo. Ensayado el 06/10: con un `lock_timeout`
  añadido y otro comentario, la reversa pasa y deja `proconfig = {search_path=""}` y comentario nulo.
- Si antes de la migración la función tuviera un comentario (en el laboratorio no lo tenía;
  producción no se ha mirado), la reversa no lo recupera.

## Revisiones

`auditor-rls`: CHANGES_REQUESTED sin P0 ni P1 (06/10/2026). Codex: CHANGES_REQUESTED sin P0 ni P1
(06/10/2026). Los dos dictámenes están conciliados por el Director del plan. **Las correcciones
posteriores a Codex no tienen tercera revisión**: las sostienen este ensayo y la verificación del
Director.

## Pendiente antes del gate de la branch y de la integración

Esta carpeta prueba la regla en el banco local, con la sesión del banco y la identidad del actor en
los claims. No sustituye a lo que ejecuta el ciclo de branch:

- **Orden de despliegue: la migración antes que la pantalla** (recomendación de Codex). Con la
  migración puesta, los clientes viejos reciben el rechazo del servidor; al revés, las otras entradas
  y los clientes viejos se quedarían sin la defensa central.
- **Build y e2e en Docker** del cambio de pantalla: no ejecutados aquí.
- **Prueba de espera real por candado** (mantener un bloqueo hasta pasada la hora y ver qué responde
  al liberarlo): no ejecutada; la herramienta del laboratorio es de una sola conexión. Lo probado es
  que el reloj es el real y no el de la transacción (mutante M5).
- **`supabase/scripts/test-rls.mjs` no se amplió.** No tiene ningún caso de la regla con sesiones
  reales por PostgREST. Los casos están descritos en el dictamen de `auditor-rls` (hallazgo P2-3; en
  el plan de backend, `fase-2/bloque-2.1/revision/auditor-rls.md`).
- **`supabase/scripts/gestion-diaria-resultado/test-gestion-diaria-resultado.sql:420-424` queda por
  ajustar.** Su caso W cierra como `no_show` una cita de pasado mañana sin capturar el error: con la
  regla revienta ahí y su sección de RLS ya no corre. No es ejecutable en este laboratorio.
- **`supabase/scripts/entrevista-al-asistir/pruebas.sql` se modificó (solo la hora de una cita) y NO
  se ejecutó en su forma del repo**: ya no corre desde antes de este cambio, porque siembra su lead
  con origen `otro`. El ajuste se verificó sobre una copia temporal con el origen cambiado.
- Repetir en la branch, antes de aplicar, la huella y la ficha del candado y el censo de quién escribe
  `estado` en `crm.tareas`: el laboratorio está en un corte anterior a `main`. Las precondiciones del
  preflight harán abortar la migración si algo difiere.

## Trampas encontradas al escribirlo

- **Un rechazo que no rechaza se escapa hacia adelante.** Cada entrada prueba sobre SU cita y compara
  una foto de antes y de después (estado, tareas, actividades, recibos, gestiones de postventa): si la
  entrada acepta, el fallo sale ahí y no tres pasos más tarde. Y cada intento lleva nota y tarea
  siguiente, para que un «No asistió» aceptado deje rastro que la foto delate.
- **La frontera no se puede fingir.** `postventa_agendar_fn` solo admite horas futuras y la regla
  mira el reloj real, así que el ensayo agenda a tres segundos, intenta cuando faltan unas décimas,
  espera a la hora e intenta otra vez. Si la hora llega durante el intento, es un FALLO («no
  concluyente»), no un verde: se repite la corrida. La igualdad exacta `vence_en = reloj` no se puede
  forzar con un reloj real; se mide a milésimas de la hora.
- **El mismo envío es el mismo contenido.** Repetir un envío es mandar lo mismo: en postventa eso
  incluye la revisión con la que se envió la primera vez (1), no la que tenga ahora la tarea (2). Con
  la revisión actual el contenido ya no sería el mismo (por lectura de `private.postventa_recibo`, el
  servidor lo trataría como otra operación con la misma clave; no se ensayó).
- **Un mutante va DESPUÉS de la migración; una deriva, ANTES.** El postflight sella el cuerpo y la
  ficha: un mutante escrito dentro de la migración moriría en el sello y no probaría el oráculo. Y un
  mutante posterior no dice nada del preflight: para eso están las derivas.
- **Un mutante puede poner el ensayo en rojo por otra cosa.** Con el trigger deshabilitado caen
  también los rechazos y el cancelar; un fallo incidental de la frontera pondría rojo cualquier
  corrida. Por eso `mutantes.sh` exige que cada mutante nombre SU fallo, no solo que salga ROJO.
- **Una deriva puede «abortar» por cualquier cosa.** `derivas.sh` exige el texto del preflight que
  corresponde y lleva un control sin deriva: sin él, un envoltorio roto daría «abortó» siempre.
- **Una medida no es una aserción.** H-10 y el rodeo por la hora se anotan tal cual responde el
  servidor y no suman fallos: son límites conocidos, y fijarlos como esperados los convertiría en
  regla sin que nadie lo decidiera.
- **El `raise` final evita el COMMIT.** Lo diferido (las FKs de los recibos y su confirmación) no se
  comprobaría nunca: el oráculo lo fuerza antes del veredicto.
- **El límite de 30 s de la migración se hereda.** `set local statement_timeout` dura toda la
  transacción del ensayo; el oráculo, que espera a propósito, fija el suyo.
- **Ningún lead nace con origen «otro»** (`private.leads_before_insert`, desde el 28/09) ni en etapa
  terminal: el del ensayo nace `contactado` y con origen `landing`.
- **Sembrar exige el JWT del dueño** (`trg_gestion_lead_serializada`), y la sesión se fija en las DOS
  formas de los claims. No se usa `set role`: llamar bajo `set role` a una función sin EXECUTE tumba
  el Postgres del banco; los permisos se leen del catálogo.
- **La jerarquía solo se ve con la sesión de su dueño.** `private.vendedor_ids_visibles` no enumera
  equipos ajenos: sin el JWT del supervisor devuelve vacío y parecería que no ve a su vendedor.
- **Los gates del banco no están todos verdes.** De los 36 `private.assert_*()`, 7 caen desde antes
  por trabajos ajenos; el postflight solo llama a los dos que sellan a los writers de agenda. Lo que
  se exige es que la foto de los 36 NO cambie con la migración puesta.
