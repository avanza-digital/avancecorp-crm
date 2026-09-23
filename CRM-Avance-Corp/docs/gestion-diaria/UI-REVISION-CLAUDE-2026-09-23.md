# Acta de revisión de la mejora visual de Gestión Diaria

23/09/2026. Codex PRIMARY; Claude SECONDARY_REVIEWER, solo lectura.
Clasificación LEVEL 2. Una revisión con dictamen recuperado mediante
`scripts/claude-review`, con protocolos, evidencia de navegación, diff, fuentes
y resultados de pruebas saneados. No se compartieron credenciales ni clientes.

## Dictamen recibido

**VERDICT: CHANGES_REQUESTED. CONFIDENCE: MEDIUM.** Sin P0/P1 demostrados.
Claude validó el estado local de cada fila, las claves por analista y actor/día,
el aislamiento entre personas y el retorno de foco del registro. Señaló tres
P2 accionables, una hipótesis P2 y riesgos P3. El dictamen es asesor y no
sustituye las comprobaciones del PRIMARY.

El primer intento no completó el wrapper en el sandbox. Se repitió con la misma
evidencia fuera del sandbox y se recuperó el informe válido; no fueron dos
revisiones sustantivas ni una consulta repetida para obtener aprobación.
Informe local: `/private/tmp/gestion-diaria-ui-claude-review.txt`.

## Resolución del PRIMARY

| Observación | Decisión y evidencia final |
|---|---|
| P2: foco invisible en alto contraste en Detalle; riesgo equivalente en Ver registro | Aceptada. `FilaDeEquipo` define outline visible y sólido. El E2E de equipo activa `forcedColors`, usa teclado y comprueba estilo y anchura del outline de ambos controles. PASS. |
| P2: vencidas sin énfasis rojo | Aceptada. Se restablecen color destructivo y peso semibold cuando `tareas_vencidas > 0`. No se presupone equivalencia entre vencidas y todos los motivos de atención. |
| P2: nombre ARIA en span genérico de posición | Aceptada. `PanelAhora` usa texto para lectores de pantalla y conserva el número visible. |
| Hipótesis P2: menú recortado por `overflow-hidden` | Verificada la ausencia de portal en `DropdownMenu`. Se retira el recorte del panel y se redondean sus hijos. E2E: Registrar resultado y Ver la ficha completa están completamente dentro del viewport. PASS. |
| P3: título y resumen del plegable sin espacio | Aceptada. Separación explícita entre ambos textos en `Plegable`. |
| P3: aria-label en dl y creación repetida del formateador | Aceptadas. Nombre accesible en grupo contenedor; `Intl.DateTimeFormat` pasa a constante de módulo. |
| P3: selectores ligados al DOM de AccionesContacto | Riesgo acotado aceptado. Se conserva el componente compartido y el estilo queda dentro de PanelAhora; los recorridos de llamada/contacto siguen cubiertos. Si cambia la estructura de ese componente, revisar esta composición. |
| Hipótesis P3: detalle fuera de vista con tabla desplazada | No se añadió desplazamiento programático sin una reproducción. El disparador está en la primera columna y debe estar visible para abrirlo con puntero; el foco del teclado lo lleva a vista. Se preserva el comportamiento de la tabla. El desplazamiento interno del gráfico sí se reproduce y verifica con ArrowRight. No se afirma cobertura del escenario hipotético de apertura con tabla desplazada. |
| Gap: conservar detalle al filtrar fuera y volver | Se acepta el cierre al desmontar la fila: el detalle es una inspección temporal sin datos editables. El mismo analista conserva su estado al reordenar por su key. No se añadió un test que solo repita el mecanismo de estado local. |

## Verificación posterior

- **PASS** `npm run check`: 279 archivos, 4.175 pruebas, lint/typecheck,
  cobertura, build y verificaciones del artefacto.
- **PASS** Docker local, specs de analista y equipo: **13 passed / 0 failed**
  (46,4 s), después de aplicar las correcciones.
- **PASS local** revisión visual en Chrome de ambas vistas.
- **NOT RUN** gate de realidad por falta de las credenciales necesarias.
- **NOT RUN** publicación y smoke de producción de esta mejora.

No se solicitó un segundo dictamen solo para cambiar CHANGES_REQUESTED por PASS.
La resolución y los resultados anteriores son responsabilidad de Codex.
La aceptación humana de la nueva UI y la jornada real de F4 siguen pendientes.
