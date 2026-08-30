-- Tras los dos filos (ambos deshechos): el mundo real sigue limpio.
select case
  when (select count(*) from private.vigia_alertas va where va.fase = 'f7_mutante') = 0
   and exists (select 1 from cron.job where jobname = 'crm-f7-piezas-vigia' and active)
    then 'LIMPIO: alerta deshecha y vigia en pie'
  else 'SUCIO: el mutante dejo rastro'
end as veredicto_limpieza;
