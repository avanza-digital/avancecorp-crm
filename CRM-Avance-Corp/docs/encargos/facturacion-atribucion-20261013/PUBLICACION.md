# Atención y dueño de venta: publicación verificada

Publicado el 13/10/2026, aproximadamente 20:22–20:24 Lima (14/10 UTC). Los cuatro pasos autorizados están completados: integración F4/baja, duplicados resguardados, publicación de backend/CRM/portal y corrección de la venta real.

## Resultado de negocio

La venta **2026-01-001595**, del 11 de octubre y por **S/150.000**, pertenece a **Jorge Marzano**. Facturación publicada, recargada tras el despliegue, muestra para ese día **Jorge S/150.000 y Fiorella S/0**; el detalle contiene exactamente ese contrato y una operación.

La corrección se hizo el 13/10 a las 18:12 Lima desde la sesión real de Gerencia y la puerta auditada existente. Auditoría única `04d3aee0-7fc5-42f8-baef-e474bbc5044a`. Las otras 74 operaciones de octubre, el capital global por moneda, el registrador y la atención del cliente quedaron iguales. Se reconfirmó después de publicar el backend nuevo. [Evidencia de la corrección](correccion-real-verificada.json).

Ya están publicadas las dos acciones separadas: cambiar quién atiende al cliente y corregir el dueño de una venta. Ambas revisan el efecto en el servidor antes de guardar. Atención completa: Gerencia y administradores activos del portal, con revocación CRM prevaleciente. El núcleo privado autoriza, bloquea conflictos y verifica las consecuencias; el cambio directo de asesor queda rechazado.

## Código y publicación

| Componente | Fuente publicada y verificación |
| --- | --- |
| Backend | Dos migraciones de la rama probada, incorporadas con `merge_branch` y comprobadas en producción |
| CRM | Commit `6dd9fbb6c6ee234acf5993b09c49c97611151b75`, [PR 274](https://github.com/avanza-digital/avancecorp-crm/pull/274), servido en https://crm.miavance.com |
| Portal | Commit `cb2b388f4d4995df06836fb19d47140a7b22438f`, repositorio privado [avanza-digital/avancecorp-portal](https://github.com/avanza-digital/avancecorp-portal), servido en https://miavance.com |

Antes de construir y publicar el CRM, Main local y `avancecorp/main` apuntaban al mismo commit `6dd9fbb6`. Se incorporó el avance remoto y se conservó el diff ajeno byte por byte. El artefacto se construyó en una copia limpia de ese commit. No se usó `origin/main`, otra rama de release ni force push.

PR 274: `verify`, `preflight` y `app-check` terminaron PASS. El push directo fue rechazado por la protección y no modificó el remoto. La integración posterior se realizó por PR con la excepción **OrganizationAdmin, modo pull_request**, ya configurada, usando `--match-head-commit` y únicamente después de los checks verdes. No se alteraron protecciones ni se inventó una aprobación humana de GitHub. Las revisiones independientes de Claude y su evaluación están conservadas en esta carpeta.

Artefacto CRM: `releases/crm-20261014T012056Z-6dd9fbb6c6ee.zip`, SHA-256 `c4a433206c1c11d12ff42bc72d975fe82a28f5f983aa0ed2d6a48ee040bc6604`. Build publicado: `build-20261014T012055587Z`. `release:crm`, verificación del paquete y preflight Hostinger: PASS. El commit vivo anterior era ancestro del candidato.

Portal: se corrigió origin al repositorio confirmado por Miguel, se reactivó conservando su privacidad y las ramas históricas, y se creó main con el historial real del portal. Main local y remoto coinciden en `cb2b388f`. Se publicaron exclusivamente `js/atencion-cliente-api.js`, `js/admin/clientes.js`, `admin/clientes.html` y `service-worker.js`; el service worker v141 fue el último y se purgó caché. Los tres archivos preexistentes coincidían con el padre del commit antes de subir; quedaron respaldados.

## Backend efectivo

- `20261013192850_crm_atencion_venta_separadas.sql` y `20261013193653_crm_atencion_venta_hardening.sql` instaladas.
- Ledger: **473 migraciones**. Los 471 registros anteriores conservaron versión, nombre y huella de sentencias.
- Las **12 funciones** afectadas coinciden exactamente con la rama ensayada: definición, propietario, configuración y ACL.
- Trigger `aaa_asesor_solo_nucleo` activo en `public.perfiles`; venta corregida y auditoría única conservadas.
- Flags previos requeridos activos; ningún cambio de flags como parte de esta publicación.
- **23 Edge Functions** cotejadas antes del merge. Aclaración: la cifra «22» en el acta de preparación era un error de conteo documental; el inventario efectivo contiene 23. No se publicaron cambios de Edge.
- El merge de Supabase serializa las sentencias del ledger: su MD5 no equivale al del archivo SQL completo. La identidad desplegada se comprobó con las definiciones y ACL efectivas, además del ledger anterior intacto.

Advisors de seguridad antes/después: RLS sin política 86/86; extensión en public 1/1; DEFINER anon 2/2; DEFINER authenticated 280/282; protección Auth de contraseñas filtradas 1/1. Los dos avisos añadidos corresponden a las dos puertas CRM mínimas, deliberadas, con ejecución authenticated y autorización real en el núcleo privado. Sin nuevas categorías de avisos de rendimiento; los avisos preexistentes no se presentan como resueltos.

## Verificación de cierre

| Comprobación | Resultado |
| --- | --- |
| CRM integral | PASS: lint, tipos, cobertura, build, 417 archivos / 6.676 pruebas y duplicación 0,43 % |
| E2E CRM completo en Docker | 409 passed / 2 failed / 1 flaky / 26 skipped; dos selectores antiguos corregidos y repetidos: 4 passed |
| E2E final desde commit limpio, Docker | PASS: 23 pruebas de gráficas, postventa F6 y ficha multiempresa; incluye el test original de gráficas sin el cambio ajeno del working tree |
| RLS completa tras la última guarda | PASS: 3.933 aserciones |
| Integración Auth/API | PASS: 83 local + 83 rama remota; roles, bajas, idempotencia y escrituras directas denegadas |
| SQL y concurrencia real | PASS: 29 aserciones; dos conexiones, un ganador, un PT409, una auditoría y capital conservado |
| F4 Auth/API/Storage | PASS: cinco cortes de recuperación |
| Portal | PASS: 209 pruebas Node, sintaxis y recorrido del HTML/módulos reales en Chromium Docker |
| Recursos HTTP publicados | PASS: 126 archivos cotejados, incluidos los cuatro del portal, versión y JS/CSS del CRM; index HTML del CRM también coincide con el paquete |
| Pantalla real posterior a publicar | PASS: contrato 001595, Jorge S/150.000, Fiorella S/0 el 11/10, una operación |

Las pruebas completas no repetidas no se convierten en PASS por extrapolación: se conservan sus resúmenes originales y los resultados focales posteriores. El recorrido HTML del portal usa transporte/Auth simulado; la integración local/remota citada sí usa sesiones Auth reales. La variante de baja por Gerencia con rol portal analista no está cubierta por ese caso focal; las nuevas acciones sí cubren ese rol. Los ensayos históricos de referidos tienen expectativas obsoletas: el oráculo vigente separado pasó 16 casos, sin modificar conversión. Detalle en [VERIFICACION.md](VERIFICACION.md) y [EVALUACION-CIERRE.md](EVALUACION-CIERRE.md).

Claude emitió CHANGES_REQUESTED sin P0/P1 en el cierre. El PRIMARY aceptó y resolvió los P2 sobre guarda antigua, inventario de escritores y orden/flags de publicación, y repitió las comprobaciones pertinentes. No se atribuye a Claude un PASS posterior inexistente.

## Recuperación y limpieza

Se conserva el ZIP anterior `releases/crm-20261013T182850Z-4e31dbbf13ef.zip`, SHA-256 `aeda98ff7557268176e0a2cb7f246555c9c55f6689579eb8b44921811b0154b6`, y el respaldo de los archivos anteriores del portal. La reversa SQL restaura código/ACL, no elimina correcciones ni su auditoría.

La rama temporal autorizada **atencion-venta-20261013**, ID `77b7b326-3c2e-4cde-975e-ddb84996d016`, ref `cdntljznxaubchkhusqo`, fue eliminada tras verificar la publicación. El conector devolvió success y el listado posterior confirmó su ausencia. Producción continúa ACTIVE_HEALTHY / FUNCTIONS_DEPLOYED. Las ramas ajenas `banco-f7` y `plan-backend-fase4` quedaron intactas.

Pruebas finales locales: `/private/tmp/atencion-smoke-hosting.json`, `/private/tmp/atencion-postflight-real.json`, `/private/tmp/atencion-e2e-commit-final.log` y `/private/tmp/atencion-facturacion-publicada.png`. La captura quedó también mostrada al usuario; los archivos temporales son evidencia de sesión y no una dependencia de funcionamiento.

Los commits posteriores que únicamente registren esta acta no cambian el artefacto de producto publicado, cuya fuente permanece identificada arriba.
