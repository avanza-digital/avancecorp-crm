# Agente de guía comercial para vendedores (plan)

> **Estado:** plan aprobado técnicamente, **sin ejecutar** — espera decisiones de Miguel (sección 9).
> **Origen:** pedido de Miguel 2026-07-19: "un agente de guía para los vendedores, NO algo con lo que puedan conversar".
> **Método:** workflow de 18 agentes (5 lectores → 3 arquitecturas en competencia → panel de 3 jueces → 5 refutadores adversariales → síntesis). Ganó la arquitectura **determinista** en las 3 lentes (valor 8, entregabilidad 9, riesgo 9). 48 hallazgos de refutación, 27 bloqueantes/altos, todos incorporados al plan.
> **Relacionadas:** [[CRM conexión a datos reales]] · [[Agenda comercial del CRM (plan v2)]] · [[Categorización de inversiones - Nuevo Renovación Upgrade]] · [[Ciclo de vida de contratos]] · [[Acceso y roles del CRM]] · [[Canales de origen de leads CRM]] · [[Distribución de leads por capital y trazabilidad CRM]]

---

# Guía comercial de Avance Corp — plan definitivo

**Fecha:** 2026-07-19 · **Para:** Miguel Briceño (dueño de producto) · **Alcance:** CRM en crm.miavance.com

---

## Antes de empezar: la respuesta directa a lo que pediste

Pediste **"que les recomiende mensajes según la etapa del prospecto"**.

Hoy eso no se puede hacer, y no por falta de tecnología: **no hay prospectos cargados**. `crm.leads` tiene 0 filas, igual que `crm.actividades`, `crm.tareas` y `crm.objetivos`. Y el pipeline de leads está oculto para tu fuerza de ventas por decisión tuya del 2026-07-16 (`FUNCIONES_LEADS_APROBADAS = false`). Cualquier plan que te prometa eso para esta semana te está mintiendo.

Lo que **sí** tienes hoy, cargado y real: **188 clientes, 197 contratos activos, 1.960 cuotas en cronograma**, repartidos entre **19 carteras** (17 vendedores + 2 supervisores). Y esos clientes también tienen etapas: les toca cobrar, no tienen cuenta bancaria registrada, se les venció el contrato, se registraron y nunca invirtieron, son candidatos a subir su capital.

**La propuesta es esta:** construimos un motor de guía que hable de la etapa del *cliente en su ciclo de inversión*, que es lo que hay hoy. Cuando cargues los leads y abras el gate, **la misma máquina** empieza a hablar de la etapa del *prospecto* — con un `UPDATE` de una fila, sin reescribir nada.

Y una advertencia honesta que verás repetida en todo el documento: **esto compite por tu tiempo con cargar leads reales**. Mi recomendación es que la carga de leads va primero o en paralelo, porque desbloquea el CRM entero. Este proyecto vale la pena igual, pero no debe empujar esa carga hacia atrás.

---

## 1. Qué es

Un **motor de reglas** que mira tu cartera y le dice a cada vendedor, en su propia pantalla, las tres cosas concretas que tiene que hacer hoy — con el mensaje ya redactado, listo para enviar.

- **No es un chatbot.** No hay caja de texto, no hay conversación, no hay turnos, no hay "escríbeme una pregunta". El vendedor no le habla; **la guía le habla a él**, sola, cuando abre el CRM.
- **No inventa nada.** Cada mensaje sale de un catálogo de textos que **tú aprobaste uno por uno**. Un modelo de IA los redacta *antes*, offline, a partir de tu capacitación; tú los firmas; recién entonces existen. En el momento en que el vendedor lo ve, no hay ninguna IA corriendo.
- **Es específico, no genérico.** No dice "haz seguimiento". Dice: "A CARO DIAZ le depositamos el miércoles 22 y no tenemos su cuenta en soles. Este es el mensaje para pedírsela."
- **Es explicable.** Cada consejo tiene un botón "¿por qué?" que muestra el párrafo literal de tu material de ventas del que salió.
- **Se apaga solo.** Cuando el cliente da su cuenta, la señal desaparece. No hay bandeja de pendientes que acumule.

---

## 2. Cómo se integra al CRM

Esta es tu pregunta #1, así que va con detalle.

### 2.1 Dónde vive el código

Todo el motor es una carpeta nueva, aislada, dentro de la app del CRM:

```
CRM-Avance-Corp/app/src/lib/guia/
  tipos.ts          contratos de datos (qué es una "señal", qué es un "consejo")
  motor.ts          la función central: senalesDe(cartera, ahora) → señales ordenadas
  orden.ts          cómo se rankean (lo que genera ingreso, primero)
  estado-clave.ts   cómo se segmenta un caso para elegir el mensaje correcto
  recetario.ts      catálogo de mensajes + validación de lenguaje prohibido
  render.ts         el único lugar donde el nombre y el monto entran al texto
  telefono.ts       normalización de números para WhatsApp
  guion-base.ts     los mensajes, compilados dentro de la app
  reglas/cobranza.ts, contratos.ts, clientes.ts, leads.ts, agenda.ts
```

El motor es **puro**: recibe datos y devuelve señales. No pide datos, no llama a internet, no escribe en la base. Eso lo hace testeable al 100% y significa que un error del motor no puede corromper ningún dato.

Reutiliza lo que ya existe: `lib/inteligencia.ts` (el motor de reglas que ya tienes vivo para leads), `lib/agenda-derivada.ts`, `lib/tipo-cambio.ts`, `lib/format.ts`. **No se reinventa nada de eso.**

### 2.2 Dónde aparece en la pantalla

Una franja llamada **"Tu gestión hoy"**, arriba de la tabla, en **dos pantallas**: Clientes y Contratos.

¿Por qué esas dos y no otras? Porque hoy, con el gate de leads cerrado, **son las únicas dos que tu fuerza de ventas ve**. Un vendedor que entra al CRM aterriza en Clientes. Ahí, encima de la tabla, hay un hueco literalmente vacío. Ahí va la franja.

```
┌─ Tu gestión hoy ─────────────────────────── 3 ─┐
│ ● CARO DIAZ · le cobramos el mié 22 y no       │
│   tenemos su cuenta en soles · S/ 2.500        │
│   [Enviar por WhatsApp]                        │
│ ● 5 clientes cobran esta semana:                │
│   S/ 5.973,76 y US$ 127,50 · [Ver lista]       │
│ ● Contrato 000789 vence en 150 días ·          │
│   S/ 120.000 · [Preparar renovación]           │
│                                     + 2 más ▾  │
└────────────────────────────────────────────────┘
```

Máximo **3 tarjetas**. El resto va detrás de "+N más". Si no hay ninguna señal, **la franja no se dibuja** — no aparece un recuadro vacío diciendo "todo al día", porque eso enseña a ignorarla.

Al pulsar el botón se abre una ventana con el mensaje ya escrito, **editable**, con el nombre y el monto reales adentro, y con el botón para enviarlo.

**No se añade ningún menú, ninguna pestaña, ningún ícono nuevo.** El vendedor no tiene que aprender a usar nada.

### 2.3 Por dónde viajan los datos

```
Supabase (con RLS)  ──►  navegador del vendedor  ──►  pantalla
   solo su cartera          el motor corre AQUÍ        WhatsApp
```

1. El navegador pide los datos que **ya pide hoy** (sus clientes, sus contratos) más una consulta nueva de cobranza. La base de datos, por sus reglas de seguridad, solo le entrega su propia cartera.
2. El motor corre **dentro del navegador**, sobre esos datos. Tarda menos de 1 milisegundo.
3. El texto del mensaje se arma **en el navegador**, mezclando la plantilla aprobada con el nombre y el monto reales.
4. El vendedor lo revisa, lo edita si quiere, y lo envía por WhatsApp.

**Nada de esto sale a internet.** No hay ningún servicio de IA involucrado en el momento del uso. Ni el nombre del cliente, ni su monto, ni su teléfono viajan a ningún tercero. El único texto que sale de Avance Corp es el WhatsApp que el vendedor decide mandar.

### 2.4 Qué se añade a la base de datos

En total, a lo largo de todo el proyecto: **4 tablas nuevas y 8 funciones nuevas**, todas dentro del esquema `crm` (el del CRM, separado del portal). Se añaden por fases, no todas de golpe:

| Fase | Qué se añade | Para qué |
|---|---|---|
| 1 | `crm.salud_cartera_fn` (lectura) | qué cobra pronto, quién no tiene cuenta |
| 1 | `crm.registrar_cuenta_cliente` (escritura) | que el vendedor pueda grabar la cuenta que le dan |
| 1 | `crm.guia_reglas` + `crm.fijar_regla_activa` | interruptor para apagar una regla sin desplegar |
| 3 | `crm.guion_piezas` + `crm.guion_historial` + 3 funciones | el catálogo de mensajes y su aprobación |
| 3 | `crm.guia_eventos` + `crm.registrar_guia_evento` | saber qué se mostró y qué se usó |
| 5 | `crm.guia_atribucion_fn` | responder "¿sirvió?" con evidencia |

Sobre la función de cobranza, una cosa que hay que decirte con claridad: **hoy la seguridad del portal no le da a tu gente el cronograma de pagos de sus clientes**. Los 2 miembros del equipo con rol de portal `comercial` (uno de ellos gerencia) leen cero filas de cronograma. Esta función nueva **les abre ese acceso, acotado a su cartera**. Es una decisión de negocio razonable — un vendedor debería saber cuándo cobra su cliente — pero es una decisión, no un accidente, y va documentada en la propia función y probada en el gate de seguridad con casos por cada combinación de rol de portal y rol de CRM.

### 2.5 Qué NO se toca

Esto es tan importante como lo anterior:

- **`lib/config.ts`** — el gate que oculta leads a la fuerza de ventas. La guía nace del lado correcto del gate y nunca lo cruza.
- **`App.tsx`, `router.ts`, `sidebar.tsx`, `topbar.tsx`** — cero cambios de navegación.
- **El portal público (miavance.com)** — no se toca una línea. Regla vigente: CRM y portal separados.
- **Las tablas del portal** (`contratos`, `perfiles`, `cronograma_pagos`) — se leen, nunca se les pone un trigger encima. Un error ahí rompería el alta de clientes en producción.
- **El alta de contratos y el flujo de aprobación** — intactos.

---

## 3. La verdad sobre los datos

Medí cada regla contra la producción real, sobre las 19 carteras — no sobre una sola. Esto es lo que hay:

### Lo que funciona HOY, con volumen real

| Señal | Casos hoy | ¿A cuántas carteras les toca? |
|---|---|---|
| **Le llega su interés esta semana** | 159 cuotas pendientes en 30 días | **16 de 17** vendedores con cartera |
| **Cobra y no hay dónde depositarle** | 18 contratos en bruto → **~4-12 reales** (ver nota) | 7 vendedores |
| **Próximo a vencer (150 días)** | ~29 contratos | ~10 vendedores |
| **Candidato a subir capital (upgrade)** | 36 upgrades históricos vs 6 renovaciones — **6 a 1** | la mayoría |
| **Registrado y nunca invirtió** | 10 en bruto → **~3 reales** tras filtrar pruebas | 6 vendedores |
| **Concentración de cartera** | informativa, 1 caso notable (38,4% en una persona) | pocas |

**Nota sobre "sin cuenta":** de los 18 casos en bruto, **6 ya cobraron** (uno hace tres días), así que la premisa "no se le puede depositar" es falsa en un tercio. Y **14 de los 18 tienen su cuenta en soles y solo les falta la de dólares**. Antes de encender esta regla necesito saber de operaciones cómo se paga realmente un contrato en dólares. Si se paga contra la cuenta en soles, los casos reales bajan de 18 a **4** — y ese 4 sí es una alerta de máxima prioridad defendible.

### Lo que NO funciona y por qué

- **"Le pagamos tarde":** 12 casos en bruto, de los cuales **11 son un solo día de desfase porque la fecha caía domingo o sábado**. Si un vendedor le escribe "disculpa la demora" a un inversionista con S/ 100.000 colocados porque el depósito salió el lunes en vez del domingo, acabamos de crear un problema que no existía. Se corrige contando **días hábiles con 3 de holgura**: la base entera produce **1 caso real**, no 12.
- **"Vence pronto" a 60 días:** emite **1 señal en toda la empresa**. El siguiente lote grande vence en diciembre-2026 (24 contratos) y enero-2027 (23). Con ventana de 60 días esta regla está muerta hasta septiembre. Va a **150 días**, rotulada como "preparar renovación", con la urgencia escalando conforme se acerca.
- **"Ventana de corrección de 5 horas":** **se elimina del alcance del vendedor.** Un vendedor no puede crear ni corregir contratos — la seguridad de la base exige rol admin. Sería una alerta que grita "corrígelo ya" a alguien que no tiene el botón. Si la quieres, va para gerencia.
- **Datos de prueba en producción:** de los 10 clientes "sin contrato", cinco son basura — "CLIENTE PRUEBA CARMEN", "ALEX", "BRICEÑO MIGUEL JOSE" (tú mismo), "GASPAR ADELAYDA" (una vendedora tuya registrada como cliente con el nombre invertido). La primera sugerencia que vería un vendedor sería mandarte un WhatsApp de reactivación **a ti**. Hay que borrarlos.

### El dato incómodo que cambia el plan

Miré `auth.sessions` de las últimas 6 semanas. **La mediana de tu fuerza de ventas es ~3 días con sesión en 6 semanas.** Tres personas no han entrado nunca o no tienen sesión alguna. Solo dos (Rosa Aguirre con 12 días, Fiorella Ruiz con 10) tienen algo parecido a un hábito.

Esto significa que **una franja dentro de la app no alcanza a quien no abre la app**. Una señal de cobranza con ventana de 7 días tiene aproximadamente 50% de probabilidad de caducar sin que nadie la haya visto. Por eso el plan incluye, como fase propia y temprana, **un resumen semanal por correo**. Sin eso, construimos un panel excelente que nadie mira.

### Y el detalle que rompe el botón principal

De los 185 clientes con teléfono, **170 lo tienen guardado a 9 dígitos, sin código de país** ("952852321"). El enlace de WhatsApp que construye el CRM hoy produce `wa.me/952852321`, que WhatsApp rechaza o resuelve como número de otro país. Solo 13 tienen el "51" adelante. **El botón estrella de la guía está roto para el 92% de los clientes antes de escribir una sola línea.** Se arregla en la fase 0, y de paso arregla los botones de contacto que ya existen hoy.

---

## 4. Fases

Supuesto de dedicación: una persona trabajando en esto sin competir con otro frente en el mismo repositorio. Cada fase con migración incluye el ciclo completo branch → gate de seguridad → advisors → merge, que en este proyecto toma días, no horas.

---

### Fase 0 · Higiene y decisiones
**~4 días de trabajo · sin migración de esquema · 21-24 de julio**

**Objetivo:** que los datos aguanten lo que viene, y arreglar de paso cosas que ya están rotas hoy.

**Qué ve el vendedor al final:** los botones de WhatsApp y Llamar que ya existen **empiezan a funcionar con todos los clientes**, no con el 7%. Y la lista de clientes deja de tener filas de prueba.

**Alcance técnico:**
- `lib/guia/telefono.ts` — normaliza a formato internacional: 9 dígitos que empiezan en 9 → se les antepone 51; 11 dígitos con 51 → tal cual; cualquier otro largo → se marca como no enviable (no se adivina). Se aplica en la frontera de lectura (`data/crm-api.ts`), no en cada pantalla.
- `UPDATE` puntual sobre los 185 teléfonos de `public.perfiles`.
- `lib/cliente-form-logica.ts:316` — que el alta guarde normalizado, o el problema vuelve con cada cliente nuevo.
- Corregir `components/app/contacto.tsx:133` para que el enlace de WhatsApp lleve mensaje prellenado (ya funciona en `lib/recordatorio.ts:41`; ese es el único punto sin hacerlo).
- Borrar o desactivar los 5 clientes de prueba en producción.
- Exportar la lista de patrones sensibles a `lib/pii.ts` (hoy está encerrada dentro de `observabilidad.ts` y no se puede reutilizar).

**Decisiones que se cierran aquí (contigo y con operaciones):**
1. Cómo se paga realmente un contrato en dólares. Determina si "sin cuenta" son 4 casos o 18.
2. Si el vendedor puede grabar la cuenta bancaria que el cliente le pasa por WhatsApp (ver decisión #2 en la sección 9).
3. Confirmar con Rosa y Fiorella — las dos que sí usan el CRM — si tienen WhatsApp Web emparejado en la laptop, o si contactan desde el celular. Cambia cuál es el botón principal.

**Criterio de aceptación:** un test con las 4 formas reales de teléfono observadas en producción ('952852321', '959 553 030', '51987654321', '96123456') y su resultado esperado. `select count(*) from public.perfiles where rol='cliente' and telefono is not null and telefono !~ '^\+?51'` devuelve 0.

**Dependencias:** tu respuesta sobre depósitos en dólares. Nada más.

---

### Fase 1 · La guía en pantalla
**~2,5 semanas · 1 tabla + 3 funciones · 28 de julio - 14 de agosto**

**Objetivo:** que un vendedor abra el CRM y vea, sin buscar, las tres cosas que le conviene hacer hoy — con el mensaje escrito.

**Qué ve el vendedor al final:** la franja "Tu gestión hoy" en Clientes y Contratos, con señales reales. Medido contra la producción de hoy: **16 de 17 vendedores tienen al menos una señal**. No es una demo.

**Señales que se encienden:**

| Señal | Prioridad | Cómo se comporta |
|---|---|---|
| Falta la cuenta para depositarle | máxima | solo si el contrato **nunca cobró** (si ya cobró, el hecho está desmentido) |
| Cobros de esta semana | alta | **una sola tarjeta agregada por semana**, no una por contrato |
| Próximo a vencer / preparar renovación | alta-media | ventana 150 días, urgencia escalada, agregada por semana si son muchos |
| Candidato a subir capital (upgrade) | media | clientes al día con capital medio o alto |
| Registrado y nunca invirtió | media | solo si tiene ≥7 días de antigüedad y no es empleado ni prueba |
| Le pagamos tarde | media | solo si ≥3 días **hábiles** de desfase → hoy: 1 caso real |
| Concentración de cartera | informativa | al pie, sin color de alerta |

Lo de "agregada por semana" no es un detalle: **162 de tus 197 contratos son mensuales**. Astrid Centenaro tiene 30 de sus 35 contratos con cuota en los próximos 30 días. Si emitiéramos una tarjeta por contrato, los 3 espacios visibles serían siempre el mismo aviso repetido y en dos semanas nadie leería la franja. Una tarjeta dice "5 clientes cobran esta semana: S/ 5.973,76 y US$ 127,50", y abre la lista.

**Alcance técnico:**
- Toda la carpeta `lib/guia/` con tests unitarios.
- `components/app/guia-gestion.tsx` (la franja) y `mensaje-sugerido.tsx` (la ventana del mensaje).
- Montaje en `screens/clientes.tsx` y `screens/contratos.tsx`.
- `data/guia-api.ts` + `guia-queries.ts` con validación estricta en la frontera.
- Migración `crm.salud_cartera_fn` — devuelve qué cobra pronto y **el veredicto** de si falta cuenta. Nunca devuelve números de cuenta ni CCI al navegador. El cálculo de días hábiles vive aquí, con calendario de feriados peruanos.
- Migración `crm.registrar_cuenta_cliente` — para que el vendedor grabe la cuenta que le dieron (ver decisión #2).
- Migración `crm.guia_reglas` + `crm.fijar_regla_activa` — el interruptor. Toda regla nace **apagada**; se encienden de a una, mirando qué pasa. Apagar una es un clic en la pantalla de Gerencia, sin desplegar nada. **Efecto en menos de un minuto** (la app relee los interruptores cada 60 segundos; el catálogo de textos, que es pesado y no es un control de seguridad, se cachea 30 minutos).
- 5 a 8 plantillas de mensaje escritas por ti, compiladas dentro de la app.

**Criterios de aceptación verificables:**
1. Cada señal emitida tiene al menos una acción que el rol que la ve **tiene permiso de ejecutar** — test automático que cruza regla × rol × acción y falla si alguna es imposible.
2. `select count(distinct vendedor) from señales_emitidas` ≥ 16 sobre datos de producción.
3. La franja **no se dibuja** cuando no hay señales.
4. Soles y dólares nunca se suman en pantalla; cuando no hay tipo de cambio, el orden se segrega en vez de inventar una tasa.
5. Gate de seguridad ampliado de 232 a ~240 casos, incluyendo un caso por cada par (rol de portal, rol de CRM) contra la función de cobranza. Advisors limpios.
6. Ningún mensaje mezcla datos de dos contratos distintos — test que verifica que toda variable interpolada procede del mismo sujeto, moneda incluida.

**Dependencias:** fase 0 cerrada. Tus 5-8 plantillas. Tu respuesta regulatoria (ver decisión #1). **Si las plantillas no están listas, la fase se despliega igual**: las señales se muestran con su explicación automática y sin mensaje sugerido. Es útil por sí sola.

---

### Fase 2 · La guía te busca
**~1,5 semanas · 1 edge function · 18-27 de agosto**

**Objetivo:** que la señal llegue aunque el vendedor no abra el CRM. Esta es la fase que decide si el proyecto se usa o no.

**Qué ve el vendedor al final:** un correo los lunes por la mañana con sus 3 señales principales y enlaces directos a la pantalla correspondiente. Y un correo el jueves si tiene algo de máxima prioridad sin resolver.

**Alcance técnico:**
- Edge function nueva (`crm-guia-resumen`) que corre el **mismo motor** `senalesDe`, por perfil, y manda por Resend.
- Extraer `private.equipo_subarbol` — la función de visibilidad actual **devuelve vacío si no hay sesión de usuario**, así que un trabajo programado la usaría y materializaría cero filas en silencio. Hay que separar el árbol del control de sesión, dejando el control en la capa de arriba. Es la pieza más delicada de esta fase.
- Cron semanal.

**Criterio de aceptación:** los 19 miembros reciben su correo; el contenido coincide exactamente con lo que verían en pantalla (misma función, no dos implementaciones); un miembro sin señales **no recibe correo**.

**Dependencias:** fase 1. Un dominio verificado en Resend para el envío.

---

### Fase 3 · Gobierno del guion
**~2 semanas · 3 tablas + 6 funciones · 1-12 de septiembre**

**Objetivo:** que puedas cambiar lo que dicen los mensajes sin que nadie despliegue nada, y que sepamos qué se muestra y qué se usa.

**Qué ve el vendedor al final:** poco — mensajes mejores y una nota de origen en la ventana ("Miguel · Módulo 3, Renovaciones"). **Esta es infraestructura, y te lo digo así en vez de venderla como una mejora.** Lo que compra es que las fases 4 y 5 sean posibles y que un mensaje malo se retire en un minuto en vez de en un despliegue.

**Alcance técnico:**
- `crm.guion_piezas` con ciclo borrador → aprobada → retirada, y funciones para cada paso.
- **Retirar una pieza la borra de verdad.** Este es un punto que en el diseño anterior estaba mal: retirar la versión aprobada hacía que reapareciera la versión anterior compilada en la app, sin aviso. Ahora una pieza retirada es una lápida: la señal se queda sin mensaje sugerido y muestra solo la explicación.
- **El filtro de lenguaje prohibido es una restricción de la tabla, no un chequeo dentro de una función.** Así ninguna vía de escritura lo evade — ni un script, ni la consola de administración. Incluye una regla estructural, no solo una lista de palabras: **las piezas no admiten un número seguido de "%"**. Es objetiva y no se esquiva con sinónimos, a diferencia de una lista negra (que se evade con "cero riesgo" o "capital protegido").
- `crm.guion_historial` con **trigger**, no con cortesía de las funciones: toda escritura sobre el catálogo deja rastro, venga de donde venga. Para un producto financiero, "quién aprobó esta frase" tiene que ser una propiedad de la base, no una convención.
- `crm.guia_eventos` — qué se mostró, qué se copió, qué se omitió. **Con deduplicación a nivel de base** (a lo sumo un registro por vendedor, señal y día), FK al catálogo de reglas, límites de longitud y purga automática a 12 meses. Sin la deduplicación esto genera cientos de miles de filas al mes; con ella, unas 1.100.
- **"Omitir" empieza a suprimir de verdad.** Hoy no existe: el botón haría desaparecer la tarjeta y reaparecería al minuto siguiente. Las omisiones entran al motor como dato: prioridad máxima reaparece a los 7 días (es dinero), el resto a los 30 o nunca.
- La tabla de eventos se declara como **dato personal pseudonimizado** (conecta vendedor con cliente identificable), no como "telemetría sin datos personales". Bajo la Ley 29733 eso importa para el plazo y el registro de tratamiento.

**Criterio de aceptación:** un intento de escribir texto prohibido por cualquier vía falla con violación de restricción. Una pieza retirada deja la señal sin mensaje aunque exista la versión compilada. Gate de seguridad ampliado (~248 casos), incluyendo un caso que intente forjar el identificador de un contrato ajeno y exija cero resultados.

**Dependencias:** fase 1.

---

### Fase 4 · Tu capacitación adentro
**~2 semanas desde que entregues el material**

**Objetivo:** que los mensajes dejen de ser plantillas tuyas escritas a mano y pasen a ser tu método de ventas, con cita al módulo del que salen.

**Qué ve el vendedor al final:** mensajes segmentados de verdad — la renovación de S/ 170.000 de un cliente puntual no recibe el mismo texto que una de S/ 5.000 — y el botón "¿por qué?" muestra el párrafo literal de tu curso.

**Alcance técnico:**
- `docs/capacitacion/*.md` — tu material normalizado a texto, por módulo, con anclas.
- `scripts/guion/destilar.mjs` — genera los borradores en lote, offline.
- Pantalla en Gerencia: "Aprobar mensajes", **con aprobación por lote**, no de a uno.
- `guion.test.ts` — falla si una regla activa se queda sin mensaje, si un texto usa una variable no permitida, o si pasa el filtro regulatorio.

**Criterio de aceptación:** toda regla activa tiene mensaje para las combinaciones que existen en tu cartera real. Cero piezas activas sin cita al material.

**Dependencias:** **tú entregas el material Y firmas las piezas.** Detalle completo en la sección 5.

---

### Fase 5 · Equipo y evidencia
**~1 semana · 1 función**

**Objetivo:** que los supervisores vean lo mismo que sus vendedores, y que puedas responder "¿esto sirvió?" con datos.

**Qué ve el supervisor:** el mismo panel, con el alcance de su equipo. Mismo motor, mismos textos — no dos implementaciones que puedan divergir.

**Qué ves tú:** un panel con, por regla, cuántas veces se mostró, cuántas se actuó y cuántas terminaron con el hecho resuelto. Rotulado como **evidencia observacional, no causal** — el sistema presenta datos, tú decides.

**Alcance técnico:** `components/app/guia-equipo.tsx` + `crm.guia_atribucion_fn`, con el gate de gerencia que le corresponde y el alcance aplicado en **todas** sus consultas internas. Reglas sin criterio de cierre medible muestran "—", **nunca 0** — un cero se lee como "no funcionó" cuando en realidad significa "no lo sabemos medir".

**Condición para encender el panel del supervisor:** las reglas de cobranza deben haber pasado una revisión de precisión primero. Una lista inocultable con imputaciones erróneas no construye adopción; construye un pedido formal de apagar la función.

**Dependencias:** fase 3.

---

### Fase 6 · Prospectos
**Sin fecha — bloqueada por ti**

**Objetivo:** lo que pediste literalmente, con las mismas palabras: mensajes según la etapa del prospecto.

**Qué ve el vendedor:** las mismas tarjetas, ahora sobre leads: sin responder, propuesta sin respuesta, seguimiento vencido, por repartir, recordatorio de cita, no asistió.

**Alcance técnico:** casi nada nuevo. Las reglas de leads son una **envoltura** de `colaDe`, `estancados`, `sinProximaAccion` y `colaHigiene`, que **ya existen y funcionan** en `lib/inteligencia.ts`. Encender la familia es un `UPDATE` de una fila.

**Prerequisito legal, no negociable:** el campo `no_contactar` funcionando de punta a punta antes de la primera regla de leads. Son ~30 líneas de frontend. Ojo con una trampa real: `crm.leads` tiene permisos **columna por columna**; hoy las 30 columnas están cubiertas, pero **toda columna nueva que se agregue nace sin permiso** y falla de forma confusa en producción. Ya costó tiempo antes.

**Dependencias:** que cargues los leads reales, y que abras el gate. **Esto es un hito de negocio con dueño (tú), no una dependencia técnica.**

---

## 5. Tu capacitación de ventas: cómo entra al sistema

### Paso 1 — Qué me entregas

El material tal como esté: PDF, Word, presentaciones, o transcripciones de video. **No necesitas prepararlo.** Solo dos cosas:
- Que cada archivo tenga un nombre que diga de qué módulo es.
- Si hay video o audio, que me digas cuáles importan; se transcriben.

Se normaliza a texto plano por módulo, con marcas de párrafo para poder citar con precisión.

**Este material NO se compila dentro de la aplicación.** La app se sirve pública en crm.miavance.com; tu curso es propiedad de la empresa. Lo que viaja a la app son las **plantillas de mensaje** (texto que de todos modos se envía por WhatsApp). El párrafo literal de tu curso vive solo en la base de datos, protegido, y se muestra únicamente cuando alguien pulsa "¿por qué?".

### Paso 2 — Conciliación con lo que ya sabemos (bloqueante)

Tu material se contrasta contra la base de conocimiento del proyecto, que ya pasó una verificación contra el folklore de ventas. Ejemplos de cosas ya purgadas: "el 80% de las ventas ocurre tras el 5º seguimiento" y "el 44% abandona tras 1 intento" son mitos sin fuente; "5-8 toques" es para *conseguir contacto*, no para cerrar; la cifra vigente de tiempo no vendiendo es 72/28, no 60%; la "mañana protegida" son en realidad dos picos (10:00-11:30 y 16:00-18:00).

Si un pasaje tuyo repite algo purgado, se marca como *corregido*, con una nota, y se usa la versión corregida. Un pasaje marcado *retirado* el generador se niega a usarlo.

**Reparto de autoridad, explícito:** la base de conocimiento manda sobre **cuándo y con qué frecuencia** contactar (plazos, cadencias, topes de llamadas, horario legal). Tu curso manda sobre **qué decir** — guiones, manejo de objeciones, tono. Ese es tu terreno y ahí no se te contradice.

### Paso 3 — Generación en lote, offline

Un modelo de IA recorre las combinaciones de casos **que existen de verdad en tu cartera** y redacta un borrador para cada una, citando el pasaje de tu curso correspondiente.

Dos precisiones importantes:

**Sobre qué combinaciones.** El diseño original iba a generar unas 360 combinaciones teóricas. Pero tu cartera real solo tiene **15 combinaciones observadas** de (moneda × categoría × rango de monto), y cuatro de ellas concentran el 68% de los contratos. Generar 360 sería producir mayoritariamente texto para casos que no existen — y hacértelo aprobar igual. El generador se alimenta de lo que hay en `public.contratos`, no de un producto cartesiano.

**Sobre lo que sale de Avance Corp.** La petición al modelo lleva **solo etiquetas y números**: qué regla, qué moneda, qué rango de monto, qué categoría, cuántos días. Sin nombres, sin identificadores, sin montos exactos, sin texto libre del CRM. Es estructuralmente incapaz de llevar datos de un cliente. El control es doble: una lista blanca estricta de campos permitidos (falla si aparece un campo nuevo) y un escaneo de valores que falla si algo parece un identificador, un correo o una secuencia larga de dígitos. Se ejecuta sobre el JSON exacto que se envía, no sobre el objeto de entrada.

### Paso 4 — Mapear tu curso a los casos (tu trabajo, declarado)

Para que cada mensaje traiga la cita literal correcta hay que saber **qué sección de tu curso corresponde a cada caso**. Descartamos montar un buscador semántico dentro de la base de datos (ver sección 8), así que este paso se hace con búsqueda de texto sobre tu material más tu revisión.

**Esto cuesta tiempo tuyo y no lo voy a esconder: entre 2 y 4 horas**, en una sola sentada, marcando qué módulo aplica a qué tipo de situación. Es la primera vez que el documento te pide esto explícitamente porque en el diseño anterior este trabajo estaba, simplemente, sin dueño.

### Paso 5 — Tu firma, pieza por pieza

Ningún vendedor ve un texto que tú no aprobaste. Se hace en dos lotes:

- **Lote 1: ~15 mensajes genéricos** (uno por regla). Con eso el sistema funciona **entero**, con copy seguro y citado. **15 firmas, ~20 minutos.**
- **Lote 2: ~15-25 mensajes especializados** para las combinaciones que concentran el 68% de tus contratos. **~30 minutos.**

Total: **~40-60 minutos de tu tiempo**, no las 4-18 horas que habría costado aprobar el catálogo completo. Con aprobación por lote en la pantalla, no de a uno.

Que el dueño firme cada frase que 17 vendedores enviarán a 188 inversionistas reales, en un producto de renta fija en Perú, **es una ventaja regulatoria**. Pero es tiempo tuyo y va en el presupuesto.

### Qué pasa en cada fase con el material

| Fase | Estado del material |
|---|---|
| 0-1 | No hace falta. Van 5-8 plantillas tuyas escritas a mano, o ninguna (las señales funcionan sin mensaje). |
| 2 | Igual — el correo lleva las mismas plantillas. |
| 3 | Se prepara el lugar donde va a vivir: catálogo, aprobación, historial. |
| 4 | **Entra el material.** Aquí el agente empieza a asesorar con tu capacitación de verdad. |
| 5-6 | El catálogo se amplía a las nuevas reglas con el mismo proceso. |

---

## 6. Costo y operación

### Funcionamiento diario, 17 vendedores

| Concepto | Costo |
|---|---|
| **Por consejo mostrado** | **US$ 0,00** — no hay ningún servicio de IA corriendo |
| **Al mes, toda la fuerza de ventas** | **US$ 0,00** |
| Correo semanal (fase 2, Resend) | ~80 correos/mes — dentro del plan gratuito |
| Almacenamiento en base de datos | ~1.100 filas/mes de bitácora, con purga a 12 meses |

Esto no es optimismo: es consecuencia directa de la arquitectura. El motor corre en el navegador sobre datos que ya se descargan. **Si internet se cae o la base no responde, la guía sigue funcionando** con lo que viene compilado en la app.

Velocidad: menos de 1 milisegundo para calcular las señales; el vendedor con más carga tiene 35 contratos. En frío se añaden 120-250 milisegundos de red, en paralelo con consultas que ya se hacen. Después, cero.

### Generación del guion, pago único

Modelo Opus vía API por lotes (50% de descuento).

| Escenario | Costo |
|---|---|
| Fases 0-3 (plantillas tuyas a mano) | **US$ 0** |
| Catálogo completo de fase 4 | **entre US$ 10 y US$ 40**, una sola vez |
| Regeneración tras revisar el curso | ~US$ 3 |

Corrijo una cifra que circulaba antes: se decía "menos de dos dólares con descuento por caché". Ese descuento **no aplica** aquí (el mínimo para cachear son 4.096 tokens de prefijo, el lote se procesa en paralelo y el caché expira en 5 minutos mientras un lote puede tardar horas). El número real es US$ 10-40. Sigue siendo despreciable, pero prefiero darte el número correcto.

### El costo que sí importa

| Concepto | Costo |
|---|---|
| Mapear tu curso a los casos | **2-4 horas tuyas**, una vez |
| Aprobar los mensajes | **40-60 minutos tuyos**, una vez |
| Redactar 5-8 plantillas para fase 1 | **~1 hora tuya** |
| Responder la pregunta regulatoria | tiempo de tu abogado o contador |

**El proyecto no está limitado por dinero. Está limitado por tu tiempo y por la carga de leads.**

### Operación continua

- Apagar una regla que molesta: un clic en Gerencia, efecto en menos de un minuto.
- Cambiar el texto de un mensaje: editar y aprobar en Gerencia, sin desplegar.
- Retirar un mensaje: un clic; la señal se queda sin mensaje sugerido pero sigue mostrando el hecho.
- Revertir las fases 0-1: un despliegue.

---

## 7. Riesgos y cómo se contienen

**1. Que el vendedor deje de mirar la franja.**
El riesgo más probable. Se contiene con: máximo 3 tarjetas; agregación de los cobros mensuales en una sola tarjeta (sin esto, el 86% de la cartera de Astrid dispara el mismo aviso todos los meses); "Omitir" que suprime de verdad; la franja no se dibuja si no hay nada; y el correo semanal para quien no entra.

**2. Que la guía diga algo falso a un cliente real.**
El escenario que más daño haría. Contención: "sin cuenta" solo si el contrato nunca cobró; "pago tardío" con días hábiles y 3 de holgura (de 12 casos falsos a 1 real); un test que verifica que toda variable del mensaje viene del **mismo** contrato, moneda incluida — el ejemplo que circulaba antes mezclaba el número de un contrato con la fecha de otro, que era en dólares; y el mensaje es **editable** antes de enviarse.

**3. Que se envíe lenguaje regulatoriamente peligroso.**
Vendes renta fija de 12-25% anual a personas naturales en Perú, y **no hay ni una nota en la base de conocimiento del proyecto sobre tu estatus ante SBS o SMV**. Contención en tres capas: una restricción de la tabla que ninguna vía de escritura puede evadir; una regla estructural (ninguna pieza puede llevar un número seguido de "%"); y **tu firma en cada pieza, registrada por trigger**. Te lo digo sin adornos: la lista de palabras prohibidas es una ayuda, no una garantía — se evade con "cero riesgo". **El control real eres tú aprobando.**

**4. Que alguien vea datos de cartera ajena.**
Contención: el motor corre sobre datos que la seguridad ya filtró; toda función nueva valida el alcance en **cada** consulta interna, no solo en la primera; la función de atribución valida el identificador **al escribirlo**, no solo al leerlo (sin eso, un vendedor podía preguntar por los 184 contratos que no son suyos y averiguar si tienen cuenta bancaria); casos nuevos en el gate de seguridad para cada combinación de rol de portal y rol de CRM.

**5. Que se pierda el rastro de qué se aprobó.**
Contención: historial por trigger, no por convención; permisos de escritura directa revocados; el historial es solo-inserción.

**6. Que la señal muera sin que nadie la vea.**
Con 3 días de sesión al mes, una señal de 7 días tiene ~50% de probabilidad de caducar sin verse. Contención: fase 2 (correo). Y una métrica que decide si esto vive: **señales emitidas contra señales efectivamente mostradas**. Si esa proporción se queda bajo 50%, el problema no es el motor y hay que cambiar el canal, no el copy.

**7. Que el despliegue se cruce con otro trabajo en el mismo repositorio.**
Ya pasó: el 2026-07-17 hubo una carrera de despliegues y ganó el último; el 2026-07-18 un "rollback a estable" eligió el artefacto equivocado. Contención: cada fase se commitea de forma selectiva con verificación de hash antes y después, contrastado contra el registro de despliegues.

**8. Que el vendedor no pueda cerrar el círculo.**
Si un vendedor ve "falta la cuenta", la pide por WhatsApp, el cliente se la da, y **no puede grabarla en ninguna pantalla** — porque la seguridad del portal solo permite editar un cliente dentro de las 5 horas de creado, y estos clientes tienen entre 2 y 58 días — entonces la alerta se queda arriba del panel para siempre. Es el diseño exacto de una alerta que enseña a ignorar todo lo demás. Contención: la decisión #2 de la sección 9.

---

## 8. Lo que decidimos NO hacer

**Un chatbot.** Es lo que pediste evitar y coincido. Una caja de texto obliga al vendedor a saber qué preguntar; la guía le dice qué hacer sin que pregunte.

**IA corriendo en el momento del uso.** Añadiría 5 a 12 segundos de espera por consejo, una dependencia externa que puede caerse en mitad de una llamada con un inversionista, datos de clientes cruzando internet, y texto que tú nunca leíste — para producir el mismo resultado que un lote generado antes por US$ 10-40. El argumento no es el dinero (serían ~US$ 18/mes, despreciable): es la latencia, la dependencia y la revisión humana.

**Buscador semántico dentro de la base de datos.** La extensión está disponible pero no instalada. Instalarla en tu base financiera de producción, más contratar un segundo proveedor sin acuerdo de retención de datos, para recorrer un corpus que cabe en un lote — no se justifica. La cita al material, que es lo valioso, se conserva sin nada de eso.

**Calcular y guardar las señales por adelantado en la base.** Requeriría reescribir la función de seguridad más delicada del sistema, con tres políticas colgando de ella. Y añade dos modos de falla que el motor en el navegador no tiene: mostrar la señal equivocada (que además sería pública para el supervisor) y fallar en silencio diciendo "todo al día" mientras cuatro clientes no pueden cobrar.

**Triggers sobre las tablas del portal.** Un error ahí rompe el alta de clientes en producción. Y viola la separación CRM/portal que fijaste.

**Un segundo motor de reglas escrito en SQL.** Habría que mantenerlo sincronizado con el que ya tienes en TypeScript. Dos implementaciones que pueden divergir.

**La alerta de ventana de 5 horas para el vendedor.** No tiene permiso de corregir contratos. Sería gritarle que arregle algo sin darle el botón.

**Métricas que no tienen datos:** porcentaje de renovación (cero contratos con renovación registrada), mora (cero cuotas marcadas como vencidas), conversión y embudo (cero leads), cumplimiento de meta (cero metas fijadas), tendencias (3 meses de historia no dan proyección).

**"Llevas 19 días de julio con 0 clientes nuevos".** Un robot regañando a un comisionista, sin acción concreta asociada. La regla existe, pero con audiencia **supervisor**, no vendedor. Un CRM percibido como control sube la rotación.

**Rankings predictivos y verbos como "priorizar" o "pausar".** Prohibidos hasta pasar un gate de suficiencia estadística. La guía recomienda sobre **proceso** — a quién le toca, qué decir, qué falta — que es regla explicable. Nunca sobre ruteo estadístico.

**Etiquetar los consejos como "aprobado por gerencia".** Convierte un consejo en una orden de la jefatura sobre un cliente concreto, con el capital en pantalla, visible para el supervisor. La autoridad que compra adopción en un equipo comercial es la del formador, no la del que revisa la meta. La etiqueta dice **"Miguel · Módulo 3, Renovaciones"**.

**Guardar el texto del mensaje ya armado.** La bitácora guarda qué regla y qué caso, nunca el texto con el nombre y el monto adentro. Así un error de registro degrada a "consejo genérico", no a fuga de datos.

---

## 9. La decisión que necesito de ti

### 1. Estatus regulatorio de Avance Corp S.A.C., por escrito

No hay una sola nota en la base de conocimiento del proyecto que mencione SBS, SMV o Fondo de Seguro de Depósitos. Necesito saber qué puede y qué no puede decir un vendedor por escrito sobre el producto.

**Recomendación:** hasta tener respuesta, **el guion versión 1 no menciona tasas, rendimientos ni porcentajes**. Habla de fechas de cobro, cuentas faltantes, vencimientos y clientes sin invertir. Todas las señales de la fase 1 funcionan sin prometer rentabilidad. Consúltalo con tu abogado esta semana; no bloquea el arranque, pero sí bloquea la fase 4.

### 2. ¿Puede un vendedor grabar la cuenta bancaria que el cliente le pasa?

Hoy no puede: la seguridad del portal solo permite editar un cliente dentro de las 5 horas de creado, y los 18 casos tienen entre 2 y 58 días de antigüedad. Sin resolver esto, la alerta de máxima prioridad **no se puede cerrar nunca**.

**Recomendación: sí, con una función controlada.** Una función que solo escriba las columnas bancarias de la moneda pedida, solo sobre clientes de su propia cartera, con registro de quién y cuándo. El vendedor graba lo que el cliente le dio y la alerta muere de verdad.

**Si prefieres que no:** entonces el mensaje de esa alerta cambia a "pásale el dato a operaciones, tú no puedes grabarlo" y baja de prioridad, porque no es resoluble en un paso por quien la ve. Es peor, pero es honesto.

### 3. ¿Cómo se paga realmente un contrato en dólares?

De los 18 casos de "falta cuenta", **14 tienen cuenta en soles y solo les falta la de dólares**. Necesito saber de operaciones si un contrato en dólares se paga contra la cuenta en soles al tipo de cambio del día, o si hace falta la cuenta en dólares sí o sí.

**Recomendación:** pregunta a operaciones esta semana. Si se paga contra la cuenta en soles, los casos reales bajan de 18 a **4** — y esos 4 son una alerta de máxima prioridad defendible. Si no lo aclaramos, la primera cosa que verá tu equipo son 14 acusaciones falsas.

### 4. ¿El equipo contacta desde la laptop o desde el celular?

El código del CRM ya asume que marcan desde el celular corporativo. Si además no tienen WhatsApp Web emparejado, el botón "Enviar por WhatsApp" no es un toque: es escanear un código QR — y el vendedor hará lo que ya hace, copiar el número y escribir desde el celular, perdiendo por el camino el mensaje que tú curaste.

**Recomendación:** pregúntales a Rosa Aguirre y Fiorella Ruiz — son las dos únicas con hábito real de uso. Si no usan WhatsApp Web, el botón principal pasa a ser **"Copiar mensaje"** y la franja se diseña para leerse bien en celular. Es un cambio de una hora si se decide ahora, y un rediseño si se decide después.

### 5. ¿Cuándo entregas el material de capacitación?

Determina la fecha de la fase 4, que es donde el agente empieza a hacer lo que tú pediste. Las fases 0 a 3 son cimientos y muestran plantillas tuyas, no tu curso.

**Recomendación:** entrégalo tal como esté, sin prepararlo, apenas puedas. Aunque las fases 0-3 tomen 6 semanas, tener el material antes permite adelantar la conciliación y la generación de borradores, y que la fase 4 arranque el día que termine la 3.

### 6. ¿Esto va antes, después o en paralelo a cargar los leads reales?

**Recomendación: en paralelo, con los leads primero si hay que elegir.** Cargar leads desbloquea el CRM entero — el pipeline, la agenda, las metas, las funciones de gerencia que ya están construidas y esperando datos. Y es lo que convierte esta guía en lo que pediste literalmente.

Si eliges hacer solo una cosa este mes, haz la carga de leads. Si eliges hacer las dos, la fase 0 de este plan (cuatro días) mejora cosas que ya están rotas hoy y no compite con nada.

### 7. ¿Autorizas el correo semanal (fase 2)?

Los datos de uso dicen que la mediana de tu equipo es ~3 días con sesión en 6 semanas, y que 3 personas no han entrado nunca. Una franja dentro de la app no alcanza a quien no abre la app.

**Recomendación: sí, y temprano.** Es la fase que decide si el proyecto se usa o se abandona. Lunes por la mañana, 3 señales, enlaces directos, y nada si no hay señales.

---

## Resumen para decidir

| Fase | Qué entrega | ¿Valor para el vendedor? | Fecha estimada | Bloqueado por |
|---|---|---|---|---|
| **0 · Higiene** | teléfonos que funcionan, datos limpios | **sí** (arregla lo de hoy) | 21-24 jul | tu respuesta sobre dólares |
| **1 · Guía en pantalla** | la franja, 7 señales, 16/17 vendedores con contenido | **sí** | 28 jul - 14 ago | fase 0, tus plantillas, decisión #2 |
| **2 · La guía te busca** | correo semanal | **sí** (decide la adopción) | 18-27 ago | fase 1, dominio en Resend |
| **3 · Gobierno** | cambiar textos sin desplegar, bitácora | **no** (infraestructura) | 1-12 sep | fase 1 |
| **4 · Tu capacitación** | **lo que pediste**: asesoría con tu material | **sí** | +2 sem desde entrega | **tú entregas y firmas** |
| **5 · Equipo y evidencia** | panel del supervisor, "¿sirvió?" | **sí** (supervisión) | +1 sem | fase 3, precisión validada |
| **6 · Prospectos** | mensajes por etapa del lead | **sí** | sin fecha | **carga de leads + abrir el gate** |

**Tu tiempo total comprometido:** ~1 hora (plantillas) + 2-4 horas (mapeo del curso) + 40-60 minutos (aprobación) + las respuestas de arriba.

**Costo en dinero:** US$ 0 al mes de funcionamiento, US$ 10-40 una sola vez.

**Lo que puede matar el proyecto,** en orden: que nadie abra el CRM (fase 2 lo ataca), que la guía diga algo falso (calibración de fase 1), y que tu tiempo se vaya en aprobar 360 mensajes en vez de 30 (por eso el catálogo se genera desde tu cartera real, no desde un producto teórico).