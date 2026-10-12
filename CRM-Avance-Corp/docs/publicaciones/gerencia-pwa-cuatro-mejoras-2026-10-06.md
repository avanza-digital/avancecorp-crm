# Publicación de las cuatro mejoras PWA de Gerencia — 6 de octubre de 2026

**Publicado y verificado** en <https://crm.miavance.com>. Hostinger aceptó el despliegue a las 09:25 Lima (14:25 UTC); versión y archivos servidos confirmados a las 14:26 UTC. Miguel autorizó «ok deploy», pidió una pausa antes de iniciar la publicación y la reanudó con «sigue».

## Fuente y artefacto

- PR integrado: [#202](https://github.com/avanza-digital/avancecorp-crm/pull/202).
- Commit publicado: `ea3b6ed22a9bc37031bd9c01ca54e694cffb3f11`.
- Build: `build-20261006T140145431Z`.
- ZIP: `releases/crm-20261006T140146Z-ea3b6ed22a9b.zip` (2.483.145 bytes).
- SHA-256 del ZIP: `10995f86d0958020362e5dd012eee4b78d52bd1492d98aadd3ef70ba092adda6`.
- Manifiesto: `releases/crm-20261006T140146Z-ea3b6ed22a9b.manifest.json`.

Main del workspace, Main de la copia limpia y `avancecorp/main` coincidían antes de publicar. Se conservaron los cambios locales ajenos y un respaldo previo a la alineación. La construcción salió de la copia limpia; `release:crm:verify` y preflight obligatorio **PASS**. Se utilizó una sola llamada a la operación vigente `hosting_deploy-static-website` del conector Hostinger habitual.

## Cambios publicados

1. Pendientes prioritarios en Resumen, con el total de la campana y enlace a la bandeja.
2. Bandeja móvil con tarjetas, filtros plegables y recuperación de consulta, posición y foco al volver.
3. Adaptaciones de Gestión Diaria, Citas, Ranking, Metas, Facturación y Cartera para Gerencia móvil.
4. Avisos de conexión y actualización voluntaria aplazable, con ajustes para teclado, viewport y diálogos.

Barra inferior: **Resumen · Citas · Gestión Diaria · Más**. Metas permanece dentro de Más. Esta entrega no aplica migraciones ni modifica permisos o notificaciones del backend.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `npm run check` | **PASS**, 385 archivos y 6.187 pruebas, además de lint, tipos, cobertura, build, bundle y duplicación |
| Equivalencia del código probado | **PASS**, árbol completo del head `742034031aaa52117e15a3cfdbb7649ae74055b7` idéntico a Main publicado |
| Docker local completo | **358 PASS, 2 FAIL, 26 omitidas**, sin reintentos; los dos fallos eran del spec de eliminación anterior al PR #200 |
| Corrección focal de ese spec | **2 PASS**, sin reintentos, después de ajustar el test al flujo vigente; no se cambió producto ni se repitió toda la suite |
| HTTPS | **PASS**, portada y JS principal, 139 archivos con bytes/SHA exactos, 13 imágenes disponibles y `.htaccess` protegido; ZIP público devuelve 404 |
| Versión servida | **PASS**, build exacto del manifiesto |
| Smoke de Gerencia real | **PASS**, Resumen, Pendientes, búsqueda y retorno con foco, Citas, Gestión Diaria, Más y regreso a escritorio |
| Gate automatizado de realidad | **NOT RUN**, falta `SUPABASE_URL` |
| PWA instalada en Android/iPhone físicos | **NOT RUN**, dispositivos no disponibles |

El smoke fue de solo lectura y usó viewport móvil 390 × 844, restablecido al terminar. En un regreso a Resumen el tipo de cambio apareció no disponible; el aviso evitó sumar dólares sin conversión y Reintentar recuperó el dato. Se observaron avisos GSAP de targets ausentes en consola, sin bloqueo de lectura o navegación en este recorrido. Offline y actualización se cubrieron en las pruebas locales, sin forzar esos estados sobre producción.

La validación física pendiente comprende teclado, áreas seguras, segundo plano y recepción de push. La lectura productiva realizada no sustituye el gate automatizado de realidad.

## Evidencia y recuperación

Evidencia en `output/pwa-gerencia-cuatro/deploy/`: `estado.json`, `check-final.log`, logs Docker, `release-verificado.json`, `preflight.log`, `hostinger-recibo.json`, `postflight-https.json`, `smoke-produccion.json`, capturas y respaldo de alineación. Capturas principales: `produccion-resumen-movil.jpg` y `produccion-pendientes-retorno.jpg`.

Se conserva el último ZIP realmente publicado antes de esta entrega: `crm-20261006T045841Z-cce54754f4f1.zip`, SHA-256 `a5a5f41580818a8f93ed8c6b1c1909310103b846c883077d192406b434edfa00`, con su manifiesto. No se ejecutó rollback. Esta acta posterior no cambia el commit fuente del artefacto publicado.


## Aclaración y comprobación posterior — 6 de octubre, 09:40 Lima

El bloqueo registrado como falta de entorno era específico del comando `gate:realidad`: espera `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`, y ninguna estaba exportada. La aplicación sí dispone de su conexión mediante las variables `VITE_*`; eso no configura automáticamente este comando administrativo. Había una vía autorizada mediante el conector Supabase que debió revisarse antes de presentar la comprobación como bloqueada.

Se ejecutaron **las nueve mediciones equivalentes por SQL/MCP en una transacción READ ONLY**, sin cambios de negocio: **ocho supuestos sin divergencia y un aviso de calidad de datos**. Los cinco caminos que contrasta la alarma de conversión coincidieron en **2,76 %**. Se observaron **279 clientes activos con `public.perfiles.domicilio IS NULL`**; se registra el estado de ese campo, sin corregirlo ni atribuir su causa al despliegue.

El comando original continúa **NOT RUN** y su configuración automática sigue pendiente. La lectura SQL equivalente está completada; no acredita el transporte HTTP/PostgREST ni sustituye una prueba de permisos o una auditoría completa del backend. Evidencia: `output/pwa-gerencia-cuatro/deploy/realidad-mcp-20261006T1440.json` y `.sql`.
