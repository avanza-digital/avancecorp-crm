# Procedencia del lead: sistema o manual (2026-09-19)

Pedido de Miguel (19/09/2026): «que en el sistema se pueda diferenciar un lead
que viene del sistema de los que los mismos analistas cargan», con «algo
amigable» que «a simple vista distinga el lead», además de un filtro.

Relacionado con [[Canales de origen de leads CRM]], [[Deploy origen manual LANDING FORMULARIO 2026-09-01]]
y [[Los dos numeros del lead - del origen al CRM]].

## La distinción ya existía en la base; faltaba enseñarla

- **Origen** (landing, formulario, referido, Walking, otro) es el CANAL. Desde el
  01/09 un analista puede declarar LANDING o FORMULARIO a mano, así que el origen
  ya no dice quién metió el lead.
- **Procedencia** es OTRA pregunta: quién lo metió. La base la sella desde el
  01/09 en `crm.leads.alta_manual` (inmutable): el puente inserta `false` y sin
  autor; la RPC de alta manual inserta `true` con autor (`creado_por`).
- Regla vigente: **manual = `alta_manual` o tener autor; sistema si no**. El
  puente nunca escribe autor, así que la regla no puede confundirlos. La segunda
  mitad existe por los **36 leads manuales de agosto**, anteriores a la columna
  (marca `false` pero con autor). Backfill de `alta_manual` para esos 36:
  decisión aparte (columna inmutable; movería «manual propio» en Citas de
  agosto, mes reabierto).

Cifras de producción al 19/09: 1 864 del sistema (landing 837 + formulario
1 027, todos sin autor), 82 manuales con marca, 36 manuales de agosto sin marca.

## Qué se ve en el CRM

- **Fila de Leads**: chip pegado al nombre, `✎ Manual` (azul de acción) o
  `🤖 Sistema` (gris silencioso). En lo manual, debajo: «registrado por NOMBRE».
  Lo del sistema no compite con la etapa: un solo acento, para la minoría.
- **Ficha** (drawer) y **tarjeta flotante**: fila «Cargado por»: «Sistema (puente
  automático)» o «NOMBRE (registro manual)». En la cabecera de la ficha, el chip
  con el nombre.
- **Filtro** «Procedencia» junto al de origen: «Sistema y manual» (neutro, no
  viaja), «Solo del sistema», «Solo registro manual». Recorta listado,
  indicadores y distribución por etapa a la vez, como el resto de filtros.
- Vocabulario: Citas ya decía «Recibidos» / «Registrados manualmente»; Leads usa
  «Sistema» / «Manual» en el chip y «Solo del sistema» / «Solo registro manual»
  en el filtro. Misma idea, sin inventar una tercera.
- Un lead sin dato (servidor anterior a la migración) **no lleva chip**: nada
  inventado.

## Cómo está hecho

- Servidor: migración `20260919170500_crm_cartera_filtro_procedencia.sql`.
  `crm.cartera_filtrada_fn` pasa a 11 argumentos (`p_procedencia`), devuelve por
  fila `procedencia` y `cargado_por`, y retira la firma de 10. Misma base para
  filas e indicadores. Exención analítica movida y resellada. Ensayo completo en
  el banco (`supabase/scripts/cartera-procedencia/`), reversa y registrador
  generados con las huellas medidas. Acta en `MIGRACIONES.md`.
- Front: el nombre del autor se resuelve con el equipo visible en pantalla
  (igual que el analista); si no se conoce, el chip dice solo «Manual». El
  drawer lee el ámbito por select directo: pide `alta_manual` + `creado_por` y
  deriva la misma regla. Contrato cerrado con el servidor (eco + filas), como
  el filtro de origen.
- Publicado el 19/09/2026: SQL ~18:35 UTC y registrado ~18:45 (Miguel con `!`);
  front `crm-20260919T202714Z-7035feefbff5` ~20:28 UTC vía `/release-crm`,
  construido en un worktree limpio porque el taller tenía trabajo ajeno sin
  commitear. Lección repetida: **con sesiones paralelas, el release se construye
  fuera del taller**, y las dos `VITE_*` públicas van por entorno.

## Lo que encontró la revisión (y por qué importa)

- **Un filtro nuevo tiene que ir en la CLAVE de caché**, no solo en el request.
  TanStack Query identifica la lista por su clave: si solo cambia lo que se
  envía, no vuelve a pedir y enseña la lista anterior en silencio. El filtro de
  procedencia nació con ese fallo (lo cazó Codex) y hoy hay un test de hook que
  lo impide.
- **El drawer lee el ámbito, no la lista**: cualquier dato derivado por pantalla
  (nombre del autor) hay que resolverlo también en el store, o la ficha cuenta
  otra historia que la tabla.
- **Los 36 de agosto dependen de conservar su autor** (`creado_por` es FK con
  `ON DELETE SET NULL`). La casa nunca borra perfiles (offboarding =
  `activo=false`), así que se acepta y se documenta; un backfill de
  `alta_manual` sería decisión de Miguel.

## Pendientes anotados (fuera de esta entrega)

- Grant por columna para `alta_manual` y `creado_por`: hecho el 19/09
  (`20260919211105`, ensayada; ver [[El grant por columna no sobrevive al revoke de tabla (2026-09-19)]]
  para lo que vale de verdad).
- `test-rls.mjs` no cubre `cartera_filtrada_fn` (ninguna firma).
- Backfill de los 36 de agosto: solo si Miguel lo decide.
