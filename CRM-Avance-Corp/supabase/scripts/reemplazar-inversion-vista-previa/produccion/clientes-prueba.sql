-- SOLO LECTURA. Clientes de PRUEBA que sirven para un alta desechable de «Reemplazar inversión»: nombre de prueba,
-- domicilio legal (el PDF lo exige) y cuenta en soles (o una cuenta de contrato). No muestra documentos ni cuentas.
begin read only;
select p.nombre_completo, p.activo,
       p.domicilio is not null and btrim(p.domicilio) <> '' as tiene_domicilio,
       p.numero_cuenta is not null as cuenta_pen_perfil,
       (select count(*) from public.contratos c where c.cliente_id = p.id) as contratos,
       (select count(*) from public.contratos c where c.cliente_id = p.id and not c.es_demo) as contratos_reales,
       left(p.id::text, 8) as id_corto
from public.perfiles p
where p.rol = 'cliente'
  and (p.nombre_completo ilike '%prueba%' or p.nombre_completo ilike '%test%' or p.nombre_completo ilike '%demo%'
       or p.nombre_completo ilike '%ficticio%')
order by p.creado_en desc
limit 15;
rollback;
