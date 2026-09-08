# Citas de Gerencia adaptadas al CRM — propuesta local

Fecha: 2026-09-08. Continuación de la [primera propuesta](../propuesta-citas-local-2026-09-08/README.md), guardada en `328bbc5`.

Abrir: **http://127.0.0.1:4180/prototypes/citas-crm.html**.

Si el servidor está cerrado, ejecutar desde `CRM-Avance-Corp/app`:

```bash
npm run dev -- --host 127.0.0.1 --port 4180 --strictPort
```

## Alcance

Propuesta independiente con 40 citas ficticias y corte fijo al 7 de septiembre de 2026, 13:00 Lima. Reutiliza los componentes reales `BrandLockup`, `Button`, `Card`, `Input`, `Select`, `Badge` y `Sheet`, los formatos monetarios y de fecha, las fuentes, los recursos de marca y los tokens del CRM. El estilo adicional vive solo en la entrada de la propuesta.

No reemplaza `ReunionesGerenciaPanel`, no consulta APIs, no registra ni reprograma citas reales y no se publicó. La integración con datos reales sigue pendiente. El promedio se atribuye al analista asignado a cada cita del ejemplo; no demuestra quién creó el registro.

## Cambios pedidos durante la revisión

- «Tu consulta» compacta: búsqueda, supervisor, analista, mes, semana y reinicio en una fila de escritorio. Los demás filtros se despliegan en «Más filtros».
- La franja superior muestra información complementaria: leads con cita, citas por lead, leads con dos o más citas e inasistencias reprogramadas. Se retiraron los conteos de citas duplicados; se conservan abajo, junto a los filtros por estado.
- Mes con cuatro semanas comerciales: días 1–7, 8–14, 15–21 y 22–último día. Son tramos del mes, no semanas ISO. La cuarta incluye 29, 30 y 31 cuando corresponde. El ejemplo permite los doce meses de 2026.
- Promedio por asesor y detalle por lead con identidad estable.
- Seguimiento de inasistencias hasta la nueva cita y su resultado.
- Guía dentro de «Cómo usar Citas», tres vistas coordinadas, exportación, teclado y ficha lateral del CRM.

## Cómo usarlo

1. Elegir mes y semana; después supervisor o analista. La selección se aplica inmediatamente. La búsqueda acepta prospecto, teléfono o código de cita.
2. Usar «Sin resultado», «Programadas», «Realizadas» o «No asistieron» para revisar una situación. «Más filtros» permite varios estados, modalidad, origen, resultado, seguimiento y monto. Para comparar importes hay que elegir una moneda; cambiarla limpia los límites previos.
3. Cambiar entre Bandeja comercial, Agenda y Resultados conserva la consulta. La Bandeja tiene orden y páginas; la Agenda mantiene orden cronológico de Lima.
4. En Resultados, «Por lead» abre las cantidades individuales del asesor. «Ver citas» filtra ese lead manteniendo el contexto consultado.
5. En seguimiento de inasistencias, pulsar una etapa para ver sus casos. El nombre abre la cita original; la flecha de la derecha abre la nueva cita vinculada.
6. Desde la ficha, «Ubicar en agenda» abre esa cita; «Citas de…» abre todas las citas del asesor en el mes de la ficha. Ambas acciones restablecen los demás filtros para que una cita futura no quede oculta por el filtro de inasistencias o por otra semana.
7. Las etiquetas permiten quitar filtros individualmente. «Restablecer consulta» vuelve al mes del ejemplo. El CSV descarga todas las citas coincidentes, aunque estén en otra página; no es una exportación de la tabla de promedios ni de la cadena de recuperación.

## Significado de los indicadores

**Citas por lead = número de citas filtradas / leads distintos con al menos una cita filtrada.** No incluye leads sin cita y no mide asistencia. Si la consulta incluye canceladas, esas citas también forman parte del promedio. Sin leads, se muestra «—».

El total usa identificadores únicos del conjunto, no la suma de leads por asesor ni el promedio de sus promedios. Un lead con citas de dos asesores cuenta para ambos asesores y una sola vez en el total. Lo mismo exige recalcular los leads con dos o más citas sobre el conjunto.

Ejemplo completo: 40 citas / 26 leads = 1.54 citas por lead; 10 leads tienen varias citas. Ana Torres: 7 citas / 4 leads = 1.75. «Por lead» permite comprobar cada numerador.

**Inasistencias reprogramadas** parte de las citas que no asistieron dentro de la consulta. Sigue únicamente relaciones explícitas `citaAnteriorId`, del mismo lead y conocidas al corte. La cita siguiente puede estar fuera del mes o semana. No basta encontrar otra cita del mismo prospecto.

Ejemplo: 4 inasistencias, 3 reprogramadas, 1 que llegó a asistir, 2 nuevas citas pendientes y 1 sin nueva cita. Los casos originales se conservan. Cada inasistencia se cuenta una vez dentro de la cohorte; varias inasistencias sucesivas pueden ser episodios separados. Si hubiera varias sucesoras, el ejemplo sigue la de registro más reciente y desempata por id. Esta regla deberá conciliarse con el contrato real antes de integrar.

## Verificación

- **PASS** `npm run lint`: sin errores; cuatro advertencias existentes en `coverflow-carousel.tsx`.
- **PASS** `npm run typecheck`.
- **PASS** `npm run test:run`: 3.079 tests, 214 archivos; incluye 13 tests de esta adaptación. Se cubren filtros compartidos, estados, moneda, vacío, navegación, retorno de foco, exportación completa, promedio, identidad de leads, límites de los meses y relaciones de inasistencia.
- **PASS** `npm run build`: build del CRM. Conserva advertencias existentes sobre `demo-config.ts` y tamaño de chunks. La entrada independiente se validó con Vite en desarrollo y navegador; no es un artefacto publicado.
- Revisión independiente de Claude: `CHANGES_REQUESTED`, evaluada por Codex. Correcciones y recomendaciones descartadas con evidencia: [evaluación](evaluacion-revision.md). El dictamen original no equivale a aprobación final ni reemplaza los checks.
- Navegador Chrome: consulta, resultados por asesor, ficha por lead, filtro individual y navegación de una reprogramación hacia Agenda comprobados. Sin desbordamiento horizontal a 390 px y en escritorio. A 1.227 px, el bloque de consulta ocupa aproximadamente 110 px y la franja de indicadores 53 px.
- En móvil se comprobó disposición y límites de la ficha, incluido su botón de cierre dentro del viewport. El control automatizado de pestañas durante la emulación presentó timeouts; no se declara una prueba táctil completa.
- **NOT RUN** `npm run check` / `check:all`, cobertura integral y E2E de producción: gate proporcional de frontend ejecutado con los cuatro comandos anteriores; esta entrada local no cambia navegación ni roles del CRM real.
- **NOT RUN** lector de pantalla real y matriz de navegadores/dispositivos; no se declara certificación de accesibilidad.
- **NOT RUN** base de datos/RLS: no hay cambios de datos o backend en este bloque.

Capturas de datos ficticios: [consulta móvil](01-consulta-movil.png), [resultados y seguimiento](02-resultados-escritorio.png), [detalle por lead móvil](03-detalle-leads-movil.png). La emulación y el zoom del navegador añaden margen a las capturas; las medidas anteriores son del viewport CSS observado.

## Archivos

- Entrada: `CRM-Avance-Corp/app/prototypes/citas-crm.html`.
- Componentes y lecturas del ejemplo: `CRM-Avance-Corp/app/src/prototypes/citas-crm/`.
- Declaración de tipos del modelo original: `CRM-Avance-Corp/app/prototypes/citas-assets/model.d.mts`.
- El JavaScript y HTML de la primera propuesta permanecen intactos.

La integración real deberá disponer de citas individuales, ids estables, responsable y relaciones de reprogramación; no se pueden fabricar cruces independientes a partir de los agregados actuales del panel.
