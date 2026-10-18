# Hoy del supervisor: dos propuestas comerciales

18/10/2026. Estado: propuestas para afinar con Miguel; no implementadas en el CRM.

## Criterio recomendado

Usar la propuesta 1, **Resultados del equipo**, como portada. El supervisor debe
poder responder al entrar: cuánto capital confirmó el equipo, cuánto falta para
la meta, quién aporta al resultado, cómo convierte y qué casos necesitan apoyo.
El resumen de actividad diaria acompaña esa lectura. Gestión Diaria y Seguimiento
conservan sus recorridos completos; desde Hoy se entra con persona, fecha y filtro.

La propuesta 2, **Dirección de la jornada**, organiza la intervención en contacto,
citas y oportunidades abiertas. Sirve mejor para las reuniones y revisiones del
día. Mantiene el resultado mensual visible, pero da mayor espacio a la ejecución.

Abrir `index.html` en el navegador. También se sirve durante esta sesión en
`http://127.0.0.1:8766/`. Los botones superiores cambian de propuesta; las cifras
y nombres abren detalles ilustrativos, el orden de la tabla 1 cambia y la tabla 2
alterna entre día y mes. Todos los nombres y cifras de las maquetas son ficticios.

## Qué falla en la lectura actual

Se inspeccionó la sesión real de supervisor abierta en `https://crm.miavance.com/#/hoy`,
incluido el diálogo Detalle, sin modificar registros. Se contrastó con el código
local y las notas del vault. El árbol local contiene cambios previos: no se afirma
que todos sus archivos correspondan al commit servido en producción.

1. **La primera pantalla responde a pendientes, no al resultado comercial.**
   La vista real inicia con Decide primero y Pendientes del equipo. La cola tiene
   cientos de casos y solo presenta una muestra; ocupa la atención antes de mostrar
   ventas, meta o conversión. Es útil como operación, insuficiente como portada comercial.
2. **El cumplimiento tiene una jerarquía demasiado baja.** El capital confirmado
   está dentro de Detalle; el porcentaje de meta y la conversión aparecen en la
   franja Consulta al final. Código: `app/src/screens/hoy/supervisor-mando.tsx:801`
   y `:857`.
3. **Equipo hoy muestra principalmente señales y capital en proceso.** El monto
   por persona no representa ventas confirmadas. No hay una tabla inicial que
   compare capital vendido, meta, conversión y actividad. Código: `supervisor-mando.tsx:749`.
4. **Los períodos conviven sin una organización suficientemente clara.** Mes,
   últimos siete días y cartera pendiente actual se reúnen en la misma página.
   «Hoy» no basta para explicar el período de cada cifra.
5. **La terminología exige esfuerzo.** En el detalle real se leen «toques» y una
   columna «CIERRES» de agenda que contiene tareas completadas, anuladas e
   inasistencias. Eso puede confundirse con cierres de venta. Propuesta: nombrar
   siempre la unidad: llamadas, citas realizadas, tareas completadas, operaciones.
6. **Los avisos no explican solos la situación comercial.** Un analista puede
   vender bien y tener pendientes; otro puede registrar muchas llamadas y vender
   poco. Un semáforo único no debería sustituir esas dos lecturas.

Esto es un diagnóstico de composición y significado, no una auditoría de la exactitud
de las cifras productivas. No se ejecutó el gate de realidad ni se consultó la base.

## Dos alternativas

| Aspecto | 1. Resultados del equipo — recomendada | 2. Dirección de la jornada |
|---|---|---|
| Pregunta principal | ¿Cómo va mi equipo y quién necesita apoyo? | ¿Dónde intervenir durante el día? |
| Primera lectura | Capital confirmado, avance de meta, operaciones y conversión | Resultado mensual compacto, seguido de contacto, citas y oportunidades |
| Centro de la pantalla | Tabla comparativa por analista | Tres bloques comerciales y tabla de actividad |
| Actividad | Franja de llamadas, contacto, citas y vencidas | Protagonista; llamadas útiles y resultados de agenda visibles |
| Oportunidades | Resumen con acceso a los casos | Bloque propio de oportunidades con entrevista realizada |
| Uso más fuerte | Revisar desempeño y dirigir al equipo | Reunión diaria y acompañamiento operativo |
| Costo de lectura | Se comparan personas en una sola tabla | Se interpreta cada tramo del trabajo |
| Precaución | No convertirla en una tabla de 20 columnas | No repetir el problema de relegar resultados a alertas |

Las dos comparten indicadores y definiciones; cambia el orden de lectura.
El ejemplo usa seis analistas. La implementación debe soportar el equipo completo,
con nombres largos, ausencias de datos y distintos tamaños de pantalla.

## Indicadores que debería conocer un supervisor

| Dato | Decisión comercial | Período y definición |
|---|---|---|
| Capital confirmado y desglose por tipo | Saber cuánto produjo realmente el equipo | Mes comercial; misma valoración y ajustes que Facturación/Metas |
| Meta, avance y brecha | Saber cuánto falta y dónde apoyar | Misma base de capital y período que la meta publicada |
| Operaciones confirmadas | Entender volumen además del monto | No confundir operaciones con personas únicas ni cierres de conversión |
| Conversión oficial, por equipo y persona | Evaluar efectividad comercial | Núcleo oficial mensual; no promediar porcentajes individuales |
| Llamadas registradas y tasa de contacto | Distinguir volumen de esfuerzo y resultado del contacto | Hoy, Lima; contestadas / útiles, con mínimo de muestra vigente |
| Citas previstas, realizadas, pendientes y no asistidas | Acompañar entrevistas y recuperar oportunidades | Por fecha prevista; citas creadas hoy es otro indicador |
| Leads recibidos/asignados y primer intento | Revisar reparto y atención de la demanda | Definir asignación vs ingreso original; no usar el divisor mensual como «recibidos hoy» |
| Oportunidades por etapa y potencial declarado | Ver trabajo por cerrar y qué falta para avanzar | Foto actual, etapa real del CRM; monto declarado y cobertura |
| Primeras gestiones y tareas vencidas | Priorizar intervención por responsable y antigüedad | Acumulado al corte, calculado por las reglas vigentes |
| Capital y conversión por analista | Identificar apoyos concretos y aportación al equipo | Mensual con atribución oficial; separado de la composición actual del equipo |

En la portada dejaría seis o siete cifras principales, una tabla por analista y
tres intervenciones concretas. El resto debe estar a un clic. La maqueta prioriza
esa primera lectura; no pretende mostrar todos los desgloses finales a la vez.

## Qué existe y qué requiere completar

**Disponible en contratos del proyecto, pendiente de integración y conciliación:**

- Capital, metas y cumplimiento: `app/src/screens/hoy/datos-supervisor.ts:153`
  y `:215`. Hay valoración oficial y cobertura; no recalcular dinero en la maqueta.
- Conversión oficial del equipo: `datos-supervisor.ts:176`. Usa
  `useConversionMensual(..., 'equipo', ...)`; el total se sirve desde el núcleo.
- Meta individual y agregación por supervisor: `app/src/lib/objetivos.ts:136`
  (`objetivosDesdeConfiguracion` y `porVendedor`); `:675` conserva la meta de la
  misma foto del cumplimiento. La meta de conversión también existe (`:185`).
- Conversión por responsable en el payload mensual y su adaptación:
  `app/src/lib/conversion-vendedores.ts:534` (`adaptarConversionMensual`). Eso
  acredita un contrato, no la publicación o cobertura de cada cuenta real.
- Desglose de facturación por fecha comercial, tipo, moneda, analista y supervisor:
  `app/src/lib/facturacion.ts:33`, `app/src/data/crm-api.ts:4745`. Debe conservar el
  alcance exacto de la meta al comparar, incluyendo las reglas sobre renovaciones.
- Llamadas, útiles, contestadas, tasa, citas agendadas: `app/src/lib/gestion-diaria-analista.ts:39`.
- Equipo diario, tareas vencidas, citas y primeras atenciones:
  `app/src/lib/gestion-diaria-equipo.ts:17`. La fecha de actividad y el corte de
  pendientes son distintos; el contrato los separa.
- Cola vigente y detalle: `supervisor-mando.tsx:223`. No contar solo las siete
  filas de la vista previa ni sumar señales solapadas como si fueran personas únicas.

**No prometer como listo para usar sin confirmar:**

- Citas realizadas/inasistencias por fecha prevista: el resumen diario ya tiene
  parte del dato, pero no acredita por sí solo el desglose propuesto. Conciliar
  con el módulo Citas y definir anuladas, reprogramadas y entrevistas efectivas.
- Leads recibidos hoy por analista y oportunidades con entrevista realizada:
  confirmar agregados y listados con la misma definición, alcance y paginación.
  No derivar totales de una página parcial ni de una caché de leads incompleta.
- Detalle de conversión accesible al supervisor: comprobar autorización y
  disponibilidad. La nota del 27/09 documenta que la vista Conversiones completa
  era exclusiva de Gerencia; no enlazar al supervisor a una pantalla inaccesible.
- Paridad entre el universo de metas individuales, capital computable y total
  de equipo en producción, incluyendo traslados, snapshots y producción fuera
  del ranking. La maqueta usa deliberadamente un equipo estable con metas que
  suman exactamente la del equipo. El ejemplo no aprueba esa igualdad en todo caso.
- Comparativa con mes anterior al mismo corte, ritmo necesario por día hábil y
  estimación de cierre: requieren contratos comparables, calendario comercial y
  regla acordada. Se dejan fuera de estas maquetas para no inventar tendencias.
- Calidad de notas o «probabilidad de cierre» inferidas por IA: no se proponen
  como datos ya disponibles ni como evaluación automática del personal.

No hace falta crear un nuevo núcleo de indicadores. La primera implementación
debe componer los lectores existentes, demostrar que coinciden y completar solo
los agregados necesarios. Si exige SQL, presentar primero la propuesta exacta.

## Reglas para mantener la confianza

- Capital confirmado, capital potencial y meta deben distinguirse por nombre y
  ubicación. El potencial no es pronóstico ni venta garantizada.
- Dinero nuevo y renovaciones se separan en el desglose. No llamar captación nueva
  al total que incluye renovaciones.
- Cada tarjeta y columna indica mes, día o corte. La fecha usa Lima.
- La tasa de contacto del equipo es suma de contestadas / suma de útiles; no
  promedio de tasas. Conversión conserva el total canónico del servidor.
- «Sin meta», «Muestra insuficiente», «No disponible», «Provisional» y «Datos
  incompletos» son estados distintos. Un error no se convierte en cero ni en verde.
- Monedas separadas o valoración oficial con cobertura visible. Nada de tipos
  de cambio inventados ni sumas directas de soles y dólares.
- Identidad y ámbito del supervisor se respetan en cada lectura y cada detalle.
  Equipo actual para operación; atribución oficial para resultados mensuales.
- Al cambiar filtros, el detalle conserva el mismo ámbito, período y tipo.
  Los totales deben seguir siendo explicables con su listado completo autorizado.
- El porcentaje de meta puede superar 100%; se conserva el texto exacto aunque
  la barra visual se llene. No etiquetar como atrasado sin criterio temporal.
- Las intervenciones del prototipo son ejemplos redactados. Antes de automatizar,
  acordar selección y orden deterministas (brecha absoluta, vencimientos o etapa),
  manteniendo visible la razón. No inferir incumplimiento a partir de la brecha.
- Para la tabla A, unir la identidad de los responsables mensuales autorizados
  y el roster operativo permitido. Marcar traslado o falta de registro diario;
  no atribuir datos históricos al equipo actual por una unión ingenua.
- La ausencia de actividad registrada no demuestra ausencia laboral.

## Qué aportó 21st

Se buscó mediante el MCP de 21st y se inspeccionaron las imágenes de dos componentes:

- [Charts & KPI Cards, uvain](https://21st.dev/@uvain/components/revenue-charts-kpi):
  jerarquía de números y contexto de comparación. Se adapta a capital confirmado,
  meta y conversión; se evita copiar métricas de suscripciones que no sirven al CRM.
- [Leads Data Table, isaiahbjork](https://21st.dev/@isaiahbjork/components/leads-data-table):
  comparación compacta y acceso al detalle desde filas. Se adapta a analistas,
  con columnas comerciales y el tema claro navy/azul de Avance.

También se localizaron Efferd Dashboard 2, Total Sales Chart y Project Management
Table, sin necesidad de ampliar la selección. No se descargó código de componentes,
no se gastaron las dos recuperaciones diarias ni se instaló una dependencia.
No se envió información del equipo real a 21st.

## Verificación y límites

La entrega son tres archivos de maqueta y este análisis. No modifica la aplicación,
permisos, datos, reglas, dependencias ni publicación.

El JS de la maqueta interpola únicamente constantes ficticias. La integración
debe usar el renderizado escapado y los formateadores existentes del CRM, no copiar
el `innerHTML` ni el formateo tipográfico de este prototipo.

- PASS: sintaxis de `propuestas.js` con `node --check`.
- Revisión visual y navegación: resultados en `VERIFICACION.md`.
- E2E del CRM, build y gate de realidad: NOT RUN, por tratarse de una propuesta
  aislada del runtime del producto. La inspección visual productiva no los sustituye.

## Memoria relacionada

[[Hoy del supervisor - puesto de mando en una pantalla, plan (2026-09-27)]] ·
[[Gestion Diaria - supervisor horizontal aprobado (2026-09-23)]] ·
[[Gestion Diaria - supervisor con consulta por fecha (2026-09-24)]] ·
[[Facturacion - auditoria completa (2026-10-08)]]
