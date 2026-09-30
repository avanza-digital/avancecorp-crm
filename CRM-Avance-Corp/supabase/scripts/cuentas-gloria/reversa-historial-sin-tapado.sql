-- REVERSA de 20260926200757_crm_historial_cuentas_sin_tapado: repone EXACTAMENTE el núcleo de
-- 20260926193424 (con tapado por rol). Huella esperada al terminar: 22019f9bee83548f756ef3de03157b1a.
begin;
set local lock_timeout = '5s';
-- Solo revierte si lo vivo es EXACTAMENTE la F2b (revisión Codex): nunca pisa un cambio posterior.
do $pre$
declare v_firma text;
begin
  -- Firma completa de las dos funciones: cuerpo, SECURITY, search_path y comentario.
  select pg_catalog.string_agg(p.proname || '|' || pg_catalog.md5(p.prosrc) || '|' || p.prosecdef
           || '|' || pg_catalog.array_to_string(p.proconfig, ',') || '|'
           || pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')), ';' order by p.proname)
    into v_firma
  from pg_catalog.pg_proc p
  where p.oid in (to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)'),
                  to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)'));
  if v_firma is distinct from 'historial_cuentas_cliente_autorizado|0806cc1937c1c5899362f69dd829a60a|true|search_path=""|d045e26924bee3f91c1da8346202e0a9;historial_cuentas_cliente_fn|83f7b235db051264bd6672450248912e|false|search_path=""|8b9d112bd3a199efe9fe268f80fddd3a' then
    raise exception 'REVERSA: las funciones vivas no son exactamente la F2b (20260926200757); no se toca';
  end if;
end;
$pre$;
create or replace function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz, desactivada_en timestamptz, desactivada_por_nombre text
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_completo boolean;
begin
  if p_cliente_id is null
     or not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  v_completo := coalesce((select public.es_admin()), false);

  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta,
         -- El N° admite de 1 a 30 caracteres: se muestran como mucho 4 y nunca más de la
         -- mitad, para que un número corto no salga entero (revisión Codex R2).
         case when v_completo then cb.numero_cuenta
              else '••••' || pg_catalog.right(cb.numero_cuenta,
                     least(4, pg_catalog.length(cb.numero_cuenta) / 2)) end,
         case when v_completo then cb.cci
              else '••••' || pg_catalog.right(cb.cci, 4) end,
         cb.titular_distinto,
         case when v_completo then cb.beneficiario_nombre end,
         case when v_completo then cb.beneficiario_dni end,
         cb.origen,
         cb.creado_en, cb.desactivada_en, pr.nombre_completo
  from crm.cuentas_bancarias cb
  -- Solo se resuelve el nombre de personal (nunca el de un cliente) bajo DEFINER.
  left join public.perfiles pr on pr.id = cb.desactivada_por and pr.rol <> 'cliente'
  where cb.cliente_id = p_cliente_id
    and cb.activa is false
  order by cb.desactivada_en desc nulls last, cb.creado_en desc, cb.id desc;
end;
$function$;

comment on function private.historial_cuentas_cliente_autorizado(uuid) is
  'Cuentas bancarias RETIRADAS (activa = false) del cliente, con fecha y nombre de quien las retiró. Autoriza con private.puede_gestionar_cuentas_cliente; 42501 si no. SECURITY DEFINER porque authenticated no tiene grants sobre crm.cuentas_bancarias. DATOS SENSIBLES: N° de cuenta, CCI y beneficiario (nombre y DNI) salen completos solo para public.es_admin(); al resto, N° y CCI tapados y beneficiario NULL.';
comment on function crm.historial_cuentas_cliente_fn(uuid) is
  'Puerta de pantalla (INVOKER) del historial de cuentas retiradas del cliente; delega en private.historial_cuentas_cliente_autorizado. La usa la ventana «Cuentas» del panel admin del portal. DATOS SENSIBLES: el núcleo los tapa para quien no es admin/superadmin.';
do $chk$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = 'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure)
     is distinct from '22019f9bee83548f756ef3de03157b1a' then
    raise exception 'REVERSA: la huella repuesta no es la de 20260926193424';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;
