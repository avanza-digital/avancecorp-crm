-- =========================================================================
-- CRM · Una sola pieza para la conversion por persona · Metas deja de calcular
-- =========================================================================
-- DECISION DE MIGUEL (23/09/2026): Metas deja de calcular la conversion y usa
-- la de la oficial. Sin fusionar payloads y sin vigilancia: se quita la causa
-- (dos textos que habia que mantener iguales para siempre), no se vigila el
-- sintoma. Encargo: `pendientes/FUSIONAR-METAS-CON-LA-OFICIAL.md`.
--
-- LAS CAPAS (tabla -> nucleo -> puerta -> pantalla). La cifra por persona es
-- logica de negocio, asi que vive en el NUCLEO, una sola vez:
--   · private.conversion_neta_por_vendedor(mes, global, visibles)  NUEVA
--       nucleo (bruto) + deuda de meses ya pagados + neto + porcentaje.
--   · private.roster_conversion_mensual(mes, global, visibles)     NUEVA
--       quien sale NOMBRADO en la oficial (roster vivo o la publicacion del mes).
-- Las PUERTAS dejan de calcular y solo autorizan, eligen su poblacion y arman
-- su paquete:
--   · crm.conversion_mensual_sin_cartera_fn   la oficial (#1)
--   · crm.cumplimiento_metas_sin_cartera_fn   la #8, motor de Metas
--   · crm.cumplimiento_metas_fn               la #7: su lista fuera del ranking
-- Ninguna puerta le pide la cifra a otra puerta. Por eso NO se hizo «Metas
-- llama a crm.conversion_mensual_fn»: la oficial solo nombra al roster VIVO y
-- manda a un agregado sin nombre a quien se fue a mitad de mes, y Metas tiene
-- que seguir mostrando su avance (regla de Miguel del 10/08). Ademas el gate de
-- la oficial deja fuera al coordinador y el de Metas no.
--
-- MEDIDO EN PRODUCCION EL 23/09 (solo lectura): Metas y la oficial ya daban lo
-- mismo persona por persona — 17/17 en septiembre y 16/16 en agosto
-- (conversion_real = conversion_pct, resueltos = divisor, numerador, cierres y
-- deuda). Esta migracion NO MUEVE NI UN NUMERO hoy; el postflight lo exige
-- comparando cada respuesta de las cuatro puertas, para cada persona del
-- equipo y el lector global, en el mes vigente y el anterior.
--
-- LO UNICO QUE CAMBIA EN LOS PAQUETES:
--   · La #8 (y la #7, que la hereda) declara `fuente: mensual` tambien en el
--     mes abierto: su cifra ya es la oficial, no un recalculo propio. El front
--     vivo (6bf0e84a) acepta los dos valores: `v.picklist(['mensual','rango_vivo'])`.
--   · LATENTE, hoy sin efecto (no hay ningun mes sellado ni deuda):
--       - Metas ensenara la deuda de quien no tuvo actividad en el mes, como ya
--         hacia la oficial (antes la perdia: su deuda iba dentro del CTE de
--         conversion y sin actividad no habia fila).
--       - La lista fuera del ranking publica, para cada persona, lo mismo que la
--         oficial: NETO a quien la oficial nombra y BRUTO a quien suma sin nombre.
--         Antes era bruto para todos (cara del defecto C2, auditoria del 21/09).
--
-- SEGURIDAD. Las dos piezas nuevas son SECURITY INVOKER (el estandar de la
-- casa): solo las llaman puertas DEFINER que ya autorizaron, y su EXECUTE queda
-- solo para postgres. La pieza RECHAZA un mes sellado: su cifra es la foto, y
-- recalcularla en vivo es el defecto C1. Y no sirve para el cierre de mes: el
-- sello descuenta la deuda al saldar, y aqui se descontaria dos veces.
--
-- CENSO. La oficial esta censada (clase analitica): se re-sella su huella con la
-- normalizacion del propio censo y se refresca el sello de la lista, en esta
-- transaccion. La #7, la #8 y las piezas nuevas siguen FUERA del censo.
--
-- AISLAMIENTO. REPEATABLE READ: el antes y el despues ven una sola foto, asi que
-- el commit de otra sesion (el backfill de conversion) no puede fabricar un falso
-- movimiento entre las dos.
--
-- FIJADO EN EL PREFLIGHT, md5(pg_get_functiondef) de los cuerpos revisados:
--   · crm.conversion_mensual_sin_cartera_fn  e2e2bf8fe3c71620a3db01de3cddc33b
--   · crm.cumplimiento_metas_sin_cartera_fn  5ae6fb2a02b63658b76b7c368c0c8588
--   · crm.cumplimiento_metas_fn              0bde18875efbb757801633571e558ca2
--   · huella del censo de la oficial         e8308294375859236ecf03e8133c176e
--
-- REVERSA: `supabase/scripts/conversion/reversa-una-sola-pieza.sql` — vuelve a
-- declarar los tres cuerpos EXACTOS de antes, restaura huella, razon y sello del
-- censo, los tres COMMENT ON, y retira las dos piezas. Todo en una transaccion.
-- =========================================================================

begin isolation level repeatable read;

set local statement_timeout = '300s';
set local lock_timeout = '5s';
lock table private.analitica_leads_citas_exenciones,
           private.analitica_lc_sello in share row exclusive mode;

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT: los cuerpos se acreditan por IDENTIDAD, no por fragmentos.
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_md5 text;
  v_ok text;
  r record;
begin
  for r in
    select * from (values
      ('crm.conversion_mensual_sin_cartera_fn(date)', 'e2e2bf8fe3c71620a3db01de3cddc33b'),
      ('crm.cumplimiento_metas_sin_cartera_fn(date)', '5ae6fb2a02b63658b76b7c368c0c8588'),
      ('crm.cumplimiento_metas_fn(date)',             '0bde18875efbb757801633571e558ca2')
    ) t(objeto, esperado)
  loop
    select md5(pg_get_functiondef(p.oid)) into v_md5
      from pg_proc p where p.oid = to_regprocedure(r.objeto);
    if v_md5 is distinct from r.esperado then
      raise exception 'PREFLIGHT: % viva NO es la revisada (md5 %). Revisar antes de tocarla.',
        r.objeto, coalesce(v_md5, 'no existe');
    end if;
  end loop;

  if to_regprocedure('private.conversion_neta_por_vendedor(date,boolean,uuid[])') is not null
     or to_regprocedure('private.roster_conversion_mensual(date,boolean,uuid[])') is not null then
    raise exception 'PREFLIGHT: una de las dos piezas ya existe; alguien la creo antes que esta migracion';
  end if;

  if to_regprocedure('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)') is null
     or to_regprocedure('private.ajuste_pendiente_por_vendedor()') is null
     or to_regprocedure('private.conversion_con_ajuste(numeric,numeric)') is null
     or to_regprocedure('private.roster_metas_vendedores()') is null
     or to_regprocedure('private.peso_referido_conversion(date)') is null
     or to_regprocedure('private.huella_exenciones_analitica_lc()') is null then
    raise exception 'PREFLIGHT: falta una de las funciones que las piezas llaman';
  end if;

  -- El trinquete tiene que estar en VERDE antes: re-sellar la lista al final
  -- solo puede bendecir lo que hace esta migracion, nunca un cambio ajeno.
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'PREFLIGHT: el trinquete ya estaba en rojo: %', v_ok;
  end if;

  if (select e.huella from private.analitica_leads_citas_exenciones e
       where e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)')
     is distinct from 'e8308294375859236ecf03e8133c176e' then
    raise exception 'PREFLIGHT: la declaracion de la oficial en el censo no es la esperada';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- (b) FOTO DE ANTES: cada respuesta de las cuatro puertas, para cada persona del
--     equipo (activa o no) y cada lector global, en el mes vigente y el anterior.
--     Un error se guarda por su codigo: el gate tambien tiene que quedar igual.
-- ---------------------------------------------------------------------------
create temp table _pieza_antes (
  identidad uuid, mes date, puerta text, payload jsonb,
  primary key (identidad, mes, puerta)
) on commit drop;
create temp table _pieza_despues (like _pieza_antes including all) on commit drop;
create temp table _pieza_atributos (
  objeto text primary key, dueno text, definer boolean, vol "char", cfg text[], acl jsonb
) on commit drop;

insert into _pieza_atributos
select p.oid::regprocedure::text, p.proowner::regrole::text, p.prosecdef, p.provolatile, p.proconfig,
       (select jsonb_agg(jsonb_build_array(a.grantee::regrole::text, a.privilege_type)
                         order by a.grantee::regrole::text, a.privilege_type)
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
  from pg_proc p
 where p.oid in ('crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure,
                 'crm.cumplimiento_metas_sin_cartera_fn(date)'::regprocedure,
                 'crm.cumplimiento_metas_fn(date)'::regprocedure);

do $antes$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_claim_sub text := current_setting('request.jwt.claim.sub', true);
  v_id uuid; v_mes date; v_puerta text; v_pl jsonb;
  v_vigente date := date_trunc('month', (now() at time zone 'America/Lima'))::date;
begin
  for v_id in
    select e.perfil_id from crm.equipo e
    union
    select p.id from public.perfiles p where p.rol = 'directorio' and p.activo is true
  loop
    -- auth.uid() mira PRIMERO la claim legada `request.jwt.claim.sub`: se vacia,
    -- y se exige que la identidad EFECTIVA sea la pedida antes de fotografiar.
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_id, 'role', 'authenticated')::text, true);
    if (select auth.uid()) is distinct from v_id then
      raise exception 'FOTO: la identidad efectiva (%) no es la pedida (%)', (select auth.uid()), v_id;
    end if;
    foreach v_mes in array array[v_vigente, (v_vigente - interval '1 month')::date] loop
      foreach v_puerta in array array['oficial', 'oficial_cartera', 'metas_sin_cartera', 'metas'] loop
        begin
          v_pl := case v_puerta
            when 'oficial'           then crm.conversion_mensual_sin_cartera_fn(v_mes)
            when 'oficial_cartera'   then crm.conversion_mensual_fn(v_mes)
            when 'metas_sin_cartera' then crm.cumplimiento_metas_sin_cartera_fn(v_mes)
            else crm.cumplimiento_metas_fn(v_mes)
          end;
        exception when others then
          v_pl := jsonb_build_object('_error', sqlstate);
        end;
        insert into _pieza_antes values (v_id, v_mes, v_puerta, v_pl);
      end loop;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_claim_sub, ''), true);
end;
$antes$;

-- ---------------------------------------------------------------------------
-- (c) NUCLEO: las dos piezas nuevas.
-- ---------------------------------------------------------------------------
create function private.roster_conversion_mensual(
  p_periodo date, p_global boolean, p_visibles uuid[]
)
returns table (vendedor_id uuid, supervisor_id uuid)
language sql
stable
set search_path = ''
as $function$
  -- El mes VIGENTE nombra al roster operativo de hoy. Un mes ANTERIOR que sigue
  -- abierto (la ventana de ajuste) nombra a la ultima publicacion de metas de ESE
  -- mes: aplicarle el roster de hoy borraria justo a quien se fue.
  select r.vendedor_id, r.supervisor_id
    from private.roster_metas_vendedores() r
   where p_periodo >= date_trunc('month', now() at time zone 'America/Lima')::date
     and (p_global or r.vendedor_id = any(p_visibles))
  union all
  select mv.vendedor_id, mv.supervisor_id
    from crm.metas_vendedor mv
   where p_periodo < date_trunc('month', now() at time zone 'America/Lima')::date
     and mv.meta_periodo_id = (
           select mp.id
             from crm.meta_periodos mp
            where mp.periodo = p_periodo
            order by mp.revision desc
            limit 1)
     and (p_global or mv.vendedor_id = any(p_visibles))
$function$;

comment on function private.roster_conversion_mensual(date, boolean, uuid[]) is
  'Quien sale NOMBRADO en la conversion mensual oficial de un mes: el mes vigente, el roster '
  'operativo (private.roster_metas_vendedores); un mes anterior aun abierto (ventana de ajuste), '
  'la ultima publicacion de metas de ESE mes. Recorta por ambito con p_global / p_visibles. Una '
  'sola regla, que usan crm.conversion_mensual_sin_cartera_fn y la lista fuera del ranking de '
  'crm.cumplimiento_metas_fn. Solo lectura, SECURITY INVOKER, EXECUTE solo postgres.';

revoke all on function private.roster_conversion_mensual(date, boolean, uuid[])
  from public, anon, authenticated, service_role;

create function private.conversion_neta_por_vendedor(
  p_periodo date, p_global boolean, p_visibles uuid[]
)
returns table (
  analista_id uuid,
  en_nucleo boolean,
  divisor integer,
  divisor_aproximado integer,
  divisor_por_motivo jsonb,
  cierres_no_referidos integer,
  cierres_referidos integer,
  cierres_de_arrastre integer,
  numerador_bruto numeric,
  ajuste_pendiente numeric,
  ajuste_origenes jsonb,
  numerador numeric,
  conversion_pct numeric,
  procedencia jsonb,
  referidos_recibidos integer,
  referidos_aporta_pct numeric
)
language plpgsql
stable
set search_path = ''
as $function$
#variable_conflict use_column
declare
  v_ini timestamptz;
  v_fin timestamptz;
begin
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes' using errcode = '22023';
  end if;
  -- Un mes SELLADO no se recalcula: su cifra es la foto de crm.periodos_cerrados,
  -- que cada puerta lee por su rama sellada. Recalcularlo aqui es el defecto C1.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    raise exception 'El mes % esta sellado: se sirve su foto, no se recalcula',
      pg_catalog.to_char(p_periodo, 'YYYY-MM') using errcode = '22023';
  end if;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  return query
  with base as materialized (
    -- `en_nucleo` marca que la fila viene del nucleo, tambien la de produccion
    -- sin analista (analista_id nulo), que ninguna comparacion de uuid distingue.
    select true as en_nucleo, cm.*
      from private.conversion_mensual_por_vendedor(
             v_ini, v_fin, p_global, p_visibles,
             private.peso_referido_conversion(p_periodo)) cm
  ), pendientes as materialized (
    -- Lo que cada vendedor arrastra de meses YA CERRADOS: cierres anulados
    -- despues de pagar. Se descuenta aqui, en la LECTURA, y nunca dentro del
    -- nucleo ni en el cierre de mes: el sello ya lo aplica al saldar
    -- (private.saldar_ajustes) y se descontaria dos veces.
    select ap.vendedor_id, ap.numerador as pendiente, ap.origenes
      from private.ajuste_pendiente_por_vendedor() ap
     where p_global or ap.vendedor_id = any(p_visibles)
  )
  -- FULL JOIN: quien tiene deuda y ninguna actividad en el mes tambien sale,
  -- con `en_nucleo = false`, para que la deuda no se pierda en ninguna puerta.
  select
    coalesce(b.analista_id, pd.vendedor_id),
    coalesce(b.en_nucleo, false),
    coalesce(b.divisor, 0),
    coalesce(b.divisor_aproximado, 0),
    coalesce(b.divisor_por_motivo, '{}'::jsonb),
    coalesce(b.cierres_no_referidos, 0),
    coalesce(b.cierres_referidos, 0),
    coalesce(b.cierres_de_arrastre, 0),
    b.numerador,
    coalesce(pd.pendiente, 0::numeric),
    coalesce(pd.origenes, '[]'::jsonb),
    -- NETO con suelo en cero; el bruto sigue siendo `numerador_bruto`.
    private.conversion_con_ajuste(b.numerador, pd.pendiente),
    -- El porcentaje se calcula sobre el NETO: el que trae el nucleo es del bruto.
    case when coalesce(b.divisor, 0) > 0
      then round(100.0 * private.conversion_con_ajuste(b.numerador, pd.pendiente)
                 / coalesce(b.divisor, 0), 2) end,
    coalesce(b.procedencia, '[]'::jsonb),
    coalesce(b.referidos_recibidos, 0),
    b.referidos_aporta_pct
  from base b
  full join pendientes pd on pd.vendedor_id = b.analista_id;
end;
$function$;

comment on function private.conversion_neta_por_vendedor(date, boolean, uuid[]) is
  'LA CIFRA DE CONVERSION POR PERSONA de un mes ABIERTO, en un solo sitio: nucleo '
  '(private.conversion_mensual_por_vendedor), deuda de meses ya pagados '
  '(private.ajuste_pendiente_por_vendedor), neto con suelo en cero (private.conversion_con_ajuste) '
  'y porcentaje sobre el neto. Devuelve tambien a quien solo tiene deuda (en_nucleo = false) y el '
  'bruto (numerador_bruto). La usan la oficial (crm.conversion_mensual_sin_cartera_fn) y Metas '
  '(crm.cumplimiento_metas_sin_cartera_fn y la lista fuera del ranking de crm.cumplimiento_metas_fn). '
  'Un mes SELLADO se rechaza con 22023: su cifra es la foto. NO usar en el cierre de mes: el sello '
  'descuenta al saldar y aqui se descontaria dos veces. SECURITY INVOKER, EXECUTE solo postgres.';

revoke all on function private.conversion_neta_por_vendedor(date, boolean, uuid[])
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (d) PUERTAS: dejan de calcular. Cuerpos generados POR ANCLAS sobre los vivos
--     acreditados arriba; cada cambio se lee en el diff del ledger.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.conversion_mensual_sin_cartera_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_alcance text;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_mes_actual date := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_suelo timestamptz;
  v_suelo_mes date;
  v_medible boolean;
  v_motivo_no_medible text;
  v_motivo_roster text;
  v_es_historico_abierto boolean := false;
  v_payload jsonb;
  v_cierre crm.periodos_cerrados%rowtype;
begin
  -- 1) GATE EXPLICITO, ANTES DE TOCAR NINGUN DATO. Nunca RLS implicita: esta
  --    funcion es SECURITY DEFINER y las policies no se evaluan. ALLOWLIST, no
  --    «rol_crm is not null»: ese idioma (el de cumplimiento_metas_fn) dejaria
  --    pasar al COORDINADOR, que aqui esta denegado por contrato.
  --    Orden deliberado: un actor denegado recibe 42501 aunque el periodo sea
  --    basura, para que el codigo de error no funcione como oraculo.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- 2) Validacion del periodo.
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;

  -- 3) ¿MES CERRADO? Entonces se sirve la foto y no se calcula nada. Va aqui,
  --    despues del gate y de validar el periodo, para que un mes cerrado
  --    responda igual de fail-closed que uno abierto.
  select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  if found then
    with visibles as (
      select f.* from private.cierre_mes_visible(p_periodo, v_uid) f
    ), fuera_foto as materialized (
      select e.value as fila
      from jsonb_array_elements(
        coalesce(v_cierre.cobertura->'fuera_ranking', '[]'::jsonb)
      ) e
      where v_global and e.value->'conversion' <> 'null'::jsonb
      union all
      select jsonb_build_object('conversion', v_cierre.cobertura->'conversion_sin_analista')
      where v_global and v_cierre.cobertura ? 'conversion_sin_analista'
    ), resumen as (
      -- El total suma la foto rankeable y el agregado empresarial congelado.
      -- Las identidades externas nunca se materializan como responsables.
      select
        count(*)::int as analistas,
        (coalesce(sum(v.divisor), 0)
          + coalesce((select sum((f.fila#>>'{conversion,divisor}')::int)
                      from fuera_foto f), 0))::int as divisor,
        (coalesce(sum(v.divisor_aproximado), 0)
          + coalesce((select sum((f.fila#>>'{conversion,divisor_aproximado}')::int)
                      from fuera_foto f), 0))::int as divisor_aproximado,
        (coalesce(sum(v.cierres_no_referidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_no_referidos}')::int)
                      from fuera_foto f), 0))::int as cierres_no_referidos,
        (coalesce(sum(v.cierres_referidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_referidos}')::int)
                      from fuera_foto f), 0))::int as cierres_referidos,
        (coalesce(sum(v.cierres_de_arrastre), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_de_arrastre}')::int)
                      from fuera_foto f), 0))::int as cierres_de_arrastre,
        (coalesce(sum(v.referidos_recibidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,referidos_recibidos}')::int)
                      from fuera_foto f), 0))::int as referidos_recibidos,
        (coalesce(sum(v.numerador), 0::numeric)
          + coalesce((select sum((f.fila#>>'{conversion,numerador}')::numeric)
                      from fuera_foto f), 0::numeric)) as numerador
      from visibles v
    ), motivos as (
      select e.key as motivo, sum(e.value::int)::int as n
      from (
        select v.divisor_por_motivo from visibles v
        union all
        select coalesce(f.fila#>'{conversion,divisor_por_motivo}', '{}'::jsonb)
        from fuera_foto f
      ) dm, jsonb_each_text(dm.divisor_por_motivo) e
      group by e.key
    )
    select jsonb_build_object(
      'version', 1,
      'generado_en', v_ahora,
      'alcance', v_alcance,
      'periodo', jsonb_build_object(
        'mes', pg_catalog.to_char(p_periodo, 'YYYY-MM'),
        'mes_nombre', private.etiqueta_mes_es(p_periodo),
        'anio', extract(year from p_periodo)::int,
        'zona', 'America/Lima',
        'desde', p_periodo::timestamp at time zone 'America/Lima',
        'hasta', (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'
      ),
      'ponderacion', jsonb_build_object(
        'referido', v_cierre.ponderacion_referido,
        'renovacion', case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
          then v_cierre.ponderacion_referido else 1 end,
        'fuente', 'crm.conversion_pesos'
      ),
      -- La fuente indica la semántica sellada. Las fotos anteriores no se
      -- reescriben ni se hacen pasar por llegadas únicas.
      'fuentes', jsonb_build_object(
        'divisor', case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
          then 'crm.leads.creado_en' else 'crm.lead_asignaciones.asignado_en' end,
        'numerador', 'crm.lead_asignaciones.resultado_en',
        'referido', case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
          then 'crm.leads.origen' else 'crm.lead_asignaciones.origen' end
      ),
      -- LA CLAVE NUEVA. El front la usa para decir «cerrado el 10/09, ya no
      -- cambia»; un cliente viejo la ignora y no se entera de nada.
      'cierre', jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cierre.cerrado_en,
        'automatico', v_cierre.automatico
      ),
      'cobertura', jsonb_build_object(
        'medible', coalesce((v_cierre.cobertura->>'medible')::boolean, false),
        'suelo_historico', v_cierre.cobertura->>'suelo_historico',
        'motivo_no_medible', v_cierre.cobertura->>'motivo_no_medible',
        'divisor_aproximado', (select r.divisor_aproximado from resumen r),
        'divisor_por_motivo', coalesce(
          (select jsonb_object_agg(m.motivo, m.n) from motivos m), '{}'::jsonb),
        -- La sonda de cierres sin episodio se calculaba sobre datos vivos; en un
        -- mes sellado no se recalcula (mentiria sobre el momento del sello) y se
        -- declara en cero, que es lo que la foto puede afirmar.
        'cierres_sin_episodio', 0,
        -- La producción de supervisores u otras identidades no rankeables se
        -- conserva en el total, pero no se convierte en una fila de analista.
        'fuera_de_roster', jsonb_build_object(
          'analistas', (select count(*)::int from fuera_foto f where f.fila->>'persona_id' is not null),
          'divisor', coalesce((select sum(
            (f.fila#>>'{conversion,divisor}')::int) from fuera_foto f), 0)::int,
          'cierres', coalesce((select sum(
            (f.fila#>>'{conversion,cierres_no_referidos}')::int
            + (f.fila#>>'{conversion,cierres_referidos}')::int
          ) from fuera_foto f), 0)::int,
          'numerador', coalesce((select sum(
            (f.fila#>>'{conversion,numerador}')::numeric
          ) from fuera_foto f), 0::numeric))
      ),
      'total', (
        select jsonb_build_object(
          'analistas', r.analistas,
          'divisor', r.divisor,
          'cierres_no_referidos', r.cierres_no_referidos,
          'cierres_referidos', r.cierres_referidos,
          'cierres_de_arrastre', r.cierres_de_arrastre,
          'referidos_recibidos', r.referidos_recibidos,
          'numerador', r.numerador,
          'conversion_pct', case when r.divisor > 0
            then round(100.0 * r.numerador / r.divisor, 2) end,
          'referidos_aporta_pct', case when r.divisor > 0
            then round(100.0 * v_cierre.ponderacion_referido * r.cierres_referidos / r.divisor, 2) end
        ) from resumen r),
      'responsables', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'vendedor_id', v.vendedor_id,
            'supervisor_id', v.supervisor_id,
            'divisor', v.divisor,
            'cierres_no_referidos', v.cierres_no_referidos,
            'cierres_referidos', v.cierres_referidos,
            'cierres_de_arrastre', v.cierres_de_arrastre,
            'numerador', v.numerador,
            'conversion_pct', v.conversion_pct,
            'estado', v.estado,
            'procedencia', v.procedencia,
            'referidos', jsonb_build_object(
              'recibidos', v.referidos_recibidos,
              'cerrados', v.cierres_referidos,
              'dados_de_alta', v.referidos_dados_de_alta,
              'aporta_pct', v.referidos_aporta_pct
            ),
            -- En un mes cerrado ya no queda nada pendiente de ese mes: lo que se
            -- pudo descontar se descontó al sellar, y lo que no, sigue vivo en
            -- el mes siguiente. Por eso `pendiente` es 0 y `aplicado` no.
            'ajuste', jsonb_build_object(
              'aplicado', v.ajuste_numerador,
              'pendiente', 0,
              'origenes', '[]'::jsonb)
          )
          order by v.conversion_pct desc nulls last,
                   v.numerador desc, v.divisor desc, v.vendedor_id
        )
        from visibles v
      ), '[]'::jsonb)
    ) into v_payload;

    -- ⚠️ SIN `filtrar_desglose_sujetos_crm`. Esa defensa descarta a quien hoy no
    -- sea vendedor, y sobre una foto de pago borraria justo a quien se fue del
    -- equipo — el caso que el sello congela el nombre para conservar.
    return v_payload;
  end if;

  -- 4) Mes ABIERTO. Quien sale NOMBRADO lo decide una sola regla del nucleo,
  -- `private.roster_conversion_mensual`: el mes vigente conserva el roster
  -- operativo; uno anterior aun abierto (ventana de ajuste), la ultima
  -- publicacion de ESE mes.
  v_es_historico_abierto := p_periodo < v_mes_actual;

  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  v_factor := private.peso_referido_conversion(p_periodo);

  select min(la.asignado_en)
    into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;

  v_suelo_mes := date_trunc('month', v_suelo at time zone 'America/Lima')::date;

  if v_suelo is null then
    v_medible := false;
    v_motivo_no_medible := 'sin_ledger';
  elsif v_ini < v_suelo then
    v_medible := false;
    v_motivo_no_medible := case
      when p_periodo < v_suelo_mes then 'anterior_al_ledger'
      else 'mes_parcial'
    end;
  else
    v_medible := true;
    v_motivo_no_medible := null;
  end if;

  if v_alcance = 'propio'
     and not exists (
       select 1 from private.roster_conversion_mensual(p_periodo, false, array[v_uid]) r
        where r.vendedor_id = v_uid
     ) then
    select vs.motivo
      into v_motivo_roster
    from private.vendedores_sin_supervisor() vs
    where vs.vendedor_id = v_uid;

    v_medible := false;
    v_motivo_no_medible := coalesce(v_motivo_roster, 'sin_supervisor');
  end if;

  with roster as materialized (
    select r.vendedor_id, r.supervisor_id
    from private.roster_conversion_mensual(p_periodo, v_global, v_visibles) r
  ),
  base as materialized (
    -- LA CIFRA POR PERSONA sale de UNA sola pieza del nucleo, la misma que usa
    -- Metas: bruto, deuda de meses ya pagados, neto y porcentaje sobre el neto.
    select n.*
    from private.conversion_neta_por_vendedor(p_periodo, v_global, v_visibles) n
  ),
  alta_referidos as materialized (
    select l.creado_por as analista_id, count(*)::int as dados_de_alta
    from crm.leads l
    where l.origen = 'referido'
      and l.creado_en >= v_ini
      and l.creado_en < v_fin
      and l.creado_por is not null
      and (v_global or l.creado_por = any(v_visibles))
    group by l.creado_por
  ),
  filas as (
    select
      r.vendedor_id,
      r.supervisor_id,
      coalesce(b.divisor, 0) as divisor,
      coalesce(b.divisor_aproximado, 0) as divisor_aproximado,
      coalesce(b.divisor_por_motivo, '{}'::jsonb) as divisor_por_motivo,
      coalesce(b.cierres_no_referidos, 0) as cierres_no_referidos,
      coalesce(b.cierres_referidos, 0) as cierres_referidos,
      coalesce(b.cierres_de_arrastre, 0) as cierres_de_arrastre,
      -- NETO de lo que se le debe descontar y porcentaje sobre el neto, tal
      -- como los sirve la pieza. Quien no tiene fila (ni actividad ni deuda)
      -- queda en cero y sin porcentaje, igual que antes.
      coalesce(b.numerador, 0::numeric) as numerador,
      b.conversion_pct,
      coalesce(b.ajuste_pendiente, 0::numeric) as ajuste_pendiente,
      coalesce(b.ajuste_origenes, '[]'::jsonb) as ajuste_origenes,
      coalesce(b.procedencia, '[]'::jsonb) as procedencia,
      coalesce(b.referidos_recibidos, 0) as referidos_recibidos,
      b.referidos_aporta_pct,
      coalesce(a.dados_de_alta, 0) as dados_de_alta
    from roster r
    left join base b on b.analista_id = r.vendedor_id
    left join alta_referidos a on a.analista_id = r.vendedor_id
  ),
  fuera as (
    -- Quien produjo dentro del ambito pero NO esta en el roster: el que se dio
    -- de baja a mitad de mes, el supervisor con cartera propia, el vendedor
    -- sin supervisor. Sigue siendo un AGREGADO SIN IDENTIDAD (ningun uuid
    -- sale), pero desde D8 (Miguel, 27/08/2026) ademas de declararse en
    -- `cobertura.fuera_de_roster` se SUMA al total: por eso aqui se agregan
    -- tambien los desgloses que `resumen` necesita. BRUTO a proposito
    -- (`numerador_bruto`): el ajuste de meses ya pagados se descuenta por fila
    -- del roster y el ex-roster no tiene fila donde descontarlo. Solo cuenta
    -- quien aparece en el nucleo (`en_nucleo`): una deuda sin actividad no es
    -- produccion.
    select
      count(b.analista_id)::int as analistas,
      coalesce(sum(b.divisor), 0)::int as divisor,
      coalesce(sum(b.cierres_no_referidos + b.cierres_referidos), 0)::int as cierres,
      coalesce(sum(b.numerador_bruto), 0::numeric) as numerador,
      coalesce(sum(b.divisor_aproximado), 0)::int as divisor_aproximado,
      coalesce(sum(b.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(b.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(b.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
      coalesce(sum(b.referidos_recibidos), 0)::int as referidos_recibidos
    from base b
    where b.en_nucleo
      and not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
  ),
  motivos_totales as (
    -- D8: el desglose por motivo cubre TODO el divisor que el total cuenta —
    -- las filas del roster y las del agregado fuera de roster. Sin la segunda
    -- pierna, `divisor_por_motivo` dejaria de cuadrar con `total.divisor`.
    select e.key as motivo, sum(e.value::int)::int as n
    from (
      select f.divisor_por_motivo from filas f
      union all
      select coalesce(b.divisor_por_motivo, '{}'::jsonb)
      from base b
      where b.en_nucleo
        and not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
    ) dm, jsonb_each_text(dm.divisor_por_motivo) e
    group by e.key
  ),
  sonda as (
    select count(*)::int as cierres_sin_episodio
    from crm.leads l
    where l.etapa = 'convertido'
      and l.origen in ('landing', 'formulario', 'referido')
      and l.convertido_en >= v_ini
      and l.convertido_en < v_fin
      and (v_global
           or l.vendedor_id = any(v_visibles)
           or l.asignado_supervisor_id = any(v_visibles)
           or exists (
             select 1
             from crm.lead_asignaciones lv
             where lv.lead_id = l.id
               and lv.analista_id = any(v_visibles)
           ))
      and not exists (
        select 1
        from crm.lead_asignaciones la
        where la.lead_id = l.id
          and la.resultado = 'convertido'
          and coalesce(la.resultado_en, la.finalizado_en) >= v_ini
          and coalesce(la.resultado_en, la.finalizado_en) < v_fin
      )
  ),
  resumen as (
    -- D8 (Miguel, 27/08/2026): el total de empresa INCLUYE la produccion fuera
    -- de roster — el mismo agregado sin identidad que declara
    -- `cobertura.fuera_de_roster`. Con el agregado en cero el total queda
    -- identico al de antes. Quien sale del roster a mitad de mes cuenta aqui
    -- entero (el roster es estado ACTUAL, no historico): su mes se mueve al
    -- agregado y su fila desaparece de `responsables`; con esto el mes abierto
    -- dice lo mismo que dira su foto al sellarse, donde todo el que produjo
    -- entra con nombre (20260815003742, «no hay fuera de roster en una foto»).
    select
      count(*)::int as analistas,
      (coalesce(sum(f.divisor), 0)
        + (select fr.divisor from fuera fr))::int as divisor,
      (coalesce(sum(f.divisor_aproximado), 0)
        + (select fr.divisor_aproximado from fuera fr))::int as divisor_aproximado,
      (coalesce(sum(f.cierres_no_referidos), 0)
        + (select fr.cierres_no_referidos from fuera fr))::int as cierres_no_referidos,
      (coalesce(sum(f.cierres_referidos), 0)
        + (select fr.cierres_referidos from fuera fr))::int as cierres_referidos,
      (coalesce(sum(f.cierres_de_arrastre), 0)
        + (select fr.cierres_de_arrastre from fuera fr))::int as cierres_de_arrastre,
      (coalesce(sum(f.referidos_recibidos), 0)
        + (select fr.referidos_recibidos from fuera fr))::int as referidos_recibidos,
      (coalesce(sum(f.numerador), 0::numeric)
        + (select fr.numerador from fuera fr)) as numerador
    from filas f
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'alcance', v_alcance,
    'periodo', jsonb_build_object(
      'mes', pg_catalog.to_char(p_periodo, 'YYYY-MM'),
      'mes_nombre', private.etiqueta_mes_es(p_periodo),
      'anio', extract(year from p_periodo)::int,
      'zona', 'America/Lima',
      'desde', v_ini,
      'hasta', v_fin
    ),
    'ponderacion', jsonb_build_object(
      'referido', v_factor,
      'renovacion', v_factor,
      'fuente', 'crm.conversion_pesos'
    ),
    'fuentes', jsonb_build_object(
      'divisor', 'crm.leads.creado_en',
      'numerador', 'crm.lead_asignaciones.resultado_en',
      'referido', 'crm.leads.origen'
    ),
    -- Mes abierto: se dice explicitamente que NO esta cerrado, para que la
    -- pantalla no tenga que deducirlo de la ausencia de la clave.
    'cierre', jsonb_build_object('cerrado', false),
    'cobertura', jsonb_build_object(
      'medible', v_medible,
      'suelo_historico', v_suelo,
      'motivo_no_medible', v_motivo_no_medible,
      'divisor_aproximado', (select r.divisor_aproximado from resumen r),
      'divisor_por_motivo', coalesce(
        (select jsonb_object_agg(mt.motivo, mt.n) from motivos_totales mt),
        '{}'::jsonb),
      'cierres_sin_episodio', (select s.cierres_sin_episodio from sonda s),
      'fuera_de_roster', (
        select jsonb_build_object(
          'analistas', fr.analistas,
          'divisor', fr.divisor,
          'cierres', fr.cierres,
          'numerador', fr.numerador
        ) from fuera fr)
    ),
    'total', (
      select jsonb_build_object(
        'analistas', r.analistas,
        'divisor', r.divisor,
        'cierres_no_referidos', r.cierres_no_referidos,
        'cierres_referidos', r.cierres_referidos,
        'cierres_de_arrastre', r.cierres_de_arrastre,
        'referidos_recibidos', r.referidos_recibidos,
        'numerador', r.numerador,
        'conversion_pct', case when r.divisor > 0
          then round(100.0 * r.numerador / r.divisor, 2) end,
        'referidos_aporta_pct', case when r.divisor > 0
          then round(100.0 * v_factor * r.cierres_referidos / r.divisor, 2) end
      ) from resumen r),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', f.vendedor_id,
          'supervisor_id', f.supervisor_id,
          'divisor', f.divisor,
          'cierres_no_referidos', f.cierres_no_referidos,
          'cierres_referidos', f.cierres_referidos,
          'cierres_de_arrastre', f.cierres_de_arrastre,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          'estado', case
            when f.divisor > 0 then 'medible'
            when f.referidos_recibidos > 0 then 'solo_referidos'
            when (f.cierres_no_referidos + f.cierres_referidos) > 0 then 'solo_arrastre'
            else 'sin_actividad'
          end,
          'procedencia', f.procedencia,
          'referidos', jsonb_build_object(
            'recibidos', f.referidos_recibidos,
            'cerrados', f.cierres_referidos,
            'dados_de_alta', f.dados_de_alta,
            'aporta_pct', f.referidos_aporta_pct
          ),
          -- Lo que se le esta descontando de meses ya pagados, con su
          -- procedencia. Un numero que baja sin explicacion es una llamada a
          -- soporte; con el motivo al lado es una consecuencia.
          'ajuste', jsonb_build_object(
            'pendiente', f.ajuste_pendiente,
            'origenes', f.ajuste_origenes
          )
        )
        order by f.conversion_pct desc nulls last,
                 f.numerador desc,
                 f.divisor desc,
                 f.vendedor_id
      )
      from filas f
    ), '[]'::jsonb)
  ) into v_payload;

  -- El roster historico ya fue validado por su publicacion mensual. Aplicarle
  -- el rol/actividad de hoy borraria precisamente a una baja de ese mes.
  if v_es_historico_abierto then
    return v_payload;
  end if;
  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

CREATE OR REPLACE FUNCTION crm.cumplimiento_metas_sin_cartera_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
  v_factor numeric;
  v_cierre crm.periodos_cerrados%rowtype;
begin
  if v_uid is null
    or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_periodo is null or p_periodo<>date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode='22023';
  end if;

  -- MES CERRADO: se sirve la foto. Mismo recorte que la conversion, del mismo
  -- helper, para que las dos pantallas no puedan enseñar poblaciones distintas
  -- del mismo mes.
  select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  if found then
    select mp.publicada_en into v_publicada_en
    from crm.meta_periodos mp
    where mp.periodo = p_periodo and mp.revision = v_cierre.meta_revision;

    select jsonb_build_object(
      -- DECLARACION. RAMA DEL MES SELLADO: lo que se publica sale de la FOTO
      -- de `crm.periodos_cerrados`, no de un recalculo.
      'es_mes_calendario', true,
      'fuente', 'mensual',
      'sellado', true,
      'ajuste_aplicado', true,
      'version', 1, 'periodo', p_periodo, 'revision', v_cierre.meta_revision,
      'publicada_en', v_publicada_en,
      'fuentes_reales', jsonb_build_object(
        'capital_y_contratos', 'contratos_confirmados',
        'conversion', 'leads_recibidos_ponderado'
      ),
      'ponderacion_referido', v_cierre.ponderacion_referido,
      'cierre', jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cierre.cerrado_en,
        'automatico', v_cierre.automatico
      ),
      'vendedores', coalesce((
        select jsonb_agg(jsonb_build_object(
          'vendedor_id', v.vendedor_id, 'nombre', v.nombre_completo,
          'supervisor_id', v.supervisor_id, 'supervisor_nombre', v.supervisor_nombre,
          'conversion_objetivo', v.conversion_objetivo,
          'conversion_real', v.conversion_pct,
          'convertidos', v.cierres_no_referidos + v.cierres_referidos,
          'resueltos', v.divisor,
          'numerador', v.numerador,
          'cierres_no_referidos', v.cierres_no_referidos,
          'cierres_referidos', v.cierres_referidos,
          -- Lo que se le descontó al sellar por deudas de meses anteriores. El
          -- bruto se recupera sumándolo al numerador: la foto es auditable.
          'ajuste', jsonb_build_object(
            'aplicado', v.ajuste_numerador,
            'aplicado_pen', v.ajuste_pen,
            'aplicado_usd', v.ajuste_usd,
            'pendiente', 0),
          'detalles', v.detalles
        ) order by v.supervisor_nombre, v.nombre_completo)
        from private.cierre_mes_visible(p_periodo, v_uid) v
      ), '[]'::jsonb)
    ) into v_payload;
    return v_payload;
  end if;

  -- Mes ABIERTO: el comportamiento de siempre.
  v_ini:=p_periodo::timestamp at time zone 'America/Lima';
  v_fin:=(p_periodo+interval '1 month')::timestamp at time zone 'America/Lima';

  select mp.id,mp.revision,mp.publicada_en
    into v_periodo_id,v_revision,v_publicada_en
  from crm.meta_periodos mp where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision:=coalesce(v_revision,0);
  v_factor:=private.peso_referido_conversion(p_periodo);

  with reales as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), conversiones as (
    -- LA CIFRA POR PERSONA ya no se calcula aqui: sale de la MISMA pieza del
    -- nucleo que usa la oficial (crm.conversion_mensual_sin_cartera_fn), asi que
    -- Metas y Ranking no pueden enseñar dos porcentajes del mismo asesor. La
    -- pieza trae tambien la deuda de quien no tuvo actividad en el mes.
    select n.analista_id as vendedor_id,
      (n.cierres_no_referidos+n.cierres_referidos)::integer as convertidos,
      n.divisor::integer as resueltos,
      n.numerador,
      n.cierres_no_referidos,
      n.cierres_referidos,
      n.conversion_pct as conversion_real,
      n.ajuste_pendiente
    from private.conversion_neta_por_vendedor(p_periodo, true, '{}'::uuid[]) n
  ), visibles as (
    select mv.*,p.nombre_completo,s.nombre_completo as supervisor_nombre
    from crm.metas_vendedor mv
    join public.perfiles p on p.id=mv.vendedor_id
    join public.perfiles s on s.id=mv.supervisor_id
    where mv.meta_periodo_id=v_periodo_id
      and (private.es_lector_global()
        or mv.vendedor_id in (select private.vendedor_ids_visibles(v_uid)))
  )
  select jsonb_build_object(
    -- DECLARACION. RAMA DEL MES ABIERTO: la cifra la sirve la misma pieza del
    -- nucleo que la oficial (`private.conversion_neta_por_vendedor`), ya neta de
    -- la deuda. Por eso `mensual`: es la cifra oficial, no un recalculo propio.
    'es_mes_calendario', true,
    'fuente', 'mensual',
    'sellado', false,
    'ajuste_aplicado', true,
    'version',1,'periodo',p_periodo,'revision',v_revision,
    'publicada_en',v_publicada_en,
    'fuentes_reales',jsonb_build_object(
      'capital_y_contratos','contratos_confirmados',
      'conversion','leads_recibidos_ponderado'
    ),
    'ponderacion_referido',v_factor,
    'cierre', jsonb_build_object('cerrado', false),
    'vendedores',coalesce((select jsonb_agg(jsonb_build_object(
      'vendedor_id',mv.vendedor_id,'nombre',mv.nombre_completo,
      'supervisor_id',mv.supervisor_id,'supervisor_nombre',mv.supervisor_nombre,
      'conversion_objetivo',mv.conversion_objetivo,
      'conversion_real',cv.conversion_real,
      'convertidos',coalesce(cv.convertidos,0),'resueltos',coalesce(cv.resueltos,0),
      'numerador',coalesce(cv.numerador,0),
      'cierres_no_referidos',coalesce(cv.cierres_no_referidos,0),
      'cierres_referidos',coalesce(cv.cierres_referidos,0),
      'ajuste',jsonb_build_object('pendiente',coalesce(cv.ajuste_pendiente,0)),
      'detalles',(select jsonb_agg(jsonb_build_object(
        'categoria',d.categoria,'moneda',d.moneda,
        'capital_objetivo',d.capital_objetivo,
        'capital_real',coalesce(r.capital_real,0),
        'capital_cumplimiento_pct',case when d.capital_objetivo>0
          then round(100.0*coalesce(r.capital_real,0)/d.capital_objetivo,2) end,
        'contratos_objetivo',d.contratos_objetivo,
        'contratos_real',coalesce(r.contratos_real,0),
        'contratos_cumplimiento_pct',case when d.contratos_objetivo>0
          then round(100.0*coalesce(r.contratos_real,0)/d.contratos_objetivo,2) end
      ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
      from crm.metas_vendedor_detalle d
      left join reales r on r.vendedor_id=mv.vendedor_id
        and r.categoria=d.categoria and r.moneda=d.moneda
      where d.meta_vendedor_id=mv.id)
    ) order by mv.supervisor_nombre,mv.nombre_completo) from visibles mv
    left join conversiones cv on cv.vendedor_id=mv.vendedor_id),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.cumplimiento_metas_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
  v_base jsonb;
  v_vendedores jsonb;
  v_fuera_ranking jsonb := '[]'::jsonb;
  v_cerrado boolean;
  v_global boolean;
  v_periodo_id uuid;
  v_ini timestamptz;
  v_fin timestamptz;
begin
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_base := crm.cumplimiento_metas_sin_cartera_fn(p_periodo);
  v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);

  -- Solo Gerencia y el lector global reciben identidades fuera del ranking.
  -- Para un mes cerrado salen del JSON append-only del sello; para uno abierto
  -- se proyectan en vivo desde los mismos nucleos de conversion, produccion y
  -- cartera. Los demás roles reciben siempre un arreglo vacío.
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  if v_global and v_cerrado then
    select coalesce(pc.cobertura->'fuera_ranking', '[]'::jsonb)
      into v_fuera_ranking
    from crm.periodos_cerrados pc
    where pc.periodo = p_periodo;
  elsif v_global then
    v_ini := p_periodo::timestamp at time zone 'America/Lima';
    v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
    select mp.id into v_periodo_id
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;

    with conv as materialized (
      -- La MISMA pieza del nucleo que la oficial y que la #8. Solo quien aparece
      -- en el nucleo del mes: una deuda sin actividad no crea fila aqui.
      select n.*
      from private.conversion_neta_por_vendedor(p_periodo, true, '{}'::uuid[]) n
      where n.en_nucleo
    ), nombrados as materialized (
      -- A quien la oficial NOMBRA en `responsables` le publica el NETO; al resto
      -- lo suma BRUTO y sin nombre en `cobertura.fuera_de_roster`. Aqui se
      -- publica, para cada persona, lo mismo que la oficial (C2, auditoria 21/09).
      select r.vendedor_id
      from private.roster_conversion_mensual(p_periodo, true, '{}'::uuid[]) r
    ), prod as materialized (
      select r.*
      from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
    ), car as materialized (
      select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), personas as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
      union
      select p.vendedor_id from prod p where p.vendedor_id is not null
      union
      select c.vendedor_id from car c where c.vendedor_id is not null
    ), dentro as (
      select (e.value->>'vendedor_id')::uuid as persona_id
      from jsonb_array_elements(coalesce(v_base->'vendedores', '[]'::jsonb)) e
    ), fuera as (
      select
        p.persona_id,
        coalesce(nullif(btrim(pf.nombre_completo), ''),
                 '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
        coalesce(eq.rol_crm, 'fuera_equipo') as rol_crm,
        case
          when eq.rol_crm = 'vendedor' and sup.perfil_id is not null
            then 'analista_sin_meta'
          when eq.rol_crm = 'vendedor' then 'analista_sin_supervisor'
          when eq.rol_crm = 'supervisor' then 'supervisor'
          when eq.rol_crm = 'gerencia' then 'gerencia'
          else 'fuera_estructura'
        end as motivo
      from personas p
      left join crm.equipo eq on eq.perfil_id = p.persona_id
      left join crm.equipo sup
        on sup.perfil_id = eq.supervisor_id and sup.rol_crm = 'supervisor'
      left join public.perfiles pf on pf.id = p.persona_id
      where not exists (
        select 1 from dentro d where d.persona_id = p.persona_id
      )
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'persona_id', f.persona_id,
      'nombre', f.nombre,
      'rol_crm', f.rol_crm,
      'motivo', f.motivo,
      'conversion', case when cv.analista_id is null then null else jsonb_build_object(
        'divisor', coalesce(cv.divisor, 0),
        'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
        'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
        'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
        'cierres_referidos', coalesce(cv.cierres_referidos, 0),
        'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
        'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
        'numerador', case
          when exists (select 1 from nombrados nm where nm.vendedor_id = f.persona_id)
            then coalesce(cv.numerador, 0)
          else coalesce(cv.numerador_bruto, 0) end
      ) end,
      'detalles', det.detalles,
      'cartera', jsonb_build_object(
        'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
        'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
        'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
        'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
        'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
        'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
        'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
        'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
        'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
        'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
      )
    ) order by f.nombre, f.persona_id), '[]'::jsonb)
      into v_fuera_ranking
    from fuera f
    left join conv cv on cv.analista_id = f.persona_id
    left join car on car.vendedor_id = f.persona_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'categoria', d.categoria,
        'moneda', d.moneda,
        'capital_objetivo', 0,
        'capital_real', coalesce(pr.capital_real, 0),
        'capital_cumplimiento_pct', null,
        'contratos_objetivo', 0,
        'contratos_real', coalesce(pr.contratos_real, 0),
        'contratos_cumplimiento_pct', null,
        'capital_ajuste', 0,
        'contratos_ajuste', 0
      ) order by array_position(
        array['nuevo','renovacion','upgrade'], d.categoria
      ), d.moneda) as detalles
      from (values
        ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
        ('renovacion', 'PEN'), ('renovacion', 'USD'),
        ('upgrade', 'PEN'), ('upgrade', 'USD')
      ) d(categoria, moneda)
      left join prod pr on pr.vendedor_id = f.persona_id
        and pr.categoria = d.categoria and pr.moneda = d.moneda
    ) det on true;
  end if;

  with m as materialized (
    select x.*
    from private.metricas_cartera_por_vendedor(p_periodo) x
    where not v_cerrado
    union all
    select
      f.vendedor_id,
      (f.cartera->>'conversiones_clientes')::int,
      (f.cartera->>'conversiones_renovacion')::int,
      (f.cartera->>'conversiones_upgrade')::int,
      (f.cartera->>'operaciones_renovacion')::int,
      (f.cartera->>'operaciones_upgrade')::int,
      (f.cartera->>'capital_renovado_pen')::numeric,
      (f.cartera->>'capital_renovado_usd')::numeric,
      (f.cartera->>'capital_adicional_pen')::numeric,
      (f.cartera->>'capital_adicional_usd')::numeric,
      (f.cartera->>'renovaciones_sin_desglose')::int
    from private.cierre_mes_visible(p_periodo, v_uid) f
    where v_cerrado
  )
  select coalesce(jsonb_agg(
    jsonb_set(
      e.value,
      '{convertidos}',
      to_jsonb(coalesce((e.value->>'convertidos')::int, 0)
               + coalesce(m.conversiones_clientes, 0)),
      true
    ) order by e.ord
  ), '[]'::jsonb) into v_vendedores
  from jsonb_array_elements(coalesce(v_base->'vendedores','[]'::jsonb))
       with ordinality e(value, ord)
  left join m on m.vendedor_id = (e.value->>'vendedor_id')::uuid;

  v_base := jsonb_set(v_base, '{vendedores}', v_vendedores, true);
  return jsonb_set(v_base, '{fuera_ranking}', v_fuera_ranking, true);
end;
$function$;

comment on function crm.conversion_mensual_sin_cartera_fn(date) is
  'Nucleo mensual de conversion: mes vigente con roster operativo, historico abierto con la ultima '
  'publicacion de ese mes (las dos cosas las decide private.roster_conversion_mensual) y cerrado '
  'desde la foto sellada. La cifra por persona del mes abierto sale de '
  'private.conversion_neta_por_vendedor, la misma pieza que usa Metas. El total.analistas cuenta '
  'solo responsables rankeables; Gerencia conserva divisor, numerador, porcentaje y produccion '
  'fuera del ranking en el total empresarial.';

comment on function crm.cumplimiento_metas_sin_cartera_fn(date) is
  'Cumplimiento de metas SIN cartera, y motor del payload de crm.cumplimiento_metas_fn, que lo '
  'HEREDA (por eso declararla aqui declara tambien la de Metas y Ranking). Su poblacion es la de '
  'Metas (quien tiene meta publicada), pero la conversion de cada persona NO la calcula: en el mes '
  'SELLADO sale de la foto de crm.periodos_cerrados; en el ABIERTO, de '
  'private.conversion_neta_por_vendedor, la misma pieza del nucleo que usa la oficial. Por eso '
  'declara fuente=mensual en las dos ramas, con es_mes_calendario=true y ajuste_aplicado=true.';

comment on function crm.cumplimiento_metas_fn(date) is
  'Cumplimiento mensual sobre el nucleo existente. En abierto incorpora conversiones de cartera '
  'vivas; en cerrado las incorpora desde la misma foto mensual, sin recalcular el pasado. Solo '
  'Gerencia recibe fuera_ranking con la produccion identificada que no pertenece a analistas '
  'rankeables. Su conversion sale de private.conversion_neta_por_vendedor y publica, para cada '
  'persona, lo mismo que la oficial: NETO a quien la oficial nombra y BRUTO a quien suma sin nombre.';

-- ---------------------------------------------------------------------------
-- (e) Re-sellar la declaracion de la oficial con la normalizacion DEL CENSO
--     (cuerpo en `lower`, sin comentarios), que es la del propio assert.
-- ---------------------------------------------------------------------------
update private.analitica_leads_citas_exenciones e
   set huella = md5(regexp_replace(regexp_replace(
                      lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                      '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
       razon  = e.razon || ' Una sola pieza (23/09/2026): la cifra por persona del mes abierto '
                        || 'sale de private.conversion_neta_por_vendedor, la misma que usa Metas, y '
                        || 'quien sale nombrado, de private.roster_conversion_mensual. Sigue siendo '
                        || 'nucleo por transitividad.'
  from pg_proc p
 where p.oid = to_regprocedure(e.objeto)
   and e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

-- ---------------------------------------------------------------------------
-- (f) FOTO DE DESPUES, identica en forma a la de antes.
-- ---------------------------------------------------------------------------
do $despues$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_claim_sub text := current_setting('request.jwt.claim.sub', true);
  v_id uuid; v_mes date; v_puerta text; v_pl jsonb;
  v_vigente date := date_trunc('month', (now() at time zone 'America/Lima'))::date;
begin
  for v_id in select distinct a.identidad from _pieza_antes a loop
    -- auth.uid() mira PRIMERO la claim legada `request.jwt.claim.sub`: se vacia,
    -- y se exige que la identidad EFECTIVA sea la pedida antes de fotografiar.
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_id, 'role', 'authenticated')::text, true);
    if (select auth.uid()) is distinct from v_id then
      raise exception 'FOTO: la identidad efectiva (%) no es la pedida (%)', (select auth.uid()), v_id;
    end if;
    foreach v_mes in array array[v_vigente, (v_vigente - interval '1 month')::date] loop
      foreach v_puerta in array array['oficial', 'oficial_cartera', 'metas_sin_cartera', 'metas'] loop
        begin
          v_pl := case v_puerta
            when 'oficial'           then crm.conversion_mensual_sin_cartera_fn(v_mes)
            when 'oficial_cartera'   then crm.conversion_mensual_fn(v_mes)
            when 'metas_sin_cartera' then crm.cumplimiento_metas_sin_cartera_fn(v_mes)
            else crm.cumplimiento_metas_fn(v_mes)
          end;
        exception when others then
          v_pl := jsonb_build_object('_error', sqlstate);
        end;
        insert into _pieza_despues values (v_id, v_mes, v_puerta, v_pl);
      end loop;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_claim_sub, ''), true);
end;
$despues$;

-- ---------------------------------------------------------------------------
-- (g) POSTFLIGHT
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_ok text;
  v_n integer;
  v_lista text;
  r record;
  v_cuerpo text;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  -- 1) NI UN NUMERO MOVIDO. Todo identico salvo la declaracion de Metas del mes
  --    abierto, que pasa de `rango_vivo` a `mensual`.
  if (select count(*) from _pieza_antes) <> (select count(*) from _pieza_despues)
     or (select count(*) from _pieza_antes) = 0 then
    raise exception 'POSTFLIGHT: la foto de despues no tiene las mismas respuestas que la de antes';
  end if;
  select count(*),
         string_agg(format('%s %s %s [%s]', left(a.identidad::text, 8), a.mes, a.puerta,
           (select string_agg(k, ',' order by k)
              from jsonb_object_keys(a.payload || d.payload) k
             where (a.payload -> k)::text is distinct from (d.payload -> k)::text)), ' | ')
    into v_n, v_lista
    from _pieza_antes a
    join _pieza_despues d using (identidad, mes, puerta)
   where (case when a.puerta in ('metas', 'metas_sin_cartera')
                    and a.payload ->> 'fuente' = 'rango_vivo'
               then jsonb_set(a.payload, '{fuente}', '"mensual"')
               else a.payload end)::text
         is distinct from d.payload::text;
  if v_n > 0 then
    raise exception 'POSTFLIGHT: % respuestas cambiaron: %', v_n, left(v_lista, 2000);
  end if;

  -- Anti-vacuidad: la comparacion tiene que haber comparado algo de verdad, en
  -- CADA mes, y cada rol operativo tiene que haber obtenido respuestas sin error.
  if exists (
    select 1 from (select distinct a.mes from _pieza_antes a) m
     where not exists (select 1 from _pieza_despues d
                        where d.mes = m.mes and d.puerta = 'oficial'
                          and jsonb_array_length(coalesce(d.payload -> 'responsables', '[]'::jsonb)) > 0)
        or not exists (select 1 from _pieza_despues d
                        where d.mes = m.mes and d.puerta = 'metas'
                          and jsonb_array_length(coalesce(d.payload -> 'vendedores', '[]'::jsonb)) > 0)
  ) or (select count(distinct a.mes) from _pieza_antes a) <> 2 then
    raise exception 'POSTFLIGHT: algun mes quedo sin responsables o vendedores: la comparacion seria vacua';
  end if;
  if exists (
    select 1 from unnest(array['gerencia', 'supervisor', 'vendedor']) ro(rol)
     where not exists (select 1 from _pieza_despues d
                        where private.rol_crm(d.identidad) = ro.rol
                          and d.puerta in ('oficial', 'metas')
                          and not d.payload ? '_error')
  ) then
    raise exception 'POSTFLIGHT: algun rol operativo no obtuvo ninguna respuesta sin error: la comparacion seria vacua';
  end if;

  -- 2) LA DECLARACION: toda respuesta de Metas dice mensual, coherente con el sello.
  if exists (
    select 1 from _pieza_despues d
     where d.puerta in ('metas', 'metas_sin_cartera')
       and not d.payload ? '_error'
       and (d.payload ->> 'fuente' is distinct from 'mensual'
            or (d.payload ->> 'ajuste_aplicado')::boolean is not true
            or (d.payload ->> 'es_mes_calendario')::boolean is not true
            or (d.payload -> 'sellado') is distinct from
               coalesce(d.payload #> '{cierre,cerrado}', 'false'::jsonb))
  ) then
    raise exception 'POSTFLIGHT: Metas no declara `mensual` o su declaracion no cuadra con el sello';
  end if;

  -- 3) UNA SOLA PIEZA: ninguna de las tres puertas calcula la cifra por su cuenta.
  for r in
    select * from (values
      ('crm.conversion_mensual_sin_cartera_fn(date)', true),
      ('crm.cumplimiento_metas_sin_cartera_fn(date)', false),
      ('crm.cumplimiento_metas_fn(date)',             true)
    ) t(objeto, usa_roster)
  loop
    select regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')
      into v_cuerpo from pg_proc p where p.oid = to_regprocedure(r.objeto);
    if v_cuerpo !~ '\mprivate\.conversion_neta_por_vendedor\s*\(' then
      raise exception 'POSTFLIGHT: % no bebe de la pieza unica', r.objeto;
    end if;
    if v_cuerpo ~ '\m(conversion_mensual_por_vendedor|ajuste_pendiente_por_vendedor|conversion_con_ajuste)\s*\(' then
      raise exception 'POSTFLIGHT: % sigue calculando la cifra por su cuenta', r.objeto;
    end if;
    if r.usa_roster and v_cuerpo !~ '\mprivate\.roster_conversion_mensual\s*\(' then
      raise exception 'POSTFLIGHT: % no toma el roster de la regla unica', r.objeto;
    end if;
  end loop;
  select regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')
    into v_cuerpo from pg_proc p
   where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure;
  if v_cuerpo ~ '\mroster_metas_vendedores\s*\(' or v_cuerpo ~ '\mcrm\.metas_vendedor\M' then
    raise exception 'POSTFLIGHT: la oficial sigue decidiendo el roster por su cuenta';
  end if;

  -- 4) LAS PIEZAS: dueno postgres, INVOKER, STABLE, search_path vacio, EXECUTE solo postgres.
  if exists (
    select 1 from pg_proc p
     where p.oid in ('private.conversion_neta_por_vendedor(date,boolean,uuid[])'::regprocedure,
                     'private.roster_conversion_mensual(date,boolean,uuid[])'::regprocedure)
       and (p.proowner <> 'postgres'::regrole
            or p.prosecdef
            or p.provolatile <> 's'
            or p.proconfig is distinct from array['search_path=""']
            or (select jsonb_agg(jsonb_build_array(a.grantee::regrole::text, a.privilege_type)
                                 order by a.grantee::regrole::text, a.privilege_type)
                  from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
               is distinct from '[["postgres", "EXECUTE"]]'::jsonb)
  ) then
    raise exception 'POSTFLIGHT: una pieza nueva quedo con dueno, seguridad, volatilidad, search_path o EXECUTE indebidos';
  end if;
  if (select count(*) from pg_proc p
       where p.oid in ('private.conversion_neta_por_vendedor(date,boolean,uuid[])'::regprocedure,
                       'private.roster_conversion_mensual(date,boolean,uuid[])'::regprocedure)
         and obj_description(p.oid, 'pg_proc') is not null) <> 2 then
    raise exception 'POSTFLIGHT: una pieza nueva quedo sin COMMENT ON';
  end if;

  -- 5) LAS PUERTAS conservan dueno, definer, volatilidad, search_path y EXECUTE.
  select count(*) into v_n
    from _pieza_atributos t
    join pg_proc p on p.oid = to_regprocedure(t.objeto)
   where p.proowner::regrole::text = t.dueno
     and p.prosecdef = t.definer
     and p.provolatile = t.vol
     and p.proconfig is not distinct from t.cfg
     and (select jsonb_agg(jsonb_build_array(a.grantee::regrole::text, a.privilege_type)
                           order by a.grantee::regrole::text, a.privilege_type)
            from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) = t.acl;
  if v_n <> 3 then
    raise exception 'POSTFLIGHT: una puerta cambio de dueno, seguridad, volatilidad, search_path o EXECUTE';
  end if;

  -- 6) FUERA DEL CENSO siguen la #7, la #8 y las dos piezas.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto in ('crm.cumplimiento_metas_sin_cartera_fn(date)',
                                 'crm.cumplimiento_metas_fn(date)',
                                 'private.conversion_neta_por_vendedor(date,boolean,uuid[])',
                                 'private.roster_conversion_mensual(date,boolean,uuid[])')) then
    raise exception 'POSTFLIGHT: una puerta de Metas o una pieza nueva entro al censo de contadores crudos';
  end if;
end;
$postflight$;

select '20260923164903' as migracion,
       private.assert_analitica_leads_citas() as trinquete,
       (select count(*) from _pieza_antes) as respuestas_comparadas;

commit;
