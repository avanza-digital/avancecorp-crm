-- REVERSA de 20261022170801_crm_conversion_cliente_antiguo_misma_ficha.sql («Convertir a un cliente antiguo sin ficha de persona usa su
-- misma ficha», bloque 2.10). GENERADA desde la migración (sus anclas, sus frases y sus listas, byte a byte; generador en
-- fase-2/bloque-2.10/salidas/ronda6/trabajo/generadores/generar-reversa.py): no editar a mano sin volver a ensayarla.
--
-- ORDEN: esta migración no toca nada de lo que fijan el 2.11 ni el 2.16 (ni sus piezas, ni sus núcleos, ni sus puertas), así que esta
-- reversa entra con ellos aplicados o no, y la de ellos entra con esta aplicada o no (ensayado: `armar-ensayo.mjs --reversa-ajena`).
-- Para volver al punto de partida del laboratorio, LIFO: esta, después la del 2.16 y después la del 2.11 (`--reversa-lifo`).
--
-- FALLA CERRADA. Antes de revertir exige EXACTAMENTE lo que deja la migración:
--   · las tres piezas con su cuerpo, su definición, su ficha (INVOKER, dueño postgres, EXECUTE solo postgres) y su comentario
--     (e42060a4052c903e899015e5e65b6820/c7c41e6a612dfbbc858e6c7035aa4731 · 5f3ff24473ab6e09ea561a555e75913c/b950e46ffa971abe6c5fc758de4a40d0 · 32c3b18303b0a32c1d92d1d73d73c28f/fbde8ab20dbf41604427a72a3c457328);
--   · la puerta y los dos núcleos con su cuerpo y su definición nuevos (da360b1929752a3e26371bf838813130/f921422dfc1567ffc82980222e299601,
--     514fda0a0ca115c620637e6408bc346c/151b1ae1fa511bf728e3d5d8c11434f6, 8e96ddefae91ca9e1587cccb103129a7/c79c0a93ad9acd23e3ee152c32c32fb7), su ficha y su comentario nuevo
--     (7b00e6ea92634d5e8ceb55687c588a38, ae77826890d3421cab96831002056dd4, 2f1723984e222937ef171266e51e9897);
--   · las 43 funciones que llaman a las tres o deciden su efecto, intactas (la misma lista de la migración); que NADIE MÁS nombre a
--     las tres ni use las piezas (las mismas búsquedas de la migración); las restricciones de las que depende la regla; los índices
--     únicos y la RLS del puente y del libro; las PREMISAS de D-83/D-85 y D-86/D-87 (índices del cierre inicial y del perfil, FK del
--     perfil, NOT NULL y CHECK del documento del cierre, `crm.inversiones.inversionista_id` NOT NULL, los disparadores de inmutables del
--     cierre, de `leads_before_update` y de tenencia enlazados y habilitados, y el conjunto de disparadores de `crm.inversionistas`; desde
--     la ronda 6, los mismos bloques que el preflight de la migración); el inventario de los 29 `assert_*` que la migración fija
--     (29|60a0851245859d8e1f0da6e2276a2594) y la existencia del trinquete que re-sella el 2.16. Lo mismo, después de revertir, en su postflight.
-- Si algo de eso cambió después (un cuerpo, un SET, un permiso, un dueño, un comentario, otro llamador), NO se revierte nada y se
-- revisa a mano (o se corrige hacia delante con otra migración). No se promete tolerancia a derivas (ensayado:
-- `armar-ensayo.mjs --reversa-deriva`).
--
-- QUÉ RESTAURA: la puerta y los dos núcleos, quitando por ancla única lo que la migración puso (cada bloque tiene que aparecer
-- EXACTAMENTE una vez); el comentario de la puerta (vuelve a no tener) y los de los dos núcleos (se quita la frase del 2.10, que tiene
-- que estar exactamente al final); y borra las tres piezas sin CASCADE (ya nadie las nombra). El postflight exige las huellas de antes
-- (puerta 4eebf912d4abc0b101e3c39688dc0c54/df451bd3cc831e2b47a26eb867c9e65e, escritura b67d8181139ab76ff9232523a67dfa11/dcc540a48b7f252c783f814f6a184144,
-- lectura b1106c6c67be483f8fb655a276e3def4/477d0e80266faa6add30929337f00701; comentarios d41d8cd98f00b204e9800998ecf8427e (ninguno), 5e0226384bc1c2db4fa72bb8dad54fff, 84620ea87a16f7610aa05d3a636b3623),
-- la misma ficha y ACL, las piezas ausentes y lo demás intacto.
--
-- LO QUE LA REVERSA NO DESHACE (datos): los puentes históricos, los retiros, las operaciones del libro, los cierres iniciales
-- completados (D-83) y los perfiles del Portal enlazados a la ficha (D-87) que la regla haya escrito se quedan (son el estado que el
-- backfill de identidad y la puerta de enlace de Gerencia ya producen; revertirlos sería una fusión inversa de Gerencia). Tras revertir,
-- la conversión con el DNI de un cliente antiguo sin ficha vuelve a crear una persona nueva (retirado) o a pedir conciliación (activo);
-- y una conversión PREPARADA y no confirmada que ya absorbió historia se detiene al seguir (preparar la solicitud) con «La persona ya
-- tiene una conversión inicial; requiere conciliación» (P0409: el núcleo vuelve a contar el puente histórico como otro lead; medido en
-- la ronda 4). Se aplica por el mismo ciclo que la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $rpf$
declare
  v_puerta regprocedure := to_regprocedure('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)');
  v_escritura regprocedure := to_regprocedure('private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)');
  v_lectura regprocedure := to_regprocedure('private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)');
  v_absorber regprocedure := to_regprocedure('private.conversion_absorber_cliente_antiguo(uuid,uuid,text,uuid,uuid)');
  v_enlazar regprocedure := to_regprocedure('private.conversion_enlazar_cliente_antiguo(uuid,jsonb,uuid)');
  v_historia regprocedure := to_regprocedure('private.lead_historia_de_persona(uuid,uuid)');
  v_mal text;
  r record;
  v text;
  v_foto text := '';
begin
  if v_puerta is null or v_escritura is null or v_lectura is null then
    raise exception 'REVERSA conversion_cliente_antiguo: falta la puerta o uno de los dos núcleos';
  end if;
  if v_absorber is null or v_enlazar is null or v_historia is null then
    raise exception 'REVERSA conversion_cliente_antiguo: falta alguna de las tres piezas: la migración no está aplicada (nada que revertir)';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_absorber) is distinct from 'e42060a4052c903e899015e5e65b6820/c7c41e6a612dfbbc858e6c7035aa4731' then
    raise exception 'REVERSA conversion_cliente_antiguo: private.conversion_absorber_cliente_antiguo no es la que deja la migración (md5 del cuerpo / de la definición %; se esperaba e42060a4052c903e899015e5e65b6820/c7c41e6a612dfbbc858e6c7035aa4731): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_absorber);
  end if;
  if md5(coalesce(obj_description(v_absorber, 'pg_proc'), '')) is distinct from '0fe920d982d5e1cb8b78cdb52e6d4e95' then
    raise exception 'REVERSA conversion_cliente_antiguo: el comentario de private.conversion_absorber_cliente_antiguo no es el que deja la migración: revisar a mano';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_enlazar) is distinct from '5f3ff24473ab6e09ea561a555e75913c/b950e46ffa971abe6c5fc758de4a40d0' then
    raise exception 'REVERSA conversion_cliente_antiguo: private.conversion_enlazar_cliente_antiguo no es la que deja la migración (md5 del cuerpo / de la definición %; se esperaba 5f3ff24473ab6e09ea561a555e75913c/b950e46ffa971abe6c5fc758de4a40d0): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_enlazar);
  end if;
  if md5(coalesce(obj_description(v_enlazar, 'pg_proc'), '')) is distinct from 'c3ce07337d5c62279d5b3dab4bcad2e6' then
    raise exception 'REVERSA conversion_cliente_antiguo: el comentario de private.conversion_enlazar_cliente_antiguo no es el que deja la migración: revisar a mano';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_historia) is distinct from '32c3b18303b0a32c1d92d1d73d73c28f/fbde8ab20dbf41604427a72a3c457328' then
    raise exception 'REVERSA conversion_cliente_antiguo: private.lead_historia_de_persona no es la que deja la migración (md5 del cuerpo / de la definición %; se esperaba 32c3b18303b0a32c1d92d1d73d73c28f/fbde8ab20dbf41604427a72a3c457328): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_historia);
  end if;
  if md5(coalesce(obj_description(v_historia, 'pg_proc'), '')) is distinct from '80f36c9d023d2d804162bbb0068f4e29' then
    raise exception 'REVERSA conversion_cliente_antiguo: el comentario de private.lead_historia_de_persona no es el que deja la migración: revisar a mano';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_puerta) is distinct from 'da360b1929752a3e26371bf838813130/f921422dfc1567ffc82980222e299601' then
    raise exception 'REVERSA conversion_cliente_antiguo: crm.preparar_persona_lead_inversion_fn no es la que deja la migración (md5 del cuerpo / de la definición %; se esperaba da360b1929752a3e26371bf838813130/f921422dfc1567ffc82980222e299601): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_puerta);
  end if;
  if md5(coalesce(obj_description(v_puerta, 'pg_proc'), '')) is distinct from '7b00e6ea92634d5e8ceb55687c588a38' then
    raise exception 'REVERSA conversion_cliente_antiguo: el comentario de crm.preparar_persona_lead_inversion_fn no es el que deja la migración: revisar a mano';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_escritura) is distinct from '514fda0a0ca115c620637e6408bc346c/151b1ae1fa511bf728e3d5d8c11434f6' then
    raise exception 'REVERSA conversion_cliente_antiguo: private.inversion_persona_contexto_para no es la que deja la migración (md5 del cuerpo / de la definición %; se esperaba 514fda0a0ca115c620637e6408bc346c/151b1ae1fa511bf728e3d5d8c11434f6): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_escritura);
  end if;
  if md5(coalesce(obj_description(v_escritura, 'pg_proc'), '')) is distinct from 'ae77826890d3421cab96831002056dd4' then
    raise exception 'REVERSA conversion_cliente_antiguo: el comentario de private.inversion_persona_contexto_para no es el que deja la migración: revisar a mano';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_lectura) is distinct from '8e96ddefae91ca9e1587cccb103129a7/c79c0a93ad9acd23e3ee152c32c32fb7' then
    raise exception 'REVERSA conversion_cliente_antiguo: private.inversion_contexto_lectura_para no es la que deja la migración (md5 del cuerpo / de la definición %; se esperaba 8e96ddefae91ca9e1587cccb103129a7/c79c0a93ad9acd23e3ee152c32c32fb7): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_lectura);
  end if;
  if md5(coalesce(obj_description(v_lectura, 'pg_proc'), '')) is distinct from '2f1723984e222937ef171266e51e9897' then
    raise exception 'REVERSA conversion_cliente_antiguo: el comentario de private.inversion_contexto_lectura_para no es el que deja la migración: revisar a mano';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_puerta and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 'v'
                   and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_puerta) is distinct from 'authenticated:EXECUTE:false,postgres:EXECUTE:false'
     or not exists (select 1 from pg_proc p where p.oid in (v_escritura, v_lectura) and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 'v'
                      and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2
                    having count(*) = 2)
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_escritura) is distinct from 'postgres:EXECUTE:false'
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_lectura) is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_puerta, 'EXECUTE') or has_function_privilege('service_role', v_puerta, 'EXECUTE')
     or has_function_privilege('anon', v_escritura, 'EXECUTE') or has_function_privilege('authenticated', v_escritura, 'EXECUTE')
     or has_function_privilege('anon', v_lectura, 'EXECUTE') or has_function_privilege('authenticated', v_lectura, 'EXECUTE') then
    raise exception 'REVERSA conversion_cliente_antiguo: la ficha de la puerta o de un núcleo no es la esperada (dueño postgres, security definer, volátil, su SET, su ACL): revisar a mano';
  end if;
  if not exists (select 1 from pg_proc p where p.oid in (v_absorber, v_enlazar, v_historia) and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.proconfig = array['search_path=""'] having count(*) = 3)
     or exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 where p.oid in (v_absorber, v_enlazar, v_historia) and a.grantee <> 'postgres'::regrole::oid) then
    raise exception 'REVERSA conversion_cliente_antiguo: la ficha de una pieza no es la esperada (INVOKER, dueño postgres, EXECUTE solo postgres): revisar a mano';
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.acceso_inversion_fn(uuid,text,jsonb)', 'b45c309fce1003058ee42de5804d95a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.buscar_cliente_existente_fn(text,text,text,uuid)', '43b317c13c40471a3e3eec2fbbe0fb8a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.confirmar_inversion_fn(uuid)', 'e69358303d4b6220354460965179c28d', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)', '33af606a814c74de5de8a080430bb299', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.contexto_cliente_existente_fn(uuid,uuid)', '8cd36f9311dd59327fa749f4568861cb', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.contexto_conversion_inversion_fn(uuid,uuid)', 'a616232e3ada628404fc6a1a8356eb13', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)', 'c41aa8ee34da4b3f828289058c41e4f4', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', '1159aa8443c117c8c9384a2bcf17ae2b', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.inversionista_ficha_fn(uuid,integer,integer)', 'be113f3c638e3fdf6e0ca9a45eb86a6d', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.preparar_inversion_fn(uuid,jsonb)', '5fefbc143578a735a8648f686f71bf9a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)', 'dc622b938e8d8e9777a033cfa625b11a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.documento_es_de_identidad(uuid,text,text)', '724c4c781b1ed289a5320ab6c9d2eea8', 'postgres:EXECUTE:false'),
    ('private.f4_comprobante_autorizado(text)', 'cdecad21e77c38d023ba156efd8faa74', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.f4_fuente_inmutable()', 'f4608368a957e5ce1fe191562d5b5bea', 'postgres:EXECUTE:false'),
    ('private.identidad_bloquear_documento(text,text)', '9c08b500af7bc11aeba5e0e7d3a63330', 'postgres:EXECUTE:false'),
    ('private.identidad_bloquear_documentos_de(uuid[])', '81dffba49b46f2defc723e53a9a96d67', 'postgres:EXECUTE:false'),
    ('private.inversion_contexto_lectura(uuid,uuid)', '7ae71408f49ecd1eb2a05ed746746dde', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_autorizada_para(uuid,uuid,uuid)', 'c91e82b30558d121782f94aefab39d6e', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_contexto(uuid)', '335fa43d5eed5d0d8010d9d0716483ce', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_contexto(uuid,uuid)', 'a7ce8164838edc6b64cdc3f933c5a276', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_lectura_para(uuid,uuid,uuid)', '6539960f2d9b7896e2c4083f80361f57', 'postgres:EXECUTE:false'),
    ('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)', 'c34bc06eafdb62f128476a8bffbfa642', 'postgres:EXECUTE:false'),
    ('private.inversiones_escritura_bajo_candado()', '2122bbf3b22996f2e8373081a259db9b', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.inversionista_fusion_destino_activo()', '861f359c23ab031945f4bad75f8dc3a7', 'postgres:EXECUTE:false'),
    ('private.inversionista_operaciones_append_only()', '909d41d42674ccb6775597fd4235ebca', 'postgres:EXECUTE:false'),
    ('private.inversionista_resolver(text,text,boolean,text)', '95d502fcae257bf2a439ec3e4aa6a2dc', 'postgres:EXECUTE:false'),
    ('private.juicio_cliente_convertido(text,text,text,uuid)', 'a2b38faf42a875c7dffb7968b106e36f', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.leads_before_update()', '4ae909f2d56ca650b5595b505e6aa51d', 'postgres:EXECUTE:false'),
    ('private.leads_de_identidades(uuid[])', '2421b2b78b02b8e93fd01598e2f54128', 'postgres:EXECUTE:false'),
    ('private.leads_de_personas(uuid[])', '6eded477639796c1053f0190f6decc18', 'postgres:EXECUTE:false'),
    ('private.leads_protege_inversionista_id()', '6151f6d4da6c80fc62ad7f131ea398a4', 'postgres:EXECUTE:false'),
    ('private.log_audit_crm()', 'c25c2af183b650f4d4c85abedd5bcc97', 'postgres:EXECUTE:false'),
    ('private.puede_gestionar_contratos_crm()', '94b5fb2af92bf4187802b1f3d26659c5', 'postgres:EXECUTE:false'),
    ('private.resolver_en_puertas_bajo_candado()', '5f74d26262fcc83e5975672da141be63', 'postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.trg_cierres_externos_inmutables()', 'c9f55c70e526975476b1f6aead562cd4', '-:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.trg_gestion_lead_serializada()', '7af0e66b8a4849566e43b514245e1b86', 'postgres:EXECUTE:false'),
    ('private.trg_leads_tenencia_desde()', '900508fa3ccf3eec2e738ccdeebad7be', 'postgres:EXECUTE:false'),
    ('private.trg_leads_zz_enlaza_identidad()', '6ea5abfcc7bc7113f62f175df4e65879', 'postgres:EXECUTE:false'),
    ('private.trg_leads_zz_puente_identidad()', 'e96f21d1c58623f6c2a84e7c04683a5c', 'postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'REVERSA conversion_cliente_antiguo: cambió algo que llama a las tres funciones o decide su efecto: revisar a mano (%)', v_mal;
  end if;
  select string_agg(x.f, ', ' order by x.f) into v_mal
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where (strpos(lower(p.prosrc), 'preparar_persona_lead_inversion_fn') > 0 and p.oid <> v_puerta)
            or (strpos(lower(p.prosrc), 'inversion_persona_contexto_para') > 0
                and p.oid not in (v_escritura, v_lectura,
                                  coalesce(to_regprocedure('private.inversion_persona_contexto(uuid,uuid)'), 0),
                                  coalesce(to_regprocedure('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)'), 0),
                                  coalesce(to_regprocedure('crm.confirmar_inversion_revisada_fn(uuid,integer)'), 0),
                                  coalesce(to_regprocedure('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)'), 0),
                                  coalesce(to_regprocedure('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)'), 0),
                                  coalesce(to_regprocedure('crm.acceso_inversion_fn(uuid,text,jsonb)'), 0),
                                  coalesce(to_regprocedure('private.f4_comprobante_autorizado(text)'), 0)))
            or (strpos(lower(p.prosrc), 'inversion_contexto_lectura_para') > 0
                and p.oid not in (v_escritura, v_lectura,
                                  coalesce(to_regprocedure('private.inversion_contexto_lectura(uuid,uuid)'), 0),
                                  coalesce(to_regprocedure('crm.buscar_cliente_existente_fn(text,text,text,uuid)'), 0),
                                  coalesce(to_regprocedure('crm.contexto_cliente_existente_fn(uuid,uuid)'), 0)))
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_puerta, v_escritura, v_lectura)) x;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'preparar_persona_lead_inversion_fn') > 0 or strpos(lower(j.command), 'inversion_persona_contexto_para') > 0
                   or strpos(lower(j.command), 'inversion_contexto_lectura_para') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'REVERSA conversion_cliente_antiguo: otro posible llamador de la puerta o de los núcleos (%): revisar a mano', v_mal;
  end if;
  select string_agg(x.f, ', ' order by x.f) into v_mal
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where (strpos(lower(p.prosrc), 'conversion_absorber_cliente_antiguo') > 0 and p.oid not in (v_absorber, v_enlazar, v_puerta))
            or (strpos(lower(p.prosrc), 'conversion_enlazar_cliente_antiguo') > 0 and p.oid not in (v_enlazar, v_absorber, v_puerta))
            or (strpos(lower(p.prosrc), 'lead_historia_de_persona') > 0 and p.oid not in (v_historia, v_puerta, v_escritura, v_lectura))
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_absorber, v_enlazar, v_historia)) x;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'conversion_absorber_cliente_antiguo') > 0 or strpos(lower(j.command), 'conversion_enlazar_cliente_antiguo') > 0
                   or strpos(lower(j.command), 'lead_historia_de_persona') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'REVERSA conversion_cliente_antiguo: otro objeto usa las piezas (%): revisar a mano antes de borrarlas', v_mal;
  end if;
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('crm.leads', 'leads_dni_check', '6dcca3c962687ba896d101adf845d281'),
    ('crm.inversionista_leads', 'inversionista_leads_rol_check', 'f6a33854861793c8dc204e1b32c07716'),
    ('crm.inversionista_leads', 'inversionista_leads_lead_id_fkey', 'c6c7de31923066a9f3b843e9c875aec6'),
    ('crm.inversionista_leads', 'inversionista_leads_inversionista_id_fkey', '99bee63006ab85e4e5c1d5fdf071a137'),
    ('crm.inversionista_leads', 'inversionista_leads_creado_por_fkey', '8b21ba4ae6f1720bfba13340e69e1f2e'),
    ('crm.inversionista_operaciones', 'inversionista_operaciones_tipo_check', 'c3b74a13c0bd2414b83c800af4f02d4b'),
    ('crm.inversionista_operaciones', 'inversionista_operaciones_motivo_check', '6c884dea657b7a534f19f04abd86d684')) e(tabla, nombre, definicion)
  left join pg_constraint c on c.conrelid = e.tabla::regclass and c.conname = e.nombre
  where c.oid is null or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'REVERSA conversion_cliente_antiguo: cambió o falta una restricción de la que depende la regla (%): revisar a mano', v_mal;
  end if;
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('leads_inversionista_uidx', 'a9f9b423261a56190a909eeea80a4a27'),
    ('inversionista_leads_lead_uidx', md5('CREATE UNIQUE INDEX inversionista_leads_lead_uidx ON crm.inversionista_leads USING btree (lead_id)')),
    ('inversionista_leads_canonico_uidx', md5('CREATE UNIQUE INDEX inversionista_leads_canonico_uidx ON crm.inversionista_leads USING btree (inversionista_id) WHERE (rol = ''canonico''::text)'))) e(nombre, definicion)
  left join pg_indexes i on i.schemaname = 'crm' and i.indexname = e.nombre
  where i.indexname is null or md5(i.indexdef) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'REVERSA conversion_cliente_antiguo: cambió o falta un índice único del que depende la regla (%): revisar a mano', v_mal;
  end if;
  if exists (select 1 from pg_class c where c.oid in ('crm.inversionista_leads'::regclass, 'crm.inversionista_operaciones'::regclass)
               and (not c.relrowsecurity or c.relacl is not null or c.relowner <> 'postgres'::regrole::oid)) then
    raise exception 'REVERSA conversion_cliente_antiguo: el puente persona-lead o el libro de operaciones ya no es como se auditó (RLS activa, sin grants, dueño postgres): revisar a mano';
  end if;
  -- Las premisas de D-83/D-85 (el cierre) y de D-86/D-87 (el perfil), fijadas (auditor r2): a lo sumo un cierre inicial por lead; el
  -- documento del cierre y su tipo NOT NULL y con su formato (por eso no hay rama «sin documento»); crm.inversiones.inversionista_id NOT
  -- NULL (un cierre sin persona no tiene inversión); el disparador de inmutables del cierre, enlazado y activo; el perfil único por
  -- persona no fusionada (la carrera da 23505, que la pieza de enlace traduce al 40001) y su clave foránea; los disparadores de
  -- crm.inversionistas que reaccionan al completar el perfil (su conjunto exacto y activo).
  select string_agg(z.x, ', ' order by z.x) into v_mal
  from (
    select 'restricción ' || e.nombre as x
    from (values
      ('crm.cierres_externos', 'cierres_externos_documento_formato', 'e5f8b87595e008282602e238bf581984'),
      ('crm.cierres_externos', 'cierres_externos_documento_tipo_check', 'e2c34a1a34e26c147329f046c1e1da5b'),
      ('crm.inversionistas', 'inversionistas_perfil_id_fkey', '7f74ba99b1e24898320e925b0cd3563a')) e(tabla, nombre, definicion)
    left join pg_constraint c on c.conrelid = e.tabla::regclass and c.conname = e.nombre
    where c.oid is null or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion
    union all
    select 'índice ' || e.nombre
    from (values
      ('cierres_externos_inicial_por_lead_uidx', 'cf8c81018d22bd499463d6cd8f101f6b'),
      ('inversionistas_perfil_uidx', '9bda30dce00b9694bc5aab719b053305')) e(nombre, definicion)
    left join pg_indexes i on i.schemaname = 'crm' and i.indexname = e.nombre
    where i.indexname is null or md5(i.indexdef) is distinct from e.definicion
    union all
    select 'NOT NULL ' || e.tabla || '.' || e.columna
    from (values ('crm.cierres_externos', 'documento'), ('crm.cierres_externos', 'documento_tipo'), ('crm.inversiones', 'inversionista_id')) e(tabla, columna)
    left join pg_attribute a on a.attrelid = e.tabla::regclass and a.attname = e.columna and not a.attisdropped
    where a.attnum is null or not a.attnotnull
    union all
    select 'disparador trg_cierres_externos_00_inmutables'
    where not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_externos_00_inmutables'
                        and t.tgenabled = 'O' and md5(pg_get_triggerdef(t.oid)) = 'e6e9970fea6f192205d0000d5b5f3dc6')
    union all
    select 'disparador ' || e.nombre
    from (values
      ('trg_leads_before_update', '02b8824f01e2f5aa026f478241711c8a'),
      ('trg_leads_zzz_tenencia_desde', 'f5849e264eb05e8a253dbd78c2362fba')) e(nombre, definicion)
    where not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = e.nombre and t.tgenabled = 'O'
                        and md5(pg_get_triggerdef(t.oid)) = e.definicion)
    union all
    select 'disparadores de crm.inversionistas'
    where (select count(*) || '|' || md5(string_agg(t.tgname || ':' || t.tgenabled::text || ':' || pg_get_triggerdef(t.oid), '|' order by t.tgname))
             from pg_trigger t where t.tgrelid = 'crm.inversionistas'::regclass and not t.tgisinternal) is distinct from '5|104c0bb1234815233ef1bfe823936553'
  ) z;
  if v_mal is not null then
    raise exception 'REVERSA conversion_cliente_antiguo: cambió o falta una premisa del cierre o del perfil (%): revisar a mano', v_mal;
  end if;
  if (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado')
     is distinct from '29|60a0851245859d8e1f0da6e2276a2594' or to_regprocedure('private.assert_gestion_diaria_resultado()') is null then
    raise exception 'REVERSA conversion_cliente_antiguo: el inventario de los private.assert_*() no es el que deja la migración (%): revisar a mano',
      (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado');
  end if;
  perform set_config('reversa_conversion_cliente_antiguo.puerta_antes', (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_puerta), true);
  perform set_config('reversa_conversion_cliente_antiguo.escritura_antes', (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_escritura), true);
  perform set_config('reversa_conversion_cliente_antiguo.lectura_antes', (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_lectura), true);
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  perform set_config('reversa_conversion_cliente_antiguo.trinquetes_antes', v_foto, true);
end
$rpf$;

-- ── La puerta y los dos núcleos, por ancla única: se quita lo que puso la migración ───────────────────────────────────
do $rg1$
declare
  v_firma regprocedure := 'crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;
  v_nuevo := $rn$  perform set_config('crm.op_privilegiada',v_config,true);
  -- Bloque 2.10 (D-38): los clientes antiguos absorbidos (ya retirados, con su rastro) se enlazan AHORA, después del UPDATE —el
  -- verificador que corre al escribir el DNI aplica «un solo lead por persona» y contaría el puente—, como HISTÓRICO de la persona
  -- (puente sin puntero; el canónico es este lead).
  if v_antiguo ? 'candidatos' then
    perform private.conversion_enlazar_cliente_antiguo(v_persona,v_antiguo->'candidatos',v_uid);
  end if;
  -- Además aplica las banderas/membresía de F4 y el ámbito canónico de Cartera.
$rn$;
  v_ancla := $ra$  perform set_config('crm.op_privilegiada',v_config,true);
  -- Además aplica las banderas/membresía de F4 y el ámbito canónico de Cartera.
$ra$;
  v_veces := (length(v_def) - length(replace(v_def, v_nuevo, ''))) / length(v_nuevo);
  if v_veces <> 1 then
    raise exception 'REVERSA conversion_cliente_antiguo: el bloque «tras el UPDATE» que puso la migración aparece % veces en crm.preparar_persona_lead_inversion_fn (debe ser 1): revisar a mano', v_veces;
  end if;
  v_def := replace(v_def, v_nuevo, v_ancla);
  v_nuevo := $rn$  -- Bloque 2.10 (D-38 de Miguel, 09/10/2026; caso P2 del 2.8): el DNI de un CLIENTE ANTIGUO SIN FICHA DE PERSONA (lead
  -- convertido sin persona ni puente). Con la fila del lead que se convierte ya tomada FOR UPDATE, la pieza toma las de esos
  -- convertidos (FOR UPDATE NOWAIT) y decide: si alguno sigue ACTIVO a nombre de OTRO asesor ⇒ «ya es cliente de X» (el veredicto
  -- del alta, D-29) con el P0481 de la regla del cliente y nada se escribe; si no (retirados, o activos del mismo asesor) ⇒ los
  -- absorbe en la ficha de esta conversión: su rastro (libro de operaciones; nota en el lead si está activo) y, si está activo, su
  -- RETIRO (la casa no admite dos leads vivos de una persona), y la conversión sigue: el cliente pasa al asesor que convierte (el
  -- responsable de la persona, abajo). El puente HISTÓRICO se pone después del UPDATE de este lead (más abajo). Solo con DNI
  -- (crm.leads.dni solo guarda DNI). Va después de todo lo que hoy decide y antes de la conciliación, que no cuenta esa historia como
  -- «otro lead» (private.lead_historia_de_persona) si la puso ESTA conversión (D-91, abajo). Nada cambia para leads sin coincidencia
  -- ni para clientes con ficha.
  if p_tipo_documento='DNI' then
    v_antiguo:=private.conversion_absorber_cliente_antiguo(p_lead,v_persona,v_doc,v_l.vendedor_id,v_uid);
    if v_antiguo ? 'veredicto' then
      raise exception 'Contacto no disponible' using errcode='P0481', detail=(v_antiguo->'veredicto')::text;
    end if;
  end if;
  if (v_l.inversionista_id is not null and v_l.inversionista_id is distinct from v_persona)
    or exists(select 1 from crm.inversionista_leads il where il.lead_id=p_lead
      and private.inversionista_canonica(il.inversionista_id) is distinct from v_persona)
    or exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead and not private.lead_historia_de_persona(x,v_persona))
    or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead and not private.lead_historia_de_persona(x,v_persona))
    -- D-91 (Miguel, 10/10/2026), SOLO cuando esta preparación ESCRIBE el DNI del lead (ronda 8): aquí, en la puerta, esa historia solo
    -- exime si la puso ESTA conversión (su operación de enlace lleva lead_conversion = este lead); un puente HISTÓRICO a la persona que
    -- ya existía antes (de Gerencia, de la carga o de la conversión de OTRO lead) ⇒ la conciliación de hoy y nada escrito, porque el
    -- verificador sellado lo contaría como lead de la persona al escribir el DNI y pararía con P0481 «ya es cliente» (D-92 lo ajustará).
    -- Ese verificador solo corre si el UPDATE de abajo SOLICITA cambiar el DNI (l. 93-94 de la definición auditada b40dded8…: dni=case when
    -- p_tipo_documento='DNI' then v_doc else dni end; el teléfono no se toca): el disparador de disponibilidad lo llama solo si cambia
    -- el teléfono o el DNI (l. 42-43 y 70 de la función de ese disparador, 418b0976…, que esta migración no fija), es decir
    -- si p_tipo_documento='DNI' y el lead aún no lleva ese documento (antes del UPDATE, l. 34 y 47, su DNI está vacío o es v_doc); en el flujo
    -- ordinario auditado eso alcanza el verificador (el disparador tiene una salida anticipada para la corrección de documento de Gerencia, l. 58-69, con
    -- la GUC crm.correccion_documento bajo la válvula: que ninguna sesión la conserve al llamar a esta puerta es una premisa que se verifica al integrar). Si el
    -- lead YA lleva ese DNI —el estado del backfill de identidad y de la carga: el lead vivo canónico y un convertido retirado con
    -- puente histórico— o el documento es un CE o un pasaporte, el verificador NO corre y manda D-90: la historia cuenta y la
    -- conversión sigue. Si ese lead no es historia, las dos comprobaciones de arriba ya lo detienen igual. Los núcleos siguen contando
    -- la historia como tal (D-90). El reintento de la misma preparación ya lleva el DNI: esta condición no lo evalúa (la exención por
    -- lead_conversion se conserva).
    or (p_tipo_documento='DNI' and v_l.dni is distinct from v_doc
      and exists(select 1 from crm.inversionista_leads il where il.inversionista_id=v_persona and il.rol='historico' and il.lead_id<>p_lead
        and not exists(select 1 from crm.inversionista_operaciones o where o.tipo='enlace' and o.lead_id=il.lead_id
          and o.detalle->>'lead_conversion'=p_lead::text))) then
    raise exception 'Esta persona ya tiene otra identidad o lead; requiere conciliación' using errcode='P0409';
  end if;
  -- D-94 (Miguel, 12/10/2026; P2-1 de Codex r2, medido en rollback): el «No insistir» de un antiguo de la persona detiene SIEMPRE la conversión con la
  -- respuesta que el alta y el verificador sellado dan a ese veto (P0481 «Contacto no disponible», detalle {"estado": "no_contactar"}) y no deja
  -- nada escrito (el rechazo deshace la absorción de arriba, como el del verificador en A15/A20). Cubre (a) los leads de la persona que la conversión
  -- cuenta como HISTORIA (D-90: la pieza de historia, que aquí es el retirado ya unido por puente histórico) y (b) los candidatos que la pieza de
  -- absorción acaba de tomar (D-38: v_antiguo, ya bloqueados FOR UPDATE NOWAIT por ella). Sitio: DESPUÉS de la conciliación —el antiguo que no es
  -- historia sigue yendo al P0409 de hoy y, con el lead SIN DNI, manda el P0409 de D-91— y ANTES del UPDATE de abajo (l. 93-94 de la definición
  -- auditada b40dded8…), que es donde hoy el verificador pararía este veto; pero el verificador solo corre si ese UPDATE solicita cambiar el DNI, y con
  -- el DNI ya escrito o con un CE o un pasaporte no corre y el veto se saltaba (M1, M2 y M4 de la medida del Director: hoy P0409 o convierte sin
  -- absorber; la ronda 8 convertía y absorbía). Lee `no_contactar` de los antiguos con un SELECT simple, sin candados nuevos (como el verificador:
  -- una marca levantada a la vez es la carrera de siempre del veto). Con CE o pasaporte no hay candidatos (la absorción solo corre con un DNI).
  if exists(select 1 from private.leads_de_personas(array[v_persona]) x join crm.leads lx on lx.id=x
        where x<>p_lead and lx.no_contactar and private.lead_historia_de_persona(x,v_persona))
    or exists(select 1 from jsonb_array_elements(coalesce(v_antiguo->'candidatos','[]'::jsonb)) c join crm.leads lc on lc.id=(c->>'id')::uuid
        where lc.no_contactar) then
    raise exception 'Contacto no disponible' using errcode='P0481', detail=jsonb_build_object('estado','no_contactar')::text;
  end if;
$rn$;
  v_ancla := $ra$  if (v_l.inversionista_id is not null and v_l.inversionista_id is distinct from v_persona)
    or exists(select 1 from crm.inversionista_leads il where il.lead_id=p_lead
      and private.inversionista_canonica(il.inversionista_id) is distinct from v_persona)
    or exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
    or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead) then
    raise exception 'Esta persona ya tiene otra identidad o lead; requiere conciliación' using errcode='P0409';
  end if;
$ra$;
  v_veces := (length(v_def) - length(replace(v_def, v_nuevo, ''))) / length(v_nuevo);
  if v_veces <> 1 then
    raise exception 'REVERSA conversion_cliente_antiguo: el bloque «la absorción y la conciliación» que puso la migración aparece % veces en crm.preparar_persona_lead_inversion_fn (debe ser 1): revisar a mano', v_veces;
  end if;
  v_def := replace(v_def, v_nuevo, v_ancla);
  v_nuevo := $rn$  v_config text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
  v_antiguo jsonb;
begin
$rn$;
  v_ancla := $ra$  v_config text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
begin
$ra$;
  v_veces := (length(v_def) - length(replace(v_def, v_nuevo, ''))) / length(v_nuevo);
  if v_veces <> 1 then
    raise exception 'REVERSA conversion_cliente_antiguo: el bloque «la variable» que puso la migración aparece % veces en crm.preparar_persona_lead_inversion_fn (debe ser 1): revisar a mano', v_veces;
  end if;
  v_def := replace(v_def, v_nuevo, v_ancla);
  execute v_def;
  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'REVERSA conversion_cliente_antiguo: los permisos de crm.preparar_persona_lead_inversion_fn cambiaron al revertir';
  end if;
end
$rg1$;

do $rg2$
declare
  v_firma regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  foreach v_firma in array array['private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'::regprocedure,
                                 'private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'::regprocedure] loop
    select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;
  v_nuevo := $rn$    -- Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no es «otro lead».
    if exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead and not private.lead_historia_de_persona(x,v_persona))
      or exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion) then
      raise exception 'La persona ya tiene una conversión inicial; requiere conciliación' using errcode='P0409';
    end if;
$rn$;
  v_ancla := $ra$    if exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
      or exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion) then
      raise exception 'La persona ya tiene una conversión inicial; requiere conciliación' using errcode='P0409';
    end if;
$ra$;
  v_veces := (length(v_def) - length(replace(v_def, v_nuevo, ''))) / length(v_nuevo);
  if v_veces <> 1 then
    raise exception 'REVERSA conversion_cliente_antiguo: el bloque «la conciliación» que puso la migración aparece % veces en private.inversion_persona_contexto_para (debe ser 1): revisar a mano', v_veces;
  end if;
  v_def := replace(v_def, v_nuevo, v_ancla);
    execute v_def;
    if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
      raise exception 'REVERSA conversion_cliente_antiguo: los permisos de % cambiaron al revertir', v_firma;
    end if;
  end loop;
end
$rg2$;

-- ── Los comentarios: la puerta vuelve a no tener; a los núcleos se les quita la frase del 2.10 (exactamente al final) ──────
comment on function crm.preparar_persona_lead_inversion_fn(uuid, text, text, text) is null;
do $rcom$
declare
  v_com text;
begin
  v_com := obj_description('private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'::regprocedure, 'pg_proc');
  if right(v_com, length($w1$ Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no cuenta como otro lead en la conciliacion.$w1$)) is distinct from $w1$ Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no cuenta como otro lead en la conciliacion.$w1$ then
    raise exception 'REVERSA conversion_cliente_antiguo: el comentario de private.inversion_persona_contexto_para no termina con la frase del 2.10';
  end if;
  execute pg_catalog.format('comment on function private.inversion_persona_contexto_para(uuid, uuid, uuid, uuid) is %L', left(v_com, length(v_com) - length($w1$ Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no cuenta como otro lead en la conciliacion.$w1$)));
  v_com := obj_description('private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'::regprocedure, 'pg_proc');
  if right(v_com, length($w2$ Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no cuenta como otro lead en la conciliacion.$w2$)) is distinct from $w2$ Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no cuenta como otro lead en la conciliacion.$w2$ then
    raise exception 'REVERSA conversion_cliente_antiguo: el comentario de private.inversion_contexto_lectura_para no termina con la frase del 2.10';
  end if;
  execute pg_catalog.format('comment on function private.inversion_contexto_lectura_para(uuid, uuid, uuid, uuid) is %L', left(v_com, length(v_com) - length($w2$ Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no cuenta como otro lead en la conciliacion.$w2$)));
end
$rcom$;

-- ── Las tres piezas: fuera, sin CASCADE (ya nadie las nombra) ──────────────────────────────────────────────────────────
drop function private.conversion_enlazar_cliente_antiguo(uuid, jsonb, uuid);
drop function private.conversion_absorber_cliente_antiguo(uuid, uuid, text, uuid, uuid);
drop function private.lead_historia_de_persona(uuid, uuid);

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $rpost$
declare
  v_puerta regprocedure := to_regprocedure('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)');
  v_escritura regprocedure := to_regprocedure('private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)');
  v_lectura regprocedure := to_regprocedure('private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)');
  v_absorber regprocedure := to_regprocedure('private.conversion_absorber_cliente_antiguo(uuid,uuid,text,uuid,uuid)');
  v_enlazar regprocedure := to_regprocedure('private.conversion_enlazar_cliente_antiguo(uuid,jsonb,uuid)');
  v_historia regprocedure := to_regprocedure('private.lead_historia_de_persona(uuid,uuid)');
  v_mal text;
  r record;
  v text;
  v_foto text := '';
begin
  if v_absorber is not null or v_enlazar is not null or v_historia is not null then
    raise exception 'REVERSA conversion_cliente_antiguo: alguna pieza sigue existiendo';
  end if;
  if exists (select 1 from pg_proc p where p.oid in (v_puerta, v_escritura, v_lectura)
               and (strpos(lower(p.prosrc), 'conversion_absorber_cliente_antiguo') > 0 or strpos(lower(p.prosrc), 'conversion_enlazar_cliente_antiguo') > 0
                    or strpos(lower(p.prosrc), 'lead_historia_de_persona') > 0)) then
    raise exception 'REVERSA conversion_cliente_antiguo: la puerta o un núcleo sigue nombrando a las piezas';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_puerta) is distinct from '4eebf912d4abc0b101e3c39688dc0c54/df451bd3cc831e2b47a26eb867c9e65e' then
    raise exception 'REVERSA (postflight) conversion_cliente_antiguo: crm.preparar_persona_lead_inversion_fn no es la de antes de la migración (md5 del cuerpo / de la definición %; se esperaba 4eebf912d4abc0b101e3c39688dc0c54/df451bd3cc831e2b47a26eb867c9e65e): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_puerta);
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_escritura) is distinct from 'b67d8181139ab76ff9232523a67dfa11/dcc540a48b7f252c783f814f6a184144' then
    raise exception 'REVERSA (postflight) conversion_cliente_antiguo: private.inversion_persona_contexto_para no es la de antes de la migración (md5 del cuerpo / de la definición %; se esperaba b67d8181139ab76ff9232523a67dfa11/dcc540a48b7f252c783f814f6a184144): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_escritura);
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_lectura) is distinct from 'b1106c6c67be483f8fb655a276e3def4/477d0e80266faa6add30929337f00701' then
    raise exception 'REVERSA (postflight) conversion_cliente_antiguo: private.inversion_contexto_lectura_para no es la de antes de la migración (md5 del cuerpo / de la definición %; se esperaba b1106c6c67be483f8fb655a276e3def4/477d0e80266faa6add30929337f00701): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_lectura);
  end if;
  if obj_description(v_puerta, 'pg_proc') is not null
     or md5(coalesce(obj_description(v_escritura, 'pg_proc'), '')) is distinct from '5e0226384bc1c2db4fa72bb8dad54fff'
     or md5(coalesce(obj_description(v_lectura, 'pg_proc'), '')) is distinct from '84620ea87a16f7610aa05d3a636b3623' then
    raise exception 'REVERSA conversion_cliente_antiguo: los comentarios no volvieron a los de antes';
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_puerta) is distinct from current_setting('reversa_conversion_cliente_antiguo.puerta_antes', true)
     or (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_escritura) is distinct from current_setting('reversa_conversion_cliente_antiguo.escritura_antes', true)
     or (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_lectura) is distinct from current_setting('reversa_conversion_cliente_antiguo.lectura_antes', true) then
    raise exception 'REVERSA conversion_cliente_antiguo: la ficha de la puerta o de un núcleo cambió al revertir';
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.acceso_inversion_fn(uuid,text,jsonb)', 'b45c309fce1003058ee42de5804d95a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.buscar_cliente_existente_fn(text,text,text,uuid)', '43b317c13c40471a3e3eec2fbbe0fb8a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.confirmar_inversion_fn(uuid)', 'e69358303d4b6220354460965179c28d', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)', '33af606a814c74de5de8a080430bb299', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.contexto_cliente_existente_fn(uuid,uuid)', '8cd36f9311dd59327fa749f4568861cb', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.contexto_conversion_inversion_fn(uuid,uuid)', 'a616232e3ada628404fc6a1a8356eb13', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)', 'c41aa8ee34da4b3f828289058c41e4f4', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', '1159aa8443c117c8c9384a2bcf17ae2b', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.inversionista_ficha_fn(uuid,integer,integer)', 'be113f3c638e3fdf6e0ca9a45eb86a6d', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.preparar_inversion_fn(uuid,jsonb)', '5fefbc143578a735a8648f686f71bf9a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)', 'dc622b938e8d8e9777a033cfa625b11a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.documento_es_de_identidad(uuid,text,text)', '724c4c781b1ed289a5320ab6c9d2eea8', 'postgres:EXECUTE:false'),
    ('private.f4_comprobante_autorizado(text)', 'cdecad21e77c38d023ba156efd8faa74', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.f4_fuente_inmutable()', 'f4608368a957e5ce1fe191562d5b5bea', 'postgres:EXECUTE:false'),
    ('private.identidad_bloquear_documento(text,text)', '9c08b500af7bc11aeba5e0e7d3a63330', 'postgres:EXECUTE:false'),
    ('private.identidad_bloquear_documentos_de(uuid[])', '81dffba49b46f2defc723e53a9a96d67', 'postgres:EXECUTE:false'),
    ('private.inversion_contexto_lectura(uuid,uuid)', '7ae71408f49ecd1eb2a05ed746746dde', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_autorizada_para(uuid,uuid,uuid)', 'c91e82b30558d121782f94aefab39d6e', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_contexto(uuid)', '335fa43d5eed5d0d8010d9d0716483ce', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_contexto(uuid,uuid)', 'a7ce8164838edc6b64cdc3f933c5a276', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_lectura_para(uuid,uuid,uuid)', '6539960f2d9b7896e2c4083f80361f57', 'postgres:EXECUTE:false'),
    ('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)', 'c34bc06eafdb62f128476a8bffbfa642', 'postgres:EXECUTE:false'),
    ('private.inversiones_escritura_bajo_candado()', '2122bbf3b22996f2e8373081a259db9b', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.inversionista_fusion_destino_activo()', '861f359c23ab031945f4bad75f8dc3a7', 'postgres:EXECUTE:false'),
    ('private.inversionista_operaciones_append_only()', '909d41d42674ccb6775597fd4235ebca', 'postgres:EXECUTE:false'),
    ('private.inversionista_resolver(text,text,boolean,text)', '95d502fcae257bf2a439ec3e4aa6a2dc', 'postgres:EXECUTE:false'),
    ('private.juicio_cliente_convertido(text,text,text,uuid)', 'a2b38faf42a875c7dffb7968b106e36f', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.leads_before_update()', '4ae909f2d56ca650b5595b505e6aa51d', 'postgres:EXECUTE:false'),
    ('private.leads_de_identidades(uuid[])', '2421b2b78b02b8e93fd01598e2f54128', 'postgres:EXECUTE:false'),
    ('private.leads_de_personas(uuid[])', '6eded477639796c1053f0190f6decc18', 'postgres:EXECUTE:false'),
    ('private.leads_protege_inversionista_id()', '6151f6d4da6c80fc62ad7f131ea398a4', 'postgres:EXECUTE:false'),
    ('private.log_audit_crm()', 'c25c2af183b650f4d4c85abedd5bcc97', 'postgres:EXECUTE:false'),
    ('private.puede_gestionar_contratos_crm()', '94b5fb2af92bf4187802b1f3d26659c5', 'postgres:EXECUTE:false'),
    ('private.resolver_en_puertas_bajo_candado()', '5f74d26262fcc83e5975672da141be63', 'postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.trg_cierres_externos_inmutables()', 'c9f55c70e526975476b1f6aead562cd4', '-:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.trg_gestion_lead_serializada()', '7af0e66b8a4849566e43b514245e1b86', 'postgres:EXECUTE:false'),
    ('private.trg_leads_tenencia_desde()', '900508fa3ccf3eec2e738ccdeebad7be', 'postgres:EXECUTE:false'),
    ('private.trg_leads_zz_enlaza_identidad()', '6ea5abfcc7bc7113f62f175df4e65879', 'postgres:EXECUTE:false'),
    ('private.trg_leads_zz_puente_identidad()', 'e96f21d1c58623f6c2a84e7c04683a5c', 'postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'REVERSA (postflight) conversion_cliente_antiguo: cambió algo que la reversa no toca (%)', v_mal;
  end if;
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('crm.leads', 'leads_dni_check', '6dcca3c962687ba896d101adf845d281'),
    ('crm.inversionista_leads', 'inversionista_leads_rol_check', 'f6a33854861793c8dc204e1b32c07716'),
    ('crm.inversionista_leads', 'inversionista_leads_lead_id_fkey', 'c6c7de31923066a9f3b843e9c875aec6'),
    ('crm.inversionista_leads', 'inversionista_leads_inversionista_id_fkey', '99bee63006ab85e4e5c1d5fdf071a137'),
    ('crm.inversionista_leads', 'inversionista_leads_creado_por_fkey', '8b21ba4ae6f1720bfba13340e69e1f2e'),
    ('crm.inversionista_operaciones', 'inversionista_operaciones_tipo_check', 'c3b74a13c0bd2414b83c800af4f02d4b'),
    ('crm.inversionista_operaciones', 'inversionista_operaciones_motivo_check', '6c884dea657b7a534f19f04abd86d684')) e(tabla, nombre, definicion)
  left join pg_constraint c on c.conrelid = e.tabla::regclass and c.conname = e.nombre
  where c.oid is null or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'REVERSA (postflight) conversion_cliente_antiguo: cambió o falta una restricción de la que depende la regla (%): revisar a mano', v_mal;
  end if;
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('leads_inversionista_uidx', 'a9f9b423261a56190a909eeea80a4a27'),
    ('inversionista_leads_lead_uidx', md5('CREATE UNIQUE INDEX inversionista_leads_lead_uidx ON crm.inversionista_leads USING btree (lead_id)')),
    ('inversionista_leads_canonico_uidx', md5('CREATE UNIQUE INDEX inversionista_leads_canonico_uidx ON crm.inversionista_leads USING btree (inversionista_id) WHERE (rol = ''canonico''::text)'))) e(nombre, definicion)
  left join pg_indexes i on i.schemaname = 'crm' and i.indexname = e.nombre
  where i.indexname is null or md5(i.indexdef) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'REVERSA (postflight) conversion_cliente_antiguo: cambió o falta un índice único del que depende la regla (%): revisar a mano', v_mal;
  end if;
  if exists (select 1 from pg_class c where c.oid in ('crm.inversionista_leads'::regclass, 'crm.inversionista_operaciones'::regclass)
               and (not c.relrowsecurity or c.relacl is not null or c.relowner <> 'postgres'::regrole::oid)) then
    raise exception 'REVERSA (postflight) conversion_cliente_antiguo: el puente persona-lead o el libro de operaciones ya no es como se auditó (RLS activa, sin grants, dueño postgres): revisar a mano';
  end if;
  -- Las premisas de D-83/D-85 (el cierre) y de D-86/D-87 (el perfil), fijadas (auditor r2): a lo sumo un cierre inicial por lead; el
  -- documento del cierre y su tipo NOT NULL y con su formato (por eso no hay rama «sin documento»); crm.inversiones.inversionista_id NOT
  -- NULL (un cierre sin persona no tiene inversión); el disparador de inmutables del cierre, enlazado y activo; el perfil único por
  -- persona no fusionada (la carrera da 23505, que la pieza de enlace traduce al 40001) y su clave foránea; los disparadores de
  -- crm.inversionistas que reaccionan al completar el perfil (su conjunto exacto y activo).
  select string_agg(z.x, ', ' order by z.x) into v_mal
  from (
    select 'restricción ' || e.nombre as x
    from (values
      ('crm.cierres_externos', 'cierres_externos_documento_formato', 'e5f8b87595e008282602e238bf581984'),
      ('crm.cierres_externos', 'cierres_externos_documento_tipo_check', 'e2c34a1a34e26c147329f046c1e1da5b'),
      ('crm.inversionistas', 'inversionistas_perfil_id_fkey', '7f74ba99b1e24898320e925b0cd3563a')) e(tabla, nombre, definicion)
    left join pg_constraint c on c.conrelid = e.tabla::regclass and c.conname = e.nombre
    where c.oid is null or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion
    union all
    select 'índice ' || e.nombre
    from (values
      ('cierres_externos_inicial_por_lead_uidx', 'cf8c81018d22bd499463d6cd8f101f6b'),
      ('inversionistas_perfil_uidx', '9bda30dce00b9694bc5aab719b053305')) e(nombre, definicion)
    left join pg_indexes i on i.schemaname = 'crm' and i.indexname = e.nombre
    where i.indexname is null or md5(i.indexdef) is distinct from e.definicion
    union all
    select 'NOT NULL ' || e.tabla || '.' || e.columna
    from (values ('crm.cierres_externos', 'documento'), ('crm.cierres_externos', 'documento_tipo'), ('crm.inversiones', 'inversionista_id')) e(tabla, columna)
    left join pg_attribute a on a.attrelid = e.tabla::regclass and a.attname = e.columna and not a.attisdropped
    where a.attnum is null or not a.attnotnull
    union all
    select 'disparador trg_cierres_externos_00_inmutables'
    where not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_externos_00_inmutables'
                        and t.tgenabled = 'O' and md5(pg_get_triggerdef(t.oid)) = 'e6e9970fea6f192205d0000d5b5f3dc6')
    union all
    select 'disparador ' || e.nombre
    from (values
      ('trg_leads_before_update', '02b8824f01e2f5aa026f478241711c8a'),
      ('trg_leads_zzz_tenencia_desde', 'f5849e264eb05e8a253dbd78c2362fba')) e(nombre, definicion)
    where not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = e.nombre and t.tgenabled = 'O'
                        and md5(pg_get_triggerdef(t.oid)) = e.definicion)
    union all
    select 'disparadores de crm.inversionistas'
    where (select count(*) || '|' || md5(string_agg(t.tgname || ':' || t.tgenabled::text || ':' || pg_get_triggerdef(t.oid), '|' order by t.tgname))
             from pg_trigger t where t.tgrelid = 'crm.inversionistas'::regclass and not t.tgisinternal) is distinct from '5|104c0bb1234815233ef1bfe823936553'
  ) z;
  if v_mal is not null then
    raise exception 'REVERSA (postflight) conversion_cliente_antiguo: cambió o falta una premisa del cierre o del perfil (%): revisar a mano', v_mal;
  end if;
  if (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado')
     is distinct from '29|60a0851245859d8e1f0da6e2276a2594' then
    raise exception 'REVERSA conversion_cliente_antiguo: el inventario de los private.assert_*() cambió al revertir (%)',
      (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado');
  end if;
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  if v_foto is distinct from current_setting('reversa_conversion_cliente_antiguo.trinquetes_antes', true) then
    raise exception E'REVERSA conversion_cliente_antiguo: algún private.assert_*() da otro resultado que antes de revertir.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('reversa_conversion_cliente_antiguo.trinquetes_antes', true), v_foto;
  end if;
  raise notice 'REVERSA conversion_cliente_antiguo: la puerta y los dos núcleos de antes (cuerpo, definición, ficha y comentario), las tres piezas borradas, lo demás intacto';
end
$rpost$;

commit;
