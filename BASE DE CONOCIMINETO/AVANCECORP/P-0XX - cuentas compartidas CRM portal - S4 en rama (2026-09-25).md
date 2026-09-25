# P-0XX — El propio cliente ve sus cuentas en miavance.com

Estado al 25/09/2026: **solo en la rama Supabase** `p0xx-cuentas-unificadas-20260925`
(`hhpjiygytwoayxymziqo`) y en los archivos locales. Sin merge ni publicación.
Continúa [[P-0XX - cuentas compartidas CRM portal - S1 en rama (2026-09-25)]],
[[P-0XX - cuentas compartidas CRM portal - S2 en rama (2026-09-25)]] y
[[P-0XX - cuentas compartidas CRM portal - S3 en rama (2026-09-25)]].

## Decisión de producto y arquitectura

La ficha administrativa y Pagos ya usan el ledger, pero el propio cliente de
`miavance.com/perfil.html` solo mostraba identidad. Se añadió una lectura de sus
cuentas activas desde `crm.cuentas_bancarias`: hecho privado existente, wrapper
que comprueba `auth.uid()`/perfil cliente activo y RPC pública sin parámetros.
Número y CCI llegan al navegador solo enmascarados. La pantalla tiene estados
vacío/error y aclara que la instrucción para un pago puede ser la versión
histórica vinculada a cada contrato. No hay lectura bancaria nueva de `perfiles`.

Los campos comunes de identidad (nombre, documento, correo, teléfono, asesor)
ya salen de la misma fila `public.perfiles` en CRM y portal; no se añadió un
sincronizador. El correo de acceso usa la Edge compartida
`corregir-correo-cliente`; la auditoría de producción de solo lectura encontró
0 divergencias perfil/Auth entre 514 clientes. Un cliente conserva en CRM la
asignación a un analista inactivo que el portal omite por regla de presentación.

## Verificación y pendientes

- `verify-s4-portal-cliente.sql`: `S4_PORTAL_CLIENTE_OK`. El testigo ficticio
  ve BCP PEN `…6087` y USD `…9168`; otro cliente ve lista vacía y un miembro
  del CRM recibe 42501. Sin grants directos de tabla a `authenticated`.
- `test-perfiles-cuentas.sql`: `CUENTAS_TX_OK` en la rama. El seed y el gate RLS
  históricos se adaptaron a perfiles bancarios de solo lectura. Preflights de
  ambos pasaron; la matriz RLS completa no se ejecutó (faltan credenciales de
  branch y banco limpio).
- Portal: 116/116 tests; sintaxis JS y `git diff --check` pasaron. El advisor
  de seguridad agrega un WARN esperado por la RPC pública `SECURITY DEFINER`
  accesible a `authenticated`, con autorización estricta por `auth.uid()`.
- La reversa de S1 bloquea cuentas, cronograma y vínculos antes de sus
  comprobaciones; ejecutada en la rama dentro de `ROLLBACK`, dejó 3 cuentas y
  2 vínculos intactos.
- Antes de publicar: revisar diff completo, resolver los 3 conflictos del
  mismo CCI con Operaciones, conciliar 23 contratos activos proyectados sin
  vínculo y completar el merge manual de Miguel. Producción no se alteró.
