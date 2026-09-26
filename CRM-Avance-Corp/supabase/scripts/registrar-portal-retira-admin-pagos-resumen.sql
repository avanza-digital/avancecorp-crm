-- REGISTRO en supabase_migrations.schema_migrations de 20260926182748_portal_retira_admin_pagos_resumen.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega
-- si la función todavía existe (la migración no se aplicó) o si la versión ya está registrada con otro nombre.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('portal_retira_admin_pagos_resumen'));
do $chk$
begin
  if to_regprocedure('public.admin_pagos_resumen()') is not null then
    raise exception 'REGISTRO: public.admin_pagos_resumen() todavía existe; aplica primero la migración 20260926182748';
  end if;
  if exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260926182748' and coalesce(name, '') <> 'portal_retira_admin_pagos_resumen'
  ) then
    raise exception 'REGISTRO: la versión 20260926182748 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260926182748', 'portal_retira_admin_pagos_resumen',
        array['drop function if exists public.admin_pagos_resumen();'])
on conflict (version) do nothing;
select version, name from supabase_migrations.schema_migrations where version = '20260926182748';
commit;
