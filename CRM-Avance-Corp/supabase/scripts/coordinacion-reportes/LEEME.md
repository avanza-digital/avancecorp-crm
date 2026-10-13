# Coordinación: Facturación y Ranking en lectura

Autorización: Miguel, 12/10/2026. **PUBLICADO el 12/10/2026, 22:53 UTC.**

Coordinación conserva Repartir como inicio y puede consultar Facturación y Ranking
de toda la empresa, cambiar filtros y abrir desgloses numéricos. No obtiene cartera,
fichas de clientes, edición, anulación ni publicación de metas. El detalle de
Facturación devuelve `visible:false`, `Cliente de otro equipo` y ninguna referencia
a clientes, leads o contratos. Los nombres e IDs del equipo comercial sirven
exclusivamente para filtros y atribución de cifras.

La consulta `equipo_reportes_fn` está separada de `equipo_visible_fn` y del store
operativo. Un fallo del reporte no impide entrar a Repartir. El permiso efectivo
comprueba actividad en CRM y Portal mediante `private.rol_crm`; un JWT anterior
a una baja no conserva el acceso.

## Archivos

- `vivo/catalogo.json`: diez cuerpos capturados de producción por lectura, sin datos.
- `generar.py`: diferencias acotadas de autorización y anonimización, con reemplazos
  de cantidad exacta; genera la migración y `reversa.sql`.
- `ensayar.py` y `prueba.sql`: matriz transaccional real con el esquema vigente y
  siembra sintética compartida de Facturación; termina en rollback.
- `../../migrations/20261012165115_crm_coordinacion_reportes_lectura.sql`: fuente versionada del cambio instalado.

## Banco y verificaciones

Contenedor exclusivo `avancecorp-coordinacion-pg-actual`, imagen PostgreSQL 17.6.1.167;
base `coordinacion_reportes_20261012`. Solo esquema, sin copiar datos de producción.
La matriz exige base vacía, comentario de identificación y triggers encendidos;
rechaza cualquier otro destino. Los fixtures técnicos (SLA, catálogo legacy y
pesos de conversión) existen únicamente dentro de la transacción sintética.

Desde la raíz CRM, con la candidata instalada en ese banco:

```sh
python3 supabase/scripts/coordinacion-reportes/ensayar.py
```

App final en copia limpia: `npm run check` PASS, 413 archivos / 6.640 tests,
lint, tipos, cobertura, configuración, build, bundle y duplicación 0,43 %. La app
es idéntica entre `3c42d572` y el commit publicado `10e3411d` (diff vacío).
E2E Docker integrado: 36 PASS, incluyendo Reportes, Ver cierres y todo Repartir.
Suite completa sobre bundle de desarrollo: 405 PASS / 2 FAIL / 26 SKIPPED.
Los dos fallos pedían fuentes exclusivas de Vite (`control-citas` y aviso de versión);
repetidos con el servidor de desarrollo requerido: 2 PASS. La primera corrida
general con dos workers había fallado por carga/timeouts: 378 PASS / 20 FAIL /
9 FLAKY / 26 SKIPPED. No se presenta esa corrida como PASS de `check:all`.

`npm run gate:realidad`: NOT RUN por falta de credencial service-role en el entorno.
Consulta equivalente parcial de contexto, solo lectura en producción: 1 coordinador
activo, 26 vendedores activos, 2 revisiones de metas del mes y 2 meses cerrados.
Los E2E cubren metas disponibles y fallo del roster; la matriz cubre el mes sin
metas y fotos cerradas. No confundir esa consulta parcial con el gate completo.

Matriz SQL: PASS, 120 comparaciones de otros roles y 24 lecturas globales de
Coordinación; escaneo de claves, IDs y nombres de clientes/leads en todos los
payloads, tres páginas de lista, roster, RLS, publicación de metas denegada,
consulta de Repartir, bajas y ACL. Reversa y reaplicación: PASS, huellas y atributos
conservados. Las bajas fabrican los flags de fixture suspendiendo sus BEFORE
guards exclusivamente durante la siembra de ese estado; se restauran antes de
la consulta autenticada y se verifica que no quede ninguno desactivado.
Esto prueba el estado revocado con el mismo JWT; no el comando de offboarding.

Dos reviews independientes con `scripts/claude-review` (arquitectura y auditor-rls).
Dictamen final del asesor: `CHANGES_REQUESTED`, por brechas de evidencia y pruebas.
El PRIMARY cerró el escaneo recursivo de privacidad, el recuento exacto de cambios
de fotos y de la matriz, la carga demo, bajas/ACL y la reversa. La identidad histórica
ausente del roster vigente se verifica en el E2E de Ranking. No se añadió un
permiso genérico para resolver una hipótesis del reviewer.

Catálogo vivo de llamadores, consultado sin escrituras: `facturacion_operaciones_visibles`
solo alimenta `crm.facturacion_diaria_fn` (agregado) y `private.facturacion_lista`
(enmascarado). `metricas_conversiones_implementacion` solo alimenta su wrapper
`crm.metricas_conversiones_fn`, cubierto por la matriz. `v_actor`/`v_uid` nacen de
`auth.uid()`; el helper conserva la misma identidad. `cierre_mes_reportes_visible`
conserva los cuatro predicados originales y añade únicamente Coordinación.
Lectura adicional de producción, sin devolver payloads ni datos personales:
38 fotos mensuales examinadas; cero con las claves sensibles prohibidas en sus
desgloses, procedencia y detalles. La prueba local comprueba también los valores
de nombres e IDs de los sujetos sintéticos.

Cierre sobre el código final: lint y build/bundle PASS; 184 tests de las dos pantallas
PASS; tres E2E Docker PASS. La última corrida de E2E usa `--output=/tmp/coordinacion-reportes-test-results`
porque la carpeta compartida contenía copias ` 2` que impedían limpiar artefactos.

Límite del banco inicial 17.6.1.105: una llamada directa denegada al helper privado
después de usarlo vía DEFINER provocó `signal 11: Segmentation fault`; también
ocurrió al invocar internamente de nuevo funciones auxiliares de las pantallas.
No se interpreta como PASS. Se redujo el ensayo a las RPC de la interfaz, cada una
en una sentencia independiente; el EXECUTE privado se comprueba por ACL. El
esquema `private` no está expuesto por la API (`supabase/config.toml`, schemas).
No se atribuye una causa ni se afirma resuelto un defecto del motor. La matriz
final del banco exclusivo pasó; no se reprodujo el helper denegado en producción.

Matriz HTTP/Auth general `test-rls.mjs`: **PASS, 3.900 aserciones, cero fallos**
sobre la rama propia, con usuarios Auth reales y datos sintéticos. Incluye grupo A;
F4-e se omite porque aún no está instalado en el padre ni en la rama.
Comprobación posterior: cero triggers de usuario desactivados y grant temporal
del seed revocado. Advisors de rendimiento: 343 → 202 avisos, cero agregados.
Rama propia `8b6b2718-8cbf-40b1-a212-465981905b1c` eliminada tras el cierre,
confirmada ausente; otras ramas preservadas. Duración aproximada 2 h 28 min;
coste de cómputo estimado US$0,0332 a US$0,01344/h, por debajo de US$1 autorizado
(estimación, no factura de Supabase).
La corrida anterior falló 44/3.629: configuraciones técnicas ausentes del volcado
y tres expectativas que aún correspondían al permiso anterior. Se restauraron
exenciones/sello de auditoría, política de llamadas, ACL explícita del propietario
de tres tablas y bandera inicial OFF de potencial, únicamente en el banco sintético.
Los oráculos ahora exigen la identidad propia en el roster operativo, el alcance
global de Facturación y la firma final de la migración, sin omitir comprobaciones.
Una repetición se interrumpió al corregir la selección de esa firma (la migración
tiene una guardia anterior y otra final); la corrida final empieza con banco limpio.
Preflight RLS y sintaxis de scripts: PASS. Ajustes de pruebas: PR #258, fusionada
en Main el 12/10/2026 a las 23:07 UTC (`01dd5742`). Acta completada el 13/10/2026
en `publicacion.json`; conserva la fuente histórica del despliegue.

Advisors: la RPC `equipo_reportes_fn` produce el aviso esperado de
[EXECUTE autenticado sobre SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
Es una proyección mínima con puerta de rol/actividad comprobada; conserva RLS y
ACL de tablas. Los demás avisos de seguridad son anteriores o corresponden al
cambio separado Ver cierres. El trinquete analítico consultado devuelve las mismas
cuatro puertas no declaradas en padre y rama; no se declara ese gate como PASS.

## Publicación comprobada

El trabajo paralelo Ver cierres instaló ambos cambios mediante su rama autorizada
y publicó el artefacto común. Se detectó antes de un segundo merge/despliegue:
no se volvió a aplicar la migración de Reportes ni a publicar la misma interfaz.
Historial productivo: `20261012223850 crm_coordinacion_reportes_lectura`;
historial de nuestra rama: `20261012212842`. El texto difiere solo por separación
de sentencias; las trece funciones coinciden en MD5, propietario, ACL, volatilidad,
modo INVOKER/DEFINER y search_path. La fuente versionada conserva SHA-256
`57aec100a96c73f6a47b8ee8288386a06e22be55914a308615efb17a5ecfd8d3`.

Fuente publicada limpia: `10e3411deb2288cbf01c81513b63a5c1ca6d9a51`.
ZIP: `crm-20261012T224323Z-10e3411deb22.zip`; SHA-256
`265fbb65b89b0ed0527b8a9e36cf9f9a9a494dc65f83f4a915915fc04801b10e`.
Build vivo: `build-20261012T224322167Z`. Verificación independiente: portada,
versión y 121 archivos JS/CSS HTTP 200 con bytes y SHA-256 exactos; PASS.
No se crearon ni editaron datos de negocio reales para esta comprobación.
El acta posterior conserva este commit como fuente del despliegue.

## Instalación y reversa

Publicar requiere invocación humana de `$release-crm`, según `CLAUDE.md`. El ciclo
backend exige rama de Supabase, matriz real, advisors y `merge_branch`; no ejecutar
`apply_migration` directamente en producción. Primero backend; después frontend.

La migración aborta y deshace todo si las diez huellas vivas cambiaron o ya existe
alguna función nueva. Antes de instalar, verificar nuevamente las huellas: otras
tareas de conversión pueden cambiar estas funciones. Si cambiaron, capturar los
nuevos cuerpos, adaptar y volver a ensayar; nunca quitar la guardia ni sobrescribir
los cambios de otro trabajo.

`reversa.sql` restaura los diez cuerpos originales y elimina las tres funciones
nuevas, sin CASCADE, solo si conserva las huellas candidatas. Ejecutarla antes de
instalar una migración posterior que dependa de estos cuerpos. No modifica datos.
Antes de revertir backend, retirar el frontend que llama `equipo_reportes_fn`.
