# Operación de Inteligencia Gerencial V2

## Contratos vigentes

- `monto_estimado` es obligatorio, positivo y de hasta dos decimales. La migración aborta si encuentra historia incompatible; no inventa ceros.
- PEN y USD se agregan y presentan por separado. V2 no aplica conversión ni publica un total monetario mixto.
- El SLA principal comienza en el ingreso o reapertura del ciclo y no se reinicia por asignación, transferencia o parqueo.
- El SLA de asignación sigue existiendo como indicador operativo de cada tramo y se etiqueta como tal.
- No existe descuento de pausas. Parqueos y transferencias continúan consumiendo el SLA global.

## Seguridad de las RPC

Las RPC expuestas V1 y V2 pertenecen a `crm_metricas_bridge`, un rol `NOLOGIN`, `NOINHERIT`, sin `SUPERUSER`, `BYPASSRLS`, creación de roles o acceso directo a tablas. El puente solo puede ejecutar `private.metricas_distribucion_leads_autorizada`, que vuelve a validar `auth.uid()`, Gerencia activa o lector global antes de consultar.

V1 se conserva para rollback del frontend. El frontend nuevo consume `crm.metricas_distribucion_leads_v2_fn`.

## Orden de despliegue

1. Aplicar la migración en un branch de Supabase.
2. Ejecutar el oráculo `supabase/scripts/test-metricas-distribucion-leads.sql`, RLS y advisors.
3. Fusionar la migración. El frontend anterior continúa usando V1.
4. Desde `CRM-Avance-Corp/`, ejecutar `npm run release:crm`.
5. Verificar el manifiesto con `npm run release:crm:verify -- releases/<release>.manifest.json`.
6. Conservar el release anterior y desplegar solo el ZIP aprobado en `crm.miavance.com`.
7. Verificar HTML, assets con hash, login y respuesta JSON V2. El ZIP debe seguir dando 404 públicamente.

## Rollback

- Ante un fallo de interfaz, desplegar el ZIP y manifiesto del release anterior. La RPC V1 permanece disponible.
- No eliminar las columnas de SLA global ni reescribir el ledger: contienen historia adquirida después de la migración.
- Ante un incidente específico del endpoint V2, revocar temporalmente su ejecución a `authenticated` y volver al frontend V1.
- Confirmar el SHA-256 del artefacto anterior antes de desplegarlo.

## Puerta de producción

- Cero registros incompatibles con `monto_estimado`.
- Vendedor y `anon` denegados en V1/V2; Gerencia y lector global permitidos.
- `crm_metricas_bridge` sin login, atributos privilegiados ni `SELECT` sobre el ledger.
- Una transferencia conserva el mismo `sla_global_iniciado_en` en ambos episodios.
- El resumen global incluye ciclos aún no asignados y no descuenta parqueos.
- Panel, contrato runtime y RPC reportan JSON V2.
- ZIP, manifiesto y release anterior conservados fuera del web root.
