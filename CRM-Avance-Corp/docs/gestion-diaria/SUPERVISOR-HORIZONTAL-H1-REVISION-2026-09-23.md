# H1 — revisión independiente y resolución

23/09/2026. Codex PRIMARY → Claude SECONDARY_REVIEWER mediante
`scripts/claude-review`, sin herramientas/MCP del reviewer y con fuentes saneadas.
Primer intento no completado; repetición del mismo pedido con acceso de red sí
entregó dictamen. Una revisión sustantiva; no se pidió una respuesta favorable.

**Dictamen original: CHANGES_REQUESTED, confianza MEDIUM; sin P0/P1.**
Codex resolvió los puntos siguientes en la especificación. No hubo segunda
revisión de la versión corregida; no atribuir PASS final a Claude.

| Punto | Decisión del PRIMARY y evidencia |
|---|---|
| Refresco multipágina | Aceptado: congelar todas las páginas desde la segunda; antigüedad visible y actualización desde inicio. Prueba de inserción/reprogramación antes del cursor definida. |
| Orden Atención/Vencidas | Aceptado: Atención por cantidad de motivos, después vencidas y nombre/id; Vencidas comparador propio. Ajuste de presentación explícito y pruebas exigidas. |
| Registro/identidad | Aceptada la concreción; no hace falta cambiar la key compartida: `pestanaInicial` queda fija por instancia. Solo apertura explícita aumenta `apertura` y reinicia según contrato. Las pestañas externas conservan instancia. Individual pasa `[id]`, oculta selector de analista y no permite selector de equipo; las opciones actuales ya se acotan por `analistaIds` (registro-actividad.tsx:115–117). No se acepta como probado que actualmente exponga otro analista. Defaults de otros roles intactos. |
| Título durante error | Aceptado: instantánea mínima de ID/nombre confirmados, ligada al contexto; no métricas antiguas. Región con ID estable; revocación/roster válido retiran todo. |
| Anclajes/nulabilidad | Aceptada la necesidad de precisar. `tarea-schema.ts:4–17` y `database.types.ts:3959–3989` declaran tipo/título/vence_en no nulos; referencia nullable. `tipos.ts:282–294` declara un sujeto lead/perfil/inversionista. Tres clases y su presentación explicitadas. La hipótesis de null por grants no queda acreditada; la falta de grant debe fallar, no convertirse en dato vacío. Ensayo SQL de las tres clases pendiente para H3. |
| Contacto/densidad | Aceptado y medido en DOM: Plus Jakarta Sans16/400, «Sin muestra»88,34375px. En fila no se añade tasa al mismo texto; tasa/fracción/mínimo permanecen en panel y descripción accesible. Columna132 con padding16. Min columnas824 + scrollbar16 = tabla840. |
| Estado accesible de selección | Aceptado: `aria-current=true` para botón activo; no toggle que no conmuta. |
| Salto al detalle | Aceptado parcialmente: un único botón de44px en la fila activa, no uno en cada fila. Cabe junto al nombre típico; los largos pueden envolver. |
| Ampliar, overlays y responsive | Aceptado: dimensiones de diálogo, popover y cajón; vacío inicial y transición de foco/modalidad por breakpoint definidos. Scrollbar reservado explícitamente. |
| Filtro Con pendientes | Aceptado: mismo predicado que KPI (tareas o primer intento), test de paridad y motivo SLA aunque tareas=0. |
| Privacidad del asset | Comprobado por inspección del asset generado aprobado: es la ilustración sintética de la conversación, con rótulo «Datos ficticios». Hash coincide. No se versionaron capturas de clientes ni se adjuntaron datos reales a Claude. |
| Roster compartido | Aceptada la recomendación de arquitectura: H3 extrae resolver autorizado de roster para usarlo en resumen y nueva lectura, con paridad antes/después. No duplicar autoridad. |
| Grant del núcleo | No aplicar la recomendación genérica de quitar EXECUTE a authenticated manteniendo puerta invoker: impediría que esta llame al núcleo. Se conserva la cadena invoker, con guard en cada entrada ejecutable y prueba de invocación directa. Sin elevación a definer ni permiso nuevo sobre tablas. |

**Cierre del PRIMARY:** especificación concreta; verificaciones documentales en
el archivo de evidencia. Implementación y pruebas SQL/frontend: NOT RUN en H1.
La geometría es un presupuesto y una medición de etiqueta; su realización completa
se acepta en H2/H5. La revisión no sustituye esos gates.

## Dictamen original

VERDICT:
CHANGES_REQUESTED

SUMMARY:
La especificación H1 es sólida y en general se puede implementar. Cubre fuentes y unidades, invariantes, estados vacíos o de error, ciclo de vida por identidad y un contrato de Pendientes acotado, invoker, con una misma denegación `42501` y validación estricta en cliente. La geometría suma exactamente: 52 + 44 + 10×44 = 536, y 192 + 536 + 8 + 44 = 780. No hay P0 ni P1.

Quedan huecos accionables: cuatro de contrato o comportamiento que pueden producir datos incorrectos o incoherentes, y varios de accesibilidad y destino. Conviene cerrarlos antes de H2/H3. No son fallos de producto: la prueba real llegará con H2–H5. Esta revisión evalúa si el documento basta para implementar sin decidir sobre la marcha.

FINDINGS:

[P2] Refresco de Pendientes con varias páginas puede perder u ocultar tareas
File: SUPERVISOR-HORIZONTAL-H1-ESPECIFICACION-2026-09-23.md
Lines: 318–330
Problem: dice «Primera página visible refresca cada minuto; si hay varias páginas, conservar recorrido». No aclara si la página 1 sigue refrescándose cuando ya hay páginas posteriores cargadas.
Evidence: el orden es `vence_en ASC, id ASC`. Si llega una tarea que vence antes, la última fila de la página 1 pasa a la posición 26. Esa fila queda por debajo del cursor ya usado para la página 2 y desaparece de la lista acumulada. El dedupe por ID (línea 321) resuelve duplicados, no omisiones. En Registro esto no pasa porque el keyset es estable hacia atrás (`registro-actividad.tsx:76–77`); en tareas ascendentes, sí.
Impact: lista incompleta presentada como actual. Contradice la línea 121.
Recommendation: refrescar automáticamente solo si hay una única página. Con más páginas, congelar, mostrar la antigüedad y ofrecer «Actualizar desde el inicio». Añadirlo al test de concurrencia (aceptación 5).

[P2] El orden inicial «Atención descendente» no coincide con lo que muestra la columna
File: spec líneas 190, 237; `gestion-diaria-equipo.ts:112–113`
Problem: la celda muestra «N motivos», pero el comparador actual ordena por `requiere_atencion` (booleano), después `tareas_vencidas` y después llamadas.
Impact: una fila con 1 motivo y muchas vencidas aparece por encima de otra con 3 motivos. El orden visible parece arbitrario, y `aria-sort` anuncia un orden que el usuario no percibe.
Recommendation: definir el comparador de Atención como `motivos_atencion.length` → vencidas → nombre/id, o mostrar la clave real. Añadir `'vencidas'` a `OrdenEquipo` con test de desempate.

[P2] RegistroActividad en el panel: identidad y selectores sin definir
File: spec líneas 204–225; `registro-actividad.tsx:62, 66, 74–75, 115–117`
Problem:
- La `key` de identidad incluye `pestanaInicial`, y el valor por defecto es `'llamadas'`. Si las acciones «Ver llamadas», «Aviso de persona» o «Ver registro» cambian `pestanaInicial`, el componente se remonta y borra filtros, páginas y scroll. Eso contradice la línea 213, que exige conservarlos.
- En modo individual, el componente sigue ofreciendo sus selectores internos de equipo y de analista. El supervisor podría ver a otra persona dentro del panel de la primera, lo que rompe «Solo una persona mantiene estado» (línea 214) y la coherencia con «Últimas gestiones».
Recommendation:
- Sustituir `pestanaInicial` en la `key` por la «secuencia de apertura deliberada» (línea 206), aplicada como comando: cambia de pestaña y reinicia solo lo que la acción declara.
- Especificar que en modo individual los selectores de analista y equipo se ocultan (`analistaIds=[id]` fijo).
- Incluir el modo en la clave.

[P2] Persona del panel durante un error temporal del equipo
File: spec líneas 120, 211, 218; `gestion-diaria-equipo-queries.ts:40`
Problem: ante un error, `dia` devuelve `null`, y la persona «se resuelve desde todo `equipoPresentado`». Con el error no hay de dónde resolver el nombre del encabezado ni el `aria-controls` del panel, aunque la especificación exige que el panel siga montado.
Recommendation: guardar al seleccionar una instantánea mínima (`analista_id` y nombre confirmado) ligada a la identidad del contexto. Usarla solo para el encabezado mientras dure el error de red. Una respuesta válida sin la persona, o un `42501`, la borra.

[P2] Contrato de ítems de Pendientes: clases de anclaje y nulabilidad
File: spec líneas 304–320; `crm-api.ts:2425–2431`; `20260920045202…sql:198`
Problem:
- El nuevo conjunto incluye tareas sin lead ni perfil («no excluir tareas por no tener lead»).
- Agenda sustituye las filas «neutrales» de postventa por otra fuente, lo que sugiere que esas filas pueden llegar parcialmente vacías bajo RLS o grants. Es una hipótesis que no puedo verificar con la evidencia adjunta.
- Además, «fila inválida → error de contrato» (línea 320) haría que una sola fila con `titulo` o `tipo` nulo por grants dejara sin lista a toda la persona.
Recommendation:
- Enumerar las clases de anclaje: lead, perfil, postventa y otras.
- Por cada clase, indicar qué campos son nulables y cómo se muestra.
- Confirmar en el banco autorizado qué columnas ve un supervisor en tareas de postventa.
- Declarar si `vence_en` puede ser NULL; la comparación de tupla del cursor lo rompería.

[P2] Ancho de Contacto frente a su contenido
File: spec líneas 116, 157
Problem: 132 px debe contener la tasa y «Muestra insuf.» a 16 px en una sola línea, además del padding. Eso ronda los 150 px o más.
Impact: la muestra insuficiente es frecuente a primera hora. Si la celda se parte en dos líneas, esas filas crecen y la meta de diez filas no se cumple justo cuando más se usa la vista.
Recommendation: medir el peor caso típico con la fuente real. Ajustar el mínimo (por ejemplo, quitando ancho a Atención o Analista) o usar un texto corto con explicación accesible.

[P3] `aria-pressed` con reselección que no deselecciona
File: spec líneas 194, 208–209
Problem: `aria-pressed` anuncia un conmutador, pero volver a pulsar la misma persona «conserva» la selección y no la desactiva.
Recommendation: usar `aria-current="true"` en el botón de la persona activa, o definir que volver a pulsar no conmuta y probarlo con un lector de pantalla.

[P3] «Ir al detalle» por fila duplica las paradas de tabulación
File: spec líneas 192, 238
Problem: si el enlace existe en cada fila, diez filas suman veinte paradas, lo contrario de «sin muchos tabs».
Recommendation: un único enlace de salto tras la tabla o en su barra, que dependa de la selección.

[P3] Destinos de layout sin dimensionar
- **«Ampliar» (líneas 248, 257):** no dice si el panel pasa a ancho completo, si tapa la tabla ni cuáles son sus medidas.
- **Desplegables «Cortes», «Otros pendientes» e «Información de esta vista» (líneas 178, 249, 252):** no dicen si son en flujo o superpuestos. Si son en flujo, al abrirse rompen «sin scroll de página».
- **Panel sin selección (línea 203):** no se especifica su contenido.
- **Cambio de breakpoint con el panel abierto:** falta la regla de transición de región no modal a cajón modal (resize o zoom), incluida la activación de la trampa de foco y el traslado del foco.
- **Barra de desplazamiento clásica:** a 1244 px quedan 8 px de holgura, y la barra del cuerpo de la tabla (unos 15 px) no está presupuestada.

[P3] Filtro «Con pendientes» y columna Pendientes
File: spec línea 92; `gestion-diaria-equipo.ts:94`
Problem: el predicado incluye `primer_intento_vencido`, así que una fila puede aparecer en el filtro mostrando Pendientes 0.
Recommendation: el filtro debe usar el mismo predicado que el KPI del servidor, con un test de paridad. La fila debe mostrar el motivo SLA.

[P3] Privacidad del asset
`assets/supervisor-horizontal-aprobado-2026-09-23.png` se versionará. Hay que confirmar que contiene solo nombres y cifras sintéticas; la evidencia adjunta no lo acredita.

TEST GAPS (para H2–H5, no fallos de H1):
- Pendientes con varias páginas más una inserción o reprogramación anterior al cursor: no debe perder filas.
- Orden de Atención por número de motivos, y orden por Vencidas con desempate.
- Cambio de pestaña por acción (aviso o llamadas) sin remontar el Registro ni perder sus filtros.
- Modo individual sin selector de otra persona.
- Error de red del equipo con la persona seleccionada: el encabezado se conserva y no se muestran cifras.
- Fila de postventa o sin anclaje con campos nulos permitidos, sin error de contrato.
- Geometría con «Muestra insuf.» en diez filas y con barra de desplazamiento clásica a 1366 px.
- Transición de breakpoint con el panel abierto (foco y trampa de foco).
- Paridad del filtro «Con pendientes» con `dia.resumen.con_pendientes`.

ARCHITECTURE RISKS:
- La pertenencia al roster (árbol recursivo con puentes inactivos, `equipo_vista.sql:95–106`) se duplicaría en la nueva puerta. Conviene extraerla a una función privada compartida con el equipo para evitar que diverjan.

SECURITY RISKS:
- El diseño es correcto: guard en la puerta y en todo núcleo ejecutable, misma denegación `42501`, sin campos de contacto ni financieros, e invoker con `search_path=''`.
- `tareas_pendientes_core` concede ejecución a authenticated (línea 219). Para la nueva función, se recomienda no conceder el núcleo a authenticated en lugar de solo protegerlo.

REGRESSION RISKS:
- Cambiar los valores por defecto de `RegistroActividad` (`pestanaInicial`, `key`) afecta a las vistas de analista y gerencia. Deben quedarse con sus valores actuales.

RECOMMENDED NEXT ACTIONS:
1. Fijar en la spec la política de refresco de Pendientes con varias páginas y el comparador de Atención y Vencidas.
2. Definir cómo recibe `RegistroActividad` los comandos de apertura (sin `pestanaInicial` en la `key`), el modo individual sin selectores y la instantánea de la persona seleccionada.
3. Enumerar las clases de anclaje y la nulabilidad del ítem de Pendientes, y comprobar los grants de postventa en H3.
4. Dimensionar Ampliar, los desplegables, el panel vacío y el cambio de breakpoint; medir Contacto y la barra de desplazamiento.
5. Confirmar que la captura es sintética.

CONFIDENCE:
MEDIUM. La conclusión sobre postventa y nulabilidad es una hipótesis, y no vi los tests ni el componente de tabla actual.

