# Facturación 3B: puerta de lista y permisos

**Estado: en banco, sin aplicar** (09/10/2026). Encargos 1–3: puerta, revisiones, decisión de Miguel sobre Directorio y
días sueltos. Huellas MEDIDAS (ver «Verificación del PRIMARY»). Sin cambios de pantalla, cifra ni piezas de la 3A.

## Contrato

`crm.listar_operaciones_facturacion_fn(desde, hasta, dias, analistas, sin_analista, equipo, sin_equipo, tipos, moneda, pagina, tamano)`
es SQL, STABLE, DEFINER de postgres, `search_path` vacío, EXECUTE solo postgres/authenticated. Delega en
`private.facturacion_lista`, PL/pgSQL, STABLE, INVOKER, ACL solo postgres. `sin_analista boolean default false`
va inmediatamente después de `analistas` en ambas firmas. `p_dias date[] default null` va inmediatamente
después de `p_hasta`; firma de puerta y núcleo:

```text
(date, date, date[], uuid[], boolean, uuid, boolean, text[], text, integer, integer)
```

- Fechas inclusivas de Lima; máximo 31 días. Tamaños 25/50/100; página desde 1.
- `dias = NULL` conserva la consulta completa del rango. Si se indican días, solo cuentan esos días de Lima
  (`dia = any(p_dias)`), después de la capa 1, junto con los demás filtros: filas, total y totales del mismo conjunto.
  Vacío, elemento NULL o cualquier día fuera de `[desde, hasta]` dan `22023`; repetir/desordenar días no cambia nada.
  Es la regla de Miguel del 11/09: al marcar días sueltos, la malla contiene únicamente esos días.
- NULL en analistas/tipos significa todos; arreglos vacíos dan `22023`.
- `sin_analista` selecciona `analista_id is null`; combinado con `analistas` da `22023`.
- `equipo` es el supervisor **de entonces**; `sin_equipo` selecciona supervisor NULL y excluye `equipo`.
- Una sola llamada a `private.facturacion_operaciones_visibles` produce operaciones, filtros, totales y páginas.
  PEN y USD jamás se suman entre sí. Mes sellado = cuenta viva.
- Orden total `(fecha, tipo, operacion_id)`; `n` es la posición en el conjunto filtrado; `fecha` pública es el día de Lima.
  Offset bigint, también para páginas grandes. Enriquecimiento personal solo sobre la página.
- **Decisión de Miguel del 09/10 por la noche:** Gerencia ve todo. Directorio ve los contratos con nombre y N.º,
  pero **toda cooperativa** sale como «Cliente de otro equipo». Dos banderas explícitas: contratos = Gerencia o lector
  global; cooperativas = solo Gerencia. La exclusión de Directorio no depende de que su conjunto de vendedores esté vacío.
- Para los demás, contrato según `cliente_ids_visibles_crm`; cooperativa según la **relación de hoy**, con la regla
  del **teléfono vivo** de `crm.cierres_externos_fn`: responsable de `private.inversionista_canonica(ce.inversionista_id)`
  dentro de los vendedores visibles, o, sin inversionista, dueño actual del lead en ese conjunto. Esta regla es más
  estricta que el reparto de filas de «En cooperativas», que usa `analista_efectivo_cierre`.
- Se conserva la llamada a `inversionista_canonica`, con lateral solo para las filas de la página y para lectores no
  globales. Los arreglos de clientes/vendedores se calculan una vez por petición no global.
- **Excepción explícita del contrato de respuesta:** la fila de otro equipo conserva analista, supervisor, día, tipo,
  moneda, importe y `anulado`, ya mostrados por la cifra o que explican por qué cuenta. Tiene exactamente las doce
  claves comunes y el nombre «Cliente de otro equipo». **Ni un id de cliente, contrato, cierre o lead**, ni N.º,
  cooperativa, estado o número de transacción.
- Nunca se proyectan DNI/documentos ni datos bancarios. No se registran aperturas.
- Sin autorización: `total: 0`, `filas: []`, `totales: []`; anon/service_role no ejecutan la puerta.
- La prueba SQL usa una foto REPEATABLE READ. Peticiones HTTP separadas pueden observar cambios concurrentes.

## Revisiones y evidencia anterior

Las dos revisiones recibidas fueron **Codex revisor** y **auditor-rls**. Resolución del PRIMARY incorporada:

- **Aceptado — Codex P2-1/P2-2/P2-3:** comparación por posición y operación, visibilidad independiente, ids visibles
  exactos, claves exactas de raíz/totales y búsqueda de documentos en cada respuesta completa.
- **Aceptado — auditor P2-2 y P3-2 a P3-7:** gate no vacío de capa 2 y subárbol anidado, huellas desde una única fuente,
  cabecera neutra, medición no global, nuevos casos/mutantes, «Sin analista», comentarios de relación actual y más
  fuentes de documentos. Los siete mutantes nuevos también recogen la revisión de Codex.
- **Rechazado:** retirar analista, supervisor y `anulado` de la fila enmascarada. La excepción explícita conserva los
  datos de la cifra o necesarios para explicar por qué cuenta, sin ids del cliente/contrato/cierre/lead.
- **Decisión posterior de Miguel:** sustituye la autorización de cooperativas para Directorio del primer encargo.
  El auditor comprobó que Directorio no recibe clientes de cooperativas en las demás pantallas (`cierres_externos_fn`
  sin filas; cartera `solo_avance`); contratos con nombre y Gerencia global se conservan.

**Evidencia de banco anterior comunicada por el PRIMARY:** ciclo aplicar/reaplicar/reversa, gate y ensayo con los
cinco mutantes anteriores, todo PASS. La llamada canónica se midió en 93 llamadas / 1,1 ms; cuerpo vivo
`34702897135078893b7d3a726b0c1816`, incluido en `vivo/` y en la verificación del generador. Se conservan la prueba
sobre el mes con MÁS operaciones, la siembra sin `beneficiario_dni*` (su trigger manda esos datos a cuentas bancarias)
y capital ≥ 100. Las antiguas huellas `6596155d…` / `f3b53fbe…` **no validan esta revisión**.

**Riesgo:** `private.facturacion_lista` depende de `cliente_ids_visibles_crm`, `vendedor_ids_visibles`,
`inversionista_canonica`, `rol_crm` y `es_lector_global`. Hay que reauditar esta lista si cambia cualquiera de ellas.

## Oráculo y gate

El DO corre en REPEATABLE READ (lock 10 s, sentencia 120 s), exige las huellas/contratos de la 3A y rechaza instalaciones
parciales o inesperadas. Postflight de huellas, dueño, ACL exacta/efectiva, lenguaje, STABLE y DEFINER/INVOKER con
`is not true`. Precondición de aplicación: 3A aplicada y registrada; el ensayo de producción comprueba el registro.

El oráculo recorre Gerencia, Directorio reconocido, cada supervisor activo, vendedor y sin sesión; ambos GUC se fijan
y limpian. Todos los meses con operaciones más el actual, todas las páginas. Compara con la cifra por día/tipo/moneda/
analista/supervisor mediante `EXCEPT ALL` en ambos sentidos; además reconstruye desde `_visibles` la secuencia filtrada
por `(fecha,tipo,operacion_id)` y exige por `n` fecha de Lima, tipo, moneda, monto, anulado, analista y supervisor.
La visibilidad se calcula independientemente con la regla anterior; los ids/número/cooperativa visibles deben
corresponder a esa operación. Directorio conserva operaciones, total, totales y contratos; toda cooperativa se enmascara.

Se exigen claves exactas en raíz, cada total y cada fila. **Cada respuesta entera** se busca por valores de documentos
no vacíos de al menos seis caracteres: perfiles (DNI y beneficiarios), cierres, DNI del lead e identificadores del
inversionista (normalizado/original, incluidos alias y canónica). Ningún error imprime esos valores. Filtros probados
sobre el mes con MÁS operaciones, incluidos sin analista y los dos días extremos con operaciones para cada
identidad (las no autorizadas siguen vacías). Se exige que ese mes tenga al menos dos días distintos con operaciones.
Cifra y secuencia esperada se filtran con `dia = any(p_dias)`; veintiuna negativas SQL exigen exactamente `22023`
(incluidos días vacíos, elemento NULL y día fuera de rango).

El bloque L del gate censa las cadenas 3A/3B y sus contratos con la firma nueva. `testFacturacionLista` lee las huellas
**del bloque HUELLAS de la migración**, sin constantes copiadas, y compara `md5(pg_get_functiondef)` fuera de banda.
Prueba nueve sesiones (incluida `sup1Nested`), tres tamaños, cifra, secuencia, claves y respuesta completa sin documentos.
Para sup1/sup2/sup1Nested exige máscaras no vacías y su conteo SQL independiente, contratos visibles con nombre/N.º y
cooperativas de canónica ajena ocultas. Las lecturas independientes fijan ambos GUC en transacciones READ ONLY; los
clientes permitidos se deducen del subárbol del fixture: asesor dentro, o asesor nulo y creador dentro.

**Fixture del gate:** si enero no cubre contratos propios/entre equipos y cooperativas de canónica ajena para los tres
supervisores, se crea una foto legada exclusiva del bloque (cuatro contratos, dos cierres, alias y personas propios).
Incluye la rama anidada y asesor nulo con creador propio; contratos los días 2 y 5 y cierres el día 7.
También se siembra si faltan tres días con operaciones. Gerencia y sup1 prueban dos días extremos contra SU cifra:
total, totales y filas por posición, con operaciones intermedias excluidas y repetidos/desorden sin cambios.
Alta y limpieza fuera de banda usan `session_replication_role`
LOCAL a la transacción, como otros bloques: enero puede estar sellado, no se cambian sellos ni banderas. Se retira en
`finally`, por UUID propios, incluso si falla una aserción; no se modifica la semilla global ni se dejan documentos
para otros bloques. Los contratos reciben snapshots mediante `crear_snapshot_producto_legacy`; sus condiciones y
versiones también se retiran. Este fixture verifica lectura/permisos; el ensayo sintético conserva los triggers encendidos.

## Archivos, banco y medición

La fuente de verdad es `../../migrations/20261009234500_crm_facturacion_lista_operaciones.sql`.
`generar-cuerpos.py` verifica doce cuerpos vivos, sincroniza el DO en los tres ensayos, comparador sintético y reversa.
`generar-registrar.py` copia el texto exacto completo a `registrar.sql`, idempotente y cerrado ante otro texto/nombre.

Desde `CRM-Avance-Corp`:

```sh
python3 supabase/scripts/facturacion-lista/generar-cuerpos.py
python3 supabase/scripts/facturacion-lista/generar-registrar.py
python3 supabase/scripts/facturacion-lista/generar-cuerpos.py --verificar
python3 supabase/scripts/facturacion-lista/generar-registrar.py --verificar
python3 supabase/scripts/facturacion-lista/test_generadores.py
node --check supabase/scripts/test-rls.mjs
git diff --check
```

`--verificar` no escribe. Sincronizar marcadores no acredita huellas: el SQL sigue fallando cerrado.
Si el banco conserva una firma anterior de 3B (sin `p_dias` o sin `p_sin_analista`), revertirla primero con su
kit/huellas anteriores: el nuevo preflight
y la nueva reversa rechazan firmas anteriores o sobrecargas, evitando dos puertas con argumentos por defecto ambiguos.

El PRIMARY ejecuta `ensayo-sintetico.sql` como postgres en banco **vacío**, 3A con las huellas de producción, producto
`HISTORICO-SIN-CATALOGO` y mes anterior/actual abiertos. READ COMMITTED por el trigger de alta de personas.
La primera ejecución debe llegar al postflight, mostrar ambas huellas y rechazar los marcadores; sustituirlos solo
en HUELLAS y regenerar. No aflojar guardas si falla antes. Repetir con las huellas medidas para comprobar:

- Más de 200 operaciones, PEN/USD, tres tamaños, páginas fuera de rango; dos contratos iniciales de igual importe.
- Cliente trasladado, cooperativas por lead propio/ajeno y anulada, inversionista propio y ajeno, alias propio con
  canónica de otro equipo; Directorio con contratos visibles y cooperativas ocultas. Aserciones tras los triggers.
- Días sueltos 1/5/20 en los tres tamaños, contra cifra y secuencia por posición; hay operaciones intermedias
  excluidas. Repetidos/desorden sin cambios; las tres negativas de días se ejecutan en el DO copiado de la migración.
- Trece mutantes, cada uno solo pasa con su SQLSTATE esperado; cualquier otro error se relanza y cada cuerpo se restaura:

| Mutante | SQLSTATE |
|---|---|
| Sin capa 2 | P3B01 |
| DNI en fila | P3B02 |
| Página corrida | P3B03 |
| Sin verja | P3B04 |
| PEN y USD sumados | P3B05 |
| Cooperativas siempre visibles | P3B06 |
| Todo enmascarado para no globales | P3B07 |
| Sin resolución canónica | P3B08 |
| Directorio ve cooperativas | P3B09 |
| Fila duplicada con igual importe y orden | P3B10 |
| Documento extra en raíz | P3B11 |
| Sin analista ignorado | P3B12 |
| `p_dias` ignorado | P3B13 |

El ensayo acaba con reversa y ROLLBACK. Después, ciclo aplicar → reaplicar → reversa → reversa → aplicar y gate
con `CRM_RLS_EXIGE_FACTURACION=1`, `CRM_BANCO_PSQL_URL` y la configuración del banco. Probar también registrador
ante otro texto y reversa ante consumidor extra. `test-facturacion.sql` permanece intacto.

- `ensayo-produccion.sql`: exige 3A registrada y supervisor con filas, mismo DO. Error final deliberado
  `ENSAYO 3B PASS ... SE DESHACE TODO`, con meses, identidades, filas, máscaras, huellas y ms.
- `medir.sql`: septiembre y octubre de 2026; **Gerencia y, en cada mes, el supervisor con MÁS cooperativas** según
  `_visibles`. Página 1/100 con `p_dias => null` y totales, calentamiento y mediana de siete muestras por ruta y mes;
  límite **150 ms**.
  Falla ante mes vacío o ausencia de supervisor con cooperativas. Mensaje final con las dos rutas, uid, volumen y
  las cuatro medianas; todo se deshace. La ruta del supervisor ejercita el lateral no global.
- Reversa sin CASCADE, huellas y guarda de consumidores. Va **antes de revertir 3A**.
- Aplicación y registro quedan al PRIMARY tras sus verificaciones y autorización.

## Verificación de este encargo

**PASS offline:** ambos generadores `--verificar`, `test_generadores.py` (12/12), `node --check` y `git diff --check`.
Las pruebas nuevas cubren canónica viva alterada, firma anterior rechazada, propagación de huellas desde una única
fuente, firmas sin días o con días fuera de posición y construcción de los trece mutantes sobre el cuerpo actual
(no su ejecución SQL).
Ejecución SQL, trece mutantes, ciclo, gate API/RLS y ambas rutas de rendimiento: **NOT RUN en este encargo**, por la
restricción explícita sin red, Docker ni producción. El PASS de banco anterior no se atribuye al código nuevo.
No se invocaron otros agentes ni se hicieron commits.

## Verificación del PRIMARY

**Verificación del PRIMARY (09/10/2026, banco Docker a paridad con producción):** huellas medidas núcleo `e8c3178b74ec5718e87b5b5fc697e1fd` y puerta `3b84fe0660b2257398edfd835828f3eb` (texto de la migración md5 `0383464b25f8a9ee2efd507c7cab1245`). Banco con datos: aplicar → «ORÁCULO 3B PASS: 4 meses, 7 identidades (1 Directorio), 172 filas, 9 enmascaradas (cooperativas de Directorio), 21 negativas» → reaplicar «reverificada» → la reversa de la 3A se NIEGA con la 3B instalada → reversa 3B PASS → otra vez «ya completa» → aplicar PASS; `test-facturacion.sql` 12/12; registrador idempotente. Gate RLS completo: 3421 aserciones, los mismos 9 rojos de fondo (diff vacío) y 49 comprobaciones de la lista en verde (el fixture de cooperativas del gate se dio de alta a mediodía de Lima: a medianoche UTC violaba `cierres_f4_fechas_validas`). Banco vacío: «ORÁCULO 3B PASS: 2 meses, 6 identidades, 660 filas, 220 enmascaradas, 21 negativas» y TRECE MUTANTES cazados por SQLSTATE exclusivo (P3B01–P3B13), reversa y ROLLBACK. Ensayo de producción en banco: PASS con la evidencia en el mensaje final. Medición en banco (Gerencia y supervisor, rutas global y no global): 1,6–3,7 ms por página de 100; elige el supervisor con más cooperativas y, si no hay, el de más operaciones. Pendiente: ensayo y medición en producción (Miguel con `!`), aplicar y registrar.
