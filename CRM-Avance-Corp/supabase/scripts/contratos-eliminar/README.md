# Eliminar contratos con pagos y conservar auditoría

## Estado

Preparado localmente el 15/09/2026. **Sin instalar SQL, desplegar Edge ni publicar frontend en producción.**
Miguel pidió permitir eliminar contratos al administrador y confirmó expresamente
«Eliminar también contratos con pagos, conservando una copia de auditoría».

SQL para revisar: [20260915222925_crm_eliminacion_contrato_con_auditoria.sql](../../migrations/20260915222925_crm_eliminacion_contrato_con_auditoria.sql).
La instalación agrega una tabla privada y una RPC y cierra el acceso externo a las
dos RPC de eliminación antiguas. **Instalarlo no elimina ningún contrato.**

## Comportamiento

- Admin/Superadmin activo puede eliminar un contrato Avance, incluso con cuotas pagadas.
- Ficha multiempresa: botón «Eliminar contrato», identificación por número y confirmación escrita.
  La gestión Avance anterior conserva su doble confirmación.
- La RPC copia contrato, identidad del cliente, cuotas/pagos, titulares, cuentas,
  documentos, metadata/revisiones PDF, operaciones y referencias antes de borrar.
  Todo ocurre en una transacción: cualquier rechazo revierte la copia y el borrado.
- Los PDF y adjuntos privados permanecen **en sus rutas originales**, referenciadas
  por la copia. No se duplican ni eliminan bytes en Storage. Deben excluirse de
  cualquier limpieza futura de objetos sin contrato vivo.
- La copia es inmutable (UPDATE, DELETE y TRUNCATE rechazados), con RLS sin
  policies y sin grants a anon/authenticated/service_role. Se registran actor y fecha.
- Repetir una solicitud devuelve el mismo identificador de auditoría.
- Se conservan las restricciones sobre fuentes enlazadas a `crm.inversiones`,
  períodos cerrados, reasignaciones y renovaciones que protegen los triggers/FK
  del portal. No es una anulación comercial ni una modificación de esos historiales.
  En la ficha, un vínculo de inversión conocido deja el botón deshabilitado.
- Los datos operativos y las métricas que dependan del contrato/pagos se recalculan
  al eliminarlo; la copia queda fuera de los totales operativos.

## Verificación

- **PASS:** `npm run check`: lint, TypeScript, 3.617 pruebas, cobertura, build,
  configuración de publicación, bundle y duplicación. Tres casos adicionales
  posteriores de demo/metadata/historial pasan en la suite específica (33 casos).
- **PASS:** 44 pruebas Deno del handler y Storage. `delete-audited` exige acuse de
  auditoría; `delete` conserva el formato legacy. Ninguno llama a borrar Storage.
- **PASS:** cinco grupos PostgreSQL en `contratos_eliminar_20260915` (copia sintética
  propia): pago archivado exactamente, referencias documentales, actor, replay,
  permisos/roles/baja, inmutabilidad, cierre de RPC antiguas, FK nueva y rollback
  cuando falla DELETE. Los ensayos usan ROLLBACK y no dejan contratos eliminados.
- **PASS:** dos E2E del nuevo flujo, 1440 y 390 px; confirmación, cancelar/retorno
  de foco, llamada única y actualización de ficha. Captura móvil inspeccionada.
- **PASS:** preflight RLS sin conexión, con variables sintéticas; valida la
  configuración y carga del harness sin ejecutar la matriz contra Auth/API.
- **FAIL ajeno al cambio:** suite E2E global: 189 PASS, 26 omitidos, un fallo en
  `e2e/acciones-real.spec.ts:206`. Espera ocultar «Convertir a cliente» al supervisor,
  pero el cambio de `lead-drawer.tsx` que ya existía al iniciar esta tarea lo habilita.
  Ese trabajo previo se conservó sin editar.
- **NOT RUN:** matriz RLS general con Auth/API, banco remoto y advisors remotos.
  El gate de realidad CLI carecía de variables; se comprobó el permiso SQL vigente,
  dependencias y conteos mediante lecturas MCP productivas (sin datos personales).

## Revisión independiente y decisiones

Claude devolvió CHANGES_REQUESTED. Se incorporaron el cierre de las RPC legacy,
protección TRUNCATE, copia de idempotencia, detección de dependencias CASCADE/SET NULL
nuevas, mensaje de concurrencia, guardas de ficha y actualización de cachés.
Los mensajes desconocidos vuelven a quedar ocultos; los públicos de la Edge usan
`ContratoEliminacionError` para conservar el motivo de rechazo sin filtrar errores crudos.

El catálogo productivo se comprobó el 15/09: las únicas cascadas son cronograma,
documentos, titulares y cuentas; SET NULL afecta a leads/altas idempotentes.
No hay dependencias en cascada de las cuotas. La única columna de ruta en esas
tablas es `documentos.storage_path`. Los triggers PDF/documentos inspeccionados
solo bloquean modificaciones; ninguno encola borrados. No hay jobs Cron de
limpieza de esos objetos. Las referencias quedan expresamente bajo retención.

## Activación y pausa

1. Obtener conformidad al SQL exacto (regla del vault: mostrar SQL primero).
2. Ensayar el mismo archivo en una rama autorizada y verificar Auth/API, permisos
   y advisors. La copia local no sustituye ese paso productivo.
3. Integrar con `avancecorp/main`, verificar el commit y generar su artefacto.
4. Instalar SQL, desplegar `crm-contrato-pdf-v2` y publicar el frontend por el
   procedimiento del proyecto. Durante el intervalo, una Edge anterior falla
   cerrada al intentar la ruta antigua. El resto de operaciones PDF sigue vigente.
5. Verificar en entorno autorizado sin eliminar contratos reales de prueba.

Para pausar la eliminación: revocar EXECUTE de
`crm.contrato_eliminar_auditado(uuid,uuid)` a `service_role`. **No borrar la tabla
de auditoría ni restaurar las puertas antiguas que destruyen archivos.**

Consulta de evidencia por personal con acceso SQL autorizado (owner), usando el
UUID del acuse o del contrato:

```sql
select id, contrato_id, eliminado_por, eliminado_en, snapshot, archivos
from crm.contratos_eliminados_auditoria
where id = '<uuid-del-acuse>'::uuid;
```

Los objetos se recuperan desde los buckets privados por las rutas de `archivos`
mediante el administrador autorizado de Storage. No hay visor público ni
restauración automática. No se ha definido una purga: conservar los registros.

Prueba local, con el banco propio disponible:

```sh
node --test CRM-Avance-Corp/supabase/scripts/contratos-eliminar/auditoria.test.mjs
```
