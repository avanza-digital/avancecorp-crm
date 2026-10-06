-- ROTAR LA CLAVE DE UN CELULAR actuando como GERENCIA (cierra la asignación vigente con motivo «rotacion» y abre otra
-- al mismo analista, con clave nueva). Mismo molde que alta-celular.sql: UNA SOLA SENTENCIA, porque `db query` solo
-- devuelve el último resultado del archivo; la identidad de gerencia vuelve sola al terminar.
--   npx supabase db query --linked --file supabase/scripts/llamadas-celular/rotar-celular.sql
--
-- ⚠️ LA SALIDA TRAE LA CLAVE NUEVA EN CLARO: terminal de Miguel, nunca una sesión de Claude ni un chat. La vieja deja
-- de valer en el acto: cambiar la clave en la «Solicitud HTTP» de la macro (aviso y latido) enseguida.
-- Rotar reinicia el límite de envíos (el estado va por asignación; Codex P3-7, documentado).
--
-- Cambiar los DOS valores marcados con «← cambiar». Los de ejemplo fallan sin cambiar nada (42501 con gerencia en
-- ceros; 22023 «Ese celular no tiene una asignación vigente» con la etiqueta 'CX').
select crm.rotar_credencial_celular(
         'CX'                                           -- ← cambiar: etiqueta del celular (C1, C2…)
       ) as rotacion
where pg_catalog.set_config('lock_timeout', '5s', true) is not null
  and pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true) is not null;  -- ← cambiar: uuid de gerencia
