> **Estado actualizado 16/09:** backend y frontend publicados. La entrega
> autorizada de Cartera incluyó esta interfaz desde `a09ecad`; 78 recursos HTTP
> idénticos verificados. La deuda global se repara en `../rls-vigente/`.
> Las menciones de frontend pendiente más abajo describen la preparación original.

# Eliminar contratos con pagos y conservar auditoría

## Estado

Implementado y validado localmente y en rama remota el 15/09/2026 (Lima).
**SQL y Edge instalados en producción el 15/09 a las 21:44 Lima, con autorización.**
La interfaz web queda pendiente de `/release-crm`. [Readback productivo](PRODUCCION.json).
Miguel pidió permitir eliminar contratos al administrador y confirmó expresamente
«Eliminar también contratos con pagos, conservando una copia de auditoría».

SQL aprobado, ensayado e instalado, en este orden:

1. [20260915222925_crm_eliminacion_contrato_con_auditoria.sql](../../migrations/20260915222925_crm_eliminacion_contrato_con_auditoria.sql).
2. [20260916003000_crm_eliminacion_auditada_guardas.sql](../../migrations/20260916003000_crm_eliminacion_auditada_guardas.sql).

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
- Repetir una solicitud devuelve el mismo identificador de auditoría. Si una
  restauración parcial reintrodujo ese UUID como contrato vivo, se bloquea la
  operación y se pide revisión: no se confirma una eliminación que no ocurrió.
- Se conservan las restricciones sobre fuentes enlazadas a `crm.inversiones`,
  períodos cerrados, reasignaciones y renovaciones que protegen los triggers/FK
  del portal. No es una anulación comercial ni una modificación de esos historiales.
  En la ficha, un vínculo de inversión conocido deja el botón deshabilitado.
- Los datos operativos y las métricas que dependan del contrato/pagos se recalculan
  al eliminarlo; la copia queda fuera de los totales operativos.

## Verificación

- **PASS:** `npm run check:all`: lint, TypeScript, 3.620 pruebas en 247 archivos,
  cobertura, configuración de publicación, build, bundle y duplicación;
  192 E2E PASS y 26 omisiones existentes. Incluye eliminación a 1440 y 390 px,
  confirmación escrita, cancelación/foco, llamada única y actualización de ficha.
  La aserción antigua de conversión del supervisor se actualizó al comportamiento
  ya integrado en Main, con backend productivo cotejado (versión 17).
- **PASS:** 46 pruebas Deno del handler y Storage. `delete-audited` exige acuse de
  auditoría; `delete` conserva el formato legacy. Ninguno llama a borrar Storage.
- **PASS:** siete grupos PostgreSQL en `contratos_eliminar_20260915` (copia sintética
  propia): pago archivado exactamente, referencias documentales, actor, replay,
  permisos/roles/baja, inmutabilidad, cierre de RPC antiguas, FK nueva y rollback
  cuando falla DELETE; colisión con UUID reintroducido y acción FK modificada.
  Los ensayos usan ROLLBACK y no dejan contratos eliminados.
- **PASS:** `deno check` con la configuración de la Edge, `check:scripts`,
  `test:edge-preflight` y preflight RLS.
- **PASS:** 284 aserciones Auth/Data API del gate `test-rls.mjs --contratos`,
  incluidos permisos, domicilio legal, frontera bancaria, contrato y acceso anónimo.
- **PASS:** 22 comprobaciones de Auth → Edge desplegada → SQL → Storage reales:
  admin con pago, superadmin, roles denegados, RPC sin suplantación, concurrencia,
  copia exacta, acuse estable, actor, compatibilidad y dos archivos privados
  conservados byte a byte. [Resultado HTTP](http-remoto.resultado.json).
- **PASS:** tipos de tabla/RPC cotejados con generación remota; fuente SQL y
  handler/index desplegados idénticos. Base reconstruida sin clientes reales:
  113 tablas, 649 funciones coincidentes y 12 políticas Storage.
- **PASS:** advisors sin nuevos WARN/ERROR. Solo INFO de RLS sin policies en la
  copia privada, deliberadamente inaccesible por API. [Resultado](advisors.resultado.json)
  y [explicación de Supabase](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- **FAIL heredado:** la matriz RLS global ya falla sin esta migración: supuestos
  antiguos de F2 frente a F4, campos ampliados de métricas, fixtures y una firma
  obsoleta de `convertir_lead_externo`. Ambas corridas: 44 aserciones fallidas y
  la misma interrupción fatal en D-13; cero fallos nuevos hasta ese punto.
  [Comparación antes/después](rls-global.resultado.json). Lo posterior a la
  interrupción no se acredita. Ver el resumen final en `VERIFICACION.json`.
  El gate de contratos no sustituye ni declara aprobada la matriz global.

La rama autorizada `urjpvkbjvpraegrmdnos` se eliminó el 16/09 a las 01:38 UTC
(15/09, 20:38 Lima), con readback de ausencia. Coste estimado: US$0,0331,
incluida la pausa pedida. No se eliminaron otras ramas ni servicios locales.

## Revisión independiente y decisiones

El cierre en GitHub detectó problemas previos de portabilidad/sincronización
del banco. Se corrigieron las pruebas y se fijaron dos workers E2E en CI:
[causas y evidencia](CI.md). Los resultados del commit final acompañan el
artefacto en `releases/`; no reutilizar un ZIP de un Main anterior.

Claude devolvió CHANGES_REQUESTED. Se incorporaron el cierre de las RPC legacy,
protección TRUNCATE, copia de idempotencia, detección de dependencias CASCADE/SET NULL
nuevas, mensaje de concurrencia, guardas de ficha y actualización de cachés.
Los mensajes desconocidos vuelven a quedar ocultos; los públicos de la Edge usan
`ContratoEliminacionError` para conservar el motivo de rechazo sin filtrar errores crudos.
La segunda revisión agregó guardas de UUID/acción FK y clasificación HTTP 409.
[Decisiones y evidencia de las dos revisiones](REVISION.md).

El catálogo productivo se comprobó el 15/09: las únicas cascadas son cronograma,
documentos, titulares y cuentas; SET NULL afecta a leads/altas idempotentes.
No hay dependencias en cascada de las cuotas. La única columna de ruta en esas
tablas es `documentos.storage_path`. Los triggers PDF/documentos inspeccionados
solo bloquean modificaciones; ninguno encola borrados. No hay jobs Cron de
limpieza de esos objetos. Las referencias quedan expresamente bajo retención.

## Instalación productiva y publicación pendiente

Miguel autorizó «ok hazlo para poder publicar» después de recibir los dos SQL
exactos y el artefacto. Se promovieron literalmente las migraciones ensayadas:
registros remotos `20260916024417` y `20260916024423`. No se ejecutó un db push
general. El SQL fuente conserva sus nombres y huellas aprobados.

Edge `crm-contrato-pdf-v2` versión 18 ACTIVE, con `verify_jwt=true` como antes;
sus nueve archivos coinciden byte a byte con el commit `2145f27`.
PASS: huella SQL final, RLS/grants, tres triggers de protección/auditoría,
Admin/Superadmin con contrato nulo, actor nulo rechazado y accesos directos
anon/authenticated denegados. Cinco comprobaciones HTTP PASS: Edge sin sesión,
CORS, RPC anónima denegada, auditoría privada y disponibilidad del CRM existente.
594 contratos, 5.320 cuotas y 26 inversiones de `crm.inversiones` antes/después;
cero auditorías y cero eliminaciones reales durante la verificación.

Advisors: cero nuevos WARN/ERROR; solo el INFO esperado de RLS sin policies para
la nueva copia privada. La matriz RLS global mantiene la limitación documentada.
El ensayo completo Auth → eliminación → Storage corresponde a la rama sintética;
no se repitió sobre contratos de clientes reales.

**Pendiente:** publicar la interfaz desde Main verificado mediante invocación
humana de `/release-crm` (Claude) o `$release-crm` (Codex). La regla está en
[SKILL.md](../../../.claude/skills/release-crm/SKILL.md): «solo Miguel lo invoca
con `/release-crm`». La actualización de actas requiere reconstruir el ZIP desde
el nuevo Main antes de publicarlo; no usar un manifiesto de otro commit.

## Procedimiento de activación y pausa

Los pasos 1, 2 y la instalación SQL/Edge del paso 4 ya están completados.

1. Obtener conformidad al SQL exacto (regla del vault: mostrar SQL primero).
2. Ensayo remoto completado en la rama autorizada, con datos ficticios. Usar
   exactamente ambos archivos cuyas huellas figuran en `VERIFICACION.json`.
3. Usar únicamente el artefacto limpio del commit sincronizado con
   `avancecorp/main`, comprobando su manifiesto y SHA-256.
4. Instalar solo los dos SQL indicados, desplegar `crm-contrato-pdf-v2` y publicar el frontend por el
   procedimiento del proyecto. Durante el intervalo, una Edge anterior falla
   cerrada al intentar la ruta antigua. El resto de operaciones PDF sigue vigente.
   No ejecutar un `db push` indiscriminado: el historial contiene otras propuestas
   que no forman parte de esta activación. El despliegue web requiere la
   invocación humana de `/release-crm` según `CRM-Avance-Corp/CLAUDE.md`.
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
