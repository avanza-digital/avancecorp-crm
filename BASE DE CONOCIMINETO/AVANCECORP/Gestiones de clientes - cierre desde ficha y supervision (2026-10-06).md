# Gestiones de clientes - cierre desde ficha y supervision (2026-10-06)

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

[Acta final y evidencia](../../CRM-Avance-Corp/docs/publicaciones/2026-10-07-cierre-gestiones-clientes-publicado.md).

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

## Estado histórico: reanudado

Miguel pidió seguir. Se conserva HEAD `5683dbdf`, con 6.279 pruebas PASS y todos los controles de GitHub aprobados. SQL verificado nuevamente el 07/10 a las 03:45:13 UTC. La PR #209 está abierta para revisión y Miguel gestiona la aprobación requerida. La última prueba Docker espera recursos ocupados por otras suites; todavía no hay resultado final de las ocho especificaciones. Frontend sin publicar. Estado actual: `app/artifacts/gestiones-clientes-independiente-estado.json`.

## Pausa anterior (reanudada por Miguel)

**Serial CRM-CIERRES-INDEPENDIENTE-20261006-02.** Miguel pidió avanzar sin esperar a #190 y después pausar en un momento seguro. El interruptor de la PR [#209](https://github.com/avanza-digital/avancecorp-crm/pull/209) deja llamadas del celular desactivadas y conserva Main completo; código subido en `5683dbdf`, incluye #208 (`62a375f0`). `npm run check`: PASS, 6.279 pruebas / 392 archivos. E2E de ocho especificaciones **interrumpidas por la pausa**, exit 143, sin resultado final. Contenedor propio detenido, symlink de dependencias restaurado, copia aislada limpia. SQL #207 sigue instalado y verificado; frontend no publicado.

Reanudar únicamente cuando Miguel lo pida, desde [la pausa vigente](../../CRM-Avance-Corp/docs/encargos/2026-10-06-cierres-independiente-PAUSA.md): completar E2E, aprobación e integración #209, reconstruir desde Main verificado y publicar. No hace falta esperar a terminar #190. El ZIP antiguo `a0c334ba` no incluye el interruptor y queda descartado como candidato. Evidencia: `app/artifacts/gestiones-clientes-independiente-estado.json`.

## Estado anterior (historial; sustituido por la pausa vigente)

Serial retomado: **CRM-CLIENTES-CIERRE-20261006-01**. Implementación y vista aprobadas por Miguel; «deploy» autorizado. PR #207 integrada en `avancecorp/main` (`a0c334ba`), sobre #190. **Las dos migraciones están instaladas y verificadas en producción**: postflight PASS el 06/10/2026 a las 19:43 Lima (07/10 00:43 UTC). **Frontend preparado, todavía no publicado**: Miguel confirmó que el otro agente sigue trabajando en SQL y función de servidor de #190. La rama temporal propia ya se eliminó.

**Vista local corregida el 06/10:** Miguel reportó una versión antigua. El servidor conservaba el modo demo habilitado, que permite abrir la cartera anterior. Se deshabilitó en el puerto 5197 y se creó `http://127.0.0.1:5197/artifacts/postventa-local-entrada.html`: abre la ficha multiempresa vigente con sesión de ejemplo y valida que toda la conexión sea local. Verificados en Chrome la ruta vigente y los dos botones de cierre; no usar el login demo para revisar esta tarea.

**Aclaración final del 06/10:** Miguel quiere **el CRM vigente de producción con los cambios, visto en local**. El demo heredado no sirve para su revisión. La vista se reconstruyó desde el commit publicado `afae7b59` (build `build-20261006T165239841Z`) más el cambio de cierre, en una copia temporal, sin cambiar de rama ni sobrescribir trabajo ajeno. Menú, Cartera y base visual cotejados byte a byte; tipos PASS y ficha con ambos botones abierta en Chrome. Procedencia/reproducción: `app/artifacts/crm-vigente-local.json` y `preparar-crm-vigente.py`. Datos de ejemplo locales; publicación pendiente.

## Decisiones de negocio

- **Cerrar tarea** aparece en Seguimiento de la ficha de cliente, tanto neutral como anterior por perfil. Agenda conserva su cierre. Un rechazo del servidor mantiene la nota para reintentar.
- Postventa registra los siete resultados de llamada, WhatsApp enviado/respondido y los resultados comerciales de entrevista. Los siguientes compromisos obligatorios se guardan junto con el cierre. La ficha anterior reutiliza su cierre vigente de Agenda.
- Una cita programada o confirmada no cuenta como entrevista. Solo la asistencia registrada cuenta; cancelación, inasistencia y reprogramación mantienen su clasificación.
- El autor real de la gestión y el responsable de la tarea son datos distintos. Los superiores consultan actividad, citas y conteos conforme a su árbol autorizado.
- Registro y resumen separan leads/clientes/total, sin modificar las fórmulas selladas de captación. Se eliminan los duplicados entre historial F6 y actividades heredadas.
- Al perder acceso a un cliente se conserva el conteo histórico del autor, pero se retiran identidad, detalle privado y enlaces.

## Verificación y siguiente paso anteriores (historial)

Main limpio `a0c334bae19c54885fcf4c02adcf34c4c85ae83a`: `npm run check` PASS, 6.263 pruebas, tipos, lint, build y duplicación 0,44 %. Docker completo: 368 aprobadas, 26 omitidas, cero fallos y cero retries. La PR [#207](https://github.com/avanza-digital/avancecorp-crm/pull/207) está integrada. Se conservaron los trabajos ajenos del árbol compartido; la entrega se construyó en `/private/tmp/crm-cierre-paquete-2pwvxy9d/repo`, Main limpio alineado con `avancecorp/main`.

SQL instalado mediante `merge_branch`: `20261005224214_crm_resultados_cliente_postventa` y `20261006012208_crm_gestiones_clientes_supervision`. Cuatro suites originales remotas PASS, también con SLA activo y parámetros vigentes de producción; matriz HTTP de este encargo: 3.075 aserciones, cero fallos. Esta matriz no acredita el backend de #190. Ensayos locales de concurrencia y volumen de 90.000 eventos también PASS.

Postflight productivo PASS a las `2026-10-07T00:43:32.969586Z`: 13 funciones, tres índices, ACL y 17 dependencias. Las 432 versiones anteriores permanecieron intactas y las 40 sentencias de las dos migraciones nuevas se cotejaron literalmente con los archivos aprobados. Las 22 Edge Functions conservaron sus hashes y configuración. Sin nuevas alertas de seguridad ni advertencias de rendimiento por entidad.

El replay histórico de la rama falló en una migración antigua dependiente de datos. Se recuperó mediante copia **solo de esquema**, sin datos de clientes, conservando la base aplicada. Se documentaron los 48 permisos por defecto de plataforma no replicables por postgres. Los errores iniciales de fixtures (Storage, potencial y representación de ACL) se corrigieron antes de repetir toda la matriz, sin alterar aserciones. La rama `cierre-gestiones-clientes-20261006` (`afszecbuolvwpqnfcpbj`) se eliminó tras verificar producción; no se tocaron las ramas de otros trabajos.

Paquete final preparado: `releases/crm-20261007T000643Z-a0c334bae19c.zip`, SHA-256 `654d18071515bf995c963779cb1034ffcee62919e437c53c79d83a61a749998c`. Artefacto y preflight Hostinger PASS. La última lectura productiva conserva `build-20261006T213354829Z`, fuente `4e6ee7ee`; todavía no están instaladas las migraciones de llamadas del celular. Los paquetes previos basados en la PR sin integrar son evidencia histórica, no el candidato a publicar.

**Siguiente paso:** comprobar que el otro agente terminó SQL y Edge de #190; revalidar Main local = `avancecorp/main`, paquete y preflight; publicar por Hostinger y cotejar versión y hashes HTTP. Si Main cambia, integrar, verificar y reconstruir. El «deploy» de Miguel sigue autorizado; no exigir una nueva invocación literal de `$release-crm`. La comprobación visual la hace Miguel.

La recuperación conserva SQL compatible, recibos y resultados; no borra historial. Release anterior: `crm-20261006T213355Z-4e6ee7ee296b.zip`, con manifiesto. Dos revisiones de Claude evaluadas y ajustes verificados por Codex; no se atribuye un PASS nuevo al reviewer.

Estado y evidencia completos: [despliegue](../../CRM-Avance-Corp/docs/encargos/2026-10-06-cierre-gestiones-clientes-DESPLIEGUE.md), [implementación](../../CRM-Avance-Corp/docs/encargos/2026-10-06-cierre-gestiones-clientes.md) y [evaluación de Claude](../../CRM-Avance-Corp/docs/encargos/2026-10-06-cierre-gestiones-clientes-REVISION.md). Evidencia estructurada en `app/artifacts/gestiones-clientes-ensayo-remoto-20261006.json` y `gestiones-clientes-produccion-20261007.json`.

## Relacionado

- [[F6 - implementación de postventa (2026-09-10)]]
- [[F5 - instalada y apagada (2026-09-10)]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
