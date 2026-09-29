-- REVERSA de 20260929151350_crm_contrato_pdf_anexo_snapshot.
-- Borra SOLO la lectura del anexo (crm.contrato_pdf_anexo_snapshot). No toca
-- datos ni ninguna otra función, vista o política: nada del catálogo la usa.
-- CONSERVA la bitácora private.contrato_pdf_anexo_impresiones y su candado de
-- solo añadir (evidencia de lo ya impreso; es aditiva y sin lectores de la API).
-- Orden: si la Edge ya expone la acción «anexo», revertir PRIMERO front y Edge.
-- La reversa no toca supabase_migrations.schema_migrations: anotar en el ledger
-- el mismo día.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is null then
    raise exception 'REVERSA anexo: la lectura ya no existe; nada que revertir';
  end if;
  if exists (
    select 1 from pg_catalog.pg_depend d
    where d.refobjid = 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)'::regprocedure::oid
      and d.deptype = 'n'
  ) then
    raise exception 'REVERSA anexo: hay objetos que dependen de la lectura; revisar antes de borrar';
  end if;
end $chk$;
drop function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text);
do $post$
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is not null then
    raise exception 'REVERSA anexo: la lectura sigue existiendo';
  end if;
  if to_regclass('private.contrato_pdf_anexo_impresiones') is null then
    raise exception 'REVERSA anexo: la bitácora debía conservarse';
  end if;
end $post$;
notify pgrst, 'reload schema';
commit;
