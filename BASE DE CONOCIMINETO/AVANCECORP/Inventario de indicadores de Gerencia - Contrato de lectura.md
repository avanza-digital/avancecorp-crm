---
tags: [crm, gerencia, metricas, inventario, contrato-de-lectura]
requerimiento: REQ-GER-MET-001
punto: 1
estado: punto-1-completo-sin-implementacion
fecha: 2026-09-04
---

# Inventario de indicadores de Gerencia — contrato de lectura

Entregable del punto 1 de [[Plan de correccion de metricas de Gerencia - requerimiento vigente]]. Evidencia de problemas en [[Auditoria de metricas de Gerencia - hallazgos y plan 2026-09-04]]. Registro de comprobaciones: [[Inventario de indicadores de Gerencia - Evidencia y verificacion]]. Punto de entrada del proyecto: [[Inicio]].

## Para qué sirve y qué no cambia

**Línea base documental:** las etiquetas y conexiones inventariadas corresponden al corte del punto 1. Los cambios posteriores de pantallas están registrados en [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]]; consultar esa nota y el plan vigente antes de retomar, sin reinterpretar los hallazgos originales como estado actual.

Este inventario define **qué significa cada indicador y de qué dato del servidor proviene actualmente**. Incluye las transformaciones existentes del navegador cuando el número no llega agregado. Distingue la definición real del nombre que la pantalla utiliza; describir una inconsistencia no la convierte en regla aprobada.

No modifica núcleos, funciones, cálculos, datos, permisos ni pantallas. No implementa los puntos 2–5 del requerimiento. No autoriza SQL ni publicación. Las alternativas para datos faltantes se documentan como decisiones pendientes, no como nuevos cálculos.

Un indicador incluye una tarjeta, porcentaje, cantidad, serie/gráfico, total de tabla, comparación o estado cuantitativo que Gerencia usa para interpretar el negocio. Las repeticiones idénticas se agrupan con sus alias y pantallas; **una misma etiqueta con distinta fuente, período o población es otro indicador**. Los valores editables de configuración se distinguen de resultados medidos, y los datos individuales de fichas se identifican sin tratarlos como totales empresariales.

## Cómo leer el inventario

Las tres notas detalladas forman un único entregable:

1. [[Inventario de indicadores de Gerencia - Comercial]]: Resumen, Conversiones, Ranking, Rendimiento, Metas y lecturas comerciales de Gestión de equipo.
2. [[Inventario de indicadores de Gerencia - Citas y operacion]]: Citas, Pipeline, Leads, Agenda, Repartir, Base para gestión, Alertas y lectura operativa del equipo/ficha de lead.
3. [[Inventario de indicadores de Gerencia - Cartera y configuracion]]: clientes, contratos, operaciones, cooperativas, fichas y configuración.

Los identificadores `C`, `O` y `K` permiten localizar un indicador aunque cambie su texto. Cada sección registra las dimensiones comunes; cada fila añade campo exacto, significado y excepciones. El contrato completo de una fila es **su definición más las condiciones comunes de su fuente/sección**.

Por indicador se requiere: etiqueta/ubicación, pregunta o significado, fuente del servidor y campo, transformación/consumidor, unidad, fecha, ámbito/atribución, exclusiones y disponibilidad. Una suma local se declara como tal; no se atribuye a un RPC que la pantalla no consume.

## Diccionario comercial común

| Concepto | Qué mide | Fuente y diferencia que debe conservarse |
|---|---|---|
| Llegadas comerciales | IDs de leads que ingresaron originalmente en el rango, de Landing/Formulario/Referido | `private.conversion_episodios`, filas `tipo='recibido'`; `fecha_divisor=leads.creado_en`. No equivale al número de asignaciones ni a personas deduplicadas por DNI |
| Base automática de conversión | Llegadas automáticas Landing/Formulario que aportan al divisor | Suma servida de `aporte_divisor`; manuales y referidos pueden ser llegadas aunque aporten cero. No llamar total de llegadas al `divisor` |
| Asignaciones/entregas | Episodios o movimientos de entrega de un lead a un responsable | Ledger `crm.lead_asignaciones` y agregadores operativos. El mismo lead puede generar varios; `asignado_en` no es su alta original |
| Cierres de leads | Hechos de cierre registrados en el ledger y admitidos por la lectura correspondiente | `conversion_episodios.tipo='cierre'`, fecha `coalesce(resultado_en,finalizado_en)`; autor del cierre, no primer receptor. Un conteo de leads cerrados no prueba clientes únicos por perfil ni contratos únicos |
| Operaciones contabilizadas | Primera operación elegible de cartera por cliente/mes, seleccionada antes de recortar rango/ámbito | `conversion_episodios.tipo='operacion'`; `operacion_id`, `fecha_numerador`, `aporte_numerador`. Una bandera de elegibilidad en el listado no prueba que esa operación haya ganado la deduplicación |
| Conversión comercial | Índice ponderado del período, con cierres, operaciones y ajustes que correspondan | Porcentaje servido por la salida de rango o mensual. No significa «ese porcentaje de las mismas llegadas se convirtió»; puede incluir arrastre y cartera |
| Resultados del lote/cohorte | Progreso y cierres de los leads que llegaron en el rango, observados hasta el corte de seguimiento | Campos `cohorte`, `origenes`, `responsables` de la lectura de conversión. El rango selecciona llegadas, no necesariamente fechas de los eventos posteriores |
| Avance inferido del embudo | Leads con señales históricas o etapas posteriores que activan etapas previas | `private.metricas_conversiones_implementacion`; propuesta/cierre puede activar cita sin registro de ella. No es asistencia registrada |
| Citas | Tareas activas de tipo reunión cuya fecha prevista pertenece al rango | `private.citas_episodios`, una fila por `tarea_id`; `vence_en`, estado actual y sus banderas. Un lead puede tener varias citas |
| Citas realizadas | Citas del rango previsto cuyo estado registrado es `completada` | Bandera `realizada` del núcleo de citas. El recorte no es por fecha de marcado como completada, y no certifica por sí solo presencia física fuera del sistema |
| Inventario/carga actual | Existencias de leads/tareas/clientes en el ámbito de la consulta | «Activo», «abierto», «asignado» y «visible» tienen filtros diferentes según el campo. No interpretar inventario como captación de un período |
| Capital estimado | Monto estimado de leads de una población operativa | `leads.monto_estimado` por moneda; no es inversión confirmada ni debe sumarse al capital contractual |
| Capital confirmado del período | Producción económica atribuida al período comercial de la lectura | Agregados de capital/cumplimiento. Distinguir producción bruta/neta, contrato, cooperativa y desglose según la salida concreta |
| Capital vigente | Saldo de la población de contratos/operaciones en estado admitido por esa lectura | Puede consultar todo el historial y filtrar estado. No equivale a capital ingresado este mes |
| Meta y cumplimiento | Objetivo configurado y grado de avance contra ese objetivo | Meta publicada y realización servida; porcentaje comercial y porcentaje de cumplimiento son unidades diferentes |
| Contador de listado | Cantidad de elementos descargados, filtrados o seleccionados | No es automáticamente total del servidor. La nota precisa paginación, filtros y límites en cada caso |

### Reglas actuales del núcleo de conversión

Definición productiva leída en esta ejecución, no inferida sólo del vault:

- Una llegada por ID y fecha original, sin filtrar por etapa actual. Primera asignación buscada en toda la historia, con desempate por `asignado_en`, `ciclo_n`, `episodio_n`, ID. Sin asignación, cuenta en empresa y no se inventa un responsable.
- Llegadas: sólo Landing/Formulario/Referido. Divisor 1 sólo en Landing/Formulario con `alta_manual=false`; el resto 0.
- Cierres: el ledger puede emitir también otros orígenes con aporte0; **contar todas las filas `tipo='cierre'` sin las condiciones del consumidor no equivale al conteo comercial elegible**. Cierres anulados aportan0. Landing/Formulario aporta1; Referido usa el peso aplicable.
- Cartera: se elige una operación elegible por `cliente_id,periodo`, ordenada por fecha de operación, creación e ID; después se aplica la ventana pedida y el ámbito. Renovación usa el peso del referido, actualmente 0,15; upgrade 1. Ambas aportan 0 al divisor.
- Atribución de la operación: analista atribuido a la cadena de contrato, con fallback al vendedor registrado. No confundirlo con quien digitó la operación o con el dueño actual del cliente.
- El agregado publicado resuelve porcentajes, ajustes, datos sin base y fotos mensuales. El inventario no introduce otra fórmula para sustituirlo.

### Reglas actuales del núcleo de citas

- Fuente `crm.tareas`, `tipo='reunion'`, `activo=true`, `vence_en` dentro de `[inicio,fin)`.
- `debio_ocurrir`: vence antes o en el instante de corte. `realizada`: estado completada. `no_show`: estado no_show.
- Cancelada por asesor: estado cancelada y `cancelada_por='asesor'`; por sistema: cancelada y distinto de asesor, incluido nulo según SQL.
- Reprogramada es su propio estado. Pendiente de cierre exige pendiente y fecha vencida; futura exige pendiente y fecha posterior al corte.
- El núcleo no filtra por origen comercial ni fuerza unicidad por lead. Pactadas conserva canceladas; los agregadores de realización/asistencia deciden sus divisores explícitos, descritos en la nota operativa.

### Reglas actuales del núcleo de capital

- La salida distingue **`medida='stock'`, `medida='desglose'` y la excepción nula**. No sumar stock y sus partes como si fueran capital adicional.
- Contratos y desgloses se recortan por día comercial local; cooperativas por instante de registro. Para comparaciones diarias, las fronteras deben ser medianoches de Lima.
- Excluye contratos `es_demo=true`, incluyendo sus desgloses. Atribuye contratos/desgloses al analista de la cadena; cooperativa al vendedor del cierre. `registrado_por` se conserva aparte.
- El estado actual del contrato se entrega, no se convierte automáticamente en una exclusión general: cada pregunta de producción o saldo filtra lo correspondiente.
- **Cooperativas anuladas conservan capital** por la regla vigente ATR-4, salvo la excepción demo explícita que produce medida nula y monto0. La anulación en conversión no implica eliminar automáticamente capital. No aplicar la antigua nota «todos los anulados aportan0» a esta definición viva.
- `en_roster` es informativo; no autoriza eliminar capital de una persona fuera de la nómina. PEN y USD son dimensiones separadas. Una consolidación necesita el tipo de cambio y corte que el consumidor declara.

## Tiempo, población y disponibilidad: contrato transversal

1. **Rango libre**: `desde` y `hasta` visibles son inclusivos para el usuario; servidor usa inicio de `desde` y principio del día posterior a `hasta` en Lima. Los campos concretos (`creado_en`, `asignado_en`, `vence_en`, fecha comercial) no son intercambiables.
2. **Mes de Gerencia**: `periodoMesCalendario` selecciona mes completo histórico o mes actual hasta hoy. En Resumen/Conversiones, el mes asociado se determina por la fecha final del rango; algunos bloques son mensuales aunque otros sean de rango.
3. **Seguimiento vivo**: los resultados del lote pueden mirar cierres posteriores al rango hasta hoy. Las series agrupadas por llegada no son series por fecha real de cierre.
4. **Foto sellada**: lectura mensual histórica y cohorte viva son fuentes distintas. No recalcular una foto sellada desde las tablas actuales para hacerla coincidir con otra pantalla.
5. **Ámbito**: Gerencia puede tener alcance global, pero la salida concreta puede seleccionar roster activo, miembros con historial, clientes gestionables o contratos comerciales. Global no significa que todas las salidas incluyan la misma población.
6. **Atribución**: llegada al primer analista; cierre al que lo consigue; cita al responsable de tarea; cartera al dueño o analista económico que declare la fuente; digitador por separado.
7. **Verificación**: `sondasNucleoVerificadas` exige `cuadra=true`, `paridad_nucleo=0` y entero `paridad_filas>0`. `null`, ausente y fallo no son cero. La nota detallada registra qué consumidores aplican hoy la guarda y cuáles no.
8. **Lectura local**: contar páginas/filas descargadas o formatear/ordenar un payload es una transformación del cliente; se identifica explícitamente. No se declara un total como servido sólo porque sus filas provengan del servidor.

Fuentes transversales de código: `CRM-Avance-Corp/app/src/components/gerencia/periodo.ts`, `periodo-context.tsx`, `app/src/screens/hoy/gerencia.tsx:232`, `app/src/lib/sondas-conversion.ts:19`, rutas/permisos en `app/src/lib/router.ts`, `vistas.ts`, `roles.ts`.

## Cobertura de rutas de Gerencia

El catálogo actual tiene 21 rutas; **20 accesibles a Gerencia**. `derivaciones` exige `verDerivacionesEquipo`, falso para Gerencia; el historial relevante se encuentra dentro de Repartir. Los alias `clientes` y `contratos` conducen a `mi-cartera`, y `capital-cierres` a `hoy`: no son pantallas de indicadores adicionales.

| Ruta | Superficie y cobertura documental |
|---|---|
| `hoy` | Resumen: Comercial; Citas: O01/O02; desglose por empresa: K51–K56; compromisos: O114–O117 |
| `conversiones` | Comercial: indicadores, embudo, orígenes, semanas y detalle individual |
| `ranking-vendedores` | Comercial: conversión, capital y resultados del lote; orden y estados por pestaña |
| `reuniones` | Operación: todas las tarjetas, modalidades, orígenes, resultados y responsables |
| `metas` | Comercial: objetivo y cumplimiento; configuración de objetivos en Cartera/configuración |
| `rendimiento` | Comercial: bloque mensual y conversión de distribución V3; O118–O140: carga/capacidad/atención y calidad. Sus diferentes relojes y unidades quedan descritos |
| `pipeline` | Operación: tarjetas globales, etapas y contadores filtrados |
| `cartera` | Operación: inventario de leads, segmentos y listado paginado |
| `agenda` | Operación: tareas pendientes, fechas, agrupaciones, conteos y ámbitos |
| `mi-cartera` | Cartera: contratos/clientes, modos de mes/saldo, filtros, fichas, operaciones y cooperativas |
| `repartir` | Operación: distribución, cola, reparto e historial/entregas |
| `rescate` | Operación: Base para gestión por mes/motivo |
| `rescate-carpeta` | Operación: carpeta, registros, recuperables, repartidos y selección |
| `equipo` | Comercial y Operación: rama Empresa de Gerencia, no asumir que la rama Supervisión está montada |
| `alertas` | Operación: señales, evidencias, umbrales, contadores y estado de evaluación |
| `config` | Cartera/configuración: parámetros y resúmenes administrativos |
| `config-usuarios` | Cartera/configuración: roles, nómina y consultas de impacto |
| `config-productos` | Cartera/configuración: catálogo, versiones y condiciones |
| `config-metas` | Cartera/configuración: objetivos, versiones y agregados configurados |
| `config-sla` | Cartera/configuración: parámetros SLA y métricas históricas |
| Fichas y elementos transversales | Operación: lead, plazos/tareas/actividad; Cartera: cliente/contrato y desgloses. Las rutas anteriores abren esos mismos componentes |

## Datos que el contrato actual no puede afirmar

- Un flag inferido de cita no demuestra cuántos leads únicos del lote tuvieron una cita registrada. Se describe el flag; la necesidad de una proyección del dato real sigue en N1, sin implementación.
- El porcentaje de realización por modalidad no viene acompañado de todas las exclusiones necesarias para imprimir su fracción ajustada. No inventar ese divisor: N2.
- La elegibilidad del listado de operaciones no demuestra aporte efectivo después de la deduplicación. El episodio conoce el aporte, pero no lo expone ese listado: N3.
- Una serie por semana de llegada no responde cierres ocurridos por semana. Se documenta el reloj existente; una necesidad distinta debe buscar otra salida o justificarse: N4.
- «Total» sobre una lista recortada no certifica todo el servidor. La definición y el riesgo de completitud se documentan aunque no se haya alcanzado el límite en los datos inspeccionados.

Estas carencias están definidas, no son casillas de investigación que autoricen inventar números. Resolverlas pertenece a los puntos posteriores del requerimiento.

## Línea base de esta ejecución

- Repositorio al iniciar: Main `2742bf88fd14356bfe046311b0967738871f2df7`. Había cambios ajenos y Main adelantado siete commits; se preservaron, sin sincronizar ni publicar. Durante la ejecución otro trabajo avanzó a `ecbb7b9`; se verificó que su cambio afecta pruebas/documentación SQL, no el árbol de aplicación inspeccionado.
- Comparación `62ef70c..2742bf8` del directorio `CRM-Avance-Corp/app`: sin diferencias. Los cambios incorporados de otro trabajo incluyen SQL de multiempresa; no se aplicaron por este objetivo.
- Proyecto Supabase: `dctqcbznekcyxhjujuci`. Definiciones consultadas en transacciones de solo lectura, sin consultar identidades ni datos personales para este inventario.
- Las huellas son `md5(pg_get_functiondef(...))`, no hashes de `prosrc`; no son intercambiables.

| Núcleo/fuente privada protegida | Huella inicial |
|---|---|
| `conversion_episodios` | `8a2549dbfa59c732da04900ed90b6361` |
| `citas_episodios` | `ea636888a266941e959f26c6a5727216` |
| `capital_episodios` | `b8f375fbb377582835f4cfe222240c5b` |
| `metricas_distribucion_leads_core` | `f8748197c550484ae59b6257397a5013` |
| `metricas_distribucion_leads_v2_core` | `7408cb964af34dfb091108c5a7062cc4` |
| `metricas_distribucion_leads_v3_core` | `be2290576ef7f8947f3b4d3a9db846a7` |
| `metricas_sla_global_core` | `2353b10e1ff2104ffb14441485eb7dde` |

Se registraron además firmas, propietario, permisos, `search_path`, volatilidad y condición de definidor/invocador de 34 funciones de métricas/lectura y núcleos, para comparar al finalizar. La existencia en ese registro no implica que todas sean consumidas por las pantallas; las notas distinguen las fuentes activas de salidas no utilizadas.

## Verificación de cierre del punto 1

**Completado documentalmente el 4 de septiembre de 2026, 21:21 America/Lima.** Las tres notas se leyeron completas y se verificaron sus contratos comunes y diferencias. Resultado:

| Nota | Registros | Cobertura |
|---|---|---|
| Comercial | C01–C80: 80 | Conversión de rango/mes/cohorte, series, ranking, capital mensual, metas y crédito comercial del equipo |
| Citas y operación | O01–O140: 140 | Citas, inventario de leads, Agenda, Repartir, Base/carpetas, Alertas, equipo, ficha, compromisos y carga de Rendimiento |
| Cartera y configuración | K01–K116: 116 | Saldo/cierre mensual, clientes, contratos, operaciones, cooperativas, cronograma y parámetros/resultados de configuración |

Son **336 registros de inventario**, no 336 KPI empresariales independientes: incluyen contadores locales, estados, parámetros y variantes que se distinguen por su significado. IDs únicos y continuos por prefijo; sin enlaces del inventario a notas inexistentes, rutas fuente inexistentes ni referencias abreviadas fuera de la longitud del archivo.

La matriz cubre las 20 rutas permitidas de Gerencia, sus alias y componentes transversales. Cada registro contiene definición/fuente/campo y hereda de su sección unidad, reloj, ámbito/atribución, exclusiones y disponibilidad cuando son comunes. Las lecturas locales se declaran; no se las presenta como agregados del servidor. Las necesidades N1–N4 y las diferencias legítimas quedan explícitas.

Comparación productiva repetida al cierre: **34 de 34 funciones, sin cambios** de definición, firma ni metadatos/permisos registrados. Árbol de aplicación idéntico al inicial; sin cambios de aplicación o SQL por esta tarea. Detalles y límites de verificación en [[Inventario de indicadores de Gerencia - Evidencia y verificacion]].

Este cierre prueba el entregable de definiciones y fuentes; **no afirma que se hayan corregido las inconsistencias ni probado visualmente todos los estados**. Los puntos 2–5 permanecen pendientes y ninguna publicación está autorizada por esta documentación.
