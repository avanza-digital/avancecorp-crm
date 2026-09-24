# Supervisor horizontal — revisión del plan (23/09/2026)

Claude fue SECONDARY_REVIEWER mediante `scripts/claude-review`; Codex conserva
la responsabilidad del plan. La primera ejecución restringida no produjo
un dictamen; la repetición fuera del sandbox completó esta única consulta.
No hubo herramientas, escrituras ni otra cadena de agentes en el review.

**Dictamen: CHANGES_REQUESTED.** Observaciones sobre decisiones del plan,
no fallos demostrados de una implementación nueva. Confianza MEDIUM;
Claude no inspeccionó FigJam ni ejecutó pruebas. No se registra como PASS.

## Resolución de Codex

| Observación | Decisión incorporada al plan canónico |
|---|---|
| Panel en error del resumen (P1) | Aceptada: panel hermano de la región carga/error/tabla; solo Resumen muestra el fallo. |
| Densidad de 10 filas (P1) | Aceptada: matriz fila/panel, 10 filas solo en contenido típico; textos largos pueden ocupar más. |
| Foco al comparar personas (P2) | Aceptada: permanece en botón de fila; aperturas explícitas lo llevan al panel; tabs separadas. |
| Dos niveles de pestañas (P2) | Aceptada: pestaña de panel y de registro separadas; montar al visitar y conservar oculto durante el mismo contexto. |
| Identidad del día (P2) | Concretada: al cambiar día Lima se limpia selección, además de reiniciar consultas. |
| Ancho del detalle (P2) | Aceptada: columnas por contenedor, mínimo orientativo 380 px, gráfico 08–20 compacto con alternativa textual. |
| Navegación por hash (P2) | Concretada: al salir se cierra la selección; volver inicia sin persona; la ficha superpuesta sí conserva contexto. |
| Fuente de Resumen (P2) | Aceptada: equipoPresentado completo por ID, nunca filas filtradas; error no significa retirada. |
| Selección semántica (P3) | Aceptada: botón con estado accesible y aria-controls; conservar tabla nativa. |
| Registro del equipo (P3) | Concretada: solo Registro, sin tabs individuales; panel ampliable. |

Se añadieron los casos de prueba indicados. El ciclo de foco/selección deberá
centralizarse en el panel o un reducer, evitando efectos acoplados a cualquier
cambio de objeto. No se implementó producto ni se ejecutaron sus pruebas en
esta tarea. Los criterios serán comprobados durante el desarrollo.

Plan vigente: [GESTION-DIARIA.md](GESTION-DIARIA.md), sección «Supervisor horizontal».

## Dictamen íntegro

```text
VERDICT:
CHANGES_REQUESTED

SUMMARY:
El plan acota bien el alcance: no promete un listado de Pendientes sin contrato, no cambia permisos, conserva los E2E en Docker y separa la aprobación visual de la validación del producto. Faltan cuatro decisiones que afectan correctitud y regresiones: dónde vive el panel cuando falla el resumen, qué datos salen de la fila para lograr 10 filas, cómo se separan las pestañas externas de las internas del registro, y cuándo se mueve el foco en un panel persistente. Son cambios al plan, no bugs existentes. No revisé el tablero FigJam porque no hay evidencia adjunta de él.

FINDINGS:

[P1] El panel puede desmontarse en el estado de error del resumen
File: `screens/gestion-diaria/supervisor.tsx`
Lines: 102-108, 159-169
Problem: Hoy el registro está fuera de la `<section>` cuyo contenido cambia por la tarjeta de error (102) o por la carga (108). Por eso sobrevive a un fallo transitorio, y así lo protege el test `supervisor.test.tsx:85`. La Etapa 2 propone un contenedor de dos columnas (tabla más panel). Si el panel queda dentro de la rama que se sustituye, cualquier error o recarga lo desmonta.
Impact: Se perderían los filtros y cursores de `RegistroActividad` y se robaría el foco. Es una regresión directa de un caso ya cubierto.
Recommendation: En la Etapa 1, fijar que el panel es hermano de la región error/carga/tabla, no hijo de ella. Solo la columna izquierda cambia de estado. Con `consulta.error` distinto de 42501, la pestaña Resumen muestra «resumen no disponible» (nunca ceros) y Registro sigue funcionando.

[P1] La meta de 10 filas no es compatible con la fila actual sin sacar datos de ella
File: `components/gestion-diaria/tabla-equipo-diaria.tsx`
Lines: 58-89
Problem: Cada fila tiene hoy `py-5`, nombre `text-lg`, subtítulo, una fila de botones `min-h-11`, tres líneas en Pendientes (82-84) y una lista de motivos (88). Mide aproximadamente 140 px o más. A 805 px de alto hay que restar el shell de la app, la cabecera, los KPI, los filtros con controles de 44 px, el `thead` y la franja de cortes. Quedan aproximadamente 45 px por fila, es decir, una sola línea a 16 px. Además, la Etapa 2 pide «aumentar altura ante varios motivos», lo que contradice esa meta.
Impact: Si no se decide ahora, la implementación recortará texto (lo que viola el criterio de cierre) o no alcanzará las 10 filas.
Recommendation: En la Etapa 1, hacer una matriz de reubicación campo por campo:
- `gestiones_hoy`, `contestadas`, nivel, `primer_intento_vencido` y la lista completa de motivos pasan al panel.
- La fila muestra un solo indicador de atención (por ejemplo, un conteo más el primer motivo, con el texto completo accesible).
- La meta de 10 filas se declara para el caso típico (nombre de una línea, un motivo). La excepción aceptada para nombres largos o varios motivos queda escrita.

[P2] El foco salta en cada cambio de estado del panel
File: `supervisor.tsx`
Lines: 53-55
Problem: `useEffect(() => { if (seleccion) tituloRegistro.current?.focus() }, [seleccion])` se dispara con cada nuevo objeto `registro`. En un panel persistente con pestañas y selección por fila, cambiar de pestaña o de persona llevaría el foco al título. Eso interrumpe la comparación con teclado dentro de la tabla.
Impact: Regresión de accesibilidad y conflicto con «no robar el foco» (Etapa 3).
Recommendation: En la Etapa 1, definir la política de foco:
- Seleccionar a otra persona desde la tabla deja el foco en la fila y anuncia el cambio con `aria-live`.
- Solo las aperturas deliberadas (aviso o «Ver registro del equipo») mueven el foco.
- Cambiar de pestaña sigue el patrón de tabs de ARIA.
- La pestaña activa no debe vivir en el mismo objeto que dispara el foco.

[P2] Colisión entre las pestañas externas y la pestaña interna del registro
File: `supervisor.tsx`
Lines: 8, 28, 81, 166
Problem: `pestana: PestanaRegistro` ya indica la pestaña interna de `RegistroActividad` (`'todo'`/`'llamadas'`), y `key=...:${seleccion.apertura}` remonta el registro en cada apertura. El plan añade Resumen/Registro/Pendientes sin separar ambos niveles. Tampoco dice qué pestaña abre `registroPedido` (81 fuerza `'llamadas'`) ni si Registro se desmonta al ir a Resumen.
Impact: Riesgo de perder cursores al cambiar de pestaña, contra el objetivo de la Etapa 3, y de anidar tablists de forma ambigua.
Recommendation: Modelar `{actor, dia, analista, pestanaPanel, pestanaRegistro, apertura}`. Decidir en la Etapa 1 si Registro permanece montado pero oculto (una sola consulta, conserva el cursor) o si se eleva su estado. Documentar que un aviso abre Registro→Llamadas.

[P2] La selección no incluye el día
File: `supervisor.tsx`
Lines: 28, 40
Problem: El estado guarda `actor` pero no `dia`. La Etapa 1 exige una selección «por actor, día y analista». Al pasar la medianoche de Lima, `hoy` cambia: `RegistroActividad` se remonta por su `key`, pero `seleccion` persiste y el Resumen mostraría a la persona con la fila del nuevo día sin avisar.
Recommendation: Añadir `dia` a la selección y a la comparación de la línea 40. Incluir el cambio de día con el panel abierto en la matriz y en los tests.

[P2] `DetalleAnalista` usa breakpoints de viewport, no de contenedor
File: `components/gestion-diaria/detalle-analista.tsx`
Lines: 18, 39
Problem: `sm:grid-cols-2 lg:grid-cols-4` responden al viewport, así que en un panel de ~30 % (~380-420 px) en escritorio se renderizarían 4 columnas apretadas. Además, 13 barras a `minmax(4.5rem)` suman ~936 px de scroll horizontal.
Impact: Texto recortado o un gráfico poco usable en el panel, contra el cierre de la Etapa 2.
Recommendation: En la Etapa 3, pasar a container queries (`@container`, como ya hace la tabla en la línea 25). Definir el ancho mínimo del panel y la presentación del gráfico 08–20 a ese ancho, sin reducir la fuente.

[P2] La navegación por hash de los avisos descarta la selección
File: `components/gestion-diaria/alertas-del-dia.tsx`
Lines: 27
Problem: `window.location.hash = hashDe(a.destino.vista)` sale de la vista, y la selección es un `useState` local, así que se pierde. La Etapa 3 promete conservar el contexto al volver de la ficha del lead (que funciona como superposición, según la línea 165), pero no dice nada de las navegaciones de avisos ni de «Ver pendientes».
Recommendation: En la Etapa 4, declarar explícitamente que esas acciones no conservan la selección, o especificar cómo se persiste (sin guardar datos de otra identidad).

[P2] La fuente de datos del Resumen es ambigua
File: `supervisor.tsx`
Lines: 36-41
Problem: `DetalleAnalista` requiere `FilaEquipoPresentada`, pero `analista` sale de `dia.equipo` (sin presentar). Si se toma de `filas`, desaparecería cuando un filtro oculta a la persona, lo que contradice la Etapa 1.
Recommendation: Especificar que el panel lee de `equipoPresentado` por `analista_id`, nunca de `filas`.

[P3] Semántica de la selección en la tabla
File: `tabla-equipo-diaria.tsx`
Lines: 56-58
Problem: No hay `role="grid"`, así que `aria-selected` en la fila no es válido.
Recommendation: Usar un botón por fila con `aria-pressed`/`aria-current` y `aria-controls` hacia el panel. Conservar `Th scope` y `aria-sort`.

[P3] Contenido del modo «Registro del equipo»
File: `supervisor.tsx`
Lines: 144, 162
Problem: El plan no dice qué muestran Resumen y Pendientes cuando `analista === null`.
Recommendation: En ese modo, ocultar esas pestañas o mostrar un contenido explícito.

TEST GAPS:
- Error transitorio con el panel abierto en el nuevo layout: equivale a adaptar `supervisor.test.tsx:85`, no solo a mantenerlo.
- Persona seleccionada oculta por un filtro: el panel sigue visible, con la acción de limpiar filtros.
- Cambio de pestaña Registro→Resumen→Registro conservando el cursor.
- Selección con teclado de una fila sin salto de foco, y retorno del foco al cerrar.
- Un `registroPedido` que llega mientras hay otra persona seleccionada.
- Cambio de día Lima con el panel abierto.
- El test de la línea 59 (el detalle horario desaparece si la persona sale del equipo) debe reescribirse sin la expansión de fila, sin perder su aserción.

ARCHITECTURE RISKS:
- `supervisor.tsx` ya concentra selección, foco, avisos y estados. Añadir panel y pestañas ahí aumenta el acoplamiento. Conviene extraer un reducer de selección o un componente `PanelAnalista`, con los invariantes de actor y día centralizados.

SECURITY RISKS:
- Sin cambios de permisos. Hay que mantener el orden actual: `fueraDeAmbito` se evalúa antes de pintar (`useLayoutEffect`, 46-52), `permitirExportar={false}` se conserva y no se derivan listas de Pendientes desde el store. El plan ya lo recoge.

REGRESSION RISKS:
- Desmontaje del panel en error o recarga (P1).
- Salto de foco en cada selección (P2).
- Pérdida de la acción «Ver llamadas del día» (`detalle-analista.tsx:62`) al mover el detalle.

RECOMMENDED NEXT ACTIONS:
1. Añadir a la Etapa 1:
   - la jerarquía de montaje del panel respecto a la región de error y carga;
   - la política de foco;
   - el modelo de estado `{actor, dia, analista, pestanaPanel, pestanaRegistro}`.
2. Añadir a la Etapa 1 la matriz de reubicación de campos fila→panel, y declarar la meta de 10 filas como caso típico con la excepción documentada.
3. Añadir a la Etapa 3 la migración de `DetalleAnalista` a container queries y la fuente `equipoPresentado`.
4. Añadir a la Etapa 4 el comportamiento de la selección ante navegaciones por hash.

CONFIDENCE:
MEDIUM. El análisis del código es directo. La factibilidad en píxeles es una estimación, porque no se adjuntaron las medidas del shell ni `RegistroActividad`.

```
