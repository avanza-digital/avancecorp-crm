---
tags: [crm, gerencia, auditoria, metricas, semantica, plan]
fecha: 2026-09-04
estado: analizado-pendiente-de-aprobacion-sin-implementar
---

# Auditoría de métricas de Gerencia — hallazgos y plan

Relacionado con [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]], [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]], [[Contrato de la capa semantica - Capital (F4, 2026-08-29)]], [[Gestión comercial de clientes - renovaciones y upgrades]], [[Main unico - sincronizacion y publicacion 2026-09-04]] e [[Inicio]].

## Mandato y resultado

Miguel pidió revisar las inconsistencias de las pantallas de Gerencia y entregar un plan, **sin editar núcleos ni crear funciones o calculadoras independientes**, preservando la semántica del servidor. Si falta un dato, explicar primero la necesidad técnica y comercial.

**Se realizó diagnóstico, no implementación.** No se modificaron código de aplicación, SQL, configuración, permisos, datos ni producción. Este informe es documentación local; no implica autorización para aplicar el plan o publicar.

Conclusión: hay inconsistencias de consumo, presentación y algunas fachadas de lectura. No se necesita otro núcleo. En particular, el núcleo de citas **ya existe**: el problema de «25 llegaron a cita / 48 pactadas» no autoriza a modificarlo ni a modificar el significado histórico del embudo de conversión.

## Evidencia y alcance

- Código inspeccionado: Main `62ef70cc48aed683d11f9d96f9624f20f4d16a66`; el árbol de aplicación corresponde al release publicado desde `b8108ae3f4dc`.
- Ventana principal contrastada: **1–4 de septiembre de 2026, America/Lima**. Consulta de capital vigente: «Todos los meses». Auditoría realizada la noche del 4 de septiembre, hasta aproximadamente 20:45 Lima.
- Navegador: sesión existente de Gerencia; lectura de Resumen, Conversiones, Citas, Rendimiento, Pipeline, Cartera, Metas y Alertas. Se probó el filtro de Pipeline y el cambio de mes de Cartera; no se ejecutaron acciones de negocio.
- Servidor: definiciones reales y consultas agregadas dentro de `begin read only`, con límite de tiempo y `rollback`; sin contraseñas ni cambios de sesión de usuario.
- Código: inventario de rutas activas, componentes, adaptadores, consultas, validadores y decisiones del vault. CodeGraph se consultó primero; lecturas puntuales complementaron sus resultados.
- También se revisaron las fuentes de Ranking y sus pestañas, Leads, Agenda, Gestión de equipo, Repartir y su historial, Base para gestión y carpetas, configuración, metas, productos, usuarios y SLA. La comprobación de estas últimas fue principalmente estática; no se ejercitaron altas, ediciones, anulaciones, reasignaciones, exportaciones de documentos ni permisos destructivos.
- No es una certificación de seguridad ni una prueba exhaustiva de todos los estados de cada formulario. Los escenarios de error, exceso de filas y sobrecumplimiento se distinguen de las incidencias observadas en producción.

Las rutas de evidencia siguientes son relativas a `CRM-Avance-Corp/`. Las referencias a `app/src/screens/hoy/gerencia.tsx` no deben confundirse con el archivo puente `app/src/screens/gerencia.tsx`.

## Hallazgos confirmados

### G01 · Alta — Rendimiento todavía presenta asignaciones como llegadas

**Evidencia:** `app/src/lib/distribucion-lecturas.ts:235` suma `pen.cohorte.episodios_recibidos` y `usd_no_segmentado.cohorte_episodios_recibidos`. `app/src/screens/hoy/distribucion-leads-gerencia.tsx:708` lo presenta como «Recibió N leads en el período».

El servidor productivo confirma que esos campos vienen del núcleo operativo de Distribución, recortados por **fecha de asignación**, con `count(*)` de episodios. V2 encadena ese resultado y V3 conserva esos campos aunque añada el índice canónico de conversión.

En la pantalla se observaron, por ejemplo, 16 en el bloque comercial de un analista y «Recibió 29» en su tarjeta operativa; otro mostraba 4 y 49. No son distintas versiones de las llegadas: **son unidades diferentes bajo un nombre parecido**. El número superior además es base automática, no todas las llegadas (G04).

**Impacto:** vuelve a presentarse como captación el movimiento de leads entre personas, precisamente lo que Miguel rechazó para estos reportes.

**Corrección propuesta:** retirar esos conteos de los reportes comerciales o conectar la tarjeta a una salida existente de llegadas originales, con el mismo rango e identidad. No basta sustituirlos por `leads_unicos_recibidos`: ese campo también usa la ventana y atribución de asignaciones. El control operativo de entregas debe seguir disponible en Repartir, correctamente nombrado.

La «Puntería» de ese panel mide ciclos resueltos de asignación, no captación. No convertirla en conversión comercial ni alterar su fórmula; separarla del reporte comercial o explicar su unidad operativa, de acuerdo con el alcance decidido.

### G02 · Alta — Conversiones presenta avance inferido como asistencia

**Evidencia:** `app/src/screens/hoy/inteligencia-comercial.tsx:714`; también embudo y detalle individual en el mismo archivo (`:106`, `:238`, `:436`, `:620`). El agregador existente infiere una cita realizada por propuesta o cierre, incluso sin registro de cita.

Reproducción agregada actual: 243 llegadas; 25 con la bandera inferida de realización y 48 con la de agendamiento. De los 25, sólo 8 tienen la señal histórica que acepta ese código y 17 se infieren sin ella. De los 48, 38 tienen señal de agendamiento. **Los 8 tampoco se certifican como asistencias reales:** esa señal no es la clasificación del núcleo de citas.

**Impacto:** el gerente puede interpretar asistencia, ausencias o desempeño de analistas que los datos mostrados no demuestran. Cambiar únicamente la tarjeta deja la misma confusión en el embudo y detalle.

**Corrección propuesta:** preservar el avance inferido como tal, pero no llamarlo asistencia. Para citas operativas usar la salida existente de `crm.metricas_reuniones_fn`, indicando que cuenta citas por fecha prevista, no leads por fecha de llegada. Si se desea exactamente «leads del lote que asistieron», ver la necesidad adicional N1; no sustituir silenciosamente una pregunta por otra.

### G03 · Alta — Cartera incluye capital de contratos de prueba

**Evidencia:** la fachada productiva `crm.contratos_cartera_fn`, consumida por su variante V2, no excluye `es_demo`; el núcleo de capital sí. La fachada tampoco expone ese atributo al cliente.

Ruta: `app/src/data/crm-api.ts:2953` → `app/src/screens/mi-cartera.tsx:1706` → `app/src/lib/cartera-vista.ts:67` y `:186`. Las tarjetas suman contratos activos de clientes activos descargados.

Se comprobaron **dos contratos de prueba activos**, con fecha comercial en agosto: **S/ 100.000 y US$ 100.000**. La pantalla «Todos los meses» y la consulta agregada concilian:

| Moneda | Contratos activos incluidos por la pantalla | Mismos contratos, excluyendo los de prueba |
|---|---:|---:|
| PEN | 19.585.413,12 | 19.485.413,12 |
| USD | 1.175.193,33 | 1.075.193,33 |

Estos son totales de **esa población de contratos**, no una equivalencia automática con todas las medidas de capital del núcleo, que también contempla otros hechos como cooperativas. La contaminación afecta agosto y el saldo global; esos dos contratos no explican diferencias del septiembre seleccionado.

**Corrección propuesta:** excluir los contratos de prueba en la **fachada de listado existente**, conservando autorización; no borrar contratos ni perfiles. Para indicadores, aprovechar `crm.resumen_cartera_clientes_fn`, ya existente y conectado al núcleo, después de conciliar campo por campo su alcance. No sustituir indiscriminadamente: por ejemplo, «sin asesor» no tiene idéntico criterio al de la UI (nulo frente a dueño/fallback y pertenencia al roster).

### G04 · Media/alta — «Recibidos» es en varios lugares sólo la base automática

**Evidencia:** `app/src/lib/conversion-vendedores.ts:328` asigna `detalle.leads = fila.divisor`; `app/src/screens/hoy/ranking-vendedores.tsx:311` dice «Recibidos»; `app/src/screens/hoy/equipo-gerencia.tsx:60` y `:76` dicen «Recibidos del mes». Se repite en grupos, tarjetas y detalle mensual de Conversiones.

En el rango revisado, **231** es la base automática Landing/Formulario; **243** son todas las llegadas comerciales, incluidas 11 manuales y 1 referido. Ambos números son válidos, pero no significan lo mismo.

**Corrección propuesta:** «Base automática» cuando el campo es `divisor`; «Leads recibidos» sólo cuando se consuma un total de llegadas servido. No reconstruir el total añadiendo campos heterogéneos en el navegador. El contrato mensual actual no declara ese total por responsable; primero buscar la proyección existente adecuada.

### G05 · Alta — Rendimiento mezcla el mes visible con un rango anterior oculto

**Evidencia:** `app/src/screens/hoy/gerencia.tsx:232` normaliza `periodoRanking`; `:239` hace mensual el selector; `:287` consulta Distribución con el rango libre `periodo`; `:543` imprime el pie mensual; `:859` oculta el rango del panel inferior con `mostrarPeriodo={false}`.

**Escenario confirmado por cableado:** aplicar un rango parcial en Conversiones y entrar en Rendimiento sin cambiar el mes. El panel superior usa el mes hasta hoy, mientras el inferior mantiene el rango anterior. En la visita productiva el rango inicial era 1–4, coincidente con el mes hasta hoy: no se afirma que ese recorrido concreto produjo cifras diferentes por fecha.

**Corrección propuesta:** usar el `periodoRanking` existente tanto en la consulta como en las props de Rendimiento. No cambiar cómo el servidor interpreta las fechas.

### G06 · Media/alta — Citas no explica todos los estados ni el divisor del porcentaje

Producción 1–4: **28 pactadas = 5 realizadas + 16 ausencias + 1 cancelada por analista + 4 canceladas por sistema + 2 sin resultado**. La UI muestra 5, 17 no concretadas, 0 reprogramadas y 2 sin resultado; omite las cuatro canceladas por sistema aunque el payload las trae.

Además, la modalidad virtual presenta **23,5 % junto a «4 de 21»**. El porcentaje servido es 4/17: excluye las cuatro canceladas por sistema. El texto imprime el denominador bruto21. Evidencia: `app/src/screens/hoy/reuniones-gerencia.tsx:111`, `:117`, `:119`, `:120` y `:126`.

**Corrección propuesta:** mostrar los estados disponibles y mantener el porcentaje servido, con su definición correcta. Si se requiere imprimir la fracción ajustada por modalidad, ver N2; no recalcularla sobre un denominador incompleto.

**Reglas que no cambian:** las canceladas siguen dentro de pactadas. Asistencia **23,8 % = 5/(5+16)** y realización **20,8 % = 5/24** son medidas distintas y legítimas; no forzar igualdad.

### G07 · Media/alta — «Ritmo semanal» ubica el cierre en la semana de llegada

**Evidencia:** migración aplicada `supabase/migrations/20260904210831_crm_conversion_llegadas_unicas.sql:752` agrupa por fecha original de llegada y cuenta cierres de esos leads hasta hoy. `app/src/screens/hoy/resumen-gerencia.tsx:467` e `inteligencia-comercial.tsx:891` dicen «Leads recibidos y cierres por semana del rango».

**Impacto:** un cierre de septiembre puede hacer crecer la semana de llegada de agosto. El gráfico no demuestra cuántos cierres se produjeron cada semana.

**Corrección propuesta:** «Resultados por semana de llegada» y «Cerraron hasta hoy», preservando la serie. Para productividad por semana real de cierre, verificar primero una salida temporal existente; si falta, justificarla según N4.

### G08 · Media — «Conversión por origen» no es el índice comercial general

**Evidencia:** `app/src/screens/hoy/resumen-gerencia.tsx:506` y `inteligencia-comercial.tsx:859`; la proporción viene de cierres del mismo lote / llegadas de ese origen. Incluye manuales en ese lote y no representa el índice con arrastre y cartera.

La advertencia distingue sólo al Referido, pero Landing y Formulario también son resultados del lote. Por eso no corresponde compararlos directamente con el 3,90 % principal.

**Corrección propuesta:** «Resultados de los leads por origen», indicando «de los recibidos, cuántos cerraron hasta hoy». Conservar los porcentajes del servidor y revisar el alcance del filtro de origen, que actualmente no recorta el índice principal. No incorporar Walking/Otro al núcleo porque aparezcan en el selector operativo.

### G09 · Media — Los filtros no tienen el mismo alcance que las tarjetas

- Pipeline filtra sólo columnas (`app/src/screens/pipeline.tsx:226`), mientras las tarjetas siguen siendo de toda la empresa (`:313`). Verificado en navegador: seleccionar un analista cambia las columnas y deja 769 leads activos y el mismo capital global arriba.
- Leads tiene una separación equivalente entre tabla y resumen (`app/src/screens/cartera.tsx:56` y `:64`).
- Cartera con mes filtra las tarjetas por analista/estado/búsqueda; al elegir «Todos los meses» vuelve al total global, aunque la tabla continúe filtrada (`app/src/screens/mi-cartera.tsx:988`, `:1013`, `:1215`).

**Corrección propuesta:** explicitar «Indicadores de toda la empresa» y «Filtro aplicado al listado» donde ése es el contrato. Si se requiere que los indicadores respondan al filtro, comprobar el soporte del agregador existente y acordar ese alcance; no sumar tarjetas/listas parciales para imitarlo.

### G10 · Alta — Cartera promete aportes de conversión que no están garantizados

- Renovación: `app/src/screens/mi-cartera.tsx:249` muestra «1 conversión» y `app/src/components/app/contrato-nuevo.tsx:1031` promete una conversión por cliente/mes. La regla vigente pondera la renovación como Referido, actualmente ×0,15, sujeta a elegibilidad y deduplicación.
- Upgrade: `mi-cartera.tsx:216` dice «suma conversión» sólo con `elegible_conversion=true`. Esa bandera no garantiza que la operación sea la elegida por el núcleo para ese cliente/mes.
- La revisión agregada encontró siete combinaciones cliente/mes con varias operaciones elegibles y nueve operaciones adicionales que no implican otro aporte mensual; ocho son upgrades. No presentar elegibilidad como aporte efectivo.

**Corrección propuesta:** retirar la promesa fija; explicar la regla vigente y distinguir «registrada/elegible» de «contabilizada». Para atribuir un aporte exacto por operación, ver N3. No cambiar los pesos, el orden de elección ni la deduplicación.

## Defectos de protección y riesgos condicionados

Estos casos están trazados en código; no se provocaron fallos ni se fabricaron datos en producción para demostrarlos.

### G11 · Alta preventiva — Porcentaje principal sin control de las sondas

Resumen (`resumen-gerencia.tsx:155`) y Conversiones (`inteligencia-comercial.tsx:722`) muestran el porcentaje recibido sin exigir las sondas verificadas. El esquema admite una respuesta con `cuadra=false`; algunos bloques se ocultan mientras el porcentaje principal puede seguir visible.

**Plan:** reutilizar `app/src/lib/sondas-conversion.ts:19` y los estados existentes. Descuadre, sin verificación y cero real deben ser distintos. No se afirma un descuadre actual del índice 3,90 %.

### G12 · Alta preventiva — Error de carpeta presentado como cero oportunidades

`app/src/screens/rescate-descartados.tsx:296` guarda los estados de carga/error de episodios, pero la rama de carpeta desde `:484` no los usa: puede mostrar «0 leads guardados», «Recuperables0» y «No hay coincidencias» (`:511`, `:521`, `:597`).

**Plan:** reutilizar carga/error/reintento de la pantalla también dentro de la carpeta. Cero sólo después de una respuesta válida y completa.

### G13 · Media preventiva — «No evaluable» confundido con ausencia de desviaciones

Las alertas correctamente se inhiben cuando falta muestra, no se alcanza el corte o las sondas no verifican (`app/src/lib/alertas-gerencia.ts:236`, `:291`). Sin errores técnicos ni alertas, `app/src/screens/alertas.tsx:566` termina en «Nada pendiente / No hay desviaciones estratégicas…».

Se observó ese estado vacío el día4, con texto general de muestra suficiente. No demuestra que todas las comparaciones se hayan ejecutado y resultado saludables.

**Plan:** diferenciar «sin desviaciones detectadas» de «evaluación pendiente/no disponible», sin bajar umbrales ni retirar las guardas. Probar también que un enlace desde una alerta respete su período: hoy la navegación por hash puede conservar el mes previamente seleccionado.

### G14 · Media preventiva — Totales dependientes de listas parciales o filas descartadas

`app/src/data/crm-api.ts:555`, `:1856`, `:2412`, `:2459`, `:2963` utiliza límites de descarga; determinados validadores omiten filas inválidas y registran el problema sólo técnicamente (`:1277`, `:2483`, `:3010`). Pipeline/Agenda y varios resúmenes de Cartera trabajan sobre arrays descargados.

Producción revisada: 420 clientes, 519 contratos y 86 operaciones; no se alcanzó el límite cliente2000. La vista operativa tiene1087 leads y797 tareas pendientes. **No se certificó el límite efectivo remoto de la API ni truncamiento actual**; el `max_rows=1000` local no prueba la configuración remota.

**Plan:** indicadores desde resúmenes existentes del servidor; listados con paginación/completitud explícita y avisos ante parcialidad/validación fallida. No aumentar el límite como solución ni tratar una lista incompleta como el total empresarial.

### G15 · Media preventiva — Resumen recorta el sobrecumplimiento al 100 %

`app/src/screens/hoy/resumen-gerencia.tsx:84`, `:207`, `:218` limita el valor mostrado; Metas utiliza `pctMeta` y limita sólo el ancho de la barra (`app/src/screens/hoy/gerencia.tsx:729`, `:758`).

Un cumplimiento de150 % produciría100 % en Resumen y150 % en Metas. No se encontró ese caso numérico en la visita actual.

**Plan:** reutilizar el avance existente y limitar sólo la barra visual, no el número. No cambia las metas ni la conversión del servidor.

## Diferencias legítimas: no corregirlas forzando igualdad

- **231 base automática /243 llegadas comerciales:** ambos correctos con rótulos diferentes.
- **3,90 % comercial /2,5 % resultados del lote:** el primero incorpora cierres del período y cartera; el segundo es6 cierres de243 llegadas seguidas hasta hoy.
- **5 citas realizadas /25 flags de avance del lote:** no son la misma unidad ni el mismo reloj. Lo incorrecto es afirmar asistencia a partir del segundo.
- **Capital mensual /capital vigente /estimación de leads:** preguntas distintas. Cartera de contratos no equivale por sí sola al total que incluye cooperativas.
- **S/578.000 y US$14.000 /S/624.887,40 equivalentes:** la segunda lectura consolida con el TC rotulado3,3491. No es una suma directa de monedas ni una diferencia de capital real; falta uniformidad en los nombres breves y algunos pies.
- **17 personas del bloque comercial /20 responsables del operativo:** los universos de roster, roles e historial no son idénticos. La composición exacta del20 debe conciliarse antes de renombrarlo; no forzar que todas las tarjetas muestren17.
- **Llegada del primer analista /cierre del que lo consigue /dueño actual de cartera:** atribuciones distintas y deliberadas.
- **Agenda pendiente /historial de citas /inventario de Pipeline /episodios de descarte:** conservar cada finalidad. Repartir puede seguir contando entregas para trazabilidad operativa.
- **Ventana de45 días de convertidos** y **fotos mensuales selladas:** decisiones vigentes; no modificarlas para cuadrar otro reporte. La cohorte viva puede evolucionar sin reabrir un cierre mensual.

## Plan de desarrollo, con puertas de aprobación

### Etapa 0 · Contrato de lectura y línea base

Entregable: inventario por indicador con **pregunta comercial, fuente/campo, unidad, fecha, ámbito, atribución, exclusiones y estado de verificación**. Separar captación, base de conversión, índice comercial, resultado del lote, citas, inventario y capital.

Registrar definiciones/huellas de todos los núcleos protegidos, firmas, ACL y fuentes actuales. Ningún ajuste de fórmula, peso, fecha de negocio, snapshot o autorización entra por esta etapa. Elegir por cada tarjeta si se conserva su pregunta o se sustituye expresamente.

### Etapa 1 · Correcciones de interfaz y consumo existente

Prioridad: G01/G02/G04/G05/G06/G10/G11/G12. Retirar afirmaciones falsas, usar base automática/llegadas correctamente, unificar el período de Rendimiento y proteger errores/verificación. Completar estados de citas ya disponibles.

Después: G07/G08/G09/G13/G15, alcance de filtros y cobertura. Reutilizar adaptadores, funciones de formato, guardas y componentes existentes; **sin nuevos cálculos de negocio independientes**. Las correcciones de etiquetas no se presentarán como reparación de datos que aún falten.

Puerta de salida: cada número visible se puede rastrear a un campo servido con el mismo significado. No publicar esta etapa automáticamente por estar descrita aquí.

### Etapa 2 · Cartera: conectar las salidas canónicas y corregir el listado

Prioridad G03/G14. Comparar el contrato de `resumen_cartera_clientes_fn` y otras lecturas existentes con cada tarjeta antes de conectarlas, preservando las diferencias de saldo, período, alcance y atribución.

Corregir la exclusión de pruebas en la fachada **existente** del listado. No borrar datos ni duplicar `capital_episodios`. Si la fachada requiere SQL, mostrar primero el SQL exacto, impacto y reversión; esperar confirmación. Evitar `db push` global: hay migraciones pendientes de otros trabajos.

Puerta de salida: ningún contrato de prueba aporta al indicador real y los listados no contradicen el resumen por una diferencia de exclusiones. Las cifras no dependen del número de filas descargadas.

### Etapa 3 · Sólo para necesidades que no cubre el contrato actual

No se propone crear nuevos núcleos ni RPC/calculadoras independientes. Una eventual ampliación de **respuesta de una función existente** también requiere explicación y aprobación; no queda autorizada por este informe.

| Necesidad | Razón comercial | Razón técnica | Alternativa sin ampliación |
|---|---|---|---|
| N1: leads únicos de un lote que realmente tuvieron cita | Saber cuántas personas captadas avanzaron mediante una cita registrada | El embudo entrega flags inferidos; el reporte de citas entrega eventos de otro rango. Hace falta una proyección de los episodios existentes sobre el lote, respetando ámbito y fechas, no sumar los dos payloads | Mostrar avance inferido como tal o citas operativas con su nombre y período |
| N2: divisor exacto de realización por modalidad | Que «4 de N» concilie con el porcentaje | El agregador ya calcula exclusiones vencidas, pero no todas salen por modalidad en el payload | Mostrar porcentaje servido y explicación, sin fracción falsa |
| N3: aporte efectivo de cada operación de cartera | Explicar cuál renovación/upgrade cuenta ese mes | Elegible no significa ganadora de la deduplicación; `operacion_id` y `aporte_numerador` ya existen en episodios, no en esa salida del listado | «Operación registrada/elegible», sin prometer un aporte efectivo |
| N4: cierres por semana real de cierre | Medir productividad semanal, no maduración de captación | La serie usada agrupa por llegada; primero verificar si otra salida existente ya sirve la dimensión de cierre | «Resultados por semana de llegada · cerraron hasta hoy» |

Una proyección nueva o un campo adicional no debe cambiar semánticas existentes ni exponer los núcleos privados directamente al navegador. Debe conservar controles de rol, ámbito y contrato anterior. Si no puede hacerse dentro de estas restricciones, detener ese punto y pedir una decisión; no buscar un atajo con otra calculadora.

### Etapa 4 · Pruebas de conciliación y regresión

1. Mismo lead con varias reasignaciones: una llegada, sin duplicación; Ana conserva llegada y Luis recibe cierre.
2. Automáticos/manuales/referidos: total y divisor diferentes pero bien rotulados; renovación×peso, upgrade×1, misma deduplicación.
3. Propuesta/cierre sin cita: nunca presentado como asistencia confirmada.
4. Citas: canceladas por analista/sistema, reprogramadas, futuras y pendientes; estados completos y fracción coherente con porcentaje servido.
5. Rango parcial1–3 → Rendimiento mensual; navegación entre meses y desde alertas sin heredar fechas equivocadas.
6. Cierres tardíos: serie por llegada y foto mensual sellada siguen siendo lecturas distintas.
7. Demos y PEN/USD: conciliación de Cartera con/sin mes; ningún dato de prueba dentro de indicadores reales; TC y componentes declarados.
8. Operaciones múltiples en un cliente/mes: no prometer varios aportes ni reconstruir deduplicación en frontend.
9. Filtros de analista/estado/búsqueda: alcance uniforme o explícito; roster vigente/histórico y sin analista identificados.
10. Fallo, espera, `null`, `cuadra=false`, respuesta parcial y filas inválidas: no producir un cero o una falsa normalidad.
11. Más del límite de listado y paginación; métricas independientes del recorte de filas.
12. Meta150 %: número150 % en todas las vistas, barra visual limitada si corresponde.
13. Roles/acceso y huellas de los núcleos: intactos; pruebas de autenticación sin modificar usuarios productivos.

Usar pruebas de contrato y UI con datos anonimizados/fixtures; cualquier banco SQL de pruebas aislado. No ejecutar pruebas mutantes, semillas ni escrituras sobre producción.

### Etapa 5 · Publicación sólo después de autorización

Integrar cambios autorizados en Main sin sobrescribir trabajo ajeno; sincronizar con `avancecorp/main`; construir el artefacto desde el commit idéntico verificado, sin ramas de release ni force push. Publicación por etapas compatibles, control de acceso, lecturas cruzadas y reversión preparada.

Antes/después comprobar: mismos núcleos y permisos, mismo significado de porcentaje, sin datos de prueba, fechas visibles correctas, total/listado conciliado y ningún error convertido en cero. No aplicar migraciones pendientes ajenas al alcance.

## Registro técnico de solo lectura

Huellas actuales `md5(pg_get_functiondef(...))` comprobadas por la auditoría principal:

- `private.conversion_episodios`: `8a2549dbfa59c732da04900ed90b6361`.
- `private.citas_episodios`: `ea636888a266941e959f26c6a5727216`.
- `private.capital_episodios`: `b8f375fbb377582835f4cfe222240c5b`.
- `private.metricas_conversiones_implementacion`: `372a4cfaf71bbbfcc1c921ca48096125`.
- `private.metricas_reuniones_implementacion`: `7f4f885e2d044afdd2fd0766991517a0`.
- Distribución: core `f8748197c550484ae59b6257397a5013`, V2 `7408cb964af34dfb091108c5a7062cc4`, V3 `be2290576ef7f8947f3b4d3a9db846a7`.

La revisión de Cartera registró adicionalmente **`md5(prosrc)`**, que no es intercambiable con el hash anterior: `contratos_cartera_fn=5776edb84d509ee717931973cd1710ca`; V2 `0efcab11c1837d70d215174abf8d9d08`; `resumen_cartera_clientes_fn=541c486b442011cd4a4a367ea8a0dd7a`.

No se ejecutaron tests de escritura ni la suite completa durante este diagnóstico; no hay una corrección implementada que certificar todavía. Quedan como comprobaciones adicionales, sin afirmar incidencia actual: configuración remota del límite de filas, escenarios de clientes dados de baja, desglose exacto de población17/20 y capital de citas con un mismo lead vinculado a contratos en ambas monedas.
