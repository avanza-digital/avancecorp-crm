-- Reversa de 20261017211313_crm_reemplazar_inversion_vista_previa.sql. Devuelve private.reemplazar_inversion_avance a su
-- cuerpo de la Fase 1 (huella 541ce30ffcc213adaebc036dda48a6a2: la regla vuelve a ir dentro del núcleo) y retira la vista
-- previa y sus tres ayudantes. No toca datos. Falla cerrado si el núcleo no tiene la huella que dejó la migración.
-- Aplicar en UN mensaje (`supabase db query --linked --file`), como la migración.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if md5(pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure))
       is distinct from 'b6af7422802edc85ced40d6b9cc26e49' then
    raise exception 'REVERSA vista_previa: el núcleo no tiene la huella que dejó la migración';
  end if;
end
$preflight$;

-- El núcleo vuelve a llevar la regla dentro (los dos cambios de la migración, al revés).
do $nucleo$
declare
  v_def text := pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure);
  v_cambios text[][] := array[
    array['  -- El día de registro de la VENTA (la cadena de copias o el registro del propio contrato): private.reemplazo_dia_
  -- registro_venta, la MISMA que usa la vista previa (20261017211313). Vale para los dos modos.
  v_dia_registro := private.reemplazo_dia_registro_venta(p_fuente);
',
          '  -- El día de registro de la VENTA: si el original ya era el resultado de un reemplazo, el de la venta que reemplazó (la
  -- cadena lo guarda en la copia); si no, el de su propio registro (Codex r1, P1). Vale para los dos modos.
  v_dia_registro := coalesce(
    (select (ie.snapshot #>> ''{reemplazo,dia_registro_venta}'')::date from crm.inversiones_eliminadas ie
      where ie.reemplazada_por = p_fuente order by ie.es_conversion desc, ie.eliminado_en desc, ie.id desc limit 1),
    (v_orig.creado_en at time zone ''America/Lima'')::date);
'],
    array['  -- La regla vive en private.reemplazo_fecha_comercial, la MISMA que usa la vista previa (20261017211313).
  select f.fecha_comercial, f.fuente_cierre_comercial into v_fecha_cc, v_fuente_cc
    from private.reemplazo_fecha_comercial(p_fuente, v_fi) f;
',
          '  if v_orig.fuente_cierre_comercial in (''registro'', ''fecha_inicio_inferida'') then
    v_fecha_cc := least(v_fi, v_dia_registro);
    v_fuente_cc := case when v_fi < v_dia_registro then ''fecha_inicio_inferida'' else ''registro'' end;
  else
    v_fecha_cc := v_orig.fecha_cierre_comercial;
    v_fuente_cc := v_orig.fuente_cierre_comercial;
  end if;
'],
    array['  -- La regla vive en private.contrato_tiene_cuotas_pagadas, la MISMA que avisa la vista previa (20261017211313).
  if private.contrato_tiene_cuotas_pagadas(p_fuente) then
',
          '  if exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = p_fuente
             and (cp.estado in (''pagado'', ''trasladado'') or cp.monto_pagado is not null)) then
']
  ];
  i int;
begin
  for i in 1 .. array_length(v_cambios, 1) loop
    if (length(v_def) - length(replace(v_def, v_cambios[i][1], ''))) / length(v_cambios[i][1]) <> 1 then
      raise exception 'REVERSA vista_previa: el ancla % no aparece exactamente una vez', i;
    end if;
    v_def := replace(v_def, v_cambios[i][1], v_cambios[i][2]);
  end loop;
  execute v_def;
end
$nucleo$;

-- Nadie más usa estas piezas (un cuerpo plpgsql/sql no deja rastro en pg_depend: auditor-rls, P3-5).
-- PL/pgSQL no deja en pg_depend a quién llama: se busca el nombre en el cuerpo, sin mayúsculas ni comillas (como el
-- censo F7), porque `PRIVATE.CONTRATO_TIENE_CUOTAS_PAGADAS(p)` o `"private"."…"` llaman al mismo ayudante. Una llamada
-- armada con EXECUTE y texto concatenado no se ve: antes de revertir, revisar a mano si alguna función arma SQL dinámico.
-- Lo que sí deja dependencia (SQL con BEGIN ATOMIC, vistas) lo frena el propio DROP de abajo.
do $nadie$
begin
  if exists (select 1 from pg_catalog.pg_proc p
             cross join lateral (select pg_catalog.lower(pg_catalog.replace(p.prosrc, '"', '')) as cuerpo) n
             where p.oid not in ('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure,
                                 'private.reemplazo_fecha_comercial(uuid,date)'::regprocedure,
                                 'private.reemplazo_dia_registro_venta(uuid)'::regprocedure,
                                 'private.contrato_tiene_cuotas_pagadas(uuid)'::regprocedure)
               and (position('reemplazo_dia_registro_venta' in n.cuerpo) > 0
                    or position('contrato_tiene_cuotas_pagadas' in n.cuerpo) > 0
                    or position('reemplazo_fecha_comercial' in n.cuerpo) > 0
                    or position('reemplazar_inversion_vista_previa_fn' in n.cuerpo) > 0)) then
    raise exception 'REVERSA vista_previa: otra función usa la vista previa o sus ayudantes; revisa antes de retirarlos';
  end if;
end
$nadie$;

drop function crm.reemplazar_inversion_vista_previa_fn(uuid, date, uuid);
drop function private.reemplazo_fecha_comercial(uuid, date);
drop function private.reemplazo_dia_registro_venta(uuid);
drop function private.contrato_tiene_cuotas_pagadas(uuid);

do $postflight$
begin
  if md5(pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure))
       is distinct from '541ce30ffcc213adaebc036dda48a6a2' then
    raise exception 'REVERSA vista_previa: el núcleo no volvió a su huella de la Fase 1';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure
                   and p.proowner = 'postgres'::regrole and not p.prosecdef and p.provolatile = 'v'
                   and p.proconfig = array['search_path=""'] and p.proacl = '{postgres=X/postgres}'::aclitem[]) then
    raise exception 'REVERSA vista_previa: dueño, seguridad, configuración o permisos del núcleo';
  end if;
  if to_regprocedure('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)') is not null
     or to_regprocedure('private.reemplazo_fecha_comercial(uuid,date)') is not null
     or to_regprocedure('private.reemplazo_dia_registro_venta(uuid)') is not null
     or to_regprocedure('private.contrato_tiene_cuotas_pagadas(uuid)') is not null then
    raise exception 'REVERSA vista_previa: quedan objetos de la migración';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
