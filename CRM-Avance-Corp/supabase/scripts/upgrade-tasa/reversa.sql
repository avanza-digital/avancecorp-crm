-- Solo antes del primer uso de tasas inferiores en upgrades con enforcement.
-- No borra contratos ni cambia la política publicada.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Esperar primero cualquier alta/corrección en curso. Bloquear solo el libro
-- dejaría un trigger ya evaluado esperando para insertar después de la reversa.
lock table public.contratos in share mode;
lock table crm.ledger_rentabilidad in share mode;
do $preflight$
declare f record;
begin
  if exists(select 1 from crm.ledger_rentabilidad where categoria='upgrade'
    and origen='enforcement' and regla='heredada_upgrade' and tasa_final<tasa_base) then
    raise exception 'Ya existen upgrades con tasa inferior: conservar la migración y corregir hacia adelante';
  end if;
  for f in select * from (values
    ('private.rentabilidad_minimo_alta(text,numeric)','6f213fb1e36f7ff52fb4b2f7a5d373f8'),
    ('private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid)','6b6ee230b34f65ee2b29eb2074ad6201'),
    ('private.trg_contratos_observar_rentabilidad()','7b73812963a1339d88e375f124c042b9')
  ) esperado(firma,huella) loop
    if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid=to_regprocedure(f.firma)) is distinct from f.huella then
      raise exception 'Reversa upgrade: % cambió; revisar antes de aplicar',f.firma;
    end if;
  end loop;
end;
$preflight$;

do $reversa$
declare cuerpo text;
begin
  cuerpo:=pg_get_functiondef('private.rentabilidad_minimo_alta(text,numeric)'::regprocedure);
  execute replace(cuerpo,$a$p_categoria in ('nuevo','upgrade')$a$,$d$p_categoria='nuevo'$d$);

  cuerpo:=pg_get_functiondef('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)'::regprocedure);
  execute replace(cuerpo,
    $a$'tasa_minima_sin_autorizacion', case when p_categoria='upgrade' then v_base else private.rentabilidad_minimo_alta(p_categoria, v_base) end,
    'tasa_minima_upgrade_sin_autorizacion', case when p_categoria='upgrade' then private.rentabilidad_minimo_alta(p_categoria, v_base) else null end,$a$,
    $d$'tasa_minima_sin_autorizacion', private.rentabilidad_minimo_alta(p_categoria, v_base),$d$);

  cuerpo:=pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure);
  cuerpo:=replace(cuerpo,$a$        v_c.categoria in ('nuevo','upgrade')
        and v_c.tasa_anual >= private.rentabilidad_minimo_alta(v_c.categoria,v_base)
        and (tg_op='INSERT' or (tg_op='UPDATE'
          and old.categoria=v_c.categoria and old.es_demo is not true$a$,
    $d$        v_c.categoria='nuevo'
        and v_c.tasa_anual >= private.rentabilidad_minimo_alta(v_c.categoria,v_base)
        and (tg_op='INSERT' or (tg_op='UPDATE'
          and old.categoria='nuevo' and old.es_demo is not true$d$);
  cuerpo:=replace(cuerpo,$a$-- Alta nueva y upgrade admiten una tasa menor. Una corrección solo$a$,
    $d$-- D4 revisada: el alta nueva admite una tasa menor. Una corrección solo$d$);
  execute replace(cuerpo,
    $a$'tasa_inferior_sin_excepcion', case when v_c.categoria in ('nuevo','upgrade') and v_c.tasa_anual<v_base then true end$a$,
    $d$'tasa_inferior_sin_excepcion', case when v_c.categoria='nuevo' and v_c.tasa_anual<v_base then true end$d$);
end;
$reversa$;
comment on function private.rentabilidad_minimo_alta(text,numeric) is
  'Mínimo de una nueva alta: 0.01 para categoría nuevo; renovaciones y upgrades conservan la base heredada. Solo uso interno. No autoriza correcciones de tasa de contratos existentes.';
notify pgrst, 'reload schema';
commit;
