# P-0XX: cuentas compartidas CRM y portal — S2 en rama

**Fecha:** 2026-09-25. **Estado:** S2 ensayado en la rama privada
`p0xx-cuentas-unificadas-20260925` (`hhpjiygytwoayxymziqo`). No se modificó
producción ni se publicaron las pantallas. Número P definitivo pendiente de Miguel.

## Regla de escritura

`crm.cuentas_bancarias` es la única fuente de cuentas de cliente. Las 14 columnas
bancarias de `public.perfiles` quedan como legado de solo lectura: el trigger nuevo
impide modificarlas y `crm.actualizar_cliente_gerencia` rechaza esas claves con un
error explícito. No se borraron columnas ni el trigger `perfiles_cuentas_no_vaciar`.

`crm.registrar_cuenta_cliente` autoriza por cartera y restringe la corrección a
analistas y Gerencia/operaciones. Un vendedor con rol `comercial` ve las cuentas de
su cartera, pero no registra versiones ni recibe «Corregir datos» desde la ficha
360. La ficha CRM y las secciones bancarias de
Admin y Analista en `miavance.com/public_html` consultan el ledger mediante RPC;
las cuentas aparecen enmascaradas, con origen y fecha, y un cliente sin cuentas
recibe un estado vacío. El alta de cliente con una o dos monedas se hace en una
transacción de perfil y cuentas desde las Edge. Un resultado de red incierto conserva
la identidad Auth para conciliación, en lugar de borrarla a ciegas; primero se
reintenta la misma RPC idempotente. El origen técnico `portal` se muestra como
«Ficha de cliente» porque también lo usa la ficha del CRM.

El validador `private.validar_cuenta_bancaria(jsonb)` reemplaza la validación
duplicada en el alta contractual, el alta de cliente y la corrección de ficha.
El registro mantiene la versión anterior inactiva y crea otra si cambian los datos
para el mismo CCI, bajo el mismo advisory lock que el alta de contrato. Los reintentos
idénticos devuelven la fila vigente; no reactivan versiones históricas.

## Vigilancia contractual y auditoría

`crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)` conserva firma, permisos y
modos `existente`, `nueva` y `perfil`. La extracción del validador modifica su
cuerpo vigilado por F7: la migración verifica la definición anterior, actualiza la
huella registrada dentro de la misma transacción, reactiva el trigger de F7 y exige
`private.assert_f7_piezas_cerradas()` verde. El replay dejó la nota F7 intacta.

Los inserts bancarios pasan por el trigger de auditoría y guardan `creado_por`
con el usuario verificado. En el alta atómica con `service_role`, la columna
`audit_log.usuario_id` queda nula porque ese trigger usa `auth.uid()`; el actor
queda identificable en `cuentas_bancarias.creado_por` y en `data_despues.creado_por`.
El backfill S1 usa `creado_por = NULL` y marca `migracion:p0xx:s1` en su tabla de
reversa, según [[P-0XX - cuentas compartidas CRM portal - S1 en rama (2026-09-25)]].

## Verificación y pendiente

En la rama pasaron las pruebas SQL de escritura versionada, permisos, alta atómica,
auditoría, reintentos y los tres modos de contrato. La repetición de S2 pasó sin
duplicar la nota de F7. En el código pasaron 112 pruebas de Portal, 4.432 pruebas
unitarias del CRM, el typecheck, lint y build, 96 pruebas del preflight Edge y 15
E2E seleccionados con Docker; el gate de duplicación
global sigue afectado por copias ` 2.tsx/css` de otro trabajo presente en el
working tree compartido. El advisor de seguridad agrega una advertencia WARN
por el nuevo RPC `SECURITY DEFINER` ejecutable por `authenticated`; la autorización
de cartera/rol está dentro del wrapper y se ensayó.

S3 todavía debe llevar la pantalla de Pagos exclusivamente a
`crm.cuentas_pago_contratos_fn`, bloquear pago/exportación sin vínculo y resolver
que los contratos nuevos del portal actualmente se crean con `public.crear_contrato`
sin elegir ni vincular cuenta de pago. La elección de cuenta debe ser explícita si
hay varias candidatas. La Edge legacy de conversión de un lead cuyo cliente ya
existía ignora el bloque bancario, como hacía antes de S2; su respuesta lo marca
con `ya_existia`, pero cualquier pantalla que reactive esa ruta deberá aclarar
que la cuenta se elige al contratar. Después de un cierre estable, otro P retirará las columnas
legacy y el modo `perfil` del alta contractual.

Relacionadas: [[Cuentas bancarias - ledger vs casillas del perfil]] ·
[[Cuentas bancarias por contrato]] · [[Arquitectura del portal]].
