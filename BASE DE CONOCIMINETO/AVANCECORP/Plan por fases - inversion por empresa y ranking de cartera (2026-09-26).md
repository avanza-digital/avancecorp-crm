---
tags: [crm, plan, ranking, cartera, multiempresa]
fecha: 2026-09-26
estado: auditado por Claude; ajustes documentados por PRIMARY; implementación pendiente
---

# Plan por fases — inversión por empresa y ranking de cartera

Auditoría del 26/09: **CHANGES_REQUESTED**, sin P0, confianza MEDIA.
PRIMARY contrastó y trató los nueve hallazgos en este plan. No se pidió otra
opinión para obtener PASS; el diseño detallado, las decisiones comerciales y
la implementación siguen pendientes. Acta: [[Auditoria Claude - plan inversion por empresa (2026-09-26)]].

## Objetivo y alcance

Miguel pidió un plan para impedir que un analista registre como primera inversión
lo que es continuidad comercial en la misma empresa, sin impedir la primera
inversión de esa persona en otra empresa del grupo.

Empresas independientes: Avance, Qorilazo y Prodelco.
Conservar «Nueva inversión», mostrando solo empresas donde la persona nunca tuvo
una inversión confirmada válida. Si no queda ninguna, ocultar el botón.
Conservar upgrade, renovación y una ruta definida para quien retiró todo y regresa.

También se corrige el ranking que hoy ubica capital de upgrades en «Sin origen
identificado» cuando la operación de cartera dice upgrade pero el contrato
legado conserva categoría nuevo.

Esta nota es un plan, no acredita implementación ni publicación.
No autoriza recategorizaciones masivas, reconstrucción de fotos cerradas,
modificar tasas ni crear otra conversión por el mero hecho de entrar a una empresa.

## Límites y responsabilidades

- Codex es PRIMARY y único escritor. Claude es SECONDARY_REVIEWER sin herramientas,
  sin cambios de archivos ni consultas recursivas; se usa `scripts/claude-review`.
- Miguel aprueba las decisiones comerciales, el SQL exacto antes de aplicarlo y
  la publicación mediante la invocación humana de release-crm.
- Esta sesión solo audita y documenta. No implementa el producto ni ejecuta SQL.
- Dos entregas independientes: **A, ranking de cartera**; **B, operaciones por empresa**.
- No se cambian fórmulas de conversión, rentabilidades, atribución ni capital como
  efecto secundario. Tampoco se crea otro lead/perfil/persona para un cliente existente.
- Separar tres conceptos: origen de captación, operación comercial y categoría del
  contrato financiero. «Primera inversión en otra empresa» no significa otra primera
  conversión de la persona ni autoriza volver a contar su captación.

## Fase 0 — línea base y alcance verificable

- [ ] Registrar commit realmente servido, versión de base, funciones/grants/triggers
  vigentes y estado de la entrega previa. No asumir que la última migración que
  declara una función contiene su cuerpo vivo: existen transformaciones posteriores.
  Conservar `pg_get_functiondef`, huellas, owner, grants y dependencias de los
  objetos afectados para preparar y ensayar la reversa desde la base viva exacta.
- [ ] Preservar trabajo ajeno. El árbol principal está modificado; no publicar desde
  él ni crear worktrees automáticamente. Acordar una copia de trabajo aislada si hace falta.
- [ ] Navegar primero con CodeGraph y complementar sus huecos con lectura puntual.
- [ ] Ejecutar `npm run gate:realidad` desde `CRM-Avance-Corp` y levantar inventario
  de inconsistencias con lecturas autorizadas: historia sin espejo, operaciones
  de cartera contradictorias, personas fusionadas, pendientes y anulaciones.
- [ ] Inventariar puerta → núcleo → escritura → trigger → efectos posteriores,
  con permisos reales por rol: cartera, conversión de lead, venta cruzada,
  reinversión COOPAC, alta contractual directa, confirmación antigua y portal.
- [ ] Verificar si `public.crear_contrato` sigue accesible a analistas. Su cierre
  quedó como tarea aparte el 24/09: si evade la regla, obtener OK específico para
  incluirlo o bloquear la aceptación «todas las puertas protegidas». No ocultar el hueco.
- [ ] Congelar una muestra de comparación antes/después, con datos ficticios que
  reproduzcan esas situaciones y un manifiesto de operaciones afectadas sin PII.
  Verificar en vivo `operaciones_cartera.contrato_nuevo_id`, su unicidad y su
  correspondencia con los tres contratos pendientes, sin depender del espejo.

**Salida:** inventario por empresa/rol/entrada, alcance aprobado y línea base
reproducible. La revisión presente inspeccionó el código publicado del ranking
`526d6d90c621e4072251818d1325b7bd0c01b2ca`, no certifica ausencia de cambios posteriores.

## Ya completado — no repetir

- [x] Enlace puntual de tres leads del backfill del 23/09 a sus contratos.
- [x] S/ 60.000 pasaron a Referido y S/ 32.450 a Walking; capital y conversión intactos.
- [x] Auditoría, ensayo e idempotencia verificados.
- [ ] Pendiente: S/ 150.000 de tres upgrades de Betzabeth deben verse como Cartera.

Evidencia: [[Ranking - enlaces excepcionales y propuesta por empresa (2026-09-26)]].

## Fase 1 — contrato de negocio e inventario

- [ ] Definir una matriz única persona × empresa × estado/historial × operación.
- [ ] «Nunca invirtió» consulta todo el historial confirmado, incluidos contratos
  y cierres legados, no solo inversiones activas ni filas de crm.inversiones.
  Resolver identidad canónica para no confundir perfiles duplicados o fusionados.
- [ ] Distinguir inversión válida de solicitud borrador, cancelada o anulada;
  acordar el tratamiento de hechos revertidos y dejarlo probado.
- [ ] Definir: primera inversión en empresa; upgrade de contrato activo;
  renovación de contrato elegible; regreso tras retiro total.
- [ ] Para regreso, acordar «Reinversión / volver a invertir»: condiciones/tasa,
  contrato de referencia si procede, atribución y efecto en métricas. No forzarlo
  a upgrade, que hoy exige contrato activo.
- [ ] Revisar equivalencias de las cooperativas: su operación existente de
  reinversión no se asume idéntica a upgrade/renovación de Avance.
- [ ] Inventariar entradas: Mi cartera, fichas de cliente/inversionista, lead
  convertido, venta cruzada, solicitudes pendientes y puertas legadas.
- [ ] Medir casos contradictorios como los tres upgrades sin modificar datos.
  La lectura agregada no sustituye verificación de contratos individuales.

**Salida:** matriz de reglas y rutas aprobada, con casos de prueba reales
anonimizados. Los permisos de responsable, analista de venta y renovación
conservan su contrato vigente. No cambiar la fórmula de conversión como efecto
colateral de la clasificación por empresa.

### Matriz comercial que debe quedar cerrada

| Situación en esa empresa | Ruta prevista | Condición |
|---|---|---|
| Nunca tuvo inversión confirmada válida | Nueva inversión | Permiso vigente; sin otra solicitud incompatible |
| Tiene contrato Avance activo | Registrar upgrade | Elegir origen activo explícito; hereda tasa; no modifica el anterior |
| Contrato Avance llegó a fecha fin | Renovación | Elegibilidad y permisos actuales; cierre/enlace atómicos |
| Tuvo inversión, retiró todo y regresa | Volver a invertir | Ruta y términos por aprobar; no forzar upgrade sin origen activo |
| Tiene historial en Qorilazo o Prodelco | Operación de continuidad COOPAC | Validar la reinversión existente; no copiar semántica Avance |
| Solo tiene borrador/solicitud cancelada | No demuestra inversión histórica | Resolver el pendiente, no duplicarlo |
| Confirmación anulada o contrato eliminado con auditoría | Decisión explícita | No equiparar «anulado» con retiro normal ni borrar evidencia |
| Identidad incompleta o historia contradictoria | Revisión / recuperación | No declarar «nunca invirtió» por falta de datos |

Decisiones que requieren a Miguel, no suposiciones del código:

1. **Regreso:** nombre visible, tasa/condiciones, vínculo histórico, quién puede
   operarlo —también en venta cruzada— y tratamiento comercial/métrico. Propuesta:
   continuidad de cliente, nunca captación nueva automática.
2. **Historia válida:** retiro/vencimiento siguen acreditando que invirtió;
   decidir anulaciones, reversas y eliminaciones. Los casos demo no acreditan
   historia comercial real. Confirmar tratamiento de cotitulares sin contarlos
   automáticamente como titular principal.
3. **Puertas compartidas:** autorizar el cierre de una vía antigua si el inventario
   demuestra que permite saltarse la regla. Mantener separadas las facultades de
   corrección histórica de Admin/Superadmin; no crear una excepción genérica.

La venta cruzada conserva A como responsable y B como autor del cierre, motivo,
cuentas enmascaradas y derechos sobre su solicitud. La nota del 24/09 registra
una discrepancia pendiente en métricas de upgrade cruzado: medirla y delimitarla;
no declararla corregida ni cambiar la atribución como parte de esta entrega.

## Fase 2 — corregir Cartera en el ranking

- [ ] Resolver el criterio de clasificación cuando operaciones_cartera y categoría
  del contrato legado difieren; usar evidencia de la operación, no inferir
  upgrade únicamente porque existe un segundo contrato.
- [ ] Mantener el origen/capital de una misma operación sin duplicados, con la
  misma atribución y las mismas monedas de la producción canónica.
- [ ] Corregir la lectura sin recategorizar contratos financieros en masa.
  Mantener separado el agrupamiento visual por origen de cualquier cambio
  a metas, cálculo de capital o conversión.
- [ ] Incluir los tres upgrades por S/ 150.000 como caso de aceptación y
  comprobar otros analistas con el mismo patrón.
- [ ] Preservar los enlaces ya corregidos y las fotos históricas selladas.
  Validar el comportamiento de la próxima foto mensual.

**Aceptación:** los S/ 150.000 de Betzabeth pasan de Sin origen identificado a
Cartera; no cambia su total, su conversión ni su atribución. Fuera del manifiesto
de operaciones equivalentes confirmado en F0, el desglose permanece idéntico.
Dentro de él, solo cambia el canal autorizado; cada operación conserva ID,
moneda, importe y vendedor. Los históricos cerrados no se reescriben.

### Implementación y conciliación A

- [ ] Corregir el lector `private.ranking_capital_origen_filas` mediante migración
  nueva. Mantener `private.capital_episodios` como fuente monetaria y conservar
  las reglas actuales de atribución, sin copiar fórmulas en el frontend.
- [ ] Definir precedencia explícita: evidencia válida de upgrade/renovación
  ligada a la operación → Cartera; luego reglas vigentes de origen. No basta
  que la persona tenga un segundo contrato; ambiguos quedan reportados.
  Para A, aplicar la corrección acotada a contratos Avance `nuevo` sin origen
  identificado y con operación de cartera inequívoca ligada por
  `operaciones_cartera.contrato_nuevo_id`. Si aparece además un lead directo o
  un origen conocido contradictorio, separarlo del manifiesto y pedir resolución;
  no quitar silenciosamente un origen identificado ni reinterpretar captaciones.
- [ ] Resolver registros de operación duplicados/contradictorios antes del join:
  no multiplicar capital. Comprobar anulaciones y fuentes históricas sin espejo.
- [ ] Revisar aparte la rama COOPAC del lector, que hoy usa el origen del lead;
  **no modificarla en A**. Su clasificación de continuidad queda para B con
  evidencia/regla aprobada, sin inferirla por repetición. Conciliar sus importes
  y canales idénticos antes/después de A.
- [ ] Comparar todas las filas por ID y moneda, totales por analista y globales,
  tasas por canal, conversión oficial y Metas. No validar solo el total de Betzabeth.
- [ ] Ensayar mes abierto, rango de meses, mes cerrado y nuevo cierre mensual.
  Si septiembre se sella antes de instalar, no reescribir la foto ni prometer
  el cambio retrospectivo; pedir una decisión separada para cualquier corrección histórica.
- [ ] Conservar el contrato JSON público cuando sea posible; si cambia, revisar
  todos sus envoltorios y validadores del frontend servido.

**Entrega A:** esta corrección puede publicarse de forma independiente después
de sus propios gates de las fases 5 y 6; no esperar por todo el cambio de botones.

## Fase 3 — regla central en el servidor

- [ ] Unificar la decisión de empresas disponibles y operaciones permitidas con
  su motivo, calculada desde el historial canónico.
- [ ] Revalidar al preparar y al confirmar: la pantalla no será la única defensa.
  Auditar todas las puertas accesibles al analista, incluidas las legadas.
- [ ] Evitar dos primeras inversiones simultáneas en la misma empresa; conservar
  idempotencia de reintentos y coordinar solicitudes pendientes existentes.
- [ ] Si otro registro cambia la elegibilidad mientras hay un formulario abierto,
  devolver un motivo y permitir corregir/retomar; no convertir automáticamente
  una solicitud en upgrade ni borrar borradores.
- [ ] Conservar permisos y responsables en cartera propia y venta cruzada.
  Cualquier ajuste de puertas compartidas con public/portal se delimita y
  autoriza antes de implementarlo.
- [ ] Completar la ruta de regreso acordada para no bloquear clientes existentes
  sin contrato activo. No habilitar una restricción sin alternativa operable.
- [ ] Añadir nueva migración si hace falta, sin modificar migraciones publicadas;
  tipos y documentación se actualizan si cambia el contrato de datos.

**Aceptación:** el servidor rechaza «nuevo» en una empresa ya invertida por
cualquier entrada en alcance, permite una primera inversión legítima en otra,
y no amplía permisos ni rompe solicitudes anteriores.

### 3.1 Lectura única de elegibilidad

- [ ] Resolver persona canónica y todo su historial: `public.contratos`,
  `crm.cierres_externos`, enlaces/operaciones e inversiones, sin duplicar una
  misma fuente. No depender únicamente de `crm.inversiones` ni de estados activos.
- [ ] Contrato propuesto, a nombrar al implementar: por empresa devolver
  historial confirmado, acciones permitidas, código de motivo, orígenes elegibles
  y referencia a pendientes que el actor esté autorizado a recuperar.
- [ ] Separar «historia comercial» de «permisos del actor». Consultar elegibilidad
  no permite leer cuentas, contratos o datos de otra cartera sin su llave vigente.
- [ ] Reutilizar el mismo núcleo para lectura y escritura; el frontend no decide
  por conteos de contratos ni reconstruye la regla con sus datos parciales.
- [ ] Revisar los envoltorios SQL antes de añadir campos. Versionar o ampliar de
  forma compatible; probar respuestas reales contra esquemas estrictos publicados.
- [ ] Medir consultas y tiempos con volumen representativo; evitar una consulta
  por fila de cartera. Añadir índices solo si la medición los justifica.

### 3.2 Preparación, corrección y confirmación

- [ ] Inventariar y cubrir `preparar_inversion_fn`,
  `preparar_inversion_cliente_existente_fn`, `preparar_reinversion_fn`,
  `corregir_solicitud_inversion_fn`, `confirmar_inversion_revisada_fn`,
  `confirmar_inversion_fn` y los escritores finales accesibles identificados en F0.
- [ ] La reinversión COOPAC llama hoy a la preparación normal ANTES de insertar
  su vínculo de origen. Ajustar ese flujo con contexto interno validado; un candado
  ingenuo en la preparación normal rompería reinversiones legítimas. No admitir
  un booleano enviado por el cliente que permita eludir la regla.
  Diseño elegido para desarrollar: el núcleo privado recibe modalidad interna
  y fuente explícita, revalida persona/empresa/permisos/fuente y crea solicitud
  y vínculo en una transacción. La puerta normal solo usa modalidad ordinaria;
  la de reinversión autoriza su origen antes de llamar al núcleo. Ningún rol de
  cliente ejecuta directamente ese núcleo. Mantener las huellas de idempotencia
  y el enlace FK; no insertar un origen antes de que exista su solicitud.
  La combinación venta cruzada + reinversión requiere ruta explícita aprobada:
  el ternario actual de la API da prioridad a venta cruzada y no basta añadir un ID.
- [ ] Autorizar primero. Un reintento ya confirmado debe devolver el mismo
  resultado según el contrato vigente, sin fallar por la historia que él mismo creó
  ni repetir contrato, cuotas, cierre, comprobante, conversión, PDF o bienvenida.
- [ ] Para nuevas escrituras: bloqueo transaccional común por persona canónica y
  empresa, relectura bajo ese bloqueo y escritura en la misma transacción. Coordinar
  orden de bloqueos con solicitud, fusión de identidad y cierre mensual para evitar
  carreras e interbloqueos. Probar dos sesiones, no solo dos llamadas secuenciales.
  Antes de escribir código se exige una tabla de adquisición de bloqueos para
  cada escritor/fusión/cierre: recurso, clave estable, orden y reintento. Propuesta
  que debe contrastarse contra F0: autorización y replay autorizado de confirmadas;
  estabilización de identidad; candado persona canónica/empresa; solicitud y
  relectura de revisión/resultado; candados de período; validación y escritura.
  Si la identidad cambió, abortar/reintentar sin escrituras. Las rutas existentes
  deben usar un orden compatible, no agregar un lock aislado después de tomar
  recursos en orden inverso. No aceptar F3 sin ensayo de interbloqueos y fusión.
- [ ] El límite afecta a la primera operación, NO a la cantidad total de inversiones.
  No crear un UNIQUE persona/empresa sobre todas las inversiones: impediría upgrades
  y renovaciones válidas. Preservar la regla de pendientes de venta cruzada.
- [ ] Corregir datos no permite cambiar persona/empresa/tipo para esquivar permisos.
  Revisar orígenes anulados, cuenta, responsable, tasa y permisos nuevamente al confirmar.
  Inventariar primero qué cambios permite hoy la RPC de corrección; conservar
  los legítimos y revalidarlos. Cualquier restricción adicional sobre una corrección
  actualmente permitida se presenta como cambio de comportamiento, no como limpieza.
- [ ] Solicitud antigua que ya no es válida: conservarla, explicar el conflicto y
  ofrecer recuperación/cancelación/repreparación autorizada. No autoconvertir el tipo
  ni permitir duplicados por ser un borrador anterior al despliegue.
- [ ] Todo efecto financiero participa de una transacción o de la recuperación
  idempotente existente. Fallo parcial no deja fuentes sin vínculo ni dos contratos.

### 3.3 Seguridad y migraciones

- [ ] Funciones privadas no expuestas, `search_path` explícito, revokes/grants
  mínimos y controles de autenticación/rol/ámbito. RLS activada desde la creación
  de tablas nuevas, auditoría desde el inicio, sin permisos de borrado añadidos.
- [ ] Revisar funciones/grants/policies con el alcance especializado de auditoría
  RLS previsto en el repo, sin romper la cadena PRIMARY → reviewer → PRIMARY ni
  multiplicar revisiones por rutina. Incluir hallazgos y pruebas en el gate final.
- [ ] SQL nuevo con timestamp, precondiciones, `MIGRACIONES.md` y reversa compatible;
  mostrarlo a Miguel y esperar autorización antes del ciclo remoto.
- [ ] Si cambia esquema/RPC, regenerar tipos; si se requieren cambios Edge,
  mantener los espejos compartidos byte a byte y sus pruebas. No crear una Edge
  o una tabla nueva solo porque el plan tiene una sección de backend.

## Fase 4 — interfaz coherente

- [ ] Filtrar el selector de empresas de «Nueva inversión» con la respuesta
  del servidor; ocultar el botón cuando ninguna empresa sea elegible.
- [ ] Mostrar upgrade/renovación/reinversión según la matriz de la fase 1.
  Si existen varios contratos elegibles, pedir cuál corresponde.
- [ ] Aplicar el mismo comportamiento a todas las entradas inventariadas,
  incluidos cliente de otra cartera y lead ya convertido.
- [ ] Conservar solicitudes en curso y mostrar mensajes claros ante estado
  cambiado, falta de permiso, carga o error. Un error de consulta no equivale
  a «nunca invirtió».
- [ ] Mostrar una preview local antes de publicar.

Ejemplos de aceptación:

| Historial confirmado | Empresas en Nueva inversión |
|---|---|
| Ninguna empresa | Avance, Qorilazo y Prodelco |
| Solo Avance | Qorilazo y Prodelco |
| Avance y Qorilazo | Prodelco |
| Las tres | Botón oculto; operaciones de cartera según elegibilidad |

### Superficies y estados de pantalla

- [ ] `inversion-nueva.tsx`: sustituir el selector incondicional de las tres
  empresas por la elegibilidad; retirar el supuesto de categoría `nuevo` cuando
  la ruta sea de continuidad. No cambiar el tipo de un borrador silenciosamente.
- [ ] Ficha del inversionista, ficha del cliente y lista/tarjeta de Mi cartera:
  botones coherentes, upgrade con selector de origen, renovación en su contrato.
- [ ] Conversión del lead y «Cliente de otra cartera», incluidos buscador,
  nuevo lead y descarte: reutilizar el mismo contrato de acciones, sin crear
  identidades ni captaciones duplicadas.
- [ ] La recuperación de solicitudes y «Iniciar otra inversión» siguen siendo
  accesibles y reconsultan elegibilidad aunque «Nueva inversión» esté oculto.
  Superficie propuesta: acción independiente «Solicitudes pendientes» en la
  ficha del inversionista y en el contexto autorizado de venta cruzada, con
  recuperación por referencia reutilizada. No muestra solicitudes ajenas sin permiso.
- [ ] Carga sin opciones accionables; error con reintento; prohibición con motivo;
  éxito que invalida caché de ficha/cartera/capacidades. Refrescar también al volver
  a la pestaña o cambiar de persona/sesión; el servidor conserva la última defensa.
- [ ] Teclado, foco de diálogos, lector de pantalla, móvil y permisos de solo lectura.
  Conservar el estilo existente; no rehacer el módulo como parte de este cambio.
- [ ] Preview local con datos ficticios: Miguel acepta el flujo visual antes de publicar.

## Fase 5 — ensayo, pruebas y revisión

Cada entrega pasa estas verificaciones según su alcance, no solo al final:

- [ ] Fixtures que reproduzcan producción: contrato nuevo con operación upgrade;
  lead tardío ya enlazado; registros legados sin espejo en inversiones.
- [ ] Matriz por las tres empresas: sin historial, activo, vencido, retirado,
  anulado, borrador, varias inversiones y venta cruzada.
- [ ] Pruebas de roles, permisos, doble envío, concurrencia entre sesiones,
  reintentos y borradores cuyo contexto cambió.
- [ ] Conciliación de capital por moneda, conversión, responsable de la relación
  y analista de la venta; aislamiento de meses cerrados.
- [ ] Gates de .ai/VERIFICATION.md: checks de app para frontend, matriz SQL/RLS
  pertinente para servidor y E2E siempre locales en Docker, nunca en GitHub.
- [ ] Revisión independiente de Claude para los cambios significativos/críticos,
  con evidencia saneada y solo un PRIMARY escritor. Resolver hallazgos con pruebas.
- [ ] Marcar cada check PASS/FAIL/NOT RUN; no publicar con un bloqueo relevante.
- [ ] Ensayo de migraciones en rama autorizada de Supabase, advisors y merge
  nativo conforme a las reglas del proyecto; no apply_migration directo a producción.

**Salida:** evidencia de que funciona en las situaciones reales y de que la
operación preserva importes, permisos, auditoría y reglas no modificadas.

### Matriz mínima de pruebas y evidencia de cierre

| Área | Casos imprescindibles | Criterio |
|---|---|---|
| Ranking A | 3 upgrades legados, otros analistas, enlace tardío, ambiguos, PEN/USD | Solo diferencias del manifiesto; suma exacta por moneda |
| Historia B | 0/1/2/3 empresas, retirado, vencido, demo, anulaciones, sin espejo | Nunca confundir vacío de datos con cliente nuevo |
| Operaciones | Upgrade activo, renovación elegible, regreso aprobado, reinversión COOPAC | Rutas válidas completas; originales protegidos |
| Identidad | Duplicado/fusión, cambio de documento, fuente legada, cotitular | Persona canónica correcta, sin doble primer registro |
| Permisos | Propio/ajeno, supervisor, Gerencia, Directorio, cuenta inactiva | Sin elevación de acceso; derechos previos conservados |
| Carreras | Propia vs cruzada, dos claves, doble clic, fusión y cierre concurrentes | Una primera escritura; error recuperable, sin datos parciales |
| Recuperación | Confirmada reintentada, respuesta perdida, PDF pendiente, borrador antiguo | Mismo resultado sin repetir efectos ni perder acceso |
| API real | Preparar/corregir/confirmar y puertas antiguas con Auth/PostgREST | Rechazo servidor incluso sin interfaz y con payload manipulado |
| Compatibilidad | UI anterior/nueva, envoltorios SQL, esquemas estrictos | Sin caída de Ranking, Metas, cartera o conversiones |
| Finanzas | Tasas, cuotas, cuentas, capital adicional, moneda, atribución y sellos | Invariantes exactos; sin recálculos ajenos al alcance |

Comandos existentes, seleccionados proporcionalmente por entrega:

- Desde `CRM-Avance-Corp`: `npm run gate:realidad`, `npm run check:scripts`,
  `npm run seed:preflight`, `npm run test:rls:preflight`, `npm run test:rls`
  en banco autorizado y `npm run test:edge-preflight` si corresponde.
- Desde `CRM-Avance-Corp/app`: `npm run check`, `npm run test:e2e:docker`
  (o `npm run check:all`) y `npm run gen:types` cuando cambie el contrato.
- Ensayo remoto en rama autorizada: matriz RLS/Auth/HTTP y advisors. El preflight
  offline no sustituye pruebas con roles reales contra la base del banco.
- Gate A y gate B conservan resultados separados, commit/huellas, conteos reales,
  fallos, omisiones y causas de NOT RUN. Un test con fixture incompatible con
  producción no acredita la propiedad que se quiere proteger.
- Para la implementación LEVEL 3, revisar el diff y evidencia final con Claude
  cuando corresponda. Esta auditoría del plan no sustituye esa revisión ni los tests.

Añadir expresamente: lead directo + ledger upgrade contradictorio; dos solicitudes
«nuevo» preparadas antes de activar y confirmadas simultáneamente; reinversión COOPAC
legítima y modalidad/origen manipulado; control que cambia entre preparar y confirmar;
sellado mensual entre instalar A y verificar sus cifras; reversa desde el cuerpo
vivo capturado. El replay conserva autorización y guardas documentales vigentes.

## Fase 6 — publicación y aceptación

- [ ] Entrega A: ranking corregido. Entrega B: regla por empresa y rutas compatibles.
- [ ] Coordinar instalación del servidor y publicación de UI: no activar el
  bloqueo mientras el frontend vigente siga ofreciendo una ruta inválida.
  Definir transición para pestañas antiguas y solicitudes pendientes.
- [ ] Integrar remoto sin sobrescribir trabajo ajeno; main local del build y
  avancecorp/main deben coincidir. Artefacto de fuente limpia; sin push forzado
  ni ramas de release. Usar release-crm bajo autorización humana.
- [ ] Conservar ZIP/manifiesto de recuperación y plan compatible para servidor;
  no restaurar copias de datos encima de inversiones nuevas ni borrar auditorías.
- [ ] Verificar bytes servidos y acceso básico; comprobar la lectura real de
  Betzabeth y casos por empresa sin crear inversiones financieras de prueba en producción.
- [ ] Registrar versión, huellas, resultados y aceptación de Miguel.

### Orden de instalación y activación B

1. Instalar primero cambios compatibles, con la nueva restricción desactivada
   mediante un control de servidor explícito, probado y auditado. En F3 se debe
   fijar almacenamiento, lectores, autorizados a cambiarlo y auditoría. Reutilizar
   configuración compatible existente; si requiere tabla nueva, va en `crm` según
   las reglas del proyecto, con RLS y sin escritura directa de analistas. No crear
   por defecto una tabla en `private` ni otorgar nuevos poderes a un rol.
   El núcleo toma la decisión vigente dentro de la transacción de confirmación;
   el cliente no manda el control. Serializar el encendido con confirmaciones
   en curso para definir un corte inequívoco y conservar replay idempotente.
   Activación y desactivación requieren autorización operativa y evento auditado.
   No abrir permisos como mecanismo de compatibilidad.
2. Publicar la interfaz compatible y todas las rutas alternativas aprobadas.
3. Comprobar solicitudes antiguas, cliente web anterior y recuperación. Una
   pestaña antigua recibe un error recuperable/instrucción de recarga, nunca
   una autorización especial para saltarse el bloqueo.
4. Activar el control solo tras gates, alcance de puertas antiguas resuelto y
   consentimiento comercial. Probar previamente ese orden exacto en el banco.
5. Si falla: detener nuevas operaciones afectadas de forma controlada y elegir
   reversa técnica compatible con los hechos nuevos; no reabrir indiscriminadamente
   una vía insegura ni restaurar un backup de datos sobre inversiones posteriores.

Si no hace falta cambiar el frontend para A, no publicar otro ZIP por rutina:
aplicar únicamente el cambio autorizado necesario y verificarlo con la UI servida.
Cuando sí haya artefacto, ejecutar `npm run release:crm` y
`npm run release:crm:verify -- releases/<manifiesto>.manifest.json` desde el CRM,
con el nombre real generado; comprobar commit, ZIP y bytes públicos.

## Fase 7 — observación, aceptación y cierre

- [ ] Preflight productivo de lectura inmediatamente antes; si cambió el schema,
  historial o commit acordado, detener y reconciliar, no saltar las precondiciones.
- [ ] Postflight A: desglose real de Betzabeth y muestra global, conversión y
  snapshots intactos. Postflight B: empresas/acciones correctas con roles existentes,
  sin fabricar inversiones o transferencias en producción para probar.
- [ ] Observar errores de elegibilidad, rechazos por historia/permiso, pendientes
  atascados, latencia y duplicados; logs sin DNI, cuentas, correos ni documentos.
  Acordar ventana y responsable de seguimiento al programar el release.
- [ ] Verificar la primera operación real autorizada de cada ruta y el próximo
  cierre mensual cuando ocurran. Registrar lo que siga pendiente de observación;
  no declararlo probado por anticipado.
- [ ] Conformidad visual/comercial de Miguel, acta con fuente servida, migraciones,
  manifiestos, auditorías, pruebas y rollback. Actualizar el vault sin falsear estados.
- [ ] Cerrar únicamente bancos/ramas temporales propios cuando sus evidencias estén
  conservadas; no detener contenedores ni retirar trabajos de otras sesiones.

## Secuencia recomendada

Entrega A: Fase 0 (alcance ranking) → Fase 2 → Fase 5-A → Fase 6-A → Fase 7-A.

Entrega B: Fase 0 (todas las puertas) → Fase 1 → Fase 3 → Fase 4 → Fase 5-B
→ Fase 6-B → Fase 7-B.

La matriz comercial de B puede prepararse mientras se corrige A. No exigir que
todas las decisiones de reinversión estén cerradas para corregir el ranking.
No se comienza la restricción productiva sin resolver la ruta de regreso de
clientes existentes; esa decisión no bloquea corregir el ranking.

Relacionado con [[Ranking - capital por canal de llegada (decision 2026-09-25)]],
[[Ranking - enlaces excepcionales y propuesta por empresa (2026-09-26)]],
[[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]],
[[Gestión comercial de clientes - renovaciones y upgrades]],
[[Venta cruzada - servidor probado en banco y P1 del PDF (2026-09-24)]] y
[[Main unico - sincronizacion y publicacion 2026-09-04]].
