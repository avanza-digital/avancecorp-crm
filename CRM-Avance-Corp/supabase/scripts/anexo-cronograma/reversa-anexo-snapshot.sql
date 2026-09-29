-- REVERSA de 20260929151350_crm_contrato_pdf_anexo_snapshot.
-- Borra SOLO las cuatro funciones del anexo (dos puertas crm.* y dos núcleos
-- private.*). No toca datos ni ninguna otra función, vista o política: nada del
-- catálogo las usa. CONSERVA la bitácora private.contrato_pdf_anexo_emisiones y
-- sus candados (evidencia de lo ya emitido; aditiva, sin lectores de la API); la
-- migración la tolera si se vuelve a aplicar.
-- Orden: si la Edge ya expone la acción «anexo», revertir PRIMERO front y Edge.
-- La reversa no toca supabase_migrations.schema_migrations: anotar en el ledger
-- el mismo día.
begin;
set local lock_timeout = '5s';
do $chk$
declare v_firma text;
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is null
     and to_regprocedure('crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)') is null
     and to_regprocedure('private.contrato_pdf_anexo_snapshot_base(uuid)') is null
     and to_regprocedure('private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)') is null then
    raise exception 'REVERSA anexo: las funciones ya no existen; nada que revertir';
  end if;
  foreach v_firma in array array[
    'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)',
    'crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)',
    'private.contrato_pdf_anexo_snapshot_base(uuid)',
    'private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)'
  ] loop
    if to_regprocedure(v_firma) is not null and exists (
      select 1 from pg_catalog.pg_depend d
      where d.refobjid = to_regprocedure(v_firma)::oid
        and d.deptype = 'n'
        and d.classid <> 'pg_catalog.pg_proc'::regclass
    ) then
      raise exception 'REVERSA anexo: hay objetos que dependen de %; revisar antes de borrar', v_firma;
    end if;
  end loop;
end $chk$;
drop function if exists crm.contrato_pdf_anexo_snapshot(uuid,uuid,text);
drop function if exists crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint);
drop function if exists private.contrato_pdf_anexo_snapshot_base(uuid);
drop function if exists private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint);
do $post$
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is not null
     or to_regprocedure('crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)') is not null
     or to_regprocedure('private.contrato_pdf_anexo_snapshot_base(uuid)') is not null
     or to_regprocedure('private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)') is not null then
    raise exception 'REVERSA anexo: alguna función sigue existiendo';
  end if;
  if to_regclass('private.contrato_pdf_anexo_emisiones') is null then
    raise exception 'REVERSA anexo: la bitácora debía conservarse';
  end if;
end $post$;
notify pgrst, 'reload schema';
commit;
