# Revisión independiente — F4 / handler `crm-contrato-pdf-v2`

**Rol:** revisor secundario. No modifiqué archivos ni ejecuté nada. Todo lo que sigue sale de la evidencia incluida en el prompt; donde no alcanza, lo digo explícitamente.

---

## 1. Veredicto sobre el cambio del handler

El cambio **sí conserva integridad e inmutabilidad**. Concretamente:

- Nunca se sobrescribe: no hay `upsert`, y la nueva rama solo permite subir cuando la ausencia está *probada* (`404` o `NoSuchKey`, `handler.ts:1011-1014`). Cualquier otro error de descarga marca `STORAGE_DESCARGA` y libera el lease (1015-1027), en vez de presumir ausencia.
- El objeto recuperado se valida contra el render determinista (`fpObjeto` vs `render.sha256/bytes`, 1064-1068) **antes** de `marcar_subido`, y el ledger final se contrasta contra `fpObjeto` (1138-1149). El `firmar(final.estado, true)` de 1150 es sano: `yaVerificado` se apoya en bytes efectivamente descargados y verificados en esta misma petición.
- La divergencia sigue siendo terminal (`INTEGRIDAD_OBJETO_DIVERGENTE`, 409), no reintentable, y no toca el objeto.
- La guarda `reclamo.estado !== "subido_verificado"` (1007, 1030) evita descargar/subir en el estado donde el ledger ya fijó huella.

Los 27 unitarios cubren las cuatro variantes de forma no trivial (`handler.test.ts:790-881`): en `identico` y `divergente` se afirma que `upload` **no** ocurre, y en `ausente` que sí. La banca cubre el ciclo real con lease real. Eso es evidencia sólida para lo ensayado.

Dicho esto, quedan defectos concretos.

---

## 2. Hallazgos sobre el cambio y su entorno

### H1 — La rama de recuperación nunca se ejerció contra el adaptador Storage de producción · **Alta**

`handler.ts:1011-1014` decide "ausente" con `previa.error?.statusCode !== 404 && previa.error?.code !== "NoSuchKey"`. La lógica booleana es correcta, pero **depende de que el adaptador real pueble `statusCode` o `code`**.

- En el arnés, quien los puebla es `pdf-fixture.mjs:12-13` (`statusCode: Number(r.data?.statusCode ?? r.status)`), que es código de prueba, no de producción.
- El entrypoint Deno (`index.ts`) que construye el `StorageContratoPdfV2` real **no está en la evidencia**. `supabase-js` no expone `statusCode` de forma uniforme en `download()` según versión (`StorageApiError.status`, o un `Error` plano con `message: "Object not found"`).
- Los dos casos que sí pasan por el entrypoint Deno (`probar-pdf-real.mjs:121-125`) son camino feliz: no pierden respuesta, no llegan a `intentos > 1`, no tocan esta rama.

**Consecuencia si el mapeo falla:** un objeto genuinamente ausente se clasifica como "inaccesible", el job cae a `error_reintentable` en bucle y **nunca vuelve a subir**. Es decir, el fallo original (cuelgue) se cambiaría por otro (contrato que jamás se sella), silencioso y permanente.

**Reproducción:** en el banco, ejercer `perderRespuesta('subir')` a través de `/functions/v1/crm-contrato-pdf-v2` (no del fixture Node), borrar el objeto de `storage.objects` y esperar el lease.

**Prueba mínima:** un test del adaptador de producción que descargue una ruta inexistente y afirme `error.statusCode === 404 || error.code === "NoSuchKey"`. Sin eso, H1 queda como riesgo abierto, no como defecto confirmado — no dispongo de `index.ts` para decidirlo.

### H2 — `INTEGRIDAD_JOB` no libera el lease ni marca el job · **Media — preexistente, agravado en costo por el cambio**

`handler.ts:941-953`: tras `adquirido: true`, si falla la coherencia (p. ej. `template_version` distinta de `contrato-aep-17-v7`), se responde 409 **sin llamar a `marcarError`**. El lease de 120 s (909) queda retenido y el job vuelve a la misma situación en el siguiente reclamo, con `intentos` creciendo indefinidamente.

Esto es **anterior al cambio** y no debe imputársele. Lo que el cambio añade: como `intentos` crece en cada vuelta, a partir de la segunda **cada iteración del bucle emite además una descarga Storage** (1008). Efecto colateral: mientras el lease esté vivo, `crm.contrato_eliminacion_preparar` (migración `:1391-1401`) rechaza el borrado, así que el contrato queda además indeleteable.

**Disparador realista:** publicar una plantilla `v8` con jobs `procesando`/`error_reintentable` en vuelo.

**Prueba mínima (unitaria):** reclamo `adquirido:true` con `template_version:"contrato-aep-17-v6"`; afirmar status 409 **y** que `calls` incluye `admin:contrato_pdf_marcar_error`. Hoy fallaría.

### H3 — La exclusión mutua depende de un acoplamiento implícito lease (120 s) > timeout de worker (30 s) · **Media**

La corrección elimina la subida duplicada del caso ensayado, pero deja una ventana TOCTOU real: entre la descarga que devuelve 404 (1008) y `subir` (1031) el objeto puede aparecer si una subida anterior aún estaba en vuelo. Hoy es improbable **solo porque** el worker muere a los 30 s y el lease dura 120 s, de modo que nunca coexisten dos escritores. Ese invariante no está declarado, ni asertado, ni acoplado en código: `p_lease_segundos: 120` es un literal en `handler.ts:909` y el timeout vive en la configuración del runtime.

**Recomendación:** derivar el lease del timeout del worker (o al menos comentar/asertar `lease > timeout` con un test que falle si alguien sube el timeout de Deno o baja el lease). No es cosmético: si se invierte la relación, vuelve exactamente el fallo de 872 KB reportado.

### H4 — El cuelgue de raíz sigue sin corregirse · **Media — preexistente**

La evidencia dice que Storage respondió `400 Duplicate` en ~5 ms y que Node y Deno se quedaron esperando 30 s. Eso es un fallo del **cliente/adaptador**, no del handler: un 4xx en `subir` no debería colgar. El cambio elimina el disparador más común, pero:

- `esConflictoObjeto` (593-597) usado en 1035 es hoy una red que, si alguna vez se activa, se activa *después* de que el cliente ya colgó 30 s.
- Cualquier otro 4xx de subida (413, 403, 429) tiene el mismo perfil de cuelgue.

**Recomendación:** acotar la I/O de Storage con timeout/`AbortSignal` en el adaptador y consumir/abortar el cuerpo de la respuesta de error. Sin eso, el sistema sigue siendo sensible a un 30 s por worker ante cualquier 4xx.

### H5 — `{data:null, error:null}` se clasifica como "inaccesible" · **Baja**

Si el adaptador devolviera datos y error nulos, `1009` es falso y `1011-1014` evalúa `undefined !== 404 && undefined !== "NoSuchKey"` → verdadero → `STORAGE_DESCARGA`. Es *fail-closed* y por tanto aceptable, pero significa que ese caso **nunca** vuelve a subir. Conviene documentarlo en el comentario de 1002-1005, que hoy solo habla de 404/NoSuchKey.

### H6 — Se calcula la huella antes de validar el objeto · **Baja**

En 1064-1066 (y también en `firmar`, 811-813) se llama `fingerprint()` —que hace `arrayBuffer()` completo— **antes** de `pdfValido()`, que es quien impone `CONTRATO_PDF_MAX_BYTES`. Un objeto grande se materializa entero en memoria antes de rechazarse. La ruta solo es escribible por service-role, así que no es un vector; es higiene de memoria con PDFs de 872 KB y superiores. Preexistente al cambio.

### H7 — Costo añadido por reintento, sin medir

Cada reintento con `intentos > 1` agrega una descarga (872 KB) al presupuesto de 30 s: render + descarga + (a veces) subida + descarga. En el caso `ausente` son cuatro operaciones. La evidencia **no incluye tiempos** de la ruta de recuperación con PDFs reales; no puedo afirmar que el margen sea holgado. Sugiero registrar la duración de los cuatro escenarios de recuperación del banco.

---

## 3. Revisión adversaria de la candidata F4

Excluyo lo ya listado como pendiente en `ESTADO-ACEPTACION.md` (cotitulares no impresos, históricos F2, roles dinámicos, corrección de términos, reversa, anulación inicial/Avance/ajustes/comisión, renovaciones ponderadas/demos, carrera sello↔alta).

### S1 — El reintento de `confirmar_inversion_fn` rompe la idempotencia si la persona cambia de estado · **Alta**

`migración:575-590`. La rama de reintento (`v_s.estado='confirmada'`) se alcanza **después** de `private.inversion_persona_contexto(v_persona)` (577). Ese contexto exige, entre otras cosas, `v_i.estado='activo' and not v_i.no_contactar` (242-244) y un responsable comercial activo (245-251).

**Reproducción:**
1. `confirmar_inversion_fn(clave)` → OK.
2. Gerencia marca `no_contactar` a la persona (o se desactiva su responsable).
3. Reintento de `confirmar_inversion_fn(clave)` con la misma clave.
4. **Esperado:** el resultado almacenado con `reintento:true`. **Real:** `P0429 "La persona no permite nuevas inversiones..."` o `P0409 "Asigna un responsable comercial activo..."`.

Contradice el requisito "misma clave y contenido, mismo resultado". La prueba actual (`probar-pdf-real.mjs:79-81`) reconfirma inmediatamente, sin cambio de estado intermedio, y por eso no lo detecta. El mismo patrón afecta a la rama `reanudar` de `crm.acceso_inversion_fn` (3865-3872): una persona vetada no puede ni releer su enlace ya completado.

**Prueba mínima:** confirmar; `update crm.inversionistas set no_contactar=true`; reconfirmar y afirmar `resultado.reintento = true` y `inversion_id` idéntico.

**Corrección sugerida:** para `estado='confirmada'` resolver solo canónica + autorización (`puede_gestionar_contratos_crm` + ámbito), sin las puertas de "admite nuevas inversiones".

### S2 — Encender la bandera vuelve indeleteable todo contrato nuevo, incluidos demo y semillas · **Alta**

`private.f4_contrato_vincular` (3787-3802) es `after insert on public.contratos` **sin filtro de `es_demo`** y sin acotarse a las altas F4: con `inversiones_escritura` activa, *cualquier* inserción crea fila en `crm.inversiones`. Y `crm.contrato_eliminacion_preparar` (1374-1377) rechaza con `55000` cualquier contrato presente en `crm.inversiones`.

Consecuencias concretas:
- La eliminación de contratos deja de funcionar para **todo** contrato creado tras el encendido, sin que exista todavía la anulación comercial Avance que la sustituya (la matriz la declara pendiente, pero no declara que la vía de borrado quede cerrada).
- Contratos demo/semilla quedan enlazados a inversiones y bloqueados. `private.capital_episodios` filtra `not c.es_demo` para contratos, pero `crm.inversiones` no lo hace: la tabla queda contaminada con demos.
- `f4_contrato_vincular` además **aborta la inserción** (`P0409 'F4: falta la identidad del contrato'`, 3794) si `asegurar_identidad_perfil` no dejó identidad.

**Prueba mínima:** con la bandera encendida, insertar un contrato `es_demo=true` y afirmar que no nace fila en `crm.inversiones`; y que `contrato_eliminacion_preparar` sigue autorizando su borrado.

### S3 — Encender la bandera hace que toda alta Avance dependa de la resolución de identidad · **Alta (riesgo de despliegue)**

Encadenado con S2: `trg_contratos_000_f4_reconocer` (3774-3785) llama `asegurar_identidad_perfil` en **todo** insert de contrato, y `f4_contrato_vincular` exige que la identidad exista. Un cliente antiguo con documento faltante, inválido o duplicado que hoy puede firmar un contrato, con la bandera encendida **no puede**. El cambio no es aditivo en el sentido operativo, aunque lo sea en el esquema.

**Acción previa a encender:** censar en producción los `public.perfiles` con `rol='cliente' and activo` para los que `asegurar_identidad_perfil` fallaría (sin documento, documento de otra identidad reconocida, dos identidades no fusionadas con el mismo `perfil_id`). No hay evidencia de que ese censo exista; el recenso citado (14 enlaces, un faltante) es de otra cosa.

### S4 — `confirmar_inversion_fn` no revalida la solicitud tras el `FOR UPDATE` · **Media**

Asimetría real entre las tres puertas:
- `acceso_inversion_fn:3842-3845` y `revisar_solicitud_inversion_fn:4050-4053` releen y comparan `v_s.inversionista_id is distinct from v_origen` → `40001`.
- `confirmar_inversion_fn:575-579` lee `inversionista_id` **sin bloqueo** (575), resuelve el contexto y luego bloquea (579), pero **no vuelve a comparar**.

Hoy no es explotable porque nada actualiza esa columna, pero **no hay nada que lo garantice**: `crm.inversion_solicitudes` no tiene trigger de inmutabilidad (`private.f4_fuente_inmutable` cubre `inversion_ajustes_mes_cerrado`, `inversion_eventos` e `inversion_solicitud_revisiones`, 467-469, pero no la solicitud). `datos`, `hash_payload`, `empresa_id` e `inversionista_id` son igual de mutables por un futuro escritor.

**Corrección:** añadir la misma revalidación, o un trigger `before update` que congele `id, inversionista_id, empresa_id, hash_payload, datos, creado_por, creado_en`.

### S5 — La inmutabilidad de bytes del comprobante solo aplica al rol `authenticated` · **Media**

Las políticas restrictivas (715-722) son `to authenticated`. La ruta service-role (que es la que usan las Edge de Storage) no queda cubierta. El diseño mitiga bien el **borrado** vía FK `comprobante_objeto_id references storage.objects(id)` sin `ON DELETE` (70): eliminar el objeto queda bloqueado. Pero **no cubre la sustitución de bytes** con el mismo `id` (upsert), y no se persiste ninguna huella: `confirmar_inversion_fn:601-606` ya lee `metadata->>'size'` y `mimetype` y los descarta.

**Corrección de bajo costo y alto valor:** guardar `sha256` (o al menos `size` + `mimetype`) del comprobante en `crm.cierres_externos` al confirmar, para que una sustitución posterior sea detectable. La prueba del banco afirma "comprobante conservado" comparando bytes, pero eso verifica el camino feliz, no la garantía.

### S6 — `f4_comprobante_autorizado` propaga errores de negocio y toma `FOR UPDATE` dentro de un `WITH CHECK` de RLS · **Media**

`440-456`. La función captura únicamente `insufficient_privilege` (452). `private.inversion_persona_contexto` lanza además `P0409`, `P0429` y `40001` (216, 234, 240, 243, 250, 255, 261, 264, 273, 279, 282, 288). Esos errores **escapan** de la política RLS hacia el cliente de Storage en un INSERT: mensajes de negocio en una superficie que debería devolver una violación de política.

Además, esa función ejecuta `select ... for update` sobre `crm.inversionistas` (227) y candados advisory (191, 218) **dentro de la evaluación por fila de una policy**. Efecto: cada subida de comprobante serializa a la persona durante toda la transacción de Storage. El orden de candados coincide con el de las RPC (bandera → jerarquía → documentos → persona), así que no veo deadlock, pero es un patrón que conviene documentar y acotar.

### S7 — Unicidad de `inversionistas.perfil_id` asumida sin garantía visible · **Media, no confirmada**

`f4_contrato_vincular:3792-3793` y `inversion_vincular_fuente:510-513` hacen `select ... into` sobre `crm.inversionistas where perfil_id = ... and estado <> 'fusionado'` **sin `limit` ni orden**. Con dos identidades no fusionadas compartiendo `perfil_id`, plpgsql toma una fila arbitraria y el contrato se enlaza a una identidad no determinista. La migración no crea índice único parcial para esa condición y el DDL previo de la tabla no está en la evidencia: **no puedo confirmar si el índice existe**. Si no existe, es un defecto de integridad; si existe, conviene añadir `limit 1` documentado igualmente.

### S8 — `producto_condicion_id` inválido explota en confirmar, no en preparar · **Baja**

`preparar_inversion_fn` solo valida la lista blanca de claves (360-363). El cast ocurre en `confirmar_inversion_fn:665-666`, dentro de un `perform set_config(...)` **sin** manejador de `invalid_text_representation` (a diferencia de 366-369, 385-391, 622-636). Resultado: `22P02` crudo en confirmación, tras haber bloqueado a la persona.

**Prueba mínima:** `preparar` con `producto_condicion_id: "no-uuid"` → hoy pasa; `confirmar` → `22P02`. Debería fallar en `preparar` con `22023`.

### S9 — `corregir_cierre_externo` puede violar el CHECK F4 con mensaje crudo · **Baja**

`v_referencia := nullif(btrim(p_referencia),'')` (1636) y el UPDATE de 1693-1701 pueden dejar `referencia_externa` en NULL. Para una fila con `es_cierre_inicial=false`, eso viola `cierres_f4_datos_completos` (82-88) y devuelve un `23514` de constraint en vez de un mensaje de negocio. Es fail-closed, pero la función no distingue filas F4 de las iniciales en ninguna de sus validaciones.

### S10 — Idempotencia de `preparar` tras fusión: contrato no ensayado · **Baja, pendiente de prueba**

`preparar_inversion_fn:375` compara `v_s.inversionista_id <> v_persona`, donde `v_persona` es el id **crudo** del payload, no la canónica. Es coherente con "la solicitud conserva la identidad de origen", pero implica que, tras una fusión, un reintento con la identidad **vigente** produce `P0409 "La misma clave llegó con datos distintos"`. El front debe reenviar `inversionista_origen_id` (expuesto en `inversion_solicitud_resultado`, 300). No veo ese caso en la batería ensayada: es un requisito de contrato con el cliente que conviene fijar con una prueba.

### S11 — `es_primera_conversion` siempre `false` en el camino Avance · **No confirmado**

`f4_contrato_vincular:3795` y `confirmar_inversion_fn:683` pasan `p_inicial=false`; solo `convertir_lead_externo:3031` pasa `true`. Si algún consumidor económico usa `crm.inversiones.es_primera_conversion`, las primeras inversiones Avance quedarían mal clasificadas. **No dispongo de los lectores de esa columna**, así que lo dejo como pregunta abierta, no como defecto.

### S12 — La FK del ajuste impide desellar un mes · **Informativo**

`inversion_ajustes_mes_cerrado.periodo_origen references crm.periodos_cerrados(periodo)` (152). Cualquier reversa de un sello mensual queda bloqueada por esta FK una vez existe un ajuste. Probablemente deseado; conviene declararlo en el paquete de reversa que la matriz ya da por pendiente.

### Sobre `capital_episodios` y las fuentes económicas

La adaptación (823, 832-833, 839) usa consistentemente `coalesce(fecha_imputacion::timestamp at time zone 'America/Lima', creado_en)` en filtro, bucket, `mes_comercial` y la búsqueda de `meta_periodos`. Las filas históricas tienen `fecha_imputacion` NULL y caen al `creado_en` original, lo que preserva la paridad que la evidencia declara medida. No encuentro asimetría entre los tres usos. La exclusión por id de la demo Qorilazo se mantiene idéntica en el núcleo (813, 829) y en `cierres_externos_fn` (1929, 1959), como pide su propio comentario.

---

## 4. Sobre el PDF legal y los cotitulares

Acato la instrucción: **no propongo ninguna modificación del texto legal ni de la plantilla**. Solo califico el riesgo, que ya está registrado como pendiente:

- La plantilla `contrato-aep-17-v7` está byte-idéntica a HEAD, el snapshot guarda cotitulares y el PDF sellado no los imprime. El artefacto legal (identificado por su sha256 y sellado en el ledger) y el registro interno describen conjuntos de partes distintos.
- Añado un matiz que no veo cubierto: F4 **no valida ni vincula la identidad de los cotitulares**. `preparar_inversion_fn` acepta `contrato` casi verbatim (432-433) y `public.crear_contrato:3317-3319` delega en `_sync_contrato_titulares`; `crm.inversion_titulares` solo recibe el principal (`inversion_vincular_fuente:539-541`). Es texto libre sin enlace a `crm.inversionistas`.
- Cualquier incorporación de cotitulares al documento debe mostrarse y aprobarse antes, como está ordenado. Lo dejo señalado como pendiente explícito, no como autorización.

---

## 5. Evidencia que falta para cerrar hipótesis

Lo digo sin rodeos: hay conclusiones que **no puedo emitir** con lo entregado.

1. **`index.ts` del Edge Deno** — sin él, H1 (mapeo real de 404/NoSuchKey) es riesgo, no defecto confirmado. Es el punto más importante de esta revisión.
2. **SQL de `contrato_pdf_reclamar`, `contrato_pdf_marcar_subido`, `contrato_pdf_finalizar`, `contrato_pdf_estado_fn`** — la guarda `intentos > 1` depende íntegramente de que el reclamo incremente `intentos` en *toda* readquisición. La banca lo corrobora empíricamente en los cuatro escenarios de recuperación (afirma `intentos === 2`), lo cual es evidencia fuerte, pero el invariante no está asertado en ningún sitio ni documentado como contrato de la RPC.
3. **`renderer.ts` y el origen de `renderizado_en`** — el esquema entero descansa en que el render sea byte-determinista dada la pareja (snapshot, `renderizado_en`) y en que `renderizado_en` se persista en el job y se devuelva idéntico en cada reclamo. La banca lo corrobora indirectamente (los reintentos convergen al mismo sha256). Riesgo a documentar: si alguna vez el render pasara a depender del reloj, **todo fallo transitorio se convertiría en un bloqueo de integridad permanente**, no en un reintento.
4. **DDL previo de `crm.inversiones` y `crm.inversionistas`** — necesario para cerrar S7 y para saber si `crm.inversiones(contrato_id)` / `(cierre_externo_id)` tienen unicidad (el `for update` de 523-524 no protege una fila inexistente).
5. **`asegurar_identidad_perfil`, `inversionista_canonica`, `saga_auth_*`, `_sync_contrato_titulares`, `puede_gestionar_contratos_crm`** — invocadas críticamente y no incluidas; no audité su contenido.
6. **Tiempos de la ruta de recuperación** con PDFs de 872 KB (H7).

---

## 6. Alcance y limitaciones

- Revisión estática sobre cinco artefactos: `handler.ts`, `handler.test.ts`, `probar-pdf-real.mjs`, `pdf-fixture.mjs`, `ESTADO-ACEPTACION.md` y la migración candidata. Sin ejecución, sin acceso al repositorio, sin banco.
- **No verifiqué** la aserción de que plantilla, renderer, firma, fondo y fuentes son byte-idénticos a HEAD: no tengo esos archivos ni el árbol git. La tomo como declarada por el agente primario.
- **No verifiqué** que los 27 unitarios y la batería del banco pasen; leí su código y evalúo qué cubren y qué no. Lo que sí puedo afirmar es que la cobertura declarada es real en el código de prueba mostrado, y que H2, S1, S2 y S8 caerían fuera de ella.
- Los hallazgos H2, H4, H6 y las semánticas de corrección de cierres son **preexistentes** al cambio del handler; los marco como tales y no los imputo a esta corrección. H1, H3 y H5 sí pertenecen a la superficie que el cambio introduce o modifica.
- **Esto no es una aprobación de F4, ni total ni parcial.** No he ensayado nada; no puedo certificar requisitos no probados. La matriz de `ESTADO-ACEPTACION.md` sigue con siete filas parciales o incompletas y esta revisión no cierra ninguna. Lo único que sostengo es lo dicho en §1 sobre las propiedades del cambio en el handler, y aun eso queda condicionado a H1.

**Prioridad sugerida para el agente primario:** H1 y S1 antes de nada; S2 y S3 antes de cualquier encendido de bandera; H2 y H3 antes de considerar cerrado el bloque PDF.
