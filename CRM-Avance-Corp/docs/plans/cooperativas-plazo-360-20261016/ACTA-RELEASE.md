# Cooperativas 360 días — publicación autorizada

Estado: **PAUSADO por petición de Miguel el 16/10/2026, 23:45 UTC**.
Producción intacta, sin merge SQL, push a Main ni publicación del frontend.
Miguel invocó `$release-crm` y aprobó además «corrige el control y continúa la
publicación». El destino es `crm.miavance.com`, desde `avancecorp/main`.

## Alcance

Qorilazo y Prodelco: un mes entero equivale a 30 días corridos desde el inicio
comercial, conservando la tasa anual. Doce meses vencen a los 360 días.
Las fuentes anteriores conservan calendario y sus fechas al corregirse.
El lector de Gerencia admite PEN y USD según el catálogo de cada cooperativa.

El gate encontró tres controles que retenían huellas anteriores a los permisos
de consulta de Coordinación ya publicados. Dos migraciones pequeñas sustituyen
cuatro constantes en esos controles. No modifican policies, ACL, propietarios,
firmas ni restricciones. La lectura de tareas de Coordinación sigue limitada
a leads activos. Cada migración exige el cuerpo y las policies exactos antes
de actuar y ejecuta sus validadores después.

SQL candidato (contenido exacto registrado en el banco):

| Versión | SHA-256 |
|---|---|
| 20261016195003 | `518641adaee9ca85d8eecf50cfe09dd50d79af377cee3613af6a96bac0acd363` |
| 20261016231301 | `be058004682a2f198da54ff8be3a49d3cb461f4178e50be759c42edd2a59a827` |
| 20261016232742 | `9cc1490237da010ab3849a956fbb26024cda2af865e243a4fa3d5b748d076a37` |

## Evidencia de preparación

- `npm run check`: PASS, 434 archivos y 6.998 pruebas, además de lint,
  TypeScript, cobertura, configuración de release, build, bundle y duplicación.
- E2E completo local en Docker: PASS, **439 passed / 26 skipped / 0 failed**.
  La app no cambió desde el commit `d4d47502087b2ebd394c64456bee28a656317079`
  que se verificó; los ajustes posteriores son SQL, documentación y fixtures.
- `check:scripts`: PASS tras repetir con permiso de red/servidor local;
  el primer intento quedó bloqueado por el sandbox al abrir 127.0.0.1.
- Preflights seed, RLS y Edge: PASS. Los primeros NOT RUN del expediente
  inicial quedan sustituidos por estas ejecuciones con entorno autorizado.
- Tipos generados desde el banco remoto: bloque `cierres_externos` idéntico
  al versionado, incluidas las tres apariciones de `base_plazo`.
- Mutantes de los validadores: **5 + 18 + 20 = 43 detectados**. Cuatro
  mutantes adicionales de policies/restrictivas también fueron rechazados
  y sus cambios revertidos por transacciones. Los tres controles quedan OK.
- `gate:realidad` productivo, solo lectura: ejecución correcta; dos divergencias
  preexistentes (ventas de analistas inactivos y clientes sin domicilio legal).
  No acredita que los diez supuestos estén satisfechos y no modifica esos datos.
- Advisors del banco: seguridad 379→380, único aviso añadido en la respuesta
  tardía es la protección de contraseñas filtradas de Auth. También aparece
  en producción, el candidato no cambia la configuración Auth y no es consecuencia del SQL. Los avisos
  de catálogo son idénticos. Rendimiento 350→313, cero hallazgos nuevos.
- Las 23 Edge Functions conservan versiones, configuración y hashes del origen.

La matriz RLS completa está **INCOMPLETA; no aprueba el release**. Se detuvo
por la petición de pausa después de 1.677 aserciones positivas, con tres fallos
preexistentes: Coordinación ya puede leer el lead de la sonda, la firma viva
del filtro de cartera tiene 15 argumentos y faltaba la fila inicial del control
de reparto en el banco reconstruido. Se corrigieron las expectativas contra
las migraciones publicadas `20261015224848` y `20261014215453` y se restauró
la fila inicial de `20261007143121`; falta repetir la matriz desde el principio.
No se retiraron aserciones de autorización ni se alteró el producto para
hacer coincidir las pruebas. Los controles de huellas y sus mutantes sí pasaron.

Se conservan las salidas de
los intentos previos fallidos por huellas antiguas. Un intento posterior fue
interrumpido al detectar dos fechas de fixture calendario; se ajustaron a
360 días y se reinició desde el seed. Las aserciones de seguridad se mantienen;
12 tests del adaptador comprueban 30/360/720 días, tasa y propagación de fechas
explícitas incorrectas al servidor para que este las rechace.

## Banco y paridad

Rama `coopac360-release-20261016`, ref `oneyeeplsvfgwzfgixhb`,
ID `bede730d-5858-43de-98ae-fe5fc17789f5`, creada 22:24:38 UTC.
Misma organización PortalAvanceCorp y tarifa autorizada de US$0,01344/h.
Eliminada a las **23:45:54 UTC**; la lista posterior confirmó su ausencia.
No se tocaron las otras ramas. Duración aproximada 1 h 21 min, unos
**US$0,0182** según la tarifa cotizada; es una estimación, no una factura.
Se eliminaron los archivos privados de credenciales del banco y de servicio.

El replay histórico falló antes del candidato. Se restauró un esquema vacío
desde producción, sin copiar clientes, y las 487 filas exactas de su historial.
Huella del historial base: `c2bb35ce082c65d2948ca2724548aece`.
Se completaron las columnas e índice UNIQUE de `schema_migrations` omitidos
por el replay parcial. El primer apply aplicó el SQL cooperativo pero falló al
registrarlo por ese índice ausente; se verificó su instalación y se registró
el SQL exacto una sola vez, sin reaplicarlo. Los dos ajustes posteriores sí
pasaron por `apply_migration`. Las tres entradas nuevas coinciden byte por
byte con los ficheros versionados. No se reparó historial de producción.

Antes del candidato: 1.110 funciones y 154 relaciones, owners/ACL comparados;
tres CHECKs ajenos solo difieren en agrupación equivalente de AND por el dump.
También se restauraron las membresías globales de los dos roles internos,
que `pg_dump --schema-only` no incluye, y las policies Storage y triggers Auth.
Se sembraron únicamente personas y configuración ficticias para el gate.
Tras el candidato: solo cambian cinco cuerpos de función, se añade el helper
de cuatro argumentos y cambia la tabla `cierres_externos`. Owners/ACL/config
de funciones existentes permanecen iguales. El catálogo productivo completo
se reconfirmó sin deriva desde la captura original.

Un inventario diagnóstico de otros validadores detectó datos de configuración
ausentes en el banco y una huella antigua del roster en
`assert_gestion_diaria_analista()`. Son controles ajenos a esta corrección;
no se han cambiado ni se presentan como PASS. No se relajan validadores para
adaptarlos a diferencias de formato del banco.

## Revisión independiente

Las dos revisiones originales del cambio cooperativo devolvieron
CHANGES_REQUESTED; sus hallazgos y resolución están en el expediente inicial.
Para el ajuste adicional de auditoría el wrapper de Claude no entregó un
VERDICT válido en dos intentos acotados: **NOT RUN**, sin atribuirle un PASS.
No se repitió para buscar conformidad. La decisión del PRIMARY se apoya en
paridad de metadatos, guards exactos, mutantes y gates reales.

## Cierre pendiente

Al retomar: recrear banco sin datos reales, restaurar configuración inicial y
catálogos estáticos de auditoría, repetir RLS completo, sincronizar Main/remoto,
construir ZIP limpio y verificarlo,
pasar preflight, merge nativo de las tres migraciones, publicar por Hostinger,
verificar versión y hashes HTTP y eliminar el banco temporal.
Se conserva para recuperación el ZIP publicado anterior
`crm-20261016T184742Z-0d6aa930fe3b.zip`, SHA-256
`595bc1deeb84014b7813699b761e3346f34fdb317dd395dba2ff5f5f8c1d79be`.
El ZIP preparado desde d4d4750 no se considera publicado ni será el final.
El parche completo sobre `1170a5e36b957d186f079edf053d2e7745351cd5` y el
estado de continuación se guardan en el expediente compartido. El checkout
compartido y sus cambios ajenos permanecen sin modificar.
