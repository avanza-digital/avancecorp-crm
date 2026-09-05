---
tags: [crm, gerencia, inventario, metricas, cartera, configuracion]
requerimiento: REQ-GER-MET-001
punto: 1
fecha: 2026-09-04
corte: "2026-09-04 20:59 America/Lima"
commit_inspeccionado: 2742bf88fd14356bfe046311b0967738871f2df7
commit_al_cierre: ecbb7b97ad79124e34f1a924227d27dd8585c737
arbol_app_revalidado: ed23ef494093755055f1b236a37d9830fe3220f9
estado: inventario-documentado-sin-implementacion
---

# Inventario de indicadores de Gerencia — Cartera y configuración

Relacionado con [[Inicio]], [[Inventario de indicadores de Gerencia - Contrato de lectura]], [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Auditoria de metricas de Gerencia - hallazgos y plan 2026-09-04]], [[Gestión comercial de clientes - renovaciones y upgrades]] y [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]].

## Alcance y lectura

Este documento ejecuta **sólo el punto 1**: describe lo que cada indicador hace **actualmente**, no aprueba esa conducta ni implementa correcciones. Incluye `#/mi-cartera` (alias `#/clientes` y `#/contratos`), ficha de cliente y contrato, cooperativas, «Por empresa» del Resumen y `#/config*`. `#/cartera` es la cartera de **leads**, cubierta por el inventario operativo; no confundir ambas rutas. El dashboard `#/metas` lo cubre el inventario comercial; aquí se inventaría el **editor** `#/config-metas`.

Método: Inicio y requerimiento leídos; CodeGraph primero y lectura puntual después de resultados insuficientes; fuentes locales revalidadas sobre el commit indicado. Las pantallas principales de este alcance no tienen diferencias frente al frontend b8108ae auditado. Se consultaron **únicamente definiciones SQL en producción**, sin escribir ni obtener identidades. Las cifras históricas del informe enlazado no son un resultado recalculado por este inventario.

Al cerrar, trabajo concurrente dejó HEAD en `ecbb7b97ad79124e34f1a924227d27dd8585c737`. Se revalidó que `CRM-Avance-Corp/app` conserva exactamente el árbol `ed23ef494093755055f1b236a37d9830fe3220f9` del commit inspeccionado; no invalida las referencias frontend de esta nota. Esta tarea no modificó ese trabajo ni produjo ese commit.

Cada fila K identifica una magnitud o estado numérico visible. Las unidades PEN/USD son dimensiones **separadas** aunque compartan etiqueta; los ID identifican esas variantes cuando cambian su fuente o alcance. Fecha, unidad, ámbito, atribución, exclusiones y disponibilidad se heredan del contrato común de su sección salvo excepción indicada en la fila. Los campos de configuración y términos contractuales se marcan **parámetro**, no resultado comercial. Las variantes móvil/desktop y alias que comparten fuente figuran en la misma fila, no duplican el indicador.

**Estado de verificación:** L = trazado en código del commit indicado; S = definición de servidor contrastada en esta sesión o en la auditoría enlazada y revalidación común del inventario; no significa prueba de escritura ni prueba UI en todas las combinaciones. «Calculado en UI» describe una implementación existente, no recomienda crear otra.

## Localizadores de fuente

En las tablas, `MC:1215` significa el archivo completo MC, línea 1215. Son localizadores `archivo:línea`, no nombres de RPC inventados.

| Clave | Archivo completo |
|---|---|
| MC | `CRM-Avance-Corp/app/src/screens/mi-cartera.tsx` |
| CV | `CRM-Avance-Corp/app/src/lib/cartera-vista.ts` |
| CM | `CRM-Avance-Corp/app/src/lib/cartera-meses.ts` |
| CLV | `CRM-Avance-Corp/app/src/lib/clientes-vista.ts` |
| CF | `CRM-Avance-Corp/app/src/components/app/cliente-ficha.tsx` |
| CFM | `CRM-Avance-Corp/app/src/lib/cliente-ficha-modelo.ts` |
| CD | `CRM-Avance-Corp/app/src/components/app/contrato-detalle.tsx` |
| CN | `CRM-Avance-Corp/app/src/components/app/contrato-nuevo.tsx` |
| CE | `CRM-Avance-Corp/app/src/components/app/cierres-externos-seccion.tsx` |
| CEL | `CRM-Avance-Corp/app/src/lib/cierres-externos.ts` |
| API | `CRM-Avance-Corp/app/src/data/crm-api.ts` |
| Q | `CRM-Avance-Corp/app/src/data/crm-queries.ts` |
| CA | `CRM-Avance-Corp/app/src/data/crm-config-api.ts` |
| CQ | `CRM-Avance-Corp/app/src/data/crm-config-queries.ts` |
| CFG | `CRM-Avance-Corp/app/src/screens/config.tsx` |
| US | `CRM-Avance-Corp/app/src/screens/config-usuarios.tsx` |
| PR | `CRM-Avance-Corp/app/src/screens/config-productos.tsx` |
| MT | `CRM-Avance-Corp/app/src/screens/config-metas.tsx` |
| SL | `CRM-Avance-Corp/app/src/screens/config-sla.tsx` |
| ST | `CRM-Avance-Corp/app/src/lib/store.tsx` |
| PG | `CRM-Avance-Corp/app/src/components/common/paginacion.tsx` |
| HG | `CRM-Avance-Corp/app/src/screens/hoy/gerencia.tsx` |
| SQL-C | `CRM-Avance-Corp/supabase/migrations/20260807203751_crm_catalogo_productos_versionado.sql` |
| SQL-C2 | `CRM-Avance-Corp/supabase/migrations/20260902190000_crm_mi_cartera_por_mes_de_cierre.sql` |
| SQL-R | `CRM-Avance-Corp/supabase/migrations/20260829192000_crm_f4_b_cartera.sql` |
| SQL-O | `CRM-Avance-Corp/supabase/migrations/20260904210831_crm_conversion_llegadas_unicas.sql` |
| SQL-U | `CRM-Avance-Corp/supabase/migrations/20260807203740_crm_usuarios_jerarquia_autoservicio.sql` |
| SQL-S | `CRM-Avance-Corp/supabase/migrations/20260807203757_crm_metas_sla_versionados.sql` |

## A. Cartera de clientes: contrato común C

**Ruta de datos actual:** `crm.clientes_basicos` → `clientes_basicos_fn` → `private.cliente_ids_visibles_crm`; `crm.contratos_cartera` → `contratos_cartera_v2_fn` → `contratos_cartera_fn`. `listarClientes` y `listarMisContratos` validan filas → `useClientes/useContratos` → `agruparCartera` → `resumirCliente` → `resumenCartera/agruparPorMes` → `VistaMiCartera`. Fuentes API:2452,2953; MC:1706; CV:47,67,186; CM:176; SQL-C:2006 y SQL-C2:100.

**Ámbito:** Gerencia global, por perfil cliente; no por autor comercial del cierre. El dueño que presenta/filtra la UI es `asesor_perfil_id ?? creado_por` (CLV:29). «Sin analista» depende además del roster cargado en `equipo`. La lista permite clientes inactivos para consulta; sólo el resumen global de dinero/clientes en gestión los excluye. No excluye contratos demo porque la fachada de la lista no expone ni filtra `es_demo`. No incluye los cierres de cooperativas, que tienen sección separada. No se deduplican contratos: un cliente puede tener varios.

**Relojes/modos:** arranca en mes de Lima de la fecha de montaje (MC:949); mes contractual = `fecha_cierre_comercial` DATE, no registro, no `fecha_inicio`. «Todos los meses» pregunta por estado vigente al refrescar. La alarma por vencer se calcula usando el día local del navegador (CV:107), a diferencia de la ficha que usa Lima expresamente; no se presupone navegador fuera de Lima. Filtros analista/estado/texto/por vencer recortan grupos y contratos del bloque mensual; en modo todos no recortan los KPI globales. `soloPorVencer` saca al usuario del mes al activarlo. Las filas «sin contratos» acompañan al mes elegido; no son cierres del mes (MC:1104).

**Disponibilidad/completitud C:** cada lista tiene tope 2,000 (API:2412,2459,2963); el tope sólo produce logging (API:268). Filas inválidas de clientes/contratos se descartan con logging y el resto retorna como éxito (API:2483,3010). El agrupador omite contratos cuyo cliente no llegó en la otra lista (CV:47). Primer error/ausencia de una lista impide construir grupos; sin grupos no se muestran chips. Error de refresco con datos conserva última foto con aviso (MC:1856,1337). Los importes usan `Number(capital)||0` en los agregados locales. Por tanto un KPI local visible **no demuestra completitud**. L/S.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Campo → adaptación; unidad, corte y exclusión particular | Fuente |
|---|---|---|---|---|
| K01 | Capital invertido · Soles; fallback Capital invertido | ¿Cuánto capital activo hay en los clientes en gestión de toda la cartera? Suma capital de contratos activos de clientes activos. | `contratos.capital/moneda/estado` → `resumen.capitalActivoPen`; PEN; todos los meses, no filtros de tabla. C. | MC:1215,1249; CV:186 |
| K02 | Capital invertido · Dólares | Mismo saldo global K01 en USD, nunca se suma con PEN. | `resumen.capitalActivoUsd`; USD. Se oculta chip si importe no positivo. C. | MC:1216,1230; CV:186 |
| K03 | Cerrado en {mes} · Soles; fallback Cerrado en {mes} | ¿Qué capital contractual suma el bloque de cierre elegido y filtrado? Suma todos sus estados contractuales. | `bloque.capitalPen` desde `capital`; PEN; mes de cierre + filtros. Incluye clientes inactivos y demo de la lista, aunque texto general diga que bajas no suman. | MC:1215,1218,1241; CM:199,210 |
| K04 | Cerrado en {mes} · Dólares | Mismo bloque K03 en USD. | `bloque.capitalUsd`; USD; no convierte. Chip ausente si no hay USD positivo. | MC:1216,1230; CM:211 |
| K05 | Por vencer ≤30 d; botón Por vencer | ¿Cuántos contratos activos vencen desde hoy hasta hoy+30 inclusive? | `resumen.porVencer30`, `idsPorVencer`; contratos, no clientes. Toda cartera, incluye bajas, ignora mes/analista/texto/estado de tabla. Fecha local navegador. | MC:988,991,1281; CV:128,186 |
| K06 | {N} son de clientes dados de baja / 1 es… | ¿Cuántos contratos de K05 pertenecen a clientes inactivos? | `porVencer30DeBaja`; contratos, subconjunto K05. Sólo se explica si positivo. | MC:1266; CV:204 |
| K07 | Clientes con capital | ¿Cuántos clientes activos tienen al menos un contrato activo? | `resumen.clientesConCapital`; clientes únicos por grupo; todos los meses, alcance C global. Puede retirarse por prioridad de espacio en Gerencia. | MC:1296,1313; CV:199 |
| K08 | de {N}; {N} clientes en cabecera | ¿Cuántos perfiles cliente activos están en la cartera descargada? | `resumen.totalClientes`; personas/perfiles, no contratos ni conversiones. Todo el ámbito, no filtro. | MC:1299,1365; CV:196 |
| K09 | {N} inactivos | ¿Cuántos perfiles descargados no están activos? | `bases.length-enGestion.length`; clientes. No significa contratos vencidos ni anulados. | MC:984,1366 |
| K10 | Clientes que cerraron | ¿Cuántos grupos cliente tienen contratos en el bloque mensual? | `bloque.grupos.length`; clientes del mes filtrado, incluye cualquier estado contractual y bajas. No equivale a clientes nuevos. Puede ocultarse si ambos chips monetarios ocupan espacio. | MC:1288,1313; CM:207 |
| K11 | Sin analista | ¿Cuántos clientes activos tienen dueño nulo o fuera del roster UI? | `duenoDeCartera` + `rosterIds`; conteo de `enGestion`, global no filtrado. No es sólo `asesor_perfil_id IS NULL`. | MC:958,1306; CLV:29 |
| K12 | Capital invertido — fila cliente, PEN | ¿Cuánto capital activo tienen los contratos incluidos en este grupo? | `grupo.capitalActivoPen`; PEN. Con mes sólo contratos de ese mes; en todos resume contratos del grupo completo, aunque filtro de estado reduzca subfilas. No excluye cliente inactivo. | MC:178,1153; CV:67; CM:207 |
| K13 | Capital invertido — fila cliente, USD | Mismo grupo K12 en USD. | `grupo.capitalActivoUsd`; USD; monedas positivas visibles, cero pasa a mensaje sin capital. | MC:183; CV:67 |
| K14 | {N} activo(s) — fila/tarjeta cliente | ¿Cuántos contratos activos contiene este grupo? | `grupo.contratosActivos`; contratos. Con bloque mensual se limita al bloque; otros estados no cuentan. | MC:489,779; CV:74 |
| K15 | Capital — subfila/subtarjeta de contrato; Monto en detalle | ¿Cuál es el capital nominal de este contrato? | `ContratoRow.capital` y `moneda`; PEN o USD del documento, cualquier estado, no capital nuevo/adicional ni AUM agregado. | MC:362,693; CD:454; API:2988 |
| K16 | {N} contratos cerrados en {mes} | ¿Cuántos contratos hay en el bloque mensual filtrado? | `bloque.contratos` incrementa por contrato; todos los estados, no clientes ni conversiones. | MC:1507; CM:209 |
| K17 | incluye {N} registrado(s) por otra persona | ¿Cuántos contratos del bloque fueron registrados por alguien diferente del dueño actual de cartera? | `creado_por != duenoDeCartera(cliente)`; ambos deben no ser nulos. No compara con analista comercial atribuido por cadena. | MC:1515; CM:113,213 |
| K18 | {N} se registró/registraron en otro mes | ¿Cuántos contratos se registraron en mes diferente de cierre? | `mesLima(creado_en) != mesDeCierre(fecha_cierre_comercial)`; fecha ilegible no cuenta. | MC:1525; CM:97,214 |
| K19 | {N} de {M} junto a filtros | ¿Cuántos grupos coinciden de cuántos descargados? | `visiblesDelFiltro.length` de `bases.length`; perfiles/grupos; incluye «sin contratos» acompañantes y bajas. No total de base servidor. | MC:1113,1491 |
| K20 | Página {p} de {n} · {N} registros | ¿Qué página local de grupos filtrados se ve? | `paginar(visiblesDelFiltro,pagina)`; páginas y grupos, no contratos. Sólo visible si más de una página. | MC:1125,1599; PG:23,27 |
| K21 | Sin contratos / sin capital vigente / aún no genera ingreso | ¿El grupo no contiene contratos o no tiene capital activo? | `grupo.contratos.length===0` y capital activo. Mensaje cualitativo: no prueba ausencia de toda inversión si listas son parciales. | MC:155,172,442; CV:67 |

**Fuera del rol Gerencia:** el chip adicional «Contratos activos» de MC:1327 se monta sólo en la rama `else if` de `verEquipo`; no es un KPI de Gerencia. Sus contratos activos sí se ven por cliente (K14) y en ficha (K30).

## B. Renovaciones/upgrades dentro de Cartera

Contrato O: `crm.operaciones_cartera` → `listarOperacionesCartera` → `useOperacionesCartera` → mapa por `contrato_nuevo_id`. API:3020,3060; MC:967,1708. Tope 2,000, sin paginación, aviso técnico al alcanzar tope; **fila inválida aborta toda la lectura**, a diferencia de C. Error tiene aviso de desglose no disponible; los contratos permanecen operables (MC:1344). El ledger contiene `fecha_operacion`/período/autor/vendedor de la operación; la UI vincula por contrato, no usa la atribución canónica de cadena para estas etiquetas. Estados de capital no se suman como otra conversión. L/S.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Campo → adaptación; unidad, fecha, ámbito | Fuente |
|---|---|---|---|---|
| K22 | {importe} anterior | ¿Cuál es el capital del contrato de origen que la lista pudo resolver? | Contrato origen por `contrato_origen_id` → `capital`; moneda de contrato. Se omite si origen no está cargado. | MC:234,614 |
| K23 | {importe} renovado / Capital renovado | ¿Qué parte quedó registrada como renovada? | `operacion.capital_renovado`; moneda operación, fecha operación. Se muestra sólo con desglose completo en tabla. Historial de ficha usa la misma columna. | MC:221,243; CF:364,370 |
| K24 | {importe} adicional / Aporte adicional | ¿Qué dinero quedó registrado adicional a la renovación? | `capital_adicional`; moneda operación. Tabla muestra cero; historial omite adicional no positivo. No es otra conversión. | MC:247; CF:372 |
| K25 | = {capital nuevo} · 1 conversión | ¿Qué contrato resultó y qué aporte afirma la interfaz? El importe es K15; **«1 conversión» es literal UI**, no aporte servido. | `contrato.capital` + constante 1; no valida peso ni deduplicación. Formulario CN:1031 repite la promesa general. No convertir esta etiqueta en definición canónica. | MC:249; CN:1031 |
| K26 | Upgrade · suma conversión / mes inicial · no suma conversión | ¿La bandera guardada indica elegibilidad? Se presenta como aporte pero sólo lee booleano. | `elegible_conversion`; estado cualitativo por operación; no comprueba ser primera operación del cliente/mes. | MC:213,216 |
| K27 | Renovación histórica · desglose pendiente | ¿Falta un desglose completo fiable? | `!desglose_completo || capital_renovado==null || capital_adicional==null`; ausencia, no monto cero. | MC:221 |

El aporte canónico **no** se calcula aquí: `private.conversion_episodios` elige primera operación elegible por cliente/período antes de filtrar rango; renovación pesa como referido, upgrade 1 (SQL-O:103). Peso y deduplicación no deben reconstruirse en la UI. Mostrar aporte efectivo por operación requeriría justificar exponer datos ya existentes por una respuesta autorizada existente; no queda aprobado en este punto.

## C. Ficha de cliente

Contrato F: grupo completo del cliente obtenido de C, **no el grupo recortado visualmente al mes** (MC:1715). Identidad/autorización se revalida por `cliente_ficha_comercial_fn`; capital proviene del grupo C, no del payload de identidad. CF:240,293. Consultas de ficha y permisos se refrescan; error de capital/vencimientos muestra aviso y conserva últimos datos (CF:647). Tareas llegan del store `tareasDeCliente` (ST:1354), a su vez `listarTareasDelAmbito`, con tope 2,000 (API:1856). Modelo CFM:177 filtra cliente, activo, pendiente y vence_en válido; ordena por fecha ascendente. El riel usa reloj `ahora` y calendario Lima. Contratos de baja o demo heredan los riesgos C. L.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Campo → adaptación; unidad/disponibilidad | Fuente |
|---|---|---|---|---|
| K28 | Capital vigente — PEN | ¿Cuál es el saldo de contratos activos de este cliente cargado? | `grupo.capitalActivoPen → vista.capitalVigente.PEN`; PEN, todo el cliente, no mes visible de Cartera. Cero no muestra importe positivo. | CF:167,192; CFM:194 |
| K29 | Capital vigente — USD | Mismo K28 en USD, separado. | `grupo.capitalActivoUsd → capitalVigente.USD`; USD. Si no hay contrato activo: «Sin capital vigente». | CF:172; CFM:196 |
| K30 | {N} contrato(s) vigente(s) | ¿Cuántos contratos activos hay en el grupo completo? | `grupo.contratosActivos → vista.contratosActivos`; contratos, no clientes. | CF:194,604; CFM:198 |
| K31 | Renovación pendiente / Próximo vencimiento | ¿Qué vencimiento se destaca para continuidad? Primero el vencimiento pasado/hoy más reciente; si no, el futuro más próximo. | `estado activo o vencido + fecha_vencimiento válida`; DATE Lima, no necesariamente el vencido más antiguo. Sin fecha: «Sin renovación inmediata». | CF:189,197; CFM:159 |
| K32 | Siguiente contacto | ¿Cuál es la primera tarea activa pendiente y fechada de este cliente? | `vista.proximaTarea → tareaAEvento`; fecha/duración formateada. Incluye tareas atrasadas; null: «Sin contacto programado». | CF:187,206; CFM:183 |
| K33 | Y {N} seguimientos más en Agenda | ¿Cuántas tareas pendientes cargadas exceden las 3 mostradas? | `tareasPendientes.length-3` si >3; tareas. No total servidor independiente. | CF:683,689,706 |
| K34 | Soles: {N} — cuentas para recibir pagos | ¿Cuántas cuentas bancarias seleccionables PEN devolvió servidor? | `cuentas_bancarias_cliente_fn(cliente,PEN) → cuentasPen.length`; cuentas, no saldo monetario. Servidor combina origen perfil/contrato; no suma números bancarios. | API:2214; CF:348,972 |
| K35 | Dólares: {N} — cuentas para recibir pagos | Mismo K34 para USD. | `cuentasUsd.length`; consultas independientes. Ausencia/error/cargando se muestra en vez de 0; ambas deben estar confirmadas. | CF:349,392,977 |

Inversiones de la ficha reutilizan K15; historial de operaciones reutiliza K23/K24 y capital del contrato nuevo para upgrades (CF:378). Su fecha visible de historial es **`creado_en` del registro**, no `fecha_operacion` (CF:386). No hay un contador de conversiones efectivo en el historial.

## D. Detalle del contrato y cronograma

Contrato D: términos desde `useContrato`, que selecciona ID sobre la caché/lista limitada de C (Q:285). Cronograma separado: `crm.cronograma_contrato_fn(p_contrato_id)` → `obtenerCronograma` → `CuotaRowSchema` → `useCronograma` → totales UI (API:3164; CD:346). Autoriza por contrato/ámbito, no por período Gerencia. Importes siempre moneda del contrato. Abarca cronograma completo recibido, no rango de reporte. **Filas de cronograma inválidas se omiten silenciosamente** (API:3182); `monto_programado` normalizado nulo→0. No se afirma aquí completitud de respuesta por haber recibido éxito. Cargando/error sin datos se separa de []; fallo con caché conserva datos (CD:144). L.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Fuente/campo → adaptación; unidad y exclusiones | Fuente |
|---|---|---|---|---|
| K36 | Tasa anual | ¿Qué tasa nominal figura en este contrato? **Parámetro contractual**, no rentabilidad realizada. | `ContratoRow.tasa_anual`; %, sin división de capital ni recalcular intereses. Capital del contrato es K15. | CD:454,455; API:2990 |
| K37 | {N} cuotas de interés en título | ¿Cuántas filas del cronograma no son retorno de capital? | `cuotas.filter(tipo!='retorno').length`; filas, incluye `devolucion` del compuesto. Título compuesto no muestra ese N; título simple usa 0 mientras totales no llegan. | CD:348,365 |
| K38 | {N} de {M} cuotas de interés pagadas | ¿Cuántas filas no-retorno están pagadas del total no-retorno? | `pagadasInteres / cuotasInteres` como conteos, **no porcentaje**. Estados `pagado`; no suma cuota retorno. | CD:351,767 |
| K39 | Cuotas vencidas | ¿Cuántas filas tienen estado guardado vencido? | `cuotas.filter(estado='vencido').length`; incluye retorno/devolución; no compara fecha con reloj UI. | CD:352,678 |
| K40 | Próxima cuota — fecha e importe | ¿Cuál es la pendiente con menor fecha programada? | `estado='pendiente'`, orden `fecha_programada`; muestra DATE e `monto_programado`. No incluye vencidas. Sin pendiente: texto explícito. | CD:353,688 |
| K41 | Saldo por pagar | ¿Cuánto monto programado queda en filas ni pagadas ni trasladadas? | suma `monto_programado` de `estado!='pagado' && !='trasladado'`; moneda contrato, incluye capital/intereses, no saldo bancario ni capital vigente. | CD:359,699 |
| K42 | Pagado | ¿Cuánto pago real figura en cuotas marcadas pagadas? | suma `monto_pagado ?? 0` si estado pagado; incluye retorno capital y devoluciones. Un pago informado en otro estado no se suma. | CD:356,769 |
| K43 | Monto — fila cronograma | ¿Cuál es el monto programado de esta cuota/hito? | `monto_programado`; moneda contrato, fecha `fecha_programada`. Cualquier estado. | CD:742,746 |
| K44 | Pago real — fila cronograma | ¿Qué fecha/monto real de pago hay registrados? | `fecha_pago_real` y `monto_pagado`; si ambos null muestra «—», monto0 explícito puede mostrarse. No implica por sí solo estado pagado. | CD:723,752 |
| K45 | Cuota #{N}; retorno del capital / pago de intereses | ¿Qué ordinal o clase contractual tiene la fila? | `numero_cuota`, `tipo`; identificador ordinal, no conteo de contratos. Retorno/devolución se rotulan como hitos. | CD:729 |

Fechas de inicio/vencimiento/cierre, número/versión de producto, modalidad y plazo son **términos o identificadores**, no KPI de producción. La atribución del contrato llega por consulta separada `useAtribucionContrato` (CD:133): registrar un documento no equivale a obtener la venta. No se inventaría como KPI un número de cuenta, DNI, número de contrato o revisión PDF.

## E. Cooperativas dentro de Cartera

Contrato E: `crm.cierres_externos_fn(p_periodo)` → `obtenerCierresExternos` (API:4568) → `CierresExternosSchema` → `useCierresExternos` → `SeccionEnCooperativas`. Gerencia tiene ámbito global; atribución por `ce.vendedor_id` congelado del cierre, no dueño actual del lead. **Cierres y mini-totales de esta sección son históricos**, aunque se pide mes actual para otros campos del payload. No siguen mes, analista, estado o búsqueda de Cartera: sólo se pasa `demo` (MC:1611, CE:142). El servidor devuelve lista limitada a 200 y totales aparte.

Las filas y `cierres_total` incluyen anuladas y la excepción demo; los agregados monetarios `totales` excluyen **sólo el demo declarado** y mantienen capital de anulaciones reales, conforme ATR-4. No igualar `cierres_total` al sumatorio de `totales.cierres`. La anulación quita conversión, no dinero. L/S; definición viva `md5(prosrc)=d78d4b5152ed0cc3f55a9c4fea66f15f`.

Error de consulta muestra aviso y oculta bloque normal; durante carga y sin respuesta, `cierres_total ?? 0` oculta sección, igual que cero recibido (CE:197,216). No se recomputan totales reales desde las 200 filas.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Campo → adaptación; unidad | Fuente |
|---|---|---|---|---|
| K46 | En cooperativas · {N} cierres | ¿Cuántos registros de cierre hay en todo el ámbito? | `cierres_total`; cierres/operaciones, no clientes únicos, incluye anulaciones y demo listada. Histórico. | CE:197,231; CEL:116 |
| K47 | Importe PEN junto a En cooperativas | ¿Cuál es el capital histórico de cooperativas en PEN admitido en totales? | `totales[].capital` agrupado servidor por coop/moneda, UI consolida coops dentro PEN. Excluye excepción demo, incluye anulados reales. | CE:176,192,219 |
| K48 | Importe USD junto a En cooperativas | Mismo K47 en USD; sin TC ni suma con PEN. | `totales[].capital` USD; moneda separada. | CE:219 |
| K49 | Mostrando {n} más recientes de {N} | ¿Qué parte del histórico se cargó? | `cierres.length` contra `cierres_total`; lista≤200. Sólo si total supera lista. | CE:238 |
| K50 | Monto — fila/minificha | ¿Qué monto original se registró en ese cierre? | `cierres[].monto/moneda`; cualquier estado, incl. fila demo. Fecha `creado_en`; tachado no pone monto0. | CE:83,104,268 |

## F. Por empresa del Resumen y revisión de cierres

Contrato PE: `DesglosePorEmpresa` recibe `cumplimientoRanking?.porVendedor` del **mes elegido del panel** (HG:575), pero consulta cooperativas con `periodoLima(Date.now())` (CE:579), no recibe el mes elegido. Sólo crea filas de analistas con algún agregado `por_empresa`. `por_empresa` excluye demo declarado pero conserva anuladas reales; mes por instante `creado_en` Lima. Las filas de revisión usan `cierres_mes`, máximo200, incluidas anuladas/demo, y `cierres_mes_total` para avisar truncamiento. Éste es el significado actual, **no una garantía de que ambas fotos tengan el mismo mes**.

Error RPC cooperativas muestra aviso; vacío/cargando sin filas oculta panel. Capital de Avance hace `Math.max(0,totalCumplimiento-capitalCoops)`; cumplimiento ausente se vuelve0 antes de la resta, no «—» (CE:656; CEL:144). Por tanto ni igualdad temporal ni completitud de la parte Avance quedan garantizadas por el consumidor actual. No tocar fórmulas en este inventario. L/S.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Campo → adaptación; unidad/corte | Fuente |
|---|---|---|---|---|
| K51 | Avance Corp — PEN por analista | ¿Qué resto queda del capital de cumplimiento recibido tras restar coops PEN del mes actual? | suma `cumplimiento.detalles.capitalReal` PEN menos `por_empresa.capital` PEN, clamp0. No es una columna servida Avance. Fotografía de cumplimiento puede ser de otro mes. | CE:656,665,710; CEL:144; HG:576 |
| K52 | Avance Corp — USD por analista | Mismo K51 USD, separado. | `capitalReal` USD menos agregados USD, clamp0. Moneda no se presenta si ni Avance ni coops tienen positivo. | CE:658,667,712 |
| K53 | Capital Qorilazo/Prodelco por analista y moneda | ¿Cuánto capital del mes actual atribuye el RPC a este analista/coop/moneda? | `por_empresa[].capital`; PEN o USD según fila, magnitudes separadas; no único por cliente. | CE:613,725; CEL:125 |
| K54 | {N} cierres por coop/analista/moneda | ¿Cuántos registros económicos aporta ese grupo del mes actual? | `por_empresa[].cierres`; operaciones, no conversiones ponderadas; mismas exclusiones de agregado PE. | CE:727 |
| K55 | Mostrando los {N} más recientes del mes — revisión | ¿Cuántos cierres mensuales llegaron de una lista truncada? | `cierres_mes.length`; comparación con `cierres_mes_total`; max200, mes actual, filas originales (incluye anuladas/demo). | CE:468,742 |
| K56 | Monto — fila de revisión del mes | ¿Qué monto original tiene este registro que se revisa? | `cierres_mes[].monto/moneda`; no cambia por tachado. Fecha visible creado_en, mes actual, no fecha de llegada del lead. | CE:491,506 |

## G. Configuración general y usuarios

Contrato G: lecturas autorizadas independientes de configuración. El resumen general no suma registros de una página: `listarCatalogoUsuariosAdministrables` recorre páginas de100 del RPC `usuarios_administrables_fn` hasta total (CA:154). Universo usuarios = perfiles con membresía CRM o rol portal comercial/analista; no todos los perfiles cliente. Cuenta inactivos, candidatos y suspendidos en total; «activos» exige CRM y Portal activos. La pantalla de usuarios sí pagina50 y `total` viene de `count(*) over()` después de búsqueda. Reloj = fotografía actual; no período comercial. No asigna méritos comerciales. L/S.

En Config general los errores/carga sustituyen el dato por «Lectura no disponible»/«Verificando…» (CFG:98). En Usuarios la etiqueta total se construye incluso sin data: null→lista[]→0, mientras un panel separado informa carga/error (US:253,494,515). Éste es un cero de presentación, no un total verificado. Respuesta de configuración inválida aborta en el parser (CA:147), no cuenta filas omitidas.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Fuente/campo → adaptación; unidad/corte | Fuente |
|---|---|---|---|---|
| K57 | Personas activas · {N} de {M} habilitadas — N | ¿Cuántas personas del catálogo tienen ambas membresías activas? | `usuarios_administrables_fn → activo_crm===true && activo_portal` → length; personas; catálogo global actual sin búsqueda. | CFG:144,151,156; CA:154 |
| K58 | Personas activas · {N} de {M} habilitadas — M | ¿Cuántas personas contiene el catálogo autorizado completo? | `catalogo.length`; incluye estados no activos y candidatos. El texto «habilitadas» no redefine el denominador como sólo activos. | CFG:156; CA:154 |
| K59 | Catálogo y revisión · {N} productos | ¿Cuántos productos tienen estado activo? | `productos_inversion_gestion_fn → productos.filter(estado='activo').length`; productos, no versiones/contratos. | CFG:163,169; CA:294 |
| K60 | revisión {N} — Config general | ¿Cuál es el máximo número de revisión entre productos activos? | `max(producto.revision)`, inicial0; identificador de versión agregado en UI, no revisión única del catálogo. | CFG:164,169 |
| K61 | Metas del mes · {N} analistas | ¿Cuántas filas del roster devuelve configuración de metas del mes vigente? | `configuracion_metas_fn(periodoLima(hoy)) → vendedores.length`; personas del roster; no suma producción. | CFG:146,181; CA:405 |
| K62 | Metas del mes · revisión {N} | ¿Qué revisión de metas del mes vigente fue publicada? | `revision`; 0 significa sin publicación, no meta cero obligatoria. | CFG:181 |
| K63 | SLA vigente · v{N} | ¿Qué versión de política está vigente en la consulta? | `configuracion_sla_fn → politica.version`; ordinal, no %cumplimiento. | CFG:193; CA:447 |
| K64 | gestión {duración} — SLA vigente | ¿Qué plazo configurado tiene primera gestión? **Parámetro.** | `politica.primera_gestion_minutos → minutosLegibles`; minutos presentados como horas/días. No tiempo real promedio. | CFG:194 |
| K65 | {N} usuarios — Usuarios y jerarquía | ¿Cuántos usuarios coinciden con búsqueda aplicada? | primer `total` servido; fallback primera página length, otras0. Personas, no sólo activos, no lead arrivals. | US:239,253,494; CA:139 |
| K66 | Página {p} de {n} — usuarios | ¿Qué página de50 de ese resultado se consulta? | `pagina+1`, `max(1,ceil(total/50))`; páginas. No conteo comercial. | US:255,569 |

### Consulta de impacto de desactivación

Contrato I: `impacto_desactivacion_usuario_fn(p_perfil_id)` → `obtenerImpactoDesactivacion` → `useImpactoDesactivacionUsuario` → `ResumenImpacto`; se invoca **antes** del diálogo, sin ejecutar desactivación. Requiere Gerencia activa, confirma membresía objetivo; es conteo sobre propiedad **actual**, sin rango ni historial de asignaciones, y sin deduplicar personas entre categorías. Si falla no se abre como impacto0. API CA:248; SQL-U:1599; US:190. L/S.

| ID | Etiqueta actual | Pregunta y definición actual, fuente exacta | Unidad, ámbito y exclusiones | Fuente |
|---|---|---|---|---|
| K67 | Subordinados activos | ¿Cuántos miembros activos tienen supervisor_id igual a persona objetivo? `subordinados_activos`. | Miembros directos, no todo subárbol; `equipo.activo=true`, sin exigir aquí activo Portal. | US:192; SQL-U:1618 |
| K68 | Leads asignados | ¿Cuántos leads activos abiertos tienen vendedor_id objetivo? `leads_abiertos`. | Leads actuales, excluye convertido/descartado; no cantidad de asignaciones históricas. | US:193; SQL-U:1622 |
| K69 | Leads en bandeja | ¿Cuántos leads activos abiertos tienen asignado_supervisor_id objetivo? `leads_en_bandeja`. | Leads actuales, mismas exclusiones; puede solaparse con otra categoría. | US:194; SQL-U:1627 |
| K70 | Tareas pendientes | ¿Cuántas tareas activas pendientes tienen vendedor o supervisor objetivo? `tareas_pendientes`. | Tareas; OR por dueño cuenta fila una vez; no son sólo reuniones. | US:195; SQL-U:1632 |
| K71 | Clientes activos | ¿Cuántos perfiles cliente activos tienen asesor_perfil_id objetivo? `clientes_activos`. | Perfiles, no contratos, sin fallback creado_por en esta consulta. | US:196; SQL-U:1638 |

`requiere_reemplazo` es booleano servido (`suma cinco conteos>0`), no un sexto total de personas. No sumar esos cinco números como cantidad de personas/leads únicos.

## H. Productos y editor de metas

Contrato P: `productos_inversion_gestion_fn → ConfiguracionProductosSchema → useConfiguracionProductos` (CA:292), lista productos/versiones/condiciones autorizadas; sin ventana de ventas ni filtro por analista. «Publicado» compara estado, no comprueba adicionalmente vigencia de fecha para el contador. Carga sin data no muestra resumen; error sin data panel explícito, datos anteriores pueden conservarse (PR:1088,1106). L.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Campo/adaptación; unidad y corte | Fuente |
|---|---|---|---|---|
| K72 | {N} activos — Productos de inversión | ¿Cuántos productos tienen estado activo? | `productos.filter(estado='activo').length`; productos, alias semántico K59 pero superficie independiente. | PR:1014,1089 |
| K73 | {N} publicados | ¿Cuántos productos tienen al menos una versión estado publicada? | `productos.filter(versiones.some(estado='publicada')).length`; productos, no número de versiones ni condiciones; no filtro de fecha adicional. | PR:1018,1089 |
| K74 | revisión {N}; v{N} · nombre — producto/versión | ¿Qué revisión/versión identifica este objeto? **Metadatos.** | `producto.revision`, `version.numero_version/revision`; enteros por objeto, no agregables ni %avance. Vigencia por fechas propias. | PR:879,881,957 |
| K75 | Plazo; Capital mín.–máx.; Tasas mín./ref./máx. | ¿Qué condiciones admite esa versión? **Parámetros**, no capital captado ni retorno pagado. | `condicion.plazo_meses` meses; `capital_minimo/maximo` moneda condición; `tasa_minima/referencia/maxima` %anual. Se muestran condiciones activas y reemplazadas rotuladas. | PR:826,829,832 |

Los contadores «Condición i de n» y caracteres n/2,000 del editor son estado local de formulario (PR:494,544), no métricas de negocio ni hechos del servidor. Se distinguen deliberadamente del inventario de producción.

Contrato M: `configuracion_metas_fn(p_periodo)` → `ConfiguracionMetasSchema` → copia local `borrador`. La definición viva devuelve **roster actual** de `private.roster_metas_vendedores()` y valores de la última revisión publicada del período solicitado; no asumir que esta lista es la fotografía histórica sellada de cumplimiento. La edición local modifica los valores que se muestran antes de publicar; se avisa «cambios sin publicar». El período es mes DATE; no rango parcial, ni fecha del cierre de leads. Personas excluidas llegan aparte en `sin_supervisor`.

`metaTotal` suma sólo dimensiones PEN; `conversionEmpresa` promedia objetivos positivos y redondea2; no usa conversión conseguida. Error de consulta se muestra; falta de borrador no imprime total. Foto de cierre (`useCierreMesEstado`) es advisory: si falla no se asume mes cerrado y el servidor mantiene su propio bloqueo. MT:55,87,284,313,547. L/S.

| ID | Etiqueta actual / alias | Pregunta y definición exacta actual | Campo → adaptación; unidad/exclusiones | Fuente |
|---|---|---|---|---|
| K76 | Meta mensual por analista | ¿Qué objetivo PEN tiene ese analista en el borrador/revisión del mes? **Parámetro editable.** | suma `vendedor.detalles[].capital_objetivo` donde moneda PEN. USD omitido, no convertido; guardar normaliza al slot nuevo/PEN. | MT:55,70,111 |
| K77 | Conversión objetivo | ¿Qué porcentaje objetivo común presenta el editor? **Parámetro**, no conversión observada. | promedio de `vendedores[].conversion_objetivo>0`, redondeado2; sin positivos0/vacío. Edición replica un mismo valor en todos. | MT:87,93,479 |
| K78 | Meta total del equipo | ¿Cuánto suma el objetivo PEN de todo el roster del borrador? | suma `metaTotal(vendedor)`; PEN; incluye ediciones no publicadas, no capital confirmado. | MT:324,507 |
| K79 | Subtotal junto al supervisor | ¿Cuánto se pide en PEN a las filas de ese supervisor del borrador? | agrupar por `supervisor_id`, sumar `metaTotal`; PEN, no grupo por nombre. | MT:206,593 |
| K80 | {N} analistas — editor de metas | ¿Cuántas filas de roster contiene el borrador? | `borrador.vendedores.length`; personas, no sólo metas positivas. | MT:511 |
| K81 | {N} analista(s) sin meta este mes | ¿Cuántos devuelve servidor excluidos por jerarquía inválida actual? | `sin_supervisor.length`; razones sin supervisor, supervisor inactivo o sin rol correcto. **No enumera a todo analista con objetivo0.** | MT:223,254,541 |
| K82 | Revisión {N} / Sin publicar — editor | ¿Cuál es la última revisión del período cargado? | `borrador.revision`; >0 revisión, 0 sin publicar. No cambia por editar hasta guardar. | MT:425 |
| K83 | Versión {N}; Hay una versión futura v{N} — SLA | ¿Qué política rige y cuál es la mayor versión registrada? **Metadatos.** | `politica.version` y `expected_version`; futura si expected>vigente. No %evaluación. | SL:267,295 |
| K84 | Primera gestión / Primer contacto / Tiempo máximo por etapa | ¿Qué plazo configura la política/borrador? **Parámetros.** | `primera_gestion_minutos`, `primer_contacto_minutos`, `etapas[].maximo_minutos`; minutos, UI horas/días. Días corridos; no cambia casos ya iniciados. | SL:293,304,324 |

## I. Cumplimiento histórico SLA: ocho familias, cuatro indicadores visibles cada una

Contrato S: `crm.metricas_sla_fn(desde,hasta)` → `MetricasSlaSchema` → `useMetricasSla` → componente `Cumplimiento` (CA:494; SL:142,195,383). Gerencia global, sin filtro de analista/origen; **casos/episodios**, no leads únicos ni conversiones. Agrupa siempre por ID y versión de política, y por etapa donde corresponde. Rango inclusive de fechas Lima, máximo diferencia365 días, hasta no posterior a hoy. La población se fija por **inicio del episodio/asignación**, no fecha en que se cumplió; estado se evalúa con `now()` servidor al consultar. No foto sellada.

**Disponibilidad actual importante:** el editor inicia `hasta=finMes(hoy)` (SL:193) y el RPC vivo rechaza hasta>hoy; salvo último día del mes el rango inicial es inválido. Esto debe figurar como error de consulta, no cero evaluable. No se ha corregido. Se puede elegir rango permitido sin cambiar datos. Si error con data previa, SL:374 y380 pueden mostrar aviso y última respuesta; no sustituir por un cero.

Definiciones por familia:

- **Ciclo, primera gestión/contacto:** `lead_sla_ciclos.iniciado_en` en rango; hito correspondiente y límite de la política asignada. Evaluable = hito no nulo o ahora≥límite; cumplido = hito≤límite; fuera = hito>límite o falta hito y ahora≥límite; pendiente = falta hito y ahora<límite.
- **Asignación, primera gestión/contacto:** `lead_asignaciones.asignado_en` en rango; join política asignación e hitos de asignación. Evaluable añade `finalizado_en IS NOT NULL`; finalización sin hito ya es fuera, aunque límite no haya llegado. Puede haber varias asignaciones del mismo lead: legítimo para esta métrica operativa.
- **Etapa:** `lead_sla_etapas.iniciado_en` en rango y etapa exacta; evaluable = finalizado o ahora≥límite; cumplido = finalización≤límite; fuera = finalización tarde o ausencia con límite vencido; pendiente = no finalizado y todavía dentro de plazo.
- **Porcentaje UI:** `round(100*cumplidos/evaluables)` si evaluables>0, si no «Sin evaluables» y barra0. `total` y `evaluables` son entradas ocultas, **no contadores impresos**. `objetivo_minutos` se rotula por grupo junto a `politica_version`; no se usa política vigente para reescribir hechos históricos.
- Fuente semántica: SQL-S:1230,1253,1286; definición viva `metricas_sla_fn`, `md5(prosrc)=b9917c230692cbf1c121f3c2f084008e`; representación SL:166,173,179. Todas las filas siguientes L/S, unidad casos salvo porcentaje, contrato S heredado.

| ID | Etiqueta actual y familia | Pregunta/campo exacto | Unidad / población |
|---|---|---|---|
| K85 | % — Ciclo · primera gestión | ¿Qué parte evaluable cumplió? `ciclos.primera_gestion[].cumplidos/evaluables`. | % redondeado entero; ciclos gestión, SL:383 |
| K86 | cumplidos — Ciclo · primera gestión | ¿Cuántos cumplieron? `ciclos.primera_gestion[].cumplidos`. | casos; SL:179,383 |
| K87 | fuera — Ciclo · primera gestión | ¿Cuántos están fuera del objetivo? `ciclos.primera_gestion[].fuera_objetivo`. | casos; SL:179,383 |
| K88 | pendientes — Ciclo · primera gestión | ¿Cuántos siguen dentro de plazo sin hito? `ciclos.primera_gestion[].pendientes`. | casos; SL:179,383 |
| K89 | % — Ciclo · primer contacto | ¿Qué parte evaluable logró contacto en plazo? `ciclos.primer_contacto[].cumplidos/evaluables`. | % entero; SL:384 |
| K90 | cumplidos — Ciclo · primer contacto | `ciclos.primer_contacto[].cumplidos`. | casos; SL:179,384 |
| K91 | fuera — Ciclo · primer contacto | `ciclos.primer_contacto[].fuera_objetivo`. | casos; SL:179,384 |
| K92 | pendientes — Ciclo · primer contacto | `ciclos.primer_contacto[].pendientes`. | casos; SL:179,384 |
| K93 | % — Asignación · primera gestión | ¿Qué parte evaluable cumplió gestión de esa asignación? `asignaciones.primera_gestion[].cumplidos/evaluables`. | % entero; SL:385 |
| K94 | cumplidos — Asignación · primera gestión | `asignaciones.primera_gestion[].cumplidos`. | asignaciones; SL:179,385 |
| K95 | fuera — Asignación · primera gestión | `asignaciones.primera_gestion[].fuera_objetivo`. | asignaciones; SL:179,385 |
| K96 | pendientes — Asignación · primera gestión | `asignaciones.primera_gestion[].pendientes`. | asignaciones; SL:179,385 |
| K97 | % — Asignación · primer contacto | ¿Qué parte evaluable logró contacto en plazo? `asignaciones.primer_contacto[].cumplidos/evaluables`. | % entero; SL:386 |
| K98 | cumplidos — Asignación · primer contacto | `asignaciones.primer_contacto[].cumplidos`. | asignaciones; SL:179,386 |
| K99 | fuera — Asignación · primer contacto | `asignaciones.primer_contacto[].fuera_objetivo`. | asignaciones; SL:179,386 |
| K100 | pendientes — Asignación · primer contacto | `asignaciones.primer_contacto[].pendientes`. | asignaciones; SL:179,386 |
| K101 | % — Por etapa: Lead nuevo | `etapas[etapa=nuevo].cumplidos/evaluables` por política. | % entero de episodios etapa; SL:21,390 |
| K102 | cumplidos — Lead nuevo | `etapas[etapa=nuevo].cumplidos`. | episodios etapa; SL:179,390 |
| K103 | fuera — Lead nuevo | `etapas[etapa=nuevo].fuera_objetivo`. | episodios etapa; SL:179,390 |
| K104 | pendientes — Lead nuevo | `etapas[etapa=nuevo].pendientes`. | episodios etapa; SL:179,390 |
| K105 | % — Por etapa: Contactado | `etapas[etapa=contactado].cumplidos/evaluables` por política. | % entero; SL:390 |
| K106 | cumplidos — Contactado | `etapas[etapa=contactado].cumplidos`. | episodios etapa; SL:179,390 |
| K107 | fuera — Contactado | `etapas[etapa=contactado].fuera_objetivo`. | episodios etapa; SL:179,390 |
| K108 | pendientes — Contactado | `etapas[etapa=contactado].pendientes`. | episodios etapa; SL:179,390 |
| K109 | % — Por etapa: Cita agendada | `etapas[etapa=reunion_agendada].cumplidos/evaluables` por política. | % entero; etapa no citas físicas; SL:21,390 |
| K110 | cumplidos — Cita agendada | `etapas[etapa=reunion_agendada].cumplidos`. | episodios etapa, no asistencias; SL:179,390 |
| K111 | fuera — Cita agendada | `etapas[etapa=reunion_agendada].fuera_objetivo`. | episodios etapa; SL:179,390 |
| K112 | pendientes — Cita agendada | `etapas[etapa=reunion_agendada].pendientes`. | episodios etapa; SL:179,390 |
| K113 | % — Por etapa: Propuesta enviada | `etapas[etapa=propuesta_enviada].cumplidos/evaluables` por política. | % entero; SL:390 |
| K114 | cumplidos — Propuesta enviada | `etapas[etapa=propuesta_enviada].cumplidos`. | episodios etapa; SL:179,390 |
| K115 | fuera — Propuesta enviada | `etapas[etapa=propuesta_enviada].fuera_objetivo`. | episodios etapa; SL:179,390 |
| K116 | pendientes — Propuesta enviada | `etapas[etapa=propuesta_enviada].pendientes`. | episodios etapa; SL:179,390 |

## J. Comparabilidad y datos existentes no consumidos

Esta matriz es inventario, **no autorización ni implementación** de reemplazos.

| Magnitud | Lectura actual | Lectura existente candidata | Diferencia que exige conciliar |
|---|---|---|---|
| Saldo activo PEN/USD global | K01/K02; UI suma lista C | `crm.resumen_cartera_clientes_fn().capital_activo`, desde capital_episodios | Candidata excluye demos; no depende de 2,000 filas. No es una respuesta actualmente consumida por MC. |
| Clientes en gestión/baja/con capital | K07/K08/K09, listas actuales | `resumen_cartera_clientes_fn().clientes` | Comparar universo de perfiles autorizado y contratos excluidos; no asumir perfil de prueba igual a contrato demo ni borrar perfiles. |
| Sin analista | K11: dueño fallback + no pertenece a roster | `resumen_cartera_clientes_fn().clientes.sin_asesor` | Servidor cuenta `asesor_perfil_id IS NULL`, UI incluye dueño fuera de roster y fallback creado_por. **No son equivalentes.** |
| Alarma por vencer | K05/K06, día local navegador y lista con demos | `resumen_cartera_clientes_fn().contratos.por_vencer_30` y de_baja | RPC usa Lima, incluye clientes inactivos pero núcleo excluye demos. Contratos `por_estado` incluye bajas; chip hipotético activos UI sólo gestión no sería el mismo conteo. |
| Capital del mes | K03/K04, contratos Avance, estado cualquiera, filtros locales | `contratos_por_periodo_comercial_fn(p_periodo)` | Totales del RPC incluyen coops; `contratos` detallados Avance, ámbito Gerencia/global, no replica filtros de MC. No conectar totales globales directamente al bloque filtrado. |
| Contribución por operación | K25 literal y K26 bandera elegible | `conversion_episodios`: operación_id/aporte_numerador | Dato existe en núcleo, pero no en lista pública de operaciones; trasladarlo por fachada existente es una necesidad a justificar, no una nueva calculadora autorizada. |
| Capital por empresa | K51–K54 restan lecturas con períodos potencialmente diferentes | Salidas existentes de cumplimiento y cierres externos | Hacer coincidir mes y disponibilidad antes de interpretar resta; no inferir que ausencia cumplimiento significa Avance0. |
| Comparación histórica de objetivos | K76–K82 editor con roster actual | Foto mensual de cumplimiento/mes sellado | Configurar metas ≠ observar cumplimiento. La lista actual de personas no necesariamente coincide con roster sellado. |

Referencia del resumen candidato: SQL-R:72; código vivo consultado en la auditoría, sin consumo frontend salvo declaración `database.types.ts`. Su semántica preserva saldo/mes/capital real; no reemplaza por sí sola todos los KPI.

## K. Cierre de cobertura y límites

- **116 registros K01–K116**, sin huecos; parámetros/metadatos están rotulados y no cuentan como resultados de captación. Los dos importes PEN/USD, los modos mes/todos y los 32 indicadores SLA se distinguen donde es necesario.
- Repeticiones móviles/desktop y variantes de palabras que comparten dato aparecen como alias; no se equiparan preguntas distintas para forzar coincidencia.
- Cubiertos: cabecera, chips, filas y subtotales de Cartera; contratos/operaciones y fichas; cronograma; cooperativas históricas y Por empresa/revisión mensual; resumen Config; catálogo/estado de usuarios y consulta de impacto; catálogo de productos; editor de metas y exclusiones; parámetros/versiones SLA y sus resultados por política.
- Los campos de identidad, contacto, banca y formulario no se copian ni se consideran métricas. No se descargaron archivos ni se ejecutaron acciones de alta, anulación, renovación, publicación o desactivación.
- No hay exportador estadístico CSV/XLSX en las superficies inventariadas; PDF contractual y exportación de calendario tienen semántica documental/de agenda, no totales gerenciales nuevos.
- Vigencia probada: código del commit indicado y definiciones SQL abajo. No se probó visualmente cada estado de error/permisos ni se simularon registros en producción. Afirmaciones de comportamiento condicional están sustentadas en el camino de código, no en una ocurrencia real inventada.
- Ninguna corrección del punto2/3, ampliación del4, pruebas de mutación del5, commit/push o publicación está realizada/autorizada por este documento.

### Huellas de definiciones verificadas (md5 de prosrc, no de archivo)

| Función | Huella / procedencia |
|---|---|
| `crm.metricas_sla_fn` | `b9917c230692cbf1c121f3c2f084008e` · consultada en esta ejecución |
| `crm.impacto_desactivacion_usuario_fn` | `88a1d6e3f94831065e6bde3ecb5a3d57` · esta ejecución |
| `crm.cierres_externos_fn` | `d78d4b5152ed0cc3f55a9c4fea66f15f` · esta ejecución |
| `crm.usuarios_administrables_fn` | `4b2993035c1bfb6fc72f7c730ffcfd95` · esta ejecución |
| `crm.configuracion_metas_fn` | `91ccdd17703ea10dbd1271f5544268ae` · esta ejecución |
| `crm.contratos_cartera_fn` | `5776edb84d509ee717931973cd1710ca` · auditoría previa enlazada |
| `crm.contratos_cartera_v2_fn` | `0efcab11c1837d70d215174abf8d9d08` · auditoría previa |
| `crm.resumen_cartera_clientes_fn` | `541c486b442011cd4a4a367ea8a0dd7a` · auditoría previa |
| `private.capital_episodios` | `38c99b1bd6e8ae0bc8bb0f93d5487ce8` · auditoría previa, revalidación común del inventario |

Las huellas identifican la evidencia; no autorizan reemplazar cuerpos ni ejecutar migraciones.
