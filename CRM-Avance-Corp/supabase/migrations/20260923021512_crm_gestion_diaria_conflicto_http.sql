-- F4: un conflicto de versión es definitivo para esta petición, no una
-- serialización transitoria. PostgREST 14 reintenta 40001 indefinidamente.
-- Devuelve HTTP 409 / PT409 y conserva mensaje, candados, reglas y permisos.
-- No publica políticas ni activa cortes. Los cuatro SQL previos no se editan.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $correccion$
declare
  f record;
  fuente text;
  verificador text;
  antes jsonb;
  despues jsonb;
begin
  perform private.assert_gestion_diaria();
  if (select md5(prosrc) from pg_proc
      where oid='private.assert_gestion_diaria_configuracion()'::regprocedure)
      is distinct from '67652733ccdcb1450ba660122379fffe' then
    raise exception 'El verificador de configuración difiere del revisado';
  end if;
  verificador := pg_get_functiondef('private.assert_gestion_diaria_configuracion()'::regprocedure);

  for f in select * from (values
    ('crm.publicar_politica_gestion_diaria(integer,timestamptz,jsonb,text)',
      '7b56e17b707e86ec577092ba372bf854','56d173e818167e73fa7e432a2c81ac2f'),
    ('crm.controlar_avisos_gestion_diaria(integer,boolean,text)',
      'e499268b4f3985887ff98d2f261e67ef','8b75761ae5d0ac1a17f7905589c29f74')
  ) cambios(firma,anterior,nueva) loop
    select jsonb_build_object('owner',p.proowner,'acl',p.proacl,'definer',p.prosecdef,
      'volatilidad',p.provolatile,'config',p.proconfig,'argumentos',p.proargtypes,
      'retorno',p.prorettype) into strict antes
      from pg_proc p where p.oid=to_regprocedure(f.firma);
    if (select md5(prosrc) from pg_proc where oid=to_regprocedure(f.firma))
        is distinct from f.anterior then
      raise exception 'Cuerpo diferente del revisado: %',f.firma;
    end if;
    fuente := pg_get_functiondef(to_regprocedure(f.firma));
    if array_length(string_to_array(fuente,'''40001'''),1) <> 2
      or array_length(string_to_array(verificador,quote_literal(f.anterior)),1) <> 2 then
      raise exception 'Ancla de conflicto o huella no única: %',f.firma;
    end if;
    execute replace(fuente,'''40001''','''PT409''');
    if (select md5(prosrc) from pg_proc where oid=to_regprocedure(f.firma))
        is distinct from f.nueva then
      raise exception 'Resultado distinto del cambio exacto: %',f.firma;
    end if;
    select jsonb_build_object('owner',p.proowner,'acl',p.proacl,'definer',p.prosecdef,
      'volatilidad',p.provolatile,'config',p.proconfig,'argumentos',p.proargtypes,
      'retorno',p.prorettype) into strict despues
      from pg_proc p where p.oid=to_regprocedure(f.firma);
    if antes is distinct from despues then
      raise exception 'Cambió un permiso o contrato de %',f.firma;
    end if;
    verificador := replace(verificador,quote_literal(f.anterior),quote_literal(f.nueva));
  end loop;
  -- El gate conserva todas sus reglas: solo fija las dos nuevas huellas.
  execute verificador;
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end $correccion$;

notify pgrst, 'reload schema';
commit;
