---
tags: [crm, ranking, origenes, capital]
fecha: 2026-09-25
estado: SQL publicado por merge nativo; ensayo y auditoría PASS; frontend en publicación
---

# Ranking — capital por canal de llegada

Miguel pidió que «Ver detalle» de **Ranking · Capital total** muestre de dónde nace el capital confirmado, por origen y monto. Confirmó que **origen** significa el canal de llegada del cliente (`crm.leads.origen`), no la categoría Nuevo/Renovación/Upgrade. Confirmó también que **renovaciones y upgrades** deben quedar separados como **Cartera**, sin sumarse al canal de llegada original.

## Presentación acordada

- Conservar capital confirmado, meta y cumplimiento arriba; debajo, «Capital y conversión por origen» con una fila por canal y monto. Cada monto conserva PEN/USD y el mismo TC del ranking para el equivalente en soles.
- Agrupar renovaciones y upgrades en **Cartera**. Mantener un grupo explícito **Sin origen identificado** para contratos nuevos sin un lead atribuible de forma inequívoca. Si hay ajuste de cierre sin vínculo inequívoco al origen, mostrar **Ajustes de cierre** con signo.
- La suma de los grupos, por moneda y después del ajuste, debe coincidir con el capital confirmado de la ficha. Si no se puede conciliar, mostrar «Desglose no disponible» en vez de importes que parezcan completos.
- Eliminar el botón «Volver a Ranking»; cerrar la ficha con un botón «Cerrar detalle» en la cabecera. El cambio visual está hecho localmente, pendiente de publicación.

## Conversión en la misma ficha (ampliación del 25/09)

Miguel pidió ver también la conversión por **Landing, Formulario, Referido y Wallking** junto al capital de cada origen. Cartera queda solo como capital de renovaciones y upgrades, sin presentarse como una tasa de leads. La base de la tasa viaja en el contrato de datos (cierres y leads) y Referido conserva el peso vigente del período, siguiendo [[Conversion - tabla por origen al peso de la general (2026-09-23)]]. En la UI se muestra solo el porcentaje; si no hay divisor, una raya.

La ficha local en modo demo muestra un ejemplo ficticio de esta disposición. La implementación local incorpora `crm.ranking_origen_vendedor_fn` para atribuir el capital y la conversión por vendedor, origen y mes; sigue sin instalarse en producción. `crm.metricas_conversiones_fn` entrega orígenes globales y responsables agregados, por lo que no se reutiliza para la ficha. Wallking cuenta cierres propios del canal con peso 1; Referido conserva el peso del período. El divisor son los leads del canal recibidos por primera vez por ese analista en el mes. Esta tasa mensual puede diferir del índice general del ranking, que agrega otros aportes y bases.

Miguel pidió quitar el texto explicativo de la ficha: la vista muestra etiquetas, montos y porcentajes sin párrafos de fórmula. El ejemplo conserva una marca breve de «Ejemplo ficticio» para distinguirlo de datos reales.

## Fuente y límites

El capital del ranking sale de `crm.cumplimiento_metas_fn` → `private.produccion_mes_por_vendedor` y de la foto del mes cerrado. Esa salida ya viene agrupada por analista, categoría y moneda: **no contiene canal**. La lectura existente `origenes[].capital_pen/usd` de Conversiones sigue un lote de leads y puede repetir capital cuando un perfil se asocia a más de un lead; no equivale al capital mensual del ranking. Véase [[Inventario de indicadores de Gerencia - Comercial]], C25 y C49–C50.

Para obtener los canales, el servidor debe conservar el grano de cada cierre confirmado y su atribución vigente antes de sumar por origen. La agregación actual y el desglose deben beber de esas mismas filas, sin una segunda fórmula de capital. Un contrato/cierre aporta una sola vez al analista acreditado; un cliente con varios leads de canales distintos queda sin origen identificado hasta que exista una relación inequívoca. Los cierres de cooperativas usan su `lead_id` cuando existe. El acceso conserva el alcance de `cumplimiento_metas_fn` para Gerencia y Supervisión.

Las fotos nuevas de mes cerrado deberán congelar también el desglose dentro de la misma transacción. Para fotos antiguas sin ese dato, no se reconstruye una cifra aparente desde leads actuales: sólo se habilita un backfill si concilia con la foto original; si no, la ficha indica que el desglose histórico no está disponible.

## Implementación local y siguiente puerta

SQL exacto preparado en `CRM-Avance-Corp/supabase/migrations/20260925190000_crm_ranking_origen_vendedor.sql`. La ficha React consulta esa RPC al abrir un analista real, valida su contrato y oculta el desglose si no concilia por PEN y USD. Las fotos futuras guardan el desglose mediante trigger `BEFORE INSERT`; si el cálculo auxiliar falla, la foto queda marcada no disponible y el sello financiero continúa. Las fotos antiguas permanecen sin dato. El banco local ejecutó migración y pruebas dentro de una transacción con `ROLLBACK`: paridad de grupos, dos leads con origen ambiguo sin duplicar un contrato, cierre cooperativo, Referido ponderado y peso ausente, ajustes, rechazo de desajustes, ACL y ámbito de Gerencia/Supervisión, foto de cierre, fallo auxiliar aislado y rechazo de UPDATE. La revisión independiente pidió aislar excepciones del sello y alinear cierres con numerador; ambos cambios están incorporados y probados. Falta aplicar la migración en una rama autorizada de Supabase, cotejar con datos reales y mostrar el SQL exacto a Miguel antes de cualquier aplicación productiva.

Actualización 25/09: Miguel aprobó el SQL exacto (SHA-256 `0e883ef84e778699a60223392dc62e2442f9a9f93e36a257159a890d67fc95ec`). Una consulta de solo lectura en producción concilió el detalle propuesto con el capital canónico en 32 grupos analista/moneda de septiembre y 29 de agosto, sin diferencias; los cuatro canales tuvieron leads y cierres en septiembre. Falta ensayar la migración en una rama propia de Supabase antes de instalarla; el conector exige confirmar la organización y el costo de la rama.

El ensayo remoto del 25/09 creó una rama exclusiva con costo autorizado. El replay falló tras 86 de 358 migraciones en `20260812000259_crm_cierres_externos`, cuyo postflight requiere un vendedor en `crm.equipo`; Supabase crea ramas sin datos de producción. La rama fue eliminada y producción sigue sin cambios. Para publicar el SQL hace falta resolver ese replay histórico o autorizar expresamente una excepción al ciclo de rama y merge.

Miguel eligió **esperar la reparación de ramas**. No hay autorización para aplicar directamente en producción. Se verificó que la RPC, la columna `origenes_ranking` y la migración siguen ausentes de producción, y que la rama de prueba ya no figura en Supabase.

A pedido de Miguel se abrió una segunda rama exclusiva. El estado `FUNCTIONS_DEPLOYED` fue transitorio: volvió a terminar `MIGRATIONS_FAILED` con solo 86/358 migraciones y sin funciones canónicas. También se eliminó esta rama; la RPC y columna siguen ausentes de producción. No tiene sentido reintentar sin reparar el postflight histórico de `20260812000259` o el mecanismo de seed previo al replay.

## Ensayo reparado y SQL publicado — 26/09/2026

El bloqueo histórico quedó resuelto reconstruyendo el esquema en una rama
exclusiva sin copiar datos personales. Se verificaron las 368 migraciones
existentes, 792 funciones con sus ACL y la paridad estructural; solo tres CHECKs
tienen paréntesis aplanados por pg_dump sin cambiar sus predicados. Se aplicó
el SQL aprobado sin cambios y se publicó por **merge nativo**, registro remoto
`20260926211038`. Las 21 Edge conservaron código y verify_jwt. Postflight:
funciones idénticas a las ensayadas, RPC sin acceso anon, 17/17 analistas de
agosto y 19/19 de septiembre conciliados por moneda.

Auditoría Claude final: PASS. Se corrigió la propagación de mes y actor desde
Gerencia/Equipo, que faltaba en el cambio aislado, y el aviso de ajustes cuando
no hay desglose histórico. `npm run check`: 4454 tests PASS. Docker: 276 PASS,
26 omitidos; smoke final de Ranking: 1 PASS. Matriz RLS focalizada con Auth y
PostgREST reales PASS; no se volvió a ejecutar la suite general de conversiones.
Ensayo con deuda real, cierre real, decimales, peso referido sellado, foto
inmutable y foto antigua sin reconstruir PASS. Carga: 272 contratos mensuales,
2048 leads, 34 vendedores, 7,29 s y ninguna foto degradada.

La conversión por canal usa los leads **creados en ese mes** y su primer
analista histórico; no cuenta de nuevo un lead por una reasignación posterior.
El capital vivo conserva el tratamiento del payload canónico y el cierre
descuenta la deuda al sellarse. No se cambió la fórmula ni se introdujo tolerancia
monetaria: la prueba con céntimos concilia exactamente.

Frontend pendiente únicamente de empaquetado, publicación y smoke HTTP.
Los scripts reproducibles están en `supabase/scripts/ranking-origen/` y el
detalle del ensayo en `supabase/migrations/MIGRACIONES.md`.

Relacionado con [[Ranking de capital total unificado (TC BCRP)]], [[Rankings por mes calendario (decision 2026-09-02)]], [[Canales de origen de leads CRM]] y [[Produccion fuera del ranking (decision 2026-09-02)]].
