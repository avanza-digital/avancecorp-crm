# Dirección de la jornada — integración local, 18/10/2026

Miguel eligió la propuesta 2 y pidió adaptarla al CRM. La ruta «Hoy» del
supervisor muestra ahora esta vista. Los títulos de los dos primeros bloques
son **Llamadas de hoy** y **Citas de hoy**. Los accesos «Cómo leer las cifras» y
«Si faltan datos» no aparecen. Implementación local; no publicada.

**Alcance confirmado por Miguel al cerrar la iteración:** estamos revisando diseño;
Docker no es necesario. No continuar E2E para esta revisión. Los intentos anteriores
se conservan como historial y no bloquean la entrega del diseño local.

**Ajuste de diseño posterior:** retirada toda la franja «La jornada, de principio
a fin / Dónde necesita apoyo tu equipo», incluido el contador y la hora lateral.
Separación entre bloques reducida a 12 px, rellenos de tarjetas y tabla compactados,
ancho disponible aprovechado y contenedores de avisos vacíos sin ocupar espacio.
Retirado también el subtítulo «Llamadas registradas hoy», sin dejar una línea vacía.
Solo archivos locales, sin control del navegador ni Docker.

## Cinco mejoras de UI solicitadas y aplicadas

1. Cabeceras de las tres tarjetas con icono y título en una línea, sin subtítulos;
   cifras alineadas arriba y acciones en la misma línea inferior. Se apilan cuando
   el ancho disponible no permite tres columnas legibles.
2. Brecha mensual destacada como «Faltan S/…» junto al porcentaje. La barra solo
   aparece con un avance confirmado; los estados de falta de meta se conservan.
3. Cifras de las tablas alineadas a la derecha, tareas vencidas resaltadas y
   motivos en etiquetas breves. «Contacto bajo» usa el nivel ya confirmado por
   el CRM; no cambia umbrales, prioridades ni reglas del filtro.
4. Texto secundario de 12–13 px y explicaciones más cortas. El potencial mantiene
   las monedas separadas y su carácter estimado; la explicación completa se abre
   desde el botón de información en un diálogo con cierre accesible.
5. Contador actual de pendientes y «Ver pendientes» junto al buscador del equipo.
   Eliminada la franja inferior duplicada; el acceso permanece también en la
   pestaña mensual. Miguel pidió simplificar sus etiquetas: primero «3 tareas
   pendientes» y debajo «1 atrasada» (cantidades dinámicas), sin «al corte».

Verificación de esta iteración: lint del componente, typecheck, build y 14 pruebas
existentes de la vista y sus agregados PASS antes del último ajuste de esas dos
etiquetas. Sin navegador ni Docker, según el
alcance de revisión de diseño indicado por Miguel.

## Aviso de leads por repartir

Miguel pidió un aviso llamativo con estado, visible solo mientras el supervisor
tenga leads pendientes de repartir. Se agregó una franja compacta bajo el título,
antes del resultado mensual: acento ámbar, icono de bandeja, cantidad destacada,
estado **Por asignar** y acceso **Repartir leads** a `#/derivaciones`.

Usa `resumen_cartera_fn` mediante el lector operativo existente y su ámbito
autorizado: abiertos sin analista (`totales.parkeados`). Incluye pendientes de
otros días; no etiqueta todo ese conteo como recién ingresado. La franja desaparece
con cero pendientes y no reserva espacio. Sin dato o con error no muestra un
conteo anterior ni afirma que la bandeja esté vacía. Las derivaciones ya invalidan
esta consulta; el aviso sigue sus actualizaciones sin añadir un lector paralelo.

Se retiró el conteo duplicado del pie y se conserva el acceso general
**Ver derivaciones**. El aviso es independiente de los tres indicadores del día.

Verificación: lint del componente, typecheck, build y 14 pruebas existentes PASS.
E2E e inspección visual en navegador NOT RUN por el alcance local de diseño
solicitado por Miguel.

## Resultados de hoy

Miguel aprobó sustituir «Acompañar el cierre». La nueva tarjeta muestra las
operaciones del día y el capital en soles y dólares por separado. Abre un diálogo
con el aporte por analista y un total que cuadra con la tarjeta. Se retiraron
el potencial de cartera y su explicación; el aviso de reparto conserva su lugar.

Se reutiliza la consulta mensual completa de Facturación, filtrada por su día
comercial de Lima. El ámbito lo decide el servidor: se preservan subárbol,
atribución histórica y ventas propias del supervisor. Todos los tipos de
operación cuentan; no se confunden operaciones con clientes únicos.

Los datos fallidos, incompletos o sin un corte que cubra hoy se presentan como
pendientes o no disponibles. Un corte de ayer no produce cero ventas hoy.
El modo demo deriva sus contratos existentes, sin inventar cierres recientes.
La revisión de Claude, las correcciones y los checks se registran en
`RESULTADOS-HOY-VERIFICACION.md`.

Miguel pidió un objetivo para Goal y un plan posterior con Claude como revisor.
Están en `PLAN-HOY-SUPERVISOR.md`. Ese plan no se ha iniciado como un Goal.

Miguel amplió después el plan hasta la creación del ZIP para publicar y pidió
recibirlo antes de ejecutarlo. La versión vigente detalla ocho fases, con Claude
como revisor, validación integral, preparación de la revisión y entrega del ZIP
con manifiesto SHA-256 comprobados. Esta actualización es documental: no se
inició la ejecución, no se creó un artefacto ni se publicó. Las comprobaciones
excluidas por la restricción de navegador/Docker figurarán como pendientes.

## Información y decisiones

| Bloque | Fuente y criterio |
| --- | --- |
| Capital confirmado, meta y brecha | Foto mensual oficial de cumplimiento/objetivos y valoración comercial existente. No se recalcula desde fichas ni desde la cola diaria. |
| Operaciones | Contratos del agregado mensual oficial, con la misma valoración que el capital. No son personas ni oportunidades. |
| Conversión oficial | RPC y cobertura del núcleo de conversión existente. Se preserva el divisor oficial. |
| Llamadas de hoy | Foto completa de `gestion_diaria_equipo_fn`, acotada por supervisor y fecha de Lima. Tasa = suma de contestadas / suma de útiles; nunca promedio de porcentajes. |
| Citas de hoy | Lector existente de Citas, filtrado por fecha prevista. Realizadas, programadas, vencidas, no asistió, canceladas y reprogramadas se cuentan por estado explícito. |
| Resultados de hoy | Facturación completa del ámbito autorizado y día de Lima. Todos los tipos de operación, PEN/USD separados y detalle por analista. No publica un cero a partir de un corte anterior al día. |
| Gestión de hoy por analista | Misma foto diaria completa, motivos de atención y orden existentes en Gestión Diaria. Citas pendientes hoy y tareas vencidas al corte se rotulan por su propio periodo. |
| Resultado del mes por analista | Unión de identidades de metas, cumplimiento, valoración y conversión. Conserva la atribución mensual aunque cambie el equipo actual. Cada métrica conserva su población; una persona con meta sin fila de conversión no oculta la conversión de las demás. |

Un fallo de fuente retira sus cifras anteriores. Ausencia de información se
representa como «—» o un estado explícito; no se convierte en cero. La meta en
carga, la meta no disponible y la ausencia confirmada de meta tienen textos
distintos. Sin tipo de cambio, las monedas se separan y no se calcula avance.

La tabla permite buscar analistas, filtrar quienes necesitan apoyo y abrir el
detalle existente con teclado y devolución del foco. Los accesos llevan a Citas
del día, Gestión Diaria, pendientes, oportunidades, Facturación y derivaciones.
Las tasas autorizadas conservan su panel existente.

La agenda semanal y el ranking antiguos dejan de ser la portada del supervisor
al elegir esta dirección; la navegación a los módulos completos continúa. Los
componentes anteriores se conservan en el árbol, pero ya no son la vista activa.
Las consultas de ranking y agenda semanal que esta portada no usa quedan
deshabilitadas mediante una opción del hook; sus otros consumidores mantienen
el comportamiento anterior.

## Archivos del cambio

- `app/src/screens/hoy.tsx`: selección de la nueva portada del supervisor.
- `app/src/screens/hoy/datos-supervisor.ts`: exposición de fuentes existentes,
  actualización mensual y opción para omitir consultas operativas no usadas.
- `app/src/screens/hoy/jornada-supervisor.ts`: agregación y filas mensuales.
- `app/src/screens/hoy/supervisor-jornada.tsx` y `.css`: vista integrada.
- Tests `jornada-supervisor.test.ts`, `supervisor-jornada.test.tsx` y
  `app/e2e/hoy-supervisor-mando.spec.ts`.

No hay migraciones, cambios de permisos ni dependencias nuevas. El árbol tenía
cambios previos de valoración de capital y otras tareas; se conservaron. El
preview usa datos de demostración locales, sin credenciales productivas.

## Verificación

- **PASS**: lint (advertencias preexistentes), typecheck, build y `verify:bundle`.
- **PASS**: suite unitaria completa, 426 archivos / 6 766 pruebas, antes de las
  correcciones de revisión. Después de corregir, 118 pruebas específicas pasan
  en las dos pantallas anteriores y los dos nuevos archivos de pruebas.
- **FAIL / corrida incompleta**: E2E Docker local. Primer intento con dos workers
  interrumpido después de timeouts de navegación en dos casos del spec de Gestión
  Diaria. Segundo intento, solo los tres casos de esta portada y un worker:
  un fallo al esperar el menú durante el arranque del workspace (10 segundos,
  aún en «Preparando tu espacio de trabajo»), sin llegar a las aserciones de la
  portada. El contenedor terminó con código 143 y no produjo resumen final;
  los otros dos casos no quedan acreditados. El entorno mostraba alta carga
  de CPU; no se modificaron ni detuvieron procesos ajenos. Log conservado en
  `E2E-ADAPTACION.log`. No se declara PASS de E2E ni comprobación responsive final.
- **NOT RUN**: gate de realidad, el comando terminó por falta de `SUPABASE_URL`.
  No se acredita conciliación de cifras productivas.
- **NOT RUN**: publicación y validación productiva; fuera de este encargo de diseño.

La revisión independiente y su resolución están en
`REVISION-ADAPTACION-CLAUDE.txt` y `REVISION-ADAPTACION-RESUELTA.md`.
Las evidencias de `VERIFICACION.md` corresponden al prototipo anterior, no a
esta integración. Tras pedir Miguel trabajar solo en local, no se continuó
la inspección interactiva en el navegador.
