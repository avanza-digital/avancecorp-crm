# Tipo de cambio fijo por venta desde octubre de 2026

Fecha: 2026-10-16. Estado: IMPLEMENTACIÓN CANDIDATA VERIFICADA LOCALMENTE; preparada para activación por flujo autorizado, sin publicación productiva. Progreso y verificaciones en [ESTADO.md](./ESTADO.md).

## Resultado solicitado

Desde el **1 de octubre de 2026**, cada venta conserva un equivalente comercial en soles calculado con la tasa de su fecha comercial. Consultar el ranking otro día o cerrar el mes no vuelve a convertir esa venta con otra tasa.

Ejemplo ilustrativo: US$ 20 000 vendidos el 02/10 con TC 3,4000 aportan S/ 68 000. Aunque el TC posterior sea 3,1000, esa operación sigue aportando S/ 68 000. Una segunda venta tiene su propia fecha y valoración.

El alcance es el capital comercial confirmado: Ranking, cumplimiento de Metas y las superficies que afirman mostrar esa misma producción (resúmenes, Equipo y Facturación, incluido su detalle y exportaciones existentes). Estimaciones de leads, oportunidades abiertas, stock financiero y pagos requieren conservar su significado propio; no se convierten automáticamente en ventas comerciales por este cambio. La fase 1 clasifica los consumidores para aplicar una sola regla a todas las cifras comparables.

## Evidencia verificada

- `supabase/functions/crm-tipo-cambio/handler.ts`: calcula el promedio de hasta siete puntos medios SBS compra/venta publicados hasta un corte, buscando en una ventana de 16 días y redondeando a cuatro decimales. Solo conserva caché en memoria durante una hora. La función publicada comprobada en esta sesión es v13, con `verify_jwt=true`.
- `app/src/lib/conversion-vendedores.ts`, `clasificarRankingCapitalTotal`: obtiene los agregados PEN/USD y los convierte con una única tasa recibida de la pantalla. Esta es la causa del movimiento del capital sin nuevas ventas.
- `private.capital_episodios`: es el núcleo compartido de capital. Expone contratos, cooperativas y desgloses, con monto, moneda, fuente y fecha. Contratos utilizan `fecha_cierre_comercial`; cooperativas utilizan `fecha_imputacion` o, para legadas sin esa fecha, la fecha de creación. Hay que conservar esa diferencia como dimensión de atribución, sin confundirla con la fecha de valoración.
- `private.produccion_mes_por_vendedor` alimenta cumplimiento y el sellado. `private.facturacion_operaciones` consume los episodios de medida `stock`. El equivalente debe seguir estos mismos eventos y reglas de cómputo; no sumar otra vez el stock y sus desgloses.
- `crm.cumplimiento_metas_fn` envuelve otras funciones y devuelve fotos para meses cerrados. El frontend contiene validaciones estrictas: una ampliación de payload necesita compatibilidad con el bundle que esté publicado.
- Lectura productiva de esta sesión: octubre tiene 89 episodios `stock` PEN por S/ 3 885 000 y 17 USD por US$ 195 423,33. Es un inventario inicial, no una lista congelada para el despliegue ni una certificación de elegibilidad final de cada reporte. Se vuelve a censar antes de activar.
- La última revisión de metas de octubre tiene objetivo USD total cero. El objetivo PEN agregado es S/ 7 100 000. La nueva valoración no debe revaluar una meta.
- Entre agosto y meses posteriores, la consulta de `crm.periodos_cerrados` devolvió únicamente agosto. Octubre no está sellado al momento de esta lectura; volver a verificar bajo el candado de cierre al activar.

## Contrato de negocio propuesto

1. **Vigencia por fecha comercial:** operaciones con fecha comercial desde `2026-10-01`, en `America/Lima`. La fecha en que alguien digita o confirma no decide la tasa ni la vigencia. Una venta de septiembre cargada en octubre sigue el régimen anterior; una venta de octubre cargada en noviembre abierto utiliza su fecha de octubre. La ventana de carga y los permisos existentes siguen siendo autoridad.
2. **Método de promedio conservado, con consolidación más estricta:** promedio de siete fechas publicadas de los puntos medios compra/venta SBS vía BCRP, con corte en la fecha comercial. Para la política nueva se exigen ambas series y siete pares completos; no se congela como definitiva una compra aislada mientras falta su venta. Se empieza consultando 16 días y se amplía a 32 y 64 si es necesario; con menos de siete pares, queda pendiente. Esta restricción de calidad se aplica a la nueva política, sin cambiar el calculador legado. No se introduce una elección manual de compra, venta o tasa por analista.
3. **Una tasa consolidada por fecha y versión:** para corte D, consolidar cuando ambas series hayan publicado D o una misma fecha posterior a D y estén completos los siete pares más recientes hasta D. La consulta de verificación puede avanzar después de D para comprobar publicación, pero esas cotizaciones posteriores nunca entran al promedio. Si la unión de las series tiene una fecha hasta D sin el otro lado, no saltarla para completar siete con una fecha más vieja: mantener pendiente. Así, fin de semana/feriado se confirma con la publicación posterior y utiliza datos anteriores. Un HTTP 200 o una hora arbitraria no prueban consolidación. Una vez consolidada, la tasa no se refresca por TTL ni se sustituye automáticamente ante revisiones del proveedor. La primera semana de implementación se simula esta condición contra respuestas reales y parciales de ambas series.
4. **Valoración por operación:** PEN usa tasa 1 y el mismo importe. USD usa la tasa consolidada de su fecha comercial. Cálculo monetario en Postgres con `numeric`; tasa con cuatro decimales, equivalente con dos y redondeo por operación. El total es la suma de equivalentes ya redondeados, también al consultar el detalle o exportar.
5. **Fecha comercial y mes de imputación separados:** una corrección que solo redistribuya una operación entre meses no debe darle la tasa del nuevo mes. Si una corrección autorizada cambia la fecha comercial real, monto o moneda, produce una nueva revisión auditada de valoración. No hay reinterpretación silenciosa. El caso de una venta anterior a octubre imputada a octubre debe detectarse en el inventario y ensayarse expresamente conservando su régimen de valoración original.
6. **Fuente de verdad en backend:** el navegador recibe el equivalente confirmado y el estado de cobertura; deja de multiplicar los dólares acumulados por la tasa de hoy para el capital comercial de este régimen.
7. **Historia hasta septiembre:** conserva el cálculo anterior y las fotos existentes, incluso si septiembre sigue abierto. En vistas mensuales históricas se conserva el corte del último día de ese mes. Un rango agosto-octubre agrega agosto con TC al 31/08, septiembre con TC al 30/09 y octubre con las valoraciones de cada venta; guarda política y corte de cada tramo. La fase 1 verifica los contratos publicados de cada consumidor y expresa cualquier diferencia en el informe antes/después; no reutilizar la única tasa del último mes para todo el rango.
8. **Tasa del día aún no publicada o BCRP indisponible:** registrar la venta y dejar su equivalencia pendiente con reintentos persistentes. Mantener visible el **último ranking completo**, rotulado con su fecha de corte, y mostrar aparte las ventas posteriores pendientes de valoración y su moneda original. No asignarles puesto ni presentar ese ranking anterior como actualizado a hoy. Al completar todas las valoraciones del siguiente corte, avanzar el ranking oficial de manera consistente; si nunca hubo un corte completo, mostrar las ventas y el estado pendiente sin puestos. Mantener D como corte de la tasa implica esta espera; usar D-1 sería otra decisión de negocio y no forma parte de este plan. No inventar una tasa ni contar una operación pendiente como cero.
9. **Metas:** conservar los objetivos en PEN. Si en un mes futuro se permite publicar una meta con componente USD, fijar su equivalente al publicar esa revisión y conservarlo en el sello. Nunca convertir una meta con la tasa de consulta.
10. **Anulaciones y ajustes:** conservar las reglas vigentes de qué afecta capital; en particular, anular una conversión de cooperativa no significa retirar su capital automáticamente. Cuando una regla vigente produzca un ajuste monetario, vincularlo a su operación y utilizar su valoración original, incluyendo ajustes parciales y arrastres; no convertir la deuda con la tasa del día de descuento. Los meses anteriores no guardaron equivalentes PEN: si una de esas ventas origina un ajuste desde octubre, reconstruir una sola vez su equivalencia con la metodología legada al último día del mes original, marcarla `reconstruida_legada` y referenciarla sin reescribir ese mes. No afirmar que esa valoración ya existía. La fase 1 debe comprobar si cada deuda conserva el id de origen; si no lo conserva, incorporar el vínculo trazable y resolver su correspondencia antes de activar, sin repartir deudas agregadas entre ventas por suposición.

Fechas por fuente:

| Fuente | Fecha de valoración | Mes de atribución y corrección |
|---|---|---|
| Contrato | `public.contratos.fecha_cierre_comercial` | El núcleo mantiene su atribución vigente. Corregir la fecha real genera revisión de valoración. |
| Renovación/upgrade y sus desgloses | Valoración del contrato resultante; las partes referencian esa valoración | `operaciones_cartera.fecha_operacion` y `periodo` conservan su significado de reporte; no crean una segunda tasa para las partes. Si contradicen el contrato, resolver el caso antes de activar. |
| Cooperativa | `crm.cierres_externos.fecha_comercial`, columna confirmada en el catálogo productivo | `fecha_imputacion` decide el mes/rango que hoy utiliza el núcleo. Corregir solo la imputación conserva el TC; corregir la fecha comercial real crea revisión. |
| Cooperativa legada sin fecha comercial | Fecha acreditada mediante revisión del dato; como candidatos se examinan imputación y `(creado_en AT TIME ZONE 'America/Lima')::date` | No sustituir silenciosamente fecha de venta por digitación. La operación queda pendiente si la fecha no se puede acreditar. Registrar el origen del dato resuelto. |

La frontera de octubre se evalúa con esta fecha de valoración acreditada. Una cooperativa de septiembre imputada en octubre mantiene el régimen legado; su equivalente se reconstruye con el corte de septiembre, sin alterar septiembre.

## Fase 1 — Inventario y simulación

- Extraer las definiciones productivas vigentes y dependencias de los núcleos mencionados, escritores, correctores, anulaciones, ajustes y `crm.cerrar_periodo`; contrastar con migraciones y bundle publicado.
- Censar operaciones de octubre por fuente, moneda, fecha comercial, fecha de imputación, categoría y medida. Detectar contratos sin fila en `crm.inversiones`, fechas faltantes, importaciones, duplicados, pruebas y operaciones que no participan en cierto reporte.
- Identificar cada consumidor de capital confirmado y su semántica: bruto, neto de ajustes, categoría, población y rango. Conservar las diferencias comerciales vigentes aunque compartan valoración.
- Descargar la información BCRP para las fechas necesarias y calcular una simulación por operación y analista. Conservar fuente, intervalos y evidencia suficiente para reproducirla.
- Entregar comparación actual/propuesta: monto PEN, USD, equivalente, avance de meta y posición. Separar el efecto esperado de cambiar de método de cualquier diferencia de población o elegibilidad.
- Comprobar las políticas de día consolidado, fechas retroactivas, correcciones de fecha y ajustes parciales con casos concretos antes de escribir la migración.
- Comprobar vínculo de cada ajuste/deuda USD con su operación de origen y el contrato de fecha de cada fuente; cualquier origen ambiguo impide activar ese conjunto como completo.

**Salida:** censo reproducible, mapa de consumidores y muestra conciliada. Producción continúa con la regla actual.

## Fase 2 — Persistencia y proceso de valoración

Modelo orientativo, sujeto al inventario:

- `crm.tipo_cambio_diario`: fecha comercial de corte, versión de política, tasa consolidada, series/fuente, días utilizados, intervalo, períodos y valores compra/venta efectivamente usados, huella de la respuesta y fecha de consolidación. Los valores guardados permiten reproducir el promedio aunque la fuente revise su historia; una huella sola no basta. Restricción única por fecha y política. Solo el proceso autorizado puede crear una consolidación; las consolidadas son inmutables.
- `crm.capital_valoraciones`: identidad estable de fuente (`contrato` o `cierre_externo`) e id, revisión de datos fuente, fecha comercial, monto y moneda originales, referencia a tasa/política, equivalente PEN, estado, registro y procedencia (`historica` o `nueva`). Las revisiones se agregan con motivo y referencia a la anterior; no se sobrescriben importes históricos.
- Identificar por la fuente financiera canónica; no usar solo el lead o el analista como clave: un cliente puede tener varias operaciones. Los desgloses deben referenciar la valoración de su operación y tener una regla de reparto que concilie al céntimo con el stock, sin doble conteo.
- Aplicar RLS, auditoría y permisos mínimos. Los usuarios del CRM no pueden escribir tasas ni equivalentes. Las lecturas conservan la visibilidad existente del analista, supervisor, coordinación y gerencia; no se expone un registro global de ventas.
- Reutilizar el calculador existente de `crm-tipo-cambio`, aislando la lectura pública del BCRP de la escritura privilegiada. La operación de consulta autenticada no adquiere permiso para establecer tasas arbitrarias.
- Proceso persistente e idempotente con reclamación, reintentos y detección de revisiones: se alimenta de las operaciones confirmadas y reconcilia periódicamente todo evento canónico que aún no tenga valoración vigente. Esto cubre altas del portal y cargas que no pasan por el wizard del CRM, sin añadir triggers a `public`.
- La consulta HTTP al proveedor ocurre fuera de la transacción monetaria. El sellado de la tasa y la asociación de cada equivalente se validan y confirman en transacciones cortas. Una tasa creada por dos workers concurrentes sigue teniendo una sola versión consolidada.
- Una valoración se considera válida solo si coincide con la revisión, fecha, moneda y monto fuente actuales. Un cambio genera revisión pendiente y evita mostrar el valor anterior como si siguiera siendo correcto.

Decisión de arquitectura: conservar valoraciones por operación además de tasas diarias. La alternativa de guardar solo tasas y calcular `round(monto * tasa, 2)` en cada lectura logra estabilidad cambiaria con menos proceso; se descarta para este alcance porque se pide guardar el equivalente comercial aceptado y vincular ajustes parciales a su revisión de origen, incluso antes de cerrar mes. La tabla de valoraciones es un registro derivado auditable, no otra autoridad de ventas. Con una tasa ya consolidada, los escritores CRM calculan la nueva revisión en su transacción sin esperar una llamada al BCRP; el reconciliador cubre escritores del portal y otros caminos. Antes de activar se mide ese rezago y se comprueba la regla de corte completo.

**Salida:** modelo y proceso probados en entorno aislado, aún sin cambiar el ranking oficial.

## Fase 3 — Núcleo de lectura y cierre mensual

- Añadir el equivalente comercial y su cobertura a través de los núcleos existentes; conservar los agregados originales PEN/USD y la atribución vigente. El modelo sirve Ranking, Metas, Facturación y cada consumidor de la misma medida.
- Tratar explícitamente las diferencias de bruto/neto y ajustes. Las mismas operaciones y el mismo ámbito deben conciliar al céntimo; cifras con significados distintos no se fuerzan a coincidir.
- Extender la foto mensual para incluir equivalente, política y trazabilidad de valoraciones/ajustes. `cerrar_periodo` debe tomar el mismo candado que la activación y las correcciones; no sellar mientras existan operaciones incluidas sin valoración consolidada.
- Ensayar el cierre real con reloj simulado. La ausencia de sellos previos se comprueba en el preflight y bajo candado, no dentro de una rama del núcleo que pueda cambiar de resultado porque `cerrar_periodo` ya insertó la cabecera del sello.
- Con cobertura pendiente, el sello de ese mes es atómico: se posponen todos sus componentes (capital, conversión y aplicación de ajustes), se informa el motivo y el ciclo conserva el siguiente intento programado. El worker reintenta a 1, 5, 15 y luego cada 60 minutos; al completar cobertura solicita una nueva evaluación por el ciclo autorizado. Si el plazo de cierre se retrasa más de 24 horas, Gerencia ve estado `atascado` y el motivo; no hay cierre forzado por antigüedad ni tasa de emergencia. La espera puede continuar hasta resolver la fuente/dato. Preservar meses ya sellados y el funcionamiento por mes del ciclo existente. Si el cron está pausado, no reactivarlo como efecto lateral de este cambio.
- Publicar un contrato de lectura versionado o una ampliación compatible, tras revisar todos los envoltorios y validadores estrictos. Durante la transición el bundle antiguo debe seguir funcionando. La activación de la presentación se coordina con la publicación del bundle compatible.

**Salida:** APIs y sello sirven el equivalente guardado y una cobertura verificable.

## Fase 4 — Completar octubre y adaptar pantallas

- Poblar las tasas históricas necesarias y las valoraciones de las operaciones ya registradas desde el 01/10. Marcar que son reconstrucciones con datos históricos de la fuente: no se conoce qué dato estaba visible exactamente al instante de digitación pasado.
- Ejecutar el relleno por identidad/revisión de operación, con controles antes/después y posibilidad de repetirlo sin duplicar. Seguir procesando las ventas que entren durante el relleno y repetir la reconciliación al activar.
- Adaptar Ranking, Metas, resúmenes, Equipo y Facturación donde muestran capital comercial confirmado. El equivalente nuevo no pasa otra vez por `totalEnSoles(PEN, USD, tcActual)`.
- Mostrar el desglose original de monedas y un rótulo como «Capital en soles con TC fijado por venta». El detalle identifica fecha, tasa y equivalente de cada operación; evita anunciar una única tasa mensual si existen varias.
- Mantener el selector de meses anteriores y probar rangos que mezclen septiembre y octubre. Diferenciar las estimaciones de oportunidades de las ventas ya valoradas.
- Revisar en móvil y con roles reales la cobertura pendiente y la recuperación tras completarla.

**Salida:** octubre completo con equivalentes fijos y UI compatible; prueba de que cambiar la tasa consultada no mueve el capital confirmado.

## Fase 5 — Validación y activación

Casos mínimos de aceptación:

| Caso | Resultado esperado |
|---|---|
| US$ 20 000 el 02/10, tasa consolidada 3,4000; consulta posterior 3,1000 | S/ 68 000 en cada consulta y en el sello |
| Otra venta de US$ 10 000 con tasa 3,1000 | Suma S/ 31 000; acumulado de ambas S/ 99 000 |
| Venta en PEN | Importe comercial idéntico |
| Venta de septiembre digitada en octubre | Régimen anterior por fecha comercial |
| Venta de octubre digitada después | Tasa de la fecha de octubre; se respeta la ventana de carga |
| Dos ventas en la misma fecha, antes y después de publicación BCRP | Comparten una tasa consolidada; la primera puede estar pendiente inicialmente |
| Solo compra publicada para D; venta pendiente | No consolidar ni reemplazar un par incompleto con una fecha antigua |
| Menos de siete pares en 16 días | Ampliar ventana; pendiente si no se obtienen siete pares completos hasta D |
| Feriado, fin de semana o BCRP sin dato del día | Política explícita de consolidación y últimos datos válidos; sin tasa provisional presentada como definitiva |
| Caída del proveedor o venta del día sin cotización aún | Venta registrada, recuperación idempotente y último ranking completo fechado; pendientes visibles sin nuevos puestos |
| Corrección autorizada de fecha/monto/moneda | Nueva revisión coherente y auditada; no reutiliza una valoración incompatible |
| Cooperativa USD con cambio de imputación y misma fecha comercial | Conserva tasa/valoración; cambia solo el ámbito temporal autorizado |
| Cooperativa legada sin fecha acreditable | Pendiente explícito; no se inventa fecha comercial |
| Desglose con fecha/periodo distintos del contrato | Detectar en preflight y conciliar; ninguna tasa independiente ni doble conteo |
| Anulación, deuda parcial, arrastre y cambio de mes | Regla comercial vigente con valoración de origen; sin duplicación ni nueva cotización |
| Ajuste USD de venta anterior a octubre | Reconstrucción legada identificada y vinculada al origen, sin reescribir el mes anterior |
| Reasignación, baja de analista o cambio de supervisor | Atribución existente; conserva la valoración de la operación |
| Nuevo, renovación, upgrade y cooperativa | Conservan elegibilidad y cómputo; desgloses y stock no se suman dos veces |
| Reejecución del relleno y dos workers concurrentes | Una valoración vigente por operación/revisión y una tasa consolidada por fecha/política |
| Cierre y corrección simultáneos | Foto consistente o rechazo explícito bajo el candado común |
| Cierre automático con fuente caída | Mes entero pendiente, reintentos y estado atascado a las 24 horas; sin foto parcial |
| Usuario sin permisos o modificación desde navegador | No puede establecer tasas, equivalentes ni consultar operaciones ajenas |
| Cambio de reloj o consulta después de cerrar mes | Equivalente y posición sellados estables |
| Agosto y septiembre antes/después | Misma semántica y resultados; comparar dentro del mismo estado de datos y omitir solo marcas temporales |
| Rango agosto-octubre | Dos tramos mensuales legados con sus cortes y octubre por venta; sin TC global |

Verificación de implementación:

- SQL de dominio, concurrencia, permisos y matriz RLS pertinente sobre una instancia/rama aislada con esquema a paridad.
- Preflights existentes del backend, tests del calculador/worker y pruebas de fronteras de payload.
- Desde `app/`, `npm run check` y E2E locales Docker de los flujos afectados (`npm run test:e2e:docker`). Si Docker está apagado, reportar `NOT RUN`, nunca PASS.
- Tipos regenerados si cambia el contrato/schema y Supabase Advisors antes/después.
- Ensayo del sellado de octubre con reloj simulado, relectura posterior y reversa. No usar producción como banco de pruebas.
- Una revisión independiente de arquitectura/finanzas/datos conforme a `.ai/REVIEW_PROTOCOL.md`; el dictamen asesora y no sustituye los checks.

Orden de activación:

1. Preflight actualizado: huellas vigentes, octubre sin sello, copia/simulaciones, cobertura y datos del mes conciliados. Rechazar si cambió una precondición importante.
2. Cambios de schema por la rama de Supabase autorizada y nuevas migraciones documentadas; nunca alterar migraciones ya versionadas ni tablas/triggers/policies de `public`.
3. Desplegar proceso de valoración y API compatible; completar octubre y las entradas concurrentes.
4. Preparar bundle compatible desde el commit verificado en `avancecorp/main`. La publicación frontend sigue la invocación humana del flujo de release del proyecto.
5. Activar la presentación nueva solo con cobertura completa y cliente compatible; comprobar autenticación, ámbitos, cifras, detalles y etiqueta de versión.
6. Verificación productiva de solo lectura y registro del antes/después por fuente y analista. Separar claramente el cambio esperado de octubre de cualquier fallo de conciliación. Preparar un aviso corto para analistas y supervisores con fecha de vigencia, razón de la corrección de octubre y significado del corte completo; su envío requiere la autorización de comunicación correspondiente.

Reversa: ensayada antes de activar. Ante un fallo, suspender la presentación de la medida nueva y volver al bundle/lectura compatibles anteriores con estado visible; conservar tasas, valoraciones, revisiones y evidencias. No volver a valorar registros ya consolidados ni borrar la auditoría. No cambiar un mes que haya quedado sellado con la nueva regla; su lectura necesita seguir entendiendo la versión guardada.

## Criterio de terminación

El trabajo estará completo cuando las ventas desde el 01/10/2026 tengan valoración reproducible, todos los consumidores de esa producción usen el mismo equivalente, las consultas posteriores del BCRP no lo modifiquen, el cierre guarde ese resultado y agosto/septiembre conserven su comportamiento anterior. Ninguna validación se da por aprobada sin ejecución y evidencia.

## Revisión del plan y estado de validación

Revisión independiente de Claude por `scripts/claude-review`, 16/10/2026: `CHANGES_REQUESTED`, confianza media por evidencia acotada. [Dictamen original](./REVISION-2026-10-16.txt). El PRIMARY incorporó reglas explícitas de fecha por fuente, consolidación de ambas series, siete pares, último ranking completo, reconstrucción de ajustes legados, reintento de cierre y rangos mixtos. Evaluó la alternativa de solo tasas diarias y documentó por qué se conservan revisiones por operación.

Matiz de evidencia: el reviewer infirió de los episodios que cooperativas no tenían otra fecha; el catálogo productivo sí confirma `crm.cierres_externos.fecha_comercial`. Se utiliza esa columna para la valoración, manteniendo separada la imputación. El dato que hoy todas las cooperativas de octubre sean PEN y tengan ambas fechas iguales no sustituye las pruebas USD y reimputación exigidas.

Esta revisión inicial no es un PASS de implementación. La implementación posterior, sus ensayos SQL/frontend/HTTP y la evaluación de hallazgos se registran en [ESTADO.md](./ESTADO.md); no inferir que la activación o las pruebas completas están terminadas por el dictamen de planificación.

## Referencias

- Memoria del proyecto: `Ranking de capital total unificado (TC BCRP)`, `Rankings por mes calendario (decision 2026-09-02)`, `Cierre de mes`, `Conversion - renovaciones sin aporte desde octubre (2026-10-12)` y `Conversion - adicional de renovacion como upgrade probado en branch (2026-10-14)` en el vault.
- `supabase/migrations/LEEME.md`: tablas nuevas en `crm`, RLS/auditoría, compatibilidad de envoltorios y prohibición de alterar `public`.
- `.ai/VERIFICATION.md` y `.ai/REVIEW_PROTOCOL.md` están en la raíz Git, un nivel por encima de este subproyecto.
- [Supabase: Database functions](https://supabase.com/docs/guides/database/functions) y [Edge Functions: Development tips](https://supabase.com/docs/guides/functions/development-tips): límites entre cálculo transaccional de datos y acceso HTTP externo. Documentación consultada durante la planificación; no constituye evidencia de ejecución de este plan.
