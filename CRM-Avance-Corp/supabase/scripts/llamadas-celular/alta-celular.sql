-- ALTA DE UN CELULAR actuando como GERENCIA, mientras no exista la pantalla de F4 (Configuración › Celulares).
-- El mismo archivo para el ensayo (paso 2.4b de PUBLICAR-F2-F3.md) y para producción (paso 4), por la misma vía:
--   npx supabase db query --linked --file supabase/scripts/llamadas-celular/alta-celular.sql
-- Punto 19 de REVISION-2026-10-02.md: el SQL de la guía no estaba probado por esa vía.
--
-- ⚠️ LA SALIDA TRAE LA CLAVE EN CLARO (punto 17). Correrlo en la terminal de Miguel, NUNCA en una sesión de Claude
-- ni pegando la salida en un chat: lo que pasa por Claude queda en la conversación. La clave se muestra UNA vez
-- (en la base solo queda su sha256); se copia directo al celular o se pasa por un canal privado, y después se
-- limpia la terminal. Este archivo no se commitea con valores reales.
--
-- Antes de correrlo, cambiar los TRES valores marcados con «← cambiar». Los de ejemplo fallan sin crear nada:
--   · uuid de gerencia en ceros → 42501 «Sin acceso a las llamadas del celular»;
--   · etiqueta 'CX' → 22023 «Etiqueta inválida (C1, C2…)»;
--   · uuid del analista en ceros → 22023 «El celular se asigna a un analista o supervisor activo».
-- El dueño tiene que ser analista (vendedor) o supervisor activo. Si la etiqueta ya está vigente → 23505: hay que
-- cerrarla o rotar su clave (crm.cerrar_asignacion_celular / crm.rotar_credencial_celular).
begin;
set local lock_timeout = '5s';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);  -- ← cambiar: uuid de un usuario de gerencia
set local role authenticated;
select crm.asignar_celular(
  'CX',                                          -- ← cambiar: etiqueta del celular (C1, C2…)
  '00000000-0000-0000-0000-000000000000'::uuid   -- ← cambiar: uuid del analista dueño del celular
);
commit;
