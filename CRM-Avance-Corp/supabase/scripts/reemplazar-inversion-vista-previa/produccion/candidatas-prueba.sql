-- SOLO LECTURA. ¿Qué inversiones podría reemplazar el perfil vendedor de PRUEBAS (d731f284…) sin tocar ventas reales?
-- Lo que la pantalla ofrece: Avance «nuevo», no demo, activo o vencido; y lo que el servidor exige además: sin cuotas pagadas
-- (la MISMA regla del servidor: private.contrato_tiene_cuotas_pagadas, ya en producción).
begin read only;
select c.numero_contrato, c.categoria, c.estado, c.es_demo, c.capital, c.moneda, c.fecha_inicio, c.fecha_cierre_comercial,
       private.contrato_tiene_cuotas_pagadas(c.id) as cuotas_pagadas,
       (c.categoria = 'nuevo' and not c.es_demo and c.estado in ('activo', 'vencido')
        and not private.contrato_tiene_cuotas_pagadas(c.id)) as reemplazable
from public.contratos c
where c.analista_cierre_id::text like 'd731f284%' or c.creado_por::text like 'd731f284%'
order by c.creado_en desc
limit 20;
rollback;
