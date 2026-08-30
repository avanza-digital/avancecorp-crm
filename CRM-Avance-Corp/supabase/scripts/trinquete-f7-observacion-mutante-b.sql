-- Mutante F7, filo B (vigia desprogramado) — un solo SELECT final.
begin;
select cron.unschedule('crm-f7-piezas-vigia');
select case
  when private.veredicto_f7() like 'VIGIA APAGADO%'
    then 'MUTANTE-B-CAZADO: el veredicto ve el vigia apagado'
  else 'MUTANTE-B-SOBREVIVIO: ' || private.veredicto_f7()
end as veredicto_mutante_b;
rollback;
