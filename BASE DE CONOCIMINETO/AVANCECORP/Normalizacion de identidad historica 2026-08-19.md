# Normalización de identidad histórica — 2026-08-19

## Corrección aplicada

Se normalizaron seis perfiles de cliente que habían sido creados desde el flujo histórico Lead → Cliente antes de que la conversión solicitara los campos separados.

- Se completaron `apellidos` y `nombres` con la información que ya constaba en el nombre registrado.
- `nombre_completo` quedó en el formato canónico que utiliza pagos: `APELLIDOS NOMBRES`.
- También se corrigió una `Ñ` afectada por la distribución de teclado (`;`), sin alterar la identidad del registro.
- La corrección quedó trazada por el `audit_log` de perfiles.

## Límite de seguridad

Un perfil histórico conserva únicamente el texto `ALEX`: no hay apellidos en el lead, el perfil ni otra fuente interna. Se deja pendiente de completar por una persona autorizada; no se crean apellidos ficticios para no afectar pagos.

## Prevención

Desde el cambio de [[PDF contractual privado e inmutable 2026-08-17]], la conversión de un lead muestra y exige confirmar nombres, apellido paterno y apellido materno antes de crear el cliente.
