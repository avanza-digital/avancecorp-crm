-- Solo lectura. Reportes para Operaciones; nunca devuelve números bancarios completos.
-- Ejecutar cada SELECT por separado si la herramienta solo devuelve el último resultado.

-- 1. Mismo CCI con otros datos: normalización igual al backfill S1.
select p.nombre_completo as cliente,p.dni,x.moneda,coalesce(a.nombre_completo,'Sin analista asignado') as analista,
array_remove(array[
case when lower(cb.banco) is distinct from lower(btrim(s.banco)) then 'banco' end,
case when cb.tipo_cuenta is distinct from lower(btrim(s.tipo_cuenta)) then 'tipo_cuenta' end,
case when cb.numero_cuenta is distinct from upper(btrim(s.numero_cuenta)) then 'numero_cuenta' end,
case when cb.titular_distinto is distinct from coalesce(s.titular_distinto,false) then 'titular_distinto' end,
case when cb.beneficiario_nombre is distinct from case when coalesce(s.titular_distinto,false) then upper(regexp_replace(btrim(s.beneficiario_nombre),'\s+',' ','g')) else null end then 'beneficiario_nombre' end,
case when cb.beneficiario_dni is distinct from case when coalesce(s.titular_distinto,false) then btrim(s.beneficiario_dni) else null end then 'beneficiario_dni' end
],null) as campos_discrepantes,
'••••'||right(s.numero_cuenta,4) as cuenta_perfil,'••••'||right(cb.numero_cuenta,4) as cuenta_crm,'••••'||right(cb.cci,4) as cci
from private.conciliacion_cuentas_p0xx x join public.perfiles p on p.id=x.cliente_id left join public.perfiles a on a.id=p.asesor_perfil_id
cross join lateral (values
('PEN',p.banco,p.tipo_cuenta,p.numero_cuenta,p.cci,p.titular_distinto,p.beneficiario_nombre,p.beneficiario_dni),
('USD',p.banco_usd,p.tipo_cuenta_usd,p.numero_cuenta_usd,p.cci_usd,p.titular_distinto_usd,p.beneficiario_nombre_usd,p.beneficiario_dni_usd)
) s(moneda,banco,tipo_cuenta,numero_cuenta,cci,titular_distinto,beneficiario_nombre,beneficiario_dni)
join crm.cuentas_bancarias cb on cb.cliente_id=p.id and cb.moneda=x.moneda and cb.activa and cb.cci=btrim(s.cci)
where x.clase='perfil' and x.motivo='mismo_cci_datos_distintos' and s.moneda=x.moneda order by analista,cliente,x.moneda;

-- 2. Varias cuentas activas: ninguna selección automática de instrucción de pago.
select p.nombre_completo as cliente,p.dni,x.moneda,coalesce(a.nombre_completo,'Sin analista asignado') as analista,
 count(cb.id) as cuentas_activas,
 string_agg(cb.banco||' '||cb.moneda||' ••••'||right(cb.numero_cuenta,4)||' (CCI ••••'||right(cb.cci,4)||', '||cb.origen||')','; ' order by cb.creado_en desc,cb.id) as cuentas
from private.conciliacion_cuentas_p0xx x
join public.perfiles p on p.id=x.cliente_id
left join public.perfiles a on a.id=p.asesor_perfil_id
left join crm.cuentas_bancarias cb on cb.cliente_id=x.cliente_id and cb.moneda=x.moneda and cb.activa
where x.clase='perfil' and x.motivo='varias_activas'
group by x.id,p.nombre_completo,p.dni,x.moneda,a.nombre_completo
order by analista,cliente,x.moneda;
