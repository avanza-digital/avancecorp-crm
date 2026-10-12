# Conversiones: detalle de cierres por analista

Aprobado por Miguel el 12/10/2026. Implementado localmente; **sin publicación ni migración en producción**.

Miguel invocó `$release-crm` y confirmó expresamente «Sí, instalar y continuar»: autoriza instalar esta consulta tras validarla en rama y publicar el frontend. Ciclo de instalación en curso; no equivale aún a una publicación efectiva.

La coordinadora veía cantidades sin poder consultar los clientes. «Ver cierres» muestra nombre, origen, fecha de cierre en Lima, registro manual/sistema/cartera y aporte. El origen y el aporte salen de `private.conversion_episodios`, igual que el agregado. Incluye cierres manuales, orígenes sin peso y referidos excedidos, y la primera operación elegible por cliente/mes. No cambia cifras, clasificaciones ni vínculos de ventas.

`crm.conversion_cierres_coordinacion_fn` autoriza y valida; `private.conversion_cierres_coordinacion` proyecta los datos. Solo Coordinación y Gerencia activas, con `private.rol_crm(auth.uid())`, tanto en puerta como núcleo. Actividad de CRM y Portal, permisos mínimos y search_path vacío. No se devuelven teléfonos, correos, documentos, montos ni IDs de lead, contrato o cliente, ni se conceden permisos sobre tablas/fichas.

Mes calendario sellado, incluso consultado por rango exacto: detalle no disponible porque la foto solo guarda agregados. Otros rangos se calculan en vivo como el resumen. Páginas de 20; orden por fecha, tipo y las claves canónicas únicas; página fuera de rango se ajusta al final. La UI identifica analista y período, admite reintento, anuncia carga y conserva/restaura foco; descarta respuestas abortadas o cuyo eco no coincide con lo pedido.

## Verificación

- PASS: matriz SQL `prueba.sql`, en Docker `avancecorp-coordinacion-pg-actual`, base exclusiva `conversion_cierres_20261012`, clon del esquema real sin datos de clientes. Roles admitidos/denegados, bajas en CRM y Portal, ACL, 24 episodios paginados, paridad con núcleo y agregado de la pantalla, formulario y landing manuales, referido manual, referido sin aporte por tope, fuentes demo/retirada/fuera de plazo excluidas, deduplicación de cartera, vacío, sellado, rango libre, límites Lima y diez entradas inválidas.
- La siembra suspende triggers de negocio solo para fabricar estados de lectura; FK y CHECK siguen activos y los triggers se restauran ANTES de las consultas autenticadas. No acredita los comandos de venta/offboarding. Todo termina en rollback.
- PASS: reversa y reinstalación en la base exclusiva. No cambios en las funciones canónicas preexistentes.
- PASS: tipos generados por Supabase CLI contra la candidata instalada en Docker. Se incorporó solo el bloque generado de la nueva RPC, preservando cambios ajenos.
- PASS: 31 E2E existentes de Repartir. Dos E2E nuevos: **2 passed (2,5 min)** en Docker, un worker, sin reintentos (entrada por menú, nombres/origen/registro/fecha, argumento HTTP, foco de apertura/cierre, rechazo de permisos y reintento). Corridas previas detectaron un selector ambiguo del test (corregido) y timeouts del arranque bajo carga de otra suite; no se presentan como PASS. Captura visual revisada: `app/artifacts/conversion-cierres-coordinacion.png`, datos sintéticos.
- PASS: lint (advertencias ajenas), typecheck, 6.640 tests con cobertura, tests de configuración/release/push, build y bundle.
- `npm run check`: FAIL únicamente en la última etapa, duplicación 6,7 %, por copias preexistentes ` 2.*`; no se borraron ni cambiaron esas copias.
- PASS: duplicación excluyendo únicamente copias ajenas ` 2.*`: 0,43 %, bajo el umbral 0,8 %.
- `gate:realidad`: NOT RUN completo, falta SUPABASE_URL/credencial service-role en el entorno. Lectura de producción equivalente para este caso: el núcleo devuelve dos cierres de Astrid en octubre, referido manual del día 1 y formulario del día 7. No hubo escrituras en producción.
- PASS: `check:scripts` y `test:edge-preflight`; la primera corrida dentro del sandbox no podía abrir el servidor HTTP local (EPERM), repetida con acceso local autorizado. `seed:preflight` y `test:rls:preflight`: NOT RUN por falta de SUPABASE_URL/credenciales.
- Matriz HTTP/Auth general de rama y advisors: NOT RUN; pendientes del ciclo de release autorizado. La matriz SQL local no sustituye esos gates remotos.

## Revisión independiente LEVEL 3

Una revisión `scripts/claude-review` conjunta como auditor-rls/revisor-a11y; dictamen CHANGES_REQUESTED en `revision.txt`. Decisiones del PRIMARY:

- Adoptado: gate por rol explícito en ambas capas para evitar depender de una futura ampliación del permiso de reparto; documentación de rangos vivos/mes exacto y ACL; foco estable durante carga y retorno por clave/respaldo.
- P1 sobre `anulado IS NULL` descartado con el cuerpo real: la pierna `operacion` de `conversion_episodios` emite `false`. Matriz con dos operaciones deduplicadas PASS.
- P1 sobre ámbito: el agregado existente y su contrato son globales para Coordinación; el usuario aprobó el detalle por analista en esa misma pantalla. No se amplían fichas ni permisos sobre tablas.
- El ejemplo de rango 01/09–30/09 del reviewer es mes calendario exacto y SÍ se bloquea; probado. Solo rangos no equivalentes al mes se calculan vivos.
- Orden: acreditaciones UNIQUE(lead_id), ledger convertido único por lead y operaciones con ID único. No se inventó una clave de episodio adicional.
- Eco de analista/fechas/página y aborto ya estaban en el adaptador; 7 tests MSW verifican HTTP y rechazo de respuestas cruzadas/incompletas. No se modificó crm-queries por esta tarea.

## Ensayo y publicación

Desde la raíz CRM, en la base exclusiva vacía con la candidata instalada:

```sh
docker exec -i avancecorp-coordinacion-pg-actual psql -X -U postgres -d conversion_cierres_20261012 -v ON_ERROR_STOP=1 < supabase/scripts/conversion-cierres-coordinacion/prueba.sql
```

Publicación requiere invocación humana de `$release-crm`, conforme a `CLAUDE.md`. Primero validar/aplicar backend en rama Supabase con gates y advisors, después frontend. La migración usa CREATE para fallar ante una colisión; no sobrescribe funciones anteriores. Reversa `reversa.sql` elimina exclusivamente las dos funciones nuevas, sin CASCADE, después de retirar el frontend consumidor. No hay cambios de datos que revertir.
