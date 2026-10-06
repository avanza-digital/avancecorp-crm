-- ALTA DE UN CELULAR actuando como GERENCIA, mientras no exista la pantalla de F4 (Configuración › Celulares).
-- El mismo archivo para el ensayo y para producción, por la misma vía (PUBLICAR-F2-F3.md):
--   npx supabase db query --linked --file supabase/scripts/llamadas-celular/alta-celular.sql
-- Punto 19 de REVISION-2026-10-02.md: el SQL de la guía no estaba probado por esa vía.
--
-- UNA SOLA SENTENCIA, sin begin ni commit (05/10/2026): `db query` solo devuelve el ÚLTIMO resultado del archivo
-- (trampa medida, `supabase/scripts/evidencia-f7-piezas.sql`). La versión anterior terminaba en `commit` y la clave
-- no se habría visto nunca: en la base solo queda su sha256. La sentencia sola es su propia transacción; la identidad
-- de gerencia se fija con set_config(…, true) en el WHERE, que se evalúa antes de llamar a la puerta, y vuelve sola
-- al terminar la sentencia (sin SET de sesión: un conjunto de conexiones podría reutilizarla).
--
-- ⚠️ LA SALIDA TRAE LA CLAVE EN CLARO (punto 17). Correrlo en la terminal de Miguel, NUNCA en una sesión de Claude
-- ni pegando la salida en un chat: lo que pasa por Claude queda en la conversación. La clave se muestra UNA vez;
-- se copia directo al celular o se pasa por un canal privado, y después se limpia la terminal. Este archivo no se
-- commitea con valores reales.
--
-- Antes de correrlo, cambiar los TRES valores marcados con «← cambiar». Los de ejemplo fallan sin crear nada:
--   · uuid de gerencia en ceros → 42501 «Sin acceso a las llamadas del celular»;
--   · etiqueta 'CX' → 22023 «Etiqueta inválida (C1, C2…)»;
--   · uuid del analista en ceros → 22023 «El celular se asigna a un analista o supervisor activo».
-- El dueño tiene que ser analista (vendedor) o supervisor activo. Si la etiqueta ya está vigente → 23505: hay que
-- cerrarla (cerrar-celular.sql) o rotar su clave (rotar-celular.sql).
-- BARRERA: solo después de aplicar y verificar la quinta y F4-a. Un alta antes de la quinta la deja sin poder
-- aplicarse (exige las tablas vacías y una asignación no se borra nunca).
select crm.asignar_celular(
         'CX',                                          -- ← cambiar: etiqueta del celular (C1, C2…)
         '00000000-0000-0000-0000-000000000000'::uuid   -- ← cambiar: uuid del analista dueño del celular
       ) as alta
where pg_catalog.set_config('lock_timeout', '5s', true) is not null
  and pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true) is not null;  -- ← cambiar: uuid de gerencia
