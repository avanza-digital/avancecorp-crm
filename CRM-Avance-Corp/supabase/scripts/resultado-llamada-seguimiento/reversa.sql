-- Solo tras volver al frontend anterior. No borra llamadas, tareas ni historial v4.
-- El gate F2 original se restaura literalmente; v3 y su nucleo nunca cambiaron.
begin;
set local lock_timeout = '5s';
do $preflight$
begin
  perform private.assert_gestion_diaria_resultado_v4();
  if md5(pg_get_functiondef('private.assert_gestion_diaria_resultado()'::regprocedure)) <> '2c7eccd6443a2eb78eefc8e0c196da15' then
    raise exception 'El gate F2 cambio: revisar antes de revertir v4';
  end if;
end;
$preflight$;
CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_resultado()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_firma text;
  v_md5 text;
  v_id oid;
begin
  -- 1. Puertas: DEFINER, volátiles, search_path vacío, owner postgres, EXECUTE
  --    exactamente para authenticated.
  foreach v_firma in array array[
    'crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',
    'crm.deshacer_resultado_llamada(uuid)'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 'v'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato del resultado de llamada alterado (debe ser DEFINER, volatile, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL del resultado de llamada alterada: %', v_firma;
    end if;
  end loop;

  -- 2. Núcleo y función del trigger: DEFINER, search_path vacío, owner postgres,
  --    SIN EXECUTE para nadie salvo postgres.
  foreach v_firma in array array[
    'private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',
    'private.trg_actividades_resultado_solo_nucleo()'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Nucleo del resultado de llamada alterado (debe ser DEFINER, search_path vacio): %', v_firma;
    end if;
    if exists (
      select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = v_id and a.grantee <> 'postgres'::regrole::oid
    ) then
      raise exception 'El nucleo del resultado de llamada tiene EXECUTE fuera de postgres: %', v_firma;
    end if;
  end loop;

  -- 3. El CHECK de forma, VALIDADO y con el catálogo completo.
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'crm.actividades'::regclass
      and c.conname = 'actividades_resultado_llamada_forma'
      and c.contype = 'c' and c.convalidated
      and strpos(pg_get_constraintdef(c.oid), 'no_contesto') > 0
      and strpos(pg_get_constraintdef(c.oid), 'volver_a_llamar') > 0
      and strpos(pg_get_constraintdef(c.oid), 'agendo_reunion') > 0
      and strpos(pg_get_constraintdef(c.oid), 'no_interesado') > 0
      and strpos(pg_get_constraintdef(c.oid), 'numero_errado') > 0
      and strpos(pg_get_constraintdef(c.oid), 'no_es_la_persona') > 0
      and strpos(pg_get_constraintdef(c.oid), 'pide_otro_producto') > 0
      and strpos(pg_get_constraintdef(c.oid), 'submotivo') > 0
      -- La DEFINICIÓN COMPLETA, sellada: un octavo valor conservaría todos los
      -- LIKE de arriba y pasaría (Codex, 19/09). Huella medida en el banco.
      and md5(pg_get_constraintdef(c.oid)) = 'ec46b200b9181592b0f48af06009c4c7'
  ) then
    raise exception 'Falta o cambio el CHECK actividades_resultado_llamada_forma (o no esta validado)';
  end if;

  -- 4. El trigger que veta la falsificación: presente, habilitado, BEFORE
  --    INSERT OR UPDATE OF metadata, con su función.
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_00_actividades_resultado_solo_nucleo'
      and t.tgenabled in ('O', 'A')
      and t.tgfoid = to_regprocedure('private.trg_actividades_resultado_solo_nucleo()')
      and pg_get_triggerdef(t.oid) like '%BEFORE INSERT OR UPDATE OF metadata ON crm.actividades FOR EACH ROW%'
  ) then
    raise exception 'Falta, esta deshabilitado o cambio el trigger trg_00_actividades_resultado_solo_nucleo';
  end if;

  -- 5. Los CUERPOS, sellados: los propios (medidos en el banco, dos pasadas) y
  --    los de TODO lo que la v3 compone (texto vivo de producción el 19/09/2026).
  --    Un `create or replace` sobre cualquiera exige re-sellar aquí a conciencia.
  for v_firma, v_md5 in select * from (values
    ('private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'fec6bfd18b0ca26623f84b55daddef64'),
    ('crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',        '92d2dcfb4cc03c158a42292980226ba2'),
    ('crm.deshacer_resultado_llamada(uuid)',                                                  '5869117e03ac55d699d248244a71bb31'),
    ('private.trg_actividades_resultado_solo_nucleo()',                                       '19952736370f64026f747c19b54ab38e'),
    ('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)',                       '805b3489aeab94371328f28229f23fe5'),
    ('crm.registrar_actividad_v2(uuid,uuid,text,text,jsonb)',                                 '52a44ac20288a9283801a28047efba18'),
    ('crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text)',                         'f5147d689ec8a213ec9320dad322de4b'),
    ('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)',                                 '5396719dc3133e3e658c59c9f63b3530'),
    ('private.sla_ejecutar_comando(uuid,text,uuid,jsonb)',                                    '9f8f1100df419f8d7d70bf4d845adc0d'),
    ('crm.reabrir_lead_fn(uuid)',                                                             '9cdac9e10f2efde549bbcbdf810b95d3'),
    ('crm.marcar_no_contactar(uuid,text)',                                                    '697e0c59f73377b30e7f13340686061c'),
    ('private.trg_gestion_lead_serializada()',                                                '7af0e66b8a4849566e43b514245e1b86'),
    ('private.trg_leads_sync_tareas()',                                                       '6874c23294da0027f25475b4e1fc49d7'),
    ('private.trg_sla_recibo_guard()',                                                        '903e9260918bc7e100bde650d46c1ee4'),
    ('private.trg_leads_cambio_etapa()',                                                      '5e457384188efa3f32cf728d4bc3b2a9'),
    ('private.trg_leads_zz_sello_descarte()',                                                 '150d7ae56bb2094733f7620a1362c29e')
  ) as m(firma, md5) loop
    if to_regprocedure(v_firma) is null
       or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
      raise exception 'El cuerpo de % cambio: re-sellar el resultado de llamada de Gestion Diaria (md5 %)',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;

  -- 6. El núcleo del historial sigue INVOKER, estable, search_path vacío, con
  --    EXECUTE para authenticated, y entrega metadata.
  v_id := to_regprocedure('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)');
  if not exists (
    select 1 from pg_proc p
    where p.oid = v_id and not p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
      and strpos(p.prosrc, 'jsonb_each(pg.metadata) as m(clave, valor)') > 0
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'private.actividades_de_lead_core perdio su forma, su EXECUTE o la metadata del item';
  end if;

  -- 7. Los writers v2 y su mundo, por el gate que ya los sella.
  perform private.assert_sla_comandos();

  return 'OK: resultado de llamada — puertas DEFINER selladas (EXECUTE solo authenticated), nucleo y trigger solo postgres, CHECK de forma validado, trigger anti-falsificacion habilitado, cuerpos propios y compuestos con su md5, historial por lead con metadata';
end;
$function$;

drop function crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean);
drop function private.assert_gestion_diaria_resultado_v4();
drop function private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean);
select private.assert_gestion_diaria();
notify pgrst, 'reload schema';
commit;
