# Preparación del despliegue · cierre de gestiones de clientes

## Estado vigente: publicado y verificado

Publicado en **https://crm.miavance.com** el 07/10/2026 a las 04:55:39 UTC
(06/10, 23:55:39 Lima). **Cartera → ficha de cliente → Seguimiento → Cerrar tarea**;
resultados disponibles para supervisión según permisos. Miguel realiza la revisión visual.

Fuente: Main limpio `3bdfded2c8130a3e8843d5320516f4691de933f3`, build
`build-20261007T045430720Z`. El commit previamente publicado `dfb8874d` es su ancestro;
se conservan las entregas de Main y la corrección de capital renovado. #212 quedó
como squash y se corrigió mediante #213 con merge real de dos padres, con aprobación
explícita de la acción administrativa puntual; no se cambiaron reglas globales.
El preflight oficial y Main remoto se verificaron inmediatamente antes de subir.

`npm run check`: **PASS 6.286 pruebas / 392 archivos**. Docker: cierre/Agenda/supervisión
43 PASS y 13 omitidas en `ad111817`; delta F5 posterior, 13/13 PASS en `e255e96d`,
con app idéntica al Main final. SQL productivo: postflight de solo lectura PASS
`2026-10-07T04:45:14.151431Z`. Build, ZIP y preflight final PASS.

Smoke requerido **PASS**: portada, versión, 110 JS y 6 CSS coinciden en bytes/SHA.
154 archivos responden HTTP 200. Comparación literal ampliada: 144 coinciden y diez
PNG difieren por un comportamiento compatible con la optimización de CDN. Sus
fuentes son idénticas al ZIP anterior; nueve originales obtenidos con BYPASS
coinciden. El PNG de NTC sigue redimensionado por CDN y su igualdad binaria por HTTP
no quedó acreditada. Se conserva el resultado literal FAIL y su diagnóstico en el
acta, sin modificar la configuración del hosting.

Paquete: `releases/crm-20261007T045431Z-3bdfded2c813.zip`, SHA-256
`053780737f010276acda83b6d6cf8c035ac4e3f947e179ff820eaf9f593afafd`.
Recuperación anterior conservada: `crm-20261007T034649Z-dfb8874d534b.zip`.
`LLAMADAS_CELULAR_APROBADAS=false` sigue; registro manual y Deshacer disponibles.
No quedan publicaciones, tests ni builds propios ejecutándose.

[Acta final y evidencia](../publicaciones/2026-10-07-cierre-gestiones-clientes-publicado.md).

## Historial previo a la publicación

## Estado histórico: reconciliación preparada, pendiente de GitHub

Miguel reanudó y gestionó la integración de #209. Main vigente: `e255e96d3d0ef39c55eedd29a9c879bf13822b91` (#210 incluido). `npm run check` PASS: 392 archivos / 6.286 pruebas. E2E de cierre/agenda/supervisión: 43 PASS, 13 omitidas, cero fallos/retries en `ad111817`; único delta posterior de Cartera: 13/13 PASS en `e255e96d`. SQL #207 instalado, postflight de lectura PASS `2026-10-07T03:45:13.885063Z`.

Otra entrega publicó capital renovado desde `dfb8874d` (build `build-20261007T034648905Z`). Su parche está en #210, pero su commit quedó fuera de la ascendencia de Main. El preflight oficial rechazó Main por ese motivo. Se preparó la [PR #212](https://github.com/avanza-digital/avancecorp-crm/pull/212), rama `rescate/cierres-cliente-main-20261007`, HEAD `4777b32199da75568efe467af2809d2bdeaba69b`, desde el commit vivo y con merge de Main completo. El merge intermedio `31ff0744` tiene árbol completo idéntico a Main; el HEAD añade solamente el acta. Todos los archivos de app son idénticos a Main (árbol `3ea20c6848873b977d95146fccdddd72a52162dc`). Las líneas agregadas/retiradas de los tres archivos publicados coinciden literalmente con #210.

**Todo lo preparable está listo:** build, bundle, ZIP, huella, preflight Hostinger real y checks GitHub PASS. Claude revisó esta nueva situación: PASS, con advertencias de reconstruir desde el Main final y reconfirmar fuente/vivo. Se aceptan: el acta está en un commit separado y el artefacto preparado no se presentará como un futuro commit de Main.

**Bloqueo concreto:** GitHub exige `required_linear_history`, revisión y checks. Para retener el commit vivo es necesario integrar #212 con **Create a merge commit**, sin squash ni rebase; requiere una excepción del responsable. Se preguntó a Miguel si puede gestionarla. Codex no cambia reglas, no usa admin bypass, no altera el preflight y no publica mientras falta esta reconciliación. Una PR abierta no equivale a cumplir la vuelta a Main del rescate.

Artefacto verificable: `releases/crm-20261007T043916Z-4777b32199da.zip`; SHA-256 `f98edf601bacdd73b6598faaddb6225b3b2311e1df58f46079621b5c2c523fe3`. Preflight: PASS, vivo `dfb8874d` incluido. Recuperación vigente: `crm-20261007T034649Z-dfb8874d534b.zip`, SHA-256 `47070ef4c08e5f1e3c1d5cc371abfcbc208d07fcbce9f5ba5ec6571b73565ca2`. Los paquetes anteriores `a0c334ba`, `ad111817` y `e255e96d` no son publicables sobre ese vivo.

**Siguiente paso:** esperar la decisión/integración de #212; fetch, verificar Main local = remoto, ascendencia `dfb8874d` y equivalencia del código; reconstruir desde ese Main limpio, verificar paquete y preflight; publicar por Hostinger con el «deploy» vigente y comparar HTTP/versión/hashes. El frontend del cierre de tareas todavía no fue publicado. `LLAMADAS_CELULAR_APROBADAS=false` permanece; no hace falta esperar #190. No quedan tests ni builds propios ejecutándose.

Estado detallado: `app/artifacts/gestiones-clientes-independiente-estado.json`; logs `gestiones-clientes-main-210-check.log`, `gestiones-clientes-main-210-e2e-F5-PASS.log`, `gestiones-clientes-independiente-e2e-PASS.log`, `gestiones-clientes-rescate-release.log` y `gestiones-clientes-rescate-review.txt`. Copia aislada limpia: `/private/tmp/crm-cierre-paquete-2pwvxy9d/repo`.

## Registro de etapas anteriores

## Alcance aprobado

Miguel aprobó la vista del CRM vigente en local el 06/10/2026, pidió preparar el despliegue y después autorizó **«deploy»**. También confirmó la organización actual de Supabase. La publicación está autorizada: no volver a exigir una invocación literal de `$release-crm`. Sus controles técnicos siguen siendo obligatorios.

La PR [#207](https://github.com/avanza-digital/avancecorp-crm/pull/207) quedó integrada sobre #190 en `avancecorp/main`: **`a0c334bae19c54885fcf4c02adcf34c4c85ae83a`**. Se verificó Main local/remoto en la copia limpia `/private/tmp/crm-cierre-paquete-2pwvxy9d/repo`. El build todavía vivo es `build-20261006T213354829Z`, commit `4e6ee7ee296be83cd96366e3e79685343b3b706b` (#206); el candidato lo contiene. Se conservan las restricciones de nueva inversión y el demo sigue fuera del bundle.

## Cambio de plan autorizado: publicar sin esperar a #190

Miguel indicó que #190 tardará y pidió avanzar. Se preparó la [PR #209](https://github.com/avanza-digital/avancecorp-crm/pull/209): mantiene Main completo y deja `LLAMADAS_CELULAR_APROBADAS = false`. El cierre de tareas y su supervisión se publicarán con la integración de celular desactivada. No se instalan migraciones de #190 ni se retira su código.

Copia aislada: `/private/tmp/crm-cierre-paquete-2pwvxy9d/repo`; cabeza actual `5683dbdf`, incorpora Main `62a375f0` (#208). SQL #208 ya instalado por la otra entrega; el postflight #207 volvió a aprobar en producción el 07/10 a las 01:35:34 UTC. `npm run check` integrado PASS: 392 archivos / 6.279 pruebas. **Trabajo pausado por Miguel**: las ocho especificaciones Docker se interrumpieron con salida 143; dependencias restauradas y copia limpia. No hay PASS final de estas E2E. La rama #209 sigue en borrador y requiere aprobación de GitHub antes de integrar; después se reconstruye desde Main verificado y se publica con el «deploy» vigente.

**Reanudado por Miguel («sigue»).** Se mantiene el código `5683dbdf` y todos los controles de GitHub PASS. Postflight SQL repetido PASS el 07/10 a las 03:45:13 UTC. Miguel confirmó que gestiona la aprobación de la PR #209. La prueba Docker de ocho especificaciones espera a que terminen otras suites por falta de memoria; no se han cambiado tiempos ni aserciones. El registro de pausa anterior se conserva en [CRM-CIERRES-INDEPENDIENTE-20261006-02](2026-10-06-cierres-independiente-PAUSA.md). Este plan sustituye la espera de #190 descrita en el historial inferior.

Evidencia: `app/artifacts/gestiones-clientes-independiente-estado.json`. **El ZIP de `a0c334ba` queda superado: no tiene el interruptor y no es el candidato de esta publicación independiente.** El estado anterior se conserva abajo como historial de la instalación SQL.

## Estado anterior del despliegue, 07/10 00:43 UTC (06/10 19:43 en Lima)

**SQL #207 instalado y verificado en producción; frontend todavía no publicado.** Las dos migraciones se integraron mediante `merge_branch`; el postflight productivo aprobó a las **2026-10-07T00:43:32.969586Z**. Miguel confirmó que **el otro agente sigue trabajando en #190**. El frontend integrado requiere que su SQL y función de servidor también estén listos. La última lectura conserva el build vivo `4e6ee7ee` y no encuentra migraciones de llamadas del celular.

| Control actual | Resultado |
| --- | --- |
| Main integrado: `npm run check` | PASS: 391 archivos / 6.263 pruebas, lint, tipos, build, bundle, duplicación 0,44 % |
| E2E completo Docker local | PASS: 368 aprobadas, 26 omitidas, 0 fallos, 0 retries; 14,4 minutos |
| Artefacto final y preflight Hostinger | PASS: `crm-20261007T000643Z-a0c334bae19c.zip`, fuente limpia, conserva el build vivo |
| Cuatro suites SQL originales en rama Supabase | PASS: resultados, agenda, supervisión, privacidad, cursor y catálogos; ROLLBACK |
| Esas mismas suites con SLA activo | PASS: modo, vigencias, reglas y fecha de adopción de producción, con actores sintéticos; ROLLBACK |
| Preflight / postflight de las dos migraciones | PASS en rama y producción: 17 dependencias, 13 funciones, ACL y tres índices; controles de solo lectura |
| Matriz HTTP general | PASS: 3.075 aserciones, cero fallos; repetición íntegra con fixture corregido |
| Advisors posteriores al merge | Sin nuevas alertas de seguridad ni nuevas advertencias de rendimiento por entidad |
| Edge Functions tras el merge | PASS: 22 funciones conservan SHA-256, `verify_jwt` y estado |
| Historial de migraciones | PASS: 432 registros previos intactos; las 40 sentencias nuevas coinciden literalmente con los archivos aprobados |
| SQL #207 en producción | INSTALADO: `20261005224214` y `20261006012208` |
| Frontend en producción | PENDIENTE de SQL y Edge de #190; no se ha subido el ZIP |
| Rama temporal propia | ELIMINADA; ausencia confirmada en `list_branches` |

ZIP: `releases/crm-20261007T000643Z-a0c334bae19c.zip`; SHA-256 **`654d18071515bf995c963779cb1034ffcee62919e437c53c79d83a61a749998c`**. Manifiesto del mismo nombre. Hostinger reconoció el sitio exacto `crm.miavance.com`, cuenta `u318796122`, mediante el servidor oficial instalado; no se cambiaron sus credenciales ni configuración.

Rama propia ya eliminada: `cierre-gestiones-clientes-20261006`, ID `1dd322d4-f02a-4ab8-ba45-f6f07493dac8`, proyecto `afszecbuolvwpqnfcpbj`, sin datos productivos. El replay histórico se detuvo en 86 migraciones por un postflight antiguo dependiente de datos. Se recuperó mediante copia **solo de esquema** y conservación exacta de las 432 versiones ya instaladas como base; no se presenta como replay aprobado. Antes del merge se cotejaron las 432 filas completas entre captura original, producción y rama; SHA-256 de JSON canónico: `7cf9b3af132fd9c90ac21b3a12ce511ea7403e6130c6a7ad3b489da97399e0e6`. Dos nombres históricos NULL se corrigieron en la rama, antes de integrar, porque la restauración temporal los había representado como texto `None`; sus sentencias permanecieron intactas.

Después del merge, los 432 registros anteriores siguen exactamente iguales y aparecen las dos versiones nuevas. Supabase divide su SQL en cuatro y 36 sentencias, omitiendo los delimitadores finales; se verificó cada contenido literalmente, en orden, permitiendo únicamente separadores y espacio exterior. La comprobación inicial de un único elemento `[archivo]` no aplicaba a esa representación nativa. No se modificó el historial productivo para cambiar su formato. El writer instalado tiene `md5(prosrc) = 6a929c3d7170f9b90acb9fb5d3888c35`.

La comparación de catálogo igualó objetos existentes, cuerpos, propietarios y permisos de aplicación. Quedaron 48 permisos por defecto de `supabase_admin.public.*` propios de la plataforma y `pg_net` en `extensions` en la rama. Las migraciones de este encargo no crean objetos de `public` ni dependen de esos valores. El delta de aplicación fue únicamente el writer, 12 funciones nuevas y tres índices. Las 22 Edge Functions se cotejaron antes y después del merge y permanecieron idénticas.

El primer ensayo HTTP encontró Storage ausente: se copiaron solo las 19 políticas y los cinco buckets de configuración, sin documentos. El segundo terminó **5/2.823 fallos**: cuatro porque `potencial_lead` debía empezar apagado para sus pruebas y uno porque el dump había representado los permisos exclusivos del propietario como ACL NULL. Se repusieron la bandera inicial y las ACL explícitas que ya existen en producción, únicamente en el banco. Se respaldaron y reiniciaron los datos sintéticos antes de repetir el gate íntegro, sin cambiar aserciones: **3.075 aserciones PASS**. El SLA activo se probó aparte porque la matriz canónica usa legado. La matriz corresponde al script de este encargo (`4d90e7ab`, SHA-256 `afc94aba502b5af5f69c2d00d3f1d5179fc3a5ff84c29f15729c238216076f19`); no acredita el backend pendiente de #190.

Estado y logs: `app/artifacts/gestiones-clientes-ensayo-remoto-20261006.json`, `gestiones-clientes-produccion-20261007.json`, `gestiones-clientes-historial-productivo-verificado.json`, `gestiones-clientes-paridad-historial-premerge.json`, `gestiones-clientes-rls-remoto-PASS.log` y `gestiones-clientes-main-{check,e2e,release}.log`. La rama se eliminó después de verificar producción, para detener su coste; `banco-f7` y `upgrade-cooperativas-20261006` permanecen intactas.

## Plan anterior de publicación (superado por PR #209 y la pausa vigente)

1. Verificar que el otro agente terminó SQL y Edge de #190. La instalación de #207 ya está terminada; usar `comprobar-tras-aplicar.sql` como lectura posterior si hubo cambios concurrentes, sin reaplicar las migraciones.
2. Confirmar de nuevo Main local = `avancecorp/main`, el build vivo y la huella del paquete. Si cambia el código de Main, integrar, verificar y reconstruir desde el nuevo commit.
3. Con ambos backends verificados, publicar conforme al «deploy» ya autorizado por Miguel: preflight Hostinger y `hosting_deployStaticWebsite` del servidor oficial, sobre `crm.miavance.com`, con el ZIP final verificado.
4. Comprobar HTTP, build y hashes de todos los assets publicados. Verificar ficha, Agenda, Registro, resumen por analista y Citas sin fabricar gestiones reales para probar. Registrar el resultado final; la comprobación visual la realiza Miguel.

Si falla cualquier paso SQL, **no adelantar el frontend**: consume cinco RPC nuevas. La compatibilidad del writer permite mantener la pantalla anterior mientras se instala y valida la base.

## Verificación histórica de la preparación inicial

| Gate | Resultado |
| --- | --- |
| `npm run check` sobre copia limpia de Main + este encargo | PASS: 387 archivos, 6.219 pruebas, tipos, lint, build, bundle y duplicación 0,43 % |
| Ensayo SQL de instalación exacta | PASS: control previo → dos migraciones → catálogo/permisos → cuatro suites → ROLLBACK |
| Dependencia F5 del banco | Actualizada desde el snapshot vigente de producción; suites SQL PASS |
| Control previo contra producción, solo lectura | PASS; 17 dependencias, 06/10/2026 22:16 UTC |
| `seed:preflight`, `test:rls:preflight` | PASS offline con destino loopback y valores ficticios; no acreditan RLS remoto |
| E2E Docker completo | PASS: 366 aprobadas, 1 aprobada tras retry, 26 omitidas, 0 fallos finales; 14,2 minutos |
| GitHub `verify`, `app-check`, `preflight` | PASS en `4d90e7ab699b3da9f7567709f0044a3abb584309` |
| ZIP candidato y preflight Hostinger | PASS; conserva el commit vivo `4e6ee7ee` |
| Revisión Claude | Dos reviews previos; recomendaciones evaluadas y verificadas por Codex en el acta de revisión |
| Rama Supabase, matriz HTTP RLS y advisors posteriores | NOT RUN; requieren la rama autorizada y la confirmación de su coste |
| SQL y frontend productivos de este encargo | No instalados |

`gate:realidad` leyó producción: hay metas, cartera, tareas y equipo operativo; los cinco caminos de conversión coinciden. El canario de metas no tiene permiso por HTTP y se completó por SQL de solo lectura: cero revisiones bajo el sello. Se detectaron 277 clientes sin domicilio legal, condición preexistente del alta de contratos que no bloquea el cierre de gestiones. El comando HTTP terminó con exit 2 por ese permiso; no se presenta como un PASS íntegro.

Advisors de referencia guardados en `app/artifacts/gestiones-clientes-advisors-base.json`. Es una línea base productiva anterior a este SQL, no una validación posterior de las migraciones. Incluye avisos existentes de seguridad y rendimiento. Los helpers DEFINER nuevos se autorizan por sesión/rol/árbol y tienen `search_path` vacío; sus EXECUTE a authenticated permiten las puertas INVOKER. `private` no se expone como esquema de la API.

## Recuperación

Release publicado anterior: `releases/crm-20261006T213355Z-4e6ee7ee296b.zip`, con su manifiesto. SHA-256: `9b5be00b190443726f5520fc37a54ba27ff3785ace447200b7ce2d807430e33d`.

La recuperación preferida retira el frontend nuevo y conserva el writer compatible, los resultados, los recibos y el historial. No se borran actividades ni se reescriben resultados. El bundle anterior admite la base ampliada. Un rollback del frontend requiere decisión de Miguel: el preflight rechazará un commit anterior y no debe eludirse automáticamente.

Si hiciera falta retirar las cinco consultas nuevas, preparar una migración inversa específica, revisada y probada en rama, después de retirar sus consumidores. No se incluye un borrado automático del SQL ni se revierte el registro de migraciones. `ensayar-entrega.mjs` retira y repone objetos únicamente dentro de una transacción con ROLLBACK en el banco sintético sellado; no es un procedimiento productivo de reversa.

## Evidencia

- Implementación: [acta](2026-10-06-cierre-gestiones-clientes.md).
- Revisión y decisiones: [Claude](2026-10-06-cierre-gestiones-clientes-REVISION.md).
- Banco y controles: [README](../../supabase/scripts/gestiones-clientes/README.md).
- Logs: `app/artifacts/gestiones-clientes-entrega-*.log` y `gestiones-clientes-realidad-destino.json`.
- El paquete final agrega el commit, manifiesto, hashes, evidencia de E2E y resultado del preflight Hostinger.

## Paquete inicial de la PR (superado por el artefacto de Main)

PR borrador [#207](https://github.com/avanza-digital/avancecorp-crm/pull/207), rama `crm/cierre-gestiones-clientes-20261006`, commit `4d90e7ab699b3da9f7567709f0044a3abb584309`. GitHub exige una aprobación y sus gates antes de integrar en Main; no se elude esa regla. La rama existe en una copia aislada, no cambia la rama del taller compartido.

Candidato limpio: `releases/crm-20261006T222409Z-4d90e7ab699b.zip`; SHA-256 `0631315b29d74eb1385546f35b9f7cd27542a2bdaa3ed40e473be652e06c2fdf`. Manifiesto del mismo nombre. No es el artefacto final publicable mientras la PR no esté integrada en Main y el backend no esté validado. Al integrar, reconstruir desde el commit compartido por Main y `avancecorp/main`; no relabelar este ZIP.

Dossier autocontenido: `releases/gestiones-clientes-20261006-4d90e7ab/`. Incluye SQL exacto, controles de lectura, evidencia, candidato, versión anterior y manifiesto de huellas. La confirmación de organización/coste de la rama temporal de Supabase se solicitó a Miguel por el requisito de su herramienta. El contenido versionado del commit conserva el estado de la preparación al crearlo; esta acta y el dossier registran los resultados posteriores sin cambiar el código probado.
