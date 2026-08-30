-- CARLOS VALLES: Directorio -> Gerencia (2026-08-29, a pedido de Miguel).
--
-- Por que hace falta un script y no basta la pantalla de Usuarios:
--   El candado del 28/08 (Fase 1) amarra las dos identidades — quien es
--   Directorio en el Portal solo puede ser Directorio en el CRM. Cambiar el
--   par exige bajar la membresia, mover el rol de Portal (que NO tiene UI) y
--   volver a subirla. Los tres candados estructurales siguen ACTIVOS: si algo
--   no cuadra, la transaccion entera aborta y Carlos no queda a medias.
--
-- Por que 'admin' y no 'comercial' en el Portal:
--   es_admin() es lo que piden cerrar_contrato, actualizar_contrato, los
--   productos de inversion y es_gestor_cartera. Con 'comercial' Carlos seria
--   una Gerencia capada. Ademas conserva el tablero de Directorio del Portal
--   (ese gate acepta es_directorio() OR es_admin()) y NO recibe superadmin:
--   la llave que asigna roles CRM sigue siendo de una sola persona.
--
-- Efecto colateral conocido: bajar la membresia rota el token de agenda ICS
-- de Carlos (trigger de offboarding). Si tenia el calendario suscrito, hay que
-- volver a copiar el enlace desde Configuracion.
--
-- Ejecutar con:
--   npx supabase db query --linked --file supabase/scripts/carlos-valles-directorio-a-gerencia.sql

do $cuerpo$
declare
  v_carlos uuid;
  v_actor  uuid;
  v_rol_portal text;
  v_rol_crm text;
  v_activo boolean;
  v_pendientes int;
begin
  select p.id, p.rol into v_carlos, v_rol_portal
  from public.perfiles p
  where p.nombre_completo = 'CARLOS VALLES' and p.activo is true;
  if v_carlos is null then raise exception 'No se encontro a CARLOS VALLES activo'; end if;

  select p.id into v_actor from public.perfiles p where p.rol = 'superadmin' and p.activo is true limit 1;
  if v_actor is null then raise exception 'No hay superadmin activo para firmar el evento'; end if;

  select e.rol_crm, e.activo into v_rol_crm, v_activo from crm.equipo e where e.perfil_id = v_carlos;
  if v_rol_portal <> 'directorio' or v_rol_crm <> 'directorio' then
    raise exception 'Estado inesperado: portal=% crm=%', v_rol_portal, v_rol_crm;
  end if;

  -- Nada colgando de el: sin esto, cambiar de rol dejaria trabajo huerfano.
  select (select count(*) from crm.equipo e2 where e2.supervisor_id = v_carlos and e2.activo)
       + (select count(*) from crm.leads l where l.vendedor_id = v_carlos)
       + (select count(*) from public.contratos c where c.analista_cierre_id = v_carlos)
       + (select count(*) from public.perfiles p2 where p2.asesor_perfil_id = v_carlos)
    into v_pendientes;
  if v_pendientes <> 0 then raise exception 'Carlos tiene % responsabilidades colgando', v_pendientes; end if;

  -- 1) La membresia baja: es la unica ventana en que el par puede cambiar.
  update crm.equipo set activo = false where perfil_id = v_carlos;
  insert into crm.usuario_eventos (actor_id, objetivo_id, accion, detalle, idempotencia)
  values (v_actor, v_carlos, 'membresia_desactivada',
    jsonb_build_object('motivo', 'paso 1 de 3 del cambio Directorio->Gerencia',
                       'via', 'consola SQL a pedido de Gerencia'),
    gen_random_uuid());

  -- 2) Identidad de Portal: directorio -> admin
  update public.perfiles set rol = 'admin' where id = v_carlos;

  -- 3) Rol CRM: directorio -> gerencia (Gerencia no admite supervisor)
  update crm.equipo set rol_crm = 'gerencia', supervisor_id = null where perfil_id = v_carlos;
  insert into crm.usuario_eventos (actor_id, objetivo_id, accion, detalle, idempotencia)
  values (v_actor, v_carlos, 'rol_cambiado',
    jsonb_build_object('rol_anterior', 'directorio', 'rol_nuevo', 'gerencia',
                       'rol_portal_anterior', 'directorio', 'rol_portal_nuevo', 'admin',
                       'via', 'consola SQL a pedido de Gerencia'),
    gen_random_uuid());

  -- 4) La membresia vuelve a subir, ya con el par valido
  update crm.equipo set activo = true where perfil_id = v_carlos;
  insert into crm.usuario_eventos (actor_id, objetivo_id, accion, detalle, idempotencia)
  values (v_actor, v_carlos, 'membresia_activada',
    jsonb_build_object('motivo', 'paso 3 de 3 del cambio Directorio->Gerencia',
                       'via', 'consola SQL a pedido de Gerencia'),
    gen_random_uuid());

  raise notice 'CARLOS VALLES: Portal admin + CRM gerencia, membresia activa';
end;
$cuerpo$;
