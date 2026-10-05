-- Reversa de 20261002054402_crm_base_gestion_esquema.sql (Base para gestión · B1).
-- Quita el sello, el CHECK, la función de constantes y las dos columnas. Solo se pierden los valores
-- de `reactivado_en` y `enfriado_hasta`; ningún otro dato cambia. Aplicar únicamente si ninguna puerta
-- o núcleo de B3/B4 sigue instalado (dependen de estas piezas).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
do $pre$
begin
  -- Orden de reversas: B1b (reversa-proxima-llamada.sql) ANTES que B1; si no, quedaría proxima_llamada_en sin sello.
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'proxima_llamada_en') then
    raise exception 'REVERSA B1: B1b sigue aplicada (proxima_llamada_en); aplicar antes reversa-proxima-llamada.sql';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('crm', 'private')
                and p.proname <> 'trg_leads_zz_sello_base_gestion'
                and p.prosrc ~ 'op_base_gestion|enfriado_hasta|reactivado_en|base_gestion_constantes') then
    raise exception 'REVERSA B1: quedan puertas/nucleos de B3/B4 que dependen del esquema; revertirlos antes';
  end if;
end;
$pre$;
drop trigger if exists trg_leads_zz_sello_base_gestion on crm.leads;
drop function if exists private.trg_leads_zz_sello_base_gestion();
alter table crm.actividades drop constraint if exists actividades_intento_base_forma;
drop function if exists private.base_gestion_constantes();
alter table crm.leads drop column if exists reactivado_en, drop column if exists enfriado_hasta;
do $post$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads'
              and column_name in ('reactivado_en', 'enfriado_hasta'))
     or to_regprocedure('private.base_gestion_constantes()') is not null
     or exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass
                 and conname = 'actividades_intento_base_forma') then
    raise exception 'REVERSA B1: quedo alguna pieza';
  end if;
  raise notice 'reversa base_gestion_esquema OK';
end;
$post$;
notify pgrst, 'reload schema';
commit;
