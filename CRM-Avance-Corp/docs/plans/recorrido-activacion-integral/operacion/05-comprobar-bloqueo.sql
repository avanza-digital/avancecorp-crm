-- Comprobación del guard del servidor en filas existentes. Solo locks y lecturas;
-- sin modificar clientes, crear inversiones, enviar correos ni inventar hechos.
-- No sustituye una conversión positiva real del usuario ni la matriz HTTP.
begin;
set local statement_timeout='30s';
set local lock_timeout='3s';
do $$
declare c record;r jsonb;n integer:=0;
begin
  if not exists(select 1 from crm.recorrido_control where id and modo='exigir'
    and cohorte_desde<=clock_timestamp()) then raise exception 'La exigencia no esta activa';end if;
  for c in select id from crm.leads where activo and etapa not in ('convertido','descartado') order by creado_en,id limit 100 loop
    select resultado into r from private.recorrido_evaluar(array[c.id]);
    if (r->>'habilita_conversion')::boolean is not true then
      begin
        perform private.recorrido_exigir(c.id,'comprobacion_tecnica_sin_escritura');
      exception when sqlstate 'P0409' then
        if position('Antes de convertir' in sqlerrm)=0 then raise;end if;
        n:=n+1;continue;
      end;
      raise exception 'Un lead sin hechos no fue bloqueado';
    end if;
  end loop;
  if n=0 then raise exception 'No se encontro un caso negativo; completar aceptacion con el usuario';end if;
  raise notice 'PASS: % leads pendientes sin hechos rechazados por el guard; ninguna escritura',n;
end $$;
rollback;
