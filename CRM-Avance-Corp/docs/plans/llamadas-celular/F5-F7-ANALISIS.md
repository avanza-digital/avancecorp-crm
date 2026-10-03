# F5 · F6 · F7 — análisis adelantado (planes cortos, borrador)

Escrito el 03/10/2026 sobre `a936b6ed` (su contenido está en `main` desde el #176). **Solo análisis: sin código ni
SQL.** Es para adelantar trabajo: **borrador, no pide revisión hasta que toque F5**. Las decisiones que lista para
Miguel se le presentan cuando llegue cada fase. Tiene el mismo molde que `F4-PLAN-CORTO.md`.

- **Fuentes:** `PLAN.md` §5 y §11–§16 (aprobado: no se reescribe), `estado.json`, `PROPUESTAS-DE-AJUSTE.md`,
  `REVISION-2026-10-02.md`, `CORRECCION-PLAN-CORTO.md`, `F4-PLAN-CORTO.md`, `macrodroid.md` §3c–§3d, la nota del vault
  de clientes y el código citado.
- **Cómo se verificó:** solo lectura de los archivos citados. No ejecuté nada: ni SQL, ni tests, ni consultas a la base.
- **Convenciones:** con `archivo:línea` = verificado leyendo ese punto. «(supuesto)» = no lo comprobé.
  «⏸» = depende de una decisión que nadie respondió todavía.
- **Estado de partida:** F5, F6 y F7 no tienen ninguna tarea empezada. En `estado.json` no hay entradas suyas en
  `fases`, `subfases` ni `tareas`, y `AVANCE.md` las muestra en 0/15, 0/12 y 0/12.

## ⚠️ Actualización 03/10, tras la respuesta de Miguel en el PR #175 (manda sobre lo de abajo)

El análisis se escribió antes de esa respuesta. Donde abajo dice «⏸», ya está decidido:
- **C1 → A:** F4-a se publica junto con F2+F3. F6 no tiene que excluir un periodo previo; a F5 solo le queda lo que
  no se registró al colgar.
- **C2:** entrantes bloqueadas; la #14 después. Las cifras de entrantes (#15) esperan.
- **C3:** ratificada. **Séptima decisión (nueva):** los leads sin dueño (`vendedor_id is null and
  asignado_supervisor_id is null`) y los descartados reutilizables también son candidatos: se guardan `por_revisar`,
  quien llamó no los ve y le aparecen a quien tome el lead. El universo de F5 (y el conteo del caso real) incluye esa bolsa.
- **C4:** 30 días desde `recibido_en` para las sin resultado; **las registradas se conservan como historial del lead**.
  Reemplaza la recomendación de F6 de darles 30 días. El plan v2 lo escribe como plazo decidido (§15: «no indefinido
  por omisión»).
- **C5:** riesgo aceptado por escrito. **C6:** bandeja vieja retirada.
- **MacroDroid Pro: no se compra todavía** (Miguel): solo hace falta para las entrantes. Sin ellas: 3 macros y el
  latido dentro de «Enviar cola», en la versión gratuita. Reemplaza lo de F7 sobre licencias y 6 macros.
- **Hallazgos que tocan lo de ahora**, comprobados en el código por la sesión principal:
  - `envios_hoy` (llamadas, también a números sin lead, + latidos: `20261001212258:308, 335`) y `ultimo_envio_en`
    (`:315`) se muestran a supervisión y gerencia (`:281-290, 370`) → propuesta para la corrección v2.
  - Cola enviada tras reasignar → regla de soporte (cola en 0 antes de reasignar).
  - Vía del enlace → diseño de F4-a.

## Decisiones abiertas que se citan

| Clave | Qué falta decidir | Dónde |
| --- | --- | --- |
| C1–C6 | Las seis de la corrección: **C1** cómo se unen la encuesta y la llamada (A: publicar con F4-a; B: publicar antes y limpiar después) · **C2** bloquear la perilla de entrantes · **C3** una llamada a un lead fuera del ámbito del dueño cuenta como número sin lead · **C4** 30 días de retención para las identificadas sin resultado · **C5** pista por tiempo · **C6** retirar la bandeja duplicada | `CORRECCION-PLAN-CORTO.md:116-125` |
| F4-1…F4-5 | Las cinco de F4: **1** emparejar por el id de origen · **2** puerta v5 en una transacción · **3** pestaña del analista · **4** supervisor y gerencia en F4 (F4-e) o en F6 · **5** tarjeta «Celulares» | `F4-PLAN-CORTO.md:130-138` |
| #10 | Qué pasa con F5 si no se guardan las llamadas a números sin lead. **No figura como aprobada**; la decisión 3 de F2, que es su contenido, sí está ratificada | `PROPUESTAS-DE-AJUSTE.md:17`, `REVISION-2026-10-02.md:13` |
| Otras | La #12 y la regla extra de la decisión 4: siguen sin confirmar | `CORRECCION-PLAN-CORTO.md:127` |

## Criterios propios de este análisis

- **Decisión:** tratar F4-e como la pantalla de F6. F6 se queda con el diccionario, el histórico, la salud y la conciliación.
  **Motivo:** así la misma pestaña no se construye dos veces.
- **Decisión:** recomendar que F5 se quede en F5.1 hasta medir cuántos casos reales hay.
  **Motivo:** lo decidido después de aprobar el plan deja a F5 casi sin casos.
- **Decisión:** proponer cualquier cambio al texto de una fase como propuesta de ajuste, nunca editando `PLAN.md`.
  **Motivo:** lo aprobado por Miguel no se reescribe.

## En una línea

- **F5:** casi se queda sin trabajo. Conviene medir primero y, si no hay casos, dejarla apagada.
- **F6:** F4-e ya la adelanta en parte. Le falta un diccionario de métricas y decidir cómo se ve el pasado si las
  pendientes se borran a los 30 días.
- **F7:** es sobre todo operación, y depende de cerrar F0 (hoy solo existe C1).

---

## F5 · Jev para identificación asistida

### 1. Qué dice el plan aprobado

- **Objetivo:** relacionar mejor el número con el lead cuando la regla exacta deja ambigüedad o datos incompletos
  (`PLAN.md:436`).
- **Reparto (§11.1):**
  - El código decide los casos exactos.
  - Jev (el modelo de TypeSafe) solo propone entre candidatos que ya existen, y la persona confirma.
  - Sin contexto suficiente, se abstiene.
  - Nunca corrige dígitos.
  - Los candidatos se buscan **antes** de Jev; no se recorre la cartera con IA (`PLAN.md:440-450`).
- **Contrato (§11.2):** todo en el servidor. Entrada: ids opacos y contexto mínimo. Salida: candidato, `ninguno` o
  `evidencia_insuficiente`, validada contra la lista, el ámbito y la vigencia (`PLAN.md:452-458`).
- **Tareas (15):**
  - F5.1.1–F5.1.3: banco y línea base.
  - F5.2.1–F5.2.3: evaluación fuera de línea.
  - F5.3.1–F5.3.3: modo sombra (Jev calcula sugerencias sin mostrarlas).
  - F5.4.1–F5.4.3: asistencia que cada analista activa.
  - F5.5.1–F5.5.3: decidir si se enciende (`PLAN.md:464-512`).
- **Puerta de salida:** mejora medida frente a la línea base reservada, sin degradar los exactos. Sin mejora, **F5 queda
  apagada y F6–F7 siguen** (`PLAN.md:516`). Se prepara con sintéticos desde F0 y se integra tras F4 (`PLAN.md:110, 114`).
- **Pendientes de §16 antes de F5:** asociación histórica acotada y revocable, y umbrales de Jev medidos con el banco
  (`PLAN.md:663-664`).

### 2. Qué cambió desde que se aprobó y cómo la afecta

- **La decisión 3 de F2 está ratificada (02/10): un número sin lead no se guarda.** La perilla `guardar_sin_identificar`
  está apagada (`20261001145242_crm_llamadas_celular_datos.sql:106, :574`).
  - F5 pierde el caso «sin coincidencia» y la fila «teléfono dentro de una nota»: esas llamadas ni existen en la base.
  - La #10 ya lo advertía («F5 se limita a las ambiguas o se aplaza»), pero no consta que Miguel la aprobara.
- **⏸ C3: cada celular reconoce solo los leads de la cartera de su dueño.**
  - Un candidato → identificada.
  - Dos o más → ambigua, y solo con leads suyos.
  - Un lead de otra cartera → como si no fuera lead (`CORRECCION-PLAN-CORTO.md:56-62`).
  - Además desaparece el conteo global `calidad.candidatos`.
  - **Sí, achica F5.** Su universo queda en números que comparten dos o más leads de la misma cartera (o del mismo
    equipo, si el dueño es supervisor).
- **F1 en producción ya resuelve la ambigüedad con la persona.**
  - Al colgar, la encuesta busca con la sesión del analista (`cartera_pagina_fn`, con RLS).
  - Si hay varios candidatos, elige la persona (`app/src/data/coincidencia-llamada.ts:6-7, 37-49`;
    `app/src/components/app/receptor-llamada.tsx:11, 189-207`).
- **⏸ F4-1: emparejar por el id de origen.**
  - Lo que el analista elija en la encuesta viaja con el id de la llamada y se enlaza exacto (`F4-PLAN-CORTO.md:55-67`).
  - Solo queda ambiguo lo que no se registró al colgar y aparece en la pestaña.
  - Allí, «Elegir el lead» ya muestra solo leads de su cartera (`F4-PLAN-CORTO.md:79`).
- **Retención:** las ambiguas sin resolver se borran a los 30 días (`20261001145242:534-539`). El modo sombra solo ve
  esa ventana.
- **#13 (clientes), aprobada para después:** puede aparecer un caso nuevo, el lead convertido y el cliente con el mismo
  número. (supuesto) Se resuelve con una regla en el plan corto de la #13, no con Jev.
- **Credenciales y tratamiento:**
  - La clave de TypeSafe se pegó en un chat el 20/09 y hay que rotarla (vault «Jev para auditar…»:74;
    `scripts/jev/README.md`). No consta que se haya rotado.
  - La retención y el tratamiento de datos de la cuenta siguen pendientes (vault «Gestion Diaria F4.1…»:42-45).
  - Las dos cosas bloquean F5.3 (F5.3.1) con datos reales.

### 3. Lo que ya existe y se reutiliza

| Pieza | Dónde | Uso en F5 |
| --- | --- | --- |
| Casos sintéticos D1–D4, ya marcados como semilla de F5.1.1 | `docs/gestion-diaria/piloto-telefonia/ejemplos-sinteticos.md:36-43, 66` | Banco inicial |
| Candidatos exactos con las dos formas canónicas | `20261001160219_crm_llamadas_celular_nucleo.sql:87-113` | Recuperar candidatos antes de Jev (F5.2.1) |
| Evaluación «como el dueño del celular» | `20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql:41-57` | La corrección la usa para limitar candidatos a la cartera |
| Asociar solo a un lead que tenga el número | `20261001160219:369-375` | Garantiza que nada adjudica «por parecido» |
| Método `propuesto_confirmado` reservado en la tabla; ninguna función lo escribe (lo comprobé buscándolo en todo el CRM) | `20261001145242:271-274, 613` | Marca de «sugerencia aceptada» en F5.4 sin tocar la tabla |
| Jev desde el servidor: Edge con la clave en secretos, el estado en un campo con nombre, cron con firma HMAC, cola con modelo, huella y error | `supabase/functions/crm-temperatura-lead/index.ts:6-45`; `20260921034748_crm_temperatura_lead.sql:1-40, 47, 188, 230, 357` | Molde del modo sombra. No verifiqué si la temperatura está aplicada en producción |
| Banco ciego, comparación de acuerdo y errores separados de los fallos del modelo | `scripts/gestion-diaria-typesafe/README.md` | Etiquetado humano y medición (F5.1–F5.2) |
| Cliente Jev y umbrales con su medición al lado | `scripts/jev/README.md` | Fijar la abstención antes de evaluar (F5.2.3) |
| «Elegir el lead» de la pestaña de F4 | `F4-PLAN-CORTO.md:76-80` | Dónde se mostraría la sugerencia (F5.4) |

### 4. Diseño propuesto (descripción, no código)

**Paso 0 · F5.1, sin código y sin datos reales**
- Ampliar el banco sintético con ambigüedad **dentro de una cartera**:
  - pareja que comparte celular;
  - el mismo lead duplicado;
  - lead convertido junto a uno activo.
- Separar familias de casos entre ajuste y evaluación reservada (F5.1.2).
- Definir dos líneas base (baseline: la regla contra la que se compara Jev):
  - **R0** = la regla exacta de hoy.
  - **R1** = la exacta más contexto que el código puede verificar: qué candidato tiene una tarea de llamada pendiente
    hoy, con cuál fue el último resultado del analista y la intención de llamada que guarda F1.
  - (supuesto) R1 resolverá casi todo sin Jev.
- **Medir el caso real:** contar cuántos números están en dos o más leads activos de la misma cartera.
  - Solo cifras: sin teléfonos ni nombres.
  - Lo corre Miguel en su terminal.

**Regla de corte**
- Si el caso real es raro, o R1 lo resuelve, F5 queda apagada, como el plan permite (`PLAN.md:516`).
- Entonces F5.2–F5.5 pasan a `NO APLICA`, con decisión y motivo (`PLAN.md:125`).

**Solo si el dato lo justifica (F5.2–F5.4)**
- **Núcleo (`private`):**
  - Candidatos de la cartera del dueño.
  - Hechos calculados por código: «figura como alternativo», «tiene tarea hoy», «asociación confirmada el…».
  - Siempre con ids opacos y nunca con dígitos.
- **Puerta de entrada:**
  - Una Edge con la clave en los secretos de Supabase, como la temperatura.
  - Una tabla de control de las consultas a Jev: la exige el estándar de 4 capas para toda llamada a terceros.
  - Una puerta `crm` DEFINER (corre con permisos del dueño; las tablas no dan acceso a la API) para leer la sugerencia.
  - Confirmar = asociar con el método `propuesto_confirmado`.
- **Modo sombra:**
  - Jev propone sobre las ambiguas sin mostrar nada.
  - La referencia es la elección posterior del analista (asociación manual).
  - Se miden acuerdo, abstención, costo y latencia.
- **Pantalla:** en «Elegir el lead», los candidatos salen ordenados y con sus hechos. Confirma la persona.
- **Requisitos:** OK de Miguel al SQL y revisión LEVEL 3, porque toca datos y un proveedor externo.

### 5. Decisiones que necesitaría Miguel

| Decisión | Recomendación | Alternativa y su costo |
| --- | --- | --- |
| ¿Sigue F5 entera? | **Hacer solo F5.1 y la medición del caso real**, y decidir con ese dato | F5 completa ahora: Edge, tabla de control, rotar la clave, tratamiento de datos y LEVEL 3, quizá para casi ningún caso |
| #10: universo de F5 | **Solo las ambiguas dentro de la cartera del dueño** (los números sin lead siguen sin guardarse) | Encender `guardar_sin_identificar` para F5: guarda 30 días teléfonos de personas ajenas al CRM y reabre la pista que cierra la corrección (`CORRECCION-PLAN-CORTO.md:65-68`) |
| Teléfono escrito en una nota (§11.1) | **Fuera del piloto** | Buscar candidatos también en notas: cambia el núcleo, que hoy exige que el lead tenga el número (`20261001160219:372-375`), y lee texto libre con datos sensibles |
| Medición del caso real | **Conteo agregado en producción, corrido por Miguel**, solo cifras | Decidir sin el dato |
| Historial confirmado (F5.4.2, §16) | **No construirlo hasta F5.5** | Construirlo ya: tabla nueva con vencimiento y revocación, sin uso probado |

Requisito previo, no decisión: rotar la clave de TypeSafe y cerrar retención y tratamiento antes de usar datos reales.

### 6. Dependencias y orden

- **Se puede adelantar ya:** F5.1.1 y F5.1.2 en documento (banco ampliado y reparto ajuste/reserva) y la definición de
  R0 y R1. No toca código ni datos.
- ⏸ **C3:** fija el universo de F5 (solo la cartera del dueño).
- ⏸ **#10:** si F5 se limita a las ambiguas o se aplaza.
- ⏸ **F4-1 y F4-2:** si la encuesta enlaza por id, a F5 solo le queda la pestaña.
- **F5.2 en adelante:** después de F4 publicada (`PLAN.md:110`). F5.3 además exige credenciales y tratamiento resueltos.
- F5 no bloquea F6 ni F7 (`PLAN.md:114, 516`).

### 7. Riesgos y límites

- **Pocos casos:** con una base pequeña, la precisión no se puede medir con confianza. El plan exige informar la muestra
  y la incertidumbre (`PLAN.md:514`).
- **La referencia del modo sombra es humana:** la elección del analista también puede estar equivocada.
- **Jev ya mostró su límite:** juzga mal lo que depende de reglas del negocio que no están en el texto (AUC de 0,47 a
  0,61, vault «Jev para auditar…»). Lo que distingue a dos familiares rara vez está escrito.
- **Ventana corta:** las ambiguas se borran a los 30 días.
- **Datos a un tercero:** mandar nombres a TypeSafe exige el tratamiento autorizado (§15, `PLAN.md:649, 652`).
- **No reutilizar el 19/20:** ese piloto midió el juicio nota/resultado, no la identificación (`PLAN.md:520`).

### 8. En llano

F5 era para que una IA ayudara a saber de qué lead es una llamada cuando el número solo no alcanza. Con lo que se decidió
después, casi no quedan casos dudosos: no se guardan números desconocidos, cada celular reconoce solo los leads de su
dueño y la encuesta que se abre al colgar ya deja elegir. Lo sensato es preparar ejemplos de prueba y contar cuántos
casos reales hay. Si son pocos, F5 se queda apagada y no afecta a nada más.

---

## F6 · Gerencia y calidad de evidencia

### 1. Qué dice el plan aprobado

- **Objetivo:** cifras interpretables **sin alterar las métricas comerciales existentes** (`PLAN.md:524`).
- **Tareas (12):**
  - **F6.1** definir métricas: detectadas, elegibles, enlazadas y pendientes; denominadores y exclusiones; no sumar eventos
    y gestiones.
  - **F6.2** medir tiempo y salud: días de Lima de inicio a fin, actor histórico, retrasos, cola, antigüedad de la señal y
    cobertura insuficiente separada de «cero llamadas».
  - **F6.3** reporte e histórico: lecturas y pantalla con diccionario; ventana limitada o agregados minimizados; eventos
    tardíos.
  - **F6.4** conciliar y aceptar (`PLAN.md:528-566`).
- **Aceptación:** explicar el lunes recibido el martes, el cambio de asignación, deshacer, el equipo sin sincronizar y el
  efecto de la retención. Negocio valida las definiciones. Depende de F4 y funciona con Jev apagado (`PLAN.md:568`).
- **§16:** histórico de gerencia con «ventana limitada o agregado minimizado», a decidir antes de F6 (`PLAN.md:665`).
- **§15:** métricas agregadas con su retención justificada (`PLAN.md:650`).

### 2. Qué cambió desde que se aprobó y cómo la afecta

- **⏸ F4-4: F4 propone adelantar la vista de gerencia y la del supervisor (F4-e).**
  - Lleva una puerta agregada con «hechas, con resultado, sin resultado y salud», que F4 llama «la métrica de F6,
    adelantada» (`F4-PLAN-CORTO.md:99-105, 124-125, 157-158`).
  - Si Miguel la elige, la pantalla de F6.3.1 se hace en F4.
  - Riesgo: que F4-e fije las definiciones por defecto. **Por eso F6.1 conviene escribirse antes de F4-e.**
- **#15, aprobada: entrantes aparte.**
  - Nunca se suman a «llamadas hechas» ni al cumplimiento.
  - Cifras: recibidas por analista y periodo; atendidas frente a perdidas; perdidas devueltas y en cuánto tiempo;
    resultado tras una entrante. Más una idea para el potencial (`PROPUESTAS-DE-AJUSTE.md:23`).
  - ⏸ C2 y #14: hoy nada produce `requiere_devolucion` (fallo 3, `REVISION-2026-10-02.md:25`), y la macro de entrantes
    está diseñada pero sin probar (`macrodroid.md:169-182`).
- **Retención frente al histórico.**
  - Hoy se borran a los 30 días las descartadas, las ambiguas sin resolver y las sin identificar
    (`20261001145242:527-546`).
  - ⏸ C4 añade las identificadas sin resultado.
  - **Las registradas no caducan:** no hay regla para ellas en la purga (`20261001145242:510-551`). El §15 pide que no
    queden «indefinidas por omisión» (`PLAN.md:647`).
  - Consecuencia: un histórico de más de 30 días calculado sobre los eventos se vería mejor de lo que fue. Las «sin
    resultado» y las descartadas desaparecen y quedan solo las que tienen resultado.
- **⏸ C3: lo que no es de la cartera del dueño no se guarda.**
  - «Detectadas» significa llamadas a leads de su cartera, no todas las llamadas del celular.
  - F6 no puede, ni debe, mostrar cuántas llamadas no comerciales hace el analista.
- **Decisión 7 de F2, ratificada.** Para las métricas se conserva quién marcó. La llamada la trabaja quien tiene el lead
  hoy (`F2-PLAN-CORTO.md:71`). La cifra por analista usa `analista_id`; la bandeja sigue al dueño actual.
- **Latido (aviso periódico del celular que dice que sigue vivo).** Ratificado cada 6 h y diseñado con Pro, sin armar ni
  probar (`macrodroid.md:175, 264-294`). Sin él no hay «sin señal» (F4, hallazgo 4: `F4-PLAN-CORTO.md:128`).
- ⏸ **C1, opción B:** antes de F4, las llamadas se acumulan como «pide resultado» (`CORRECCION-PLAN-CORTO.md:85-86`).
  F6 tendría que excluir ese periodo o esperar la limpieza.

### 3. Lo que ya existe y se reutiliza

| Pieza | Dónde | Uso en F6 |
| --- | --- | --- |
| Una sola definición de llamada, contacto y tasa, sellada por md5 | `20260920041500_crm_gestion_diaria_analista.sql:27-33, 795-800` | **No se toca** (F6.1.3). Lo del celular va al lado, nunca sumado |
| Fuente de las llamadas de Gestión Diaria: actividades por `creado_por` y hora de Lima | `20260924201358_crm_gestion_diaria_pulso_habitos.sql:9-23` | Conciliar: cada llamada con resultado ya cuenta ahí una vez |
| Días de Lima de inicio a fin, límite de 365 días, periodos de 7, 14 y 30 días | `20260924201358:193-241, 253, 365-377` | El mismo corte para F6.2.1 y el histórico |
| Reparto analista → supervisor con el organigrama actual | `20260924201358:124-145, 314, 449` | Agrupar por equipo como el resto de gerencia |
| Autorización de gerencia o lector global | `20260924201358:112-120` | Molde de la puerta agregada |
| Vista del supervisor (su equipo; gerencia, el que elija) | `20260921040335_crm_gestion_diaria_equipo_vista.sql:191-200` | Ámbito del bloque «Su celular» |
| Evidencia de cada llamada: horas del celular y del servidor, dirección, estado técnico, analista, asignación, identificación y atención | `20261001145242:233-304` | Datos de F6.1 y F6.2 sin cambiar la tabla |
| Enlace evento ↔ actividad, uno a uno; «deshecho» se calcula al leer | `20261001145242:403-413`; `20261001160219:684-697` | «Con resultado» y «efectos anulados» |
| Salud actual por celular: último envío, último latido, versión de la macro, cola | `20261001212258_crm_llamadas_celular_ingesta.sql:81-102, 269-291, 362-374` | F6.2.2, solo el estado de ahora |
| Pestañas de gerencia y su capa de datos con contrato validado | `screens/gestion-diaria/gerencia.tsx:43, 114-115`; `data/gestion-diaria-pulso-api.ts:7-29`; `data/gestion-diaria-pulso-queries.ts:24, 53-64` | Pantalla y cliente de la puerta nueva |
| «Mi equipo hoy» | `screens/gestion-diaria/supervisor.tsx:58, 261-319` | Vista del supervisor |
| Pie de lectura en las gráficas («qué significa cada serie») | `screens/hoy/graficas-gerencia.tsx:161-162` | El diccionario dentro de la pantalla |

### 4. Diseño propuesto (descripción, no código)

**F6.1 · Diccionario de métricas (documento, sin código)**

| Cifra | Definición propuesta | Ojo |
| --- | --- | --- |
| Llamadas del celular | Eventos guardados (identificados y ambiguos), por quién marcó y por día de Lima de la llamada | No incluye números sin lead ni leads ajenos (decisión 3, C3) |
| Pedían resultado | Identificadas que eran elegibles al llegar | Punto abierto: lead cerrado después |
| Con resultado | Tienen enlace a un resultado no deshecho | Ya están dentro de «llamadas» de Gestión Diaria: **nunca se suman** |
| Sin resultado | Pedían resultado y no tienen enlace ni descarte | Nombre ya elegido en F4: no es «sin registro» (`F4-PLAN-CORTO.md:25-26`) |
| Por revisar | Ambiguas o no elegibles | — |
| Descartadas | Por motivo | Se borran a los 30 días |
| Resultado deshecho | El enlace apunta a una actividad con `deshecho_en` y sin corregir | — |
| Retraso de entrega | `recibido_en` − `ocurrio_en` (mediana y p90) | Mide el celular y la red, no al analista |
| Retraso de registro | Hora del resultado − `ocurrio_en` | Dato nuevo previsto (`F2-PLAN-CORTO.md:119`) |
| Entrantes (#15) | Recibidas, atendidas o perdidas, devueltas y tiempo de devolución, resultado tras una entrante | ⏸ #14. Nunca en «llamadas hechas» |
| Salud | Último latido, cola y versión de la macro | Técnica: no mide trabajo |

Puntos abiertos del diccionario, para Miguel:
- Leads borrados.
- Lead cerrado después de la llamada.
- Reasignación.
- Día de la llamada frente al día del resultado.
- Qué hacer con `envios_hoy`.

**F6.2 · Tiempo y salud**
- **Día de la llamada:** se agrupa por `ocurrio_en`. Si falta, por `recibido_en` (decisión 5 de F2). Si el reloj del
  celular va adelantado (marca de `calidad`), también por `recibido_en`.
- **Cobertura:** la de hoy sale del latido. Los días pasados dicen «sin dato de cobertura»; nunca «0 llamadas».

**F6.3 · Lecturas y pantalla**
- **Puerta:** una puerta agregada en `crm`, DEFINER, porque las tablas de llamadas no dan permisos a la API
  (`20261001145242:653-665`). Llama a un núcleo en `private`.
- **Ámbito:** gerencia ve todo; el supervisor, su equipo; el analista, lo suyo.
- **Contenido:** solo cifras, sin teléfonos.
- **Cálculo:** al vuelo dentro de la ventana, como hacen pulso y hábitos. Así un aviso tardío corrige su día sin duplicar
  nada (F6.3.3).
- **Si F4-e existe:** se amplía su puerta en vez de crear otra (supuesto: depende de cómo se construya F4-e).
- **Pantalla:** la pestaña de F4-e, o la de F6. Lleva un selector de 7, 14 o 30 días como «Hábitos», limitado a la
  ventana, y el diccionario como pie de lectura.

**F6.4 · Conciliación**
- Tomar una muestra de un día en C1 y cruzar: registro del teléfono ↔ eventos ↔ enlaces ↔ actividades.
- Probar los escenarios del plan (lunes recibido el martes, reasignación, deshacer, sin señal, purga) en el banco y con
  E2E en Docker local.

**Capas:** pantalla → puerta `crm` → núcleo `private` → tablas. Ninguna lectura directa. No se tocan las funciones
selladas de Gestión Diaria.

### 5. Decisiones que necesitaría Miguel

| Decisión | Recomendación | Alternativa y su costo |
| --- | --- | --- |
| Dónde vive la pantalla (es F4-4) | **En F4-e, con el diccionario de F6.1 aprobado antes** | Todo en F6: gerencia no ve las llamadas sin resultado hasta entonces |
| Ventana histórica | **30 días calculados al vuelo**, igual que la retención, sin tabla nueva, mientras dure el piloto | Agregado diario minimizado (solo cifras, sin teléfonos ni leads) guardado antes de la purga: tabla y tarea nuevas, pero permite comparar meses |
| Retención de las registradas (hoy sin plazo) | **Un plazo explícito igual a la ventana.** El resultado comercial sigue en `crm.actividades`. Efecto: el enlace se borra con el evento (`20261001145242:405`), así que la marca «Celular» desaparece pasado el plazo | Guardarlas más tiempo para auditar enlaces: el teléfono queda guardado más tiempo |
| Puntos abiertos del diccionario | **Contar las llamadas a leads borrados** como hecho, sin detalle · **una llamada cuyo lead se cerró no cuenta como «sin resultado»** · por analista, **quién marcó** · día de la llamada, explicado | Definir sobre la marcha: cifras que cambian de significado |
| Cobertura de días pasados | **Solo la de hoy (latido); el pasado dice «sin dato»** | Guardar un historial diario de salud: tabla nueva. ¿O sirven las recepciones de la corrección, si guardan la hora? Pregunta abierta: su conteo incluye llamadas personales |
| Idea de la #15: entrantes que suben el potencial | **Fuera de F6** (F6 promete no alterar las métricas comerciales) | Incluirla: toca el potencial (`20260930235917`) y necesita su propio plan |
| Cifra «encuesta abierta al colgar» por celular (F4) | **Que F4-a guarde por qué vía se hizo el enlace**: hoy el enlace no lo guarda (`20261001145242:403-413`) | No medirla: no se encuentra el celular que falla (`F4-PLAN-CORTO.md:82-85`) |

### 6. Dependencias y orden

- **Se puede adelantar ya:** el borrador del diccionario F6.1. Conviene tenerlo antes de F4-e.
- ⏸ **F4-4:** decide si la pantalla (F6.3.1) se hace en F4-e o en F6.
- ⏸ **C4, más la retención de las registradas:** fijan la ventana.
- ⏸ **C1:** con la opción B, hay que excluir el periodo anterior a F4.
- ⏸ **C2 y #14, más la macro de §3d con Pro:** las entrantes de la #15.
- ⏸ **F4-1 y F4-2:** «con resultado» depende de cómo enlaza la v5.
- **Latido armado y probado** (B6–B7, `macrodroid.md:315-316`) antes de F6.2.
- **Orden:** F6.1 → (F4-e) → F6.2 → F6.3 → F6.4. F6 no espera a F5.

### 7. Riesgos y límites

- **Dos relojes.**
  - Gestión Diaria cuenta por la hora del resultado (la del servidor); F6, por la hora de la llamada (la del celular).
  - Una llamada de las 23:58 registrada a las 00:03 cae en días distintos.
  - El diccionario lo explica y F6.4 lo prueba.
- **La atención «efectiva» depende de quién mira.** Hoy se calcula al leer (`20261001160219:146-160`). Una cifra agregada
  necesita una regla que no dependa de eso.
- **Pocas llamadas:** con 2–3 celulares, un porcentaje engaña. Mostrar siempre el conteo junto a la tasa.
- **`envios_hoy` no mide trabajo.** Lo ven supervisión y gerencia, y cuenta también las llamadas personales y los latidos
  (`20261001212258:141-180, 281-282`). Solo sirve como salud.
- **Sin eventos no prueba inactividad** (`PLAN.md:36`).
- **Sellos de Gestión Diaria:** tocar sus funciones obliga a resellarlas (`20260930150852_crm_gestion_diaria_solo_operativos.sql:1-27`).
  El diseño lo evita.

### 8. En llano

F6 es el tablero de gerencia de las llamadas del celular. Dice cuántas hubo, cuántas tienen resultado y cuántas no, y si
cada celular sigue enviando. Una parte ya se adelantaría en F4. Falta decidir qué significa exactamente cada cifra y
cuánto tiempo hacia atrás se puede mirar, porque las llamadas pendientes se borran a los 30 días. Las llamadas que hace
el propio lead se cuentan aparte y nunca suben las cifras del analista.

---

## F7 · Despliegue gradual y operación

### 1. Qué dice el plan aprobado

- **Tareas (12):**
  - **F7.1 Aceptar el piloto:**
    - Validación integral en los equipos admitidos.
    - Revisar las evidencias de F0–F6 y registrar la decisión sobre Jev.
    - Responsables y criterios para parar o ampliar.
  - **F7.2 Soporte y reversa:**
    - Guía de permisos, cola, clave perdida, cambio de equipo y baja.
    - Reasignación, números compartidos y corrección de asociaciones.
    - Apagado independiente de captura, apertura y Jev.
  - **F7.3 Publicar por cohortes (grupos pequeños de celulares que se encienden primero):**
    - Gates y release humano con el commit local igual a `avancecorp/main`.
    - Publicar solo el artefacto verificado.
    - Cohortes pequeñas.
  - **F7.4 Cerrar y mantener:**
    - Fechas, aceptación e incidencias.
    - Diccionario y operación de la retención y la salud.
    - Plan, tablero y vault al día (`PLAN.md:574-612`).
- **Reversa:** detener la captura o la apertura por equipo, conservar la evidencia y apagar Jev. `DROP` solo en pruebas
  vacías (`PLAN.md:614`).
- **Depende de** F4 y F6, más una decisión explícita sobre F5 (`PLAN.md:112`).

### 2. Qué cambió desde que se aprobó y cómo la afecta

- **MacroDroid Pro (Jhosep, 03/10):** S/19 por celular, pago único ligado a la cuenta de Google del teléfono
  (`macrodroid.md:74, 171`).
  - Cada celular pasa de 3 a 6 macros (`macrodroid.md:296-304`): más pasos manuales por equipo.
  - (supuesto) Cambiar de cuenta de Google o de celular puede exigir otra licencia.
- **Latido cada 6 h y al vaciar la cola:** diseñado, sin armar ni probar (`macrodroid.md:264-294`). Será la herramienta
  de soporte: «¿este celular habla?» y «¿cuántos avisos tiene en cola?».
- **#14 (entrantes) y #13 (clientes):** aprobadas como pasos propios. Las cohortes también crecen por alcance, no solo
  por número de celulares.
- **Siguen abiertas las seis decisiones de la corrección y las cinco de F4.** F7 no empieza hasta que ambas estén
  publicadas.
- **Solo existe C1** (`compatibilidad.md`: las filas C2 y C3 están vacías).
  - F0 va 1/12 y la línea base de cinco días (F0.2) no empezó (`PLAN.md:158-166`).
  - Hoy, «equipos admitidos» significa solo un Samsung A16 con Android 16, que está fuera del rango 12–15 que cubre la
    documentación consultada.
- **La guía de publicación de F2+F3 ya trae** el alta por SQL, el cambio de macro y la reversa
  (`PUBLICAR-F2-F3.md:121-155`). Es la base de F7.2 y F7.3.

### 3. Lo que ya existe y se reutiliza

| Pieza | Dónde | Uso en F7 |
| --- | --- | --- |
| Guía de la macro: pasos, trampas y pruebas A1–A7 (PASS) y B1–B9 (sin probar) | `docs/gestion-diaria/piloto-telefonia/macrodroid.md:63-167, 169-318` | Lista de comprobación por celular en cada cohorte |
| Matriz de compatibilidad y registro de incidencias | `compatibilidad.md`; `REGISTRO.md` §6 | F7.1.1 y F7.4.1 |
| Asignar, rotar y cerrar celulares: solo gerencia; la clave se muestra una vez | `20261001160219:510-609`; `PUBLICAR-F2-F3.md:121-133` | La cohorte son los celulares asignados: no hace falta bandera nueva |
| La ingesta rechaza un celular cerrado o un analista de baja | `20261001212258:128-139` | La baja del analista no pide pasos extra en el servidor |
| Salud por celular (supervisión y gerencia) | `20261001212258:269-291, 362-374` | Vigilar cada cohorte (F7.3.3) |
| Reversas que conservan los hechos; la total se niega si hay filas | `20261001145242:50-52`; `PUBLICAR-F2-F3.md:146-155` | F7.2.3 y la regla de no borrar datos |
| Cortar la apertura sin tocar el servidor: quitar «Abrir sitio web» o no montar el receptor | `macrodroid.md:61` | Apagado independiente de la apertura |
| Retención programada (cron diario a las 06:23 UTC) | `20261001145242:554-568` | F7.4.2: comprobar que corre |
| Release y gates: preflight del CRM, `/release-crm`, E2E solo en Docker local | `CLAUDE.md` de la raíz; `CRM-Avance-Corp/CLAUDE.md` | F7.3.1 y F7.3.2 |
| Piloto por persona, instalado apagado | `20260913215240_crm_f8_piloto_controlado.sql:1-4` | Solo si Miguel quisiera encender por persona (no parece necesario) |

### 4. Diseño propuesto (descripción, no código)

**F7.1 · Aceptar el piloto**
- **Entrada:**
  - F0 cerrado con al menos dos celulares y la matriz llena.
  - Finalidad comunicada a cada analista (F0.1.3).
  - F4 y F6 publicadas.
  - Decisión sobre Jev registrada. (supuesto) Si queda apagado, «apagar Jev» de F7.2.3 pasa a `NO APLICA`.
- **Responsables:**
  - Soporte: Jhosep, hoy.
  - Operador de claves: alguien de gerencia, porque es el único rol que asigna, rota y cierra
    (`20261001160219:520-522, 553-555, 588-590`).
  - Release: Miguel.
- **Criterios para parar o ampliar, por tipo** (los umbrales se fijan con los datos de F0.2, no aquí):
  - una llamada perdida o duplicada sin explicar frente al registro del teléfono;
  - la encuesta no se abre al colgar (la cifra por celular de F4);
  - la cola no baja;
  - hay avisos en `errores_llamadas`;
  - falta el latido, por ejemplo, durante dos ciclos (supuesto).

**F7.2 · Guía de soporte, en llano y sin secretos**
- **Permisos y ajustes del celular:** los de F0.1.3 (`PLAN.md:154`).
- **Cola:** ver `cola_llamadas` y `errores_llamadas`, y vaciar la cola antes de pasar a producción (`PUBLICAR-F2-F3.md:137-138`).
- **Clave perdida:** gerencia la rota y la nueva se lleva al celular por un canal privado, nunca por chat (punto 17).
- **Cambio de celular o de analista, en este orden:**
  1. Comprobar que el latido diga `en_cola = 0`, o vaciar la cola.
  2. Cerrar la asignación con su motivo.
  3. Asignar de nuevo.
  4. Armar las macros y la licencia Pro.
  5. Repetir A1, A3 y B1–B9.

  Por qué el paso 1, verificado en el código: la llamada se atribuye a la asignación de la clave con la que **llega**
  (`20261001160219:248-253, 320`). La ingesta no compara `ocurrio_en` con el inicio de la asignación. Una cola vieja
  enviada con la clave nueva quedaría a nombre del analista nuevo.
- **Baja del analista:** cerrar la asignación con el motivo `baja_analista`. La ingesta ya rechaza al inactivo.
- **Revocar la clave sin tocar la macro** deja los avisos reintentando cada 5 minutos para siempre: un 401 no los saca
  de la cola (`macrodroid.md:71, 95`). La guía dice apagar también la macro.
- **El analista no ve la salud de su propio celular** (solo supervisión y gerencia, `20261001212258:370`). El soporte la
  mira por él.
- **Reasignación, números compartidos y corrección:** se aplica lo ya decidido.
  - La llamada la trabaja quien tiene el lead hoy (decisión 7 de F2).
  - El lead solo se corrige mientras la llamada está por atender (`20261001145242:351-363`).
  - Revocar asociaciones confirmadas solo existe si F5 construye el historial.

**F7.2.3 · Apagados independientes, probados en C1**
- **Captura de un celular:** cerrar su asignación (efecto inmediato) y apagar la macro.
- **Apertura:** quitar «Abrir sitio web» de la macro. Para todos a la vez: publicar el CRM sin el receptor, lo que exige
  un release.
- **Todo el servicio:** retirar la Edge. Afecta a todos los celulares.
- **Jev:** `NO APLICA` si queda apagado.

**F7.3 · Cohortes**
- **Cohorte 0:** C1 (Jhosep) durante unos días, con todo publicado.
- **Cohorte 1:** uno o dos analistas más con celular corporativo, lo que pide el piloto.
- **Después:** las entrantes (#14) en la misma cohorte. Más tarde, los clientes (#13).
- **En cada cohorte:**
  - release según el `CLAUDE.md` de la raíz (`main` = producción, con preflight);
  - migraciones con la guía de Miguel;
  - gates: `test-rls` con `CRM_RLS_EXIGE_LLAMADAS=1` y E2E en Docker local.

**F7.4 · Cierre**
- Fechas reales, incidencias y diccionario de F6 entregado.
- Retención y latido funcionando: Miguel consulta el cron.
- Plan, tablero y vault al día con evidencia.
- Nunca borrar datos como reversa.

### 5. Decisiones que necesitaría Miguel

| Decisión | Recomendación | Alternativa y su costo |
| --- | --- | --- |
| Primera cohorte y criterios | **C1 y luego 1–2 analistas.** Criterios por tipo ahora; umbrales con los datos de F0.2 | Todos los celulares a la vez: un fallo no se puede aislar |
| Interruptor por celular | **Lo que ya existe:** cerrar la asignación y apagar la macro | Una perilla de pausa en el servidor que no cambie la clave: cambio de esquema |
| Licencias de MacroDroid Pro | **Comprarlas con la cuenta de Google corporativa de cada celular** | Con la cuenta personal del analista: la licencia se va con la persona |
| Operador de claves | **Una persona de gerencia nombrada** | Abrir asignar, rotar y cerrar a supervisión: cambio de permisos (LEVEL 3) |
| Traspaso de un celular con cola | **Regla de soporte** (cola en 0 antes de reasignar). Opcional: que la ingesta marque en `calidad` una llamada anterior al inicio de la asignación | No hacer nada: llamadas del analista anterior quedan a nombre del nuevo |
| Pestaña «Llamadas del celular» para quien no tiene celular | **Ocultarla** (necesita una lectura pequeña) | Mostrarla vacía: confunde a los analistas sin celular |
| Jev | **Registrar la decisión de F5** (probablemente apagado) | — |

### 6. Dependencias y orden

- **Se puede adelantar ya (documentos):**
  - El borrador de la guía de soporte (F7.2.1–F7.2.2). Casi todo existe ya, repartido entre `macrodroid.md` y
    `PUBLICAR-F2-F3.md`.
  - Los criterios de F7.1.3 por tipo.
- **F0 cerrado:** más celulares, finalidad comunicada y línea base. Depende de personas, no de Miguel.
- ⏸ **C1–C6:** F2 y F3 corregidas tienen que estar publicadas.
- ⏸ **F4-1…F4-5.** Con F4-5 sin tarjeta «Celulares», cada alta pasa por la terminal de Miguel: es un cuello de botella
  para ampliar cohortes.
- **F6 publicada y decisión sobre F5.**
- **MacroDroid Pro comprado en cada celular** y §3d probado (B1–B9).

### 7. Riesgos y límites

- **Configuración manual por celular:** 6 macros, la clave y la URL. Un error en un celular no se ve hasta que falta una
  llamada, así que las pruebas A y B por celular son obligatorias.
- **Marca y versión de Android:** solo hay evidencia de un Samsung con Android 16. Cada modelo nuevo puede portarse
  distinto con la batería o al abrir enlaces.
- **Límite de envíos:** 30 por minuto y 600 al día. Es un dato de la política, pero no hay puerta para cambiarlo
  (`20261001212258:42`): hace falta SQL.
- **Cuello de botella:** solo gerencia asigna, rota y cierra.
- **Licencia Pro:** ligada a una cuenta de Google.
- **Atribución tras traspasar un celular:** ver F7.2.

### 8. En llano

F7 es encender esto de verdad, poco a poco: primero el celular de Jhosep, después uno o dos analistas, y solo si todo va
bien, el resto. Antes hacen falta más celulares de prueba y una guía de soporte para cuando se pierde la clave, cambia el
celular o se va un analista. También hay que probar que cada parte se puede apagar por separado. La compra de MacroDroid
Pro por celular ya está decidida.

---

## Resumen

| Fase | Se puede adelantar ya | Depende de | Decisiones para Miguel |
| --- | --- | --- | --- |
| F5 | F5.1.1–F5.1.2 en documento: banco sintético ampliado con ambigüedad dentro de una cartera, reparto ajuste/reserva y reglas base R0 y R1 | ⏸ C3 · ⏸ #10 · ⏸ F4-1/F4-2 · F4 publicada (F5.2+) · rotar la clave de TypeSafe y cerrar el tratamiento (F5.3) | Seguir o parar tras medir · universo (#10) · teléfono en notas · medición real en producción · historial confirmado |
| F6 | Borrador del diccionario F6.1, **antes de F4-e** | ⏸ F4-4 · ⏸ C4 y retención de las registradas · ⏸ C1 · ⏸ C2/#14 y macro §3d · ⏸ F4-1/F4-2 · latido probado | Pantalla en F4-e · ventana de 30 días · plazo para las registradas · puntos abiertos del diccionario · cobertura de días pasados · potencial (#15) · vía del enlace |
| F7 | Guía de soporte (F7.2.1–F7.2.2) y criterios por tipo (F7.1.3), en documento | F0 cerrado · ⏸ C1–C6 publicadas · ⏸ F4-1…F4-5 · F6 · decisión de F5 · Pro y §3d probados | Primera cohorte · interruptor · licencias Pro · operador de claves · traspaso con cola · pestaña sin celular |

## Hallazgos colaterales (fuera de lo pedido)

1. `envios_hoy`, que ven supervisión y gerencia, cuenta las llamadas personales y los latidos
   (`20261001212258:141-180, 281-282`).
2. Una cola enviada después de traspasar el celular queda a nombre del analista nuevo (`20261001160219:248-253, 320`).
3. Las llamadas registradas no tienen plazo de retención (`20261001145242:510-551`), aunque §15 lo pide (`PLAN.md:647`).
4. `propuesto_confirmado` está reservado en la tabla y nadie lo escribe (`20261001145242:274`).
5. El enlace no guarda por qué vía se hizo, y la cifra «encuesta al colgar» de F4 lo necesita (`20261001145242:403-413`).
