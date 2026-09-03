-- Reversa de F3: apaga la puerta unica y suelta el trigger. NO deshace las
-- identidades ya enlazadas por conversiones reales mientras estuvo encendida
-- (esas son conversiones legitimas; deshacerlas seria revertir F2/conversiones).
-- Tras esto, las conversiones vuelven a comportarse como antes de F3.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f3_puertas'));

drop trigger if exists trg_leads_reconocer_identidad on crm.leads;
drop function if exists private.leads_reconocer_identidad_al_convertir();

update crm.multiempresa_flags set activo = false, actualizado_en = now()
  where nombre = 'resolver_en_puertas' and activo = true;

do $post$
begin
  if to_regprocedure('private.leads_reconocer_identidad_al_convertir()') is not null
     or exists (select 1 from pg_trigger where tgname='trg_leads_reconocer_identidad' and not tgisinternal)
     or (select activo from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'REVERSA F3: quedo residuo (trigger/funcion/bandera)';
  end if;
  raise notice 'REVERSA F3 OK: puerta unica apagada y trigger retirado; identidades ya enlazadas se conservan.';
end
$post$;
commit;
