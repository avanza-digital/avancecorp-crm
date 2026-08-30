-- Mutante F7, filo A (alerta sintetica) — un solo SELECT final: db query solo
-- devuelve el ULTIMO resultado de un archivo (trampa medida).
begin;
insert into private.vigia_alertas (fase, motivo)
values ('f7_mutante', 'alerta sintetica del mutante del gate - debe cazarse y deshacerse');
select case
  when private.veredicto_f7() like 'ALERTAS ABIERTAS:%'
    then 'MUTANTE-A-CAZADO: el veredicto ve la alerta abierta'
  else 'MUTANTE-A-SOBREVIVIO: ' || private.veredicto_f7()
end as veredicto_mutante_a;
rollback;
