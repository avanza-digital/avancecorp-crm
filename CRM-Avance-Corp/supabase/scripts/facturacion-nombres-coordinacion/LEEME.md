# Nombres en el reporte de Facturación de Coordinación

Miguel autorizó el 13/10/2026 mostrar nombres para los reportes de Rosa, manteniendo
solo lectura. Se aplica al rol Coordinación activo en CRM y Portal. No habilita
fichas, identificadores de clientes/contratos/leads/cierres, números de contrato,
documentos, contactos ni escrituras. Ranking y Repartir conservan sus permisos.

## Contrato y compatibilidad

La RPC nueva `crm.listar_operaciones_facturacion_v2_fn` devuelve `version:2`.
Coordinación recibe `visible:false`, `nombre_visible:true` y `cliente_nombre`.
El panel distingue permiso de nombre y permiso de ficha; un nombre nulo se muestra
como «Cliente sin nombre». El parser rechaza campos extra y el consumidor exige v2.

La RPC v1 y su helper quedan intactos: las pestañas del frontend anterior continúan
funcionando con su máscara. Otros roles delegan exactamente en v1, sin cambiar
visibilidad, filtros o cifras. El nuevo helper INVOKER pertenece a postgres y no
tiene EXECUTE para authenticated, anon o service_role. Solo el wrapper DEFINER,
STABLE con search_path vacío, tiene EXECUTE authenticated.

**Mantenimiento obligatorio:** Coordinación usa una copia acotada del cuerpo v1
porque su salida enmascarada no contiene una identidad con la que unir nombres.
Toda modificación futura de `private.facturacion_lista` debe revisar esta copia
y ejecutar la matriz de paridad de este kit y el bloque v2 de `test-rls.mjs`.
La huella protege la instalación; no sincroniza cambios futuros automáticamente.

## Evidencia y límites

- `vivo/catalogo.json`: dos definiciones capturadas por lectura del proyecto destino
  `dctqcbznekcyxhjujuci`, sin datos de clientes. Guarda de definiciones antes/después.
- `generar.py`: genera dos funciones nuevas, permisos sellados y `reversa.sql`.
- `ensayar.py` / `prueba.sql`: siembra sintética, matriz real y rollback. Exigen la
  base local exclusiva y vacía `coordinacion_nombres_20261013`, con comentario de
  identificación, postgres y triggers encendidos. No apuntan a producción.
- Matriz SQL y reversa/reaplicación: PASS. 15 comparaciones exactas de otros roles,
  tres meses, 220 filas (214 contratos, seis cooperativas), tres páginas por mes,
  nombres iguales a Gerencia, cifras y v1 intactas, sin IDs privados/contactos,
  RLS de fichas conservada, metas denegadas y Repartir permitido.
- Bajas CRM y Portal con el mismo JWT: PASS. Se fabrican flags de fixture
  suspendiendo BEFORE guards solo durante la siembra; se restauran antes de leer.
  Esto mide el estado revocado, no el comando de offboarding.
- Frontend: `npm run check` PASS, 413 archivos / 6.651 tests, duplicación 0,43 %.
  E2E local Docker: 50 PASS (Facturación, realidad de Facturación, Coordinación y
  Repartir). Tras integrar Main remoto, repetir los checks pertinentes.
- Revisión independiente `scripts/claude-review`, auditor RLS: PASS. El primer
  intento fue rechazado por formato; la repetición entregó dictamen válido.
  Recomendaciones aceptadas: contrato v2 exigido, nombres nulos y regresión HTTP
  de paridad con v1. Aviso de mantenimiento documentado aquí sin modificar v1.
- `gate:realidad`: NOT RUN en producción por falta de credenciales configuradas;
  no equivale a las pruebas sintéticas. La identidad de Rosa se verificó por lectura.
- Rama Auth remota, advisors y publicación: pendientes; no afirmar instalación viva.

Desde la raíz CRM, con la candidata instalada en el banco local:

```sh
python3 supabase/scripts/facturacion-nombres-coordinacion/ensayar.py
```

## Instalación y reversa

Backend primero: rama Supabase autorizada → candidata → matriz RLS/Auth real
(`test-rls.mjs`, incluye v2 con nombres exactos y claves mínimas) → advisors → merge.
La rama sin datos requiere reconstruir el esquema publicado porque el replay
histórico se detiene en `20260811210049`; esa preparación no es otra migración de
producto. Se preservan las migraciones y restricciones del historial del padre.
El primer `apply_migration` falló al registrar el historial por ausencia del índice
único de idempotencia en esa réplica. Se comprobó el estado, se revirtió la candidata,
se repuso exclusivamente esa restricción del padre y se reaplicó: PASS.

Confirmar que PostgREST ve v2 y permite una lectura autenticada de Gerencia antes
de publicar frontend. Construir y publicar desde Main limpio y verificado conforme
al flujo de release del proyecto. Para revertir: frontend compatible primero;
después `reversa.sql`, que exige cuerpos y v1 intactos y elimina solo las dos
funciones nuevas, sin CASCADE ni cambios de datos.

El preflight del candidato Main `f81d726e` fue rechazado: no contiene el commit
vivo `33a701156385` (build `build-20261013T153933959Z`). Conforme al procedimiento
de rescate, la fuente de publicación se prepara desde ese commit vivo en una
copia aparte, con únicamente el parche de nombres y sus pruebas/documentación.
Conserva la realización anticipada publicada; no adelanta el cambio de referidos
que Main aún documenta pendiente de backend. El rescate debe volver a Main el
mismo día mediante un merge que preserve su historia, después del despliegue.
