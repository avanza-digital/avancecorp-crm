-- PRUEBA SINTÉTICA (banco Docker, como supabase_admin, todo deshecho al final): el cuerpo VIVO y el NUEVO de
-- private.cartera_f5_fuentes() deben dar las MISMAS filas sobre grafos que producción no tiene hoy (0 fusiones,
-- 3 operaciones): hijos y nietos fusionados, cadena de 17 (supera el tope 16), ciclo A↔B, padre inexistente,
-- auto-padre, upgrades encadenados, renovación tras upgrade, ciclo de operaciones y analista nulo.
-- Casos: SINT-3 (nieto fusionado → canónica 01) · SINT-9 (cliente 10, cadena de 17 → él mismo) · SINT-13 (cliente 11 → raíz 26 en el nodo 16)
-- · SINT-5/6 (ciclo A↔B → cada uno él mismo) · SINT-7 (padre inexistente → él mismo; upgrade con analista NULL) · SINT-8 (perfil sin
-- persona; renovación de un upgrade sin analista → su propio analista) · SINT-4 (renovación tras upgrade → analista del upgrade)
-- · SINT-14 (identidad incoherente: perfil de la persona 01 e inversión de la 27 → identidad_coherente=false) · TX-1/TX-2 (cierres externos
-- con persona propia) · TX-3 (cierre inicial sin persona propia, enlazado por inversión → ruta iv.cierre_externo_id) · TX-4 (cierre inicial cuya
-- persona llega por el lead → ruta l.inversionista_id).
-- Requiere el cuerpo NUEVO instalado (la migración aplicada en el banco). Triggers y FKs apagados con
-- session_replication_role = replica para sembrar filas mínimas; los CHECK siguen vivos.
begin;
set local session_replication_role = replica;
set local search_path = '';
CREATE OR REPLACE FUNCTION pg_temp.cartera_f5_fuentes_vieja()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce(private.analista_atribuido_cadena(c.id),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$;

-- Actores mínimos
insert into public.perfiles (id, nombre_completo) select ('00000000-0000-4000-8000-0000000000'||lpad(g::text,2,'0'))::uuid, 'Sintético '||g from generate_series(1,40) g;
-- Personas: P01 raíz · P02→P01 · P03→P02 · cadena C10→C11→…→C26 raíz (17 nodos: C10 no llega a la raíz dentro del tope 16 y queda como su propia canónica; C11 sí llega, en su nodo 16) · A↔B (27,28) · D→inexistente (29) · el auto-padre lo prohíbe el CHECK inversionistas_no_autofusion (no se siembra) · perfil 30 sin persona
insert into crm.inversionistas (id, perfil_id, inversionista_canonico_id) values
  ('00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8000-000000000001', null),
  ('00000000-0000-4000-8000-000000000002'::uuid, '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000003'::uuid, '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000027'::uuid, '00000000-0000-4000-8000-000000000027', '00000000-0000-4000-8000-000000000028'),
  ('00000000-0000-4000-8000-000000000028'::uuid, '00000000-0000-4000-8000-000000000028', '00000000-0000-4000-8000-000000000027'),
  ('00000000-0000-4000-8000-000000000029'::uuid, '00000000-0000-4000-8000-000000000029', '00000000-0000-4000-8000-000000000099');
insert into crm.inversionistas (id, perfil_id, inversionista_canonico_id)
  select ('00000000-0000-4000-8000-0000000000'||g)::uuid, ('00000000-0000-4000-8000-0000000000'||g)::uuid,
         case when g < 26 then ('00000000-0000-4000-8000-0000000000'||(g+1))::uuid end from generate_series(10,26) g;

-- Contratos: K1 nueva (a1) · K2 upgrade de K1 (a2) · K3 upgrade de K2 (a3) · K4 renovación de K3 · K5↔K6 ciclo · K7 upgrade con analista nulo, K8 renovación de K7
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, modalidad, fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial, categoria, analista_cierre_id, estado, es_demo)
select ('00000000-0000-4000-8000-00000000c0'||lpad(k::text,2,'0'))::uuid, 'SINT-'||k, ('00000000-0000-4000-8000-0000000000'||lpad(cli::text,2,'0'))::uuid, 1000, 'PEN', 'mensual', date '2026-01-01', date '2027-01-01', gen_random_uuid(), date '2026-01-01', cat, an, 'activo', false
from (values
  (1, 1, 'nuevo',      '00000000-0000-4000-8000-000000000031'::uuid),
  (2, 2, 'upgrade',    '00000000-0000-4000-8000-000000000032'::uuid),
  (3, 3, 'upgrade',    '00000000-0000-4000-8000-000000000033'::uuid),
  (4, 3, 'renovacion', '00000000-0000-4000-8000-000000000034'::uuid),
  (5, 27,'upgrade',    '00000000-0000-4000-8000-000000000035'::uuid),
  (6, 28,'renovacion', '00000000-0000-4000-8000-000000000036'::uuid),
  (7, 29,'upgrade',    null::uuid),
  (8, 30,'renovacion', '00000000-0000-4000-8000-000000000038'::uuid),
  (9, 10,'nuevo',      null::uuid),
  (13, 11,'nuevo',     null::uuid),
  (14, 1,'nuevo',      null::uuid)) v(k, cli, cat, an);
-- (El EMPATE de dos orígenes «upgrade» al mismo nivel NO puede sembrarse: operaciones_cartera.contrato_nuevo_id es UNIQUE,
--  la cadena es lineal. Codex r1 P2 refutado con esa evidencia; el intento de sembrarlo lo confirmó: duplicate key.)
-- Las operaciones que enlazan origen→nuevo son RENOVACIONES (el CHECK operaciones_cartera_forma exige contrato_origen_id
-- NULL en los upgrades); la cadena sube por ellas hasta el primer contrato con categoria = 'upgrade'.
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, contrato_origen_id, fecha_operacion, periodo, moneda, elegible_conversion, fuente, creado_por, desglose_completo, capital_renovado, capital_adicional)
select ('00000000-0000-4000-8000-000000000001')::uuid, ('00000000-0000-4000-8000-000000000031')::uuid, 'renovacion', ('00000000-0000-4000-8000-00000000c0'||lpad(n::text,2,'0'))::uuid, ('00000000-0000-4000-8000-00000000c0'||lpad(o::text,2,'0'))::uuid, date '2026-02-01', date '2026-02-01', 'PEN', true, 'flujo_cartera', ('00000000-0000-4000-8000-000000000031')::uuid, true, 1000, 0
from (values (2,1),(3,2),(4,3),(5,6),(6,5),(8,7)) v(n,o);
-- Inversiones que enlazan contrato→persona (rama iv.inversionista_id) y cierres externos con persona/lead
insert into crm.inversiones (id, inversionista_id, empresa_id, contrato_id) values
  (gen_random_uuid(), '00000000-0000-4000-8000-000000000003', gen_random_uuid(), '00000000-0000-4000-8000-00000000c001'),
  (gen_random_uuid(), '00000000-0000-4000-8000-000000000010', gen_random_uuid(), '00000000-0000-4000-8000-00000000c009'),
  -- identidad INCOHERENTE (auditor-rls P3-5): K14 es del perfil 01 (persona 01) y su inversión apunta a la persona 27 (ciclo A↔B)
  (gen_random_uuid(), '00000000-0000-4000-8000-000000000027', gen_random_uuid(), '00000000-0000-4000-8000-00000000c014');
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, inversionista_id) values
  ('00000000-0000-4000-8000-00000000ad01', 'Lead sintético 1', '+51900000001', 'otro', 1000, null),
  ('00000000-0000-4000-8000-00000000ad02', 'Lead sintético 2', '+51900000002', 'otro', 1000, '00000000-0000-4000-8000-000000000002');
insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion, vendedor_id, creado_por, inversionista_id, vence_en, es_cierre_inicial, fecha_comercial, fecha_imputacion, comprobante_objeto_id, referencia_externa, lead_id)
values ('00000000-0000-4000-8000-00000000ce01', 'qorilazo', 500, 'PEN', 'DNI', '00000001', 'Sintético CE', 'TX-1', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000003', date '2027-01-01', false, date '2026-01-01', date '2026-01-02', gen_random_uuid(), 'TX-1', null),
       ('00000000-0000-4000-8000-00000000ce02', 'prodelco', 500, 'PEN', 'DNI', '00000002', 'Sintético CE2', 'TX-2', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000027', date '2025-01-01', false, date '2026-01-01', date '2026-01-02', gen_random_uuid(), 'TX-2', null),
       -- TX-3: cierre inicial SIN inversionista_id propio (lead L1 sin persona); su persona llega por la ruta iv.cierre_externo_id (Codex r2):
       -- inversión de la persona 03 → canónica 01
       ('00000000-0000-4000-8000-00000000ce03', 'qorilazo', 500, 'PEN', 'DNI', '00000003', 'Sintético CE3', 'TX-3', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000031', null, date '2027-01-01', true, null, null, null, 'TX-3', '00000000-0000-4000-8000-00000000ad01'),
       -- TX-4: cierre inicial cuyo lead L2 SÍ tiene persona (02 → canónica 01): ruta l.inversionista_id, sin inversión
       ('00000000-0000-4000-8000-00000000ce04', 'qorilazo', 500, 'PEN', 'DNI', '00000004', 'Sintético CE4', 'TX-4', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000031', null, date '2027-01-01', true, null, null, null, 'TX-4', '00000000-0000-4000-8000-00000000ad02');
insert into crm.inversiones (id, inversionista_id, empresa_id, cierre_externo_id) values
  (gen_random_uuid(), '00000000-0000-4000-8000-000000000003', gen_random_uuid(), '00000000-0000-4000-8000-00000000ce03');

do $p$
declare v_vieja text; v_nueva text; n_v int; n_n int; v_foto text; v_md5 text; v_esp text; v_real text;
begin
  select md5(pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure)) into v_md5;
  if v_md5 <> 'fa15f7765d0892c790c7a4b6822e756e' then raise exception 'la prueba exige el cuerpo NUEVO instalado (huella %)', v_md5; end if;
  select count(*), md5(string_agg(f::text, '|' order by f::text)) into n_v, v_vieja from pg_temp.cartera_f5_fuentes_vieja() f;
  select count(*), md5(string_agg(f::text, '|' order by f::text)) into n_n, v_nueva from private.cartera_f5_fuentes() f;
  -- foto legible: fuente → persona canónica / analista atribuido (según el cuerpo nuevo)
  select string_agg(f.numero||'→'||coalesce(right(f.inversionista_id::text,2),'-')||'/'||coalesce(right(f.analista_origen_id::text,2),'-')||case when f.identidad_coherente then '' when f.identidad_coherente is null then '?' else '!' end, ' ' order by f.numero) into v_foto
    from private.cartera_f5_fuentes() f where f.numero like 'SINT-%' or f.numero like 'TX-%';
  if n_v <> n_n or v_vieja <> v_nueva then
    raise exception 'SINTETICA: DISTINTAS (vieja % filas md5 %, nueva % filas md5 %) · nueva: %', n_v, v_vieja, n_n, v_nueva, v_foto;
  end if;
  -- Expectativas EXPLÍCITAS (además de la igualdad vieja = nueva): canónica y atribución esperadas por caso.
  -- «!» = identidad_coherente FALSE (dos canónicas distintas: personas[1] es la menor por array_agg(distinct), igual en ambos cuerpos)
  -- «?» = identidad_coherente NULL (sin ninguna persona: cardinality(NULL) es NULL; Codex r2 P3)
  v_esp := 'SINT-1→01/31 SINT-13→26/- SINT-14→01/-! SINT-2→01/32 SINT-3→01/33 SINT-4→01/33 SINT-5→27/35 SINT-6→28/35 SINT-7→29/- SINT-8→-/38? SINT-9→10/- TX-1→01/31 TX-2→27/31 TX-3→01/31 TX-4→01/31';  -- SINT-8: perfil sin persona → personas NULL → coherente NULL, en ambos cuerpos
  if v_foto <> v_esp then
    raise exception 'SINTETICA: la foto no es la esperada. esperada: % · real: %', v_esp, v_foto;
  end if;
  raise exception 'SINTETICA OK (rollback): % filas idénticas entre cuerpo vivo y nuevo · expectativas explícitas OK · fuente→persona canónica/analista atribuido: %', n_n, v_foto;
end $p$;
rollback;
