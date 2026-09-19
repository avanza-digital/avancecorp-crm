---
tags: [crm, conversion, auth, incidente]
fecha: 2026-09-19
estado: publicado
---

# Conversión: credencial interna de acceso

Seguimiento de [[Conversion de lead con Nueva inversion - preparado 2026-09-19]].

Al crear el acceso Avance, el usuario recibió «No se pudo completar el acceso.
Retoma esta misma solicitud». La solicitud estaba preparada, sin usuario Auth,
perfil ni inversión confirmada. La reserva seguía siendo recuperable.

## Causa confirmada

Los logs de Auth del 19/09 entre 18:49 y 18:52 UTC registraron HTTP 403
`bad_jwt` en `/admin/users`: token con número de segmentos inválido. El digest
de la credencial del runtime coincide con una clave moderna `sb_secret_`.
El código enviaba esa clave como Bearer junto a una apikey pública.

Una consulta GET a un UUID inexistente reprodujo el fallo sin modificar datos:
cabeceras anteriores → 403; clave secreta solo en `apikey` → 404
`user_not_found` (autorización aceptada); service JWT legacy en ambas → 404.
Contrato oficial: https://supabase.com/docs/guides/functions/auth-headers.

## Corrección

`crm-inversion-portal` y `crm-inversion-bienvenida` usan la clave de servicio
en `apikey` para sus llamadas privilegiadas. Las claves `sb_secret_` no se
envían como Bearer; se conserva el Bearer del JWT legacy. Las llamadas del
usuario mantienen su JWT y la clave pública, incluyendo la comprobación de
permisos previa a cualquier llamada privilegiada.

La recuperación sigue usando la misma solicitud y la marca de su reserva.
La corrección no requiere SQL ni un nuevo frontend. No cambia credenciales,
roles, importes, datos de clientes, plantilla ni destinatario del correo.

## Verificación previa a publicación

- PASS: reproducción HTTP real de solo lectura, sin clientes de prueba en producción.
- PASS: `npm run test:edge-preflight`: 88 + 12 + 4 + 15 pruebas y Deno check.
- PASS: 8 casos nuevos fallaban antes del arreglo y pasan después; alta,
  recuperación y correo ya registrado con clave moderna y JWT legacy.
- PASS: rechazo de sesión/ámbito sin usar la clave de servicio; bienvenida
  conserva el proveedor y la misma clave de idempotencia.
- PASS: el gate incluye ahora el typecheck de `crm-inversion-portal/index.ts`.
- Revisión independiente: CHANGES_REQUESTED por falta de evidencia del alcance
  y de PostgREST. El PRIMARY trazó el recorrido vigente y comprobó que sólo
  estas dos Edges aplican a acceso/bienvenida; la Edge de documentos ya era
  compatible. La sospecha de otros endpoints afectados no se confirmó.
- PASS: GET a `auth_usuario_por_correo_fn`, RPC STABLE de producción, con correo
  inexistente `.invalid`: clave secreta moderna y legacy → 200, `id: null`;
  clave pública → 401. Se completó la evidencia solicitada por el reviewer.
- NOT RUN: conversión de un cliente real como prueba; corresponde al usuario
  reanudar su solicitud una vez publicada la corrección.

Las pruebas del release anterior verificaban el banco y las fronteras de las
Edges, pero no esta combinación concreta de clave opaca y cabeceras en el
runtime de producción. Ese es el caso añadido en esta corrección.

## Publicación efectiva

Miguel solicitó publicar con urgencia. El PR #27 recibió APPROVED de
`miguejbs98` a las 19:15:08 UTC y esa cuenta lo integró a las 19:15:35 UTC.
Main local y `avancecorp/main` se verificaron limpios e iguales en
`7035feefbff5ade3e8a7b0a02c48c46fdac8f905`. Los siete archivos del paquete
coincidían exactamente con la corrección probada `f9ca932f0f169eee6e39da816f25926d334b795c`.

Publicadas el 19/09 a las 19:17 UTC (14:17 Lima):

| Función | Versión | verify_jwt | SHA-256 del bundle |
|---|---:|---|---|
| crm-inversion-portal | 4 | true | deaa99cc4e7e07d478a56cf1127d9582fb3ced8a7305066ac236c8b79c5e783d |
| crm-inversion-bienvenida | 2 | false, autenticación propia preservada | 59160895c8b12479c71bf465e7c96db9dbde62dbb6fa77eac495d92ac6a2e042 |

- PASS: descarga posterior de ambas Edges coincide byte a byte con Main.
- PASS: CORS devuelve 204 y una petición sin sesión devuelve 401 en ambas.
- CI `preflight`: PASS. Los jobs generales `verify` y `e2e` seguían ejecutándose
  al comprobar el PR ya integrado por Miguel; no se les atribuye PASS.
- SQL y frontend conservados. No se creó otro banco temporal ni nuevo coste.
- Indicación al usuario: reintentar el acceso en la misma solicitud guardada.

Evidencia privada saneada: `releases/cierre-conversion-inversion-20260919/correccion-acceso/`
en la carpeta original del CRM. Incluye recibo de publicación, pruebas HTTP,
revisión y patch; excluye las claves recuperadas durante el diagnóstico.

Seguimiento fuera del arreglo urgente: distinguir fallos internos de servicio
de errores de sesión al clasificar HTTP y consolidar las cabeceras compartidas.

## Recuperación observada en producción

Después de informar al usuario que podía reintentar, la consulta de solo lectura
de su solicitud encontró un único usuario Auth, un único perfil y el estado de
acceso `enlazado`. La inversión seguía `preparada`, pendiente de confirmación por
el usuario. Esto confirma que el bloqueo de creación del acceso quedó resuelto
en el caso real. El PRIMARY sólo observó el resultado: no creó el acceso ni
confirmó la inversión mediante herramientas.
