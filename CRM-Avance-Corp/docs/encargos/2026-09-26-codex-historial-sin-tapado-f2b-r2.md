ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo R2 (última): F2b — corrección de tu P1 sobre la reversa

En la R1 diste BLOCK: «la reversa hace CREATE OR REPLACE sin exigir antes la huella F2b; podría pisar
un cambio posterior». ACEPTADO. Ahora la reversa empieza con un DO que exige md5(prosrc) =
'0806cc1937c1c5899362f69dd829a60a' (F2b) y aborta si difiere; mantiene el chequeo final
(22019f9b… = F2). Además, por consistencia, la reversa de la F2 (drop de las dos funciones) exige
ahora que lo vivo sea la F2 (22019f9b…), para que no se pueda saltar el orden.

Evidencia (banco Docker): con la F2 viva, la reversa de F2b se NIEGA y la huella sigue 22019f9b…;
con la F2b viva, la reversa de F2 se NIEGA («revierte antes la F2b»); orden correcto
(F2b→F2) deja el catálogo idéntico al original. Prueba del historial: HISTORIAL_OK con 3 mutantes.
La migración 20260926200757 NO cambió desde la R1 (ya dijiste que conserva firma, gate, filtro, ACL).

REFUTA: ¿queda algún camino en que las reversas pisen o dejen estado incoherente?

## Reversa F2b (íntegra)
```sql
-- REVERSA de 20260926200757_crm_historial_cuentas_sin_tapado: repone EXACTAMENTE el núcleo de
-- 20260926193424 (con tapado por rol). Huella esperada al terminar: 22019f9bee83548f756ef3de03157b1a.
begin;
set local lock_timeout = '5s';
-- Solo revierte si lo vivo es EXACTAMENTE la F2b (revisión Codex): nunca pisa un cambio posterior.
do $pre$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)'))
     is distinct from '0806cc1937c1c5899362f69dd829a60a' then
    raise exception 'REVERSA: el núcleo vivo no es la versión F2b (20260926200757); no se toca';
  end if;
end $pre$;
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
```
## Reversa F2 (íntegra)
```sql
-- REVERSA de 20260926193424_crm_historial_cuentas_cliente.
-- Borra SOLO las dos funciones nuevas (lectura; ninguna otra función, vista ni política las
-- usa). No toca datos. Se niega si algo del catálogo depende de ellas.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  -- Solo si lo vivo es EXACTAMENTE la F2 (si la F2b está aplicada, revertir primero la F2b).
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)'))
     is distinct from '22019f9bee83548f756ef3de03157b1a' then
    raise exception 'REVERSA: el núcleo vivo no es la versión de 20260926193424; revierte antes la F2b';
  end if;
  if exists (
    select 1 from pg_catalog.pg_depend d
    where d.refobjid in (
      coalesce(to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)')::oid, 0),
      coalesce(to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)')::oid, 0))
      and d.deptype = 'n'
  ) then
    raise exception 'REVERSA: hay objetos que dependen del historial; revisar antes de borrar';
  end if;
end $chk$;
drop function if exists crm.historial_cuentas_cliente_fn(uuid);
drop function if exists private.historial_cuentas_cliente_autorizado(uuid);
notify pgrst, 'reload schema';
commit;
```
