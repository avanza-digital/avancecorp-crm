# P-0XX — cierre productivo verificado, 26/09/2026

## Resultado

**Completado el alcance técnico aprobado.** CRM y portal comparten las cuentas
canónicas y los pagos usan la cuenta vinculada al contrato. Las tres diferencias
históricas pendientes quedaron resueltas y se retiraron los dos avisos de
seguridad introducidos por P-0XX.

Miguel aprobó expresamente aplicar los dos SQL finales en producción, incluida
la reparación puntual de una celda bancaria legada. El código quedó integrado
por el PR #109 en Main `1cb79aecce07ef7e4b66aa938931e81e79743c7e`; Main local de
la copia limpia y `avancecorp/main` coincidían antes de aplicar.

## Entrega por fase

| Fase | Cambio y decisión | Filas y pantallas |
| --- | --- | --- |
| S1 — lectura y backfill | Cuentas válidas del perfil al ledger; vínculos únicamente con una candidata inequívoca; lectura desde cuentas activas. | 241 cuentas y 257 vínculos. Ficha de cliente con firma de RPC conservada. |
| S2 — escritura | Validador común y registro versionado, autorizado para analistas/Gerencia según ámbito y plazo; el patch general rechaza claves bancarias. | Fichas CRM, Clientes/Usuarios/Analista del portal y altas Edge compatibles. Sin nuevas escrituras bancarias habituales en perfiles. |
| S3 — pagos | Cuenta contractual obligatoria; bloqueo explícito si falta vínculo, también en el servidor. | Pagos, importación y exportes. 23 contratos reportados: 21 operativos y 2 demo. |
| S4 — portal personal | Lectura de las cuentas propias derivada de la identidad autenticada, con máscaras y estado vacío. | Perfil personal de miavance.com; valores compartidos con CRM. |
| Cierre — excepciones | Dos entradas INVOKER con autorización privada DEFINER; dos nuevas versiones de cuenta y corrección excepcional del nombre de un banco legado. | 2 cuentas adicionales; 1 celda bancaria legada corregida; 0 vínculos cambiados. |

Las pantallas ya estaban publicadas. Este cierre modifica únicamente permisos y
datos del servidor; conserva los artefactos de frontend previamente publicados.

## SQL aplicado y auditoría

- Migración canónica: `20260926145330_p0xx_cuentas_wrappers_invoker.sql`.
  Registro productivo: **`20260926172402 p0xx_cuentas_wrappers_invoker`**.
- Conciliación: transacción operativa con parámetros privados y huellas del
  estado revisado. Se ejecutó el SQL exacto aprobado, con validación final de
  cero diferencias; su repetición produjo cero cambios.
- Las dos versiones nuevas usan la RPC oficial y origen `portal`. Sus IDs
  figuran en `private.backfill_cuentas_p0xx`, marcas `conciliacion:p0xx:*`,
  con referencia a la versión anterior para la reversa.
- Actor técnico de las tres reparaciones: **ADMINISTRADOR AVANCE CORP**,
  superadmin activo. Cada INSERT tiene su registro de auditoría identificado;
  la modificación excepcional de banco tiene un UPDATE auditado.
- El trigger `trg_perfiles_banca_solo_lectura` terminó habilitado (`O`).
  La excepción no instala una sincronización ni un permiso permanente.
- Los cuatro vínculos de los tres clientes conservan sus huellas completas.
  Se mantienen los dígitos, CCI y versiones históricas usadas por sus contratos.

El backfill S1 conserva sus 498 INSERT auditados originales, identificados por
`marca_actor='migracion:p0xx:s1'` (usuario SQL nulo). La conciliación posterior
sí tiene el actor administrativo explícito indicado arriba.

## Verificación final

| Verificación | Resultado |
| --- | --- |
| Datos bancarios válidos del perfil sin equivalente activo | **501 válidos; 0 sin equivalente; 0 con mismo CCI y datos distintos** |
| Primera conciliación productiva | **2 cuentas nuevas + 1 nombre de banco corregido** |
| Segunda ejecución del mismo SQL | **0 cuentas nuevas + 0 cambios de banco** |
| Ficha del caso 02650333 y RPC personal autenticada | **BCP PEN …6087 / BCP USD …9168**, lectura y máscaras PASS |
| Llamadas anónimas a lectura pública y autorizador privado | Rechazadas, PASS |
| Permisos/cuerpos de las ocho funciones contrastados con rama | Coinciden; solo las dos entradas son INVOKER, PASS |
| Acceso directo de authenticated a tabla bancaria | SELECT/INSERT/UPDATE/DELETE: **false** |
| Auditoría y trigger legado | 2 INSERT identificados, 1 UPDATE de banco; trigger habilitado, PASS |
| Contratos activos sin vínculo | **23: 16 sin cuenta y 7 ambiguos**, todos en el reporte |
| Security Advisor | **0 hallazgos nuevos; retirados exactamente los 2 avisos de P-0XX** |
| Performance Advisor | **0 hallazgos nuevos**, comparación individual por metadatos y detalle |
| Ensayos en rama | SQL S1/S2/S3/S4, idempotencia, ambigüedad, reversa y modos existente/nueva/perfil: PASS |
| Permisos por API en rama | **287 HTTP/RLS + 10 HTTP específicos: PASS** |
| Scripts y preflights finales | check:scripts, seed:preflight, test:rls:preflight, sintaxis Node y diff: PASS |
| GitHub del PR #109 | preflight, cambios, app-check y verify: **4 SUCCESS** |
| Frontend de P-0XX publicado el 25/09 | Build, typecheck, lint y **4.440 tests PASS**; Docker E2E **274 PASS / 26 SKIP / 0 FAIL**; portal **112 PASS** |

No se repitió la suite frontend para el cierre SQL. Los números de esa fila
pertenecen al artefacto publicado y a su acta del 25/09. Las dos tentativas de
revisión independiente no devolvieron un VERDICT válido: **NO COMPLETADA**,
sin atribuirles un PASS. La revisión propia y los controles reales constan arriba.

Remediación del aviso retirado:
[funciones SECURITY DEFINER ejecutables por authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
Los avisos preexistentes del proyecto no se presentan como resueltos por P-0XX.

## Reporte para Operaciones

La lista nominal actualizada, con cliente, DNI, moneda y analista, queda privada:

- `_DEV_NO_SUBIR/releases/p0xx-conciliacion-actual-20260926.csv`
- `_DEV_NO_SUBIR/releases/p0xx-conciliacion-actual-20260926.md`

El censo validado dio 23, frente a la estimación inicial aproximada de 22.
La consulta original cuenta todos los activos: **21 son operativos** (14 sin
cuenta y 7 ambiguos) y **2 están marcados como demo** (ambos sin cuenta).
Los 23 ya estaban incluidos en la proyección validada previa a S1. El reporte
ahora incluye es_demo para distinguirlos; un demo carece de DNI y figura como
«Sin DNI registrado». No se inventó ese documento ni se excluyeron filas para
alterar el total. Los pagos y exportes continúan bloqueados hasta conciliar.

Las tres discrepancias de perfil adicionales se cerraron en esta entrega.
Este cierre no autoriza cambiar retroactivamente una instrucción contractual
inmutable cuando Operaciones corrija la titularidad de una cuenta vigente.

## Recuperación, entorno y deuda

La reversa fue ensayada con datos ficticios: crea versiones con los valores
originales, conserva los vínculos y rechaza cuentas usadas en nuevos contratos.
SQL exactos, huellas, ejecución y advisors antes/después están en
`_DEV_NO_SUBIR/releases/p0xx-crm-publicado/`.

La rama propia `hhpjiygytwoayxymziqo` se eliminó el **26/09 a las 12:32:54 Lima**
después de verificar producción, y se confirmó su ausencia. Costo de cómputo
estimado por la tarifa aprobada: **US$0,3503**; no es una factura del proveedor.
El código y los ensayos sintéticos permanecen versionados para reproducirlos.

Deuda acordada: conciliar los 21 contratos operativos y revisar los 2 demo; retirar columnas
bancarias legadas y su trigger después de un cierre estable; retirar el modo
`perfil` en un trabajo posterior. Número P definitivo pendiente de Miguel.

Antecedentes: [publicación original](ACTA-PUBLICACION.md) y
[ensayo de las excepciones](CIERRE-EXCEPCIONES.md).

