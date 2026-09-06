# Auditoría UX de reportes para Gerencia

5 de septiembre de 2026 · CRM Avance Corp · revisión experta e investigación de buenas prácticas.

**Conclusión:** la prioridad es facilitar el recorrido desde un resultado hasta su explicación y la acción correspondiente. Las principales oportunidades están en la jerarquía del resumen, la claridad de las bases de comparación, la continuidad de navegación y la cabecera móvil. Existen patrones útiles que conviene extender: tablas con denominadores, exclusiones explicadas, atención y capacidad por analista, y una entrada explícita a administrar metas.

El [plan vigente de Gerencia](../../BASE%20DE%20CONOCIMINETO/AVANCECORP/Plan%20de%20mejora%20UX%20de%20Gerencia%20-%20revision%202026-09-05.md) contiene las fases, entregables y criterios de cierre. Este informe conserva la evidencia que lo sustenta.

## Alcance y método

Se recorrió la aplicación local con el rol **Gerencia demo**, en escritorio de 1440 × 960 y ancho móvil de 390 × 844. Se inspeccionaron las capturas guardadas, el DOM y algunas interacciones. Se consultó primero CodeGraph para localizar código y se contrastó el rol con el conocimiento del proyecto. El recorrido se pausó por indicación de Miguel y se reanudó en la misma auditoría.

Un intento de acceso a producción no permitió entrar. Por ello, **las observaciones corresponden a la versión local y a datos sintéticos**. Las diferencias entre cantidades de ejemplo no prueban errores de cálculo en producción. El modo demo limita filtros y edición. El árbol de trabajo recibe cambios concurrentes; al reanudar, la referencia local era `4abebb8`, con trabajo adicional en curso. No se presenta esta captura como un artefacto inmutable de ese commit.

Se guardaron 14 capturas. El CRM utiliza scroll interno: son vistas del área visible, no imágenes de toda la longitud de cada pantalla. Las capturas 04, 06 y 10 se renovaron después de descartar versiones en transición. Se volvió a inspeccionar cada archivo aceptado.

No se entrevistó ni observó trabajar a una persona de Gerencia. No se midieron tiempos de tarea, rendimiento de producción, lectores de pantalla ni cumplimiento completo de WCAG. No se hicieron cambios comerciales, modificaciones de código de la aplicación ni publicaciones.

## Análisis del usuario

Gerencia tiene responsabilidad global de consulta y operación comercial. El diseño debe acompañar tres niveles: **revisar el negocio, investigar un resultado y actuar sobre su causa o responsable**. El rol no se reduce a leer un tablero ejecutivo.

| Tarea propuesta para validar | Pregunta que la interfaz debe responder | Información necesaria |
| --- | --- | --- |
| Revisar resultados | ¿Cómo vamos y qué merece revisión? | Resultado, objetivo vigente, período, ámbito y estado del dato. |
| Entender una diferencia | ¿Qué población y fecha explican este porcentaje? | Base, numerador o aporte, exclusiones, atribución y acceso al detalle. |
| Comparar responsables | ¿Quién produce, con qué base y con qué carga? | Métricas equivalentes, denominadores y capacidad actual claramente distinguida. |
| Intervenir | ¿Qué casos revisar y qué acción existente corresponde? | Casos, responsable, alcance y resultado de la acción. |
| Preparar una reunión | ¿Puedo explicar y volver a esta misma consulta? | Contexto visible, definición, filtros y corte de la información. El formato de salida está por validar. |

La frecuencia de estas tareas, el uso real del celular y el formato de los reportes son hipótesis. Deben contrastarse con Gerencia. Observar tareas reales complementa este recorrido experto; NN/g advierte que entrevistas y simulaciones por sí solas pueden omitir aspectos del trabajo cotidiano. [NN/g: análisis de tareas](https://www.nngroup.com/articles/task-analysis/).

## Recorrido y evidencia

### 1. Resumen de escritorio — mejorable

![Paso 1. Resumen con cifras repetidas entre la cabecera y las tarjetas](01-resumen-escritorio.png)

**Funciona:** período, ámbito y desglose de moneda visibles; enlace explícito a Ranking. **Fricción:** conversión, capital y citas aparecen en la cabecera y vuelven a ocupar una fila de tarjetas. Los compromisos de supervisores quedan más abajo, según el DOM. Trece destinos de análisis y operación comparten el grupo «Principal». **Propuesta:** una única presentación de cada indicador principal, seguida de asuntos verificables y enlaces a su evidencia. Revisar agrupación del menú por tareas. **Accesibilidad:** verificar contraste de las etiquetas pequeñas y alternativa de datos de los gráficos; su apariencia no acredita un incumplimiento medido.

### 2. Ranking de conversión — buena base para comparar

![Paso 2. Ranking con base, cierres, porcentaje y exclusiones](02-ranking-escritorio.png)

**Funciona:** se llega desde Resumen mediante «Ver ranking»; tabla compacta con equipo, base, cierres y porcentaje. Las exclusiones están explicadas. **Fricción:** no hay un filtro visible por equipo/analista ni enlace por fila al detalle en esta vista. La explicación extensa de la fórmula ocupa la entrada. Los colores de los primeros puestos pueden interpretarse como cumplimiento de meta. **Propuesta:** conservar la tabla, acercar filtros y detalle, y distinguir posición, cumplimiento y alerta. **Accesibilidad:** hay cifras y nombres además del color; no afirmar que todo el significado depende exclusivamente de él.

### 3. Ranking de capital — criterio de orden poco explícito

![Paso 3. Capital total muestra un orden distinto del importe de capital](03-ranking-capital.png)

**Observación:** el primer puesto presenta S/ 317,518 y 127 % de avance; el último S/ 435,020 y 108.74 %. En este ejemplo el orden coincide con el avance frente a la meta, mientras la pestaña se llama «Capital total». **Propuesta:** indicar por qué se ordena y distinguir monto y cumplimiento. Confirmar la regla canónica antes de modificar el orden. **Funciona:** desglose PEN/USD, TC y porcentajes superiores al 100 % visibles. El bloque «Altas nuevas» tiene un horizonte independiente de seis meses: explicitar su alcance junto al título. Los importes son sintéticos; no representan un error productivo demostrado.

### 4. Conversiones — contenido útil con lectura exigente

![Paso 4. Conversiones y primeras secciones de detalle](04-conversiones.png)

**Funciona:** diferencia citas registradas como realizadas, señales inferidas, cierres por fecha y resultados de las llegadas; incluye explicaciones de atribución. **Fricción:** muchos bloques preceden al selector de analista; el DOM contiene expresiones como «núcleo», «lectura viva» y «fotos mensuales cerradas», además de identificadores de operaciones. **Propuesta:** organizar por la pregunta comercial; mantener una explicación breve y desplegar el método completo. Por ejemplo, explicar qué operaciones aportan al indicador y a qué período corresponden, conservando todas las reglas reales. **Accesibilidad:** algunos gráficos tienen nombre accesible y el de cierres tiene tabla; falta comprobar equivalencia informativa en los demás.

### 5. Detalle de analista — apertura y cierre correctos; comparación limitada

![Paso 5. Detalle de Ana Torres en un panel modal](05-detalle-analista.png)

**Verificado:** panel identificado por nombre, equipo y período; el foco entra en cerrar, Escape cierra y devuelve el foco a «Ver detalle». **Fricción:** el fondo queda bloqueado y el indicador principal aparece después de otros bloques; comparar responsables exige recordar información o cerrar y abrir. **Propuesta:** mantener este acceso rápido para una persona y probar una comparación conjunta cuando la tarea lo requiera. **Límite:** no se comprobó todo el recorrido de teclado ni cada estado del panel; esta prueba no constituye una certificación de accesibilidad.

### 6. Regreso al Ranking — pérdida de contexto reproducida

![Paso 6. Al volver aparece Conversión general aunque se salió de Capital total](06-ranking-al-volver.png)

**Secuencia:** Ranking → Capital total → Conversiones → abrir y cerrar detalle → Atrás. **Resultado:** vuelve a «Conversión general»; el mes se conserva. **Propuesta:** conservar la pestaña, selección, filtros compatibles y posición relevantes. El criterio de cierre debe repetir exactamente este recorrido y comprobar el retorno. No se atribuye a la aplicación la duración de la llamada automática del navegador.

### 7. Citas — definiciones presentes, prioridad diluida

![Paso 7. Citas con indicadores repetidos y distintas tasas](07-citas-escritorio.png)

**Funciona:** explica fecha prevista, cancelaciones y denominadores; el DOM incluye modalidad y tabla por analista. **Fricción:** 58 realizadas, 15 no concretadas y 29.3 % que terminan en cliente se repiten. La asistencia de 87.9 % y la realización de 79.5 % necesitan su definición cerca del dato: miden poblaciones distintas. La indicación de tres citas vencidas sin resultado queda bajo «Reprogramadas». **Propuesta:** una lectura compacta, distinción inmediata de tasas y acceso a los casos por resolver cuando esté disponible. No igualar asistencia y realización ni deducir un error de los ejemplos.

### 8. Metas — consulta clara con etiquetas por precisar

![Paso 8. Consulta de metas y enlace a su administración](08-metas-escritorio.png)

**Funciona:** pantalla breve; consulta separada de edición, mes visible y enlace «Administrar metas». **Fricción:** el 83 % de avance necesita una etiqueta como «Cumplimiento de la meta» junto al 23.06 % de conversión; «El detalle por analista está en Conversiones» es texto, no enlace. **Propuesta:** conectar ese destino y mostrar objetivo, vigencia y cumplimiento de forma inequívoca. Las metas sintéticas de distintos paneles no se concilian mediante esta auditoría; verificar revisiones y alcance con datos controlados antes de publicar mejoras.

### 9. Entrada a administrar metas — estructura comprensible, edición no probada

![Paso 9. Administración de metas en modo de consulta](09-administrar-metas.png)

**Funciona:** revisión, autor, fecha, moneda y agrupación por supervisor; estado de solo lectura explícito. **Fricción:** la vuelta visible dirige a Configuración aunque se llegó desde Metas; consulta y administración tienen el mismo título superior. **Propuesta:** distinguir «Consultar metas» de «Administrar metas» en el contexto de navegación y conservar el origen al regresar. **Límite:** el modo demo permite auditar esta entrada; no se probó editar, guardar o publicar ni se concluye que Gerencia carezca de esos permisos en producción.

### 10. Rendimiento general — legible, con solapamiento de propósito

![Paso 10. Rendimiento general y comparación de conversión por analista](10-rendimiento-escritorio.png)

**Funciona:** barras horizontales con valor, equipos y excepciones. **Fricción:** el menú dice «Rendimiento» y la cabecera «Equipo»; la primera parte se solapa con Ranking y el bloque de capacidad queda más abajo. **Propuesta:** darle una tarea principal reconocible, vinculada a carga y capacidad, manteniendo el acceso a comparación de resultados. **Accesibilidad:** las etiquetas del gráfico se ven pequeñas; verificar contraste, ampliación y alternativa textual antes de declarar un defecto normativo.

### 11. Rendimiento y capacidad — patrón útil para extender

![Paso 11. Asuntos que merecen atención y capacidad por analista](11-rendimiento-capacidad.png)

**Funciona:** «Lo que merece tu atención» expresa cantidad y responsable; el orden por cupos está explicado y la carga actual se distingue del mes elegido. Las tarjetas tienen una acción explícita para editar el límite. **Fricción:** el aviso no enlaza a los leads afectados en la vista inspeccionada; aparecen además medidas históricas con definición anterior. **Propuesta:** llevar este patrón de atención al Resumen, conectar los casos y mantener separadas las lecturas históricas y actuales. **Límite:** aviso y capacidad son ejemplos; no se modificó ningún límite ni se certificó el guardado.

### 12. Resumen al reducir el ancho — menú abierto invade la consulta

![Paso 12. Resumen a 390 píxeles con el menú que estaba fijado en escritorio](12-resumen-movil.png)

Al pasar de escritorio a 390 × 844, el menú previamente fijado ocupa 240 píxeles y cubre gran parte del reporte. Existe control para plegarlo. **Propuesta:** navegación móvil que deje espacio suficiente al contenido y se cierre de forma predecible al elegir un destino. **Límite:** se probó una sesión procedente de escritorio; no se afirma que sea el estado inicial de una sesión móvil nueva ni el comportamiento de un dispositivo físico.

### 13. Resumen móvil con menú plegado — demasiado contenido antes de la decisión

![Paso 13. Resumen móvil con navegación plegada y cabecera sin título legible](13-resumen-movil-menu-cerrado.png)

**Funciona:** los campos de fecha quedan disponibles y no hay desbordamiento horizontal global en esta vista. **Fricción:** el menú conserva 64 píxeles; la cabecera prioriza acciones y la gran tarjeta apila indicadores hasta exceder la primera pantalla. **Propuesta:** asegurar título y período legibles, compactar indicadores y acercar la primera revisión pertinente. No reducir texto o cifras hasta volverlos ilegibles para que todo quepa.

### 14. Ranking móvil — adaptación útil con fallo en la cabecera

![Paso 14. Ranking móvil con filas adaptadas y título superior oculto](14-ranking-movil.png)

**Funciona:** la tabla pasa a una lista con analista, equipo, porcentaje, base y cierres. Las tres pestañas caben y miden 64 píxeles de alto en esta muestra. **Fallo comprobado:** el título superior «Ranking» tiene ancho visible de **0 píxeles** en el DOM; «Nuevo lead» ocupa aproximadamente 131 píxeles. **Propuesta:** reservar espacio para la orientación del reporte y adaptar las acciones; mantener la buena adaptación de las filas. La fórmula extensa precede al primer analista: probar explicación breve más método desplegable. Esta prueba es de viewport en Chromium, no de iOS/Android ni de accesibilidad completa.

## Prioridades derivadas de la evidencia

| Prioridad de trabajo | Cambio propuesto | Evidencia | Cierre observable |
| --- | --- | --- | --- |
| Alta | Explicar período, base, criterio de orden, moneda y cumplimiento junto a cada lectura. | 1, 3, 4, 7, 8, 11 | Gerencia explica las diferencias sin confundir poblaciones o porcentajes. |
| Alta | Conservar el contexto al ir al detalle y volver. | 5, 6, 9 | Regreso a la pestaña y consulta de origen; comportamiento de foco correcto. |
| Alta | Simplificar Resumen y elevar asuntos que requieren revisión. | 1, 7, 11 | Un solo bloque por indicador principal y asuntos respaldados por evidencia. |
| Alta para consulta móvil | Corregir cabecera y comportamiento del menú. | 12, 13, 14 | Título, período y navegación utilizables en los anchos acordados. |
| Siguiente entrega | Comparar equipos/analistas y acercar el detalle. | 2, 3, 4, 5, 10 | Comparación de dos responsables con la misma definición y base visible. |
| Siguiente entrega | Conectar aviso, casos y acción existente; aclarar configuración. | 9, 11 | El usuario identifica alcance y comprueba resultado en un entorno controlado. |
| Según validación de la tarea | Preparar consultas o reportes para reuniones. | Necesidad inferida del rol; formato aún por validar | Destinatario entiende contexto y vigencia; salida adecuada al uso confirmado. |

Estas prioridades describen impacto esperado en las tareas, no incidentes de producción. La accesibilidad, los estados de carga/vacío/error y la comprensión del dato se validan en cada entrega.

## Investigación aplicada

- **Jerarquía según la decisión:** Microsoft recomienda priorizar lo necesario para la audiencia, presentar contexto y facilitar el acceso al detalle. Se aplica aquí a la repetición de indicadores del Resumen y Citas. [Microsoft: diseño de dashboards](https://learn.microsoft.com/en-us/power-bi/create-reports/service-dashboards-design-tips).
- **Diseño por dispositivo:** Tableau propone ajustar contenido y distribución al tamaño de uso. Se aplica a cabecera, menú y densidad móvil; no exige que todo el CRM quepa en una sola pantalla. [Tableau: dashboards efectivos](https://help.tableau.com/current/pro/desktop/en-us/dashboards_best_practices.htm).
- **Comparación:** NN/g identifica encontrar, comparar, consultar un registro y actuar como tareas centrales de las tablas. Se aplica a filtros visibles, columnas relevantes próximas y acceso al detalle. [NN/g: tablas de datos](https://www.nngroup.com/articles/data-tables/).
- **Continuidad:** la aplicación de filtros y los desplazamientos deben acompañar la intención del usuario. Se propone conservar la consulta al regresar, y diferenciar controles pendientes de aplicar y filtros ya activos. [NN/g: diseño de filtros](https://www.nngroup.com/articles/applying-filters/).
- **Gráficos comprensibles:** dar un nombre al gráfico no sustituye comunicar sus valores y relaciones mediante texto o tabla. Se verificará la equivalencia en cada visualización. [W3C: imágenes complejas](https://www.w3.org/WAI/tutorials/images/complex/).
- **Color y contraste:** los significados deben tener apoyo textual o visual adicional. Se medirá contraste; las capturas por sí solas no demuestran conformidad. [W3C: uso del color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html), [W3C: contraste mínimo](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).
- **Títulos informativos:** un mensaje principal y un subtítulo de medida, ámbito y período ayudan a interpretar y comunicar gráficos. Se aplica a las lecturas por fecha de llegada, cierre y citas. [Government Analysis Function: gráficos](https://analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts/).

## Verificación pendiente

La siguiente validación debe utilizar usuarios reales disponibles de Gerencia y tareas concretas: detectar un asunto, explicar dos porcentajes distintos, comparar responsables, abrir y volver al detalle, y llegar a la acción adecuada. Registrar interpretación correcta, ayuda, tiempo, pasos y errores. No convertir una prueba con una sola persona en porcentajes representativos de toda la organización.

Completar en un entorno controlado los estados de carga, dato parcial, cero, ausencia, error y guardado incierto; comprobar navegación de teclado, zoom, contraste medido y lectores de pantalla. La edición de metas y capacidad requiere su propio recorrido de validación. Las reglas de negocio y los permisos se conservan; cualquier cambio de definición tiene seguimiento separado del plan UX.
