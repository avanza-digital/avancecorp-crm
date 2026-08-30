-- REAPERTURA de las tres cuentas de prueba del CRM (avancecorp26+crm-*).
--
-- El 2026-08-30 se cerraron las cuatro membresías revocadas: perfil del Portal
-- apagado, sesiones cerradas, llaves de renovación anuladas y entrada bloqueada.
-- Las tres cuentas de prueba son de Miguel; esto las devuelve a la vida SIN
-- devolverles la membresía del CRM (esa sigue revocada a propósito).
--
-- ⚠️ NO sirve para IVETT TEEVIN: esa baja es real y no se revierte con un guion.
--
-- Uso:  supabase db query --linked --file supabase/scripts/reabrir-cuentas-demo-crm.sql
begin;
set local lock_timeout = '5s';

do $$
declare
  v_ids uuid[] := array[
    'd81aca5b-e39e-42d7-b723-1a44930145b8',  -- GERENTE CRM (DEMO)
    '0c7ffc92-260a-4f87-b2fe-a732740c8d17',  -- ANALISTA CRM (DEMO)
    '3a4f3c2a-271d-478c-8625-16225e932c46'   -- SUPERVISOR CRM (DEMO)
  ];
  v_id uuid; v_correo text;
begin
  foreach v_id in array v_ids loop
    select p.correo into v_correo from public.perfiles p where p.id = v_id;
    if v_correo is null or v_correo not like 'avancecorp26+crm-%' then
      raise exception 'Este guion SOLO abre cuentas de prueba: % no lo es (%).', v_id, coalesce(v_correo, '(no existe)');
    end if;
  end loop;

  update public.perfiles set activo = true where id = any(v_ids);
  update auth.users set banned_until = null where id = any(v_ids);
end $$;

commit;

select p.nombre_completo, p.correo, p.activo, u.banned_until is null as puede_entrar
  from public.perfiles p left join auth.users u on u.id = p.id
 where p.correo like 'avancecorp26+crm-%'
 order by p.nombre_completo;
