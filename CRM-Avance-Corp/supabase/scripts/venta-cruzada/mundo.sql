-- Venta cruzada · mundo sintético del banco. Se CONFIRMA (commit): lo reutilizan las
-- pruebas de todas las fases, que corren encima en transacciones que se deshacen.
-- NUNCA en producción (la guarda lo impide). Idempotente: si el mundo ya existe, no
-- recrea nada y solo lo verifica.
-- Uso: psql -h 127.0.0.1 -p 53322 -U postgres -d postgres -v ON_ERROR_STOP=1 \
--        -f supabase/scripts/venta-cruzada/mundo.sql
--
-- Equipo (auth.users + perfiles + crm.equipo), ids c0000000-0000-4000-8000-0000000000NN:
--   01 G   gerencia        02 S1 supervisor      03 S2 supervisor
--   04 A   vendedor (S1)   05 A2 vendedor (S1)   06 B  vendedor (S2)   07 C vendedor (S2)
--   08 D   vendedor (S1), INACTIVO               09 DIR directorio     0a CO coordinador
-- Personas (una por rama de las reglas de autorización y contexto):
--   X  cliente Avance normal, responsable A              (perfil c...21, DNI 70000021)
--   Q  cliente con perfil inactivo, responsable A        (perfil c...22, DNI 70000022)
--   R  cliente cuyo responsable es D, inactivo           (perfil c...23, DNI 70000023)
--   Z  persona sin responsable                           (DNI 70000024)
--   W  cliente con «No insistir», responsable A          (perfil c...25, DNI 70000025)
--   V  identidad fusionada en X                          (DNI 70000026)
--   T  persona con lead canónico ABIERTO de A            (DNI 70000027)
--   U  persona con documento SIN verificar, resp. A      (DNI 70000028)
--   Y  persona sin antecedente de nombre, resp. A        (DNI 70000029)
-- Leads: el de T y seis abiertos sin DNI (dos de A, uno de A2, B y C, y uno de S1 sin
-- vendedor) para la prueba de conversión existente.
begin;

do $guarda$ begin
  if (select count(*) from crm.leads) > 200 or (select count(*) from public.perfiles where rol = 'cliente') > 50 then
    raise exception 'El mundo de venta cruzada solo se siembra en el banco sintético';
  end if;
end $guarda$;

do $mundo$
declare
  e record;
  v_t uuid; v_u uuid; v_y uuid; v_z uuid; v_v uuid;
  v_x uuid; v_q uuid; v_r uuid; v_w uuid;
begin
  if exists (select 1 from public.perfiles where id = 'c0000000-0000-4000-8000-000000000001') then
    return; -- ya sembrado
  end if;

  -- Equipo --------------------------------------------------------------------
  for e in select * from (values
    ('c0000000-0000-4000-8000-000000000001','vc.g','VC GERENCIA','admin','gerencia',null::text,true,'71000001'),
    ('c0000000-0000-4000-8000-000000000002','vc.s1','VC SUPERVISOR UNO','analista','supervisor','c0000000-0000-4000-8000-000000000001',true,'71000002'),
    ('c0000000-0000-4000-8000-000000000003','vc.s2','VC SUPERVISOR DOS','analista','supervisor','c0000000-0000-4000-8000-000000000001',true,'71000003'),
    ('c0000000-0000-4000-8000-000000000004','vc.a','VC ANALISTA A','analista','vendedor','c0000000-0000-4000-8000-000000000002',true,'71000004'),
    ('c0000000-0000-4000-8000-000000000005','vc.a2','VC ANALISTA A DOS','analista','vendedor','c0000000-0000-4000-8000-000000000002',true,'71000005'),
    ('c0000000-0000-4000-8000-000000000006','vc.b','VC ANALISTA B','analista','vendedor','c0000000-0000-4000-8000-000000000003',true,'71000006'),
    ('c0000000-0000-4000-8000-000000000007','vc.c','VC ANALISTA C','analista','vendedor','c0000000-0000-4000-8000-000000000003',true,'71000007'),
    ('c0000000-0000-4000-8000-000000000008','vc.d','VC ANALISTA D','analista','vendedor','c0000000-0000-4000-8000-000000000002',true,'71000008'),
    ('c0000000-0000-4000-8000-000000000009','vc.dir','VC DIRECTORIO','directorio','directorio',null,true,'71000009'),
    ('c0000000-0000-4000-8000-00000000000a','vc.co','VC COORDINACION','analista','coordinador',null,true,'71000010')
  ) t(id, correo, nombre, rol, rol_crm, supervisor, activo, dni)
  loop
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change,
      raw_app_meta_data, raw_user_meta_data)
    values (e.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      e.correo || '@avancecorp.test', '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}');
    insert into public.perfiles (id, nombre_completo, correo, rol, activo, tipo_documento, dni,
      debe_cambiar_password, titular_distinto, titular_distinto_usd, telefono)
    values (e.id::uuid, e.nombre, e.correo || '@avancecorp.test', e.rol, true, 'DNI', e.dni,
      false, false, false, '9' || right(e.dni, 8));
    insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
    values (e.id::uuid, e.rol_crm, e.supervisor::uuid, true);
  end loop;

  -- Clientes con perfil: la identidad nace como en producción ------------------
  for e in select * from (values
    ('c0000000-0000-4000-8000-000000000021','vc.x','VC CLIENTE X','70000021','c0000000-0000-4000-8000-000000000004'),
    ('c0000000-0000-4000-8000-000000000022','vc.q','VC CLIENTE Q','70000022','c0000000-0000-4000-8000-000000000004'),
    ('c0000000-0000-4000-8000-000000000023','vc.r','VC CLIENTE R','70000023','c0000000-0000-4000-8000-000000000008'),
    ('c0000000-0000-4000-8000-000000000025','vc.w','VC CLIENTE W','70000025','c0000000-0000-4000-8000-000000000004')
  ) t(id, correo, nombre, dni, asesor)
  loop
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change,
      raw_app_meta_data, raw_user_meta_data)
    values (e.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      e.correo || '@avancecorp.test', '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}');
    insert into public.perfiles (id, nombre_completo, correo, rol, activo, tipo_documento, dni, asesor_perfil_id,
      debe_cambiar_password, titular_distinto, titular_distinto_usd, telefono)
    values (e.id::uuid, e.nombre, e.correo || '@avancecorp.test', 'cliente', true, 'DNI', e.dni, e.asesor::uuid,
      false, false, false, '987' || right(e.dni, 6));
    perform private.asegurar_identidad_perfil(e.id::uuid, 'vc_mundo');
  end loop;
  select id into v_x from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000021';
  select id into v_q from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000022';
  select id into v_r from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000023';
  select id into v_w from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000025';

  -- Q: su perfil queda inactivo. W: «No insistir». R: su responsable D deja el equipo.
  update public.perfiles set activo = false where id = 'c0000000-0000-4000-8000-000000000022';
  update crm.inversionistas set no_contactar = true, no_contactar_en = now(),
    no_contactar_por = 'c0000000-0000-4000-8000-000000000001' where id = v_w;
  -- (D deja el equipo más abajo, fuera de este bloque.)

  -- Personas sin perfil --------------------------------------------------------
  v_z := private.inversionista_resolver('DNI', '70000024', true, 'vc_mundo');
  v_v := private.inversionista_resolver('DNI', '70000026', true, 'vc_mundo');
  v_t := private.inversionista_resolver('DNI', '70000027', true, 'vc_mundo');
  v_y := private.inversionista_resolver('DNI', '70000029', true, 'vc_mundo');
  insert into crm.inversionistas (estado) values ('activo') returning id into v_u;
  insert into crm.inversionista_identificadores (inversionista_id, tipo_documento, documento_normalizado,
    documento_original, estado, verificado, fuente)
  values (v_u, 'DNI', '70000028', '70000028', 'vigente', false, 'vc_mundo');
  for e in select unnest(array[v_t, v_u, v_y]) as id loop
    insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo, por)
    values (e.id, 'c0000000-0000-4000-8000-000000000004', 'vc_mundo', 'c0000000-0000-4000-8000-000000000001');
    update crm.inversionistas set responsable_relacion_id = 'c0000000-0000-4000-8000-000000000004' where id = e.id;
  end loop;
  -- V se fusiona en X.
  update crm.inversionistas set estado = 'fusionado', inversionista_canonico_id = v_x, fusionado_en = now()
   where id = v_v;

  -- Leads ------------------------------------------------------------------------
  -- El de T: canónico, abierto (contactado) y de A.
  insert into crm.leads (id, nombre_completo, telefono, monto_estimado, moneda, origen, etapa, vendedor_id, dni, inversionista_id)
  values ('c0000000-0000-4000-8000-000000000071', 'VC PERSONA T', '+51987700027', 5000, 'PEN', 'formulario',
          'contactado', 'c0000000-0000-4000-8000-000000000004', '70000027', v_t);
  -- Seis abiertos sin DNI para la prueba de conversión existente.
  insert into crm.leads (id, nombre_completo, telefono, monto_estimado, moneda, origen, etapa, vendedor_id)
  values
    ('c0000000-0000-4000-8000-000000000081','VC LEAD UNO','+51987800001',1000,'PEN','formulario','nuevo','c0000000-0000-4000-8000-000000000004'),
    ('c0000000-0000-4000-8000-000000000082','VC LEAD DOS','+51987800002',1000,'PEN','formulario','nuevo','c0000000-0000-4000-8000-000000000004'),
    ('c0000000-0000-4000-8000-000000000083','VC LEAD TRES','+51987800003',1000,'PEN','formulario','nuevo','c0000000-0000-4000-8000-000000000005'),
    ('c0000000-0000-4000-8000-000000000084','VC LEAD CUATRO','+51987800004',1000,'PEN','formulario','nuevo','c0000000-0000-4000-8000-000000000006'),
    ('c0000000-0000-4000-8000-000000000085','VC LEAD CINCO','+51987800005',1000,'PEN','formulario','nuevo','c0000000-0000-4000-8000-000000000007'),
    ('c0000000-0000-4000-8000-000000000086','VC LEAD SEIS','+51987800006',1000,'PEN','formulario','contactado','c0000000-0000-4000-8000-000000000004');
end $mundo$;

-- D deja el equipo. En producción el offboarding no deja desactivar a quien
-- conserva cartera (private.validar_equipo_usuario_crm); aquí se fuerza SOLO para
-- ejercitar la rama defensiva «responsable inactivo», sin triggers. Tiene que ser
-- una sentencia suelta: dentro de un bloque el banco no permite este ajuste.
set local session_replication_role = replica;
update crm.equipo set activo = false
 where perfil_id = 'c0000000-0000-4000-8000-000000000008' and activo;
set local session_replication_role = origin;

-- Verificación del mundo (también en una segunda ejecución).
do $verifica$
declare v_n integer;
begin
  select count(*) into v_n from crm.equipo where perfil_id::text like 'c0000000-0000-4000-8000-0000000000%';
  if v_n <> 10 then raise exception 'MUNDO: el equipo debía tener 10 miembros (tiene %)', v_n; end if;
  if (select responsable_relacion_id from crm.inversionistas i join public.perfiles p on p.id = i.perfil_id
      where p.id = 'c0000000-0000-4000-8000-000000000021') is distinct from 'c0000000-0000-4000-8000-000000000004' then
    raise exception 'MUNDO: X debía tener como responsable a A';
  end if;
  if (select private.rol_crm('c0000000-0000-4000-8000-000000000008')) is not null then
    raise exception 'MUNDO: D debía quedar inactivo';
  end if;
  if (select count(*) from crm.leads where id::text like 'c0000000-0000-4000-8000-0000000000%') <> 7 then
    raise exception 'MUNDO: faltan leads';
  end if;
end $verifica$;

commit;
select 'MUNDO_VENTA_CRUZADA_OK' as veredicto,
  (select count(*) from crm.inversionistas) as personas,
  (select count(*) from crm.leads) as leads,
  (select count(*) from crm.equipo) as equipo;
