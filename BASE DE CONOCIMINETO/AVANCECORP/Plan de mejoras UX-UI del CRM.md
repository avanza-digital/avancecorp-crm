# Plan de mejoras UX/UI del CRM

Plan por fases para aplicar los fundamentos UX/UI (más allá de Gestalt y color) al CRM. Cada fase entrega algo visible y sirve de base para la siguiente. Pantallas de referencia: Hoy, Agenda, Pipeline, Mi Cartera, Repartir, Derivaciones, Gerencia y los flujos de lead-drawer / contrato-nuevo.

**Plan específico de Gerencia:** [[Plan de mejora UX de Gerencia - revision 2026-09-05]] recupera su PDF por rol y actualiza prioridades, fases y validación. Es el seguimiento de experiencia del usuario de Gerencia; el plan de corrección de métricas conserva su propio alcance.

## Lo que ya está a favor

- **Role-Based UX ya existe**: vistas por rol (vendedor, supervisor, gerencia, config de admin).
- **Agente `revisor-a11y`**: la accesibilidad ya tiene revisor automático.
- **UI Playground** (`../ui-playground/`): laboratorio para microinteracciones y motion antes de tocar el CRM.
- Vault con decisiones de negocio → insumo directo para Jobs To Be Done y user flows.

## Fase 0 — Auditoría y línea base (1 semana, sin tocar código)

1. Pasar el **checklist de heurísticas de Nielsen** sobre las 5 pantallas más usadas: Hoy, Mi Cartera, lead-drawer, contrato-nuevo, Agenda. Anotar cada incumplimiento como issue.
2. Medir la **línea base de fricción**: contar clics y pasos de las 3 tareas más frecuentes del vendedor (registrar interacción con un lead, agendar seguimiento, crear contrato).
3. Una **prueba de usabilidad informal**: darle a un vendedor real una tarea ("busca este cliente y agéndale un seguimiento para mañana") y solo observar dónde se traba.

Salida: lista priorizada de problemas reales, no supuestos.

## Fase 1 — Design system mínimo (los tokens)

Formalizar en el código lo que hoy es implícito:

- **Colores semánticos**: primary, success, warning, danger, neutral. Regla: un significado = un color en todo el CRM.
- **Escala tipográfica**: 4 tamaños con roles fijos (título de pantalla, título de sección, cuerpo, etiqueta/dato secundario) con peso y line-height definidos.
- **Escala de espaciado**: 4/8/12/16/24/32/48 px; prohibidos los valores arbitrarios.
- **Estados obligatorios por componente**: default, hover, focus, disabled, loading, error, empty.

Documentar como nota del vault + tokens en el código (Tailwind config / CSS vars). Todo lo posterior se apoya aquí.

## Fase 2 — Jerarquía y tipografía en las pantallas clave

Aplicar los tokens pantalla por pantalla, en orden de uso: Hoy → Mi Cartera → lead-drawer → Agenda → Pipeline.

- En cada pantalla decidir **qué se mira primero, segundo y tercero** (para el vendedor: próximo contacto y monto antes que metadatos).
- Reducir ruido: si todo destaca, nada destaca. Bajar contraste de lo secundario en vez de subir el de lo primario.
- **Scannability**: bloques, etiquetas y chips consistentes para que la pantalla se escanee, no se lea.

## Fase 3 — Tablas y formularios (donde vive la productividad)

**Tablas** (Cartera, Pipeline, Derivaciones, Repartir):
- Ordenamiento y filtros consistentes en todas; filtros guardados si hay demanda.
- Columnas: lo accionable primero; estados con chip + texto (no solo color).
- Acciones por fila: 1 primaria visible + menú «⋯» para el resto (Ley de Hick).

**Formularios** (lead-nuevo, cliente-form, contrato-nuevo):
- **Progressive disclosure**: primero los 4–6 campos que cierran el 80 % de los casos; el resto bajo «+ Información adicional».
- Valores por defecto inteligentes, buscar-y-seleccionar en vez de códigos (reconocimiento sobre recuerdo).
- **Prevención de errores**: fechas imposibles no seleccionables, validación en línea antes del submit.

## Fase 4 — Feedback y estados del sistema

- Toda acción de guardado: Guardando… → Guardado ✓ (o error claro con qué hacer). Nunca dejar la duda de «¿funcionó?».
- **Skeletons** en cargas de tablas y detalle; **empty states** con acción («Todavía no tienes leads hoy → Revisar cartera») en vez de texto seco.
- **Deshacer** en acciones destructivas frecuentes (descartar lead, anular) como alternativa al confirm-modal.
- Mensajes de error en UX writing: qué pasó + qué hacer, nunca códigos.

## Fase 5 — Flujos y productividad

- Mapear los **user flows** completos (lead → calificar → oportunidad → seguimiento → cierre → contrato) y recortar pasos: la métrica es clics por tarea vs. la línea base de la Fase 0.
- **Acciones rápidas** desde donde el usuario ya está (llamar/registrar/agendar desde la fila o el hover-card, sin abrir el detalle).
- Atajos de teclado y, si escala, command palette. Microinteracciones se prototipan en el UI Playground y se promueven aprobadas.

## Fase 6 — Accesibilidad y validación continua

- Pasar `revisor-a11y` como gate de toda pantalla tocada; contraste WCAG, foco visible, navegación por teclado.
- Repetir la prueba de usabilidad de la Fase 0 con las mismas tareas y comparar: tiempo, clics, errores.
- Instrumentar 2–3 **métricas UX** en el propio CRM (task completion, clics por tarea, adopción de funciones) para que el ciclo no dependa solo de opiniones.

## Reglas transversales (desde la Fase 1)

1. **Consistencia**: mismo botón, misma posición, mismo significado en todo el CRM.
2. **Ley de Jakob**: patrones conocidos (lupa=buscar, engranaje=config); nada de reinventar.
3. **Modelo mental del vendedor**: la UI habla de clientes y seguimientos, nunca de IDs ni de la estructura de la base.
4. **Carga cognitiva**: cada pantalla responde una sola pregunta («¿a quién contacto hoy?», «¿cómo va mi cartera?»).
5. Cambio visual nuevo → primero al [[UI Playground (laboratorio de animaciones)]], luego se promueve.

## Orden de impacto si solo se puede hacer una cosa a la vez

1. Fase 0 (medir) → 2. Tokens (Fase 1) → 3. Hoy + Mi Cartera (Fase 2) → 4. Formulario de contrato (Fase 3) → 5. Feedback de guardado (Fase 4).

Relacionado: [[Acceso y roles del CRM]] · [[Centro de ayuda del vendedor]] · [[Navegacion compacta de Agenda y Pipeline 2026-08-20]]

## Marco integral acordado — 2026-08-23

La mejora del CRM se evaluará como un sistema completo de experiencia, no como una pasada cosmética. El marco queda organizado en ocho pilares inseparables:

1. **Psicología y percepción:** Gestalt, atención visual, carga cognitiva y modelos mentales.
2. **Fundamentos visuales:** tipografía, color, espaciado, grid, jerarquía e iconografía.
3. **Arquitectura UX:** arquitectura de información, navegación, Jobs To Be Done, user flows, diseño por tareas y por rol.
4. **Interacción:** affordances, signifiers, feedback, estados, progressive disclosure, microinteracciones y motion funcional.
5. **Leyes y heurísticas:** Hick, Fitts, Jakob, reconocimiento sobre recuerdo y heurísticas de Nielsen.
6. **Componentes profesionales:** tablas, formularios, dashboards, filtros, búsqueda, navegación y design system gobernado.
7. **Accesibilidad:** contraste, teclado, foco, semántica, lectores de pantalla, targets y comunicación que no dependa solo del color.
8. **Validación:** tareas de usabilidad, Task Completion Rate, Time on Task, Error Rate, Clicks per Task, Adoption Rate y Feature Discovery.

### Guardrails de aplicación

- **Reducir carga cognitiva no significa eliminar datos profesionales:** primero se agrupan, jerarquizan y revelan según contexto.
- **Las leyes UX son heurísticas, no mandatos rígidos:** la densidad y rapidez de un usuario experto pueden justificar más opciones si pasan pruebas de tarea.
- **La personalización llega después de un buen valor por defecto:** habilitarla demasiado pronto fragmenta producto, soporte y QA.
- **Heatmaps y eventos complementan las pruebas de usabilidad:** no reemplazan observar tareas y requieren minimización de datos y revisión de privacidad.
- **Accesibilidad es gate de release:** no una auditoría opcional al final.
- **El design system incluye gobierno:** tokens, anatomía, estados, documentación, contribución, pruebas visuales, deprecación y medición de adopción.
- **Gramática cromática local:** azul comunica acción confiable o estado saludable; rojo intervención inmediata; ámbar atención próxima; navy y neutros estructuran; violeta y cian identifican categorías o series. No se introduce verde como éxito si rompe la semántica ya acordada.

### Planes independientes por usuario

Se generaron planes de diez páginas para vendedor, supervisor, gerencia, directorio y coordinador. Cada uno contiene contrato de experiencia, ocho pilares aplicados, JTBD, modelo mental, flujo, leyes cognitivas, fases, mapa de superficies, componentes y estados, accesibilidad, tareas de usabilidad, métricas, riesgos y gate de salida.

Los artefactos viven en `output/pdf/plan-ux-<rol>-crm-avance.pdf` y se apoyan en [[Acceso y roles del CRM]] y [[Pasada de UX del CRM 2026-07-17]].

## Huecos detectados en la investigación base — 2026-08-23

La investigación de fundamentos UX/UI es completa y bien priorizada, pero para este CRM en concreto le faltan seis áreas. Se incorporan al plan como temas de primera clase:

1. **Móvil y touch.** Los vendedores usan el CRM en campo desde el celular. Falta diseñar: targets táctiles de al menos 44 px, gestos, comportamiento responsive de las tablas (la tabla de desktop no sobrevive en móvil) y qué se recorta en pantalla chica. Se integra en las Fases 2 y 3: cada pantalla clave se revisa también en viewport móvil.

2. **Red inestable y offline.** Qué pasa cuando falla la conexión: reintentos, guardado optimista (optimistic UI), indicador visible de "sin conexión" y nunca perder un formulario a medio llenar. Para un vendedor en la calle pesa más que varios puntos clásicos de la lista. Se integra en la Fase 4 (feedback y estados).

3. **Umbral de Doherty y performance percibida.** Si el sistema responde en menos de ~400 ms la productividad se dispara. Con Supabase esto significa respuestas optimistas y caché, no solo spinners y skeletons. Se integra en la Fase 4.

4. **Ley de Tesler (conservación de la complejidad).** La complejidad de un contrato o una derivación no desaparece: solo se decide quién la absorbe, el sistema o el usuario. Es el antídoto contra simplificar de más un CRM profesional al aplicar "carga cognitiva". Se suma a las reglas transversales.

5. **UX de permisos y roles.** No basta con vistas por rol: hay que diseñar qué ve el usuario cuando NO puede hacer algo — ¿botón oculto, deshabilitado con tooltip que explica por qué, o error al intentar? Con RLS activo, la opción no diseñada genera confusión real. Se integra en la Fase 2 al revisar cada pantalla por rol.

6. **Notificaciones e interrupciones.** El CRM tiene Alertas y SLA, y falta criterio de cuándo interrumpir vs. acumular, prioridad entre alertas y prevención de fatiga de notificaciones. Se trata como tema propio dentro de la Fase 5.

### Mejoras menores a la investigación

- **Fuentes para estudiar:** Nielsen Norman Group (nngroup.com), lawsofux.com, Refactoring UI, WCAG 2.2.
- **Esfuerzo vs. impacto en el top-15:** saber qué es barato (tokens, feedback de guardado) frente a lo caro (rediseño de arquitectura de información) cambia el orden real de ejecución. Primer corte: baratos y de alto impacto → tokens (F1), feedback de guardado (F4), empty states (F4); caros → arquitectura de información, rediseño de tablas responsive.
