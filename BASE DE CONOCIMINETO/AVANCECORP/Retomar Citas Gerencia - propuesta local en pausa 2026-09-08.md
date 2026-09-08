# Citas de Gerencia — propuesta local retomada y verificada

Miguel pidió mejorar comercialmente la presentación del módulo de Citas, hacerlo accesible y ofrecer todos los filtros posibles, con propuestas en local. Después pidió parar y luego **«sigamos»**. La propuesta se retomó y quedó verificada. También pidió hacer commit de los cambios de este trabajo; se incluyen únicamente los archivos propios. No publicar.

## Cierre después de retomar

- **10/10 pruebas PASS**, sintaxis y lint específico sin avisos.
- Se corrigió el banco de JSDOM con dobles de `showModal`/`close` para contenido y navegación. El foco/Escape se comprobaron en Chrome. Se cerró un escape faltante en el contexto del detalle de una cita realizada y se agregó su regresión.
- Chrome: filtros compartidos, detalle hacia Agenda, foco inicial y regreso al cerrar con Escape, Tab dentro del diálogo y cambio de pestaña con flecha derecha. Móvil a 390 px CSS sin desbordamiento horizontal.
- Propuesta lista en `http://127.0.0.1:4178/citas-gerencia.html`; servidor local de la sesión activo al entregar. Pestaña conservada y viewport restaurado.
- Capturas ficticias, instrucciones y evaluación final del review en `UX-UI-GERENCIA/propuesta-citas-local-2026-09-08/README.md`.
- **NOT RUN:** build/gate integral y E2E del CRM, porque el prototipo es independiente de su runtime. **NOT RUN:** auditoría completa con lector de pantalla; no afirmar conformidad completa de accesibilidad.
- Pendiente posterior: elegir ajustes comerciales y conectar una consulta autorizada de citas reales. El prototipo no constituye esa integración.

## Avance guardado

- Propuesta navegable: `CRM-Avance-Corp/app/prototypes/citas-gerencia.html`.
- CSS, JavaScript, modelo, pruebas, iconos Lucide y fuentes IBM Plex locales en `CRM-Avance-Corp/app/prototypes/citas-assets/`.
- URL de la sesión: `http://127.0.0.1:4178/citas-gerencia.html`. Servidor Python limitado a `CRM-Avance-Corp/app/prototypes`, enlazado a 127.0.0.1; sesión de ejecución 89048. Si ya no corre: desde la raíz, `python3 -m http.server 4178 --bind 127.0.0.1 --directory CRM-Avance-Corp/app/prototypes`.
- Tres vistas complementarias: Bandeja comercial (recomendada), Agenda por día y Resultados por analista. Botón «Las 3 propuestas» explica y abre cada una.
- Filtros compartidos: búsqueda por prospecto/teléfono/código; supervisor; analista; fecha prevista/presets/rango; varios estados; modalidad; origen; resultado; seguimiento; moneda y monto mínimo/máximo. Orden, paginación, etiquetas removibles, restablecimiento y CSV de todas las citas filtradas.
- Detalle en diálogo con fecha, responsable, estado, contexto y siguiente paso; enlaces funcionales a las citas del analista y a Agenda. Solo lectura.
- **40 citas ficticias**, corte fijo 7 septiembre 2026 a las 13:00 Lima. No representa datos reales ni nuevas fórmulas comerciales. La pantalla identifica el ejemplo.
- No se editaron los componentes reales de Citas ni el backend. El commit local fue solicitado al retomar; no se hace push ni deploy. El working tree contenía mucho trabajo previo, que se conservó.

## Motivo del alcance local

Se inspeccionó Citas real en Chrome, ruta `https://crm.miavance.com/#/reuniones`. La pantalla concentra indicadores grandes y deja la tabla por analista lejos de la primera vista. La consulta consumida por `ReunionesGerenciaPanel` entrega agregados (`resumen`, `responsables`, `modalidades`, `origenes`, `conversion`), no las filas por cita necesarias para todos los cruces propuestos. Se informó a Miguel que la propuesta sería navegable con ejemplos y que conectar el detalle real es un trabajo posterior. No inventar filtros sobre agregados independientes ni cambiar bases de realización/asistencia.

CodeGraph se usó primero, pero devolvió símbolos ajenos/incompletos; se complementó con lecturas dirigidas. Se leyeron las notas comerciales de Citas y las reglas de colaboración/verificación.

## Historial de verificación anterior a la pausa

1. Primera versión: 10/10 pruebas Node aprobadas, sintaxis JS y lint específico sin errores.
2. Navegador: bandeja, diálogo, cierre con Escape, filtro supervisor + virtual + vencida/programada (dos citas correctas), conservación de filtros en Agenda, tabla de Resultados y selector de propuestas comprobados. Móvil a **390 CSS px efectivos**, sin desbordamiento horizontal. El navegador tenía una escala que exigía viewport 312 para obtener 390 CSS px; se restablece el override al pausar.
3. Evidencia/capturas y review: `/private/tmp/citas-gerencia-ux/`. `02-bandeja.png` y `03-propuestas.png` son capturas limpias de escritorio; `01-antes.png` contiene la pantalla real y datos internos. Otras capturas móviles incluyen espacio extra del mecanismo de captura; no presentarlas como capturas finales pulidas.
4. Claude se consultó una vez con `scripts/claude-review`, solo lectura y evidencia ficticia. Primer intento restringido no terminó; el reintento autorizado terminó con `CHANGES_REQUESTED`. Dictamen en `review-claude.txt`; prompt en `review-input.txt`. No repetir una consulta general.
5. Evaluación del PRIMARY: la hipótesis de colisión con Vitest **se descartó con evidencia**: `vitest.config.ts` incluye solo `src/**/*.test.{ts,tsx}`, TS incluye `src`, Vite entra por el index del CRM. JSDOM ya existía como dependencia de desarrollo; no se cambiaron package.json/lockfile. El supuesto fallo de `[hidden]` también se descartó: CSS ya tiene `[hidden]{display:none!important}` y se añadió comprobación de estilo calculado. No afirmar que Claude aprobó la versión corregida.
6. Ajustes aplicados tras review: escape de valores en filas/agenda/resultados/detalle; asociación de campos inválidos con su error; actualización de textos accesibles solo cuando cambian y demora de 250 ms para avisos de búsqueda/montos/fechas; región permanente para anunciar exportación; atajos muestran «—» ante consulta inválida; validación de fechas ISO reales; protección CSV ante espacios iniciales; singular/plural y orden de fechas más claro. Los presets siguen fijos por tratarse de un escenario fijo; CSV conserva coma estándar (la recomendación sobre separador de Excel era dependiente de configuración, no un hecho demostrado).
7. Al pausar, hubo 9/10 pruebas aprobadas y 1 FAIL porque JSDOM no implementa `HTMLDialogElement.showModal`. **Resuelto al retomar**, como se documenta en el cierre superior; no queda una prueba fallida pendiente.

Comando del banco, desde `CRM-Avance-Corp/app`:

```sh
node --test prototypes/citas-assets/citas.test.mjs
```

Comprobación y entrega visual cerradas al retomar. El juicio final del PRIMARY sobre el review y sus límites están documentados en el README de la propuesta. No afirmar integración al CRM ni aprobación posterior de Claude.

Relacionadas: [[Inicio]], [[Citas de Gerencia - correcciones comerciales y bases 2026-09-07]], [[Auditoria de Citas de Gerencia - frontend y contrato backend 2026-09-07]], [[Terminologia de citas en el CRM]], [[Decisiones UI UX Gerencia - 2026-09-06]].
