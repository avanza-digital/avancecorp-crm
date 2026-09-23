---
tags: [crm, gestion-diaria, f4, publicacion]
estado: histórico; supersedido por etapa 3 publicada con cortes OFF
fecha: 2026-09-22
---

# Gestión Diaria F4 etapa 3 — SQL OFF en producción, frontend pendiente

> El frontend pendiente se publicó y verificó después, el 22/09 a las 12:28
> Lima. Esta nota conserva el checkpoint anterior. Estado vigente:
> [[Gestion Diaria F4 - etapa 3 publicada con cortes OFF (2026-09-22)]].

Miguel ya aprobó el SQL y la publicación; no volver a pedir esa autorización.
El PR #68 está fusionado y el `main` remoto verificado al cierre fue
`e22c0cab2db30c5f570adf28f998d4d773fb3ed9` (también incorpora el PR #69).
El `main` local del taller sigue divergente y con trabajo ajeno sin confirmar;
se preservó intacto. Se construyó en una copia limpia separada, sin worktree.

El SQL versionado `20260921214018_crm_gestion_diaria_cortes.sql`, SHA-256
`8563bf8bf66e97a4e328d54582bbcf74e17f63d3d6056c6f9ae2dc4b9f940ea5`,
se probó en una rama Supabase con copia de datos productivos autorizada por Miguel.
Antes del merge, producción tenía 323 migraciones y la rama 324: la única extra
era F4.3. Las 21 Edge Functions tenían las mismas versiones. Pasaron los
asserts F4/Gestión Diaria/SLA, lectura como supervisor autenticado con estado
`desactivados`, controles de RLS y advisors. Se fusionó por la operación de
ramas de Supabase, no por `db push` ni por `apply_migration` directo a producción.
Supabase registró esta ejecución remota como versión `20260922164159`.
El archivo del repositorio conserva la versión `20260921214018`: antes de usar
de nuevo la CLI para publicar migraciones hay que reconciliar el historial sin
reinstalar esta política.

Postflight de producción: 324 migraciones; política histórica v1 única con
`cortes_activos=false`; `private.assert_gestion_diaria_cortes()`,
`private.assert_gestion_diaria()` y cuatro gates SLA PASS; RLS encendida,
columnas sensibles ocultas y ninguna escritura API. Sin avisos de seguridad
nuevos. Quedaron dos avisos INFO por claves foráneas sin índice en la tabla
nueva, actualmente de una fila: [linter de Supabase](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).
La rama temporal `gd-f4-con-datos-20260922` se eliminó y se verificó su ausencia.
La instantánea privada previa de las seis funciones alteradas está en
`CRM-Avance-Corp/releases/private/gd-f4-20260922T164624Z-pre.json`, SHA-256
`ed8f4f960ce2669b122e9d57912caf7be7f3c9cb75bb3764032138fbaf9bae4d`.
No es una reversa ejecutable ni autoriza restaurar datos productivos desde el
backup diario; cualquier reversión requiere procedimiento específico.

**Frontend NO publicado.** En la copia limpia del commit remoto pasó `npm run
check`; después `release:crm` y `release:crm:verify` generaron y verificaron
`CRM-Avance-Corp/releases/crm-20260922T165248Z-e22c0cab2db3.zip` y su
manifiesto. SHA-256 del ZIP:
`58f81cbf903ffdcef6d892dabd38d7f75cf99d4f81d6baae7eb87e3192989098`.
Se conservaron en el taller. `crm.miavance.com` seguía HTTP 200 con
`build-20260921T223103201Z` al cierre. Hostinger está configurado y autenticado
como MCP de Codex, pero **esta sesión no expone** `hosting_deployStaticWebsite`.
Tampoco existe aquí un ZIP comprobado que corresponda exactamente al sitio
actual, así que no se intentó una subida sin recuperación fiable.

Gates adicionales sobre el commit limpio: `npm run check:scripts` PASS tras
instalar las dependencias del paquete raíz; `npm run
test:gestion-diaria-cortes:preflight` PASS (7 pruebas SQL estáticas y 25 HTTP
estáticas). `npm run test:rls:preflight` no se pudo completar en esa copia tras
eliminar la rama, porque exige las variables de un banco/branch no productivo;
no se apuntó a producción ni se presentaron credenciales ficticias como una
matriz real. La matriz SQL/RLS/HTTP local completa ya estaba acreditada en el
acta de F4, y el postflight productivo descrito arriba sí pasó.

Para continuar: reconectar/reiniciar Codex para cargar Hostinger; obtener
respaldo exacto del sitio actual; confirmar que `avancecorp/main` aún apunta
al commit del manifiesto (si avanzó, reconstruir); desplegar el ZIP verificado
y comprobar portada, JS/CSS y acceso básico. Los cortes permanecen OFF. Las
etapas 4–6 (pop-up, reconocimiento/posponer, configuración y activación) no se
han implementado/publicado. El piloto TypeSafe sigue independiente.

Relacionado: [[Gestion Diaria F4 - release detenido por historial de ramas (2026-09-22)]],
[[Gestion Diaria F4 - cortes de jornada (2026-09-21)]], [[Inicio]].
Plan principal: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
