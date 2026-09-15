# Corrección administrativa del correo de clientes

## Comportamiento

En el portal, un administrador o superadministrador activo abre Clientes →
Editar, escribe el correo y un motivo y guarda. El cliente entra con el correo
nuevo y su contraseña existente. Los demás roles no pueden ejecutar esta acción.

La Edge obtiene el actor del JWT verificado y prepara una operación privada.
La API administrativa de Auth actualiza el email y la identidad. Un trigger
diferido valida el estado final y actualiza perfil y auditoría en la misma
transacción. Un rechazo revierte el cambio completo; una respuesta perdida se
resuelve leyendo el resultado, sin compensaciones ciegas.

## Verificación previa a publicar

- PASS: 9 grupos con Auth y Postgres reales en banco local aislado: admin y
  superadmin, login nuevo/misma clave, rechazo del correo anterior, roles,
  duplicados, RPC privilegiada, escritura directa, rollback, reintento,
  respuesta perdida y concurrencia.
- PASS: 3 pruebas del núcleo del portal y 2 del HTML y módulo reales con DOM.
- PASS: CRM lint, tipos, 3600 pruebas, build, bundle y duplicación.
- PASS: CRM Playwright, 190 aprobadas y 26 omitidas.
- FAIL preexistente: 2 expectativas antiguas del banco global del portal
  (`asiento-operaciones.test.mjs` y `contrato-pdf-servidor.test.mjs`). Se
  verificaron contra HEAD previo; no las introduce esta corrección.
- NOT RUN: revisión independiente completa. El wrapper `scripts/claude-review`
  falló inicialmente y el reintento autorizado no devolvió un VERDICT válido.
  No se interpreta como aprobación.

## Instalación autorizada

Miguel aprobó expresamente el SQL `20260915173423` y una rama temporal a
US$0,01344/h, con eliminación al terminar. El historial productivo no se
reproduce completamente en ramas nuevas; el ensayo reconstruye el esquema
vigente sin copiar clientes. Solo se publica la migración aprobada.

Las propuestas `20260908221500` y `20260908221501` nunca se instalaron y quedan
supersedidas; no aplicarlas junto a esta migración. Las credenciales, dumps y
datos sintéticos quedan fuera de Git. El acta de publicación registra el
resultado remoto efectivo, sus límites y la eliminación de la rama.
