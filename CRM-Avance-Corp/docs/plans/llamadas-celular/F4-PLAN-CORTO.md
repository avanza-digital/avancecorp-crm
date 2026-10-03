# F4 · Bandeja y registro conciliado — plan corto (borrador para el OK de Miguel)

Escrito el 03/10/2026; puesto al día la tarde del 03/10 con el encaje real en Gestión Diaria. **Solo análisis: sin
código ni SQL.** Depende de F2 y F3 **corregidas** (revisión del PR #170; plan de la corrección en el PR #171) y
aplicadas. Las tareas son las del plan aprobado (`PLAN.md` §10, F4.1–F4.4); aquí se dice cómo hacerlas con lo que ya
existe y qué decide Miguel.

## En una línea

Que cada llamada que avisa el celular quede **registrada y enlazada a su resultado**, sin duplicar gestiones. Si el
analista no la registró, la ve en una pestaña nueva de su Gestión Diaria y la completa desde el celular o el PC.

## Principio: se adapta la Gestión Diaria que ya existe; no se rediseña

Gestión Diaria ya está en producción y funciona. F4 no cambia su forma: **añade una pestaña o un bloque donde hace
falta**, con los mismos componentes y estilos.

| Rol | Lo que ya existe y se queda igual | Lo único que se añade |
| --- | --- | --- |
| Analista | «¿A quién llamo ahora?»: el panel «Ahora», «Tu día en cifras» y la tarjeta «Tu cola y tu actividad» con «Cola de hoy», «Mi actividad» y «Mi seguimiento» | Una pestaña **«Llamadas del celular · N»** en esa tarjeta. La encuesta de siempre se abre en «Ahora», como ya hace F1, con una línea: «Quedará unida a tu llamada del celular de las 10:42». En «¿Qué hice hoy?», una marca **«Celular C1»** en las gestiones que vinieron del celular |
| Supervisor | «Mi equipo hoy»: tabla por analista, panel del analista, cortes y «Registro del equipo» | Un botón «Llamadas del celular» y, en el panel del analista, un bloque «Su celular». Sin prototipo todavía |
| Gerencia | «Toda la operación hoy», con «Actividad del día» y «Hábitos del equipo» | Una tercera pestaña **«Llamadas del celular»** con la misma forma: tabla por equipo y panel con «Necesitan atención». En el panel de «Actividad del día», un aviso que lleva a ella |
| Gerencia (administración) | Configuración, una tarjeta por vista | La tarjeta **«Celulares»**: asignar, rotar, cerrar y ver la salud |

Nombre de la cifra nueva: **«sin resultado»** (llamadas que nadie registró). «Sin registro» ya existe en gerencia y
significa otra cosa: analistas sin ninguna gestión en el día.

## El problema que resuelve el diseño: la encuesta llega ANTES que el aviso

Probado en C1 el 02/10 (`REGISTRO.md` §5e): al colgar, la encuesta de F1 se abre al instante, y el aviso del celular
llega unos 11 segundos después (o horas después, sin señal). El analista suele guardar el resultado **antes** de que
exista la llamada en el CRM. Hoy ese resultado no sabe de qué llamada es. Emparejarlos por la hora («el resultado de
las 10:43 es de la llamada de las 10:42») está prohibido por el plan (F4.2.4: «nunca decidir solo por ±10 minutos»):
con dos llamadas seguidas al mismo lead se equivocaría.

## Lo que ya existe y se reutiliza (no se rehace)

| Pieza | Dónde | Uso en F4 |
| --- | --- | --- |
| Puertas de la bandeja, detalle, asociar, enlazar y descartar | F2-c `20261001160219`, F3-a `20261001212258` (`crm.llamadas_celular_bandeja_fn` paginada, `crm.llamada_celular_detalle_fn`, `crm.asociar_llamada_celular`, `crm.enlazar_llamada_celular`, `crm.descartar_llamada_celular`) | La pestaña las consume tal cual, con los cambios de la corrección (PR #171); el ámbito lo decide el servidor |
| Puertas de celulares | `crm.asignar_celular`, `crm.rotar_credencial_celular`, `crm.cerrar_asignacion_celular`, `crm.celulares_salud_fn`, `crm.celulares_asignaciones_fn` | Tarjeta «Celulares» de gerencia (F4.3.2) |
| Gestión Diaria del analista | `screens/gestion-diaria/analista.tsx` (pestañas de «Tu cola y tu actividad») | Se conserva entera; una pestaña más |
| Panel «Ahora» y encuesta «Registrar resultado» | `analista.tsx` (`PanelAhora`, prop `registro`) y `components/gestion-diaria/registrar-resultado.tsx` | La misma encuesta en el mismo sitio; solo recibe el contexto de la llamada |
| «¿Qué hice hoy?» | `components/gestion-diaria/registro-actividad.tsx` (versión `compacto`) | La marca «Celular» en cada gestión enlazada (hallazgo 3) |
| «Toda la operación hoy» | `screens/gestion-diaria/gerencia.tsx` (`PESTANAS`) | Una pestaña más |
| «Mi equipo hoy» | `screens/gestion-diaria/supervisor.tsx` | Botón y bloque «Su celular» |
| Confirmación real del resultado | `lib/store.tsx` → `registrarLlamada(...).confirmacion` devuelve el `actividad_id` que confirmó el servidor | Base de F4.2.1 |
| Comandos con recibo («Guardados por confirmar») | `data/sla-operacion-comandos.ts` | El registro con enlace usa el mismo mecanismo: un reintento no duplica |
| Deshacer | `store.deshacerResultadoLlamada` + regla del servidor (decisión 4 de F2: el enlace se mueve al resultado corregido) | F4.3.3 ya está resuelto en el servidor; la pantalla solo lo muestra |
| Receptor de F1 y cola de intenciones por pestaña | `components/app/receptor-llamada.tsx`, `lib/intencion-contacto.ts`, `lib/router.ts` | Llevan el id de origen hasta la encuesta (abajo) |
| Configuración de gerencia | `screens/config.tsx` (una tarjeta por vista) | Tarjeta nueva «Celulares» |

## Diseño propuesto (descripción, no código)

### 1. Emparejar por el id que genera el celular (propuesta #12)

1. La macro ya crea un id por llamada (`C1-{system_time}`, F3-c). La dirección que abre al colgar lo añade:
   `…/#/gestion-diaria/llamada/{call_number}/{lv=id_llamada}`. Las URL viejas, sin id, siguen funcionando como F1.
2. F1 (router, receptor y cola de intenciones) lleva ese **id de origen** hasta la encuesta.
3. Al guardar, la encuesta lo envía con el resultado.
4. **Servidor (migración nueva, F4-a):** una puerta versionada `crm.registrar_llamada_v5` hace, en **una sola
   transacción**, lo mismo que v4 (llama al núcleo sellado sin tocarlo) y además:
   - si la llamada con ese id **ya llegó** (de un celular vigente del mismo analista) → la enlaza al resultado;
   - si **todavía no llegó** → guarda una **intención de enlace** por id de origen, y la ingesta la consume cuando el
     aviso llega y enlaza sola.

   Correlación exacta, sin mirar la hora y sin un toque extra del analista. Es la propuesta #4 (puerta v5) más la #12.
   Con la corrección (PR #171), la llamada se busca por el hash del id de origen.

### 2. Pestaña «Llamadas del celular» del analista (F4.1)

- **Dónde:** en la tarjeta «Tu cola y tu actividad», después de «Mi seguimiento», con su número (`· N`) como las demás.
  Misma pantalla en el celular y en el PC (PWA).
- **«Pendientes»:** cada fila dice el lead, la hora de la llamada y el retraso («llamaste a las 10:42 · hace 16 min») y lo
  que pide: registrar resultado, revisar (ambigua o no elegible) o devolver (entrante perdida, con la #14).
- **Acciones:**
  - «Registrar resultado» abre **la encuesta de siempre en el panel «Ahora»**, con la línea que dice a qué llamada
    quedará unida.
  - «Elegir el lead» muestra solo leads de su cartera.
  - «Descartar» pide el motivo (lista cerrada + «otro»).
- Cerrar la encuesta **no** quita la llamada de la pestaña (F4.1.3).
- **«Qué pasó hoy»:** lo resuelto del día, con su resultado o su motivo y «Deshacer» (hallazgo 1).
- **Detalle (F4.1.2):** explica «ya registrada» o «descartada», o «no está disponible» para las que no existen, son de
  otro equipo o ya se depuraron (el servidor responde lo mismo a las tres, 42501, para no filtrar datos), y los errores
  con reintento.
- Lo registrado desde la pestaña **cuenta en «Tu día en cifras»** como cualquier gestión, y aparece en «¿Qué hice hoy?»
  con la marca «Celular».

### 3. Resultados que ya estaban sin enlazar (F4.2.4)

Para lo registrado desde el PC, o antes de la macro nueva: si un lead tiene una llamada pendiente y un resultado del
mismo analista guardado **después** de esa llamada y sin enlazar, la fila propone «¿Es este su resultado?». Un toque
enlaza (`crm.enlazar_llamada_celular`); nunca se enlaza solo, y no se duplica la gestión.

### 4. Supervisor y gerencia (decisión 4)

- **Gerencia:** la tercera pestaña de «Toda la operación hoy». Tabla por equipo (en el celular, con resultado, sin
  resultado, celulares, con problema) y panel del equipo con «Necesitan atención»: quién tiene llamadas sin resultado y
  qué celular está sin latido. Es de solo lectura: el resultado lo registra el analista.
- **Supervisor:** lo mismo para su equipo en «Mi equipo hoy». Falta su prototipo.
- Necesitan la puerta agregada del hallazgo 2.

### 5. Celulares para gerencia (F4.3.2)

Tarjeta «Celulares» en Configuración:
- **Asignar:** etiqueta C1, C2… y analista. La clave se muestra **una vez**, con «Copiar» y el aviso de que no se vuelve
  a ver.
- **Rotar:** clave nueva, y la vieja deja de valer.
- **Cerrar:** baja, extravío o reemplazo.
- **Salud por celular:** último envío, último latido, versión de la macro y avisos en cola.

### 6. Deshacer (F4.3.3)

Ya resuelto en el servidor (F2-c): deshacer no borra ni desenlaza; el enlace pasa al resultado corregido y el detalle
marca `efectos_anulados`. La pantalla solo lo muestra; nunca fabrica otra gestión.

## Hallazgos al revisar Gestión Diaria (03/10)

1. **No hay puerta para lo ya resuelto.** Las bandejas solo listan pendientes; «Qué pasó hoy» necesita una lectura nueva.
2. **Supervisor y gerencia necesitan una puerta que cuente por analista y por equipo**: hechas, con resultado, sin
   resultado y salud. Es la métrica de F6 del plan aprobado, adelantada.
3. **La marca «Celular» en «¿Qué hice hoy?»** exige que la consulta del registro sepa qué gestión está enlazada a una
   llamada del celular.
4. **El latido todavía no está en la macro**: sin él, «Sin latido» no se puede calcular.

## Decisiones que necesita Miguel

| # | Decisión | Recomendación de Claude | Alternativa y su costo |
| --- | --- | --- | --- |
| 1 | Cómo se emparejan resultado y llamada | **Por el id de origen del celular** (#12): exacto y sin toques extra | Proponer por cercanía de hora y que el analista confirme: un toque más en cada llamada y riesgo con dos llamadas seguidas |
| 2 | Dónde se compone el enlace | **Puerta v5 en una transacción** (F4.2.2 del plan, propuesta #4): sin resultados huérfanos | Que la pantalla llame a `enlazar` después de guardar y reintente (F4.2.3): sin migración nueva, pero con un hueco si se corta entre los dos pasos |
| 3 | Dónde vive la bandeja | **Pestaña «Llamadas del celular» en la Gestión Diaria del analista**, donde ya trabaja | En Alertas: más visible, pero separada de la cola del día |
| 4 | Supervisor y gerencia | **En F4, como paso propio (F4-e)**, con la puerta agregada del hallazgo 2 | En F6 (métricas): menos alcance ahora, pero gerencia no ve hasta entonces qué llamadas se quedan sin resultado |
| 5 | Administración de celulares | **Tarjeta «Celulares» en Configuración, solo gerencia** | Por SQL, como en el alta de C1 (`PUBLICAR-F2-F3.md` §4): sin pantalla, pero propenso a errores |

Miguel aprobó #13 (clientes) y #14 (entrantes) el 02/10. Van como pasos propios, después de la corrección. El diseño no
las cierra: la pestaña ya distingue «devolver», el enlace no depende de que sea lead y la búsqueda del número incluirá
los clientes de la cartera del dueño con la misma regla.

## Orden de trabajo (un PR por paso, cada uno con su plan aprobado)

0. **Antes:** la corrección de F2 + F3 (PR #171). Si Miguel elige ahí la opción A, F4-a se publica junto con F2 + F3.
1. **F4-a · Servidor:** migración de `crm.registrar_llamada_v5` + intención de enlace por id de origen + la ingesta la
   consume, y la lectura de «Qué pasó hoy» (hallazgo 1). Oráculo en el banco reducido (`npm run test:llamadas:local`),
   bloque nuevo en el gate y comando con recibo nuevo. **Necesita el OK de Miguel al SQL.**
2. **F4-b · Pantalla del analista:** módulo de datos (`data/llamadas-celular-api.ts`, un solo cliente para las puertas),
   la pestaña nueva, la encuesta con contexto, la marca «Celular» (hallazgo 3) y F1 con id de origen. Pruebas unitarias
   y E2E en Docker.
3. **F4-c · Celulares en Configuración** (gerencia).
4. **F4-d · Macro y validación (F4.4):** URL con el id de origen y el latido; casos de F4.4 en E2E y en C1, entre ellos
   evento antes/después, dos llamadas en diez minutos, dos pestañas, guardado con enlace fallido, deshacer y lead
   reasignado.
5. **F4-e · Supervisor y gerencia** (si Miguel lo elige en la decisión 4): puerta agregada (hallazgo 2), pestaña de
   gerencia y bloque del supervisor.

## Prototipo

https://claude.ai/artifact/NcXoy3g69AVv7vTWxD5mgv (privado hasta que Jhosep lo comparta). A Miguel le gustó (03/10,
según Jhosep). El tablero del analista se rehízo esa tarde para que copie la pantalla real: la primera versión dibujaba
un marco aproximado y parecía un rediseño.

- **Analista en el PC, interactivo:** su Gestión Diaria de siempre más la pestaña nueva. Se puede registrar (la encuesta
  se abre en «Ahora»), unir a un resultado ya guardado, elegir el lead, descartar con motivo y deshacer. Lo registrado
  sube en «Tu día en cifras», en «Llamadas por hora» y en «¿Qué hice hoy?» con la marca «Celular C1».
- **Analista en el celular:** la misma tarjeta de pestañas, y la encuesta en «Ahora».
- **Gerencia, interactivo:** «Toda la operación hoy» con la tercera pestaña.
- **Configuración › Celulares, interactivo:** asignar con la clave mostrada una vez, rotar, cerrar con motivo y ver la
  salud.

Datos de la demo, sin conexión al CRM.

## Riesgos y límites

- **v4 está sellada por md5** (`private.assert_gestion_diaria_resultado_v4`). La v5 no la modifica, la llama; el gate de
  sellos se amplía como se hizo con v4.
- **Todo F4 depende de F2 y F3 corregidas y en producción.** Sin ellas, la pestaña no tiene datos.
- La intención de enlace por id de origen necesita retención: si el aviso nunca llega (celular perdido), se depura con
  la misma política de 30 días.
- Límite de MacroDroid gratuito (5 macros): F4 no añade macros; cambia la dirección de «Abrir sitio web» y suma el latido
  a «Enviar cola». Las entrantes (#14) sí necesitan MacroDroid Pro.

## En llano

Gestión Diaria no se rediseña: al analista se le suma una pestaña, «Llamadas del celular», con lo que llamó desde el
celular y todavía no tiene resultado. Al registrarlo, se abre la misma encuesta de siempre en el mismo sitio, y queda
unida a esa llamada sin adivinar por la hora. Gerencia gana una tercera pestaña en «Toda la operación hoy» y una
tarjeta en Configuración para los celulares. Miguel decide cinco cosas; la cuarta es si supervisor y gerencia entran ya
en F4 o esperan a F6.
