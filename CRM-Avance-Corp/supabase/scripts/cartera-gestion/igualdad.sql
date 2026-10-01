-- FRAGMENTO (sin transacción propia): oráculo de IGUALDAD. Sobre los mismos datos de
-- `volumen.sql`, la función NUEVA sin `p_gestion` (omitido y con null explícito) devuelve lo
-- mismo que la VIEJA, salvo `generado_en`. Lo compone `ensayar.mjs`, que antes instala la
-- definición vieja —tal cual la tenía el banco, md5 7169d942…— como
-- `pg_temp.cartera_filtrada_anterior`. No aborta en la primera diferencia: cuenta y enseña.
set local session_replication_role = origin;
-- Cuando va detrás del cuerpo de la migración hereda su `statement_timeout` de 30 s; el bucle
-- de abajo es UNA sentencia con casi 400 llamadas.
set local statement_timeout = 0;
do $guarda$
begin
  -- Llamar sin EXECUTE tumba este Postgres: se comprueba en el catálogo antes de cambiar de rol.
  if (
    has_function_privilege('authenticated', 'pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.vactor(integer)', 'EXECUTE')
  ) is not true then
    raise exception 'IGUALDAD: falta EXECUTE para authenticated; no se llama a ciegas';
  end if;
  -- La «vieja» es de verdad la vieja: mismo cuerpo que la función viva antes de la migración.
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)'::regprocedure)
     is distinct from 'e48f00b152c965d3bae303a9660dad09' then
    raise exception 'IGUALDAD: la funcion de comparacion no es el cuerpo vivo de antes';
  end if;
end;
$guarda$;

set local role authenticated;
do $igualdad$
declare
  -- gerencia, directorio, coordinador, dos supervisores y tres analistas.
  actores constant integer[] := array[1, 2, 3, 11, 12, 101, 102, 107];
  llamadas constant text[] := array[
    $c$p_limite => 50$c$,
    $c$p_limite => 200, p_etapa => 'nuevo'$c$,
    $c$p_limite => 200, p_etapa => 'contactado'$c$,
    $c$p_limite => 20, p_etapa => 'descartado'$c$,
    $c$p_limite => 10, p_texto => 'lead 0001'$c$,
    $c$p_limite => 10, p_texto => '5190000'$c$,
    $c$p_limite => 50, p_origen => 'landing'$c$,
    $c$p_limite => 50, p_procedencia => 'manual'$c$,
    $c$p_limite => 50, p_procedencia => 'sistema', p_etapa => 'nuevo'$c$,
    $c$p_limite => 50, p_reasignados => true$c$,
    $c$p_limite => 50, p_sin_asignar => true$c$,
    $c$p_limite => 50, p_vendedor_id => 'f3bb1000-0000-4000-8000-000000000101'$c$,
    $c$p_limite => 50, p_desde => (now() at time zone 'America/Lima')::date - 30, p_hasta => (now() at time zone 'America/Lima')::date$c$,
    $c$p_limite => 25, p_antes_de => now() - interval '10 hours', p_antes_id => '00000000-0000-4000-8000-000000000000'$c$,
    $c$p_limite => 200, p_etapa => 'nuevo', p_reasignados => true, p_procedencia => 'sistema', p_origen => 'formulario'$c$,
    $c$200, null, null, 'nuevo', null, false, null, null, null, null, null, false$c$
  ];
  a integer; c text; vieja jsonb; nueva jsonb; nula jsonb;
  iguales integer := 0; total integer := 0; filas bigint := 0; con_datos integer := 0; distintas text := '';
begin
  foreach a in array actores loop
    perform set_config('request.jwt.claim.sub', pg_temp.vactor(a)::text, true),
            set_config('request.jwt.claims', json_build_object('sub', pg_temp.vactor(a), 'role', 'authenticated')::text, true);
    foreach c in array llamadas loop
      execute 'select pg_temp.cartera_filtrada_anterior(' || c || ')' into vieja;
      execute 'select crm.cartera_filtrada_fn(' || c || ')' into nueva;
      execute 'select crm.cartera_filtrada_fn(' || c || ', p_gestion => null)' into nula;
      total := total + 2;
      filas := filas + jsonb_array_length(vieja -> 'items');
      if (vieja #>> '{resumen,totales,vivos}')::integer > 0 then con_datos := con_datos + 1; end if;
      if vieja is not null and (vieja - 'generado_en') = (nueva - 'generado_en') then iguales := iguales + 1;
      else distintas := left(distintas || ' · actor ' || a || ' [' || c || '] omitido', 1500); end if;
      if vieja is not null and (vieja - 'generado_en') = (nula - 'generado_en') then iguales := iguales + 1;
      else distintas := left(distintas || ' · actor ' || a || ' [' || c || '] null explicito', 1500); end if;
    end loop;
  end loop;
  perform set_config('ensayo.igualdad', jsonb_build_object('iguales', iguales, 'total', total,
    'actores', cardinality(actores), 'llamadas', cardinality(llamadas), 'filas_comparadas', filas,
    'respuestas_con_datos', con_datos, 'distintas', distintas)::text, true);
end;
$igualdad$;
reset role;
select 'IGUALDAD ' || current_setting('ensayo.igualdad');
