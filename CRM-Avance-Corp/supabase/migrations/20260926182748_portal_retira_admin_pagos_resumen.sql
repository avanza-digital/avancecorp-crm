-- Portal admin · Pagos: se retira la RPC `public.admin_pagos_resumen()` («todo de golpe»).
--
-- Por qué: desde el 26/09/2026 (portal commit 232b2ea, F2) la pantalla de Pagos pide la
-- tabla por contrato por páginas a `public.pagos_admin_resumen_contratos(...)`. La función
-- vieja devolvía los 656 contratos en un jsonb (~2,8 s) y ya nadie la llama. Miguel ordenó
-- retirarla el mismo día («retira eso ahora mismo»), sin esperar la semana de observación.
--
-- Evidencia (producción, 26/09/2026 18:2x UTC):
--   · 0 funciones, 0 vistas, 0 triggers y 0 jobs de pg_cron la citan; 0 filas en pg_depend.
--   · En el código solo aparece en un comentario de `js/admin/pagos-tabla-core.js` y en los
--     tipos generados del CRM (`database.types.ts`), que no la invocan.
--   · pagos.js v43 vivo no la llama (verificado con la URL versionada exacta).
--   · Una pestaña de Pagos abierta con un pagos.js anterior a v41 (antes de F2) la llamaría
--     y mostraría «No se pudieron cargar los pagos»: basta recargar la página.
--
-- Reversión: `../scripts/reversa-portal-admin-pagos-resumen.sql` recrea la función con el
-- cuerpo exacto que tenía (md5 del prosrc en la cabecera de ese archivo) y sus grants.
-- Sin datos afectados: es solo una función de lectura.

drop function if exists public.admin_pagos_resumen();
