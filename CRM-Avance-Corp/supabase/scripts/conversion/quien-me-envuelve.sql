-- =========================================================================
-- ¿QUIEN ENVUELVE A ESTA FUNCION? · correr ANTES de anadir una clave al payload
-- =========================================================================
-- Existe porque el 23/09/2026 costo 13 minutos de Metas y Ranking caidos.
--
-- Se declaro `crm.cumplimiento_metas_sin_cartera_fn` tras comprobar que no
-- tiene consumidor en el front. Era CIERTO. Lo que no se vio: que
-- `crm.cumplimiento_metas_fn` construye su payload SOBRE el de esa, y esa SI
-- tiene consumidor — con `v.strictObject`. Cuatro claves desconocidas y
-- valibot rechazo el payload entero.
--
-- 🔑 Un `grep` en `app/src` ve quien LLAMA a la RPC. No ve quien HEREDA su
--    forma dentro de la base. Esto si.
--
-- COMO SE CORRE:
--   psql/supabase db query --linked --file supabase/scripts/conversion/quien-me-envuelve.sql
-- cambiando el nombre de abajo. No escribe nada.
--
-- Y PARA CADA ENVOLTORIO QUE SALGA, el paso que no se puede saltar: mirar su
-- esquema del front EN EL COMMIT PUBLICADO, no en el arbol:
--   git show <commit vivo>:CRM-Avance-Corp/app/src/lib/<modulo>.ts
-- `v.object` ignora lo que no conoce. `v.strictObject` tumba el payload entero.
-- El commit vivo sale de: version.json -> buildId -> manifiesto en releases/.
-- =========================================================================

\set funcion 'cumplimiento_metas_sin_cartera_fn'

select p.oid::regprocedure::text as la_envuelve,
       p.prosecdef as es_definer,
       p.proowner::regrole::text as dueno,
       case when p.provolatile = 'v' then 'ESCRIBE' else 'lee' end as que_hace
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('crm', 'private', 'public')
   and p.prosrc like '%' || :'funcion' || '%'
   and p.proname <> :'funcion'
 order by 1;
