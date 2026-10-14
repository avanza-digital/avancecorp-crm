# Facturación: venta de Fiorella y dos acciones separadas

13/10/2026. Relacionado: [[Inicio]], [[Conversion - sincronizacion al reasignar (2026-09-29)]], [[Contrato PDF - analista asignado y creador separados (2026-09-30)]].

El traslado de atención a Jorge no había corregido la venta 2026-01-001595: el contrato conservaba analista_cierre_id de Fiorella. No era caché. El 13/10 a las 18:12 Lima se corrigió desde la sesión real de Gerencia en el CRM publicado usando la RPC auditada existente. Día 11: Fiorella S/0; Jorge S/150.000. Las otras 74 operaciones de octubre, capital global por moneda, registrador y atención quedaron iguales. Auditoría 04d3aee0-7fc5-42f8-baef-e474bbc5044a.

Miguel aprobó dos acciones: «Cambiar quién atiende al cliente» y «Corregir el dueño de una venta». La primera corresponde a Gerencia y administradores del portal, con revocación CRM prevaleciente. Ambas muestran efecto calculado por servidor y confirman su versión. Núcleo private, puertas mínimas, autorización, locks, historial y postcondiciones. Se bloquea cambiar asesor por UPDATE directo. La atención antigua exige revisión si movería ventas heredadas de una baja.

Pruebas: CRM 6.676; RLS completa 3.933; integración Auth/API 83 local y 83 remota; SQL 29; concurrencia real; F4 cinco cortes; portal 209 Node y recorrido HTML Docker. E2E CRM completo 409 passed, 2 fallos por etiquetas antiguas corregidos y 4 focales PASS, 1 flaky y 26 skipped. Claude revisó; sus hallazgos se resolvieron con evidencia por el PRIMARY, sin convertir su CHANGES_REQUESTED en PASS.

Rama Supabase autorizada atencion-venta-20261013, ref cdntljznxaubchkhusqo. Esquema sin datos productivos, 471 migraciones base y 22 Edge cotejadas. Dos nuevas migraciones, advisors clasificados (dos puertas deliberadas, aviso Auth también preexistente en producción).

Portal confirmado por Miguel: avanza-digital/avancecorp-portal. Se reactivó el repo privado archivado para guardar main, conservando las ramas antiguas. Commit de producto cb2b388.

Estado: protecciones verificadas y listas para publicación autorizada. La venta real YA corregida. Publicación, hashes, smoke y limpieza de rama: acta CRM-Avance-Corp/docs/encargos/facturacion-atribucion-20261013/PUBLICACION.md al ejecutarse.
