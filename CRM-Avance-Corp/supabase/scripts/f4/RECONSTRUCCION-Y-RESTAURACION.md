# Reconstrucción y recuperación F4

Este procedimiento corresponde exclusivamente a datos sintéticos locales.
No autoriza aplicación en producción. El ensayo completo se realizó con
Supabase CLI 2.117.0, PostgreSQL 17.6 y postgres-meta v0.99.0.

## Reconstrucción limpia

1. Crear el proyecto local separado `avancecorp-f4-reconstruccion` con puertos
   API 57321, DB 57322 y auxiliares 57320/57323/57324. Crear la red Docker
   `avancecorp-f4-reconstruccion-red`. No reutilizar ni resetear otro proyecto.
2. Arrancar el stack en esa red; se pueden excluir studio, imgproxy, realtime,
   logflare, vector y supavisor. Conservar Auth/API/Storage y PostgreSQL.
3. Usar la captura privada `schema-prod.sql` del 07/09, **sin filas productivas**.
   Crear previamente `crm_metricas_bridge` NOLOGIN NOINHERIT si falta. Restaurar
   como `supabase_admin` para conservar propietarios/grants originales; no
   sustituirlos por concesiones generales a la API.
4. Configurar `authenticator` con `pgrst.db_schemas='public,graphql_public,crm'`
   y notificar recarga de configuración/esquema a PostgREST. Guardar estado CLI
   privado (modo 0600), nunca en evidencia versionada. `banco-local.mjs` verifica
   URL/puerto/emisor de claves y exige una línea JSON local en `start.log`.
5. Ejecutar `preparar-fixtures.mjs` con `F4_BANCO=reconstruccion`. Crea siete
   usuarios Auth con login real; recupera las nueve parejas Portal/CRM de la
   configuración PUBLICADA mediante `configuracion-publicada.mjs`. No inventar
   parejas para conseguir permisos.
6. Ejecutar `preparar-operaciones-base.mjs` ANTES de instalar: tres leads,
   cuatro contratos, dos cierres, 52 cuotas por RPC reales. Domicilios/correos
   y teléfonos ficticios legales deben cumplir los validadores publicados.
7. Capturar paridad `antes`. Guardar copia SQL pre-F4 con `crearCopiaSql` y
   archivo privado `respaldo-pre-f4.json` (`id`, `nombre`, `archivo`, `fecha`).
   Nombre cerrado `f4_pre_fcuatro_<12 hex>`. La necesitan corpus, finanzas y tipos.
8. Ensamblar la candidata, comparar SHA con el manifiesto y aplicar íntegra
   mediante `aplicar-candidato.mjs`, que usa administrador local. Verificar
   paridad `despues` y estructura: 48 cuerpos, owners/grants/RLS, fuentes/principal.
9. Copiar Portal/PDF con sus scripts específicos. El runtime debe arrancarse en
   **la misma red nombrada**; de otro modo su `db`/API no resuelven el banco.

```sh
/private/tmp/avancecorp-f4-tools/node_modules/.bin/supabase functions serve --workdir /private/tmp/avancecorp-f4-reconstruccion --network-id avancecorp-f4-reconstruccion-red
```

Se usa `policy="per_worker"` predeterminada. No aumentar presupuesto de CPU ni
modificar fuentes/renderer para esconder un fallo de runtime. La candidata puede
instalarse de nuevo únicamente en otra base anterior a F4, no sobre inversiones.

## Recuperación operativa y restauración ensayada

Apagar `inversiones_escritura` toma su candado y espera confirmaciones en vuelo.
Luego las altas/reintentos F4 se rechazan; fuentes y PDF existentes se conservan.
F3 permanece activo. Esto es reversa operativa, no eliminación del modelo instalado.

```sh
F4_BANCO=reconstruccion node CRM-Avance-Corp/supabase/scripts/f4/probar-restauracion.mjs
```

El script exige F4 OFF y hace lo siguiente:

1. Captura huellas/conteos de 133 tablas public/crm/private/auth/storage, cuerpos,
   propietarios, privilegios efectivos y políticas/RLS.
2. Comprueba que F4 apagada rechaza preparación sin alterar historia.
3. Vuelca SQL y restaura en una DB nueva con nombre aleatorio cerrado. Conserva
   owners/grants y compara todas las tablas/cuerpos/ACL/RLS. La ACL de owner por
   defecto y su representación explícita se normalizan con `acldefault`.
4. Archiva el volumen Storage del banco y lo extrae a un volumen Docker NUEVO,
   usando la imagen local ya disponible. No borra ni reemplaza el original.
5. Compara rutas y SHA-256 de todos los archivos y la correspondencia de los
   objetos de Storage con la base restaurada. El ensayo final pasó 6 grupos,
   133 tablas y 27 archivos. Captura temporal: posteriores fixtures no forman
   parte de aquella copia, como en cualquier respaldo de un instante concreto.

Los dumps y tar contienen únicamente fixtures, pero se mantienen privados (0600).
No versionar claves Auth, tokens, archivos de recuperación, logs CLI ni SQL dumps.

**Límites:** la copia SQL omite cron/replicación para no duplicar jobs. No se
presenta como un tercer stack HTTP ni como restauración de servicios externos.
Restaurar a un punto anterior después de inversiones reales requeriría conciliar
operaciones posteriores. No se incluye un DOWN que borre inversiones o reinstale
`UNIQUE(lead_id)` sobre una relación 1:N.

## Antes de una futura aplicación autorizada

- G4 técnico cerrado; renovar recenso antes de tratar datos reales. Las comisiones
  se calculan fuera del sistema. El dato de 14 resueltos + 1 faltante
  productivo pertenece al 07/09 a las 11:32 Lima, no al estado actual.
- Repetir ciclo de branch/seed antes de aplicar y gates/advisors del repositorio.
  Este ensayo local no sustituye los gates remotos de publicación.
- Integrar `avancecorp/main` sin sobrescribir y verificar igualdad de Main local
  y remoto. Publicar únicamente un artefacto desde ese commit. Sin force/release branch.
- Ventana sin escrituras Storage y copia pareada verificada: la transacción agrega
  FK/políticas y usa `lock_timeout=5s`. Un timeout revierte todo; no subirlo a ciegas
  ni aplicar fragmentos. Revisar contención, recapturar guardas y reintentar completo.
- La FK de comprobante impide borrar evidencia referenciada. Un error de borrado
  no se resuelve eliminando filas en `storage.objects` manualmente.
- Mantener F4/F5 OFF hasta el gate y habilitación correspondientes. F2 global ya
  no se puede ejecutar desde que se instala F4, aunque la bandera esté apagada.
