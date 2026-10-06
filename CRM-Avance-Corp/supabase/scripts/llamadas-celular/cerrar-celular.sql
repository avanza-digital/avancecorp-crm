-- CERRAR LA ASIGNACIÓN DE UN CELULAR actuando como GERENCIA: la clave deja de valer en el acto. Para pasar el celular a
-- otro analista (antes, cola en 0: PUBLICAR-F2-F3.md), por baja, extravío o para apagar todo después del alta.
-- Mismo molde que alta-celular.sql: UNA SOLA SENTENCIA (`db query` solo devuelve el último resultado).
--   npx supabase db query --linked --file supabase/scripts/llamadas-celular/cerrar-celular.sql
--
-- Cambiar los TRES valores marcados con «← cambiar». Motivos: rotacion, baja_analista, extravio, reemplazo, otro.
-- Con la etiqueta de ejemplo no se encuentra nada y no cambia nada (fila vacía); con gerencia en ceros, 42501.
-- Una asignación cerrada no se borra ni se reabre: para volver a usar la etiqueta, alta-celular.sql.
select crm.cerrar_asignacion_celular(a.id, 'reemplazo') as cierre   -- ← cambiar: motivo
from crm.celulares_asignaciones a
where a.etiqueta = 'CX'                                              -- ← cambiar: etiqueta del celular (C1, C2…)
  and a.vigente_hasta is null
  and pg_catalog.set_config('lock_timeout', '5s', true) is not null
  and pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true) is not null;  -- ← cambiar: uuid de gerencia
