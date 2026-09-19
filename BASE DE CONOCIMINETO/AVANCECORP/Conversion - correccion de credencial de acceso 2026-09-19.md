---
tags: [crm, conversion, auth, incidente]
fecha: 2026-09-19
estado: validado-pendiente-publicacion
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
- Revisión independiente y publicación: pendientes al preparar esta nota.
- NOT RUN: conversión de un cliente real como prueba; corresponde al usuario
  reanudar su solicitud una vez publicada la corrección.

Las pruebas del release anterior verificaban el banco y las fronteras de las
Edges, pero no esta combinación concreta de clave opaca y cabeceras en el
runtime de producción. Ese es el caso añadido en esta corrección.
