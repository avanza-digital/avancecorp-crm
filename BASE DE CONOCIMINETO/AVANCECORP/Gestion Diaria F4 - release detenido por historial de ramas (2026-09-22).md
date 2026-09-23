---
tags: [crm, gestion-diaria, f4, publicacion]
estado: histórico; supersedido por SQL OFF productivo
fecha: 2026-09-22
---

# Gestión Diaria F4 etapa 3 — release detenido por historial de ramas

> Este registro describe el bloqueo anterior. La rama nueva con datos autorizada
> permitió probar y fusionar el SQL OFF. Estado vigente: [[Gestion Diaria F4 - SQL OFF publicado y frontend pendiente (2026-09-22)]].

La invocación humana de `$release-crm` autorizó intentar la publicación. El [PR #68](https://github.com/avanza-digital/avancecorp-crm/pull/68) ya está fusionado en `avancecorp/main` (`9152fca46b79e31ef012cd23eb27efbcc8e6d6c2`), aprobado y con cuatro checks de CI correctos. En una copia limpia de ese mismo commit, `npm run check` pasó: 4.085 pruebas de 272 archivos, lint, tipos, cobertura y build. El artefacto se creó y verificó:

- ZIP local conservado: `CRM-Avance-Corp/releases/crm-20260922T154127Z-9152fca46b79.zip`.
- Manifiesto local: `CRM-Avance-Corp/releases/crm-20260922T154127Z-9152fca46b79.manifest.json`.
- SHA-256 del ZIP: `069021fd5db61fd4f34ea953b0b6e4388b52d3c5de1d8daa27dd6da8df9cf3d8`.
- Configuración pública productiva y verificación del bundle: PASS. El ZIP **no se ha publicado**.

El SQL aprobado `20260921214018_crm_gestion_diaria_cortes.sql` conserva la huella `8563bf8bf66e97a4e328d54582bbcf74e17f63d3d6056c6f9ae2dc4b9f940ea5`. En el proyecto productivo `dctqcbznekcyxhjujuci` no consta esa migración ni existen todavía `crm.gestion_diaria_cortes` o `private.assert_gestion_diaria_cortes()`. **No se ejecutó SQL productivo ni se activaron cortes.**

Miguel autorizó crear una rama de Supabase tras conocer su coste de US$0,01344/h. La rama temporal `gestion-diaria-f4-cortes-20260922` (`jxveelejhsvpjwtlgnzg`) quedó `MIGRATIONS_FAILED` al reproducir el historial previo: registró 86 de las 323 migraciones presentes en producción; la última registrada fue `20260811210049` y la siguiente productiva es `20260812000259`. Esa primera rama se eliminó.

En el reintento de diagnóstico, la rama temporal `gd-f4-diagnostico-20260922` (`nayymlyvamwtsryswuhs`) reprodujo la misma parada. El ensayo con `psql` de `20260812000259_crm_cierres_externos.sql`, dentro de una transacción que terminó en `ROLLBACK`, identificó el error concreto: `Postflight: crm.equipo esta vacia; se necesita un perfil real para la FK de vendedor_id`. La rama nace sin datos y Supabase ejecuta **Migrate antes de Seed**, de modo que un seed posterior no satisface ese postflight histórico. Se crearon solo en esta rama dos identidades ficticias `@fixture.invalid`, sus perfiles y una jerarquía supervisor–vendedor; el mismo ensayo reversible pasó su postflight. La operación oficial `push` conservó esos datos y avanzó el historial de 86 a 128 migraciones.

La siguiente migración, `20260824231133_crm_gestion_clientes_renovaciones_conversion.sql`, volvió a fallar en un ensayo reversible: `Backfill agosto inesperado: 0 operaciones, 0 conversiones (esperado >=48 y 29)`. Es una segunda dependencia explícita de datos productivos preexistentes. **La rama de diagnóstico se eliminó y se verificó su ausencia**, por lo que sus dos identidades ficticias también desaparecieron y dejó de generar coste. No se copiaron clientes reales, no se modificó producción y no se aplicó el SQL F4 a una rama remota. La rama antigua `banco-f7`, también fallida, no se tocó. La reparación durable del replay requiere una decisión separada sobre las migraciones históricas ya versionadas; no se deben insertar datos ficticios en producción ni fingir que el replay vacío pasó.

La conexión OAuth del MCP oficial `https://mcp.hostinger.com` se añadió a Codex como `hostinger` y el login respondió correctamente, sin copiar claves. **Esta sesión todavía no expone** `hosting_deployStaticWebsite`; se requiere reconectar/reiniciar Codex y comprobar el inventario real de herramientas antes de usarlo. El sitio sigue respondiendo HTTP 200 con `build-20260921T223103201Z` y `assets/index-Bg_0yXjj.js`, distintos del ZIP anterior conservado en este taller (`crm-20260921T200509Z-baa63aeac71e`, entrada `assets/index-MbAI3sVV.js`). Ese ZIP anterior **no debe asumirse como respaldo exacto del sitio actual**. No se subió ni retiró ningún archivo de Hostinger.

La rama `main` del taller principal tiene dos commits locales ajenos, ahora está dos commits detrás del remoto y contiene cambios sin confirmar de otras tareas. Se dejó intacta. El ZIP nuevo se construyó desde un worktree limpio y separado, en HEAD desacoplado del commit remoto fusionado. Antes de publicar hay que reconfirmar `avancecorp/main`; si avanzó desde `9152fca`, reconstruir y verificar otro ZIP del commit vigente.

Para retomar: decidir explícitamente cómo superar las dos dependencias históricas de datos (sin editar migraciones versionadas ni copiar datos reales sin autorización); conseguir que esta sesión exponga el conector Hostinger y obtener un respaldo exacto del sitio actual; conciliar `main` local sin sobrescribir trabajo ajeno. Después, repetir los gates del [procedimiento de F4](https://github.com/avanza-digital/avancecorp-crm/blob/9152fca46b79e31ef012cd23eb27efbcc8e6d6c2/CRM-Avance-Corp/docs/gestion-diaria/F4-PUBLICACION-RECUPERACION.md), probar el SQL exacto en una rama sana, conservar los resguardos de las seis funciones, instalarlo con cortes OFF y solo entonces publicar/verificar el frontend. No usar `db push` general ni publicar otras migraciones o TypeSafe.

Relacionado: [[Gestion Diaria F4 - cortes de jornada (2026-09-21)]], [[Inicio]]. Plan principal: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
