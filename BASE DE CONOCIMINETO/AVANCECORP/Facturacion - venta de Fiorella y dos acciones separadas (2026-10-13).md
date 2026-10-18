# Facturación: venta de Fiorella y dos acciones separadas

13/10/2026. Relacionado: [[Inicio]], [[Conversion - sincronizacion al reasignar (2026-09-29)]], [[Contrato PDF - analista asignado y creador separados (2026-09-30)]].

El traslado de atención a Jorge no había corregido la venta 2026-01-001595: el contrato conservaba analista_cierre_id de Fiorella. No era caché. El 13/10 a las 18:12 Lima se corrigió desde la sesión real de Gerencia en el CRM publicado usando la RPC auditada existente. Día 11: Fiorella S/0; Jorge S/150.000. Las otras 74 operaciones de octubre, capital global por moneda, registrador y atención quedaron iguales. Auditoría 04d3aee0-7fc5-42f8-baef-e474bbc5044a.

Miguel aprobó dos acciones: «Cambiar quién atiende al cliente» y «Corregir el dueño de una venta». La primera corresponde a Gerencia y administradores del portal, con revocación CRM prevaleciente. Ambas muestran efecto calculado por servidor y confirman su versión. Núcleo private, puertas mínimas, autorización, locks, historial y postcondiciones. Se bloquea cambiar asesor por UPDATE directo. La atención antigua exige revisión si movería ventas heredadas de una baja.

Pruebas: CRM 6.676; RLS completa 3.933; integración Auth/API 83 local y 83 remota; SQL 29; concurrencia real; F4 cinco cortes; portal 209 Node y recorrido HTML Docker. E2E CRM completo 409 passed, 2 fallos por etiquetas antiguas corregidos y 4 focales PASS, 1 flaky y 26 skipped. Claude revisó; sus hallazgos se resolvieron con evidencia por el PRIMARY, sin convertir su CHANGES_REQUESTED en PASS.

Rama Supabase autorizada atencion-venta-20261013, ref cdntljznxaubchkhusqo. Esquema sin datos productivos, 471 migraciones base y 23 Edge cotejadas (corrige el conteo documental anterior de 22). Dos nuevas migraciones, advisors clasificados (dos puertas deliberadas, aviso Auth también preexistente en producción).

Portal confirmado por Miguel: avanza-digital/avancecorp-portal. Se reactivó el repo privado archivado para guardar main, conservando las ramas antiguas. Commit de producto cb2b388.

Estado: **PUBLICADO Y VERIFICADO** el 13/10 a las 20:22–20:24 Lima. Backend: 473 migraciones, las 471 anteriores intactas, 12 funciones/propietarios/ACL idénticos a la rama y guarda activa. CRM publicado desde Main verificado `6dd9fbb6c6ee234acf5993b09c49c97611151b75` (PR 274); portal `cb2b388f4d4995df06836fb19d47140a7b22438f`. Tres checks GitHub PASS, integración por la excepción administrativa de PR ya configurada, sin alterar protecciones. Build `build-20261014T012055587Z`; 126 recursos HTTP coincidentes y pantalla real recargada: Jorge S/150.000, Fiorella S/0 el día 11. E2E final desde commit limpio: 23 PASS.

La rama temporal atencion-venta-20261013 fue eliminada; ausencia confirmada y producción saludable. Se conservaron las ramas ajenas y el paquete anterior. Evidencia, hashes, observaciones y límites: CRM-Avance-Corp/docs/encargos/facturacion-atribucion-20261013/PUBLICACION.md. No queda pendiente la publicación ni la corrección de la venta.
