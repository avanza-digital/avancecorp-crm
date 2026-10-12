# Upgrade y reinversión separados — retoma

## PUBLICADO Y VERIFICADO · 07/10 05:02 UTC

**Entrega funcional cerrada.** La otra sesión integró #212 y publicó el frontend. Verificación independiente de esta tarea: Main fuente limpio = `avancecorp/main` = `3bdfded2c8130a3e8843d5320516f4691de933f3`; árbol de la aplicación idéntico al Main `e255e96d` probado con 6.286 tests y Docker F5 13/13. El único cambio posterior es documental. Se conserva la ascendencia de la publicación de capital renovado.

- Release real: `crm-20261007T045431Z-3bdfded2c813`; build servido `build-20261007T045430720Z`; ZIP SHA-256 `053780737f010276acda83b6d6cf8c035ac4e3f947e179ff820eaf9f593afafd`.
- HTTPS PASS: 155 archivos comprobados, 141 con bytes/hash exactos, 13 imágenes disponibles y `.htaccess` protegido; portada y versión exactas, ZIP no público (404), cero fallos.
- UI productiva con Gerencia PASS en **Qorilazo y Prodelco**: «Registrar upgrade» visible y habilitado, «Reinvertir desde esta inversión» separado y habilitado, «Registrar nueva inversión» deshabilitado. Se abrieron fichas de inversiones vigentes, sin crear operaciones financieras ni entrar al formulario escritor.
- Postflight SQL productivo 05:01 UTC PASS: siete huellas exactas, ACL/helpers/RLS/tipos correctos; no se reaplicó SQL ni se recreó una rama.
- Evidencia: `output/upgrade-cooperativas-20261006/deploy/cierre-publicacion.json`, `postflight-https.json`, `postflight-sql-final.json`, `qorilazo-botones.jpg` y `prodelco-botones.jpg` (recortes sin datos personales).
- #211 permanece abierto con CI PASS: corrige solo la sincronización de una prueba de gráficas. La repetición aislada corregida pasó sin retry. No afirmar que ese cambio de test esté integrado ni que la suite completa original tuviera cero reintentos.

Los candidatos anteriores nunca se publicaron desde esta tarea. No repetir despliegue ni permisos. Las secciones siguientes son historial y sus pendientes de publicación quedan superados por este cierre.

## REANUDADO por Miguel · 07/10 03:41 UTC

**Corte 04:43 UTC — pendiente de integración/publicación a cargo de la otra sesión:** PR **#212**, https://github.com/avanza-digital/avancecorp-crm/pull/212, head `4777b32199da75568efe467af2809d2bdeaba69b`, controles `verify`, `preflight` y `cambios` PASS; app-check/preview omitidos por delta documental. GitHub `mergeable_state=blocked`: requiere revisión y resolver la regla de historial lineal para conservar la ascendencia. Miguel indicó que lo termina la otra sesión; no asumir esa rama, alterar reglas ni duplicar publicación.

El merge `31ff0744` tiene árbol completo idéntico a Main `e255e96d`; `4777b321` añade únicamente `docs/publicaciones/2026-10-07-reconciliar-main-capital-publicado.md`. Candidato de la otra sesión `crm-20261007T043916Z-4777b32199da.zip`, SHA-256 `f98edf601bacdd73b6598faaddb6225b3b2311e1df58f46079621b5c2c523fe3`, build `build-20261007T043915352Z`, validado pero **NO confirmado en producción**. Fuente, equivalencia, ascendencia de Main y del vivo y hash comprobados en `output/upgrade-cooperativas-20261006/deploy/validacion-candidato-conjunto.json`.

Última web verificada: `build-20261007T034648905Z`, todavía sin Upgrade cooperativo. UI Qorilazo real: Nueva inversión deshabilitada, Reinvertir presente, Upgrade ausente en esta versión anterior. **HTTPS del nuevo paquete y UI de Upgrade Qorilazo/Prodelco: NOT RUN, despliegue pendiente.** No se crearon inversiones productivas. Postflight SQL fresco 04:38 UTC: 7/7 huellas, ACL, RLS y tipos PASS, evidencia `deploy/postflight-sql-publicacion.json`.

Al continuar: consultar primero la versión viva y #212 para no publicar dos veces; identificar el manifiesto realmente instalado (puede ser otro construido desde Main después de la integración). Ejecutar `/private/tmp/upgrade-cooperativas-remoto-20261006/postflight.mjs <manifiesto-real>` y verificar los botones en ambas cooperativas desde Cartera. El candidato propio `ad111817` sigue superado y nunca fue publicado. PR #211 es una corrección solo de sincronización E2E, CI PASS, abierta. Backend y rama temporal ya están cerrados; no repetir SQL, crear otra rama ni volver a solicitar autorizaciones ya concedidas.

**Actualización 04:36 UTC:** CI de #211 PASS (`verify`, `app-check`, `preflight`, `cambios`; preview Supabase omitido), todavía abierta. Evidencia de la otra entrega en Main `e255e96d`: check **6.286 tests / 392 archivos PASS** y Docker F5 **13/13 PASS**, copiada con huellas en `equivalencia-main210.json`, `check-integrado-main210.log` y `e2e-main210-f5-PASS.log`. La otra sesión prepara `rescate/cierres-cliente-main-20261007` desde el commit vivo `dfb8874d`, con merge de Main en curso; no modificar su copia ni duplicar publicación. Frontend público aún `build-20261007T034648905Z`. Verificación visual de lectura en Qorilazo: Nueva inversión deshabilitada, Reinvertir disponible, Upgrade aún ausente; pendiente comprobar después del deploy. No se ejecutaron operaciones financieras.

**Actualización 04:26 UTC:** el caso aislado de gráficas reprodujo el fallo (sin retry): el menú móvil se desmontó durante el clic tras cambiar a escritorio. Se añadieron dos esperas `toBeHidden()` después de los cambios de viewport, sin quitar aserciones ni ampliar tiempos. El mismo caso pasó **1/1 en 7,2 s, sin reintentos**. Corrección solo de E2E, commit `418d7930`, PR **#211**: https://github.com/avanza-digital/avancecorp-crm/pull/211. No altera el frontend del artefacto. Logs `e2e-graficas-aislada-fallo.log` y `e2e-graficas-corregida-PASS.log`; CI de la PR en curso. La copia limpia volvió a Main e hizo FF a `e255e96d` (#210), sin cambios locales.

**Cambio concurrente del sitio:** otra entrega publicó `build-20261007T034648905Z`, paquete `crm-20261007T034649Z-dfb8874d534b.zip`, fuente `dfb8874d534bc6462432dee00298f022e4437a0b` (padre `4e6ee7ee`; todavía SIN #208/#209). SHA-256 `47070ef4c08e5f1e3c1d5cc371abfcbc208d07fcbce9f5ba5ec6571b73565ca2`, manifiesto en `CRM-Avance-Corp/releases/`. Main remoto ahora `e255e96d3d0ef39c55eedd29a9c879bf13822b91`, squash de #210 sobre #209. Nuestro candidato `ad111817` queda **SUPERADO y NO PUBLICADO**. No subirlo. La otra sesión ya verificó el check de #210 y terminó/termina su F5; prepara la publicación conjunta desde Main. Debe reevaluar el preflight contra la nueva versión viva (el guard usa ascendencia Git). Si lo rechaza, seguir la rama de rescate autorizada por CLAUDE.md; nunca saltarlo. No asumir ni duplicar su publicación.

**Actualización 04:17 UTC:** la otra sesión completó #209 en Main `ad111817`: Docker **43 passed / 13 skipped / 0 failed / 0 flaky**, ocho especificaciones, 3,7 minutos. Log copiado como `output/upgrade-cooperativas-20261006/e2e-pr209-final.log`; huella y equivalencia guardadas. Esperar su publicación y verificarla; no duplicar el deploy. El banco quedó libre y se inició la comprobación aislada de `graficas.spec.ts:36`, sobre Main `ad111817`, con un worker y **sin retries**. Fuente limpia y `release:crm`/preflight ya PASS.

**Candidato propio 04:13 UTC, NO publicado:** `crm-20261007T041303Z-ad111817c480.zip`, SHA-256 `f4dab3b0cc16ece983d33888f4fb38808701ba29a646732b5ecd71fc805d8f25`, dentro de `releases/` del clon limpio. `release:crm`, `release:crm:verify` y preflight Hostinger PASS. Main fuente `ad111817`; paquete y huella registrados en `output/upgrade-cooperativas-20261006/deploy/candidato.json`. La otra sesión confirma E2E #209 en curso sobre ese mismo Main y es responsable de terminar/publicar su entrega; comprobar el sitio antes de subir un candidato propio.

**Actualización 04:12 UTC:** E2E completo propio sobre `62a375f0` terminado con exit 0: **369 passed / 1 flaky / 26 skipped / 0 failed**, 29,9 minutos. El único reintento fue `e2e/graficas.spec.ts:36` al alternar móvil/escritorio; pasó en el retry. Log y resumen: `output/upgrade-cooperativas-20261006/e2e-completa-final.{log,json}`. Traces conservadas en `/private/tmp/upgrade-cooperativas-remoto-20261006/e2e-completa-final-artifacts/`. No afirmar cero retries.

Después de finalizar, la copia limpia hizo FF a `ad111817`, Main = remoto; se conservó intacto su árbol durante toda la prueba. `npm run check` del #209 es reutilizable por identidad completa de árbol con `5683dbdf`: 6.279 pruebas PASS, evidencia copiada como `check-integrado-pr209.log` y `equivalencia-pr209.json`. La otra sesión ya ejecuta las ocho especificaciones del #209 en `avancecorp-cierre-independiente-e2e`; esperar ese resultado y no publicar en paralelo. Se prepara un candidato desde el Main limpio, todavía NO publicado. Comprobar aparte la prueba de gráficas cuando quede libre el banco.

**Actualización 03:58 UTC:** PR #209 fusionado a las 03:56:36 UTC, Main remoto `ad111817c48043ab3cd2945944c8cdd42633c075`, árbol idéntico a su head probado `5683dbdf`. Se hizo fetch en ambas copias, pero **no se cambió el árbol de la copia limpia mientras corre el E2E completo** sobre `62a375f0`. Esperar su final antes de integrar el nuevo Main ahí. La otra sesión termina/publica #209, según Miguel; comprobar versión viva antes de subir otra vez.

La sesión de capital renovado creó entretanto dos commits en el Main del taller compartido: `dfb8874d` y `cdad1f43` (remoto `avancecorp/codex/cartera-capital-activo`). El taller ahora está ahead 2 / behind 1 respecto del Main remoto; **no resetearlo ni borrar esos commits**. La alineación anterior fue correcta y está respaldada, pero este cambio concurrente la supera. La fuente de publicación debe ser el Main limpio del clon de release, igual al remoto vigente, preservando ese trabajo ajeno.

**Actualización 03:50 UTC:** Miguel confirmó que **la otra sesión termina #209**. No asumir ni modificar esa PR. Antes de publicar, comprobar si esa sesión ya subió el Main integrado para no duplicar la publicación.

El plan de alineación **ya se aplicó con PASS** tras aprobación del permiso de filesystem: Main del taller original y de la copia limpia = `avancecorp/main` = `62a375f0`. Se actualizaron 113 archivos mediante merge de tres vías, se verificaron **374 archivos ajenos intactos**, sin nada staged. Las cinco resoluciones y los respaldos están en `output/upgrade-cooperativas-20261006/deploy/alineacion-main-20261007T0343/resultado.json`. La marca anterior de «plan preparado, NO aplicado» queda superada. El ledger de la migración y la nota del vault ya reflejan SQL productivo instalado y frontend pendiente.

Miguel indicó «sigue». Main remoto y copia limpia continúan en `62a375f0`; frontend vivo sigue `build-20261006T213354829Z`. Backend Upgrade y #207 presentes; funciones de llamadas y Edge `crm-llamadas-ingesta` aún ausentes.

- E2E completo reanudado con un worker y volumen exclusivo: sesión **2160**, contenedor `crm-upgrade-20261006-gate-one-worker`, 396 casos configurados. No atribuir PASS antes del resumen final.
- Nueva evidencia de coordinación: la otra sesión preparó PR **#209**, head `5683dbdfb650c704363b9e0e5ff3e29d77d4f99f`, para publicar Main dejando `LLAMADAS_CELULAR_APROBADAS=false`. Incorpora #208, mantiene el registro v4 y condiciona consultas/formulario/receptor/store. GitHub verify/app-check/preflight PASS; PR abierta, ya no draft. Su acta local conserva la pausa y E2E incompletas. Se preguntó a Miguel si la termina la otra sesión o la asumimos aquí; no se modificó esa rama ni su PR.
- Plan fresco de alineación del taller original en `output/upgrade-cooperativas-20261006/deploy/alineacion-main-20261007T0343/plan-resuelto.json`: **solo preparado, NO aplicado**. Cinco conflictos resueltos conservando WIP de renovación, actas productivas de #207 y ambos avisos históricos del vault. Revalidar contra el Main definitivo y cambios concurrentes antes de aplicar.
- Evidencia propia remota/local copiada y con huellas en `output/upgrade-cooperativas-20261006/verificacion-huellas.json`; las credenciales de la rama eliminada no se copiaron.

La pausa anterior queda como historial. La autorización de publicación sigue vigente; resolver dependencia #190 mediante su backend verificado o #209 integrado y verificado antes de publicar.

## PAUSADO por Miguel · 07/10 01:38 UTC

Miguel pidió «pause en un momento seguro». Se detuvo únicamente el contenedor propio `crm-upgrade-20261006-gate-one-worker`; la sesión 70265 terminó con exit 143. La repetición E2E queda **INCOMPLETA, no PASS**, con log `output/upgrade-cooperativas-20261006/e2e-completa-pausada.log`. No quedan operaciones productivas en curso de esta tarea. No reanudar hasta que Miguel lo indique.

Punto seguro: SQL aprobado instalado y postflight productivo PASS; rama remota propia eliminada y credenciales temporales borradas; PR208 fusionado; frontend NO publicado. No se modificaron los servicios ni contenedores de otras sesiones.

Se preparó solamente un **plan de alineación**, NO aplicado, para el taller original: `output/upgrade-cooperativas-20261006/deploy/alineacion-main/plan.json`. Main original sigue `4e6ee7ee`, con su trabajo ajeno intacto; su seguimiento remoto ya es `62a375f0`. El plan detectó cinco conflictos (Inicio.md, f5-cartera.spec.ts, dos actas de #207 y MIGRACIONES.md); conserva base/local/target, pero habrá que regenerarlo y verificar cambios concurrentes antes de usarlo. Main de la copia limpia sí coincide con el remoto `62a375f0`, con árbol idéntico al head probado `39f9e0e7`.

Al retomar: comprobar estado de #190 a cargo de otra sesión; completar E2E Docker (1 worker por memoria), resolver/alinear Main sin perder WIP, construir/verificar artefacto del Main vigente, preflight Hostinger, publicar y verificar HTTPS/UI. No repetir autorizaciones de SQL, rama o frontend ya concedidas.

## Estado verificado antes de la pausa · 07/10 01:37 UTC

**Backend de Upgrade instalado y verificado en producción; frontend todavía pendiente.**

- PR #208 fusionado el 07/10 a las 01:31:59 UTC: `62a375f0e23a220952489148c6f8e07357a053e8`. Su árbol es idéntico al head probado `39f9e0e7`; Main de la copia limpia ya coincide con `avancecorp/main`.
- Matriz RLS remota final: **3.076 PASS, cero fallos**. Omisiones declaradas: llamadas aún no instaladas, variante de nombre canónico sin fixture y canario de meses cerrados sin datos. Los dos fallos previos de fixtures se corrigieron y la tercera corrida íntegra pasó.
- Matriz SQL propia remota: **8 grupos PASS**. HTTP/Auth/Storage reales: **PASS**, incluyendo comprobante, confirmación, reintento único, inversión original intacta, historial Upgrade y Reinversión separados y permisos negativos.
- SQL aprobado integrado mediante `merge_branch`; postflight productivo PASS: las siete funciones tienen huellas exactas, ACL correctas, helpers privados, columna/tipos y RLS correctos. Historial anterior intacto; la plataforma segmentó el archivo en 22 sentencias. Catálogo cambió únicamente lo aprobado y las 22 Edge Functions quedaron idénticas.
- Advisors productivos: seguridad 337→338 por el RPC autenticado SECURITY DEFINER intencional; evaluación y enlace oficial en `output/upgrade-cooperativas-20261006/postflight-produccion.json`. Rendimiento 212→212, sin delta. No se afirma cero advertencias.
- Rama de pago `fe1a6347-0b3c-4618-9a8f-8f85c4aa7bd1` **eliminada**, ausencia verificada. Credenciales temporales `branch-credentials.json` y `password` eliminadas del directorio privado.
- Suite completa Docker con 2 workers interrumpida (exit 143) después de confirmar **OOMKilled=true**; hubo cierres de Chromium y timeouts. NO PASS. Log conservado en output y traces en el directorio privado `e2e-oom-artifacts/`. Repetición íntegra con **1 worker**, contenedor/volumen propios: sesión **70265**, detenida por la pausa de Miguel; no obtuvo resumen final.
- #207 backend ya está en producción. #190 SQL/Edge de llamadas sigue ausente al último control; otra sesión se encarga. No publicar su consumidor ni asumir esa tarea.
- Publicación Hostinger aún NO realizada. Falta gate E2E completo, backend #190 y verificación final de Main antes de construir/subir.

Las secciones siguientes conservan el historial; sus estados pendientes antiguos quedan sustituidos por este corte.

PR: https://github.com/avanza-digital/avancecorp-crm/pull/208
Rama: `fix/upgrade-cooperativas`. Commit: `39f9e0e7cfe4f9e6ffea34e529b2de982676c306`.
Copia limpia: `/private/tmp/crm-continuidad-release-20261006`.
El taller original se conserva con sus cambios ajenos. No publicar desde su árbol sucio.

Decisión de Miguel: sí, Upgrade y Reinversión separados en Qorilazo y Prodelco.
Upgrade registra solo aporte adicional, con depósito y comprobante nuevos, vinculado a una inversión vigente de la misma persona y empresa. Conserva el original y el bloqueo global de Nueva inversión. Avance conserva su flujo.

## Hecho

- Implementación y migración preparadas, versionadas y subidas en el PR #208.
- Integrados #190 y #207 de `avancecorp/main` (`a0c334ba`). Conflicto solo documental resuelto conservando ambos aportes.
- `npm run check`: PASS, 392 archivos y 6.275 pruebas, lint/typecheck/build/bundle.
- Docker local: PASS, 26/26 E2E de cartera, postventa y cierre de ficha.
- SQL real local: PASS, permisos, fuentes, recuperación, ficha/historial, reversa y replay de migración definitiva.
- Concurrencia con dos conexiones: PASS, sin duplicación ni registro parcial al anular.
- Scripts/seed/RLS/Edge preflight: PASS. Seed/RLS offline, no equivalen a matriz remota.
- Claude review LEVEL 3: CHANGES_REQUESTED; PRIMARY cerró hallazgos con correcciones y pruebas. Segundo intento devolvió salida vacía/sin dictamen válido; no afirmar PASS final ni consultar una tercera vez.
- Evidencia preservada: `output/upgrade-cooperativas-20261006/` con SQL, reversa, guía, logs y hashes.

## Pendiente antes de publicar

1. Aprobación del SQL exacto por Miguel (Inicio.md pide mostrar SQL y esperar confirmación).
2. Rama Supabase equivalente, aplicar solo la migración de Upgrade, matriz RLS/advisors. Ninguna escritura remota se ha ejecutado para esta tarea.
3. Aprobación y squash/merge del PR #208: main exige una revisión aprobada y controles `verify`/`preflight`, sin auto-merge. No saltar las reglas con admin.
4. Integrar el main remoto sin sobrescribir los cambios ajenos, construir desde main local/remoto iguales; preflight Hostinger y publicar. No asumir que `a0c334ba` siga siendo el tip.
5. Verificación productiva de lectura y botones. No crear inversiones reales para probar.

No está aplicado ni publicado. La autorización previa de despliegue del frontend continúa; esta solicitud SQL es nueva y concreta.

Banco local exclusivo: contenedor `supabase_db_avancecorp-pr190-20261006`, base `upgrade_cooperativas_20261006`. El banco conserva datos sintéticos de concurrencia; usar `banco.mjs replay` para repetir, no `test` con los mismos DNI. El banco general de otras tareas no se modificó.

## Autorizaciones posteriores y rama remota

Miguel autorizó explícitamente el SQL exacto de `39f9e0e7` y publicar, y después crear la rama temporal a US$0,01344/h. No volver a pedir esos permisos.
Rama propia: `upgrade-cooperativas-20261006`, id `fe1a6347-0b3c-4618-9a8f-8f85c4aa7bd1`, proyecto `zwezlorzqybwelmxnlje`. Creada el 06/10 a las 23:52 UTC; borrar al terminar. Las otras ramas NO pertenecen a este encargo.
El replay histórico se detuvo en la migración `20260811210049` (86/432). Reconstrucción autorizada con esquema/configuración/historial productivos, sin clientes reales. Herramientas con destino fijo y credenciales privadas: `/private/tmp/upgrade-cooperativas-remoto-20261006/`. Nunca imprimir `branch-credentials.json` ni `password`.
Catálogo anterior: 138 tablas, 972 funciones, 130 policies, 1.034 restricciones, 432 migraciones. Pendiente verificar paridad final tras preservar CR de cadenas SQL y luego aplicar únicamente la migración aprobada, seed/matriz/RLS/advisors.
GitHub verify/app-check/preflight PASS; revisión humana del PR todavía pendiente.
Dependencia de publicación: Main también incorpora #207; `crm.gestiones_resumen_fn(date,date,uuid[])` aún no existe en producción a las 23:58 UTC. Su rama propia `cierre-gestiones-clientes-20261006` pertenece a otro trabajo. No publicar su consumidor hasta que su backend esté listo, ni instalar ese SQL ajeno desde esta tarea.

## Avance remoto 07/10 00:17 UTC (06/10 Lima)

- SQL aprobado aplicado y registrado SOLO en la rama `zwezlorzqybwelmxnlje`, versión exacta `20261006221545`, nombre `crm_upgrade_cooperativas`, statements[1] idéntico al archivo. SHA256 del SQL: `1a5caac35c5bbf6c10764dfee97f3f582ad2f2ad22f56e5d0774efd65adf1bbe`. Aún NO en producción.
- 7 huellas finales coinciden con Docker; RPC solo authenticated, sin anon/service.
- Paridad previa final: tablas/RLS, 972 cuerpos/dueños/ACL/comentarios, policies e historial íntegros. Solo 3 CHECK cambian agrupación redundante de paréntesis AND al restaurar; condiciones equivalentes. Se preservaron CR dentro de cadenas y repusieron dos comentarios internos que el exportador filtró.
- Seed remoto PASS. Matriz SQL propia remota PASS en 8 grupos, con rollback. La adaptación `test-remoto.sql` elige al supervisor negativo FUERA de todos los antecesores: el seed tiene supervisión anidada y el test local solo excluía al supervisor inmediato. No es una falla del permiso de producto.
- Gate general RLS remoto EN CURSO, sesión exec 94418, log `/private/tmp/upgrade-cooperativas-remoto-20261006/rls.log`. No iniciar escrituras adicionales en la rama mientras corre.
- Prueba HTTP de RPC + Storage reales preparada y sintaxis PASS: `/private/tmp/upgrade-cooperativas-remoto-20261006/test-http.mjs`. Ejecutar DESPUÉS del gate general (crea fixtures adicionales). Usar `node /private/tmp/upgrade-cooperativas-remoto-20261006/run-banco.mjs --log upgrade-http.log node /private/tmp/upgrade-cooperativas-remoto-20261006/test-http.mjs`.
- Advisors rama: seguridad 335→337; nuevo aviso intencional de RPC `crm.preparar_upgrade_fn` DEFINER ejecutable por authenticated (misma frontera que reinversión; permisos/persona/empresa validados en núcleo, search_path vacío, tablas y helpers sin escritura/EXECUTE directos). Documentar justificación, NO afirmar cero alertas brutas. Otro aviso de contraseña filtrada pertenece a Auth del banco y ya estaba en baseline productiva, sin cambio de configuración. Rendimiento 322→297, cero avisos nuevos. Comparar sin `observed_at`, no con el JSON temporal entero.
- Miguel dijo que aprobará y fusionará #208. Aún verificar en GitHub antes de construir; la última consulta lo veía abierto.
- SQL productivo, merge_branch, postflight y frontend siguen pendientes. No aplicar migraciones de #207/#190 ajenas a este encargo para destrabar el frontend.

## Avance remoto 07/10 00:37 UTC (06/10 Lima)

- Miguel confirmó que **otra sesión termina #207 y #190**. Esperar sus servicios antes del frontend; no asumir su tarea ni modificar su rama.
- Gate RLS inicial terminó: 3.073/3.074 PASS. Único fallo B7: exigía `relacl is not null` en tres tablas; el dump había normalizado a NULL sus ACL de propietario. Comparación de 152 tablas/vistas/secuencias y grants por columna: permisos efectivos IDÉNTICOS a producción; diferencia de representación, sin permisos extra. Se materializó solo `GRANT ALL ... TO postgres` en las tres tablas del banco; el mismo control devuelve 3/3.
- Repetición integral EN CURSO: sesión **72460**, log `rls-repeticion.log`. No escribir en la rama mientras corre. Se limpió y resembró el banco: la limpieza versionada hizo COMMIT pero su último UPDATE de domicilio fue rechazado por el trigger inmutable; se restauró el domicilio del cliente ficticio con replica en la rama propia. `seed-repeticion.log` y `domicilio-fixture.log` PASS.
- El gate inicial omite llamadas (no instaladas en producción) y un caso de nombre por perfil canónico cuyo fixture ya tiene identidad. Reportar como NOT RUN/omitidos, sin inventar cobertura.
- HTTP/Storage real sigue PENDIENTE; ejecutar `test-http.mjs` únicamente después del gate. `postflight.sql` readonly preparado y probado en la rama: migración exacta + siete huellas + ACL/helpers/RLS/columna PASS.
- Catálogo fresco: producción sin deriva desde baseline (432 migraciones); rama 433, solo 3 funciones añadidas/4 modificadas, nueva columna/constraint y ampliación del tipo de historial. Las 22 Edge Functions coinciden exactamente. Persistencia adicional en functions.store: `upgrade_premerge_catalog_0/1`, `upgrade_premerge_edges_2/3`, `upgrade_premerge_diff`, `upgrade_acl_0/1`, `upgrade_postflight_sql`.
- Realidad de Upgrade en producción: cuatro banderas requeridas ON; 41 fuentes Qorilazo y 11 Prodelco vigentes. Sin datos de clientes expuestos.
- PR #208 seguía abierto/sin fusionar a las 00:33 UTC. El sitio conserva build `build-20261006T213354829Z`.
- Scripts `publicar.mjs` y `postflight.mjs` adaptados al directorio privado de esta tarea; sintaxis PASS. Aún NO ejecutados, no existe artefacto nuevo desde main integrado. El frontend sigue esperando PR208 + servicios de la otra sesión.

## Avance 07/10 00:54 UTC

- La otra sesión instaló #207 en producción: ahora 434 migraciones. Catálogo respecto de baseline: solo 12 funciones nuevas y `crm.postventa_tarea_fn` modificada; nada coincide con las 7 de Upgrade. Las 22 Edge siguen iguales. Guardado `catalogo-prod-con-207.json`; preparar **rebase_branch** al finalizar el gate, para incorporar esas 2 migraciones a nuestra rama (sin reset). #190 llamadas aún ausente.
- PR208 continúa abierto, sin revisiones (`reviews=[]` a las 00:49 UTC). No publicar frontend antes de la fusión humana y backend completo.
- Gate segunda corrida sesión 72460: el B7 corregido ya PASS, pero hay UN fallo de fixture bancario: `cliente_detalle_fn` muestra la última cuenta activa `BANCO RLS IDEM` creada en la corrida anterior. El seed conserva su cuenta fija sin retirar las antiguas. El mismo control pasó en la primera corrida; ninguna función bancaria cambió. NO declarar la segunda corrida global PASS.
- Preparados (NO ejecutados): `limpiar-fixtures.sql` (limpieza del banco adaptada para domicilio inmutable), `restaurar-cuenta-fixture.sql` (desactiva solo otras cuentas PEN del usuario sintético, preserva UUID fijo), `preflight-fixtures.mjs` (verifica ACL B7 y lectura bancaria por supervisor mediante API real). Ejecutar tras terminar 72460, sin escrituras concurrentes. Luego repetir el gate apropiado; si se repite completo tras rebase, guardar un tercer log separado.
- Gate de realidad prod ejecutado mediante `realidad-produccion.mjs` sin guardar credenciales: 8/9 mediciones; sale 2 por lectura denegada de `periodos_cerrados` con service_role (no se alteraron ACL prod). SQL complementario readonly: metas bajo el sello=0. Divergencia preexistente: 277 clientes Avance sin domicilio legal; el alta cooperativa se prueba sin domicilio. Artefactos `realidad-produccion.json` y `realidad-produccion-complemento.json`.
- Importante historial: Supabase merge resegmenta SQL (migraciones #207 quedan en 4 y 36 statements). `postflight.sql` ya distingue registro válido/huellas exactas del formato del historial; no exigir que prod conserve un único statement. En rama aún es 1 y md5 exacto `79178bd4ec36f0e6dbc852e9dce70a97`. Las 7 definiciones/ACL/default/RLS siguen PASS.
- Documentación oficial MCP verificada: merge_branch aplica incrementalmente migraciones pendientes; rebase_branch trae incrementalmente las nuevas de producción; no copiar datos ni diff destructivo de catálogo. Fuente: https://github.com/supabase/mcp/blob/main/docs/production.md.

## Avance 07/10 01:09 UTC

- Rebase Supabase COMPLETO: rama en `FUNCTIONS_DEPLOYED`, 435 migraciones; producción 434. Solo Upgrade pendiente de integrar. Catálogo de rama contra prod actualizado conserva únicamente los cambios aprobados de Upgrade y las tres diferencias inocuas de paréntesis CHECK del dump. Historial previo intacto.
- Segunda corrida terminó FAIL por 1/3.076 aserciones (solo cuenta ficticia residual; B7 PASS).
- Limpieza final y seed PASS. La retirada de cuentas ficticias exige `desactivada_en`; el primer UPDATE sin fecha se revirtió por CHECK. Adaptación corregida con fecha/autor: `restaurar-cuenta-fixture-final.log` PASS. No cambia esquema ni datos reales.
- `preflight-fixtures.mjs` PASS por API real: supervisor recibe cuenta `BANCO DEMO` y tres ACL B7 explícitas correctas.
- **Gate integral final EN CURSO: sesión 2021**, inició 01:07:27 UTC, archivo `rls-final.log` en el directorio privado. Más de 400 PASS sin fallos al último corte. No escribir en la rama mientras corre.
- Después: `test-remoto.sql` con rollback, `test-http.mjs` real, advisors/catálogo/Edge frescos; merge_branch solo si únicamente Upgrade falta en prod; postflight; eliminar la rama de pago. No repetir permisos ya concedidos.
- Main sigue `a0c334bae19c54885fcf4c02adcf34c4c85ae83a`, PR208 sin revisión humana ni merge. Sitio sigue `build-20261006T213354829Z`. No construir/publicar frontend hasta PR208 y backend de llamadas de la otra sesión listos.
