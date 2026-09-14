# F8 — instalada y verificada en producción, apagada

Los dos SQL autorizados se instalaron por `merge_branch` en
`dctqcbznekcyxhjujuci` el 14/09/2026. El control nació a las **11:51:20 Lima**
con `activo=false`, revisión cero, sin ventana y **cero participantes**.
F3 sigue ON y F4/F5/F6/F7 globales OFF. El piloto real y G7 permanecen abiertos.

## Publicación exacta

Main local, `avancecorp/main` y la copia limpia de publicación se verificaron en
`8c185f689afbfdc48dcb459d6f0527bcd0db7301`. La integración conservó los cambios
remotos de Citas y Facturación. El preflight productivo final, capturado a las
16:50:28 UTC, pasó a las 16:50:49 UTC antes del merge.

| Archivo inmutable | Registro productivo | Sentencias |
|---|---|---|
| `20260913215240_crm_f8_piloto_controlado.sql` | `20260914161616` | 43 |
| `20260914025926_crm_f8_excluir_fuentes_demo.sql` | `20260914161816` | 10 |

Sus SHA-256 siguen siendo, respectivamente,
`0807e59bcaccfbce8d7af02dc67fcfa8a64686305aaa976d4840af16c86c18fe` y
`0f7daa10f1e1ac1d71501795d0f0d45c64e58fa263426c7e27a56f5c0e73dc08`.
El ejecutor separó los arrays de una sentencia de la rama. Se cotejó cada
sentencia productiva literalmente y en orden contra el archivo aprobado: solo
se retiraron los separadores externos de punto y coma y espacios. No se cambió
el SQL ni se reparó el ledger después del merge. Total: **281 migraciones**;
las 279 filas anteriores conservan su MD5 completo
`576597950066582f3269ea9cc0672771`.

El artefacto `crm-20260914T164225Z-8c185f689afb.zip` se construyó desde ese Main
verificado, SHA-256
`0f12575760ca4a5b58638991f2a76a04c7c1663b6bbc8d0587b08c171d7bfcc6`.
El código ejecutable del frontend no cambia respecto de Main anterior; solo
se añadieron tipos borrados al compilar. Esta entrega instala SQL, sin volver a
subir recursos web ni incorporar candidatas de otras tareas.

## Comprobaciones posteriores

| Control | Resultado |
|---|---|
| Control OFF, revisión 0, ventana vacía y cero miembros | PASS |
| F3 ON y F4–F7 globales OFF | PASS |
| RLS de ambas tablas; 42 permisos API denegados | PASS |
| Lector privado sin EXECUTE de anon/authenticated/service_role | PASS |
| 605 fuentes brutas: 600 reales, 5 demo, cero brechas reales | PASS al corte 12:09 Lima |
| Lector operativo: 600 fuentes, cero demos | PASS |
| Catálogo instalado respecto de rama ensayada | PASS: exactamente las 6 diferencias centrales y 172 externas revisadas |
| 19 Edge: inventario, versión, configuración y hash de bundle | PASS, idénticos antes/después |
| Auth settings y schemas Data API | PASS, iguales a la configuración comprobada antes |
| CRM y Portal HTTP | PASS, ambos 200; Miguel confirmó acceso normal |
| Rama exclusiva eliminada y ausencia verificada | PASS; otras ramas conservadas |

Las capturas de catálogo posteriores son del mismo intervalo de 13 segundos.
El comparador se ejecutó sobre esas capturas guardadas usando su momento de
captura como referencia y registrando aparte el momento real de comparación;
es evidencia posterior al merge, no una autorización ni un preflight vivo.
Las diferencias administradas y sus límites están explicados en el
[ensayo completo](ENSAYO-2026-09-14.md). No se afirma equivalencia general de
Realtime/pg_net.

## Datos y actividad concurrente

La base continuó recibiendo ventas y usuarios durante la verificación. Las
602 fuentes existentes antes del merge conservaron **todas** sus filas y MD5.
También coinciden exactamente los 580 contratos, 22 cierres y 484 personas
anteriores. Se observaron después un contrato, dos cierres y tres personas
nuevos; sus altas tienen actor en la auditoría. Las 14 inversiones, 14
cotitularidades, periodo cerrado, equipo, dos secretos Vault y diez jobs Cron
conservaron sus huellas completas. Los diez Cron productivos siguen activos.

Auth/perfiles pasan de 496 a 497. Hay sesiones y actualizaciones posteriores:
la auditoría de perfiles registra `debe_cambiar_password`, `pwa_instalada_at` y
fecha de actualización. **No se declara igualdad de hashes de Auth/perfiles**;
los registros se dejaron tal como están. Los dos SQL no escriben en esas
tablas y sus sentencias exactas quedaron verificadas. Cero usuarios nuevos con
el dominio sintético del ensayo y cero actualizaciones del control F8 en la
auditoría. No se atribuye el error transitorio de conexión a una causa no
demostrada ni se declara haber aplicado una corrección de acceso.

## Verificación del paquete y límites

- PASS: 31 pruebas SQL locales, 27 remotas y 12 grupos Auth/Data API con sesiones
  reales de usuarios ficticios, además de las comprobaciones de restauración,
  historial, preflight y paridad documentadas en el ensayo.
- PASS: lint/typecheck, 3.513 pruebas frontend, configuración de release,
  build, bundle y verificación independiente del manifiesto del ZIP.
- Claude revisó la instalación y devolvió `CHANGES_REQUESTED`, sin P0/P1.
  El PRIMARY evaluó y resolvió las recomendaciones con evidencia y pruebas;
  no se presenta ese dictamen como un PASS de Claude.
- NOT RUN: suite RLS general heredada completa en este ensayo combinado.
  La matriz específica F8 sí pasó. Los avisos previos de seguridad y los INFO
  de RLS cerrado/FK pequeñas siguen documentados, sin SQL adicional no aprobado.
- PENDIENTE: selección nominal, configuración/activación aprobadas, operaciones
  reales, conciliaciones y firmas de [G7](ACTA-G7.md). La conformidad G6 anterior
  sigue vigente para su corte; las comisiones se calculan fuera del CRM.

La rama `zgjyapayxvnvrgpiarod`, ID
`1d5c256d-a7a2-4031-9242-1292ffd37be2`, fue eliminada después de las
comprobaciones, cerrando su coste. No se repite el lote de diez enlaces ya
aplicado. [Evidencia saneada](instalacion/produccion-2026-09-14/README.md).

