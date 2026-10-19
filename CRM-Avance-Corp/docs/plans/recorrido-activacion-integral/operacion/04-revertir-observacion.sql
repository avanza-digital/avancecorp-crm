-- Reversa operativa del bloqueo, solo tras autorización de contingencia.
-- Conserva fecha, evidencia, inversiones y datos. No ejecuta down-migrations.
begin;
set local statement_timeout='30s';
set local lock_timeout='3s';
do $$
declare c crm.recorrido_control%rowtype;r jsonb;
begin
  select * into strict c from crm.recorrido_control where id for update;
  if c.modo<>'exigir' then raise exception 'No hay exigencia activa que revertir';end if;
  perform set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
  r:=crm.recorrido_configurar_fn('observacion',
    'Reversion tecnica autorizada por Miguel por incidencia de activacion; conservar evidencia y revisar antes de reactivar.',c.revision);
  if r->>'modo'<>'observacion' or (r->>'cohorte_desde')::timestamptz is distinct from c.cohorte_desde
    or (r->>'revision')::integer<>c.revision+1 then
    raise exception 'La reversa no conserva el contrato del control';
  end if;
end $$;
commit;
