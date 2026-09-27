-- Variante A1 (la solicitud de respaldo SE QUEDA). Termina SIEMPRE en rollback.
begin;
set local ensayo.modo = 'conservar';
\ir ../backfill-A-banco.sql
select set_config('ensayo.lead', id::text, true) from crm.leads where nota like 'Backfill 2026-09 · contrato BANCO-A1 %';
create temp table pantalla(actor text, rpc text, ok boolean, res jsonb) on commit drop;
grant all on pantalla to authenticated;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b0000000-0000-4000-8000-000000000002","role":"authenticated"}', true) \gset x_
do $v$ declare v jsonb; s jsonb; begin
  select to_jsonb(t) into v from crm.contexto_conversion_inversion_fn(current_setting('ensayo.lead')::uuid) t;
  insert into pantalla values ('vendedor', 'contexto_conversion_inversion_fn', true, v);
  begin
    select to_jsonb(t) into s from crm.solicitud_inversion_fn((v->'contexto_conversion_inversion_fn'->>'solicitud_id')::uuid) t;
    insert into pantalla values ('vendedor', 'solicitud_inversion_fn', true, s);
  exception when others then insert into pantalla values ('vendedor', 'solicitud_inversion_fn', false, jsonb_build_object('e', sqlerrm)); end;
end $v$;
reset role;
select actor, rpc, ok, left(res::text, 900) from pantalla;
rollback;
