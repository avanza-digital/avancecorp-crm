-- Mutante del gate F7 — DOS filos, ambos contra LA FUNCION real, ambos
-- deshechos:
--   A) alerta sintetica abierta -> el veredicto debe delatarla;
--   B) cron desprogramado -> el veredicto debe delatarlo.
begin;
insert into private.vigia_alertas (fase, motivo)
values ('f7_mutante', 'alerta sintetica del mutante del gate - debe cazarse y deshacerse');
select case
  when private.veredicto_f7() like 'ALERTAS ABIERTAS:%'
    then 'MUTANTE-A-CAZADO: el veredicto ve la alerta abierta'
  else 'MUTANTE-A-SOBREVIVIO: ' || private.veredicto_f7()
end as veredicto_mutante_a;
rollback;

begin;
select cron.unschedule('crm-f7-piezas-vigia');
select case
  when private.veredicto_f7() like 'VIGIA APAGADO%'
    then 'MUTANTE-B-CAZADO: el veredicto ve el vigia apagado'
  else 'MUTANTE-B-SOBREVIVIO: ' || private.veredicto_f7()
end as veredicto_mutante_b;
rollback;

-- Tras deshacer, el mundo real sigue limpio y el vigia sigue en pie:
select case
  when (select count(*) from private.vigia_alertas va where va.fase = 'f7_mutante') = 0
   and exists (select 1 from cron.job where jobname = 'crm-f7-piezas-vigia' and active)
    then 'LIMPIO: alerta deshecha y vigia en pie'
  else 'SUCIO: el mutante dejo rastro'
end as veredicto_limpieza;
