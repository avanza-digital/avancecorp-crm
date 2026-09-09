---
fecha: 2026-09-08
estado: adaptacion-identidad-local-pendiente-revision-visual
tags: [crm, citas, gerencia, ux, ui, propuesta]
---

# Citas: tablero horizontal y flujo por persona

Miguel pidió mejorar la experiencia de Citas respetando los principios UX/UI del CRM y conservando sus datos. Aclaró que lo prioritario es entender qué pasó con quienes no asistieron, de forma **horizontal, de una sola pasada, como un tablero Power BI**, con mes, semanas y filtros aplicados.

Continúa [[Citas Gerencia - adaptacion CRM y consultas por lead 2026-09-08]]. Reglas de [[Fundamentos UX del CRM]] y [[Plan UX Gerencia - numero lista ficha 2026-09-06]]: número → lista → ficha; el sistema absorbe trabajo mecánico sin ocultar bases, unidades ni fechas.

Propuesta recomendada: filtros compactos, flujo 4 → 3 → 1 → 1, conversión 25% sobre los cuatro leads iniciales y S/35.000, seguidos por una matriz de personas con columnas ausencia, reprogramación, asistencia y depósito del flujo. Comparación de asesores y promedio por lead en el mismo tablero de escritorio. Los filtros de consulta recalculan el conjunto; seleccionar una etapa cambia su lista de detalle y conserva la base. Mantener visibles el período de las citas de origen y el corte del seguimiento.

Se prepararon tres conceptos horizontales independientes con capturas actuales: matriz de recuperación, recorrido con comparación, y revisión con ficha abierta. Son imágenes de propuesta; Miguel aún no eligió una y no se modificó código. Los detalles incidentales de las imágenes generadas no sustituyen los datos ni las reglas verificadas. La composición seleccionada se adaptará con los componentes y colores reales del CRM.

Documento, revisión de tres estados y conceptos: `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/PROPUESTA.md`. Se distingue persona pendiente de pérdida comercial: dos nuevas citas pendientes y una persona sin nueva cita. No se mezclan citas con leads, ni depósitos fuera de la cadena con la conversión de este flujo.

## Meta de citas por lead

Miguel pidió incorporar una meta de **3 citas por lead (100%)**, buscando un **125% de cumplimiento**, equivalente a **3.75 citas por lead de promedio**. Confirmó continuar visualmente sobre las tres propuestas. Se muestra promedio y porcentaje por analista, junto a cuántos leads realmente tienen al menos tres citas; ambas lecturas son distintas.

El ejemplo conserva sus datos: equipo 40 citas/26 leads = promedio 1.54 y cumplimiento 51.3%; tres leads tienen 3+ citas. Ana tiene 7/4 = 1.75, 58.3% y un lead de cuatro con tres citas. Andrea tiene dos citas (66.7% de su meta individual) y ya completó el depósito; la meta no se convierte en requisito para depositar ni en una instrucción de agendar citas innecesarias.

La propuesta mantiene como base las citas y leads con cita del conjunto filtrado. No redefine el indicador sobre toda la cartera ni prorratea automáticamente la meta entre semanas. La vigencia de la meta real y la lectura de filtros parciales debe precisarse antes de integrar esa política.

Tres imágenes actualizadas, definiciones, valores calculados desde fixtures y límites visuales: `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/metas/README.md`. No se modificó código del módulo ni metas productivas. Se conserva la distinción de [[Citas Gerencia - adaptacion CRM y consultas por lead 2026-09-08]] entre citas, personas, asistencia y depósitos confirmados.

## Ajuste de ruido visual tras revisar el PDF original

Miguel encontró las tres propuestas con metas algo cargadas y pidió simplificar su presentación sin perder información. Se leyó completo el `UI-UX.pdf` original de la raíz (siete páginas) y se inspeccionaron visualmente las páginas 2, 3 y 5. Las propuestas anteriores usaban las notas del vault; no se había releído ese PDF para generarlas.

La nueva revisión aplica proximidad, jerarquía y detalle contextual de [[Fundamentos UX del CRM]]: recorrido de recuperación primero; comparación de analistas después; una sola referencia compartida de meta 3/100% y objetivo 3.75/125%; total del equipo una sola vez. Se quitan contenedores, iconos, estados y acciones repetidos. Las fechas completas se consultan por persona y las métricas complementarias siguen disponibles como columnas opcionales. La ficha es un detalle que se abre al seleccionar, no un panel permanente.

Las tres revisiones mantienen los datos del mismo ejemplo y están en `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/ajuste-ux/README.md`, con enlaces a las imágenes, correspondencia de datos y límites de la verificación visual. Continúan pendientes de elección; no se cambió el módulo ejecutable ni se publicó.

## Elección e implementación local de la tercera revisión

Miguel eligió **la 3**, correspondiente a `ajuste-ux/detalle-a-demanda.png`. Se adaptó el prototipo ejecutable existente, abierto por defecto en Resultados: flujo horizontal, tabla de personas, metas por analista y ficha a demanda. Se reutilizan BrandLockup, IBM Plex Sans, tokens, Button, Select y Sheet del CRM; las métricas complementarias siguen disponibles en Columnas. En pantallas amplias la ficha permite operar la consulta; en ventanas menores es modal.

Se mantienen las bases y cifras descritas arriba. La asistencia de la ficha y la del flujo usan una misma condición validada. Los filtros globales recalculan todas las métricas; elegir una etapa solo cambia la tabla de personas. Meta 3/100%, objetivo 3.75/125% y 3+ por persona permanecen como lecturas distintas. Continúa siendo un ejemplo local, sin cambiar metas productivas ni conectar movimientos reales.

Guía de uso, capturas y prueba de navegador: `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/README.md`. QA visual: `CRM-Avance-Corp/app/design-qa.md`. PASS: gate integral (3106 tests), 32 tests del prototipo, revisión técnica evaluada, filtros/exportación/foco y adaptación 1672/1280/1024/768/390. NOT RUN: E2E completa de producción y backend real. Sigue el criterio de [[Fundamentos UX del CRM]] y la base funcional de [[Citas Gerencia - adaptacion CRM y consultas por lead 2026-09-08]].

## Rechazo del aspecto implementado y búsqueda de recursos Figma

Miguel indicó que el resultado no le gusta y no se parece a su CRM; pidió buscar mejores recursos en Figma y una recomendación. La selección previa de la imagen 3 y el QA técnico no significan aprobación de su implementación visual.

Se capturaron Resumen, Ranking y Citas de la demo local actual a 1672×941, además del prototipo a la misma medida. La implementación cambió el marco de navegación, aplanó las superficies, introdujo pestañas diferentes y comprimió las filas. Recomendación: usar el aspecto real de Ranking/Metas, cabecera y paneles del CRM, y mejorar distribución y filtros conservando las reglas de negocio. IBM Plex Sans ya es la fuente del contenido actual de Gerencia; las notas históricas sobre otras fuentes no deben mandar sobre la referencia vigente.

El Figma del proyecto contiene cabecera, pestañas, período, fila de Ranking y detalle lateral, pero también antecedentes que no están totalmente sincronizados. Se encontraron Obra Community y los recursos de filtros/tablas de Untitled UI como complementos concretos, sujetos a adaptación a la identidad propia. Evidencia, enlaces, diagnóstico y siguiente dirección: `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/recursos-figma/README.md`. No se modificó código ni se creó una nueva propuesta de producto en esta revisión. Antes de otra implementación, mostrar la composición dentro del CRM real, según [[Fundamentos UX del CRM]].

## Aplicación local de la identidad del CRM

Miguel autorizó aplicar la recomendación y mostrarla en local. Se adaptó el prototipo de Citas con Sidebar real, cabecera de64 px con acciones de la consulta, paneles gi-card y tokens vigentes de Gerencia, pestañas agrupadas, filas legibles y barras azules de cumplimiento. No se monta el Topbar conectado al store; la identidad del Sidebar es estática, sin iniciar sesión ni consultar servicios. Los recursos Figma encontrados sirven como apoyo de organización y componentes, sin importar un tema diferente.

La ficha del recorrido vuelve a ser el Sheet modal del CRM: se abre a demanda y no reduce las tablas. Se conserva la lógica de recuperación, filtros, métricas y límites del ejemplo. En escritorio el flujo es horizontal; bajo900 px pasa a dos filas y las tablas se desplazan dentro de su panel. Se abrevian meses para mantener el año visible. Se conserva la meta3=100%, objetivo3.75=125% y el corte del seguimiento. La vista completa a1672 px mide1173 px de alto; se permite desplazamiento vertical para mantener filas cómodas.

Guía, capturas y pruebas: `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/README.md`. El navegador comprobó filtros, flujo, exportación, fichas, foco y tamaños. Gate integral y31 tests específicos pasan; se retiró una parametrización duplicada al volver al Sheet modal. El usuario preguntó si se estaba usando Claude; se explicó que Codex implementaba y Claude haría una revisión independiente. La revisión técnica no sustituye la aprobación visual de Miguel. Sigue siendo local con datos ficticios; no se publica ni se conecta una política de metas productiva. Continúa [[Fundamentos UX del CRM]] y sustituye la apariencia rechazada de la propuesta3.

Claude entregó una revisión técnica: se aplicaron semántica de diálogo, ajustes de filtros y navegación por teclado. Se descartó la hipótesis de desborde de la barra porque Progress ya limita su valor. Evaluación completa y evidencia en `adaptacion-identidad/revision.md`. La revisión se contrastó con CodeGraph, componentes compartidos y pruebas; no se tomó como autoridad sobre la aprobación del cliente.
