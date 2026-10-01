# Documentos del lead — publicación verificada, 2026-09-30

Estado: **SQL y frontend PUBLICADOS y verificados** en https://crm.miavance.com.
Miguel autorizó la publicación y delimitó «Solo documentos; mantener F1 pendiente».
El PR [#151](https://github.com/avanza-digital/avancecorp-crm/pull/151) quedó
fusionado el 30/09/2026 a las 22:57:54 UTC. El banco temporal propio se eliminó.

## Fuente y artefacto efectivamente publicados

- Main aprobado: `be280b6c51e5dd58139ae8c91eb1b4598696852c`, idéntico al árbol probado
  `d79beb9c9bbc162c1519bab662ec6e443ddc44cf`. Main local y `avancecorp/main`
  coincidían antes de construir.
- El preflight oficial rechazó el artefacto de Main porque el squash no conservaba
  la ascendencia del commit vivo `6bb984edc63c6d5f853a0f4a565fc6c7ce024700`.
  Se siguió la excepción de rescate de `CLAUDE.md`, sin saltar el preflight.
- Fuente publicada: `6a9ad5e685a2c595924cc0bccf2df31678e36948`, rama
  `rescue/documentos-lead-20260930`, creada desde ese vivo. Su árbol completo y
  el de Main aprobado son idénticos: `a9552fca82712df2cee501dde7312846e3f9fe7d`.
- Build: `build-20260930T225943345Z`.
- ZIP: `crm-20260930T225944Z-6a9ad5e685a2.zip`.
- SHA-256: `caf2408ef5689a6068e436b4eeefd5163015819601b067cb22634e7ac0627b80`.
- `release:crm`, `release:crm:verify` y preflight del rescate: **PASS**.
- Publicación mediante MCP oficial Hostinger `hosting_deployStaticWebsite`:
  upload/deploy success. Se esperó la nueva versión servida antes de comprobarla.
- HTTP posterior: **PASS**, portada 200 y 94 archivos con SHA-256 idéntico al
  manifiesto, incluidos todos los JS/CSS y los metadatos de versión/PWA.
- Smoke visual Chrome: **PASS**. Cargó el CRM con la sesión existente; Nuevo lead
  muestra DNI, Carné de Extranjería y Pasaporte. Al elegir CE, el campo muestra
  «Entre 9 y 12 dígitos». Se canceló el formulario sin guardar ni crear registros.

El ZIP anterior publicado se conserva para recuperación:
`crm-20260930T213752Z-6bb984edc63c.zip`, build `build-20260930T213751470Z`.
Una recuperación requiere el procedimiento autorizado; no se ha ejecutado.
Los artefactos y recibos saneados están en `CRM-Avance-Corp/releases/` de la copia
habitual y de la copia limpia `/private/tmp/crm-documentos-release-20260930`.
El acta posterior no cambia el commit fuente del artefacto ni exige republicar.

## Base de datos

Migración `20260930193325_crm_documentos_lead.sql` publicada por `merge_branch`
en `dctqcbznekcyxhjujuci`, tras validación remota. SHA-256 del SQL:
`89a760e86f4daa9ad41bd20a18b1ce6ba2c931b48a08886559a628cc7ab56e72`;
MD5 de la sentencia registrada: `f0a23459407e1a314da28eb41eaf5994`.
El catálogo posterior coincide con el banco probado: 863 funciones, incluidas
las cinco nuevas; objetos anteriores, 1320 columnas, 7668 grants de columna,
478 índices, 125 policies, 134 tablas/vistas y 333 triggers conservados.
Las 22 Edge Functions mantienen paquetes y verify_jwt; los cinco buckets,
sus permisos y límites. Advisors de producción: **cero avisos nuevos** de
seguridad o rendimiento respecto a su propio baseline.

El banco `lead-documentos-publicacion-20260930` (`saiwhmjrgqdggscfimbu`) se creó
en la organización autorizada, con límite aprobado de US$1, y se eliminó tras
verificar el merge. Se comprobó su ausencia. No se tocaron otros bancos.
Su reconstrucción de esquema, controles técnicos y fixtures sintéticos está
documentada en `supabase/scripts/lead-documentos/README.md`; no se copiaron
clientes ni contratos reales. Los estados «pendiente» en actas anteriores son
fotografías históricas; esta acta registra el resultado final.

## Verificación

| Gate | Resultado |
| --- | --- |
| Check integral del código final | PASS: 5100 tests / 328 archivos; lint, tipos, cobertura, build, bundle y duplicación |
| E2E Docker local completo | PASS: 298 passed / 26 skipped / 0 failed |
| SQL remoto específico | PASS: 52 aserciones |
| Auth + HTTP/PostgREST remoto | PASS: 12 casos |
| RLS contractual remoto | PASS: 287 comprobaciones |
| Identidad D5 remota | PASS: 30 comprobaciones |
| Concurrencia de dos sesiones, reversa y reaplicación locales | PASS |
| GitHub PR151 | PASS: app-check, preflight y verify |
| Catálogo, Edge, Storage y advisors después del merge | PASS |
| Artefacto, preflight y hashes HTTP publicados | PASS |
| Smoke visual de acceso y selector de documento | PASS, sin guardar datos |

Se reutiliza la evidencia del mismo código: el árbol probado, el Main aprobado
por PR151 y el rescate publicado son idénticos. El cierre solo añade prosa;
no necesita repetir suites de producto ni desplegar otra vez.
Las revisiones de Claude y la evaluación con pruebas del PRIMARY están en
`supabase/scripts/lead-documentos/revision-publicacion.txt`; no se presenta
un dictamen independiente PASS que no se obtuvo.

## Alcance y caso comunicado

Alta/edición conservan tipo y número; conversión consulta la misma identidad.
DNI sigue usando ocho dígitos; CE/pasaporte conservan ceros y letras admitidas.
F1 Llamadas sigue sin activar. Sus módulos y pruebas permanecen versionados;
la integración de producción se mantiene previa a F1, según
`docs/plans/llamadas-celular/PUBLICACION-PENDIENTE-2026-09-30.md`.

El contrato del caso comunicado se conserva. Un documento histórico recortado
necesita el CE real completo y corrección administrativa auditada; no se adivinó
ni cambió identidad real. No hace falta eliminar ni volver a crear el contrato.
