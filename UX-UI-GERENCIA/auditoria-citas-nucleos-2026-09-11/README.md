# Auditoría de integración de métricas de Citas

**Dictamen: no está todo conectado. No corresponde declarar el módulo listo con las nuevas metas.**

Se revisaron el frontend local, las funciones instaladas en Supabase y sus dependencias. La consulta operativa usa datos reales; la nueva propuesta de metas, ticket y proyección sigue siendo un ejemplo independiente. Hay además dos defectos de integración en la ruta operativa: un lector fuera del control de núcleos y una invalidación de caché que no alcanza al tablero.

Fecha: 11/09/2026, America/Lima. Backend: proyecto `dctqcbznekcyxhjujuci`. HEAD local: `40497037cf561cae2cf10dfd38b0c4aa9bb180f1`, más los borradores sin commit presentes al auditar. Esto no identifica el artefacto actualmente desplegado: no se comprobó su bundle. **No se modificó código de producto ni se aplicó SQL.**

## Recorrido real de los datos

`App → screens/gerencia.tsx:14 → CitasGerencia → useCitasGerencia → crm.citas_gerencia_consulta_fn → private.citas_gerencia_consulta → adaptarCitas/adaptarDepositos → ContextoCitas → TableroCitas`.

La ruta de Gerencia usa ese lector detallado. El agregador anterior, `private.metricas_reuniones_implementacion`, sí llama a los núcleos de citas, conversión y capital; comprobar solamente ese agregador habría dado una falsa impresión de conexión completa.

| Indicador o dato visible | Fuente y cálculo actuales | Situación |
|---|---|---|
| Total, programadas, vencidas, realizadas, no asistieron, canceladas y reprogramadas | `crm.tareas` activas de tipo reunión; adaptador y filtros del frontend | Datos reales. Las banderas se reconstruyen fuera de `citas_episodios`. |
| Leads con cita, promedio por lead, leads con 2+ o 3+ citas | Agrupación de las citas filtradas por `leadId` | Conectado al detalle, pero solo incluye leads con cita. No satisface la nueva base de asignados. |
| Cumplimiento de citas | Promedio anterior ÷ 3 × 100; objetivo 125% = 3,75 citas/lead | Regla anterior fija en frontend. No aplica la nueva configuración de 1,25. |
| No asistieron → reprogramaron | `estado=no_show` y vínculos `reagendada_de` del mismo lead | Conectado a registros reales; deduplica por lead y verifica secuencia. |
| Asistieron después de reprogramar | Cita completada y fecha de la actividad `reunion_realizada` vinculada | Conectado; no presume fecha de asistencia cuando falta evidencia. |
| Depositaron después de recuperar la cita | Lead convertido, perfil cliente y `convertido_en`; exclusión por `private.cierre_anulado` | Conectado a conversión real. Sin importe monetario. |
| % de recuperación hasta depósito | Leads convertidos del recorrido ÷ leads que faltaron | Conectado. Su denominador no es el de la meta del 70% sobre entrevistados. |
| Seguimiento pendiente / cerrado | Resultado de asignación convertido, sin anulación y posterior a fecha prevista | Lee el ledger directamente; no consume `conversion_episodios`. |
| Analista y supervisor | Responsable de la tarea; equipo/perfiles y respaldo del supervisor de la tarea | No acredita al creador de la cita ni congela la jerarquía del mes. |
| Mes, cuatro semanas y demás filtros | Mes completo en RPC; semana/estado/origen/modalidad/importe en frontend | Funcionales para citas por fecha prevista. Seguimiento posterior llega hasta el corte del servidor. |
| Monto estimado en ficha y CSV | `crm.leads.monto_estimado` y moneda | Es estimación comercial; no es depósito ni ticket medio. |
| Base total de leads asignados, incluidos los que no tienen cita, excluyendo registro propio | No forma parte del payload del tablero | Pendiente. |
| Nueva meta interna 1,25 y avances hacia 70% / 70% | Constantes y cifras ficticias en la propuesta; borrador separado de configuración | Pendiente de contrato y conexión al servidor. |
| Ticket medio por analista y cierre mensual proyectado | Valores fijos y operaciones JavaScript en el HTML de propuesta | Sin conexión al núcleo de capital ni al CRM real. |
| Control de Superadmin | Frontend y migración candidata para guardar versiones en estado borrador | Tabla y dos RPC ausentes del servidor. Ningún lector de métricas consume ese borrador. |

## Hallazgos que requieren atención

### H1 — Alta: el lector actual de Citas queda fuera de la gobernanza de núcleos

La función instalada `private.citas_gerencia_consulta` consulta directamente tareas, leads, asignaciones y actividades. No llama a `private.citas_episodios`, `private.conversion_episodios` ni `private.capital_episodios`.

La consulta de catálogo confirmó `declarada=false` y `huella_ok=false` para ese lector. La ejecución de solo lectura de `private.assert_analitica_leads_citas()` **falló** y lo nombró expresamente entre los contadores sin declarar.

Esto no demuestra que todas sus cifras sean falsas, pero sí impide certificar la arquitectura de fuente única: un cambio en el núcleo puede dejar el tablero con reglas distintas. Debe consumir las definiciones canónicas aplicables; las lecturas de detalle que necesiten excepción requieren justificación y registro por migración. Registrar una excepción, por sí solo, no conecta las nuevas métricas.

Evidencia: [lector instalado](lector-citas-servidor.sql), [resultado y catálogo del servidor](servidor-evidencia.json); migración local `20260909015744_crm_citas_deposito_por_conversion_cliente.sql:31–90`.

### H2 — Alta para adoptar las nuevas metas: la base y la regla son todavía las anteriores

`components/citas/metas.ts:3–15` mantiene 3 y 125%. `datos.ts:5–19` solo puede contar leads presentes en las citas. `resultados.tsx:45–70` muestra esas reglas al usuario.

Por ejemplo, con 100 leads elegibles asignados y 100 citas concentradas en 20 leads, el promedio actual sería 5; no refleja la cobertura de los otros 80 leads. Con la regla nueva, la meta sería 125 citas y el avance de volumen 80%.

El contrato tampoco entrega alta manual, creador ni universo completo de asignaciones. No basta cambiar una constante a 1,25. Hay que definir y servir la base completa, permitir analistas con cero citas y obtener la configuración vigente desde el backend.

**Precaución de negocio verificada:** el núcleo actual `conversion_episodios` usa llegadas por alta original, primera asignación y canales específicos; su `aporte_divisor` excluye referidos y manuales de manera distinta. Su índice ponderado no puede reutilizarse como divisor de esta nueva meta. Citas necesita una lectura semántica de asignaciones compatible con la regla acordada, conservando el significado del índice general de Conversiones.

Evidencia: [funciones instaladas](funciones-servidor.sql), `data/citas-gerencia.ts:13–30`, `lib/control-citas.ts:28–34`.

### H3 — Media: guardar o cambiar una cita no refresca la consulta del tablero

El tablero se identifica por `['crm','metricas','citas-detalle',actor,mes]`. Crear, cerrar y reprogramar una cita invalidan `['crm','metricas','reuniones']`. Son familias diferentes. Las listas compartidas de invalidación por cambios comerciales tampoco incluyen el detalle.

Se reprodujo con el QueryClient instalado y una consulta activa: **1 lectura inicial → 1 tras invalidar el prefijo antiguo → 2 al invalidar el prefijo correcto**. Puede persistir una foto anterior hasta una nueva consulta, por ejemplo mediante «Actualizar». No se pierde la escritura del servidor.

Corregir el contrato de invalidación para citas, asistencia, reprogramación, conversión/anulación y cambios de responsable. Probar también la estrategia para cambios hechos por otro usuario; no se verificó actualización entre sesiones.

Evidencia: `data/citas-gerencia.ts:90–97`, `lib/store.tsx:992–995,1584–1602,1798–1823,1881–1887`, `data/crm-queries.ts:231–264`; [reproducción](reproducir-cache.mjs) y [resultado](reproduccion-cache.json). Esta reproducción verifica las claves; no simula una escritura productiva.

### H4 — Pendiente de implementación: Superadmin guarda borradores, no reglas activas

El catálogo confirmó que `crm.control_citas_versiones`, `crm.control_citas_configuracion_fn()` y `crm.guardar_control_citas_fn(integer,jsonb,text)` no existen en el servidor.

La migración candidata solamente admite `estado='borrador'`; no introduce aplicación a las métricas. El frontend comunica esta condición y maneja el RPC ausente sin inventar un guardado. Instalar ese SQL, por sí solo, no cambiaría los resultados de Citas.

Evidencia: [comprobación de instalación](control-instalacion.json), `20260911212756_crm_control_citas_superadmin_borradores.sql:41–55`, `screens/config-citas.tsx:17–24`, `data/control-citas.ts:20–35`.

### H5 — Pendiente de implementación: tasas nuevas, ticket y pronóstico no tienen conexión productiva

`integracion-resultados.html:163–201` contiene personas, semanas y tickets ficticios. Calcula metas y proyección localmente; no llama a RPC ni forma parte de la ruta real.

La conversión a cliente acredita el **conteo** de depósitos según la regla confirmada, pero no aporta el **importe**. El adaptador devuelve `monto:null, moneda:null`. El ticket requiere una consulta al núcleo de capital con ventana, clientes, atribución y moneda compatibles. Nunca debe sustituirse por `monto_estimado`.

El pronóstico ilustrativo, con bases distintas de cero, se simplifica a `clientes actuales × días del mes / días transcurridos × ticket`. No constituye todavía un modelo productivo aprobado. Faltan reglas para ausencia de ticket/base, actividad pendiente o futura, desfases entre entrevista y conversión y capacidad/población del mes.

## Comprobaciones favorables y límites de significado

La recuperación existente exige conjuntos anidados: **depositaron ≤ asistieron ≤ reprogramaron ≤ no asistieron**. Sigue vínculos del mismo lead, comprueba fechas, deduplica y excluye anulaciones. Una conversión anterior a la asistencia no completa la recuperación. El porcentaje final usa a quienes faltaron al inicio.

El lector V2 está instalado. Sus migraciones remotas figuran como `20260909031832` y `20260909031848`; tienen nombres equivalentes a las migraciones locales con otros timestamps. No se confundió esa diferencia de versiones con ausencia del lector.

Los estados de carga/error no se presentan como cero ni permiten exportar cifras anteriores; las respuestas se validan por período, identidad, límites y duplicados. El guard del backend exige Gerencia activa con `private.rol_crm`; esto se inspeccionó en código, sin reemplazar una matriz RLS ejecutada.

Las cuatro semanas actuales son rangos de actividad: 1–7, 8–14, 15–21 y 22–fin. La propuesta usa un corte acumulado del mes. Se debe elegir y rotular el significado antes de conectar ambos comportamientos.

## Orden recomendado de corrección

1. Corregir la invalidación del tablero y el incumplimiento del control de núcleos, conservando historial, permisos y seguimiento fuera del período.
2. Completar el contrato de Citas: base de asignados sin registro propio, autor/responsable, unidad de entrevista, atribución temporal y tratamiento de manuales en resultados.
3. Añadir aplicación/versionado de configuración y un lector de métricas que use esa versión. La tabla de borradores no debe convertirse silenciosamente en configuración activa.
4. Conectar las metas 1,25 / 70% / 70%, el ticket desde capital y el pronóstico mensual. Distinguir tasa observada, cumplimiento y proyección.
5. Verificar por casos reproducibles: lead sin cita, manual, reasignación, cita repetida, pendiente/futura, reprogramación fuera del mes, conversión previa/posterior/anulada, falta de ticket y monedas separadas; comparar totales con sus desgloses. Ejecutar permisos y flujo completo de escritura→lectura en entorno de prueba antes de publicar.

Las preguntas abiertas sobre ventana del ticket, volumen futuro y atribución ya constan en la memoria del proyecto. Esta auditoría no las convierte en decisiones aprobadas.

## Verificación de esta auditoría

| Comprobación | Resultado |
|---|---|
| Frontera RPC, componentes Citas y controles nuevos: 5 archivos, 66 pruebas | PASS |
| Lógica compartida de filtros, metas y recuperación mediante sus fixtures: 6 archivos, 31 pruebas | PASS |
| TypeScript: `npm run typecheck` | PASS |
| Reproducción aislada de invalidación de caché | DEFECTO REPRODUCIDO |
| Catálogo y definiciones instaladas, de solo lectura | INSPECCIONADOS |
| `private.assert_analitica_leads_citas()` contra servidor | FAIL |
| Banco SQL de fixtures/permisos y aplicación de migraciones durante esta auditoría | NOT RUN |
| E2E completo de escritura y conciliación de resultados en navegador | NOT RUN |
| Build y gate integral del producto | NOT RUN: no hubo cambios de runtime; auditoría con comprobaciones focalizadas |
| Dictamen independiente Claude | NOT RUN: se intentó mediante el wrapper, pero no entregó un resultado completo con VERDICT válido |

**97 pruebas pasadas no certifican los nuevos indicadores**, que todavía no están implementados, ni subsanan el gate del servidor. Detalle en [verificacion.json](verificacion.json).

La revisión independiente se intentó una vez dentro del sandbox y se reintentó con autorización fuera de él. El primer intento no completó; el segundo fue rechazado por el wrapper por respuesta incompleta o sin VERDICT. No se obtuvo una revisión utilizable, no se afirma que Claude aprobara el módulo y no se usó su salida para justificar conclusiones. Evidencia en [revision-independiente.md](revision-independiente.md).

Al cierre se volvieron a capturar las huellas de las funciones relevantes para distinguir la inspección de cambios concurrentes: [huellas-al-cierre.json](huellas-al-cierre.json).

El gate global también nombró cuatro objetos fuera del alcance de Citas: `crm.historial_decisiones_tasa_gerencia_fn`, `crm.metricas_multiempresa_fn`, `private.inversion_historica_aplicar` y `private.inversion_historica_estado`. Se conserva el error completo para otro seguimiento; no se auditó su lógica ni se atribuyen sus fallos al módulo de Citas.

La auditoría produjo únicamente este informe, capturas de definiciones sin datos personales y una reproducción aislada. No hay migración aplicada, publicación ni commit de estos cambios.
