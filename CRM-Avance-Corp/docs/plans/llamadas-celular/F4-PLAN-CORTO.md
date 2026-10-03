# F4 · Bandeja y registro conciliado — plan corto (borrador para el OK de Miguel)

Escrito el 03/10/2026 en `feat/llamadas-f2`. **Solo análisis: sin código ni SQL.** Depende de que F2 y F3 estén
aplicadas (PR #169). Las tareas son las del plan aprobado (`PLAN.md` §10, F4.1–F4.4); aquí se dice cómo hacerlas con
lo que ya existe y qué decide Miguel.

## En una línea

Que cada llamada que avisa el celular quede **registrada y enlazada a su resultado**, sin duplicar gestiones. Si el
analista no la registró, la ve en una **bandeja de «llamadas sin registrar»** y la completa desde el celular o el PC.

## El problema que resuelve el diseño: la encuesta llega ANTES que el aviso

Probado en C1 el 02/10 (`REGISTRO.md` §5e): al colgar, la encuesta de F1 se abre al instante, y el aviso del celular
llega unos 11 segundos después (o horas después, sin señal). El analista suele guardar el resultado **antes** de que
exista la llamada en el CRM. Hoy ese resultado no sabe de qué llamada es. Emparejarlos por la hora («el resultado de
las 10:43 es de la llamada de las 10:42») está prohibido por el plan (F4.2.4: «nunca decidir solo por ±10 minutos»):
con dos llamadas seguidas al mismo lead se equivocaría.

## Lo que ya existe y se reutiliza (no se rehace)

| Pieza | Dónde | Uso en F4 |
| --- | --- | --- |
| Puertas de la bandeja, detalle, asociar, enlazar y descartar | F2-c `20261001160219`, F3-a `20261001212258` (`crm.llamadas_celular_bandeja_fn` paginada, `crm.llamada_celular_detalle_fn`, `crm.asociar_llamada_celular`, `crm.enlazar_llamada_celular`, `crm.descartar_llamada_celular`) | La bandeja las consume tal cual; el ámbito ya lo decide el servidor |
| Puertas de celulares | `crm.asignar_celular`, `crm.rotar_credencial_celular`, `crm.cerrar_asignacion_celular`, `crm.celulares_salud_fn`, `crm.celulares_asignaciones_fn` | Pantalla de administración para gerencia (F4.3.2) |
| Encuesta «Registrar resultado» | `app/src/components/gestion-diaria/registrar-resultado.tsx` | La misma encuesta, sin pantalla nueva; solo recibe el contexto de la llamada |
| Confirmación real del resultado | `lib/store.tsx` → `registrarLlamada(...).confirmacion` devuelve el `actividad_id` que confirmó el servidor | Base de F4.2.1 |
| Comandos con recibo («Guardados por confirmar») | `data/sla-operacion-comandos.ts` | El registro con enlace usa el mismo mecanismo: un reintento no duplica |
| Deshacer | `store.deshacerResultadoLlamada` + regla del servidor (decisión 4 de F2: el enlace se mueve al resultado corregido) | F4.3.3 ya está resuelto en el servidor; la pantalla solo lo muestra |
| Receptor de F1 y cola de intenciones por pestaña | `components/app/receptor-llamada.tsx`, `lib/intencion-contacto.ts`, `lib/router.ts` | Llevan el id de origen hasta la encuesta (abajo) |
| Gestión Diaria del analista | `screens/gestion-diaria/analista.tsx` («Ahora» + «Tu cola y tu actividad» en pestañas, `pestanasDiarias`) | La bandeja va como una pestaña más |
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

### 2. Bandeja «Llamadas sin registrar» (F4.1)

- **Dónde:** una pestaña nueva en «Tu cola y tu actividad» de Gestión Diaria, con su contador. «Hoy» ya lleva ahí con su
  botón. Misma pantalla en el celular y en el PC (PWA).
- **Cada fila:** el lead, la hora de la llamada y el retraso («llamó a las 10:42 · hace 25 min») y lo que pide: registrar
  resultado, revisar (ambigua o no elegible) o devolver (entrante perdida, solo si se aprueba la #14).
- **Acciones:** «Registrar resultado» abre la misma encuesta con el contexto de la llamada; «Asociar» elige entre los
  candidatos de su ámbito; «Descartar» pide el motivo (lista cerrada + «otro»).
- Cerrar la encuesta **no** quita la llamada de la bandeja (F4.1.3).
- **Detalle (F4.1.2):** explica «ya registrada» o «descartada» (lo dice el propio detalle), o «no está disponible» para
  las que no existen, son de otro equipo o ya se depuraron (el servidor responde lo mismo a las tres, 42501, para no
  filtrar datos), y los errores con reintento.

### 3. Resultados que ya estaban sin enlazar (F4.2.4)

Para lo registrado desde el PC, o antes de la macro nueva: si un lead tiene una llamada pendiente y un resultado del
mismo analista guardado **después** de esa llamada y sin enlazar, la fila propone «¿Es este su resultado?». Un toque
enlaza (`crm.enlazar_llamada_celular`); nunca se enlaza solo.

### 4. Celulares para gerencia (F4.3.2)

Tarjeta «Celulares» en Configuración:
- **Asignar:** etiqueta C1, C2… y analista. La clave se muestra **una vez**, con «Copiar» y el aviso de que no se vuelve
  a ver.
- **Rotar:** clave nueva, y la vieja deja de valer.
- **Cerrar:** baja, extravío o reemplazo.
- **Salud por celular:** último envío, último latido, versión de la macro y avisos en cola.

### 5. Deshacer (F4.3.3)

Ya resuelto en el servidor (F2-c): deshacer no borra ni desenlaza; el enlace pasa al resultado corregido y el detalle
marca `efectos_anulados`. La pantalla solo lo muestra; nunca fabrica otra gestión.

## Decisiones que necesita Miguel

| # | Decisión | Recomendación de Claude | Alternativa y su costo |
| --- | --- | --- | --- |
| 1 | Cómo se emparejan resultado y llamada | **Por el id de origen del celular** (#12): exacto y sin toques extra | Proponer por cercanía de hora y que el analista confirme: un toque más en cada llamada y riesgo con dos llamadas seguidas |
| 2 | Dónde se compone el enlace | **Puerta v5 en una transacción** (F4.2.2 del plan, propuesta #4): sin resultados huérfanos | Que la pantalla llame a `enlazar` después de guardar y reintente (F4.2.3): sin migración nueva, pero con un hueco si se corta entre los dos pasos |
| 3 | Dónde vive la bandeja | **Pestaña en Gestión Diaria** del analista, donde ya trabaja | En Alertas: más visible, pero separada de la cola del día |
| 4 | Supervisión y gerencia ven la bandeja de su equipo | **En F6** (métricas); las puertas ya lo permiten, sin pantalla en F4 | En F4: más alcance y más pruebas ahora |
| 5 | Administración de celulares | **Tarjeta «Celulares» en Configuración, solo gerencia** | Por SQL, como en el alta de C1 (`PUBLICAR-F2-F3.md` §4): sin pantalla, pero propenso a errores |

Clientes (#13) y llamadas entrantes (#14) quedan fuera de F4 hasta que Miguel las decida. El diseño no las cierra: la
bandeja ya distingue «devolver» y el enlace no depende de que sea lead.

## Orden de trabajo (un PR por paso, cada uno con su plan aprobado)

1. **F4-a · Servidor:** migración de `crm.registrar_llamada_v5` + intención de enlace por id de origen + la ingesta la
   consume. Oráculo en el banco reducido (`npm run test:llamadas:local`), bloque nuevo en el gate y comando con recibo
   nuevo. **Necesita F2 y F3 aplicadas y el OK de Miguel al SQL.**
2. **F4-b · Pantalla del analista:** módulo de datos (`data/llamadas-celular-api.ts`, un solo cliente para las puertas),
   la pestaña de la bandeja, la encuesta con contexto y F1 con id de origen. Pruebas unitarias y E2E en Docker.
3. **F4-c · Celulares en Configuración** (gerencia).
4. **F4-d · Macro y validación (F4.4):** URL con el id de origen; casos de F4.4 en E2E y en C1, entre ellos evento
   antes/después, dos llamadas en diez minutos, dos pestañas, guardado con enlace fallido, deshacer y lead reasignado.

## Lo que se puede adelantar sin Miguel

- **Prototipo visual de la bandeja y de «Celulares»** con `/design`, antes de tocar código (regla del proyecto para
  cambios visuales grandes).
- **F4-a en el banco reducido**, sin aplicar, como se hizo con F2 y F3, si Miguel aprueba antes las decisiones 1 y 2.

## Riesgos y límites

- **v4 está sellada por md5** (`private.assert_gestion_diaria_resultado_v4`). La v5 no la modifica, la llama; el gate de
  sellos se amplía como se hizo con v4.
- **Todo F4 depende de F2 y F3 en producción.** Sin ellas, la bandeja no tiene datos.
- La intención de enlace por id de origen necesita retención: si el aviso nunca llega (celular perdido), se depura con
  la misma política de 30 días.
- Límite de MacroDroid gratuito (5 macros): F4 no añade macros; solo cambia la dirección de «Abrir sitio web».

## En llano

Hoy el celular avisa de cada llamada y la encuesta se abre al colgar, pero las dos cosas no se conocen entre sí. F4
las une: el celular le pasa a la encuesta el código de la llamada, así el resultado y la llamada quedan emparejados sin
adivinar por la hora. Y lo que el analista no registró aparece en una bandeja nueva dentro de Gestión Diaria, para
completarlo desde el celular o el PC. Gerencia tendrá una pantalla para dar de alta y de baja los celulares. Miguel
decide cinco cosas antes de empezar; mientras tanto se puede adelantar el diseño visual.
