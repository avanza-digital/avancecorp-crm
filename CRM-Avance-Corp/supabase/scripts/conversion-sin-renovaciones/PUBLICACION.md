# Renovaciones sin aporte: activado en producción · 12/10/2026

**ACTIVO EN EL SISTEMA desde octubre de 2026.** La renovación aporta cero en
Conversión, Coordinación y Metas. Agosto y septiembre conservan sus fotos.

[PR #256](https://github.com/avanza-digital/avancecorp-crm/pull/256) fusionada
en Main: `16f493006dce0ee4a82d0b065d9660f251953469`. La copia aislada de
publicación y `origin/main` apuntaban a ese commit antes del merge Supabase.
No se incluyeron cambios locales de otros trabajos.

Migración local `20261012184345_crm_conversion_sin_renovaciones.sql`, SHA-256
`2eaeedc130cf7c629126328f33865d180400fb7956231d2b176e6a4f1327c56c`.
Versión productiva **`20261012213521`**, aplicada mediante `merge_branch`.
Supabase separó el archivo en 14 sentencias: se compararon todas contra el
archivo aprobado y son idénticas, salvo delimitadores y espacio entre sentencias.
Por eso el hash del array concatenado del historial productivo es distinto.

## Verificación

- Nueva rama propia `conversion-activar-20261012`, ref `wkqygywfqpgsfjkionok`.
  Reconstrucción sin clientes desde el mismo esquema productivo; 1.067 funciones,
  1.489 columnas, 382 triggers, 111 policies y 463 migraciones previas coincidentes.
  Tres CHECK difieren solo en agrupación asociativa de AND.
- **22 comprobaciones SQL PASS** con rollback y **319 aserciones RLS PASS**
  con sesiones Auth reales (`test-rls.mjs --contratos`). No quedan triggers
  desactivados ni el permiso temporal utilizado por el seed.
- CI de la PR: `preflight`, `app-check` y `verify` PASS. Batería local general:
  6.625 pruebas / 410 archivos PASS con dos workers; el intento inicial terminó
  por un worker y se conserva como FAIL de infraestructura. Focalizadas: 108 PASS.
- Producción: renovación **0**, default **0** y CHECK vigente; referido **1**,
  tope **15 %**. Numerador oficial/Coordinación **39,30 → 39,00**; Metas
  **38,30 → 38,00**. Divisor **779**. Son capturas del momento, no totales fijos.
- Las dos renovaciones siguen registradas y su aporte es cero. Se conservan
  los USD 6.000 renovados y los USD 7.000 adicionales de cartera.
- Huellas idénticas de fotos cerradas, periodos, 148 operaciones, 1.067 funciones
  y las 463 migraciones anteriores. Las 23 Edge conservan contenido y configuración.
- Advisors productivos: seguridad **366 → 366**, rendimiento **235 → 235**,
  sin altas ni bajas. En la rama, tras activar Auth con el seed apareció el aviso
  heredado `auth_leaked_password_protection`, también presente en producción;
  no hubo cambios de Auth ni nuevos avisos de base de datos. Bajaron 42 avisos
  `unused_index` por la actividad del ensayo. No se corrigieron avisos ajenos.
- Matriz RLS global y E2E: **NOT RUN**; no cambia pantalla ni se publica frontend.

Evidencia agregada y saneada: [activacion.json](activacion.json).
Ensayo anterior y reversa: [LEEME.md](LEEME.md), [verificacion.json](verificacion.json).

## Cierre

Verificación productiva: **21:39 UTC / 16:39 Lima**, 12/10/2026.
Main de Supabase finalizó `FUNCTIONS_DEPLOYED` y `ACTIVE_HEALTHY`.
Se eliminó la rama propia a las **21:40 UTC** y se confirmó su ausencia.
Ventana 21:29:45–21:40:00 UTC a US$0,01344/h: **US$0,0023 estimados**, no factura.
La rama anterior fue eliminada a las 20:58 UTC (US$0,0248 estimados).
Las ramas de otros trabajos permanecen intactas.

[FigJam para Gerencia](https://www.figma.com/board/tO6Lpx3ieJ6QuwUxfZcSvM?node-id=50-19)
actualizado con el aviso «ACTIVO EN EL SISTEMA · RENOVACIONES NO SUMAN CONVERSIÓN».
Captura revisada: texto legible y sin recortes.
