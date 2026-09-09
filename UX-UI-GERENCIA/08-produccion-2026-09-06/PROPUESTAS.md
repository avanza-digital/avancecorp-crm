# Propuestas UX/UI sobre el CRM en producción · 6 de septiembre de 2026

Base: capturas del commit vivo (`96f2038`) en modo demo, tres roles (carpetas `gerencia/`, `analista/`, `supervisor/`, `analista-movil/`), contrastadas con el playbook `UI-UX.pdf` (8 pilares, tokens, fases 0–6, checklist por pantalla). Sin considerar Figma ni el plan anterior.

## Lo que ya está bien y no se toca
- Hoy del analista y del supervisor absorben la complejidad (Tesler): el sistema prioriza y redacta el motivo; la persona solo actúa.
- Estados vacíos con acción en Mi cartera («Ver toda la cartera») y aviso «Faltan correo, DNI y nota · Completar» en la ficha.
- Atajos de teclado en Agenda; llamada y WhatsApp a un clic desde la fila (Fase 5 ya aplicada).

## Propuestas, en el orden de impacto del playbook (§9)

0. **Medir antes de tocar (Fase 0, sin código, 2 días).** Contar clics y tiempo de las 3 tareas más frecuentes: registrar resultado de una llamada, crear un lead, derivar un lead. Observar a un analista real 20 minutos sin explicarle nada. Checklist de Nielsen sobre Hoy, Leads, Agenda, Nuevo lead y Cartera.
1. **Tokens (Fase 1).** Dos tipografías conviven (Plus Jakarta Sans en el CRM, IBM Plex Sans en Resumen/Conversiones/Ranking): Gerencia parece otro producto. El color no es semántico: verde/ámbar por puesto en Ranking, cinco colores por etapa en Leads y Pipeline, teal/verde decorativos en KPI. Formalizar 5 colores con significado fijo, 4 tamaños de texto, escala 4/8/12/16/24/32/48 y unificar la fuente.
2. **Jerarquía en Conversiones (Fase 2).** Repite el hero de Resumen y luego tres paneles de texto técnico («aporte 1.15», «núcleo», «elegible no significa elegida»). Una pregunta por pantalla: «¿cuánto convertimos y quién?»; la fórmula detrás de «¿Cómo se calcula?».
3. **Nuevo lead (Fase 3, formulario).** 13 campos; los obligatorios Origen y Capital quedan después de Género, Fecha de nacimiento, Correo y Distrito. Primero los 4 que cierran el lead (Nombre, Teléfono, Origen, Capital), el resto en «Más datos»; validación en línea del teléfono.
4. **Cartera (Fase 3, tabla).** Cuatro botones por fila (Gestionar, Ver detalle, Corregir, Registrar primera inversión). Una acción primaria según el estado del cliente y menú «…» para las demás.
5. **Estados no diseñados (Fase 4 y tema 5).** Derivar leads en demo muestra «—» en tres KPI y «carga un reporte válido» sin decir cómo; Resultados por origen deja un panel vacío al 70 % con «cifras ocultas». Cada bloqueo dice qué pasó y qué hacer; el panel sin datos se colapsa.
6. **Móvil (tema 1).** Barra lateral de solo iconos (recuerdo, no reconocimiento), el título de pantalla se pierde («Tu si…»), «Nuevo lead» domina la cabecera. Barra inferior con 4–5 destinos etiquetados, título visible, alta de lead como acción flotante.
7. **Ranking.** El color por puesto (verde 01–03, ámbar 04) se lee como cumplimiento. Un color y una columna explícita de meta si se quiere juzgar.

Cada propuesta se valida con el checklist de la §7 antes de darse por buena y se mide contra la línea base de la propuesta 0.
