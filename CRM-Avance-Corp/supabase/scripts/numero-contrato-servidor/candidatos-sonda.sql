-- CANDIDATOS DE LA SONDA de 20261009210100_crm_numero_contrato_servidor — SOLO LECTURA (F4.1-A ronda 5, auditor de permisos r2
-- P3-6). Una sola SELECT: no llama a public.crear_contrato ni a nada que escriba, y no muestra documentos (solo si existe).
--
-- QUÉ DICE. Los 5 primeros pares vendedor–cliente que probaría la sonda del postflight de la migración —la MISMA selección y el
-- MISMO orden: vendedor activo (public.perfiles.rol = comercial y activo; crm.equipo.rol_crm = vendedor y activo;
-- private.rol_crm = vendedor) × cliente activo de su cartera (rol cliente, activo, asesor_perfil_id = ese vendedor), por
-- (vendedor, cliente), limit 5— y si cada uno CONCLUIRÍA: llega a la guarda del número (con la migración, «RECHAZADO con 22023 y
-- el mensaje fijado») o muere ANTES (no concluyente). La última fila resume: con qué candidato concluiría la sonda, o que la
-- migración se NEGARÍA (sin candidatos, o ninguno concluye).
--
-- CÓMO PREDICE «concluiría». Para un vendedor de esa selección, lo único que `public.crear_contrato` hace ANTES de la guarda y
-- puede cortarlo es reconocer al cliente por su documento, y solo con la identidad unificada ENCENDIDA (crm.multiempresa_flags
-- 'resolver_en_puertas'; private.asegurar_identidad_perfil + private.inversionista_resolver): sin documento ⇒ P0409; tipo fuera
-- de DNI/CE/PASAPORTE ⇒ 22023 «Tipo de documento invalido»; documento que no casa con su tipo ⇒ 22023 «Documento invalido para el
-- tipo» (22023, pero con otro mensaje: NO concluye); la persona de ese documento ya tiene OTRO perfil ⇒ P0409; este perfil ya es
-- de OTRA persona reconocida ⇒ P0409. Con la identidad apagada no corre nada de eso. Lo demás que va antes de la guarda
-- (autoridad de vendedor, capital 500, tasa 15, categoría nuevo, analista = el propio vendedor) lo cumple por construcción.
-- Fuera de la predicción: esperas de candados (lock_timeout 5s) y carreras (40001). La prueba sigue siendo la sonda de la
-- migración, que se detiene en el PRIMER candidato que concluye y, si ninguno concluye, NO aplica nada.
--
-- USO (antes de aplicar la 2.3: en la branch y, en F4.7, en producción), desde `CRM-Avance-Corp/`:
--   supabase db query --linked --file supabase/scripts/numero-contrato-servidor/candidatos-sonda.sql
-- Si ninguno concluye: preparar UN vendedor activo con un cliente activo CON DOCUMENTO válido en su cartera (lo que describe el
-- mensaje de la migración) y repetir esta consulta. Comprobada contra el laboratorio con q.py (solo lectura).
with identidad as (
  select coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) as encendida
), candidatos as (
  select row_number() over (order by e.perfil_id, c.id) as n, e.perfil_id as vendedor, c.id as cliente,
         coalesce(nullif(btrim(c.tipo_documento), ''), 'DNI') as tipo,
         nullif(upper(regexp_replace(coalesce(c.dni, ''), '[^A-Za-z0-9]', '', 'g')), '') as documento
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  join public.perfiles c on c.asesor_perfil_id = e.perfil_id and c.rol = 'cliente' and c.activo
  where e.rol_crm = 'vendedor' and e.activo and p.activo and p.rol = 'comercial'
    and private.rol_crm(e.perfil_id) = 'vendedor'
  order by e.perfil_id, c.id
  limit 5
), reconocida as (
  select k.n,
         (select i.inversionista_id from crm.inversionista_identificadores i
            join crm.inversionistas inv on inv.id = i.inversionista_id
           where i.tipo_documento = k.tipo and i.documento_normalizado = k.documento
             and i.estado = 'vigente' and i.verificado = true and inv.estado <> 'fusionado'
           limit 1) as inversionista
  from candidatos k
), juicio as (
  select k.n, k.vendedor, k.cliente, k.documento is not null as tiene_documento,
    case
      when not (select x.encendida from identidad x) then null
      when k.documento is null then 'P0409: el cliente no tiene documento'
      when k.tipo not in ('DNI', 'CE', 'PASAPORTE') then '22023 «Tipo de documento invalido» (otro mensaje)'
      when (k.tipo = 'DNI' and k.documento !~ '^[0-9]{8}$') or (k.tipo = 'CE' and k.documento !~ '^[0-9]{9,12}$')
        or (k.tipo = 'PASAPORTE' and k.documento !~ '^[A-Z0-9]{6,12}$') then '22023 «Documento invalido para el tipo» (otro mensaje)'
      when (select inv.perfil_id from crm.inversionistas inv where inv.id = r.inversionista) is not null
        and (select inv.perfil_id from crm.inversionistas inv where inv.id = r.inversionista) <> k.cliente
        then 'P0409: la persona de ese documento ya tiene otro perfil de cliente'
      when (select inv.perfil_id from crm.inversionistas inv where inv.id = r.inversionista) is null
        and exists (select 1 from crm.inversionistas inv where inv.perfil_id = k.cliente and inv.estado <> 'fusionado'
                     and inv.id is distinct from r.inversionista)
        then 'P0409: este perfil ya pertenece a otra persona reconocida'
    end as corta_antes
  from candidatos k
  join reconocida r on r.n = k.n
)
select j.n as candidato, j.vendedor, j.cliente, (select x.encendida from identidad x) as identidad_unificada,
       j.tiene_documento,
       case when j.corta_antes is null then 'SÍ: llega a la guarda (con la 2.3: RECHAZADO con 22023)'
            else 'NO: muere antes, ' || j.corta_antes end as concluiria,
       case when j.n = (select min(y.n) from juicio y where y.corta_antes is null) then 'la sonda concluiría aquí' else '' end as nota
from juicio j
union all
select null, null, null, (select x.encendida from identidad x), null,
       case when not exists (select 1 from candidatos) then 'SIN CANDIDATOS: la migración se NEGARÍA'
            when not exists (select 1 from juicio y where y.corta_antes is null)
              then 'NINGUNO concluye: la migración se NEGARÍA (preparar un vendedor con un cliente con documento)'
            else 'concluiría con el candidato ' || (select min(y.n) from juicio y where y.corta_antes is null)
                 || ' de ' || (select count(*) from candidatos) end,
       'resumen'
order by 1 nulls last;
