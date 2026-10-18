# Atención y dueño de venta: verificación

13/10/2026. Codex PRIMARY; Claude SECONDARY_REVIEWER mediante el wrapper del proyecto. Miguel autorizó implementar, probar y publicar los cuatro pasos, además de corregir la venta real. Backend y pantallas preparados; la publicación de las protecciones se registra por separado al ejecutarse.

**La venta real 2026-01-001595 fue corregida el 13/10 a las 18:12 Lima desde la sesión real de Gerencia en el CRM publicado.** PEN 150.000 pasó de Fiorella a Jorge mediante la puerta auditada existente. Día 11: Fiorella S/0, Jorge S/150.000. De 75 operaciones, las otras 74 quedaron idénticas; capital global por moneda, registrador y atención conservados. Evidencia: [acta estructurada](correccion-real-verificada.json) y [pantalla](correccion-real-facturacion.jpg).

## Reglas implementadas

- Cambiar quién atiende: Gerencia activa y administradores activos del portal. Una membresía CRM revocada prevalece sobre el permiso de administrador. Alinea persona, tramo, perfil, leads abiertos y tareas en una transacción. Gerencia como destino conserva la cartera operativa y se anuncia en la vista previa.
- Corregir el dueño de una venta: mantiene sus permisos anteriores, capital, registrador e historial. No reasigna otras ventas por inferencia. Muestra las operaciones que heredan un upgrade o una baja.
- Ambas pantallas consultan al servidor y confirman una versión del estado. El servidor vuelve a autorizar, toma candados, comprueba versión y postcondiciones con los mismos resolutores de Facturación. Error o conflicto revierte también el historial.
- Los adaptadores antiguos no pueden confirmar atribución efectiva adicional que no mostraron. La atención antigua se rechaza si mueve ventas heredadas; la venta antigua solo puede afectar su contrato directo.
- Se bloquea el UPDATE directo de las columnas de asesor, incluso desde service_role. La edición normal conserva esos campos. Las altas y la revisión F4 usan sus puertas existentes.

Arquitectura: pantalla → módulo de datos → puerta CRM → núcleo private → tablas. Núcleos INVOKER con search_path vacío y ACL cerradas; puertas DEFINER mínimas, solo authenticated, con autorización real en el núcleo. Se conserva la firma pública del portal. No se crean tablas de negocio ni se reescriben fotos selladas.

## Resultados

| Gate | Resultado observado |
| --- | --- |
| SQL con RLS, roles y triggers activos | PASS, 29 aserciones; conservación monetaria, upgrade, desglose, cooperativa, baja, foto sellada y rollback |
| HTTP y concurrencia entre conexiones | PASS: una confirmación escribe, la otra recibe PT409; un historial y capital conservado |
| Integración local Auth/PostgREST | PASS, 83 comprobaciones; 10 actores × 3 acciones, bajas reales, idempotencia, asesor legado y rechazo de atención antigua con venta heredada |
| Integración rama remota | PASS, mismas 83 comprobaciones con sesiones Auth reales y datos sintéticos |
| Matriz RLS completa final | PASS, 3.933 aserciones; repetida tras la guarda final en banco reconstruido |
| Alta/revisión F4 con Auth/API/Storage reales | PASS, cinco cortes de recuperación; evidencia versionada en supabase/scripts/evidencia-f4/revision-responsable-d262d5ef-a529-40ae-a3b2-6bdb8f3be1b5.json |
| Reversa y reinstalación | PASS, funciones y ACL anteriores recuperadas; reinstalación verificada |
| npm run check CRM | PASS, 417 archivos / 6.676 pruebas, lint, tipos, cobertura, build, bundle y duplicación 0,43 % < 0,8 % |
| E2E CRM completo en Docker | 409 passed / 2 failed / 1 flaky / 26 skipped. Los dos fallos eran selectores del texto antiguo; corregidos y repetidos: 4 passed. La prueba flaky pasó al reintentar |
| Portal Node | PASS, 209 pruebas; sintaxis comprobada |
| Portal Chromium en Docker | PASS, HTML y módulos reales; revisión, invalidación, conflicto, confirmación y edición de teléfono sin cambiar asesor legado. Transporte/Auth simulados, sin escrituras productivas |
| Backend preflights | PASS: scripts, seed, RLS y Edge; no sustituyen las pruebas con base real |
| Oráculo exacto de referidos vigente | PASS, 16 valores absolutos, fracciones, rangos y bordes. El ensayo histórico del 07/10 ya no corresponde a la regla publicada el 13/10. Véase evaluación del review |
| Tipos generados desde la rama | Esquemas public y crm coinciden; solo cambia metadata HTTP 14.18 de la rama frente a 14.5 del destino. Se conserva la versión productiva |

Las 25 copias previas «* 2.*» se conservaron con sus huellas en releases/resguardos/atencion-duplicados-20261013; no se cambió el umbral de calidad. Manifest: [duplicados](duplicados-resguardados.json).

## Rama y advisors

Rama autorizada atencion-venta-20261013 (cdntljznxaubchkhusqo). Su replay histórico inicial falló antes de las candidatas. Se reconstruyó exclusivamente esa rama vacía con el esquema productivo sin datos de clientes y se cotejaron 149 tablas, 1.076 funciones, propietarios, ACL, 72 permisos de columna, roles, políticas, triggers de Auth y metadatos Storage. Historial de 471 migraciones conservado. Tres CHECK equivalentes difieren solo por normalización de paréntesis; la discrepancia de un literal CR se corrigió byte por byte. Las 22 Edge Functions son idénticas a producción.

Se aplicaron las dos candidatas. La iteración final de la primera, todavía no versionada ni publicada, actualizó la guarda legacy y su registro en una transacción; los otros 472 registros permanecieron idénticos. Rama con datos exclusivamente sintéticos y cron desactivado.

Advisors remotos: dos avisos nuevos sobre las dos puertas DEFINER de authenticated, deliberadas y revisadas; no son ejecución pública ni acceso al núcleo. El aviso de contraseñas filtradas también existe en producción antes del cambio. Sin avisos nuevos de rendimiento. [Delta clasificado](advisors-rama-delta.json). Avisos existentes no corregidos por esta tarea: [protección de contraseñas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Publicación y recuperación

Orden preparado: merge de las dos migraciones → cuatro archivos del portal (service worker al final, purga) → ZIP CRM construido desde Main verificado con avancecorp/main. Mantener el paquete anterior. Las pantallas antiguas pueden recibir rechazo al cambiar asesor hasta recargar; no pueden realizar una escritura parcial. Antes del merge se comprueba resolver_en_puertas activo y ausencia de las candidatas en producción.

Portal: repositorio confirmado por Miguel avanza-digital/avancecorp-portal; se conserva la importación antigua y se crea main con el historial real del portal. El repositorio estaba archivado: reactivado para el guardado autorizado, manteniendo su privacidad.

La reversa restaura código y ACL; no borra decisiones ni auditorías ya confirmadas. La publicación efectiva, hashes y smoke se registrarán en PUBLICACION.md. No se atribuye un PASS posterior a Claude: su dictamen final fue CHANGES_REQUESTED, evaluado por el PRIMARY en [EVALUACION-CIERRE.md](EVALUACION-CIERRE.md).
