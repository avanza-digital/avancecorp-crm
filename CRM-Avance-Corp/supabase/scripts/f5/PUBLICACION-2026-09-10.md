# F5 instalada y verificada, sin activar

Miguel aprobó el SQL correctivo el 10/09: «hazlo. aprobado». La aprobación del
SQL original y del banco temporal ya estaba registrada. Se completó la instalación
mediante merge del banco exclusivo, sin volver a aplicar F4 ni modificar banderas.

## Artefacto y ejecución

- Main local, `avancecorp/main` y remoto vivo coincidían en
  `a884ac3a661d6f10a32bfcb520c7288d0dfa58ea` al construir y comprobar el paquete.
- Paquete: `/private/tmp/avancecorp-f5-paquete-a884ac3a661d/`.
  Build y comprobación de bundle PASS. Esta operación no subió otra web.
- Captura productiva: 14:40:15 UTC; preflight PASS a las 14:40:22 UTC
  (09:40 Lima). El merge terminó con `FUNCTIONS_DEPLOYED`.
- Proyecto: `dctqcbznekcyxhjujuci`; historial de 266 a 268 migraciones.
- Banco `f5-cartera-publicacion-20260909` eliminado después de verificar producción.
  La lectura posterior del inventario confirma su ausencia; `banco-f7` se conserva.

| SQL local aprobado | Versión productiva | SHA-256 del archivo aprobado |
| --- | --- | --- |
| `20260908230249_crm_f5_cartera_ficha_multiempresa.sql` | `20260909165335` | `a13c7ec388993b8cba5299d61e33d9db1cff7d148146b06cbd0cd99cdcce22e5` |
| `20260909170900_crm_f5_candado_estado_cartera.sql` | `20260909171452` | `36390b01ded88d7d1f90b8ca8036d3c864c0470df10b9673c348541d530353ab` |

El merge de Supabase separó cada SQL en 33 y seis sentencias, respectivamente.
Cada sentencia coincide literalmente y en orden con el archivo aprobado; los
únicos caracteres separados son delimitadores `;` y espacios/saltos entre
sentencias. Por ello el hash del array de historial difiere del banco, donde
MCP había guardado cada archivo en un único elemento. No se reparó ni normalizó
el historial. Las 266 migraciones anteriores mantienen sus arrays exactos
(MD5 agregado `eb42c6aff05f6716440955e52cb68271`).

## Comprobaciones productivas

| Comprobación | Resultado |
| --- | --- |
| 1.353 funciones/restricciones preexistentes | PASS: definición, propietario, configuración, comentarios y permisos conservados |
| Nueve funciones y cuatro restricciones nuevas F5 | PASS: corresponden exactamente al banco ensayado |
| ACL de esquemas, tablas y columnas | PASS: coinciden con el banco; helpers privados cerrados |
| 14 tablas de negocio, incluidas fuentes financieras, identidades y banderas | PASS: recuentos y huellas idénticos antes/después |
| Auth | PASS: 474 usuarios antes/después; sin altas ni modificaciones de cuentas por esta instalación |
| 17 Edge anteriores | PASS: paquete, entrada, JWT e import map conservados, incluida Tasa |
| `crm-inversion-documento` v1 productiva | PASS: sus dos archivos coinciden con el paquete; JWT exigido; petición HTTP sin sesión rechazada con 401 |
| Capacidad con identidad CRM autorizada | PASS: `habilitada=false`, `escritura_habilitada=false` |
| Auditoría de lectura | PASS: RLS activa, sin acceso de anon/authenticated/service_role ni filas añadidas |
| Censo D-19 | PASS: cero funciones leyendo la bandera sin candado |
| Banderas | PASS: F3 ON, F4 OFF, F5 OFF |
| Huecos de identidad | Mismos 15: 13 Avance y dos Qorilazo; sin backfill |

Advisors de seguridad: **0 ERROR, 183 WARN, 53 INFO**, frente a
0/178/52 antes de instalar. El incremento corresponde a las cinco RPC
SECURITY DEFINER de lectura, autorizadas explícitamente y probadas por rol,
y la tabla de auditoría intencionadamente cerrada sin policies.
Referencias: [RPC con autoridad explícita](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
[RLS sin policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
Advisors de rendimiento: **0 ERROR, 5 WARN, 105 INFO**. No se declara que los
avisos históricos estén corregidos.

## Ensayo y límites

Se conserva el ensayo de 46 pruebas locales, 15 comprobaciones remotas y siete
checks D-19, más replay/reversa y evaluación independiente de Claude, descritos en
[la instalación ensayada](INSTALACION-2026-09-09.md). Las 12 pruebas de proxy y
premerge, ambos generadores, el build y el bundle se comprobaron de nuevo el 10/09.
El CI backend del commit `d969381` pasó:
[CRM RLS preflight](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/34490153393).

El RLS general completo posterior a la corrección sigue **NOT RUN**: el ensayo
anterior tenía 65 fallos conocidos de configuración/expectativas del banco y el
D-19 ahora corregido. No se presenta ese gate como PASS. Su mantenimiento se
requiere antes del piloto. La operación no repitió el recorrido visual aprobado.

F5 queda técnicamente instalada y apagada. El encendido requiere conciliar las
15 fuentes con lotes revisados y cumplir los gates posteriores del maestro.
Sigue F6 (postventa); F7/G6 concilia métricas; F8/G7 requiere piloto y firmas;
F9/G8 requiere un ciclo mensual real. Las comisiones permanecen fuera del CRM.

Evidencia sin credenciales en `evidencias/publicacion-2026-09-10/`.
Evidencia privada completa en `/private/tmp/avancecorp-f5-instalacion-20260909/`.
