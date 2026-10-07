-- Upgrade Avance: el nuevo aporte puede pactarse por debajo de su referencia.
-- El interruptor existente sigue mandando: observación no pide ni consume
-- aprobaciones; enforcement exige autorización por encima de la referencia.
-- No cambia contratos existentes, firmas, propietarios, ACL ni configuración.
-- Reversa: ../scripts/upgrade-tasa/reversa.sql (solo antes del primer uso).
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $preflight$
declare f record;
begin
  for f in select * from (values
    ('private.rentabilidad_minimo_alta(text,numeric)','16035988be07d26455c2c48f1f59c8c0'),
    ('private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid)','f6655428825fda40e8c7ba7a12cdddde'),
    ('private.trg_contratos_observar_rentabilidad()','58664972f2caf80b2d4557d541467340')
  ) esperado(firma,huella) loop
    if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid=to_regprocedure(f.firma)) is distinct from f.huella then
      raise exception 'Upgrade tasa: % cambió; revisar antes de aplicar',f.firma;
    end if;
  end loop;
end;
$preflight$;

do $cambio$
declare cuerpo text; antes text; despues text;
begin
  cuerpo:=pg_get_functiondef('private.rentabilidad_minimo_alta(text,numeric)'::regprocedure);
  antes:=$a$p_categoria='nuevo'$a$;
  despues:=$d$p_categoria in ('nuevo','upgrade')$d$;
  if cardinality(string_to_array(cuerpo,antes))<>2 then raise exception 'Mínimo: ancla no única'; end if;
  execute replace(cuerpo,antes,despues);

  -- Conservar la respuesta que aceptan los bundles anteriores. Solo el CRM
  -- que conoce la nueva capacidad usa el mínimo específico de upgrade.
  cuerpo:=pg_get_functiondef('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)'::regprocedure);
  antes:=$a$'tasa_minima_sin_autorizacion', private.rentabilidad_minimo_alta(p_categoria, v_base),$a$;
  despues:=$d$'tasa_minima_sin_autorizacion', case when p_categoria='upgrade' then v_base else private.rentabilidad_minimo_alta(p_categoria, v_base) end,
    'tasa_minima_upgrade_sin_autorizacion', case when p_categoria='upgrade' then private.rentabilidad_minimo_alta(p_categoria, v_base) else null end,$d$;
  if cardinality(string_to_array(cuerpo,antes))<>2 then raise exception 'Resolución: ancla no única'; end if;
  execute replace(cuerpo,antes,despues);

  cuerpo:=pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure);
  antes:=$a$        v_c.categoria='nuevo'
        and v_c.tasa_anual >= private.rentabilidad_minimo_alta(v_c.categoria,v_base)
        and (tg_op='INSERT' or (tg_op='UPDATE'
          and old.categoria='nuevo' and old.es_demo is not true$a$;
  despues:=$d$        v_c.categoria in ('nuevo','upgrade')
        and v_c.tasa_anual >= private.rentabilidad_minimo_alta(v_c.categoria,v_base)
        and (tg_op='INSERT' or (tg_op='UPDATE'
          and old.categoria=v_c.categoria and old.es_demo is not true$d$;
  if cardinality(string_to_array(cuerpo,antes))<>2 then raise exception 'Validación: ancla no única'; end if;
  cuerpo:=replace(cuerpo,antes,despues);

  antes:=$a$-- D4 revisada: el alta nueva admite una tasa menor. Una corrección solo$a$;
  despues:=$d$-- Alta nueva y upgrade admiten una tasa menor. Una corrección solo$d$;
  if cardinality(string_to_array(cuerpo,antes))<>2 then raise exception 'Regla: ancla no única'; end if;
  cuerpo:=replace(cuerpo,antes,despues);

  antes:=$a$'tasa_inferior_sin_excepcion', case when v_c.categoria='nuevo' and v_c.tasa_anual<v_base then true end$a$;
  despues:=$d$'tasa_inferior_sin_excepcion', case when v_c.categoria in ('nuevo','upgrade') and v_c.tasa_anual<v_base then true end$d$;
  if cardinality(string_to_array(cuerpo,antes))<>2 then raise exception 'Auditoría: ancla no única'; end if;
  execute replace(cuerpo,antes,despues);
end;
$cambio$;

comment on function private.rentabilidad_minimo_alta(text,numeric) is
  'Mínimo del alta: 0.01 para nuevo y upgrade; renovación conserva la base heredada. Solo uso interno. No autoriza rebajar tasas de contratos existentes. El modo observación conserva su comportamiento libre con límites.';

notify pgrst, 'reload schema';
commit;
