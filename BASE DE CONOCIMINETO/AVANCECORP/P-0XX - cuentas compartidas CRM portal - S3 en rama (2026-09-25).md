# P-0XX: cuentas compartidas CRM y portal — S3 en rama

**Fecha:** 2026-09-25. **Estado:** S3 ensayado en la rama privada
`p0xx-cuentas-unificadas-20260925` (`hhpjiygytwoayxymziqo`). Ningún cambio
de base de datos se hizo en producción; las pantallas no se publicaron.

## Regla de pago

La instrucción de pago de un contrato es `crm.contrato_cuentas_pago`, incluso
si la cuenta vinculada ya fue versionada e inactivada. La pantalla Pagos de
`miavance.com/public_html` consulta `crm.cuentas_pago_contratos_fn` para la agenda
y el resumen completo. No lee casillas bancarias de `public.perfiles`. Un contrato
sin vínculo muestra «Sin cuenta de pago — requiere conciliación», aun si sus
cuotas históricas están pagadas. Pago manual, importación de Excel y exportación
quedan bloqueados si la cuenta no existe o la consulta falla.

La migración `20260925194026_p0xx_pagos_solo_cuenta_contractual.sql` agrega dos
triggers a `cronograma_pagos`: prohíben INSERT pagado y UPDATE hacia pagado sin
vínculo coherente del mismo cliente y moneda. Protegen también escrituras que
no usan la pantalla. Se ejecutan después del trigger documental 00. La función
es `SECURITY DEFINER`, con `search_path=''` y mensaje sin datos bancarios.

## Alta contractual del Portal

Admin y Analista eligen explícitamente una cuenta activa de la moneda, tomada
del ledger por `crm.cuentas_bancarias_cliente_fn`. El selector enmascara número y
CCI y descarta respuestas viejas si cambia cliente o moneda. El alta usa
`crm.crear_contrato_con_cuenta_pdf_v2` con una clave de idempotencia estable
durante el modal, de modo que contrato, cronograma, vínculo y PDF nacen juntos.
La función antigua `public.crear_contrato` conserva su permiso por F5.c y por
otros flujos históricos; si un consumidor la usa para crear sin vínculo, Pagos
queda bloqueado. Un futuro cambio de contrato API exige revisar F5.c y semillas.

## Evidencia y pendientes

Ensayos SQL en la rama, con datos ficticios y reversión: pago sin vínculo
rechazado en INSERT y UPDATE; pago con vínculo aceptado; alta contractual como
`authenticated` produjo contrato, cronograma y vínculo. El test anterior con
JWT simulado comprobó reintento idempotente. Ambos triggers están habilitados.
El portal pasó 116/116 pruebas Node; CRM 4.433/4.433 pruebas, lint, typecheck y
build. El advisor no añadió hallazgos por S3. El banco Playwright del Portal
usa una cuenta de producción y no se ejecutó contra esta rama.

Conciliación sin cambios desde S1: 3 contratos sintéticos activos pendientes.
`supabase/scripts/p0xx/proyeccion-conciliacion-activos.sql`, ejecutada con SELECT
en producción, proyecta 23 activos tras el eventual backfill: 16 sin cuenta
(2 registros de demostración) y 7 con varias candidatas. El reporte real se
repite después del merge manual. En la rama, la consulta de validación halló
1 sección de perfil válida sin equivalente activo porque comparte CCI con una
cuenta CRM de datos distintos. La proyección real contiene 3 conflictos de ese
tipo; se dejan a operaciones y no se reemplaza una cuenta contractual a ciegas.

La lectura de producción del 25/09 identificó los tres conflictos de mismo CCI,
sin exponer número de cuenta, CCI ni documento del beneficiario:

| Cliente | DNI | Moneda | Diferencia perfil ↔ CRM | Contratos que usan la cuenta CRM |
|---|---|---|---|---:|
| RAMIREZ MONTES LUIS | 00891060 | PEN | Número de cuenta | 1 |
| RIVERA OLAZABAL ARQUIMEDES | 27688865 | PEN | Indicador de otro titular, nombre y documento del beneficiario | 1 |
| SINARAHUA GRATTELLY NATALY MARGARITA | 44757523 | PEN | Nombre del banco | 1 |

Operaciones debe confirmar la instrucción vigente de cada uno. Si corresponde
corregirla, registrar una nueva versión por la RPC; los contratos existentes
conservan su cuenta vinculada. No copiar automáticamente los campos de perfil.
El caso testigo real y la vista publicada del Portal no se pueden validar en
la rama sin copiar datos reales, lo que Miguel descartó.

Relacionadas: [[P-0XX - cuentas compartidas CRM portal - S1 en rama (2026-09-25)]] ·
[[P-0XX - cuentas compartidas CRM portal - S2 en rama (2026-09-25)]] ·
[[Cuentas bancarias por contrato]] · [[Arquitectura del portal]].
