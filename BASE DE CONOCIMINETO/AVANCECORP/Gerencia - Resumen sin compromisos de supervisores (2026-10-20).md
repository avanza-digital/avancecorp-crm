# Gerencia - Resumen sin compromisos de supervisores (2026-10-20)

Relacionado con [[Gerencia - Resumen sin Por empresa (2026-10-20)]], [[Gerencia - Aviso de cierre compacto y limpieza del resumen (2026-10-20)]] y [[Inventario de indicadores de Gerencia - Citas y operacion]].

## Decisión y resultado

Miguel pidió retirar «Compromisos de supervisores» del Resumen por considerarlo irrelevante. Después preguntó si también había que eliminar algo del backend y autorizó publicar con `$release-crm`.

**Publicado y verificado el 20/10/2026, 20:15 Lima.** Se retiraron el montaje de `CompromisosSupervisoresPanel`, su import y el mapa de nombres que solo utilizaba esa tarjeta en `app/src/screens/hoy/gerencia.tsx`. El Resumen deja de consultar los reconocimientos. Las pruebas existentes de `gerencia.test.tsx` comprueban que no se muestra ni consulta la tarjeta aun habiendo registros.

## Backend compartido

No requiere migración ni borrar registros. `crm.alertas_reconocimientos` y su vista `crm.alertas_reconocimientos_vigentes` siguen utilizadas para reconocer y posponer alertas de la campana del supervisor.

Evidencia: `app/src/lib/alertas-provider.tsx` invoca `useReconocimientosAlertas(sesionSupervisorReal && usaLibro)`; el hook de `app/src/data/crm-queries.ts` utiliza `listarReconocimientosAlertas`; `app/src/data/crm-api.ts` lee la vista y `reconocerAlertaSupervisor` inserta en la tabla. La vista se define sobre esa tabla en `supabase/migrations/20260824170349_crm_reconocimientos_ultimo_manda_vencido.sql`.

La publicación preserva el backend y la actualización de Gestión Diaria de la PR #349. Se comprobó en solo lectura del catálogo productivo que `20261020214445` está registrada y `gestion_diaria_pendientes_v3_fn` instalada; el acta de instalación de #350 se integró después y confirma el resultado. No se aplicó SQL ni se modificaron datos reales.

## Fuente y publicación

- URL: https://crm.miavance.com/#/hoy
- PR: https://github.com/avanza-digital/avancecorp-crm/pull/351, fusionada por el conector normal de GitHub; no se solicitó ni ejecutó fusión administrativa.
- Fuente publicada: `8406775fdda838bea02e57cd5719b63885384d49`.
- Clon limpio de publicación: `/private/tmp/crm-compromisos-publicar-20261020`, Main local y `avancecorp/main` coincidentes antes de subir.
- Main del taller en su worktree existente `/private/tmp/crm-citas-fecha-comercial-20261017` quedó también en el mismo commit mediante fast-forward. El checkout original conserva los trabajos previos.
- Build: `build-20261021T011416019Z`.
- ZIP: `CRM-Avance-Corp/releases/crm-20261021T011417Z-8406775fdda8.zip`.
- Manifiesto: `crm-20261021T011417Z-8406775fdda8.manifest.json`.
- SHA-256: `f3085c31087dd2473fd571461b0e309d11e3dfffb3e1d82c13a4bf796ea9e57c`.
- Tamaño: 2.595.214 bytes.
- Subida y despliegue aceptados mediante `hosting_deployStaticWebsite` del cliente oficial Hostinger ya instalado y su sesión existente, sin cambiar MCP ni credenciales.
- Recuperación: ZIP publicado anterior `crm-20261021T005328Z-67aa76c05f9f.zip` y manifiesto conservados (SHA-256 `4b1ac5a50745259170d7e3d676bf973177eac4d66564880cf3a75418797feed7`).

## Validación

- PASS: `npm run check`, 464 archivos / 7.503 pruebas; lint, tipos, cobertura, release config, service worker, build, bundle y duplicación.
- PASS: Playwright local Docker, 4 passed / 0 failed, specs `resumen-gerencia-compacto` y `resumen-gerencia-movil`.
- El código de aplicación probado en `d156b1a2987a2f6bbf193dfe751649111913cad4` es idéntico al del commit fusionado (`git diff --exit-code ... -- CRM-Avance-Corp/app`). La actualización intermedia solo añade el acta #350; se reutilizó la evidencia del mismo código y se construyó el ZIP desde Main.
- PASS: `release:crm`, `release:crm:verify` y preflight; vivo anterior `67aa76c05f9f` / `build-20261021T005327919Z`, candidato `8406775fdda8`.
- PASS: preflight obligatorio de GitHub sobre la cabecera actualizada antes de fusionar.
- PASS HTTP: 131/131 archivos (portada, versión y JS/CSS), todos con HTTP 200, bytes y SHA-256 coincidentes, a las 20:15:52 Lima.
- PASS UI autenticada: antes de publicar la tarjeta estaba presente; después de recargar, cero encabezados «Compromisos de supervisores», con el Resumen y las demás secciones cargadas. Captura `resumen-publicado.jpg` muestra Avance de metas seguido de Solicitudes de tasa.
- PASS: `git diff --check` y ausencia del texto de la tarjeta en el JavaScript compilado.
- NOT RUN: gate de realidad completo; falta su entorno administrativo. El prerrequisito productivo del release anterior sí se comprobó por catálogo con Supabase.
- Nivel 1, sin revisión secundaria. Los E2E avisaron de fuentes fuera de la raíz de Vite al reutilizar dependencias por enlace; el smoke de la versión publicada se realizó con sus fuentes servidas.

ZIP, manifiesto, logs, diff, recibo saneado, verificación HTTP, captura y `publicacion.json` se conservaron en el workspace original (`CRM-Avance-Corp/output/resumen-sin-compromisos/`) y en el clon de publicación. La fuente del despliegue es la del manifiesto; no se vuelve a publicar por esta acta.
