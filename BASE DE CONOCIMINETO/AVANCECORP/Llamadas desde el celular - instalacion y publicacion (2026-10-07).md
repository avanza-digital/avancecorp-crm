# Llamadas desde el celular — instalación y publicación

07/10/2026. Relacionado: [[Llamadas desde el celular - PR 215 aprobado y activacion pendiente (2026-10-07)]], [[Llamadas desde el celular - analisis del PR 190 (2026-10-06)]], [[Telefonia CRM - plan por fases y Jev asistido (2026-09-29)]], [[Inicio]].

## Estado vigente

**H1, H2 y H3 terminados y publicados. C1 y las fases siguientes del plan conservan sus pruebas/aceptación pendientes.** El usuario pidió «haz todooo» y autorizó la rama temporal Supabase a US$0,01344/h. Esa rama ya fue eliminada; ya no permanece activa.

- #215 fusionado en `5f42e908155af3486cdf489a17b6eb8d6c673a16`, tras integrar main y repetir 6397 tests / 10 E2E Docker. #221 documental fusionado en `8e1c521af3ea982ffd669caacbf137515412e41b`.
- Las doce migraciones de llamadas están aplicadas en `PortalAvanceCorp` (`dctqcbznekcyxhjujuci`) mediante rama autorizada y `merge_branch`, terminado aproximadamente a las 21:53 UTC. 438 entradas anteriores idénticas, 450 totales. Las 56 funciones y las siete tablas coinciden con el ensayo en cuerpos/propietarios/permisos/RLS. SLA sigue activo, revisión 1, con política y primera activación intactas.
- Rama `llamadas-cierre-20261007` reconstruida desde esquema e historia productivos, sin clientes, al fallar el replay histórico vacío. Registradores ejecutados después de cada migración en el ensayo. Producción registra sentencias divididas: se cotejaron léxicamente las doce fuentes; no repetir registradores de estados intermedios allí.
- Edge `crm-llamadas-ingesta` v1 ACTIVE, `verify_jwt=false`, las dos fuentes descargadas idénticas al repositorio. Las otras 22 Edge conservan versión/huella/JWT. Negativas productivas sin clave/desconocida: mismo 401. Sin altas/eventos reales en el postflight.
- Matriz local completa **3292/3292 PASS** con SLA activo. Remota dirigida **328/328 PASS** (matriz de visibilidad y 197 de llamadas; no toda la global remota). Seis casos reales Edge en rama PASS; unitarias 17/17 y mutantes 18/18. Fallos anteriores del banco resueltos solo completando fixtures/configuración.
- Advisors: ningún ERROR nuevo; quince WARN de RPC DEFINER autenticadas intencionales y cubiertas por negativas, siete INFO de RLS sin policies cerradas a acceso directo, veinte INFO de índices recién instalados sin uso. No nuevos WARN de rendimiento. `gate:realidad`: 8/9, divergencia previa de 275 clientes sin dirección legal, ajena a llamadas.

## Habilitación del frontend

[PR #222](https://github.com/avanza-digital/avancecorp-crm/pull/222), commit `426904069b6d69575b3d7faa57d84a92015aa9f5`, un único cambio consolidado: flag ON, cuatro pruebas OFF explícitas, tipos regenerados desde producción y acta/ledger. No se editaron SQL versionados. `npm run check`: 6397/6397, 399 archivos, todos los gates PASS. Docker dirigido: 7 passed + 1 flaky; configuración repetida aislada: 2/2 PASS. GitHub preflight/app-check/verify PASS; revisión automática de seguridad concluida sin comentarios de hallazgos. Dos intentos acotados de revisión Claude adicional no produjeron VERDICT válido; no se declaran aprobados.

Se solicitó aprobación a Jhosep. GitHub rechazó la fusión normal por la regla de una aprobación externa y el repositorio no permite auto-merge. Codex consultó a Miguel si esperar o autorizar la fusión administrativa del commit ya verificado. Miguel respondió explícitamente «Autorizar fusión administrativa y publicación». Con esa autorización y los checks PASS, se fusionó #222 a las 22:18:30 UTC en `d4c9a6897bb3164a7499d2c4002a6544010b0f23`. Main local y `avancecorp/main` coinciden, árbol completo idéntico al commit probado; el release se construyó y publicó desde esa fuente limpia.

Último frontend vivo al preparar: `build-20261007T191820053Z`, commit `ab361d4f6c6d2b9db2e36c5a6ece71894725398d`, ZIP `crm-20261007T191820Z-ab361d4f6c6d.zip`, SHA256 `0c8fe83fba846b7c33b7745aee3362a169638e7823cff2656428606e14f7f8dc`. Conservar para recuperación conforme al preflight, no restituirlo por cuenta propia.

## Publicación verificada

Frontend vivo: **`build-20261007T222046462Z`**, commit **`d4c9a6897bb3164a7499d2c4002a6544010b0f23`**. Artefacto `crm-20261007T222047Z-d4c9a6897bb3.zip`, SHA-256 **`04d8c94ee949412d24e3ff70e4df493e0dccb812929c23fa8fe1a2f7ece4941d`**. ZIP/manifiesto conservados en `CRM-Avance-Corp/releases/`; fuente limpia, Main/remoto, configuración productiva, bundle, artefacto y preflight PASS.

Hostinger confirmó el despliegue y el postflight verificó **121/121 archivos idénticos** por HTTPS: todos los JS/CSS, HTML, versión y manifiesto web. Smoke con la sesión real disponible de **Analista**: módulo `assets/index-DMgwC82E.js`, pestaña Celular visible, bandeja cargada con cero pendientes y cero errores JS. La sesión antes mostraba Gerencia y tras recargar mostró Analista; no se cambió de cuenta ni se alteraron permisos para probar. Por eso el smoke manual de Gerencia posterior al release se declara **NOT RUN**; sus permisos/UI están cubiertos por Docker. Sin altas ni llamadas reales de prueba.

[Informe final y turno para Jhosep](https://github.com/avanza-digital/avancecorp-crm/pull/222#issuecomment-6048124018): H1–H3 listos, Pro/C1/P1–P15/noches/cinco días pendientes, después F4-e y las fases siguientes. `release-publicado.json` y `postflight-web.json` están en `_DEV_NO_SUBIR/llamadas-publicacion-20261007/`, junto con los gates. No se necesita otra publicación por esta nota de memoria.

## Coordinación y pendientes reales

Decisiones #16/#17/#18 comunicadas a Jhosep: aceptación F0 con salientes, F4-e después de F4-d con A1–A7 y Pro corporativo para 2–3 celulares dentro de S/57. [Decisiones](https://github.com/avanza-digital/avancecorp-crm/pull/215#issuecomment-6047091499). [Revisión documental y aviso H1/H2](https://github.com/avanza-digital/avancecorp-crm/pull/221#issuecomment-6047722612).

Tras H3: Jhosep compra/verifica Pro, activa C1 con credencial privada y cola de ensayo limpia, ejecuta P1–P15 contra la Edge real, diez salientes/casos especiales, noches y piloto de cinco días. P1/P2 dependen del orden real; no mezclar entrantes, recepciones y eventos en el recuento. F4-e/F5–F7 conservan sus gates; Jev sigue apagado. No declarar terminado el plan de 102 tareas por instalar el backend. Tras un alta, cerrar credencial o apagar UI y corregir hacia adelante: no reversas SQL ni borrar historia.

Acta versionada: `CRM-Avance-Corp/docs/plans/llamadas-celular/INSTALACION-20261007.md`. Evidencia local persistente: `_DEV_NO_SUBIR/llamadas-publicacion-20261007/` (prueba saneada, logs de gates). Copia limpia de trabajo: `/private/tmp/avancecorp-pr190-correcciones-20261006`, remoto correcto `avancecorp`. El checkout compartido y su trabajo ajeno se preservaron.
