# Llamadas del CRM: corrección de las propuestas #23 y #21 y encargo de implementación

Fecha: 13/10/2026. PRIMARY de este análisis: Codex, por encargo directo de Miguel.
Fuente revisada: `avancecorp/main` en `4ec46ba30838559142320692aa137305454a62d8` y PR #270 en
`3fc596a0babf5e890c3e7fed6255a7e1c8d1cd1c`. La rama local de código de #21 que menciona Jhosep no está publicada:
los hallazgos sobre ella son del **contrato escrito**, no una revisión de esa implementación inaccesible.

Estado: **CHANGES_REQUESTED para el diseño #23/#21 actual**. Este documento corrige el diseño y encarga su
implementación a Jhosep/Claude. No modifica código de producción, no aplica SQL y no acredita que la unificación
ya funcione. La aceptación anterior de F4-e queda conservada como evidencia histórica.

## 1. Decisión de Miguel y alcance

Las llamadas siempre se hacen con el celular. El resultado es una gestión del CRM, se marque en la PC o en el
celular. Miguel confirma quitar los apartados separados y pide unificar **registro, lectura y conteo**, no solo
los rótulos. El 13/10 encargó a Codex desarrollar la modificación, corregir el planteamiento y delegar la ejecución
que corresponda a Jhosep.

- Una encuesta de resultado y unas reglas comerciales para todos los accesos.
- Una llamada cuenta una vez. Su captura y su resultado son evidencia del mismo hecho, no dos gestiones.
- La captura sin resultado abre un pendiente del CRM; no fabrica «No contestó», contacto ni actividad comercial.
- El dato técnico de captura se conserva para vinculación, soporte y auditoría. No inventar que la llamada se
  originó en una pantalla del CRM ni cambiar su trazabilidad para lograr esta unificación funcional.
- «Sin captura integrada» no significa «sin celular» ni «no trabaja». Ningún flujo de registro depende de tener
  asignación de celular o latido activo.
- La fórmula de contacto y el cambio de reloj de los KPI son decisiones distintas de unificar la experiencia.
  Este encargo conserva el criterio comercial existente mientras se especifica la proyección nueva.

## 2. Hallazgos con evidencia

Las rutas siguientes son relativas a `CRM-Avance-Corp/`, salvo el comentario de GitHub.

| Prioridad | Evidencia | Problema y corrección |
| --- | --- | --- |
| P1 | #23, [apartados 2, 4, 5 y 6](https://github.com/avanza-digital/avancecorp-crm/pull/270#issuecomment-6156537188); `supabase/migrations/20260924201358_crm_gestion_diaria_pulso_habitos.sql:9` y `:49`; `supabase/migrations/20261013145935_crm_llamadas_celular_operacion_hoy_rendimiento.sql:139` | El pulso cuenta actividades por fecha de registro y F4-e cuenta eventos por fecha de llamada, además de resultados enlazados. No se pueden sumar ni elegir una fuente por «tener celular». Una persona integrada también puede registrar desde PC con la captura pendiente. Hace falta una proyección por identidad, fechas y ámbito, antes de reemplazar cifras. |
| P1 | `docs/plans/llamadas-celular/P21-PLAN-CORTO.md:40` y `:51` en el SHA del #270 | El plan rechaza el evento ya resuelto **antes** de recuperar el recibo. Si el primer guardado confirmó en la base y se perdió la respuesta, el mismo reintento ya no encuentra una pendiente. Recuperar y validar la operación confirmada antes de exigir que siga pendiente; vincular el recibo también a la llamada exacta. |
| P1 | `P21-PLAN-CORTO.md:40–46`; `supabase/migrations/20260921153654_crm_resultado_llamada_seguimiento.sql:131–159`; `supabase/migrations/20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql:74–103` | El plan toma evento → núcleo, pero el núcleo toma lead y el enlace vigente toma lead → evento. Intercalado posible: #21 retiene evento y espera lead; v5 retiene lead y espera evento. Corregir el orden y probar con dos conexiones. Es un riesgo derivado del plan, no un interbloqueo reproducido en su rama local. |
| P1 | `app/src/lib/store.tsx:3253–3266`; `supabase/migrations/20261005155914_crm_llamadas_celular_enlace_exacto.sql:639–647`; `supabase/migrations/20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql:103–110` | La encuesta comparte el núcleo v4, pero el cliente selecciona v4/v5 según el id de captura. v5 permite guardar la gestión y devolver `no_enlazado` si otra operación ya cerró esa llamada. Unificar solo las pantallas no elimina esa posibilidad. La nueva operación común debe confirmar conjuntamente el resultado y la identidad cuando se suministra una llamada exacta. |
| P2 | `P21-PLAN-CORTO.md:64–89`; `app/src/data/sla-operacion-comandos.ts:9`, `:29`, `:209–230` | El cliente no soporta sin cambios el nuevo nombre de comando del plan. Su lista cerrada, el nombre del sobre confirmado y las comprobaciones específicas de resultado/enlace deben actualizarse. Conservar intenciones v4/v5 pendientes y sus ids al actualizar la aplicación. |
| P2 | `app/src/lib/llamadas-celular-operacion.ts:142–155`; `app/src/components/gestion-diaria/su-celular-analista.tsx:45`; #23 §3.4 y §6.2 | `sin_dato` añade un motivo de atención incluso sin integración; el texto «sin celular» atribuye una ausencia física no demostrada. Separar cobertura técnica de pendientes de trabajo, sin sustituir las llamadas manuales por cero. |
| P2 | #23 §5 y §7; `supabase/migrations/20261005155914_crm_llamadas_celular_enlace_exacto.sql:576–605` | El alcance no es «solo pantalla». Incluye identidad/recibos, lecturas, paginación y compatibilidad; además hay purga de evidencia no resuelta. No reconstruir históricos completos a partir de una fuente con retención limitada. |

No se afirma que haya duplicados observados en producción. Mostrar el mismo hecho en dos vistas tampoco prueba
dos escrituras: la v5 **ya llama al núcleo v4**. Se reutiliza esa regla comercial, no se reimplementa.

## 3. Modificación concreta: un comando de resultado

`ReceptorLlamada` abre `RegistrarResultado` con el contexto disponible; la PC, la ficha, la cola y la lista de
llamadas abren esa misma encuesta. Una referencia de captura es contexto opcional, no el selector de otro proceso.
El acceso por enlace y las rutas publicadas siguen funcionando y aterrizan en el flujo común.

En el cliente, `registrarLlamada` pasa a usar **una versión común del comando** para las operaciones nuevas,
con resultado, submotivo, detalle, tarea, próxima acción, descarte y No insistir, más la referencia opcional de la
llamada. Nombre propuesto: `registrar_llamada_v6`; Jhosep lo confirma contra el catálogo antes de crear la migración.
Conserva el núcleo comercial v4 sellado y compone autorización, recibo y vínculo. No basta llamar a v5 desde todas
las pantallas si persiste el caso `no_enlazado` después de crear otra gestión.

Contrato de servidor:

1. Autorizar actor, rol y ámbito; no confiar en el actor o lead de una captura enviados por el navegador.
2. La identidad idempotente comprende actor + operación + contenido normalizado + llamada objetivo (si existe).
   Recuperar la confirmación de **esa misma operación** antes de rechazar «ya tiene resultado». Reusar el id con
   otro evento, resultado, lead o próxima acción es conflicto; no puede enlazar la actividad anterior a otra llamada.
3. Para una operación nueva, respetar el orden de bloqueos de persona/veto cuando corresponda, lead, evento y enlace,
   compatible con el núcleo y con Deshacer. Leer primero la referencia para resolver el lead sin bloquear el evento;
   después del bloqueo volver a validar identidad y ámbito. No esperar por una actividad retenida por Deshacer
   teniendo el lead bloqueado: conservar la defensa existente sin espera/reintento. No copiar un orden incompleto
   sin probarlo con ingesta, corrección, reasignación y las puertas antiguas aún accesibles.
4. Si la llamada exacta ya tiene resultado de otra operación: devolver conflicto de negocio y cero actividades,
   tareas o efectos nuevos. Ofrecer abrir el resultado existente. Una corrección se solicita explícitamente tras
   Deshacer y sigue las reglas actuales; no equivale a otra llamada.
5. Si la captura todavía no llegó pero hay id de origen válido, conservar la intención exacta existente y vincularla
   al llegar. La reserva/intención y el resultado se confirman atómicamente. Un rechazo de identidad/vinculación no
   debe dejar una segunda actividad. No hacer el fallback automático «falló con captura → guardar sin captura».
6. Si no hay referencia de captura, el registro habitual sigue funcionando. Se crea una sola actividad y su recibo.
   Una captura posterior se concilia con esa actividad, no obliga a volver a llenar la encuesta.
7. La respuesta confirma la operación, la actividad y el estado de vinculación; el cliente valida todos los campos.
   Un timeout conserva la intención y reintenta con el mismo id. Una actualización de la app recupera las intenciones
   antiguas con su comando original; no cambia su huella ni genera otro id para «migrarlas».

Las v4/v5 y los clientes antiguos requieren estrategia de convivencia: probar escrituras mezcladas. La garantía
global no está cerrada si el mismo evento todavía puede recibir un resultado nuevo mediante una puerta antigua
que omite la nueva guarda. Jhosep debe definir el adaptador compatible o la guarda común en una migración nueva,
conservando las respuestas y los replays existentes. No revocar una versión en uso sin resolver esos recibos.

**Prerrequisito obligatorio de la entrega B:** la guarda compatible de v5 entra en la misma migración que la
operación común, antes de conectar las pantallas. Para una operación nueva con captura, ambos accesos deben pasar
por la misma exclusión/confirmación transaccional. Puede ser una composición compatible o una excepción controlada
que revierta **toda** la transacción si no se confirma el vínculo: un helper posterior al núcleo no es por sí solo
demasiado tarde para hacer rollback. No poner una guarda en v4 que dependa de un evento que v4 no recibe.
Los replays antiguos deben recuperar la actividad confirmada sin efectos nuevos; la respuesta histórica completa
de v5 no está guardada en el recibo v4, por lo que no se puede prometer reconstruirla literalmente. Si no existe
evidencia persistida de a qué captura correspondía una operación antigua, confirmar su gestión y exigir conciliación
explícita del vínculo, sin enlazar otra captura a partir de parámetros distintos enviados durante el replay.

### 3.1. Asociación y descarte: reutilizar las operaciones existentes

Existe `crm.enlazar_llamada_celular(p_evento_id, p_actividad_id)` (`20261001160219`, líneas 765–775;
implementación vigente de su núcleo en `20261005143843:680–752`). Reutilizarla para la conciliación; no inventar
otra puerta por afirmar que falta. El cliente ya la invoca en `app/src/data/llamadas-celular-api.ts:184–193`.

- Es idempotente por el par evento/actividad: repetir el mismo par devuelve `repetido`; otra actividad vigente o
  una actividad ya vinculada a otro evento producen conflicto. No crea actividad ni cambia `creado_en` o efectos.
- La autorización es el ámbito **actual** sobre el lead, mediante `private.llamada_celular_visible`, no la igualdad
  obligatoria entre llamante y registrante. Se conserva el autor original de cada hecho. No ampliar ese ámbito.
- El núcleo toma actividad `FOR SHARE` → lead `FOR SHARE` → evento → enlace. Ese orden difiere del registro;
  mantener la compatibilidad probada y ensayar su concurrencia, no reemplazarlo mecánicamente por un orden genérico.
- La ventana de asociación sigue el contrato actual: resultado de la encuesta vigente del mismo lead, no anterior
  a la llamada por más de diez minutos. No se amplía la ventana de llamadas largas (#19) dentro de este encargo.
- No existe «desenlazar» libremente: un resultado deshecho puede sustituirse por el corregido, con auditoría.
  Una asociación errónea que no pueda corregirse así se trata por el procedimiento de soporte; no borrar enlaces.
- `crm.descartar_llamada_celular` se conserva para descartar evidencia con motivo, con sus permisos y repetición
  idempotente por evento/motivo. «Descartar evidencia» y «descartar lead» son operaciones distintas del CRM.

### 3.2. Intención diferida y captura incompatible

Reservar no significa que la captura esté comprobada. Además de formato/ventana, validar la asignación del
dispositivo al actor para ese momento y guardar la referencia autorizada, actor, lead y actividad esperada.
El helper actual ya valida asignación (`20261005182227:60–71`); no reducirlo a una validación de formato.

Al llegar el evento, revalidar asignación/actor, lead, resultado vigente y unicidad. La ingesta vigente toma primero
el lead (`20261005155914:531–546`) y el cumplimiento usa actividad sin esperar (`20261005182227:189–219`). Preservar
esa defensa. Si los datos no coinciden, la actividad guardada permanece: no se cambia de lead, no se deshace ni
se duplica. La captura queda sin asociar y se ofrece revisión **solo a quien tenga ámbito**; un actor no ve el lead
o número ajeno a causa de una reserva fallida. Un evento ya enlazado tampoco se sustituye silenciosamente.

Si la captura no llega, mostrar el resultado registrado con evidencia técnica no confirmada, sin exigir registrar
otra gestión. La intención se purga al plazo vigente de 32 días (`20261005155914:602–605`), distinto del plazo de
pendientes de la política. Su vencimiento elimina la expectativa técnica, no la actividad del CRM. No agregar
retención indefinida ni un estado «Sin resultado» a una gestión que ya tiene resultado.

## 4. Identidad y lectura única

No crear automáticamente otra actividad solo porque llegó un aviso del teléfono. Mantener separados el hecho,
su resultado vigente y su evidencia técnica, y proyectarlos como **una llamada del CRM**.

La proyección de servidor debe tener una identidad de llamada estable, independiente de la versión del resultado.
Reusar los vínculos existentes; si hace falta persistir una identidad/alias adicional para correcciones o llegada
tardía, justificarla en la migración. `p_operacion_id` identifica un intento de escritura, no sustituye por sí solo
la identidad de la llamada. Dos resultados de corrección no son dos llamadas.

Regla de identidad para la implementación: el primer hecho persistido recibe `llamada_id`; eventos, intenciones
y versiones de resultado se vinculan como referencias a esa identidad. Al conciliar dos representaciones previas,
conservar la identidad de la actividad ya registrada y redirigir la referencia de captura mediante un alias.
Una corrección hereda el `llamada_id` del resultado anterior; no genera otra identidad. Puede implementarse con
un mapa privado mínimo de identidades/referencias sobre las tablas actuales, sin copiar teléfonos ni crear otra
actividad. Si solo queda evidencia pendiente sin resultado, ese mapa caduca con ella. Si existe actividad,
la identidad puede conservarse con su historial autorizado; no convertir la purga en un archivo de capturas.

Reglas para construir las filas antes de filtrar por día y paginar:

- Captura enlazada + actividad: una fila; resultado vigente y evidencia conservados.
- Intención exacta antes de la captura: una fila; cuando llega el aviso se completa la evidencia de esa identidad.
- Actividad sin captura: una fila CRM, aunque el analista tenga captura integrada o esta falle.
- Captura identificada sin resultado: pendiente CRM, apto para abrir la misma encuesta o asociar un resultado existente.
- Corrección/Deshacer: conservar identidad e historial; cambiar el resultado vigente. No sumar versiones anuladas
  como llamadas nuevas, ni borrar el hecho físico al deshacer su resultado.
- Coincidencia solo por lead, teléfono o cercanía horaria: **candidato, nunca unión automática**. Puede haber dos
  llamadas reales próximas. La asociación confirmada de una captura con una actividad elimina la representación
  duplicada sin crear actividad ni alterar la fecha de registro de la existente.
- Si no se puede saber si una captura y un registro son la misma llamada, mostrar «Por revisar» dentro del flujo
  común y declarar el conteo provisional. No prometer un total exacto ni ocultar una evidencia para cuadrarlo.
- La cobertura técnica no cambia el registro manual, no amplía permisos y no transforma llamadas personales,
  ambiguas o excluidas en trabajo comercial confirmado.

**Límite real:** los datos actuales no prueban la identidad de una captura tardía cuando el resultado se guardó sin
referencia. Cambiar nombres, usar `DISTINCT lead_id` o sumar dos consultas no resuelve esa falta de información.
La implementación debe resolverla con referencia exacta o conciliación explícita. El prototipo debe mostrar ese caso.

La lectura común debe servir filas y agregados desde el mismo conjunto autorizado y el mismo corte temporal.
Paginar **después** de resolver identidades, con cursor estable; no unir en React la primera página de actividades
con la primera página de capturas. El total de una tabla no se obtiene contando las filas que ya descargó el cliente.

Regla de «Por revisar»: usar el predicado de candidatos de la asociación vigente como sugerencia, nunca como prueba
de identidad. Una captura sin referencia que tenga candidatos sin asociar se clasifica en revisión, no además en
«Sin resultado»; el analista puede confirmar una asociación o que fue otra llamada. La ausencia de candidatos
dentro de la ventana no prueba por sí sola que dos hechos antiguos sean distintos; los casos fuera de ventana
con duda declarada van a soporte (#19 permanece separado).
Si la identidad del conjunto del día no está resuelta, `total_llamadas` es `null` y `conteo_estado` es
`por_conciliar`; mostrar «Por revisar», no sumar 1 + 1 y mostrarlo como dos llamadas exactas. La revisión tiene su
propio número de casos, nunca se suma a llamadas ni a resultados. Los tres roles heredan ese mismo estado en los
totales que abarcan el caso. Con identidad resuelta pero hora/captura incompleta, usar `conteo_estado = parcial`;
con identidad y cobertura declaradas suficientes, `conteo_estado = confirmado`. Estos estados no acreditan que
un latido haya capturado todas las llamadas del mundo real.

Deshacer un resultado no prueba que la llamada existiera ni que fuera ficticia. Una actividad manual deshecha sin
captura pasa a revisión, no automáticamente a una llamada física «sin resultado». Se conserva el historial. La
unificación no crea un borrado/anulación libre para solventarlo; un registro erróneo se resuelve por soporte o por
una corrección explícita con trazabilidad, cuyo alcance debe reflejar el contrato existente.

## 5. Conteos, fechas y contacto

Primera entrega: operación de **hoy en Lima**, conservando el histórico anterior como registros históricos.
El contrato debe versionar el cambio de semántica; no reinterpretar silenciosamente hábitos o comparaciones previas.
El reloj técnico de la macro actual corresponde a colgar, no al comienzo de la conversación; no inventar duración.

| Dato en la misma vista de CRM | Definición |
| --- | --- |
| Llamadas de hoy | Identidades distintas con momento de llamada conocido dentro del día. Cuando solo se conoce el registro, conservar esa referencia declarada; no presentarla como hora física verificada. La calidad temporal y la conciliación determinan si el total es completo o provisional. |
| Con resultado | Subconjunto de esas mismas llamadas con un resultado vigente. El origen/dispositivo de registro no modifica la pertenencia. |
| Sin resultado | Subconjunto gestionable de esas llamadas sin resultado vigente, incluidas las deshechas que requieren corrección. Otros estados, como cerradas después o por revisar, conservan su estado; no forzar `total = con resultado + pendientes` si existen otras cubetas. |
| Pendientes de resultado | Trabajo actual de hoy y días anteriores; indicar la antigüedad. No usar todo ese saldo como denominador de un porcentaje de hoy. La retención sigue la política; no fijarla a 30. |
| Resultados registrados hoy | Resultados vigentes registrados hoy, aunque la llamada sea de ayer. Es una dimensión temporal distinta, en la misma vista, no otro origen de llamadas. No se suma a «Llamadas de hoy». |
| Contacto de resultados registrados hoy | Conservar inicialmente `contestadas / útiles` en la cohorte de **resultados registrados hoy**, con las exclusiones actuales (`numero_errado`, `no_es_la_persona`). Rotular esa cohorte junto al porcentaje. No usar «Llamadas de hoy» como su denominador. Las llamadas sin resultado no se tratan como «No contestó». Sin denominador: «—». Un cambio de definición se presenta aparte con ejemplo antes/después. |

Los nuevos porcentajes se calculan desde enteros del mismo conjunto en pantalla, como exige F4-e; no añadirlos a
su JSON. No alterar por este encargo los porcentajes legados de otros contratos. En grupos, sumar numeradores y
denominadores; nunca promediar porcentajes. Mostrar el estado de cobertura sin dividir el trabajo en «CRM/celular».

Para el autor del conteo: la captura conserva quién llamó; la actividad conserva quién registró el resultado.
Una reasignación cambia el ámbito actual, no reescribe al autor histórico. Sin evidencia del llamante, no inferirlo
del dueño actual del lead. Roster, actividad propia de supervisor y exclusiones deben tener reglas explícitas.

La nueva lectura respeta RLS/ámbito y retención. La captura purgada no se reconstruye desde datos de auditoría ni
se conserva indefinidamente mediante una tabla nueva por comodidad. Un histórico de llamadas físicas completo
requeriría otro contrato de conservación; no está autorizado por esta unificación.

Al conciliar, la hora física disponible sustituye la referencia de registro **en la proyección nueva**; puede mover
una llamada del día de registro al día de ocurrencia. No modifica `actividad.creado_en` ni los KPI históricos del
contrato anterior. La respuesta incluye `generado_en` y una revisión del conjunto; la conciliación invalida todos
los totales afectados y reinicia la paginación. Un cursor de una revisión anterior se rechaza o fuerza recarga;
no continuar una lista cuyo orden cambió mientras se calculaba el agregado.

## 6. Pantallas y los tres hallazgos de C1

| Lugar | Cambio encargado |
| --- | --- |
| Analista | Quitar la pestaña separada «Celular». En «Mi actividad → Llamadas» mostrar una fila por llamada. Integrar «Sin resultado» y «Por revisar» en su trabajo habitual, usando la misma encuesta. Mantener accesibles asociar, descartar con motivo, abrir resultado, Deshacer y corregir. |
| Supervisor | Quitar «Su celular» y consumir las mismas cifras autorizadas en los cuadros actuales. «Necesitan atención» muestra acciones pendientes reales. La ausencia de integración es contexto de cobertura, no un incumplimiento. |
| Gerencia | Integrar llamadas, pendientes y cobertura en la tabla habitual de operación; quitar la tercera pestaña. Los subtotales y los detalles deben cuadrar contra la misma lectura. |
| Encuesta | Misma UI, catálogo y consecuencias desde cualquier acceso. La referencia de la llamada viaja internamente; no obliga a elegir entre «registrar en CRM» y «registrar en celular». |
| Soporte | La administración de dispositivos conserva su sitio en Configuración. Los detalles de macro, cola y latido no se convierten en categorías de actividad. |

Correcciones de los hallazgos: (1) quitar la ausencia de integración de los motivos de atención, manteniendo los
pendientes reales incluso si no hay integración; (2) permitir localizar las deshechas antiguas corregibles, aunque
no aparezcan en «Qué pasó hoy»; si el lead está cerrado/vetado, mostrar su estado sin ofrecer escritura prohibida;
(3) llamar «Tareas pendientes» a las tareas y «Sin resultado» a las llamadas. «Sin cerrar encuesta» no debe confundir
un problema de asociación con una encuesta que nunca se guardó.

## 7. #21: atajo del mismo flujo, no otro motor

Se incorpora después de asegurar la operación común. Elegir varias llamadas del mismo lead y confirmar
«No contestó» es una declaración del analista. **Se corrige nuestro reparo anterior:** no exigir un estado técnico
no disponible para que el analista pueda declarar el resultado. Esto no autoriza inferirlo automáticamente.

- Un resultado por llamada, misma operación común e invariantes que el registro individual; solo cambia cuántas
  veces se pide confirmación. Sin descarte automático «No responde» en la primera versión.
- Persistir el lote, las llamadas elegidas, la carga útil y un id de operación por elemento antes del envío.
  Serializar. Un reintento recupera esos ids, incluso tras recargar; crear otro lote no es reintentar el anterior.
- Separar éxitos propios, llamadas ya resueltas por otra operación, errores y confirmaciones inciertas. «Ya estaba
  resuelta» no acredita que esa otra operación guardó «No contestó».
- La tarea que se cierra y la próxima acción se ejecutan una sola vez. Definir el caso de que la última llamada
  ya esté resuelta, falle o se omita: no mostrar «seguimiento programado» si nunca se creó. Propuesta inicial:
  confirmar los resultados del lote y ofrecer la próxima acción en un paso común posterior con recibo propio.
  Jhosep especifica cómo conserva las validaciones del CRM y la recuperación de ese paso; no concatenar a ciegas
  `p_siguiente`/`p_tarea_id` en todos los elementos.

La próxima acción es opcional para `no_contesto` en el núcleo vigente
(`supabase/migrations/20260921153654_crm_resultado_llamada_seguimiento.sql:95–116` y `:189–195`), por lo que registrar
los elementos del lote sin `p_siguiente` es compatible. No extender ese atajo a `volver_a_llamar` o `agendo_reunion`,
que sí exigen seguimiento al dueño; mantienen su encuesta normal.

## 8. Entrega delegada a Jhosep y su Claude

Miguel autorizó corregir o delegar. Codex entrega este contrato y su revisión; **Jhosep/Claude es el único escritor
de la implementación**, en su checkout y rama. Codex no modifica su #270 ni su rama local de #21.

| Entrega | Archivos/área | Evidencia de cierre |
| --- | --- | --- |
| A. Corregir el plan y mostrar el flujo | #23, `P21-PLAN-CORTO.md`, `COORDINACION.md`, prototipo de los tres roles | Responder en #270 con cómo incorpora cada hallazgo; ejemplo PC/celular, conciliación tardía y cobertura parcial. Prototipo con estados normales, vacíos y de error. |
| B. Identidad, comando y lectura | Migración nueva; recibo/vínculo común; lecturas y tipos | SQL, reversa compatible, registrador y ledger; matriz de permisos, banco real y concurrencia. La guarda compatible de v5 y recuperación de intenciones antiguas son obligatorias antes de C. No limitar el cambio al pulso. |
| C. Integración de pantallas | `lib/store.tsx`, `data/sla-operacion-comandos.ts`, receptor/encuesta, pantallas `analista.tsx`, `supervisor.tsx`, `gerencia.tsx`, consultas, demo | Un acceso común de escritura y una proyección coherente de lectura; pruebas y E2E Docker con los tres roles. Retirar componentes separados solo después de cubrir sus acciones. |
| D. Lote #21 | Misma operación y UI de llamadas | Pruebas de respuesta perdida, recarga, dos pestañas y tarea/seguimiento parcial; sin guardar otra gestión por una llamada ya resuelta. |
| E. Validación final | Codex revisa la entrega publicada por Jhosep; Jhosep acepta en C1 | Gates, evidencia de despliegue y aceptación. La aplicación SQL/publicación sigue su autorización y procedimiento vigente; no se considera hecha al fusionar. |

No repetir la pregunta genérica «¿unificamos?»; esa decisión ya la tomó Miguel. Una decisión adicional debe venir
con alternativas concretas y evidencia del contrato que afectaría. Jhosep debe publicar su trabajo local revisable
antes de que Codex pueda certificarlo; «probado en local» no sustituye esa entrega.

## 9. Casos de aceptación obligatorios

1. Cinco llamadas, cinco resultados vinculados: cinco filas y cinco llamadas, no diez, iguales en los tres roles.
2. Mismo resultado desde PC y celular: misma regla comercial; dos intentos sobre la misma identidad de llamada no crean dos actividades.
3. Captura primero, resultado después: un pendiente pasa a resuelto; total de llamadas estable.
4. Resultado primero con referencia exacta, captura después: se completa una misma identidad, sin sumar otra llamada.
5. Resultado sin referencia y captura tardía: conciliación dentro del CRM, sin inventar coincidencia ni pedir registrar otra gestión.
6. Dos llamadas al mismo lead cercanas: se mantienen dos; jamás deduplicar solo por lead, número o ventana de tiempo.
7. Una llamada de ayer registrada hoy: una llamada ayer y un resultado registrado hoy; no un 100 % con fechas mezcladas.
8. Cerrar la encuesta sin guardar: pendiente, sin resultado inventado. Guardar no identifica automáticamente «contacto» por duración.
9. Deshacer y corregir, incluida llamada antigua: misma identidad; se conserva el historial y una única versión vigente.
10. Actor sin integración o con pérdida de señal: su registro manual funciona y cuenta; no aparece como inactivo por cobertura.
11. Dos sesiones, operación común contra v5 antigua, ingesta y Deshacer: sin doble resultado ni interbloqueos; errores reintentables con el mismo id.
12. Respuesta perdida: mismo id devuelve confirmación incluso si ya está resuelta; otro id no crea otro resultado para esa llamada.
13. Id reutilizado con evento/lead/resultado distinto: conflicto, sin efectos. Logout/cambio de rol no muestra recibos ajenos.
14. Lote con éxitos parciales, última llamada omitida y recarga: progreso recuperable; tarea y seguimiento cero o una vez, estado explícito.
15. Reasignación, lead cerrado/vetado y otro equipo: ámbitos preservados y autor histórico intacto; ninguna fuga de números personales.
16. Más de una página, timestamps empatados y actualización concurrente: filas y totales coherentes, sin dobles ni huecos al paginar.
17. Pendientes fuera del plazo, captura purgada e histórico: no prometer cifras completas ni ampliar retención silenciosamente.
18. Contacto con denominador cero, resultados no útiles y registro tardío: «—» cuando corresponde, exclusiones y cohorte documentadas.
19. Captura posterior de otro actor/lead/asignación: no enlazar, no alterar la actividad guardada ni revelar datos ajenos.
20. Intención cuya captura nunca llega: vence al plazo actual; resultado conservado, sin inventar otro pendiente de resultado.
21. Asociación al mismo par repetida, otro par concurrente y tras reasignación: invariantes y permisos existentes, sin nueva gestión.
22. Reintento v5 anterior con vínculo no confirmado: misma actividad, ningún efecto nuevo, sin prometer un sobre histórico no guardado.
23. Asociación que cambia el día: invalidación de ambos cortes y del cursor; no alterar la fecha de registro.
24. Deshacer una actividad manual sin captura: revisión explícita, no una llamada física inventada ni borrado de historial.
25. Captura con candidato ambiguo: solo revisión, total no exacto (`null`), sin duplicarla como pendiente y llamada confirmada.
26. Purga de evidencia sin resultado: identidad auxiliar caduca con ella; la identidad con actividad sigue su historial autorizado.

## 10. Verificación de esta entrega

Este es un contrato técnico revisado contra código, no una implementación. Se verifican rutas, referencias y
`git diff --check`. La revisión independiente devolvió `CHANGES_REQUESTED`; se conserva sin convertirla en PASS.
Las decisiones de aceptación parcial y las correcciones están en
`2026-10-13-llamadas-crm-unificadas-respuesta-review.md`, junto al dictamen original.
Los tests de aplicación, E2E, concurrencia SQL y producción de la **nueva unificación** son NOT RUN: pertenecen
a la implementación delegada. No reutilizar los PASS de F4-e como si validaran #23.
