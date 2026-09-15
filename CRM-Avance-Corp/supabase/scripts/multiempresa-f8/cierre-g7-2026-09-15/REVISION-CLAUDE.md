VERDICT:
CHANGES_REQUESTED

SUMMARY:
Las tres consultas son de solo lectura en efecto y, en lo esencial, correctas: la multiplicidad está bien tratada con `EXCEPT ALL`, los importes se comparan como NUMERIC, la muestra queda fijada por huellas y las fuentes se comprueban antes y después. La propuesta de conservar G7 **ABIERTO** con sub-resultados parciales es honesta y la apoyo. No encuentro P0. Hay que corregir, antes de guardar el acta, varias interpretaciones que sobrevaloran la evidencia:

- **Paridad casi tautológica:** la "paridad F5/F7" deriva en gran parte de las mismas columnas.
- **Atribución, no autoría:** "altas por analistas no piloto" mide la atribución comercial, no quién registró la fuente.
- **Anclaje frágil:** el ancla del piloto se lee de la fila viva del control.
- **Sin cobertura del desglose:** no se concilia el desglose de upgrades.
- **Fuera de alcance:** falta evidencia del estado global que se quiere abrir a los 18 analistas.

La evidencia es suficiente para revisar este alcance; no lo es para cerrar G7 ni para autorizar la apertura global.

FINDINGS:

[P1] La evidencia no cubre el estado que se quiere abrir (flags globales ON) ni el orden de olas del maestro
File: roles.json, verificar-roles.sql; maestro F9
Lines: bloque `banderas` de conciliacion.json; sección "Olas tras aprobar G7"
Problem: Todas las capacidades se midieron con `ficha_360_neutral`, `postventa_neutral` e `inversiones_escritura` en OFF. Solo prueban el aislamiento del piloto; no dicen nada sobre el comportamiento con flags globales.
Evidence:
- Con flags globales ON, `cartera_inversionistas_estado_fn` devuelve `habilitada` para todo rol vendedor/supervisor/gerencia o lector global (`v_f5 or v_piloto`).
- El coordinador recibe `42501` en F5, pero en F6 recibe `{"habilitada":false}` sin error. No se adjunta `crm.postventa_estado_fn`, así que no puedo saber si con `postventa_neutral` ON el coordinador quedaría habilitado.
- `trg_multiempresa_flags_bloquear_piloto_f8` impide encender los flags globales mientras F8 esté activo. La apertura exige apagar F8 primero, lo que deja una ventana en la que los 4 pilotos pierden escritura.
- El maestro exige G7 firmado y luego las olas 1→2→3. "Los 18 analistas" corresponde a la ola 3.
Impact: Presentar la apertura a los 18 como algo cercano mezcla gates. La matriz de roles actual no valida el estado destino.
Recommendation:
- En el procedimiento de activación, declarar que la apertura a los 18 es la ola 3 y queda bloqueada por G7.
- Incluir una matriz de roles para cada ola en rama o entorno aislado con flags globales ON, cubriendo el coordinador en F6.
- Adjuntar la definición de `postventa_estado_fn`.
- Documentar la secuencia F8 OFF → flag global ON y su ventana.

[P2] La paridad Capital/F5/F7 es en gran parte estructural, no una conciliación independiente
File: conciliar.sql; definiciones vivas de `private.metricas_f7_fuentes`, `private.cartera_f5_fuentes` y `private.capital_episodios`
Lines: CTE `capital`, `diferencias_cartera`, `diferencias_metricas`
Problem: `metricas_f7_fuentes` toma `moneda`, `monto`, `analista_id`, `fecha` y `tipo` directamente de `capital_episodios`. Comparar F7 con Capital solo detecta fan-out del join y el filtro demo. La comparación F5 con Capital usa las mismas columnas fuente con la misma expresión:
- `c.capital` / `ce.monto`;
- `coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)`;
- `fecha_cierre_comercial` convertida a Lima y de vuelta a fecha.
Evidence: Definiciones SQL adjuntas; `identidades_metricas_distintas` compara `metricas.inversionista_id` con un valor que la propia `metricas` obtiene de `cartera_f5_fuentes`.
Impact: "0 diferencias" demuestra que los lectores internos no divergen. No demuestra "cero diferencias financieras": un error en `analista_atribuido_cadena` o en un importe cargado se propagaría por igual a los tres núcleos.
Recommendation: Rotular este resultado en el acta como "coherencia interna de lectores (derivación compartida)". La fila "Cero diferencias financieras" debe seguir PARCIAL hasta contrastar con una fuente externa o con los documentos firmados por el responsable financiero.

[P2] El desglose de upgrades (renovado/adicional) queda fuera de toda la conciliación
File: conciliar.sql
Lines: `where e.medida='stock'` en `capital`; mismo filtro en `metricas_f7_fuentes`
Problem: `capital_episodios` emite filas `medida='desglose'` para `crm.operaciones_cartera`, pero ningún chequeo las compara.
Evidence: Hay 89 upgrades y 1 `upgrades_atribuidos_a_otro`. La rama `desglose_*` usa `o.vendedor_id` como respaldo y las fechas `o.fecha_operacion` / `o.periodo`, distintas de las del stock.
Impact: El caso "upgrade reasignado" y la atribución de capital renovado/adicional no están conciliados. Tampoco se ha verificado el único candidato real.
Recommendation:
- Añadir una comprobación de solo lectura del desglose frente a `operaciones_cartera`: suma renovado + adicional por contrato nuevo, analista y periodo.
- Inspeccionar el caso atribuido a otro analista.
- Mientras tanto, dejar "Upgrade reasignado" en PENDIENTE (candidato identificado), no en PASS.

[P2] "Registrada por analistas no piloto" y "fuente de actores piloto" miden atribución, no autoría ni uso de F8
File: conciliar.sql
Lines: CTE `nuevas` (`m.perfil_id=f.analista_origen_id`); `altas_desde_inicio`
Problem: En Avance, `analista_origen_id` es `coalesce(analista_atribuido_cadena, analista_cierre_id)`, es decir, el analista comercial atribuido. No es `creado_por` ni el actor de la solicitud F4. `solicitudes_nuevas` tampoco filtra por actor.
Evidence: Definición de `cartera_f5_fuentes`; `capital_episodios` expone `registrado_por` (`c.creado_por`, `ce.creado_por`), pero no se usa.
Impact: Las frases "10 Avance registradas por no piloto" y "solo 1 de actores piloto" no están demostradas tal como se redactan. Un piloto podría haber registrado una fuente atribuida a otro, y al revés.
Recommendation: Usar `creado_por` y el actor de `crm.inversion_solicitudes` para "quién escribió y por qué ruta (legado o F8)". Si no se corrige, redactar el acta como "atribuidas a".

[P2] El ancla "desde inicio" depende de la fila viva del control y se pierde si el piloto se reinicia
File: conciliar.sql
Lines: `control`, `nuevas`, `solicitudes_nuevas`, `desde_inicio` en `fuentes_hash`
Problem: Usa `crm.piloto_f8_control.inicia_en` actual. `trg_piloto_f8_control_validar` solo permite acortar la ventana activa; para ampliarla hay que apagar y volver a encender, con un `inicia_en` nuevo.
Evidence: `if old.activo and (new.inicia_en is distinct from old.inicia_en or new.vence_en > old.vence_en) then raise ... 'apaga para ampliarla'`. La ventana vence el 21/09 y hoy hay 1 alta F8.
Impact: Si se amplía el piloto, que es probable, reejecutar la consulta excluiría sin avisar la inversión Qorilazo del 14/09 y cualquier otra del primer tramo. El recuento acumulado de G7 bajaría o quedaría mal.
Recommendation: Fijar como constante el instante de activación del acta ACTIVACION-2026-09-14 (`2026-09-14T18:23:51.712435Z`) o leerlo del historial de revisiones. Reportar además el `inicia_en` vivo para detectar la divergencia.

[P2] Lectura productiva de fichas suplantando a una persona de Gerencia, con la auditoría de acceso revertida
File: verificar-fichas.sql
Lines: cabecera ("ROLLBACK deshace esa auditoría"), `set_config('request.jwt.claims', ...)`
Problem: Un operador con privilegios leyó 19 fichas reales con la identidad nominal de Gerencia y eliminó el registro de esas lecturas.
Evidence: Comentario y `rollback;` del script; `metodo` en fichas.json.
Impact: No se filtran datos personales (la salida son huellas y recuentos). Aun así, el rastro de acceso que la RPC está diseñada para dejar desaparece y la acción queda atribuible a Gerencia. Es un riesgo de gobierno y seguridad.
Recommendation: Registrar en el acta, fuera de la base de datos auditada:
- operador;
- conexión o rol usado;
- fecha;
- propósito;
- las 19 huellas;
- aclaración de que la persona de Gerencia no participó.

No reutilizar el patrón sin esa nota.

[P3] La huella del mes sellado es una captura única y su orden puede no ser determinista
File: conciliar.sql
Lines: `fotos_selladas` (`order by f.vendedor_id`)
Problem: Una sola huella no prueba "sin reescritura" si no hay línea base anterior (del momento del sellado) ni captura posterior a escrituras del piloto. Además, si `cierre_mes_vendedor` tiene más de una fila por vendedor en un periodo (por ejemplo, por moneda), `jsonb_agg` ordenado solo por `vendedor_id` puede cambiar de orden y dar un falso positivo. Esto es una hipótesis: no tengo el esquema.
Evidence: 16 filas en 2026-08-01; no se adjunta línea base.
Recommendation: Ordenar por la clave primaria completa. Dejar "Mes sellado" en PENDIENTE hasta comparar con una línea base o con una captura posterior a escrituras F8.

[P3] Fijación incompleta de versiones y detalles del harness
File: conciliar.sql, verificar-fichas.sql, verificar-roles.sql
Problem:
- Las huellas de `funciones` no incluyen dependencias críticas: `analista_atribuido_cadena`, `piloto_f8_actor_activo`, `postventa_estado_fn`, `rol_crm`, `es_lector_global`, `puede_gestionar_contratos_crm`, `inversiones_escritura_bajo_candado`.
- `verificar-roles.sql` y `verificar-fichas.sql` no guardan huellas.
- En `verificar-fichas.sql`, `ficha` no se reinicia por persona: si falla la primera llamada, `ficha_hash` registraría la ficha anterior. Hoy no ocurrió porque todos los `error` son null.
- El bucle usa `ceil(v_count/25.0)` y un tercer argumento `1` sin la definición de `inversionista_ficha_fn` adjunta. El máximo de la muestra es 4 inversiones, así que la paginación nunca pasó de una página.
Recommendation:
- Ampliar la lista de huellas y capturarlas en los tres scripts.
- Reiniciar `ficha:=null`.
- Adjuntar la firma o semántica de `inversionista_ficha_fn`.

[P3] `anulaciones_coopac` y los recorridos solo cuentan parte de los casos
File: conciliar.sql
Lines: `casos_existentes`, `secuencia`
Problem:
- Solo cuenta anulaciones de cooperativas (`anulado_comercialmente`); si el maestro incluye anulaciones de Avance, no aparecen.
- La transición avance→avance (145) incluye upgrades y renovaciones: no equivale directamente a "segunda inversión en la misma empresa".
- En el legado, `creado_en` puede reflejar la fecha de carga y no el orden real (hipótesis).
Recommendation: Excluir operaciones de upgrade al contar "segunda inversión" o separarlas, y confirmar el alcance de "anulación" con el maestro.

TEST GAPS:
- Matriz de roles con flags globales ON por ola, incluidos el coordinador en F6 y el usuario `directorio` sin fila en `crm.equipo`. La enumeración actual hace join con `crm.equipo` y omite ese camino de `es_lector_global`, así que "sin fugas a no piloto" solo cubre miembros del equipo.
- Denegación para cuentas inactivas (`e.activo=false` o `p.activo=false`); el script las filtra y nunca las prueba.
- Paginación de ficha con más de 25 inversiones; nunca se ejecutó.
- Lectura de solo lectura de las 2 personas sin responsable y del upgrade atribuido a otro. Los datos existen, pero la verificación no se hizo.
- Identidad provisional, cotitularidad, retiro y anulación: 0 casos reales. Requieren operación real o un ajuste aprobado por Miguel.
- 10 reintentos idempotentes y 5 carreras "en el entorno aislado": el maestro sí admite entorno aislado. Las pruebas F4 previas (seis carreras económicas, depósitos duplicados, idempotencia) podrían contar, pero faltan tres datos:
  - el recuento exacto de reintentos (¿≥10?);
  - la versión del código probada;
  - si siguen valiendo tras los parches COOPAC y de rendimiento posteriores.

ARCHITECTURE RISKS:
- `habilitada = v_cobertura` es un interruptor global que falla en cerrado. Con 18 usuarios en modo global, una sola fuente nueva sin identidad coherente (por ejemplo, un contrato del flujo legado) deshabilita la cartera para todos. Hoy hay 0 huecos, pero entraron 10 fuentes legado desde el inicio. El procedimiento de activación necesita monitorizar este indicador y un runbook.
- `cartera_inversionistas_estado_fn` recalcula la unión completa de fuentes en cada llamada. No hay medición de su latencia con concurrencia; la optimización medida (0.72s) es de la ficha (hipótesis de carga).

SECURITY RISKS:
- Suplantación nominal y reversión de la auditoría (P2 arriba).
- Las huellas `md5('G7-20260915:'||uuid)` son seudónimos con sal pública: cualquiera con acceso de lectura a la base de datos puede reidentificarlas. Esto es aceptable para Git, pero no debe describirse como anonimización.

REGRESSION RISKS:
- Reiniciar el piloto para ampliarlo altera los recuentos "desde inicio" (P2).
- Apagar F8 para encender flags globales corta la escritura de los pilotos durante la transición.

INTERPRETACIÓN (consejo, no autoridad de negocio):
- **"15 identidades verificadas, ≥5 por empresa":** puede marcarse **PASS técnico retrospectivo**. Hay 19 personas (10/5/5) con identificador vigente verificado en la base de datos y fichas coherentes. Añadir la nota "verificación documental física no evaluada; requiere conformidad del responsable".
- **"20 inversiones confirmadas y consecutivamente conciliadas":**
  - "confirmadas" apunta al flujo de confirmación;
  - "consecutivamente" apunta a una conciliación continua y ordenada durante el piloto, no a una lectura única.
  - En la muestra, Prodelco solo tiene 3 fuentes con relación F4 y la mayoría es legado.
  - Recomiendo: **PARCIAL — lectura retrospectiva PASS (20 fuentes y 25 inversiones sin diferencias); confirmadas por F8: 1/20; al menos 5 por empresa por F8: 0/0/1**.
  - Que Miguel decida si la lectura retrospectiva basta; no presentarla como cumplida.
- **Recorridos:** PARCIAL. Avance→Qorilazo, Qorilazo→Avance y Qorilazo→Prodelco **no existen en los datos reales**; solo hay 1 persona multiempresa. Con 4 actores y la ventana hasta el 21/09 no parece alcanzable. Conviene anticiparlo a Miguel ahora, junto con el P2 del ancla temporal.
- **Multirrol:** PASS SQL (24 cuentas, estado piloto con flags OFF). Login JWT/HTTP y recorrido humano NOT RUN.
- **Sin responsable, upgrade reasignado y mes sellado:** PENDIENTE, con candidatos o línea base identificados.
- **Soporte y reversa en producción, y todas las firmas:** PENDIENTE.
- **Incidencias del harness** (`codigo`→`clave`, error 25006 por READ ONLY): de acuerdo, no son fallos de producto. Conviene dejarlas registradas.

RECOMMENDED NEXT ACTIONS:
1. Corregir la redacción del acta: "coherencia interna de lectores", "atribuidas a" y la anotación de suplantación y auditoría revertida. Mantener G7 ABIERTO con los estados de la interpretación.
2. Anclar "desde inicio" al instante de activación del acta y añadir `creado_por` y el actor de la solicitud para distinguir escrituras legado de F8.
3. Añadir la conciliación de solo lectura del desglose de upgrades y leer los 2 casos sin responsable y el upgrade atribuido a otro.
4. Mapear las pruebas F4 aisladas previas a "10 reintentos / 5 carreras" con recuento y versión; si no alcanzan o quedaron obsoletas, reejecutarlas en rama.
5. En el procedimiento de activación:
   - separar las olas F9;
   - añadir la matriz de roles con flags globales ON (adjuntar `postventa_estado_fn`);
   - monitorizar el interruptor de cobertura;
   - describir la transición F8 OFF → global ON.
6. Llevar a Miguel la decisión explícita sobre los recorridos inexistentes y los casos raros: operación real, ampliación del piloto o ajuste aprobado. No resolverlo por cuenta propia.

CONFIDENCE:
MEDIUM. El SQL adjunto y las definiciones vivas sostienen bien los hallazgos. Faltan las definiciones de `postventa_estado_fn`, `inversionista_ficha_fn` y `analista_atribuido_cadena`, el esquema de `cierre_mes_vendedor` y el detalle de las pruebas F4 previas.
