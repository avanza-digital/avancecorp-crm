# Coordinación - planilla de reparto y equilibrio por fechas

Estado: requerimiento acordado y maqueta en Figma; **todavía sin implementación ni publicación en el CRM**. La publicación anterior de Formulario 3 nativo sigue completa. No se modificaron leads, responsables, permisos, turnos ni n8n durante esta definición.

## Decisión de Miguel

El 15/10 Miguel explicó que los turnos fijos Landing/Formulario ya no responden a su operación. Quiere una planilla parecida a Excel, para ver lo disponible y repartir cantidades combinando orígenes, equilibrando el total que reciben todos los supervisores. No limitar a dos supervisores ni a tres orígenes.

Eligió el **acumulado semanal** como referencia habitual. Después amplió el requisito: consultar un día, un rango o varios días específicos, tanto individualmente como sumados. Confirmó **ambos filtros de fechas, diferenciados**:

- Fecha de ingreso: seleccionar los leads de esos días que siguen pendientes de reparto.
- Fecha de reparto: consultar cuánto se entregó a cada supervisor en esos días.
- Origen y supervisor: ajustar las filas, columnas, desglose y totales a la selección. No presentar un total global como si fuese el filtrado.

La semana es un acceso rápido, no una restricción del módulo. Las fechas se interpretan en America/Lima. Falta definir en implementación si «ingreso» utiliza el ingreso al CRM o la fecha original de la fuente; no confundirlas al importar históricos. La actual cola devuelve `creado_en` del CRM.

## Vista acordada

1. Pendientes disponibles: total y desglose por origen, según fechas de ingreso y filtros. No confundir con tamaño de la hoja ni con todos los leads históricos.
2. Planilla: una fila por supervisor; recibidos en el período; celdas editables de cantidad a entregar por origen; total por enviar; total previsto después del reparto.
3. Cambiar cantidades actualiza la proyección. Editar no ejecuta asignaciones. Revisar y confirmar con «Repartir»; los confirmados aumentan únicamente según resultado real.
4. Poder ver por día o agrupar las fechas elegidas. La vista histórica es de consulta: repartir hoy no debe sumar ficticiamente al período pasado seleccionado. Si hoy no está incluido, mostrar explícitamente la fecha real del envío y separar su proyección del total histórico.
5. Destinos y orígenes dinámicos. Supervisores inactivos con entregas históricas siguen visibles en consulta, pero no pueden recibir nuevos leads.
6. Conservar los leads ya repartidos y la historia. No redistribuirlos automáticamente para igualar los totales.

Figma: [Planilla de reparto](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=52-34). Sección `52:34`, tabla de reparto `53:59`. Maqueta sin cifras reales; revisión visual sin cortes ni solapamientos PASS. No es una pantalla publicada ni una conexión de datos.

## Ajuste visual aprobado

Miguel aprobó la propuesta y pidió acercarla a lo que ya tiene el CRM en recursos. Se adaptó la misma sección de Figma a los estilos reales de `app/src/index.css` y a las primitivas existentes:

- Fuente Plus Jakarta Sans; tinta `#16233f`, navy `#111e3d`, azul `#2563eb`, fondo `#f6f8fc`, bordes `#e4e9f2` / `#dbe2ef`.
- Ancho 1240 px, cabecera compacta, filtros alineados con campos redondeados, cabecera clara de tabla y botones primario/contorno.
- En implementación reutilizar `Card`, `SectionHead`, `TablaEnvoltura`, `TheadCrm`, `Th`, `Td`, `Input`, `Select`, `Button` y, si conviene para el resumen, `Pastilla` / `StatStrip`. No introducir otro kit visual ni otra tipografía.
- La explicación tabular de filtros (`53:37`) quedó oculta; se sustituyó visualmente por controles separados de ingreso, reparto, agrupación, origen y supervisor. Se conservan las reglas funcionales acordadas.
- FigJam no admite bibliotecas de componentes Design; no había Code Connect en el repositorio. La maqueta reproduce los tokens del CRM mediante texto, tabla y controles editables, sin una captura aplanada.

Comprobación de fuente: todos los textos visibles usan Plus Jakarta Sans. Revisión visual final PASS (1240 × 1010), sin recortes ni solapamientos. Esta iteración solo cambia diseño/documentación; no requiere tests de runtime ni modifica producción.

## Base técnica verificada

- `crm.agenda_reparto_diaria(desde,dias)` ya devuelve `dias[].origenes[].entregas` con todos los orígenes exactos y destinos reales. Sumar solo esa colección, sin volver a sumar los carriles agregados. Máximo actual: 14 días por llamada; rangos mayores necesitan partición disjunta y tratamiento explícito de fallos, o un contrato nuevo si resulta necesario.
- Su unidad actual es el evento `crm.actividades`, tipo `reasignacion`, movimiento `entra_bandeja`. No equivale a leads únicos ni a stock actual. Un reingreso puede representar otra entrega. Etiquetar correctamente y no deduplicar silenciosamente el histórico.
- `supervisores_para_reparto` enumera supervisores activos dinámicamente. No usar `agenda.destinos`, que es la lista antigua de Carmen/Jor.
- `leads_por_repartir` devuelve cola elegible, sin dueño, y aplica vetos de contacto. `bandeja_pendiente` y el panel de distribución actual no miden entregas del período.
- `repartir_lead` ya asigna un lead con permisos, validación de destino, bloqueo de fila y rechazo si dejó de estar disponible. No existe lote de Coordinación equivalente. No usar las RPC de bases/analistas para esta operación.
- El modo libre existente (`agenda.reparto_libre`) permite operar sin turno para Coordinación si el control de Gerencia está activo, o superadmin. Gerencia ordinaria no hereda ese permiso automáticamente. Estado productivo no consultado en este trabajo; nunca habilitarlo silenciosamente.
- Mantener tablas/helper de turnos conserva lectura histórica. Cambiar el helper afectaría los cómputos históricos de fuera de turno. La nueva planilla debe sustituir su función operativa, sin borrar evidencias.

## Controles del reparto por cantidades

Enteros no negativos, disponibilidad suficiente por origen dentro de fechas de ingreso, sin ocultar borradores cuando cambian filtros. Fijar IDs y destinos al confirmar con orden estable (fecha e ID), sin duplicar un ID entre filas. Prevalidar y exigir nueva revisión si cambió la disponibilidad. Revalidación final del servidor obligatoria.

Si se reutilizan llamadas individuales, el lote **no es atómico**. Mostrar confirmados, conflictos, desconocidos y no intentados. Detener ante resultado ambiguo, conciliar cola/historia, no reintentar a ciegas ni reemplazar un lead por otro automáticamente. Bloquear doble clic y relecturas que restauren una cola vieja durante el envío. `useReparto.repartir` actual captura errores y devuelve void: no sirve como contador de éxitos de un bucle.

Pruebas necesarias: días sueltos/rangos sin doble conteo, límites de Lima, cambio de semana/mes, filtros de ingreso independientes de reparto, proyección al consultar pasado, más de dos supervisores, orígenes distintos, destinos históricos, ceros versus dato ausente, lote parcial, revocación de permiso, veto, carrera, red ambigua y cambios de filtros con borrador. E2E del CRM siempre local en Docker.

## Revisión y continuidad

Agente Codex secundario de solo lectura: **PASS condicionado** a respetar permiso efectivo, conteos por entregas y resultados parciales. Inspeccionó la variante semanal; la ampliación posterior a dos calendarios requiere sus pruebas propias.

Claude se intentó mediante `scripts/claude-review`, con evidencia saneada. El intento restringido falló y el intento autorizado fuera del sandbox terminó sin VERDICT ni salida utilizable. **Revisión Claude NOT RUN de forma efectiva**, no se considera aprobada. No hubo tercer intento ni cambios de configuración.

No se ejecutaron pruebas de producto porque este cambio solo documenta y dibuja el requerimiento. Antes de implementar: cerrar semántica de fecha de ingreso, concretar UX de selección de días y borradores, completar revisión técnica útil, implementar y verificar antes de cualquier publicación.

Relacionados: [[Historial de derivaciones de Coordinacion]], [[Reparto de Leads]], [[Formulario 3 - origen nativo publicado (2026-10-15)]].
