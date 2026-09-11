# F7 — SQL aprobado y preparación de instalación

11/09/2026. Codex PRIMARY. **Acta histórica de preparación, anterior a instalar.**
El estado vigente es **F7 publicada e instalada OFF**, con banco cerrado y G6
pendiente: [publicación verificada](PUBLICACION-2026-09-11.md).

Miguel respondió «sii» a la solicitud concreta de ensayar e instalar F7
inicialmente apagada. El archivo aprobado es
[20260911163243_crm_multiempresa_f7_metricas_sombra.sql](../../migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql),
SHA-256 `7b9cb56992dea24ead99d2d14c8ac79f9dabc7e9b40765f666117a5986e3c8e7`.
En este punto de preparación aún no se había ejecutado en producción. El
archivo aprobado se conserva sin modificar. No volver a solicitar
aprobación del mismo SQL.

## Preparación completada

- Se integró `avancecorp/main@4bfae4937373116bfa5fe93cb8de069a7b23ada0`
  en la rama `codex/f7-metricas`, commit de integración `8dd0a14`.
  Se conservaron los cambios recientes de Facturación y del aviso push.
- El gate `VITEST_MAX_WORKERS=2 npm run check` terminó con salida cero:
  lint, tipos, **3.341 pruebas en 233 archivos**, cobertura, configuración,
  service worker, build, bundle y duplicación. No se cambiaron aserciones,
  límites ni reintentos. `npm run test:e2e -- --workers=2` pasó los 168 casos
  de navegación y mantuvo los 26 SKIP existentes.
  [Evidencia de esta integración](evidencias/preparacion-instalacion-2026-09-11.json).
- Se capturaron en transacciones de solo lectura el historial de migraciones,
  funciones, restricciones, permisos, empresas y banderas del padre. La
  [captura resumida](evidencias/base-productiva-preparacion-2026-09-11.json)
  confirma **274 migraciones**, las cuatro huellas exigidas por F7,
  F7 ausente, F3 ON y F4/F5/F6 OFF a las 20:26 UTC.
- Se exportó solo el esquema `public,crm,private` para preparar el banco,
  usando `supabase db dump --linked --project-ref dctqcbznekcyxhjujuci`.
  El dump no contiene registros de negocio ni usuarios Auth. El historial
  completo y la estructura se conservan únicamente en la carpeta privada.
- La versión viva `build-20260911T185614310Z` corresponde a Main `4bfae49`.
  Se localizó y verificó el ZIP anterior
  `crm-20260911T185614Z-4bfae4937373.zip`, SHA-256
  `5cc3160d2ff5a1f8aac2a484a7b6d0dd5d8705951591f7d3ee949d8eba951394`.
  No se sustituyó la publicación ni se adelantó Main a la candidata F7.

## Incidencia del hook de envío

La primera repetición completa del hook pre-push falló en un caso de
`app/src/prototypes/citas-crm/tablero.test.tsx`: el selector Analista esperaba
tener foco, pero lo tenía el botón Mónica Silva. Resultado conservado:
3.340 PASS y 1 FAIL. El mismo archivo aislado pasó 4/4.

La prueba esperaba la desaparición del diálogo y cambiaba de filtro antes
del retorno de foco. `Sheet.onCloseAutoFocus` lo devuelve en
`requestAnimationFrame`, después del desmontaje. Se añadió la espera por
el foco en el botón de origen antes de seleccionar el nuevo analista,
conservando la comprobación final del foco del selector. No se modificó
código de producto, límites ni reintentos. Los nueve tests de Citas y
diálogos pasaron; `VITEST_MAX_WORKERS=2 npm run check` volvió a pasar completo
con las 3.341 pruebas. Los 168 E2E anteriores corresponden al mismo código de
producto. Los logs fallidos y corregidos se conservan en la evidencia.

## Coste autorizado y banco creado

Miguel respondió **«si»** al coste de **US$0.01344/h**. Se confirmó ese precio
con Supabase y se creó `multiempresa-f7-20260911` a las 20:42:52 UTC,
proyecto `awshxyerdsvgjnteetfa`, rama `429fa19f-d018-428c-94a5-731541fde6ed`.
La autorización del SQL y del coste está completa; no volver a pedirla.
El avance remoto y sus límites están en [ENSAYO-REMOTO-2026-09-11.md](ENSAYO-REMOTO-2026-09-11.md).

El antiguo **`banco-f7`** pertenece al trabajo de altas, no a esta fase
multiempresa. Conservarlo. La rama nueva es exclusiva de esta tarea; el banco ajeno se conserva.

## Retoma

1. SQL y coste autorizados; banco propio creado. Continuar con los gates y
   el cierre de instalación registrados en el ensayo remoto.
2. Volver a capturar el padre: estas capturas son preparación, no sustituyen
   las guardas frescas previas al ensayo o al merge. Conservar cambios nuevos
   de la base y de `avancecorp/main`.
3. Si falla el replay histórico, reconstruir únicamente el esquema vivo en el
   banco propio vacío, con su historial y permisos. Sembrar datos ficticios
   antes de ensayar F7. No copiar usuarios ni datos reales, ni activar cron.
4. Completar ensayo, matriz pertinente de permisos/RLS, comparación con los
   fallos generales preexistentes, advisors, tipos, reversa y verificación
   del JSON real con el contrato del frontend. Las pruebas locales existentes
   conservan su alcance; no equivalen a este ensayo remoto.
5. Publicar el consumidor compatible desde el commit común verificado de
   Main/remoto, con las variables públicas productivas comprobadas. Después,
   instalar únicamente el SQL aprobado por el ciclo de rama Supabase y
   verificar banderas OFF, permisos, núcleos e historial. No aplicar DDL
   directamente al padre. Conservar las Edge Functions vigentes.
6. Eliminar solo el banco nuevo tras el cierre verificado. G6 sigue requiriendo
   revisión y firma humana de cifras reales; F8/F9 continúan pendientes.

Evidencia privada: `/private/tmp/avancecorp-f7-publicacion-20260911`.
Respaldo duradero: `/Users/usuario/.codex/backups/avancecorp-f7-20260911`.
No incluir credenciales ni volcados privados en Git.
