# F7 — SQL aprobado y preparación de instalación

11/09/2026. Codex PRIMARY. **F7 no instalada ni publicada en producción.**

Miguel respondió «sii» a la solicitud concreta de ensayar e instalar F7
inicialmente apagada. El archivo aprobado es
[20260911163243_crm_multiempresa_f7_metricas_sombra.sql](../../migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql),
SHA-256 `7b9cb56992dea24ead99d2d14c8ac79f9dabc7e9b40765f666117a5986e3c8e7`.
No se modificó ni ejecutó esa migración en producción. No volver a solicitar
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

## Único dato pendiente para crear el banco

El coste consultado para una rama en el mismo proyecto PortalAvanceCorp es
**US$0.01344 por hora**, aproximadamente US$0.03 por dos horas. La herramienta
`supabase_get_cost` exige repetir ese coste y obtener la confirmación antes
de crear la rama. La pregunta enviada a Miguel sigue pendiente de respuesta;
no se ha llamado a `confirm_cost` ni a `create_branch`.

El antiguo **`banco-f7`** pertenece al trabajo de altas, no a esta fase
multiempresa. Conservarlo. Una respuesta favorable al coste permite crear
un banco exclusivo; una respuesta negativa no autoriza reutilizar o alterar
el banco ajeno para evitar el coste.

## Retoma

1. Resolver la respuesta al coste. Si se autoriza, confirmar el precio y crear
   una rama exclusiva, registrando su identificador y destino antes de escribir.
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
