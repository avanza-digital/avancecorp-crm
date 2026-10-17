# Banco de tipo de cambio por venta

Candidatas locales sin publicar. Estado y límites:
[ESTADO.md](../../../docs/plans/tipo-cambio-por-venta/ESTADO.md).
Aceptación por requisito: VALIDACION.md. Operación futura: ACTIVACION.md.

## Entorno

Contenedor exclusivo `avancecorp-tc-20261016`, network none, sin puertos.
`tc_venta` contiene esquema productivo restaurado + fundación vacía M1;
los replays crean clones con nombre propio, aplican las once candidatas y
retiran únicamente su clon en finally. No aplicar guardas otra vez sobre un
banco ya integrado. No dirigir estos scripts a producción u otro contenedor.

El banco histórico anterior tc_venta_historico se conserva como evidencia de
108 hechos/9 tasas. El replay final de 116 hechos con diez candidatas se hizo
en otro clon propio retirado: total numeric S/4 650 700,67, repetición0.
Hechos monetarios/ids para cotejo, personas/contactos/documentos ficticios;
exportaciones sensibles y dump solo en temporal0600, nunca en git.

## Verificaciones desde raíz del CRM

```sh
npm run test:tipo-cambio-venta
npm run test:tipo-cambio-venta:sql
npm run test:tipo-cambio-venta:http
```

SQL: 27 dominio/legado +16 atribución +89 cortes/permisos/escritores/Citas y
cuatro carreras concurrentes. Incluye cierre nativo con reloj simulado,
reversa, firmas, mil pendientes, 10 000 fuentes históricas extra y 600 ventas
que el cierre difiere sin materializar bajo locks. Semillas en réplica;
las RPC de negocio ejecutan triggers normales y constraints diferidos.

HTTP: GoTrue/PostgREST reales con once cuentas ficticias, ocho ámbitos,
privilegios de lectura/PII/escritura y F4 activa preparar/revisar/confirmar,
idempotencia, TC conocido y pendiente/recuperado. Sidecars comparten solamente
el namespace sin red del banco; no abren puertos ni reciben credenciales reales.
Se retiran contenedores, clon y roles técnicos propios en finally.
`auth-migraciones.json` contiene versiones técnicas del dump, no usuarios.
No acredita navegador F4 con Auth real, PDF binario o subida Storage.

Deno:30 casos, fmt/typecheck, consolidación estricta y política legada separada.
E2E de UI: desde app usar `npm run test:e2e:docker`, siempre Docker local.
Sus payloads interceptados no se confunden con las pruebas Auth HTTP.

## Artefactos de contrato y esquema

```sh
node supabase/scripts/tipo-cambio-por-venta/verificar-cortes-local.mjs --replay --fixtures
node supabase/scripts/tipo-cambio-por-venta/verificar-cortes-local.mjs --replay --fixtures-citas
node supabase/scripts/tipo-cambio-por-venta/verificar-http-local.mjs --fixtures-rangos
node supabase/scripts/tipo-cambio-por-venta/generar-tipos-local.mjs
node supabase/scripts/tipo-cambio-por-venta/advisors-local.mjs
```

La primera opción reemplaza solo nueve fixtures originales en
app/src/lib/__fixtures__/capital-valorado. La segunda reemplaza solo cuatro
Citas en app/test-fixtures/capital-valorado; la tercera genera facturacion-rangos
allí desde HTTP nativo. No regenerar por rutina: UUIDs/timestamps pueden cambiar.
Fixtures sintéticos; no exportaciones productivas.

Generación oficial de tipos escribe en el temporal database-candidato.types.ts;
revisar/conciliar con database.types.ts preservando cambios previos y metadata
PostgREST, no copiar a ciegas. Requiere imagen postgres-meta local. Advisors
requiere la CLI Linux2.117.0 previamente descargada en el temporal y verificada
contra digest del release oficial. El script verifica esa integridad y compara
el MISMO clon antes/después, sin instalar ni actualizar el entorno global.
Ver ADVISORS.md para avisos preexistentes y INFO deliberados.

## Activación y reversa

Pruebas no autorizan publicación. Se exige censo actual, cobertura completa,
bundle compatible y huella de preflight por el flujo humano autorizado.
No reactivar/pausar el cron existente. La reversa de persistencia solo sirve
con fundación vacía; integrada o con historia, suspender presentación y
conservar tasas, auditoría y sellos. Un cierre desde octubre con política
suspendida bloquea reactivación automática; ver ACTIVACION.md.

## Censo y gate cloud de publicación

`verificar-censo-local.mjs <configuracion-analitica.json>` prueba conservación
transaccional del censo nativo sin datos personales. El JSON privado incluye
analitica_exenciones, analitica_tope y analitica_sello; no se versiona.

`test-rls.mjs --tipo-cambio-venta-cloud` ejecuta la misma matriz HTTP del banco
local, fijando exclusivamente la referencia de la rama temporal aprobada.
CRM_TC_BRANCH_CREDENTIALS apunta al JSON privado de la CLI, nunca al proyecto
productivo. No reutilizar ese destino en otra tarea sin autorización y guardas.
El despliegue mantiene verify_jwt=true y el secreto de servicio JWT dedicado
CRM_CAPITAL_VALORAR_SERVICE_KEY. Ver acta PUBLICACION-20261017.md.
