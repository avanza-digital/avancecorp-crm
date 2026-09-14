VERDICT:
CHANGES_REQUESTED

SUMMARY:
Las conclusiones financieras del caso se sostienen con la evidencia adjunta: identidad, fuentes, solicitud, depósito, conversión, facturación y firmas. No hay indicio de duplicación en este caso. El timeout de ficha para supervisor y gerencia es un defecto de rendimiento del producto, no del arnés. Es reproducible y relevante en producción, porque el rol `authenticated` tiene un límite de 8s y el ensayo superó 20s. Falla cerrado, así que no es fuga de datos. No hay P0. Pido ajustes en cómo se documenta y comunica, y cerrar dos huecos antes de hablar con el solicitante: listado de supervisor/gerencia y la coherencia temporal de la fecha comercial.

FINDINGS:

[P1] Ficha F5 inutilizable para supervisor y gerencia bajo el timeout productivo
File: función `private.cartera_f5_personas_visibles` (cuerpo activo adjunto), llamada desde `crm.inversionista_ficha_fn` (migración `20260910150039_crm_f6_postventa_persona.sql:1065`)
Lines: personas_visibles 11-12, 37, 41, 44-46, 62-70; ficha línea 12
Problem: la ficha de supervisor y gerencia excede 20s. En PostgREST el límite es 8s, así que en la UI fallará siempre con 57014.
Evidence:
- `matriz_f5.supervisor_ficha` tardó 22239 ms y `gerencia_ficha_aislada` 21179 ms, ambos con 57014.
- El CONTEXT sitúa el fallo en `cartera_f5_personas_visibles` → `inversionista_canonica`, desde el `select * ... where inversionista_id=v_id` de la ficha.
- Config documentada: `authenticated`/`authenticator` con 8s.
Hipótesis de causa, confianza MEDIA, basada en el cuerpo y sin EXPLAIN:
- (a) La función es SQL `SECURITY DEFINER` con `SET search_path`, así que Postgres no la inlinea. El filtro `inversionista_id=v_id` se aplica después de materializar la cartera completa del actor.
- (b) `cartera_f5_fuentes()` se evalúa dos veces: vía `fuentes_reales` (línea 11) y en `demos` (línea 12). Cada fila llama a `inversionista_canonica`, y los contratos además a `analista_atribuido_cadena`.
- (c) Predicados no indexables del tipo `private.inversionista_canonica(x.id)=i.id`, correlacionados por persona (líneas 37, 41, 46, 64, 67, 69). Con gerencia, `autorizadas` es casi toda la base (491 personas). Eso da del orden de personas × (inversionistas + 1690 leads) CTEs recursivos, cientos de miles de llamadas.
- El analista es rápido porque `responsable_relacion_id=any(a.visibles)` recorta `autorizadas` antes de los laterales.
Impact:
- Supervisor y gerencia no pueden abrir fichas F5 en la aplicación. G7 no puede atribuir permisos F5 a esos roles.
- El coste crece con la base, por lo que analistas también se acercarán al límite (ver P2 de margen).
Recommendation:
- Registrar G7-R01 como defecto de producto P1 abierto y no presentarlo como limitación del ensayo.
- No hacer remediación en esta revisión. Para la futura:
  - filtrar temprano con un parámetro `p_inversionista_id`;
  - calcular una sola vez un mapa `id → canónica` y unir por igualdad;
  - derivar `demos` de la misma materialización de fuentes.

[P2] Hueco de cobertura: listado de supervisor y gerencia no ensayado
File: `app/src/data/inversionistas-api.ts` (`cartera_inversionistas_fn`); matriz del recibo
Lines: n/a
Problem: la matriz solo prueba `analista_lista`. Si el listado usa la misma `personas_visibles`, lo que el cuerpo sugiere, gerencia y supervisor probablemente tampoco puedan ver la cartera.
Evidence:
- `matriz_f5` contiene solo `analista_lista`.
- La ficha de esos roles falla en la misma función base.
Impact: comunicar "listado PASS" sin calificar el rol induciría a pensar que la cartera F5 funciona para todos los roles.
Recommendation: ejecutar `cartera_inversionistas_fn` como supervisor y gerencia con el mismo método ROLLBACK, o documentar explícitamente NOT RUN y el riesgo inferido.

[P2] Fecha comercial del adicional anterior a la conversión inicial
File: `app/src/components/app/inversion-nueva.tsx:284,300,308`; recibo `caso.fuentes`
Lines: n/a
Problem: la fuente Qorilazo tiene `inicial=false` con fecha comercial/imputación 11-Sep. La conversión inicial Prodelco es del 14-Sep. Un adicional queda fechado tres días antes del primer cierre de la persona.
Evidence:
- `fuentes[1].fecha_comercial = 2026-09-11`, `inicial=false`.
- `fuentes[0].fecha_comercial = 2026-09-14`, `inicial=true`.
- `conversion.fecha_lima = 2026-09-14`.
- `facturacion_diaria` 11-Sep muestra 1 operación de 4500 para este analista.
- El formulario permite editar la fecha libremente (líneas 300 y 308).
Impact:
- Los reportes del 11 al 13-Sep muestran capital de una persona aún no convertida.
- El reporte diario del 11-Sep cambió retroactivamente el 14-Sep.
- No es un error de cálculo: `capital_episodios`, líneas 108-115, respeta `fecha_imputacion`. Puede ser un error de captura o una validación faltante (adicional con fecha anterior al inicial).
Recommendation:
- Incluirlo como observación al solicitante y preguntar si el 11-Sep fue intencional. No presentarlo como bug confirmado.
- Registrar como test gap que no se sabe si existe límite de retroactividad ni validación contra la fecha del cierre inicial.

[P2] Margen de tiempo del analista estrecho y medición no aislada
File: recibo `lectores`; `app/src/data/inversionistas-queries.ts:18-23`
Problem:
- La ficha del analista pasó en 5653 ms contra un límite de 8s (71%).
- La negación para otra analista tardó 6407 ms (80%).
- `duration_ms` es tiempo de pared del arnés, con viaje HTTP a la API de administración, no tiempo de ejecución en BD. Hay una sola muestra por lector.
Evidence:
- `analista_ficha_8s.duration_ms=5653`, `otra_analista_ficha.duration_ms=6407`.
- Polling cada 15s con `retry:false`: un timeout ocasional deja la vista en error hasta el siguiente ciclo.
Impact: "PASS con 8s" no es robusto. Con variación de caché o carga concurrente del polling puede fallar de forma intermitente.
Recommendation: documentarlo como "PASS, margen ~30%, muestra única, tiempo de pared". Si se repite, medir con `clock_timestamp()` dentro de la transacción y tomar al menos 3 muestras.

[P3] Firmas de consistencia no cubren todas las superficies escritas por el flujo
File: recibo `consistencia`
Problem: las cinco firmas (persona, lead, cierres, inversiones, solicitudes) no incluyen reclamos de depósito, eventos/auditoría de solicitud, `storage.objects` del comprobante ni tablas de auditoría que escriben los lectores.
Evidence: `firmas_antes` y `firmas_despues` solo tienen esas 5 claves. El método dice que los lectores con auditoría corrieron en ROLLBACK.
Impact: bajo. ROLLBACK cubre la auditoría, y los conteos puntuales (`reclamaciones: 1`, `eventos_registro: 1`) cubren parcialmente. La afirmación "sin cambios" debe limitarse a esas cinco superficies, como ya dice `cinco_superficies_sin_cambios`.
Recommendation: mantener la redacción acotada. Opcionalmente añadir un conteo antes/después de reclamos y eventos del caso.

[P3] `capital_activo: null` en totales de fuentes vigentes
File: recibo `analista_ficha_8s.totales`, `analista_lista.totales`
Problem: ambas fuentes están `vigente` pero `capital_activo` es null y solo se informa `capital_registrado`.
Evidence: el JSON muestra `capital_activo: null` para prodelco y qorilazo.
Impact: probablemente sea por contrato, porque el capital activo aplicaría solo a contratos Avance y las cooperativas son externas. Pero la frase "cartera/ficha coinciden" no lo aclara.
Recommendation: citar el contrato del campo en la documentación o marcarlo como "no evaluado". No afirmarlo como bug.

TEST GAPS:
- Listado F5 para supervisor y gerencia (ver P2).
- EXPLAIN (ANALYZE, BUFFERS) del cuerpo expandido. Un EXPLAIN de la llamada a la función solo muestra el nodo Function Scan; hace falta `auto_explain.log_nested_statements` o ejecutar las CTEs por separado (`fuentes`, `demos`, `con_historia`, conteo de `autorizadas`) con un `statement_timeout` local elevado dentro de ROLLBACK.
- Camino real Auth/HTTP con el límite de 8s (NOT RUN; confirmaría el P1 desde la UI).
- Validación o límite de retroactividad de `fecha_comercial` frente al cierre inicial.
- Reintentos y concurrencia de confirmación (los 10 de G7): no cubiertos, como ya declara el recibo.
- Descarga autenticada y contenido del comprobante: NOT RUN.

ARCHITECTURE RISKS:
- Lectores de ámbito construidos como funciones SQL `SECURITY DEFINER` no inlineables: cualquier consulta puntual paga el coste de la cartera completa del actor. El patrón escala con el tamaño de la base y con la amplitud del rol, de modo que los roles más amplios son los más lentos.
- La resolución canónica por función recursiva dentro de predicados correlacionados impide usar índices.

SECURITY RISKS:
- Ninguno observado. Los fallos cierran: supervisor y gerencia reciben error, no datos ajenos. `otra_analista` recibe ficha NULL y postventa 42501, que es lo esperado.
- Un eventual arreglo de rendimiento que filtre temprano debe preservar exactamente las ramas de autorización de `autorizadas` (líneas 30-46) y requerirá revisión RLS/ámbito.

REGRESSION RISKS:
- Si se comunica "listado y ficha PASS" sin calificar el rol, gerencia y supervisor del piloto F8 podrían reportar fallos como regresión.
- El crecimiento de personas y leads durante el piloto puede llevar a analistas por encima de 8s.

RECOMMENDED NEXT ACTIONS:
1. Reclasificar G7-R01 como defecto de producto P1 abierto (rendimiento de ficha F5 para supervisor y gerencia con límite productivo de 8s). Mantener la causa como hipótesis hasta tener un plan expandido.
2. Antes de comunicar, ejecutar o declarar NOT RUN el listado de supervisor y gerencia. Calificar por rol cada PASS del recibo.
3. Incluir en las observaciones al solicitante la fecha 11-Sep del adicional, anterior al inicial del 14-Sep, como pregunta y no como error.
4. Anotar el margen del analista (5.6 y 6.4 de 8s, muestra única, tiempo de pared) y acotar la afirmación de no-cambios a las cinco superficies firmadas.
5. En una tarea separada de remediación (LEVEL 3, con migración y revisión de ámbito): perfilar con plan expandido y evaluar filtro temprano por persona, un mapa canónico único y una sola evaluación de `cartera_f5_fuentes`.

CONFIDENCE:
MEDIUM. Es alta para las conclusiones financieras, de no-duplicación y de clasificación del timeout como defecto real. Es media para la hipótesis de causa raíz y para el comportamiento del listado de gerencia y supervisor, que no fueron medidos.
