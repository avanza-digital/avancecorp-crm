# Los dos números del lead — del origen al CRM

**Lo que pidió Miguel (2026-08-26), en sus palabras:**

1. «Necesito que los leads vengan con sus dos números sí o sí.»
2. «No importa si el otro número está mal: con tal que tenga un número válido, ya debe entrar al CRM.»
3. «Si los dos números están mal, ahí sí debe descartarlo.»
4. «Además debe reconocer formatos de número a nivel mundial.»
5. «Quiero saber si los vendedores van a poder ver los dos números en su CRM.»
6. «Que siempre todos los leads tengan ese número alternativo, así ese número sea errado.»

Relacionado: [[Carga de leads desde hoja de Google]] · [[Fundamentos UX del CRM]]

---

## Dónde estamos de verdad (medido en producción, 26/08)

| | |
|---|---|
| Leads en el CRM | 544 |
| Con segundo número | **14** (2,5 %) |
| De esos 14, en la cartera de alguien | 8 — los otros 6 están por repartir |
| Sin segundo número | 530 — entraron antes de que el campo existiera |

**El CRM ya sabe mostrarlo.** El bundle vivo (`index-BqXq5w5i.js`) pide la columna,
la valida, la copia al navegador y pinta la fila «Teléfono alternativo» en la ficha
del lead. Lo que falta no es la vitrina: es la mercadería.

**Por qué solo 14.** El puente tiraba en el origen todo lo que no fuera un celular
peruano: los fijos, los números extranjeros y los mal escritos. Nunca llegaban.

---

## Lo que se puede y lo que no

**✅ Se puede:** que NUNCA se pierda un segundo número, aunque esté mal escrito. Se
guarda tal como llegó y la ficha lo muestra marcado como sin validar.

**❌ No se puede:** que todos los leads tengan uno si el origen solo dio uno. Ese
dato no existe, y inventarlo sería peor que no tenerlo.

## MEDIDO — el diagnóstico corrió el 26/08 sobre las 14.310 filas del origen

| Qué pasa en el origen | Filas | % |
|---|---|---|
| **Repiten el mismo número** en las dos columnas | 12.043 | **84,2 %** |
| Segundo celular distinto | 1.501 | 10,5 % |
| Solo dieron un número | 462 | 3,2 % |
| Algo escrito que no es número | 299 | 2,1 % |
| Un fijo como segundo | **5** | **0,03 %** |

**TECHO REAL: 10,5 %. Y ya estábamos ahí.** De los leads que entraron el 25 y 26
de agosto, 14 de 147 traían dos números = 9,5 %. El puente viejo ya capturaba los
segundos celulares distintos: lo que se creía roto no lo estaba.

**El trabajo de fijos e internacionales (F2) suma 5 filas de 14.310.** Se queda
—no hace daño y el CRM es más correcto— pero no era el cuello de botella. Decirlo
aquí para que nadie vuelva a construir sobre la premisa «F2 convierte 14 en
muchos», que era falsa.

**Lo único recuperable de verdad: las 299 filas ilegibles (2,1 %)** → es lo que
hace F4.

### Por qué el 84 % repite el número

| Pestaña | Campos que pide | Repiten |
|---|---|---|
| landing (COOPAC MásCapital) | `Celular` \| `WhatsApp` | 89,9 % |
| formulario (campaña de Facebook) | `celular` \| `celular` | 78,3 % |

Para casi todo el mundo el celular Y el WhatsApp son **el mismo teléfono**. La
gente no lo hace mal: la pregunta está mal hecha. La única palanca que movería ese
84 % es cambiar la etiqueta del segundo campo a «Otro número de contacto (familiar
o trabajo)».

⛔ **Miguel decidió el 26/08 NO tocar los formularios.** Queda escrito como la
razón por la que el techo se queda en 10,5 %, no como una tarea pendiente.

---

## Las decisiones ya tomadas

| | Decisión |
|---|---|
| **Cuándo se descarta un lead** | Solo cuando NINGUNO de sus números sirve. Los dos se juzgan juntos: si el principal está ilegible pero el segundo es bueno, ese pasa a ser la identidad y el lead entra. |
| **Fijos peruanos** | Se guardan. Un fijo de casa o de oficina es un canal de contacto real. |
| **Números de otros países** | Se guardan. E.164 (`+` y de 8 a 15 dígitos). El peruano que ahorra desde fuera existe y no cabía en el CRM. |
| **Si el segundo repite al primero** | No se duplica. Es el mismo número. |
| **Quién manda como identidad** | El móvil: es quien responde WhatsApp. Un fijo solo sube a principal cuando no hay ningún móvil, y entonces la ficha lo avisa. |

---

## La trampa que casi se cuela: el DNI tiene ocho dígitos

Un fijo peruano tiene ocho dígitos nacionales (Lima `1`+7, Cusco `84`+6). **Un DNI
peruano tiene ocho dígitos.** Al aceptar ocho dígitos pelados como fijo, todo DNI
pasaba a parecer un teléfono: el buscador ofrecía «verificar disponibilidad» sobre
un documento. Lo cazaron tres pruebas del front que ya existían.

**Regla resultante: un fijo solo se reconoce MARCADO** — con `+51`/`0051`, o con el
`0` de larga distancia con el que la gente escribe su fijo (`014457890`). Ocho
dígitos pelados no son un teléfono.

---

# EL PLAN

## Ya hecho, verde, SIN PUBLICAR

### F0 · Diagnóstico del origen
Entrada nueva en el menú de la hoja: «Diagnóstico de segundos números». Recorre el
origen sin escribir nada y responde cuántas filas traen segundo número, cuántas lo
repiten, cuántas traen un fijo, cuántas algo ilegible, y **cuál es el techo real**.

### F1 · Que la Cartera lo devuelva y el buscador lo encuentre
Hoy, si te llama el número alternativo y lo escribes en el buscador, el CRM dice
que ese lead no existe. Se arregla.

### F2 · Que el puente no pierda ninguno
Conserva fijos y números extranjeros en vez de tirarlos en el origen. ⚠️ **Medido
después: vale 5 filas de 14.310.** El puente viejo ya cogía los segundos celulares
distintos. Se queda porque el CRM es más correcto así, no porque mueva la aguja.

### F3 · Que un número malo no cueste un lead
El lead entra siempre que tenga uno bueno. Si el segundo no sirve, entra sin él y
la hoja lo avisa en su columna de estado.

---

## Lo que falta

### F4 · Que NADA se pierda, ni lo ilegible *(pedido 6)*
Una columna nueva sin reglas de formato que guarda el segundo número **tal como lo
escribió la persona** cuando no se pudo entender. Y la ficha pasa a mostrar
**siempre** la fila, con uno de tres estados:

```
Teléfono alternativo   +51 918 620 573                    ← llamar / WhatsApp
Teléfono alternativo   «99988 7»  ⚠️ sin validar — tal como llegó
Teléfono alternativo   — el origen no dio un segundo número
```

El vendedor nunca se queda con la duda de si el CRM se comió un dato o si nunca lo
hubo. Y el campo bueno sigue limpio, que es lo que hace que el botón de llamar
funcione.

### F5 · Que el vendedor pueda USARLO, no solo verlo *(pedido 5)* — ✅ HECHA (sin publicar)
- ✅ botón de **WhatsApp** para el segundo número — y solo si es móvil: sobre un
  fijo, `numeroWhatsapp` devolvía un enlace perfectamente formado que nadie iba a
  contestar;
- ✅ **campo para corregirlo** en la ficha, que precarga el texto «sin validar»
  para no teclearlo de cero. Es la vía con la que se arreglan las 299 filas;
- ✅ **campo en el alta manual**, que admite celular, fijo o número de otro país;
- ⏸️ la **tarjeta al pasar el mouse** — no hecha, cabe poco y el dato está a un clic.

**La sorpresa de F5: la regla del teléfono tenía SEIS espejos, no cuatro.** Los
dos que faltaban vivían en el servidor (`crm.crear_lead_si_disponible` y
`private.normalizar_telefono`). Sin ellos, el front habría aceptado un fijo que
la base rechazaba.

**Decisión (opción A):** el primer número IDENTIFICA al lead y sigue siendo
celular peruano; el segundo solo lo contacta y admite lo que sea. La alternativa
—alinear también el principal— obliga a tocar `private.normalizar_telefono`, que
es con lo que el CRM decide que dos leads son el mismo: movería esa huella hacia
atrás sobre 544 leads vivos.

⚠️ **Asimetría asumida:** por la vía automática un lead SÍ entra con un fijo de
identidad (allí la alternativa era perderlo). A mano se exige celular, así que un
cliente de oficina que solo deje un fijo no se podrá registrar.

### F6 · Que sobreviva al cierre — pendiente
Al convertir el lead en cliente, el segundo número se pierde: no viaja a la ficha
del cliente ni al contrato.

### F7 · Rellenar los 530 leads viejos — pendiente (vale ~55 leads)
Pase único que relee el origen, cruza por el número principal y completa el segundo
en los leads que ya están en el CRM. No pasa por la hoja: esas filas ya están
marcadas como importadas y no vuelven a viajar.

### F8 · Publicar y verificar
Con leads reales del día siguiente.

---

## El orden, y por qué NO se puede alterar

```
F0 (diagnóstico)   →  decide si F2 y F7 valen la pena
        ↓
BASE  →  CONECTOR  →  HOJA          ← este orden es obligatorio
        ↓
F4 · F5 · F6                        ← se pueden hacer en paralelo
        ↓
F7 (relleno histórico)              ← al final, a propósito
```

**La base y el conector ANTES que la hoja.** Si el puente empieza a mandar fijos y
extranjeros antes de que el CRM los acepte, esos leads se rechazan: se perderían
leads por intentar salvarlos.

**F7 al final.** Rellenar el histórico antes de arreglar el circuito repetiría el
mismo error 530 veces.

**F0 primero de todo.** Es lo único que puede decir si el origen trae de verdad
segundos números. Sin ese dato, F2 y F7 se construyen sobre una suposición.

---

## Estado técnico al 2026-08-26

| Pieza | Dónde | Estado |
|---|---|---|
| Diagnóstico del origen | menú de la hoja | escrito · 67 pruebas |
| La regla del teléfono | `telefonos.ts` (conector) | 18 pruebas |
| Su gemela del front | `lib/validacion.ts` | 2228 pruebas |
| Su gemela del puente | `puente-drive-origen.gs` | gate verde · e2e 63 |
| Cartera devuelve el 2.º nº | migración `20260826151907` | 6 mutantes muertos |
| El CHECK acepta fijos y mundo | migración `20260826154500` | 4 mutantes muertos |

**La regla vive en CUATRO sitios y tienen que decir lo mismo**: `telefonos.ts` del
conector, `validacion.ts` del front, `reconocerTelefono()` del puente y el CHECK
`leads_telefono_alternativo_formato`. Mover uno sin los otros es cómo se pierde un
lead sin que nadie lo vea.

## Lo único que no puedo hacer yo

Pegar el `.gs` en el editor de Apps Script de la hoja. Eso es tuyo, y F0 depende de
ello.
