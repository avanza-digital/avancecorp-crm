-- ============================================================================
-- REMEDIACIÓN DEL CONTRATO DUPLICADO DEL 05/09/2026 — SOLO LECTURA + PUERTA OFICIAL
-- ============================================================================
--
-- ✅ EJECUTADO el 05/09/2026 a las 22:12:03 UTC (17:12 Lima) contra producción (dctqcbznekcyxhjujuci) por
-- `db query --linked --file` como `postgres`, con una copia rellena de la sección 3. DECISIÓN DE MIGUEL: el
-- contrato físico firmado lleva 000253, así que se ELIMINÓ 2026-01-000025 (74b5694f, el primer alta) y se
-- CONSERVÓ 2026-01-000253 (9597d503). Atribuido a ADMINISTRADOR AVANCE CORP (bf1c562e…): el DELETE quedó
-- en public.audit_log con ese usuario_id (la postcondición 3.3 lo exigió y pasó). Verificado después: el
-- cliente tiene UN contrato (000253, 13 cuotas, 1 cuenta), de 000025 no queda nada (0/0/0), y la consulta
-- de vigilancia 1.e devuelve 0 parejas. Este archivo queda como plantilla y registro; las constantes de
-- la sección 3 conservan el valor por defecto (eliminar 000253) por si hace falta otro caso.
--
-- (Original: lo revisa y lo corre Miguel desde el SQL editor del dashboard, como `postgres`. Cada sección
-- es independiente.)
--
-- LOS HECHOS (leídos en producción el 05/09/2026):
--   cliente  4e0c11bc-3fec-492b-a90e-93fd75b36ad4
--   A) 74b5694f-843d-4b88-be13-5f8fc8e82404  N° 2026-01-000025  creado 16:04:19 UTC  (el PRIMER alta)
--   B) 9597d503-1bff-4853-9c47-1eef5b5d3dfe  N° 2026-01-000253  creado 16:05:20 UTC  (el REINTENTO, 61 s después)
--   Idénticos: capital 20 000 PEN, tasa 15 %, mensual/simple, 11/03/2026 → 11/03/2027, 13 cuotas,
--   misma cuenta de pago 470bfde6-aa80-41ff-904a-705b523cca5c, mismo creado_por/analista, ambos 'activo'.
--   Ninguno tiene: pagos, job/PDF (régimen documental anterior), documentos, operación de cartera,
--   inversión F1, lead enlazado, reasignación ni preparación de eliminación (todo medido = 0).
--   El mismo día hubo OTRO ciclo igual (otro analista, cliente distinto): 16:56:34Z alta de 2026-01-000247
--   leída como error → 17:03:24Z eliminado por el botón de Gerencia (audit_log.usuario_id NULL) → 17:06:04Z
--   recreado con el mismo número para otro registro de cliente. De ese ciclo NO queda duplicado; la
--   consulta 1.e devuelve hoy UNA sola pareja: la de este archivo.
--   Sí tienen, cada uno: 13 filas en cronograma_pagos, 1 en crm.contrato_cuentas_pago y una condición
--   legacy propia en crm.producto_condiciones (es_legacy, legacy_contrato_id = él mismo; versiones
--   retiradas 603 y 604). Esa condición NO se puede borrar (trigger: «las condiciones se retiran; no se
--   eliminan») ni retirar (su versión ya está 'retirada'): queda huérfana, como las 55 que ya hay hoy de
--   contratos borrados antes. Es inocua: nadie la referencia.
--
-- POR QUÉ POR LA PUERTA OFICIAL Y NO CON DELETE A MANO. `crm.contrato_eliminacion_preparar` +
-- `crm.contrato_eliminacion_finalizar` son lo que usa el botón «Eliminar contrato y PDF» de Gerencia
-- (edge crm-contrato-pdf-v2, acción delete). Comprueban admin/superadmin y pagos, levantan el candado
-- documental con el set_config autorizado, borran PDFs/jobs (aquí 0) y el contrato; las FKs ON DELETE
-- CASCADE se llevan cronograma, cuenta de pago y titulares; el trigger de auditoría deja el DELETE en
-- public.audit_log. Un DELETE a mano tendría que bajar candados nombrados: no hace falta.
--
-- QUÉ CONTRATO ELIMINAR. Por defecto B (000253): es el reintento. PERO si el número que figura en el
-- contrato físico firmado es 000253 y no 000025, elimina A y conserva B: los dos son idénticos en
-- todo salvo el número, así que la decisión es cuál NÚMERO quieres que sobreviva. Cambia las dos
-- constantes de la sección 3 en ese caso.
--
-- CAMINO RECOMENDADO: la sección 3 (este SQL). El botón «Eliminar contrato» de Gerencia usa la MISMA
-- puerta, pero su edge la llama con service role: `auth.uid()` es NULL dentro de `log_audit_change` y el
-- DELETE queda en public.audit_log SIN actor (medido en prod el 05/09: el contrato eliminado a las
-- 17:03:24Z por el botón tiene usuario_id NULL; el actor solo queda en la fila efímera de
-- private.contrato_eliminaciones, que la propia puerta borra al finalizar). La sección 3 fija
-- `request.jwt.claim.sub` a tu perfil durante todo el bloque para que el borrado quede a tu nombre y lo
-- comprueba como postcondición (hallazgo de Codex, 05/09). Desde el SQL editor sin esa claim el rastro
-- también quedaría con usuario NULL.

-- ────────────────────────────────────────────────────────────────────────────
-- 1) DIAGNÓSTICO (solo lectura)
-- ────────────────────────────────────────────────────────────────────────────

-- 1.a Los dos contratos, lado a lado.
select c.numero_contrato, c.id, c.estado, c.categoria, c.capital, c.moneda, c.tasa_anual, c.modalidad,
       c.tipo_interes, c.fecha_inicio, c.fecha_vencimiento, c.fecha_cierre_comercial, c.creado_en,
       c.creado_por, c.analista_cierre_id, c.producto_condicion_id, c.notas_internas,
       private.contrato_documental_regimen(c.id) as regimen_documental
from public.contratos c
where c.id in ('74b5694f-843d-4b88-be13-5f8fc8e82404', '9597d503-1bff-4853-9c47-1eef5b5d3dfe')
order by c.creado_en;

-- 1.b Todo lo que cuelga de cada uno (debe salir 13 / 1 / 0 / 0 / 0 / 0 / 0 / 0 / 0 para ambos).
select c.numero_contrato,
       (select count(*) from public.cronograma_pagos cp where cp.contrato_id = c.id)                          as cuotas,
       (select count(*) from crm.contrato_cuentas_pago ccp where ccp.contrato_id = c.id)                       as cuentas_pago,
       (select count(*) from public.cronograma_pagos cp where cp.contrato_id = c.id
                                                          and (cp.estado = 'pagado' or cp.monto_pagado is not null)) as pagos,
       (select count(*) from public.contrato_titulares t where t.contrato_id = c.id)                          as cotitulares,
       (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = c.id)
         + (select count(*) from private.contrato_pdfs p where p.contrato_id = c.id)                          as pdf_jobs_y_archivos,
       (select count(*) from public.documentos d where d.contrato_id = c.id)                                  as documentos,
       (select count(*) from crm.operaciones_cartera o where o.contrato_nuevo_id = c.id or o.contrato_origen_id = c.id) as operaciones_cartera,
       (select count(*) from crm.inversiones i where i.contrato_id = c.id)                                    as inversiones_f1,
       (select count(*) from crm.leads l where l.contrato_id = c.id)
         + (select count(*) from crm.reasignaciones_analista r where r.contrato_id = c.id)
         + (select count(*) from private.contrato_eliminaciones e where e.contrato_id = c.id)                 as otros_enlaces
from public.contratos c
where c.id in ('74b5694f-843d-4b88-be13-5f8fc8e82404', '9597d503-1bff-4853-9c47-1eef5b5d3dfe')
order by c.creado_en;

-- 1.c Los cronogramas son el mismo (misma suma, mismas fechas): si difieren, PARA y revisa.
select c.numero_contrato, count(*) as cuotas, sum(cp.monto_programado) as total_programado,
       min(cp.fecha_programada) as primera, max(cp.fecha_programada) as ultima,
       md5(string_agg(cp.numero_cuota || '|' || cp.fecha_programada || '|' || cp.monto_programado || '|' || cp.tipo, ',' order by cp.numero_cuota)) as huella_cronograma
from public.contratos c join public.cronograma_pagos cp on cp.contrato_id = c.id
where c.id in ('74b5694f-843d-4b88-be13-5f8fc8e82404', '9597d503-1bff-4853-9c47-1eef5b5d3dfe')
group by c.numero_contrato order by c.numero_contrato;

-- 1.d El rastro de auditoría de ambos (alta, y después de la remediación, el DELETE del eliminado).
select a.ts, a.tabla, a.operacion, a.fila_id, a.usuario_id
from public.audit_log a
where a.fila_id in ('74b5694f-843d-4b88-be13-5f8fc8e82404', '9597d503-1bff-4853-9c47-1eef5b5d3dfe')
order by a.ts;

-- 1.e ¿Hay OTRAS parejas así en producción? (misma búsqueda que encontró esta; hoy devuelve solo esta).
select a.numero_contrato as n1, b.numero_contrato as n2, a.cliente_id, a.capital, a.moneda, a.fecha_inicio,
       a.creado_en as t1, b.creado_en as t2, extract(epoch from (b.creado_en - a.creado_en))::int as segundos
from public.contratos a
join public.contratos b
  on b.cliente_id = a.cliente_id and b.id <> a.id and b.creado_en > a.creado_en
 and b.creado_en - a.creado_en < interval '30 minutes'
 and b.capital = a.capital and b.moneda = a.moneda and b.tasa_anual = a.tasa_anual
 and b.fecha_inicio = a.fecha_inicio and b.fecha_vencimiento = a.fecha_vencimiento
where a.estado <> 'anulado' and b.estado <> 'anulado'
order by a.creado_en;

-- ────────────────────────────────────────────────────────────────────────────
-- 2) QUIÉN PUEDE ELIMINAR (para rellenar el actor de la sección 3)
-- ────────────────────────────────────────────────────────────────────────────
-- La puerta exige `public.es_admin()` para el actor (superadmin si hubiera pagos; aquí no hay).
select p.id as actor_id, p.rol, p.activo
from public.perfiles p
where p.rol in ('admin', 'superadmin') and p.activo
order by p.rol, p.id;

-- ────────────────────────────────────────────────────────────────────────────
-- 3) REMEDIACIÓN — por la puerta oficial, en UNA transacción, con verificación
-- ────────────────────────────────────────────────────────────────────────────
-- Rellena v_actor con TU perfil (sección 2). Si el número firmado es 000253, intercambia v_eliminar /
-- v_conservar. Cualquier comprobación que falle aborta el bloque entero y NO se borra nada.
-- Las comprobaciones de 3.1 se hacen DENTRO del bloque y bajo lock (no dependen de haber mirado la
-- sección 1): si alguien tocó uno de los dos entre medias (cuenta, cuota, cotitular, nota), aborta.
do $remediacion$
declare
  v_actor      uuid := '00000000-0000-0000-0000-000000000000';               -- ← TU perfil (sección 2)
  v_eliminar   uuid := '9597d503-1bff-4853-9c47-1eef5b5d3dfe';               -- B · 2026-01-000253 (el reintento)
  v_num_elim   text := '2026-01-000253';                                       -- su número: doble candado contra el uuid equivocado
  v_conservar  uuid := '74b5694f-843d-4b88-be13-5f8fc8e82404';               -- A · 2026-01-000025 (el primer alta)
  v_num_cons   text := '2026-01-000025';
  v_cliente    uuid := '4e0c11bc-3fec-492b-a90e-93fd75b36ad4';
  v_e public.contratos%rowtype;
  v_c public.contratos%rowtype;
  v_prep jsonb; v_fin jsonb; v_n int;
  v_crono_e text; v_crono_c text; v_cta_e uuid; v_cta_c uuid; v_tit_e int; v_tit_c int;
  v_audit_actor uuid;
begin
  if v_actor = '00000000-0000-0000-0000-000000000000' then
    raise exception 'Rellena v_actor con tu perfil de admin/superadmin (sección 2)';
  end if;
  if not exists (select 1 from public.perfiles p where p.id = v_actor and p.activo and p.rol in ('admin', 'superadmin')) then
    raise exception 'v_actor no es un perfil admin/superadmin activo';
  end if;
  -- Quién borra, para la auditoría: auth.uid() lee esta claim. Local a la transacción.
  perform set_config('request.jwt.claim.sub', v_actor::text, true);

  -- 3.1 Precondiciones bajo lock: existen, son del cliente, activos y DUPLICADOS COMPLETOS.
  if v_eliminar = v_conservar then raise exception 'v_eliminar y v_conservar son el mismo contrato'; end if;
  select * into v_e from public.contratos where id = v_eliminar for update;
  if not found then raise exception 'No existe el contrato a eliminar %', v_eliminar; end if;
  select * into v_c from public.contratos where id = v_conservar for update;
  if not found then raise exception 'No existe el contrato a conservar %', v_conservar; end if;
  if v_e.numero_contrato <> v_num_elim or v_c.numero_contrato <> v_num_cons then
    raise exception 'Los números no cuadran con los uuid (eliminar=% esperado %, conservar=% esperado %): revisa las constantes',
      v_e.numero_contrato, v_num_elim, v_c.numero_contrato, v_num_cons;
  end if;
  -- Una preparación de eliminación PENDIENTE de otro admin haría fallar la finalización con un
  -- mensaje engañoso (token ajeno): se detecta antes.
  if exists (select 1 from private.contrato_eliminaciones e where e.contrato_id in (v_eliminar, v_conservar)) then
    raise exception 'Hay una preparación de eliminación pendiente sobre uno de los dos contratos (private.contrato_eliminaciones): revísala antes';
  end if;
  if v_e.cliente_id <> v_cliente or v_c.cliente_id <> v_cliente then
    raise exception 'Los contratos no son del cliente esperado';
  end if;
  if v_e.estado <> 'activo' or v_c.estado <> 'activo' then
    raise exception 'Se esperaban ambos en estado activo (eliminar=%, conservar=%)', v_e.estado, v_c.estado;
  end if;
  -- Todo lo que define el contrato, no solo lo económico: autoría, analista, fecha comercial, notas.
  if row(v_e.capital, v_e.moneda, v_e.tasa_anual, v_e.modalidad, v_e.tipo_interes, v_e.fecha_inicio,
         v_e.fecha_vencimiento, v_e.categoria, v_e.creado_por, v_e.analista_cierre_id, v_e.fecha_cierre_comercial,
         v_e.notas_internas)
     is distinct from
     row(v_c.capital, v_c.moneda, v_c.tasa_anual, v_c.modalidad, v_c.tipo_interes, v_c.fecha_inicio,
         v_c.fecha_vencimiento, v_c.categoria, v_c.creado_por, v_c.analista_cierre_id, v_c.fecha_cierre_comercial,
         v_c.notas_internas) then
    raise exception 'Los dos contratos NO son idénticos (cabecera, autoría, analista, fecha comercial o notas): PARA';
  end if;
  -- El cronograma, cuota a cuota (número, fecha, monto, tipo, estado).
  select md5(string_agg(cp.numero_cuota || '|' || cp.fecha_programada || '|' || cp.monto_programado || '|' || cp.tipo || '|' || cp.estado, ',' order by cp.numero_cuota))
    into v_crono_e from public.cronograma_pagos cp where cp.contrato_id = v_eliminar;
  select md5(string_agg(cp.numero_cuota || '|' || cp.fecha_programada || '|' || cp.monto_programado || '|' || cp.tipo || '|' || cp.estado, ',' order by cp.numero_cuota))
    into v_crono_c from public.cronograma_pagos cp where cp.contrato_id = v_conservar;
  if v_crono_e is null or v_crono_e is distinct from v_crono_c then
    raise exception 'Los cronogramas NO son idénticos: PARA';
  end if;
  -- La cuenta de pago: exactamente una en cada uno, y la misma.
  select ccp.cuenta_bancaria_id into v_cta_e from crm.contrato_cuentas_pago ccp where ccp.contrato_id = v_eliminar;
  select ccp.cuenta_bancaria_id into v_cta_c from crm.contrato_cuentas_pago ccp where ccp.contrato_id = v_conservar;
  select count(*) into v_n from crm.contrato_cuentas_pago ccp where ccp.contrato_id in (v_eliminar, v_conservar);
  if v_n <> 2 or v_cta_e is null or v_cta_e is distinct from v_cta_c then
    raise exception 'Las cuentas de pago NO coinciden (eliminar=%, conservar=%, filas=%): PARA', v_cta_e, v_cta_c, v_n;
  end if;
  -- Co-titulares: ninguno en los dos (así nacieron).
  select count(*) into v_tit_e from public.contrato_titulares t where t.contrato_id = v_eliminar;
  select count(*) into v_tit_c from public.contrato_titulares t where t.contrato_id = v_conservar;
  if v_tit_e <> 0 or v_tit_c <> 0 then
    raise exception 'Hay co-titulares (eliminar=%, conservar=%): revisa antes de borrar', v_tit_e, v_tit_c;
  end if;
  if exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = v_eliminar
             and (cp.estado = 'pagado' or cp.monto_pagado is not null)) then
    raise exception 'El contrato a eliminar tiene pagos registrados: PARA';
  end if;
  if exists (select 1 from private.contrato_pdf_jobs j where j.contrato_id = v_eliminar)
     or exists (select 1 from private.contrato_pdfs p where p.contrato_id = v_eliminar)
     or exists (select 1 from public.documentos d where d.contrato_id = v_eliminar) then
    -- Con archivos en Storage la puerta devolvería objetos que hay que borrar desde la edge:
    -- usa el botón de Gerencia en ese caso.
    raise exception 'El contrato a eliminar tiene documentos: elimínalo desde el botón de Gerencia';
  end if;
  if exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = v_eliminar or o.contrato_origen_id = v_eliminar)
     or exists (select 1 from crm.inversiones i where i.contrato_id = v_eliminar)
     or exists (select 1 from crm.leads l where l.contrato_id = v_eliminar)
     or exists (select 1 from crm.reasignaciones_analista r where r.contrato_id = v_eliminar) then
    raise exception 'El contrato a eliminar tiene enlaces (cartera, inversión, lead o reasignación): PARA';
  end if;

  -- 3.2 La puerta oficial: preparar (autorización + manifiesto de archivos) y finalizar (borrado).
  v_prep := crm.contrato_eliminacion_preparar(v_eliminar, v_actor);
  if coalesce(jsonb_array_length(v_prep->'objetos'), -1) <> 0 then
    raise exception 'La preparación devolvió archivos en Storage (%): elimínalo desde el botón de Gerencia', v_prep->'objetos';
  end if;
  v_fin := crm.contrato_eliminacion_finalizar(v_eliminar, (v_prep->>'token')::uuid, v_actor);
  if coalesce((v_fin->>'ok')::boolean, false) is not true then
    raise exception 'La finalización no confirmó: %', v_fin;
  end if;

  -- 3.3 Postcondiciones: el eliminado no deja nada; el conservado sigue entero.
  if exists (select 1 from public.contratos where id = v_eliminar) then raise exception 'El contrato sigue existiendo'; end if;
  select count(*) into v_n from public.cronograma_pagos where contrato_id = v_eliminar;
  if v_n <> 0 then raise exception 'Quedaron % cuotas del eliminado', v_n; end if;
  select count(*) into v_n from crm.contrato_cuentas_pago where contrato_id = v_eliminar;
  if v_n <> 0 then raise exception 'Quedó el vínculo de cuenta del eliminado'; end if;
  select count(*) into v_n from public.contrato_titulares where contrato_id = v_eliminar;
  if v_n <> 0 then raise exception 'Quedaron cotitulares del eliminado'; end if;
  select count(*) into v_n from public.cronograma_pagos where contrato_id = v_conservar;
  if v_n <> 13 then raise exception 'El conservado ya no tiene 13 cuotas (%): PARA', v_n; end if;
  select count(*) into v_n from crm.contrato_cuentas_pago where contrato_id = v_conservar;
  if v_n <> 1 then raise exception 'El conservado perdió su cuenta de pago'; end if;
  if not exists (select 1 from public.contratos where id = v_conservar and estado = 'activo') then
    raise exception 'El conservado no está activo';
  end if;
  -- El rastro: un DELETE de public.contratos para el eliminado, atribuido a TI (log_audit_change
  -- guarda 'DELETE' y auth.uid(); la claim fijada arriba es lo que auth.uid() lee).
  select a.usuario_id into v_audit_actor
  from public.audit_log a
  where a.tabla = 'contratos' and a.fila_id = v_eliminar::text and a.operacion = 'DELETE'
  order by a.ts desc limit 1;
  if not found then
    raise exception 'No quedó rastro de auditoría del DELETE';
  end if;
  if v_audit_actor is distinct from v_actor then
    raise exception 'El rastro del DELETE no quedó a tu nombre (usuario_id=%): PARA y revisa', v_audit_actor;
  end if;
  raise notice 'REMEDIACIÓN OK: eliminado % (N° %), conservado % (N° %), archivos borrados: %, auditado por %',
    v_eliminar, v_e.numero_contrato, v_conservar, v_c.numero_contrato, v_fin->>'objetos_eliminados', v_audit_actor;
end
$remediacion$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4) VERIFICACIÓN DESPUÉS (solo lectura): el cliente debe tener UN contrato activo
-- ────────────────────────────────────────────────────────────────────────────
select c.numero_contrato, c.id, c.estado, c.capital, c.fecha_inicio, c.fecha_vencimiento,
       (select count(*) from public.cronograma_pagos cp where cp.contrato_id = c.id) as cuotas,
       (select count(*) from crm.contrato_cuentas_pago ccp where ccp.contrato_id = c.id) as cuentas_pago
from public.contratos c
where c.cliente_id = '4e0c11bc-3fec-492b-a90e-93fd75b36ad4'
order by c.creado_en;

select a.ts, a.operacion, a.fila_id, a.usuario_id
from public.audit_log a
where a.fila_id in ('74b5694f-843d-4b88-be13-5f8fc8e82404', '9597d503-1bff-4853-9c47-1eef5b5d3dfe')
order by a.ts;

-- La condición legacy huérfana que deja el eliminado (inocua; se lista para que conste).
select pc.id, pc.legacy_contrato_id, pc.activa, pc.version_id, pc.creado_en
from crm.producto_condiciones pc
where pc.legacy_contrato_id in ('74b5694f-843d-4b88-be13-5f8fc8e82404', '9597d503-1bff-4853-9c47-1eef5b5d3dfe')
order by pc.creado_en;
