# Corrección de la revisión de F2 + F3 — plan corto v2 (para el OK de Miguel)

Escrito el 03/10/2026 en la sesión de Jhosep, que escribe la corrección (confirmación 1 de Miguel). **Solo análisis:
sin SQL ni código.** Reemplaza la v1 (PR #171). Responde a:
- la revisión de Miguel (`REVISION-2026-10-02.md`);
- la ronda 1 de Codex sobre la v1: **BLOCK**, 6 P2 y 1 P3
  (`docs/encargos/2026-10-03-codex-llamadas-celular-correccion-r1-respuesta.md`);
- los tres comentarios de Miguel en el #175: la séptima decisión, las observaciones de su sesión y su respuesta.

Base: `origin/main` `00a482a3`. Las 4 migraciones están en `main` y **sin aplicar**.

## Qué cambió desde la v1

- Miguel decidió las seis decisiones y una séptima: los leads sin dueño y los descartados reutilizables también son
  candidatos (tabla al final).
- Cada hallazgo de Codex tiene su arreglo; la tabla del final dice dónde.
- El id de la llamada tiene **una forma fija** (`C1-<segundos>`) y se guarda tal cual, sin hash.
- La recepción va en `private` y caduca a los 32 días: ya no es permanente.
- La Edge deja de validar el contenido: la base es la única que valida, y todo inválido gasta cupo.
- Los candados siguen **un solo orden**, sacado de las rutas reales de Deshacer y de la encuesta.
- **Nuevo, para tu OK:** la salud del celular deja de mostrar `envios_hoy` y `ultimo_envio_en` (§6).
- Lo imprescindible para publicar va separado de lo que es mejora (tabla antes de las pruebas).

## En una línea

Una quinta migración cierra los fallos 1–4 y los menores sin editar las cuatro fusionadas. Se publica junto con F4-a,
que une cada encuesta con su llamada (decisión 1).

## Cómo se aplica

- **Orden:** datos → núcleo → ingesta → elegibilidad → quinta, cada una con su registrador **justo después**. Así
  `registrar-nucleo` y `registrar-elegibilidad` no chocan con lo que la quinta retira (corrección 3 de Miguel al
  #173). F4-a va después, con su propia migración.
- **Tablas vacías:** la precondición de la quinta lo exige y, si encuentra filas, se niega. Por eso puede cambiar
  tablas sin migrar datos.
- **Barrera (Codex P2-6):** no se despliega la Edge ni se da de alta ningún celular hasta verificar la quinta. Sin Edge
  y sin claves, las puertas de las cuatro no exponen nada: las tablas están vacías.
- **Reversa (Codex P11):**
  - antes del primer aviso, la reversa de la quinta vuelve al estado de las cuatro;
  - después, la quinta no se revierte, porque reinstalaría las fugas: se apaga (retirar la Edge, cerrar las
    asignaciones), se corrige hacia adelante y se conservan los hechos.
- La v4 de la encuesta (sellada por md5) no se toca: F4-a la envuelve.

## 1. El id, la recepción y el orden de la puerta (fallo 1; menores 6, 7, 9, 11, 12, 13 y 15)

### El id de la llamada (Codex P2-2 y P2-3)

- **Forma única:** `C<n>-<10 dígitos>`, la etiqueta del celular más los segundos de su reloj. Es lo que la macro ya
  genera, una vez por llamada, al colgar (`macrodroid.md:130, 141`). Ejemplo: `C1-1790980958`.
- La etiqueta del id tiene que ser **la de la asignación** de la clave.
- Los segundos tienen que caer entre **hace 30 días y dentro de 1 día**, con la hora del servidor.
- Fuera de eso → «inválido» (400). La macro lo aparta en `errores_llamadas` sin trabar la cola (`macrodroid.md:71`).
- **Por qué basta, sin hash, HMAC ni id aleatorio:**
  - no puede llevar un teléfono: un móvil peruano tiene 9 dígitos, y la ventana solo deja valores cercanos a la hora
    actual;
  - una etiqueta reutilizada no choca: cada llamada tiene su segundo;
  - un id de hace más de 30 días no vuelve a entrar.
- Se guarda tal cual. F4 encuentra la llamada por el id completo (Codex P11).

### La recepción

- Tabla nueva **`private.llamadas_celular_recepciones`**: una fila por cada llamada aceptada, **antes** de buscar el
  lead, también si después se ignora. Única por id.
- **En `private`, no en `crm` (Codex P11):** es una tabla técnica sin bitácora, como `private.celulares_estado`.
- **Caduca a los 32 días** (30 de ventana + 1 de tolerancia + 1 de margen): pasado ese plazo, su id ya no puede volver
  a aceptarse. Así no queda un registro eterno de a qué hora llamaba el analista, llamadas personales incluidas
  (Codex P9).
- **Recepción y llamada se confirman en la misma transacción.** Nada atrapa un fallo al guardar la llamada para
  confirmar solo la recepción (Codex P1).
- La llamada (`crm.llamadas_celular_eventos`) conserva su `evento_origen_id`, ahora **único por id**. Antes era único
  por asignación + id, y rotar la clave duplicaba (menor 9).
- Se retira `hash_payload`: solo servía para el 409, que desaparece.

### El orden de la puerta (llamadas y latidos)

1. **Clave** → asignación `FOR SHARE`, revalidada: vigente y analista activo. Si no, 401 (menor 6).
2. **Estado del celular** `FOR UPDATE`. Recién ahí se toma la hora (`clock_timestamp()`), una sola vez (Codex P2):
   - la ventana del cupo nunca retrocede (menor 7);
   - el `Retry-After` sale de esa hora;
   - las marcas de salud usan esa hora, no `now()`.
3. **Cupo.** Sin fila de política, error explícito (menor 13).
4. **Validación**, forma del id incluida. Un inválido devuelve el resultado «inválido» y el cupo gastado queda
   (menor 11, Codex P3).
5. **Recepción**, solo en llamadas. Si ya existía → «aceptado», sin buscar nada: el primer envío gana. Los latidos no
   tienen id y no pasan por aquí (Codex P11).
6. Solo si es nueva: política, búsqueda del lead (§2) y la llamada, si corresponde.

El `P0409` desaparece de la ingesta, y con él el 409 de la Edge.

### El contrato entre la Edge y la base (Codex P2-1)

- **La base es la única que valida el contenido** y devuelve un resultado con forma fija: `aceptado` o `invalido`, con
  un mensaje para quien arma la macro.
- Errores esperados: `42501` → 401; `P0429` → 429 con `Retry-After`. Lo inesperado → 503, que revierte todo, el cupo
  incluido.
- **La Edge lee ese resultado:** `aceptado` → 202 (llamada) o 200 (latido); `invalido` → 400.
- **Lo que la Edge contesta sin tocar la base** (no gasta cupo y no depende de ningún lead):
  - método distinto de POST → 405;
  - tipo distinto de JSON → 415;
  - cabecera de clave sin forma válida → 401;
  - cuerpo de más de 4 KB → 413, cortando la lectura.
- **Todo lo demás llega a la base**, también el JSON mal formado y el sobre inválido. La Edge solo elige la puerta por
  `accion`; la base autentica, gasta cupo y devuelve `invalido`.
- En la base, la validación va en un bloque que atrapa **solo** `22023`, con el cupo ya gastado antes del bloque
  (Codex P3: sin `WHEN OTHERS`).
- **Fecha estricta:** ISO 8601 con zona, validada en la base (menor 15). Acepta el espacio que usa `{datetime}`.
- Guardada, repetida o ignorada: el mismo 202, con la URL de la encuesta.

### Lo que no cierra

- **El tiempo de respuesta:** riesgo aceptado por escrito (decisión 5). La #12 queda así: «la respuesta, el cupo y el
  estado no delatan si un número es de un lead; el tiempo es riesgo aceptado» (confirmación 4).
- Un 503 por esperar un candado solo puede darse cuando hay lead. Es la misma pista de tiempo, rara y fuera del control
  de quien envía: queda dentro del riesgo aceptado (Codex P1).
- **Calibración** (sesión de Miguel, #175): dentro del CRM, saber si un teléfono existe no es secreto. «Nuevo lead» se
  lo dice a cualquier analista (`app/src/lib/disponibilidad-lead.ts:8-59`). Esto protege frente a quien tiene la clave
  de un celular **sin** sesión del CRM: una macro exportada, un exempleado.

## 2. Qué lead puede ser de la llamada (fallos 2 y 4; decisiones 3 y 7; Codex P5)

**Candidatos:** leads activos con el número (las dos formas canónicas, `nucleo:87-113`) que cumplan una de tres:
- **(a) Del ámbito del dueño del celular**, evaluado **como el dueño** con el mecanismo de identidad de
  `private.llamada_celular_elegible_dueno` (`elegibilidad:41-57`).
  - Se reutiliza el mecanismo, **no el predicado** (Codex P5): ese excluye etapas terminales y «no contactar», y esos
    leads propios tienen que seguir identificándose.
- **(b) Sin dueño** (decisión 7): `vendedor_id is null and asignado_supervisor_id is null`, en etapa abierta. Es la
  condición de «en bolsa» de la disponibilidad (`20260906200000:3633-3641`).
- **(c) Descartado reutilizable** (respuesta de Miguel). Es la condición de «reutilizable» de la disponibilidad
  (`20260906200000:3677-3727`):
  - etapa `descartado`, `activo` y con `descartado_en`;
  - ya pasó su espera: los días de `crm.enfriamiento_politica` para su motivo, o 24 horas si son 0.

**Resultado:**
- **Uno** → identificada.
  - Si es (a): pide resultado si es elegible como el dueño; si no, por revisar.
  - Si es (b) o (c): por revisar.
- **Dos o más** → ambigua, sin guardar cuántos (`calidad.candidatos` desaparece).
- **Ninguno** → igual que un número sin lead: no se guarda (decisión 3), aunque sea de un lead de otro analista.

**Quién la ve:**
- Lo de hoy: gerencia, o quien tiene hoy ámbito sobre el lead (decisión 7 de F2).
- Más una condición para todos, gerencia incluida: **el lead tiene que estar activo** (fallo 2).
- Por eso la llamada a un lead en bolsa no la ve quien llamó mientras el lead no sea suyo. Le aparece a quien lo tome
  (`crm.tomar_lead_libre`). Si nadie lo toma, se borra a los 30 días (§5).

**Efectos aceptados** (Codex P5; ratificados por Miguel):
- La llamada a un lead de otro analista ya no le llega a su equipo.
- Un número de un lead propio y de uno ajeno con dueño queda identificado con el propio: significa «coincidencia única
  en su cartera», no identidad global.

Con la #13 (clientes), la búsqueda sumará los clientes del ámbito del dueño con la misma regla.

## 3. Candados con un solo orden (menores 8 y 10; Codex P2-4 y P10)

**Las rutas reales** que cambian lo que se valida:
- **Reasignar** un lead escribe su fila en `crm.leads`: `vendedor_id`, `asignado_supervisor_id` y `activo` son columnas
  suyas. Un `UPDATE` toma un candado incompatible con `FOR SHARE` (Codex P10). La regla de ámbito
  (`private.sla_gestion_permitida`, `20260907025220:81-92`) solo lee esa fila, el rol y el equipo.
- **Deshacer** (`crm.deshacer_resultado_llamada`): bloquea primero el resultado y después el lead, los dos
  `FOR UPDATE`, y revalida el ámbito bajo el candado (`20260920005000:649, 682-685`).
- **La encuesta v4** bloquea el lead `FOR UPDATE` (`20260921153654:148`). F4-a la envuelve y bloquea la llamada después.

**Orden único para todo lo de llamadas: resultado → lead(s) → llamada → enlace.** Con dos leads, por id.
- **Descartar y asociar:**
  - leen la llamada sin candado;
  - bloquean su lead y, al asociar, también el destino, por id;
  - bloquean la llamada y comprueban que su lead no cambió. Si cambió, 40001 «vuelve a intentarlo» (Codex P10).
- **Enlazar (manual):** resultado `FOR SHARE` → lead → llamada → enlace. Rechaza un resultado deshecho (menor 10).
  Empieza por el mismo candado que Deshacer, así que no se cruzan.
- **v5 (F4-a):** lead (núcleo de v4) → llamada → enlace. No bloquea un resultado anterior: si tuviera que mover el
  enlace, lo lee y, si no está deshecho, se niega.
- **Purga:** llamada → enlace (cascada). No toca leads.
- Todas revalidan el ámbito **después** de tomar los candados, como Deshacer.

**Límite aceptado:** un cambio en `crm.equipo` o una baja en `public.perfiles` no se serializa con estos candados
(Codex P2). Pasa lo mismo en el resto del CRM: Deshacer tampoco lo bloquea. La ventana dura una transacción.

## 4. Entrantes (fallo 3; decisión 2)

- **Perilla bloqueada:** un `check` la fija en falso y `crm.fijar_politica_llamadas_celular` rechaza encenderla con
  un mensaje claro. La #14 llega después, como paso propio.
- **`direccion = 'desconocida'` se ignora**, igual que una entrante (Codex P6). La macro siempre manda la dirección; un
  aviso sin ella no debe pedir resultado.
- **Límite (Codex P6):** la base no detecta una entrante que la macro marque como saliente. Se prueba en el celular,
  con las pruebas de la guía.

## 5. Retención (decisión 4; Codex P4 y P7)

| Qué | Plazo | Desde |
| --- | --- | --- |
| Identificadas sin resultado: sin enlace, piden resultado o están por revisar | **30 días (nuevo)** | `recibido_en` |
| Ambiguas y sin identificar | 30 días, como hoy | `recibido_en` |
| Descartadas | Su plazo de hoy | `descartado_en` |
| Registradas: con enlace, aunque su resultado se haya deshecho | **Se conservan** como historial del lead (Miguel) | — |
| Recepciones | **32 días (nuevo)** | `recibido_en` |

- Deshacer no convierte una llamada en «sin resultado»: el enlace permanece por contrato. La purga mira el enlace, no
  la atención.
- Las registradas de un lead dado de baja quedan ocultas (§2) y se conservan como el resto de su historial: el CRM no
  borra historial. Es un plazo **decidido**, no «indefinido por omisión» (`PLAN.md:647`).

## 6. Salud del celular (nuevo, para tu OK)

- Hoy supervisión y gerencia ven `envios_hoy` y `ultimo_envio_en` (`ingesta:278-290, 370`).
- Los dos cuentan **todo** lo que manda el celular, también las llamadas a números que no son leads
  (`ingesta:308, 315`). `envios_hoy` suma además los latidos (`ingesta:335`).
- Restando, se sabría cuántas llamadas personales hizo el analista y a qué hora.
- **Propuesta:** la lectura de salud muestra solo el latido, la versión de la macro y la cola. Los contadores siguen
  por dentro, solo para el límite.
- Cierra además, sin más trabajo, la pista que la v1 cerraba actualizando esos datos siempre.
- La cola (`eventos_en_cola`) también cuenta llamadas personales hechas sin red. Se mantiene: soporte la necesita y es
  pasajera.
- Salió del análisis adelantado de F5–F7 (PR #178).

## 7. Lo que va con F4-a (decisión 1: se publica junto)

- **Puerta v5 por id exacto** (`F4-PLAN-CORTO.md` §1), con intención de enlace si el aviso todavía no llegó.
- **Sin la regla de los 10 minutos** en el camino exacto (confirmación 3 de Miguel; Codex P2-5). La encuesta suele
  guardarse antes de que llegue el aviso, y un reloj adelantado la rechazaría (`nucleo:423-425`). La regla queda solo
  para el enlace manual.
- **Guardar por qué vía se hizo el enlace:** al colgar, desde la pestaña o a mano. Sin ese dato no se mide «encuesta
  abierta al colgar» por celular, que es el objetivo (`F4-PLAN-CORTO.md` §2). Hoy el enlace no lo guarda
  (`datos:403-413`).
- **Al deshacer, el enlace pasa al resultado corregido** (confirmación 2).
- El detalle va en `F4-PLAN-CORTO.md`, que se pone al día con esta sección.

## 8. Lo demás

- **Bandeja duplicada:** se retiran `crm.llamadas_celular_pendientes_fn` y su núcleo (decisión 6).
- **Rotar reinicia el límite de envíos** (Codex P3-7): el estado va por asignación. Se documenta; solo gerencia rota.
- **Guía de publicación** (correcciones de Miguel al #173):
  - cada registrador, justo después de su migración;
  - una fila final de veredicto después del `commit`, como `anexo-cronograma/registrar-20260929151350.sql`: los
    `raise notice` no se ven por `db query --linked`;
  - en una copia Docker, `psql -f`: `db query --local --file` falla con varias sentencias;
  - la barrera de «Cómo se aplica»;
  - el prefijo del id en la macro es la etiqueta del celular (`C2-…`), no siempre `C1-`, y la hora del celular es
    automática;
  - **antes de pasar un celular a otro analista, cola en 0** según su latido. La llamada se atribuye a la clave con la
    que llega (`elegibilidad:128-133, 200`): una cola vieja quedaría a nombre del analista nuevo. Salió del análisis
    de F5–F7.
- **Guía de la macro, sin Pro** (Miguel): las 3 macros de hoy y el latido dentro de «Enviar cola»; la sección de
  entrantes (§3d) queda para la #14. Va en su propio PR.

## Imprescindible para publicar o mejora

| Pieza | Tipo | Por qué |
| --- | --- | --- |
| §1 Id, recepción, orden y contrato de la Edge | Imprescindible | Fallo 1; Codex P2-1 a P2-3 |
| §2 Qué lead puede ser | Imprescindible | Fallos 2 y 4; decisiones 3 y 7 |
| §3 Candados | Imprescindible | Menores 8 y 10; Codex P2-4 |
| §4 Entrantes | Imprescindible | Fallo 3 |
| §5 Retención | Imprescindible | Decisión 4 |
| §6 Salud | Imprescindible | Llamadas personales a la vista de supervisión |
| §7 Enlace exacto, sin la regla de 10 minutos | Imprescindible | Decisión 1; Codex P2-5 |
| Guía: barrera, registradores, veredicto, `psql`, prefijo y hora | Imprescindible | Publicar sin sorpresas; Codex P2-6 |
| §7 Vía del enlace | Mejora barata | Mide el objetivo; no se recupera después |
| Retirar la bandeja vieja | Mejora | Nadie la usa |
| Cola en 0 antes de cambiar de analista | Mejora | Caso raro; es una línea de la guía |

## Pruebas

| Dónde | Qué demuestra |
| --- | --- |
| Banco reducido (`npm run test:llamadas:local`), oráculo nuevo | La lista de abajo |
| Banco reducido, dos sesiones | Carreras con barreras: cierre durante un latido; reasignación durante descartar, asociar y enlazar; Deshacer durante enlazar, sin interbloqueo; medianoche de Lima |
| Edge (`test:llamadas-ingesta` y mutantes) | Contrato nuevo: inválido → 400 con cupo gastado; JSON mal formado llega a la base; 405, 415 y 413 sin base; sin 409 |
| Gate `testLlamadasCelular` | Ya no exige `P0409`: exigirlo es exigir la fuga (punto 22 de la revisión). Añade lead borrado, entrantes, bolsa y reutilizable, un enlace real con su encuesta y rotación |
| Banco de Miguel (esquema de producción) | `banco/verificar-hallazgos.sql` con los fallos cerrados, gate completo, advisors y la quinta forzada a fallar (barrera) |

**El oráculo nuevo comprueba:**
- **Sin pistas:** número sin lead, lead ajeno con dueño, ajeno en enfriamiento y varios ajenos dan la misma respuesta,
  el mismo cupo y el mismo estado visible.
- **Bolsa:** se guarda por revisar; quien llamó no la ve; al tomar el lead la ve y puede enlazar; si nadie lo toma, la
  purga la borra a los 30 días.
- **Reutilizable:** igual que la bolsa.
- **Propios terminales o con «no contactar»:** identificada, por revisar.
- **Id:**
  - forma inválida, etiqueta de otro celular o fuera de la ventana → 400, con el cupo gastado;
  - el mismo id con otro contenido → aceptado, sin cambios;
  - ignorado y después el mismo id con lead → sigue ignorado;
  - rotar no duplica;
  - con la etiqueta reutilizada, un id nuevo entra.
- **Purga:**
  - no libera un id dentro de la ventana;
  - recepciones a los 32 días e identificadas sin enlace a los 30;
  - las registradas y las de resultado deshecho se quedan;
  - las descartadas, por su plazo.
- **Cupo:** la ventana no retrocede, `Retry-After` ≥ 1 y, sin política, error claro.
- **Identidad:** vuelve a la anterior en éxito y en error, también dentro del bloque que atrapa `22023`.
- **Otros:** lead borrado (nadie lo ve ni lo toca, gerencia incluida); entrantes y desconocidas ignoradas, con la
  perilla bloqueada; fecha sin zona rechazada; salud sin envíos ni último envío.
- **F4-a (en su banco):** reloj adelantado con enlace exacto, aviso tardío, intención sin aviso y aviso caducado.

## Orden de trabajo (con tu OK)

1. Quinta migración, con su reversa, su registrador y sus oráculos. Banco reducido en verde.
2. F4-a, según `F4-PLAN-CORTO.md` puesto al día con §7.
3. Edge y sus pruebas.
4. Bloque del gate.
5. Guías de publicación y de la macro; `MIGRACIONES.md`.
6. Encargo de Codex r2 sobre el diff, con el dato de «Nuevo lead», y auditor-rls. Los corre Miguel.
7. Ensayo en tu banco y publicación: las cinco, F4-a y la Edge, con la barrera.

## Decisiones

### Ya decididas por Miguel (03/10, PR #175)

| # | Decisión |
| --- | --- |
| 1 | **A:** F2 + F3 se publican junto con el enlace exacto de F4-a |
| 2 | Entrantes bloqueadas; la #14 después, como paso propio |
| 3 | La llamada a un lead de otro analista = número sin lead |
| 4 | Sin resultado → 30 días; las registradas se conservan como historial del lead |
| 5 | Pista por tiempo: riesgo aceptado por escrito |
| 6 | Retirar la bandeja vieja |
| 7 | Leads sin dueño y descartados reutilizables: candidatos, por revisar; le aparecen a quien los tome |

Confirmaciones:
- escribe esta sesión; tu sesión verifica en tu banco y corre Codex r2;
- al deshacer, el enlace pasa al resultado corregido;
- la regla «resultado posterior a la llamada» solo vale para el enlace manual;
- la #12, con la redacción de §1;
- MacroDroid Pro no se compra todavía.

### Para tu OK

| # | Decisión | Recomendación | Alternativa y su costo |
| --- | --- | --- | --- |
| N1 | Salud del celular (§6) | **Quitar `envios_hoy` y `ultimo_envio_en`** de la lectura | Dejarlos: supervisión ve cuántas llamadas personales hace el analista y a qué hora |

### Criterio de Claude (PRIMARY), para que lo veas

- La forma del id y su ventana. Se guarda tal cual, sin hash.
- La recepción en `private`, con 32 días.
- La Edge solo revisa el transporte; la base valida todo lo demás.
- `desconocida` se ignora.
- Rotar reinicia el cupo: se documenta, no se cambia.
- Registradores intercalados, en vez de relajar sus comprobaciones.
- Descartar y asociar revalidan la llamada después de bloquear los leads.
- El inválido se resuelve dentro de la base, con un bloque que atrapa solo `22023`.

## Hallazgos de Codex r1 (03/10) → dónde se cierran

| Hallazgo | Dónde |
| --- | --- |
| P2-1 La Edge no acompaña el arreglo | §1, contrato |
| P2-2 El sha256 no protege un teléfono | §1, el id |
| P2-3 Etiqueta e id reutilizados | §1, el id |
| P2-4 Candados incompletos | §3 |
| P2-5 Reloj adelantado | §7 |
| P2-6 Sin barrera si falla la quinta | Cómo se aplica; guía (§8) |
| P3-7 Rotar reinicia el cupo | §8 |
| P1: recepción y llamada juntas; duplicados con cupo; hora tras el estado; 503 por candado | §1 |
| P4: ocultar no es caducar | §5 |
| P6: dirección desconocida; entrante mal marcada | §4 |
| P11: recepción en `private`; latidos sin id; F4 por id completo; reversa | §1; Cómo se aplica |

## Riesgos y límites

- Tiempo de respuesta: riesgo aceptado (decisión 5).
- `crm.equipo` y `public.perfiles` no se serializan, como en el resto del CRM (§3).
- Una entrante que la macro marque como saliente solo se detecta probando en el celular (§4).
- Un celular con la hora muy mal (más de 1 día adelantada o 30 días atrasada) ve sus avisos rechazados: la guía exige
  hora automática y las pruebas del alta lo detectan.
- Cola vieja tras cambiar de analista: la evita la regla de la guía (§8).
- Aplicar las cuatro sin la quinta: lo frena la barrera.
- Las carreras se prueban con barreras en el banco reducido; tu ensayo con el esquema de producción lo completa.

## En llano

Miguel ya decidió todo lo que estaba pendiente, y su revisor encontró siete huecos en el diseño. Este plan cierra cada
uno:
- el CRM anota cada aviso antes de mirar si el número es de un lead, y contesta siempre igual;
- el id de cada llamada tiene una forma fija que no puede esconder un teléfono;
- las operaciones se bloquean en un solo orden, para no trabarse entre sí;
- las llamadas a leads libres no se pierden: le aparecen a quien tome el lead.

Hay una propuesta nueva: que el panel de los celulares deje de mostrar datos que cuentan llamadas personales. Nada de
esto se programa hasta que Miguel diga que sí.
