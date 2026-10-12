# Coordinación: Facturación y Ranking en lectura

Autorización: Miguel, 12/10/2026. **Preparado localmente; producción sin modificar.**

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
- `../../migrations/20261012165115_crm_coordinacion_reportes_lectura.sql`: candidata.

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

App: `npm run check` pasó lint, tipos, 6.624 tests con cobertura, configuración de
release, push/tasa, build y bundle. Su última etapa de duplicación falló por copias
preexistentes ` 2.*` ajenas a esta tarea. Ejecutada sin esas copias: 0,43 %, PASS.
E2E Docker: 38 tests existentes de Repartir/lista de Facturación PASS;
los tres nuevos `e2e/coordinacion-reportes.spec.ts` PASS tras corregir sus fixtures.

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

Matriz HTTP/Auth general `test-rls.mjs` y advisors de rama: NOT RUN, pendientes
del ciclo de release. Preflight offline con valores sintéticos y sin conexión: PASS.

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
