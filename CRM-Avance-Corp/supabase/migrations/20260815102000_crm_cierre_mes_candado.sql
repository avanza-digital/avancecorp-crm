-- ---------------------------------------------------------------------------
-- El candado del dia 10: el mes se cierra SOLO, y nadie lo adelanta
-- ---------------------------------------------------------------------------
-- QUE ARREGLA. `crm.cerrar_periodo` (20260815002914) nacio con cuatro guardias
-- —solo gerencia, el mes tiene que haber terminado, se cierra en orden, y un mes
-- cerrado no se reescribe— y ninguna de las cuatro dice CUANDO. Hoy gerencia
-- puede cerrar el mes pasado el dia 1 del siguiente, o el 30, o cerrar un mes de
-- hace medio año. Eso rompe dos cosas:
--
--   1. SE COME LA VENTANA DE AJUSTE. Miguel fijo del 1 al 10 para corregir el
--      mes que acaba de terminar. Cerrandolo el dia 2, un cierre que se registre
--      el dia 6 y pertenezca a ese mes ya no entra en la foto, y el vendedor lo
--      pierde.
--
--   2. ⚠️ DEJA ELEGIR A QUIEN LE DUELE UNA CORRECCION — la seria. Al anular un
--      cierre: si el mes sigue ABIERTO, el numero de ese mes baja ahi mismo; si
--      ya esta CERRADO, nace una deuda que se descuenta del MES VIVO. Como el
--      momento de cerrar es libre, quien cierra decide en cual de los dos mundos
--      cae la correccion — es decir, DE QUE MES SALE EL DINERO. Es exactamente
--      la segunda puerta que la regla «la anulacion es la unica puerta de la
--      conversion» viene a cerrar, solo que abierta desde el otro lado.
--
--      ⚠️ Y HONESTAMENTE: esto ACOTA la puerta, no la clausura. Con el suelo del
--      dia 10 (decision de Miguel: suelo, no fecha exacta) sigue habiendo margen
--      — gerencia puede sellar el dia 10 a las 00:05 o dejar que el ciclo lo
--      haga a las 09:20, y para un mes mas viejo el margen es ilimitado. Se deja
--      dicho para que quien audite esto no busque una puerta cerrada que no
--      esta: esta estrechada de meses a horas, y esa fue la decision.
--
-- QUE HACE.
--   · Un mes no se puede cerrar antes del dia 10 del mes siguiente. Ni gerencia.
--   · El cierre pasa a ser AUTOMATICO: un ciclo diario cierra lo que toque.
--   · Y el servidor publica el estado del cierre, para que la pantalla pueda
--     avisar del 1 al 10 y para que un cierre atascado se VEA.
--
-- DECISIONES DE MIGUEL (2026-08-15), que son las que dan forma a esto:
--   1. El candado es un SUELO, no una fecha exacta: nunca antes del dia 10;
--      despues si. Si el ciclo automatico falla el 10, el 11 cierra igual y el
--      mes no queda atascado bloqueando a todos los siguientes.
--   2. El sistema NO calcula comisiones — eso sera otro apartado el dia que
--      exista. Aqui solo se sella y se muestra correctamente lo que lleva el
--      asesor en capital y en conversion.
--   3. Un cierre que llega tarde, cuando su mes ya esta sellado, NO se construye:
--      no ha pasado nunca y se maneja de forma interna. Por eso este archivo solo
--      mira en una direccion.
--
-- ⚠️ LA VENTANA ES UNA FUNCION DE DOS ARGUMENTOS A PROPOSITO. `now()` no se
-- puede falsear dentro de una prueba sin hacer mentir al banco local —y un calco
-- que miente ya nos costo dar por buenas cosas que no lo eran—. Separando la
-- ARITMETICA (`private.cierre_mes_ventana_desde`, inmutable y sin reloj) del
-- RELOJ (quien la llama pasa `now()`), el oraculo prueba la regla exhaustivamente
-- y de forma determinista, corra el dia que corra. La funcion es `private` y
-- nadie de fuera puede pasarle un instante inventado.
--
-- ⚠️ UNA SOLA DEFINICION DE «MES QUE DEBE UN CIERRE». El ciclo automatico, el
-- aviso de pantalla y la regla de «sin huecos» de `cerrar_periodo` responden a la
-- misma pregunta. Con tres copias, el ciclo elegiria un mes que `cerrar_periodo`
-- despues rechaza y el cron fallaria todos los dias para siempre. Va una vez, en
-- `private.cierre_mes_pendiente`, y las tres la llaman.
--
-- FOTO DE PRODUCCION AL ESCRIBIR ESTO (2026-08-15): el unico mes con metas
-- publicadas es agosto 2026, que es el mes EN CURSO. Asi que al aplicar esto no
-- se cierra nada de golpe: el primer cierre real sera el de agosto, el 10 de
-- septiembre. Comprobado contra produccion, no supuesto.
--
-- NO TOCA NADA DE `public`. No cambia ninguna policy ni ningun grant existente.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('crm.periodos_cerrados') is null then
    raise exception 'Falta crm.periodos_cerrados: aplicar antes 20260815002914.';
  end if;
  if to_regprocedure('crm.cerrar_periodo(date)') is null then
    raise exception 'Falta crm.cerrar_periodo: aplicar antes 20260815002914.';
  end if;
  if to_regprocedure('private.etiqueta_mes_es(date)') is null then
    raise exception 'Falta private.etiqueta_mes_es.';
  end if;
  if to_regprocedure('private.es_lector_global()') is null then
    raise exception 'Falta private.es_lector_global.';
  end if;
  if to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)') is null then
    raise exception 'Falta private.registrar_ajuste_si_mes_cerrado: aplicar antes 20260815002100.';
  end if;

  -- Los dos cuerpos de los que se parte. Ambas funciones se reemplazan enteras
  -- mas abajo (Postgres no sabe parchear un cuerpo), asi que hay que probar que
  -- se esta reemplazando LA MISMA version que se leyo al escribir esto.
  --
  -- ⚠️ SE ANCLA `prosrc`, NO `pg_get_functiondef`. `prosrc` es el cuerpo tal cual
  -- se guardo —el mismo texto que hay en el fichero de la migracion—, mientras
  -- que `pg_get_functiondef` es el catalogo RENDERIZADO por el servidor y su
  -- formato puede cambiar entre versiones mayores. Este hash se calculo en un
  -- PG16 local y produccion corre otra mayor: con `pg_get_functiondef` el
  -- preflight podria abortar la migracion diciendo que la funcion «cambio»
  -- cuando lo unico que cambio es como la imprime el servidor.
  if (select md5(p.prosrc) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'cerrar_periodo')
     is distinct from '764377ff0ca6708401030a431191d7b7' then
    raise exception 'crm.cerrar_periodo cambio desde que se escribio esta migracion: revisar antes de aplicar.';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'registrar_ajuste_si_mes_cerrado')
     is distinct from '81163eea2b9b1b96f2119fa385527802' then
    raise exception 'private.registrar_ajuste_si_mes_cerrado cambio desde que se escribio esta migracion: revisar antes de aplicar.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La ventana: desde cuando se puede cerrar un mes
-- ---------------------------------------------------------------------------
-- Aritmetica pura, sin reloj: dado un mes, en que instante se abre su ventana de
-- cierre. Del 1 al 10 del mes siguiente es ventana de AJUSTE (el mes todavia
-- admite correcciones); el dia 10 a las 00:00 de Lima se puede sellar.
--
-- Es INMUTABLE: `timestamp at time zone <constante>` lo es en Postgres, y Peru no
-- tiene horario de verano. Que sea inmutable es lo que permite probarla con
-- decenas de pares (mes, instante) sin depender de cuando se corra la prueba.
create or replace function private.cierre_mes_ventana_desde(p_periodo date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select ((p_periodo + interval '1 month' + interval '9 days')::timestamp
          at time zone 'America/Lima')
$$;

comment on function private.cierre_mes_ventana_desde(date) is
  'Instante en que se abre la ventana de cierre de un mes: el dia 10 del mes siguiente, 00:00 de Lima. Del 1 al 10 hay ventana de ajuste y el mes no se sella. Inmutable y sin reloj a proposito: el que la llama pone el instante, y asi la regla se prueba sin depender del dia.';

revoke all on function private.cierre_mes_ventana_desde(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. El mes mas antiguo que todavia debe un cierre
-- ---------------------------------------------------------------------------
-- «Debe un cierre» = tiene metas publicadas (o sea, hubo algo que pagar), ya
-- termino segun el limite que le pase quien pregunta, y no esta sellado.
--
-- El limite es un parametro porque las tres preguntas que la usan tienen bordes
-- distintos: `cerrar_periodo` pregunta «¿queda alguno anterior AL QUE VOY A
-- CERRAR?», y el ciclo y el aviso preguntan «¿queda alguno anterior AL MES EN
-- CURSO?». La regla es la misma; el borde, no.
--
-- ⚠️ Y NUNCA POR DEBAJO DEL ULTIMO MES SELLADO. Sin ese suelo hay una tercera
-- puerta, y automatizada: `crm.publicar_metas_vendedores` acepta CUALQUIER mes
-- (solo exige que sea dia 1; no mira `crm.periodos_cerrados`, no podia — no
-- existia cuando se escribio). Asi que gerencia publica en noviembre las metas
-- de un julio que nunca las tuvo, julio pasa a «deber un cierre», su ventana
-- abrio hace meses, y el cron lo sella SOLO — despues de agosto y septiembre, y
-- cobrando contra julio deudas vivas que tocaban al mes vivo. Nadie tendria que
-- apretar nada. Con el suelo, un mes que aparece por detras del sello
-- simplemente no es candidato: el ciclo lo ignora en vez de fallar a diario.
create or replace function private.cierre_mes_pendiente(p_antes_de date)
returns date
language sql
stable
security invoker
set search_path = ''
as $$
  select min(mp.periodo)
  from crm.meta_periodos mp
  where mp.periodo < p_antes_de
    and mp.periodo > coalesce(
      (select max(pc.periodo) from crm.periodos_cerrados pc), '-infinity'::date)
    and not exists (
      select 1 from crm.periodos_cerrados pc where pc.periodo = mp.periodo
    )
$$;

comment on function private.cierre_mes_pendiente(date) is
  'El mes mas antiguo con metas publicadas, anterior al limite dado y POSTERIOR al ultimo mes sellado, que aun no esta cerrado. Fuente unica: la usan la regla de «sin huecos» de crm.cerrar_periodo, el ciclo automatico y el aviso de pantalla. Con copias, el ciclo elegiria meses que cerrar_periodo rechaza y el cron fallaria a diario.';

-- SECURITY INVOKER, no DEFINER: no lo necesita. Solo la llaman funciones DEFINER
-- propiedad de postgres, asi que dentro de ellas ya corre con ese privilegio; y
-- la regla del repo es que toda DEFINER lleve gate explicito, que aqui no
-- tendria sentido. El `revoke` sigue siendo la barrera que importa, porque
-- `authenticated` SI tiene `usage` sobre el esquema `private`.
revoke all on function private.cierre_mes_pendiente(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Cerrar un mes — ahora con el candado
-- ---------------------------------------------------------------------------
-- Reemplazo integro de la version de 20260815002914. Cambian DOS cosas y solo
-- dos, para que la revision sea un diff corto:
--   · el paso 2bis, nuevo: la ventana;
--   · el paso 3, que pasa a llamar a `private.cierre_mes_pendiente` en vez de
--     llevar su propia copia de la consulta.
-- Todo lo demas es identico.
create or replace function crm.cerrar_periodo(p_periodo date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text;
  v_automatico  boolean;
  v_mes_actual  date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini         timestamptz;
  v_fin         timestamptz;
  v_factor      numeric;
  v_periodo_id  uuid;
  v_revision    integer;
  v_suelo       timestamptz;
  v_medible     boolean;
  v_motivo      text;
  v_cobertura   jsonb;
  v_vendedores  integer;
  v_pendiente   date;
  v_ventana     timestamptz;
  v_ultimo_sellado date;
begin
  -- 1) Gate. `auth.uid()` nulo = el ciclo automatico (service_role); con uid,
  --    solo gerencia. Un vendedor o un supervisor no cierran meses.
  v_rol := private.rol_crm(v_uid);
  v_automatico := v_uid is null;
  if not v_automatico and v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia cierra un mes' using errcode = '42501';
  end if;

  -- 2) El periodo.
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode = '22023';
  end if;
  -- El mes en curso NO se cierra: todavia esta pasando. Y el siguiente tampoco,
  -- obviamente. La ventana de ajuste (del 1 al 10) vive en el mes SIGUIENTE al
  -- que se cierra, asi que aqui basta con exigir que el mes ya haya terminado.
  if p_periodo >= v_mes_actual then
    raise exception 'Un mes solo se cierra cuando ya termino' using errcode = '22023';
  end if;

  -- 2bis) EL CANDADO. Del 1 al 10 del mes siguiente el mes todavia admite
  --    correcciones, asi que NADIE lo sella: ni gerencia ni el ciclo. Sin esto,
  --    el momento de cerrar decide de que mes sale el dinero de una correccion.
  --    Es un SUELO, no una fecha exacta (decision de Miguel, 2026-08-15): pasado
  --    el dia 10 se puede cerrar cualquier dia, para que un fallo del ciclo no
  --    deje el mes atascado bloqueando a todos los siguientes.
  v_ventana := private.cierre_mes_ventana_desde(p_periodo);
  if now() < v_ventana then
    raise exception using
      errcode = '22023',
      message = format('El mes %s no se puede cerrar antes del %s',
                       to_char(p_periodo, 'YYYY-MM'),
                       to_char(v_ventana at time zone 'America/Lima', 'DD/MM/YYYY')),
      hint    = 'Del 1 al 10 hay ventana de ajuste: el mes todavia puede recibir correcciones.';
  end if;

  -- 2ter) EL CERROJO DEL PERIODO. Se toma ANTES de leer `periodos_cerrados` y de
  --    escribir nada, y lo comparte `private.registrar_ajuste_si_mes_cerrado`.
  --    Sin el hay una carrera que PIERDE DINERO EN SILENCIO: una anulacion que
  --    arranca mientras el cierre esta a medias ve el mes todavia ABIERTO —el
  --    sello aun no ha hecho commit—, decide que no hay deuda que registrar, y
  --    la foto que se esta sellando ya habia contado ese cierre. Resultado: un
  --    cierre anulado queda pagado para siempre y sin una linea que lo explique.
  --    Antes era una carrera teorica (alguien tenia que decidir cerrar); con el
  --    ciclo automatico hay una cita fija, mensual y a hora conocida, justo
  --    cuando gerencia esta mirando esos numeros. Mismo patron que usa
  --    `crm.publicar_metas_vendedores`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_periodo - date '2000-01-01')::integer
  );

  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    raise exception using
      errcode = 'P0409',
      message = 'Ese mes ya estaba cerrado',
      hint    = 'Un mes cerrado no se reescribe: lo que haya que corregir se descuenta en el mes vivo.';
  end if;

  -- 2quater) NUNCA POR DETRAS DE UN MES YA SELLADO. La regla de «sin huecos»
  --    del paso 3 protege el orden dado un conjunto de meses FIJO, y el conjunto
  --    no es fijo: `crm.publicar_metas_vendedores` acepta cualquier mes, asi que
  --    unas metas publicadas hacia atras pueden fabricar un «mes pendiente»
  --    anterior a uno que ya se pago. Sellarlo despues reescribiria la historia
  --    por el unico hueco que quedaba, y `private.saldar_ajustes` le cobraria a
  --    ese mes viejo deudas que tocaban al mes vivo.
  --    En el camino normal esto es un no-op: el ciclo siempre va de viejo a
  --    nuevo. Cuesta una consulta y cierra la ultima puerta.
  select max(pc.periodo) into v_ultimo_sellado from crm.periodos_cerrados pc;
  if v_ultimo_sellado is not null and p_periodo < v_ultimo_sellado then
    raise exception using
      errcode = '22023',
      message = format('No se sella %s: %s ya esta cerrado y es posterior',
                       to_char(p_periodo, 'YYYY-MM'), to_char(v_ultimo_sellado, 'YYYY-MM')),
      hint    = 'Los meses se sellan hacia adelante. Un mes que aparece por detras de lo ya pagado se corrige en el mes vivo, no sellandolo.';
  end if;

  -- 3) Sin huecos: no se cierra un mes si queda alguno anterior CON DATOS
  --    abierto. «Con datos» = tiene metas publicadas; un mes sin metas nunca
  --    tuvo nada que pagar y no bloquea la secuencia.
  v_pendiente := private.cierre_mes_pendiente(p_periodo);
  if v_pendiente is not null then
    raise exception using
      errcode = '22023',
      message = format('Falta cerrar %s antes que %s', v_pendiente, p_periodo),
      hint    = 'Los meses se cierran en orden: si no, el que se salta queda abierto para siempre.';
  end if;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(p_periodo);

  select mp.id, mp.revision into v_periodo_id, v_revision
  from crm.meta_periodos mp
  where mp.periodo = p_periodo
  order by mp.revision desc
  limit 1;
  -- Un mes sin metas publicadas se puede cerrar igual: se sella lo que hubo
  -- (conversion sin objetivo). Cerrar es fijar la historia, no premiarla.
  v_revision := coalesce(v_revision, 0);

  -- 4) La cobertura, con el MISMO criterio que la pantalla. Se recalcula aqui en
  --    vez de leerse de `conversion_mensual_fn` porque esa funcion recorta por
  --    `auth.uid()` y el cierre necesita la foto completa.
  select min(la.asignado_en) into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;

  if v_suelo is null then
    v_medible := false;
    v_motivo := 'sin_ledger';
  elsif v_ini < v_suelo then
    v_medible := false;
    v_motivo := case
      when p_periodo < date_trunc('month', v_suelo at time zone 'America/Lima')::date
        then 'anterior_al_ledger'
      else 'mes_parcial'
    end;
  else
    v_medible := true;
    v_motivo := null;
  end if;
  v_cobertura := jsonb_build_object(
    'medible', v_medible,
    'suelo_historico', v_suelo,
    'motivo_no_medible', v_motivo
  );

  insert into crm.periodos_cerrados (
    periodo, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura
  ) values (
    p_periodo,
    case when v_automatico then null else v_uid end,
    v_automatico, v_factor, v_revision, v_cobertura
  );

  -- 5) La foto. El conjunto de personas es el ROSTER DEL MES (quien tenia meta),
  --    en union con quien PRODUJO aunque no tuviera meta: los dos importan para
  --    una foto de pago, y quien produjo sin meta tiene que quedar registrado
  --    con su nombre en vez de disolverse en un agregado anonimo — que es lo que
  --    hace la pantalla viva, y esta bien alli (privacidad) y mal aqui (pago).
  with conv as (
    select cm.*
    from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
  ), prod as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), roster as (
    -- `distinct on`: una fila por persona, pase lo que pase. La foto tiene la
    -- clave (periodo, vendedor), asi que dos metas del mismo vendedor en el
    -- mismo periodo harian reventar el cierre entero con un duplicado — un mes
    -- que no se puede cerrar por una fila repetida es peor que el duplicado.
    -- (Lo cazo el oraculo ejecutando, no leyendo.)
    select distinct on (mv.vendedor_id)
      mv.vendedor_id, mv.supervisor_id, mv.conversion_objetivo, mv.id as meta_vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
    order by mv.vendedor_id, mv.id
  ), personas as (
    select vendedor_id from roster
    union
    select analista_id from conv
    union
    select vendedor_id from prod where vendedor_id is not null
  )
  insert into crm.cierre_mes_vendedor (
    periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
    divisor, divisor_aproximado, divisor_por_motivo,
    cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
    numerador, conversion_pct, estado,
    referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia,
    ajuste_numerador, ajuste_pen, ajuste_usd,
    conversion_objetivo, detalles
  )
  select
    p_periodo,
    pe.vendedor_id,
    coalesce(pf.nombre_completo, '(sin ficha)'),
    r.supervisor_id,
    sup.nombre_completo,
    coalesce(c.divisor, 0),
    coalesce(c.divisor_aproximado, 0),
    coalesce(c.divisor_por_motivo, '{}'::jsonb),
    coalesce(c.cierres_no_referidos, 0),
    coalesce(c.cierres_referidos, 0),
    coalesce(c.cierres_de_arrastre, 0),
    -- NETO: lo bruto menos lo que este mes absorbio de deudas viejas. Es lo que
    -- se paga, asi que es lo que se sella.
    coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador,
    case when coalesce(c.divisor, 0) > 0
      then round(100.0 * (coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador)
                 / coalesce(c.divisor, 0), 2) end,
    case
      when coalesce(c.divisor, 0) > 0 then 'medible'
      when coalesce(c.referidos_recibidos, 0) > 0 then 'solo_referidos'
      when coalesce(c.cierres_no_referidos, 0) + coalesce(c.cierres_referidos, 0) > 0 then 'solo_arrastre'
      else 'sin_actividad'
    end,
    coalesce(c.referidos_recibidos, 0),
    coalesce(alta.dados_de_alta, 0),
    c.referidos_aporta_pct,
    coalesce(c.procedencia, '[]'::jsonb),
    sal.aplicado_numerador,
    sal.aplicado_pen,
    sal.aplicado_usd,
    r.conversion_objetivo,
    coalesce(det.detalles, '[]'::jsonb)
  from personas pe
  left join roster r on r.vendedor_id = pe.vendedor_id
  left join conv c on c.analista_id = pe.vendedor_id
  left join public.perfiles pf on pf.id = pe.vendedor_id
  left join public.perfiles sup on sup.id = r.supervisor_id
  left join lateral (
    -- El capital bruto del mes por moneda, que es el techo de lo que este mes
    -- puede absorber. PEN y USD por separado: una deuda en soles no se paga con
    -- produccion en dolares.
    -- ⚠️ Va ANTES del `saldar_ajustes` que lo consume: un LATERAL solo puede
    -- mirar a su izquierda.
    select
      coalesce(sum(pr.capital_real) filter (where pr.moneda = 'PEN'), 0) as pen,
      coalesce(sum(pr.capital_real) filter (where pr.moneda = 'USD'), 0) as usd
    from prod pr
    where pr.vendedor_id = pe.vendedor_id
  ) cap on true
  -- Lo que este mes puede absorber de las deudas viejas del vendedor. Es
  -- VOLATIL a proposito: ademas de devolver lo aplicado, DESCUENTA lo saldado y
  -- deja el resto arrastrandose. Se llama una vez por persona, que es la unica
  -- forma en que la cuenta cuadra.
  left join lateral private.saldar_ajustes(
    pe.vendedor_id,
    coalesce(c.numerador, 0::numeric),
    coalesce(cap.pen, 0::numeric),
    coalesce(cap.usd, 0::numeric)
  ) sal on true
  left join lateral (
    select count(*)::int as dados_de_alta
    from crm.leads l
    where l.origen = 'referido'
      and l.creado_en >= v_ini and l.creado_en < v_fin
      and l.creado_por = pe.vendedor_id
  ) alta on true
  left join lateral (
    -- ⚠️ `capital_real` y `contratos_real` van NETOS del descuento que este mes
    -- absorbio, casilla a casilla. Es la correccion de un fallo de DINERO: la
    -- primera version marcaba la deuda como saldada y NO la restaba de ninguna
    -- cifra, asi que el asesor cobraba igual y la deuda desaparecia — miles de
    -- soles perdonados en silencio, sin una sola linea que lo dijera.
    select jsonb_agg(jsonb_build_object(
      'categoria', d.categoria,
      'moneda', d.moneda,
      'capital_objetivo', d.capital_objetivo,
      'capital_real', greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0),
      'capital_cumplimiento_pct', case when d.capital_objetivo > 0
        then round(100.0 * greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0)
                   / d.capital_objetivo, 2) end,
      'contratos_objetivo', d.contratos_objetivo,
      'contratos_real', greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0),
      'contratos_cumplimiento_pct', case when d.contratos_objetivo > 0
        then round(100.0 * greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0)
                   / d.contratos_objetivo, 2) end,
      -- Y se DECLARA lo descontado en su propia casilla: la foto tiene que poder
      -- explicar por que ese numero no es el bruto.
      'capital_ajuste', coalesce(aj.capital, 0),
      'contratos_ajuste', coalesce(aj.contratos, 0)
    ) order by array_position(array['nuevo','renovacion','upgrade'], d.categoria), d.moneda) as detalles
    from crm.metas_vendedor_detalle d
    left join prod pr on pr.vendedor_id = pe.vendedor_id
      and pr.categoria = d.categoria and pr.moneda = d.moneda
    left join lateral (
      select coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(sal.aplicado_detalle) e
      where e->>'categoria' = d.categoria and e->>'moneda' = d.moneda
      limit 1
    ) aj on true
    where d.meta_vendedor_id = r.meta_vendedor_id
  ) det on true;

  get diagnostics v_vendedores = row_count;

  -- El rastro del cierre NO se escribe en `crm.actividades`: esa tabla cuelga de
  -- un lead y un cierre de mes no es de ningun lead. El registro lo deja el
  -- trigger de auditoria sobre `crm.periodos_cerrados`, con quien, cuando y que.

  return jsonb_build_object(
    'ok', true,
    'periodo', to_char(p_periodo, 'YYYY-MM'),
    'automatico', v_automatico,
    'vendedores', v_vendedores,
    'meta_revision', v_revision,
    'cobertura', v_cobertura
  );
end;
$$;

comment on function crm.cerrar_periodo(date) is
  'Sella la foto de un mes: conversion, cumplimiento y capital por vendedor. Solo gerencia o el ciclo automatico. NUNCA antes del dia 10 del mes siguiente (ventana de ajuste). Cierra en orden y no reescribe: un mes cerrado no se vuelve a cerrar.';

revoke all on function crm.cerrar_periodo(date) from public, anon;
grant execute on function crm.cerrar_periodo(date) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3bis. La otra mitad del cerrojo
-- ---------------------------------------------------------------------------
-- Un lock que solo toma una de las dos partes no serializa nada. `cerrar_periodo`
-- ya lo toma; aqui lo toma la anulacion, con la MISMA clave (el periodo del
-- cierre que se anula). A partir de ahora las dos operaciones sobre un mismo mes
-- se ponen en fila: o la anulacion ve el mes abierto y lo recalcula, o lo ve
-- cerrado y registra la deuda. Nunca el estado intermedio, que era el que
-- perdia el dinero.
--
-- Reemplazo integro de la version de 20260815002100. Cambia UNA cosa: la linea
-- del `pg_advisory_xact_lock` justo despues de calcular el periodo. Todo lo
-- demas es identico, para que la revision sea un diff de una linea.
create or replace function private.registrar_ajuste_si_mes_cerrado(
  p_lead_id uuid,
  p_motivo text,
  p_por uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- ⚠️ EL CERROJO, antes de mirar si el mes esta cerrado. Sin el, una anulacion
  -- concurrente con el sellado de ESE mes lee «abierto» —porque el sello aun no
  -- ha commiteado—, devuelve NULL, y el cierre anulado se queda pagado para
  -- siempre. Misma clave que en `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  select coalesce(bool_or(la.origen = 'referido'), false) into v_referido
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id and la.resultado = 'convertido';

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_referido then v_peso else 1 end;

  -- Y lo que valia en capital: los contratos que dejan de acreditar, con la
  -- MISMA regla que la cuota. PEN y USD por separado, y ADEMAS desglosado por
  -- categoria: es la casilla exacta de la que habra que descontarlo.
  select
    coalesce(sum(c.capital) filter (where c.moneda = 'PEN'), 0),
    coalesce(sum(c.capital) filter (where c.moneda = 'USD'), 0)
    into v_pen, v_usd
  from private.contratos_afectados_por_anulacion(p_lead_id) x
  join public.contratos c on c.id = x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'categoria', d.categoria, 'moneda', d.moneda,
           'capital', d.capital, 'contratos', d.contratos)), '[]'::jsonb)
    into v_detalle
  from (
    select c.categoria, c.moneda, sum(c.capital) as capital, count(*)::int as contratos
    from private.contratos_afectados_por_anulacion(p_lead_id) x
    join public.contratos c on c.id = x
    group by c.categoria, c.moneda
  ) d;

  -- Un cierre que no valia nada no genera deuda.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;
$$;

comment on function private.registrar_ajuste_si_mes_cerrado(uuid, text, uuid) is
  'Si el cierre anulado pertenece a un mes YA CERRADO, registra la deuda que el vendedor arrastrara al mes vivo. Si el mes sigue abierto devuelve NULL: ese mes se recalcula solo. Toma el cerrojo del periodo, el mismo que crm.cerrar_periodo: sin el, anular a la vez que se sella pierde la deuda en silencio.';

revoke all on function private.registrar_ajuste_si_mes_cerrado(uuid, text, uuid) from public;

-- ---------------------------------------------------------------------------
-- 4. El ciclo: el mes se cierra SOLO
-- ---------------------------------------------------------------------------
-- Corre TODOS los dias, no solo el 10. Es lo que lo hace auto-reparable: si el
-- dia 10 el ciclo no corrio —o fallo—, el 11 cierra igual. Un cierre que solo se
-- intenta una vez al año necesita que alguien vigile ese dia; este no.
--
-- Idempotente: si no hay nada pendiente, o la ventana del pendiente aun no abrio,
-- no hace nada y lo dice. Correrlo dos veces el mismo dia no cierra dos veces —
-- lo impide `crm.periodos_cerrados.periodo` siendo clave primaria, ademas del
-- guardia explicito de `cerrar_periodo`.
--
-- ⚠️ SI UN MES FALLA, EL CICLO PARA Y CONSERVA LO YA HECHO. Cada mes se sella en
-- su propia SUBTRANSACCION. Sin eso —y asi nacio— todo el bucle era una sola
-- transaccion: un fallo en el mes M+1 no solo paraba, sino que TIRABA TAMBIEN el
-- sellado de M, que habia ido bien. Y como estos fallos son deterministas (una
-- fila duplicada, un dato torcido), el sistema se quedaria atascado para siempre
-- en M, rehaciendo y descartando el mismo trabajo bueno cada dia — justo lo
-- contrario de la auto-reparacion que este ciclo presume.
--
-- No sigue con los siguientes: los meses se cierran en orden y saltarse uno
-- dejaria un hueco permanente. El fallo viaja en el payload (y por tanto a
-- `cron.job_run_details`), y —lo que de verdad se ve— el mes sigue apareciendo
-- como pendiente y VENCIDO en `crm.cierre_mes_estado_fn`, que es por donde
-- gerencia se entera sin mirar logs.
--
-- SOLO EL CICLO. No hay rama de «gerencia lo dispara a mano»: seria superficie de
-- la Data API sin ningun consumidor, y gerencia ya tiene su puerta manual en
-- `crm.cerrar_periodo`, que es explicita y va mes a mes. Por eso el grant es a
-- `service_role` y no a `authenticated`.
create or replace function crm.ciclo_cierre_mes()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_periodo    date;
  v_detalle    jsonb := '[]'::jsonb;
  v_fallo      jsonb := null;
  v_vueltas    integer := 0;
begin
  -- Gate explicito y ANTES de tocar nada, aunque `cerrar_periodo` tenga el suyo:
  -- quien llame a esto con una sesion tiene que recibir 42501 aqui, no a mitad
  -- del recorrido y con parte del trabajo hecho.
  if (select auth.uid()) is not null then
    raise exception 'El ciclo de cierre lo dispara el reloj, no una persona'
      using errcode = '42501',
            hint = 'Para cerrar un mes concreto a mano, gerencia usa crm.cerrar_periodo.';
  end if;

  loop
    v_periodo := private.cierre_mes_pendiente(v_mes_actual);
    -- Nada pendiente, o el pendiente todavia esta en su ventana de ajuste.
    exit when v_periodo is null;
    exit when now() < private.cierre_mes_ventana_desde(v_periodo);

    begin
      v_detalle := v_detalle || jsonb_build_array(crm.cerrar_periodo(v_periodo));
    exception when others then
      -- Lo sellado hasta aqui SOBREVIVE; solo revierte el mes que fallo.
      v_fallo := jsonb_build_object(
        'periodo', to_char(v_periodo, 'YYYY-MM'),
        'sqlstate', sqlstate,
        'mensaje', sqlerrm
      );
      exit;
    end;

    -- Cinturon: `cerrar_periodo` inserta en `periodos_cerrados`, asi que la
    -- siguiente vuelta ve un mes mas nuevo y el bucle avanza. Si alguna vez
    -- dejara de avanzar, mejor reventar que girar para siempre dentro de un cron.
    v_vueltas := v_vueltas + 1;
    if v_vueltas > 120 then
      raise exception 'El ciclo de cierre dio mas de 120 vueltas sin terminar: hay un mes que no avanza.';
    end if;
  end loop;

  return jsonb_build_object(
    'ok', v_fallo is null,
    'cerrados', jsonb_array_length(v_detalle),
    'detalle', v_detalle,
    'fallo', v_fallo
  );
end;
$$;

comment on function crm.ciclo_cierre_mes() is
  'Cierra, en orden y de mas antiguo a mas nuevo, los meses que ya deben un cierre y cuya ventana abrio. Pensada para correr a diario: si el dia 10 falla, el 11 cierra igual. Idempotente. Cada mes va en su subtransaccion: si uno falla, para y CONSERVA los anteriores. Solo el reloj la dispara; la puerta manual de gerencia es crm.cerrar_periodo.';

revoke all on function crm.ciclo_cierre_mes() from public, anon, authenticated;
grant execute on function crm.ciclo_cierre_mes() to service_role;

-- ---------------------------------------------------------------------------
-- 5. El estado del cierre, para que la pantalla pueda avisar
-- ---------------------------------------------------------------------------
-- ⚠️ NO CONFUNDIR CON `crm.cierres_estado_fn(uuid[])`, que es de los CIERRES de
-- venta (los tratos). Esta es del CIERRE DE MES. Nombres parecidos en un esquema
-- en español ya nos costaron un despliegue; de ahi el `_mes_` en medio.
--
-- Por que una funcion aparte y no una clave mas en el payload de la conversion:
-- el aviso no habla del mes que el usuario esta MIRANDO, habla del estado de la
-- maquinaria. Alguien mirando junio necesita igual saber que agosto se cierra el
-- 10 de septiembre. Meterlo en el payload de un periodo concreto seria colgar la
-- respuesta de una pregunta que no es la suya.
--
-- Sirve para las dos cosas:
--   · el aviso del 1 al 10 («julio se cierra el 10/08, quedan 3 dias»);
--   · la ALARMA de que el ciclo esta atascado (`vencido: true` = la ventana ya
--     abrio y el mes sigue sin sellar). Sin esto, un cron roto es invisible.
--
-- No devuelve PII ni cifras de nadie: es el estado del reloj. El gate es el mismo
-- de la conversion para que la respuesta no funcione como oraculo de roles.
create or replace function crm.cierre_mes_estado_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text;
  v_lector     boolean;
  v_ahora      timestamptz := now();
  v_hoy        date := (v_ahora at time zone 'America/Lima')::date;
  v_mes_actual date := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_pend       date;
  v_ventana    timestamptz;
  v_ult        crm.periodos_cerrados%rowtype;
begin
  -- ⚠️ EL COORDINADOR SI ENTRA, al reves que en `crm.conversion_mensual_fn`. No
  -- es un descuido copiando: `crm.cumplimiento_metas_fn` —la otra pantalla que
  -- desde 20260815003742 publica la clave `cierre`— usa el idioma laxo
  -- («rol_crm is not null») y por tanto el coordinador SI la ve. Si el aviso le
  -- respondiera 42501, abriria las metas de un mes cerrado, leeria
  -- `cierre.cerrado = true`, y su banner quedaria en error o girando para
  -- siempre. Y no hay nada que proteger: esta funcion no devuelve cifras, ni
  -- PII, ni quien cerro — solo etiquetas de mes, fechas y un estado.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(
          v_rol in ('vendedor', 'supervisor', 'gerencia', 'coordinador') or v_lector,
          false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_pend := private.cierre_mes_pendiente(v_mes_actual);
  if v_pend is not null then
    v_ventana := private.cierre_mes_ventana_desde(v_pend);
  end if;

  -- Por `periodo`, no por `cerrado_en`: la pregunta que responde es «¿hasta que
  -- mes esta cerrado?». Y desde el guardia 2quater de `crm.cerrar_periodo` los
  -- meses solo se sellan hacia adelante, asi que los dos criterios coinciden.
  select * into v_ult
  from crm.periodos_cerrados
  order by periodo desc
  limit 1;

  return jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'hoy', v_hoy,
    'zona', 'America/Lima',
    -- El mes que esta corriendo y cuando le tocara sellarse. Es el aviso normal:
    -- «lo que cierres este mes queda fijo el 10 del que viene».
    'mes_en_curso', jsonb_build_object(
      'mes', to_char(v_mes_actual, 'YYYY-MM'),
      'mes_nombre', private.etiqueta_mes_es(v_mes_actual),
      'cierra_el', (private.cierre_mes_ventana_desde(v_mes_actual)
                    at time zone 'America/Lima')::date
    ),
    -- El mes que ya termino y todavia no se ha sellado.
    --
    -- ⚠️ EL ESTADO SE NOMBRA AQUI, no se deduce en el front. Son TRES
    -- situaciones, no dos, y la del medio es la que se presta al error:
    --   · `en_ventana` — del 1 al 10: todavia se puede corregir. Normal.
    --   · `hoy`        — hoy le toca sellarse y el ciclo aun no ha pasado.
    --                    Normal tambien. La ventana abre a las 00:00 y el ciclo
    --                    corre a las 09:20: sin este estado, la lectura literal
    --                    («ya paso la fecha y sigue abierto») gritaria «atascado»
    --                    nueve horas cada dia 10, un mes tras otro, con todo
    --                    funcionando. Una alarma que suena cuando no pasa nada
    --                    deja de mirarse, y entonces tampoco se ve la vez que si.
    --   · `atascado`   — paso un dia entero: al menos un ciclo tuvo su turno y
    --                    no lo hizo. ESTA es la alarma.
    -- Se publica un solo campo y no un booleano ademas: dos formas del mismo
    -- dato se contradicen tarde o temprano.
    'pendiente', case when v_pend is null then null else jsonb_build_object(
      'mes', to_char(v_pend, 'YYYY-MM'),
      'mes_nombre', private.etiqueta_mes_es(v_pend),
      'cierra_el', (v_ventana at time zone 'America/Lima')::date,
      'dias_para_cierre', greatest(
        0, (v_ventana at time zone 'America/Lima')::date - v_hoy),
      'estado', case
        when v_ahora < v_ventana then 'en_ventana'
        when v_ahora < v_ventana + interval '1 day' then 'hoy'
        else 'atascado'
      end
    ) end,
    'ultimo_cerrado', case when v_ult.periodo is null then null else jsonb_build_object(
      'mes', to_char(v_ult.periodo, 'YYYY-MM'),
      'mes_nombre', private.etiqueta_mes_es(v_ult.periodo),
      'cerrado_en', v_ult.cerrado_en,
      'automatico', v_ult.automatico
    ) end
  );
end;
$$;

comment on function crm.cierre_mes_estado_fn() is
  'Estado de la maquinaria del cierre de mes: cuando se sella el mes en curso, que mes esta pendiente y si ya se le paso la fecha (ciclo atascado). No devuelve cifras ni PII. OJO: no es crm.cierres_estado_fn, que es de los cierres de venta.';

revoke all on function crm.cierre_mes_estado_fn() from public, anon;
grant execute on function crm.cierre_mes_estado_fn() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. El reloj: que el ciclo corra de verdad todos los dias
-- ---------------------------------------------------------------------------
-- Sin esto, `crm.ciclo_cierre_mes` es una funcion que nadie llama y «el mes se
-- cierra solo» es mentira. Va DENTRO de la migracion —y no en un paso manual de
-- despliegue— porque un cron creado a mano en el editor no esta versionado: no
-- se sabe cuando cambio, no viaja a una branch de pruebas y no se puede revisar.
--
-- 14:20 UTC = 09:20 de Lima, justo detras del ciclo de contratos (14:10). El
-- mismo hueco de la mañana para todo lo automatico, que es mas facil de vigilar
-- que tres horarios distintos.
--
-- DIARIO, no «el dia 10»: el candado ya impide cerrar antes de tiempo, asi que
-- correr a diario no adelanta nada y en cambio repara solo un dia 10 fallido.
-- `cron.schedule` reemplaza por nombre, asi que reaplicar es idempotente.
do $reloj$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    -- Banco local sin pg_cron: no es un fallo, aqui no hay reloj que programar.
    raise notice 'pg_cron no esta disponible: no se programa el ciclo de cierre de mes.';
    return;
  end if;
  perform cron.schedule(
    'crm-cierre-mes-diario',
    '20 14 * * *',
    'select crm.ciclo_cierre_mes();'
  );
end;
$reloj$;

-- ---------------------------------------------------------------------------
-- 7. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_n   integer;
begin
  -- La ventana cae donde tiene que caer: dia 10 del mes siguiente, 00:00 Lima.
  if (private.cierre_mes_ventana_desde('2026-07-01'::date)
      at time zone 'America/Lima')::date <> '2026-08-10'::date then
    raise exception 'La ventana no abre el dia 10 del mes siguiente.';
  end if;
  -- Y en un mes de 31 dias y en uno de 28, que es donde la aritmetica de fechas
  -- suele torcerse.
  if (private.cierre_mes_ventana_desde('2026-01-01'::date)
      at time zone 'America/Lima')::date <> '2026-02-10'::date
     or (private.cierre_mes_ventana_desde('2026-02-01'::date)
      at time zone 'America/Lima')::date <> '2026-03-10'::date then
    raise exception 'La ventana se tuerce en meses de distinta longitud.';
  end if;

  -- El candado esta DENTRO de cerrar_periodo, no solo escrito en un comentario.
  if (select strpos(p.prosrc, 'cierre_mes_ventana_desde') from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'crm' and p.proname = 'cerrar_periodo') = 0 then
    raise exception 'crm.cerrar_periodo no quedo con el candado de la ventana.';
  end if;
  -- ⚠️ EL CERROJO ESTA EN LAS DOS PUERTAS. Esta comprobacion es estructural y no
  -- de comportamiento a proposito: una carrera necesita DOS sesiones a la vez y
  -- el oraculo corre en una sola, asi que ningun test la caza — verificado con un
  -- mutante el 15/08: quitar el `pg_advisory_xact_lock` deja el oraculo en verde.
  -- Sin esta linea, el arreglo se podria borrar sin que nada protestara, y el
  -- fallo que evita (una anulacion a la vez que el sellado deja un cierre anulado
  -- pagado para siempre) es silencioso y de dinero. Un lock que solo toma una de
  -- las dos partes no serializa nada, de ahi que se exijan las dos.
  if (select strpos(p.prosrc, 'pg_advisory_xact_lock') from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'crm' and p.proname = 'cerrar_periodo') = 0
     or (select strpos(p.prosrc, 'pg_advisory_xact_lock') from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private' and p.proname = 'registrar_ajuste_si_mes_cerrado') = 0 then
    raise exception 'El cerrojo del periodo falta en alguna de las dos puertas (cerrar_periodo / registrar_ajuste_si_mes_cerrado).';
  end if;

  -- Y la regla de «sin huecos» quedo apoyada en la fuente unica.
  if (select strpos(p.prosrc, 'cierre_mes_pendiente') from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'crm' and p.proname = 'cerrar_periodo') = 0 then
    raise exception 'crm.cerrar_periodo no quedo usando private.cierre_mes_pendiente.';
  end if;

  -- Las funciones nuevas no son alcanzables por anon.
  if has_function_privilege('anon', 'crm.ciclo_cierre_mes()', 'EXECUTE')
     or has_function_privilege('anon', 'crm.cierre_mes_estado_fn()', 'EXECUTE') then
    raise exception 'Alguna funcion del cierre quedo ejecutable por anon.';
  end if;
  -- Y el ciclo tampoco por `authenticated`: lo dispara el reloj, no una persona.
  if has_function_privilege('authenticated', 'crm.ciclo_cierre_mes()', 'EXECUTE') then
    raise exception 'crm.ciclo_cierre_mes quedo ejecutable por authenticated.';
  end if;
  -- Los helpers de private no se exponen a la Data API. Se preguntan los DOS
  -- roles: `authenticated` tiene `usage` sobre el esquema `private`, asi que el
  -- revoke del grant de PUBLIC es la unica barrera que hay.
  if has_function_privilege('authenticated', 'private.cierre_mes_ventana_desde(date)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.cierre_mes_pendiente(date)', 'EXECUTE')
     or has_function_privilege('anon', 'private.cierre_mes_ventana_desde(date)', 'EXECUTE')
     or has_function_privilege('anon', 'private.cierre_mes_pendiente(date)', 'EXECUTE') then
    raise exception 'Un helper de private quedo ejecutable desde la Data API.';
  end if;

  -- El reloj quedo puesto (donde hay reloj). Un ciclo sin cron es una funcion
  -- que nadie llama, y «el mes se cierra solo» seria falso sin que nada avisara.
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    -- Se cuenta `= 1`, no `exists`. `cron.schedule` reemplaza por
    -- (jobname, username), no por jobname a secas: si algun camino de despliegue
    -- lo aplicara como un rol distinto, quedarian DOS jobs activos con el mismo
    -- nombre sellando meses en paralelo, y un `exists` los daria por buenos.
    select count(*) into v_n
    from cron.job
    where jobname = 'crm-cierre-mes-diario' and active
      and strpos(command, 'ciclo_cierre_mes') > 0;
    if v_n <> 1 then
      raise exception 'El ciclo de cierre de mes quedo con % jobs activos, se esperaba exactamente 1.', v_n;
    end if;
  end if;

  -- Y el candado MUERDE: el mes pasado no se puede cerrar antes del dia 10.
  -- Solo se puede comprobar aqui los dias 1..9; el resto del mes la situacion no
  -- existe y la prueba exhaustiva vive en el oraculo.
  if extract(day from v_hoy) < 10 then
    begin
      perform crm.cerrar_periodo(
        (date_trunc('month', v_hoy::timestamp) - interval '1 month')::date);
      raise exception 'El candado no mordio: se cerro el mes pasado antes del dia 10.';
    exception
      when sqlstate '22023' then null;  -- lo esperado
    end;
  end if;
end;
$postflight$;

-- ---------------------------------------------------------------------------
-- 8. Aclaracion heredada, que el ciclo automatico vuelve importante
-- ---------------------------------------------------------------------------
-- `automatico` NO significa «lo hizo el cron»: significa «llego sin sesion».
-- Cualquier proceso con la llave de servicio sella con `automatico = true` y
-- `cerrado_por = null`. Hasta hoy daba igual porque nadie cerraba; con el ciclo
-- pasa a ser la via normal, y conviene que quien lea la foto dentro de un año no
-- lo interprete de mas. Si algun dia hay un boton de gerencia servido por una
-- edge function, la autoria habra que pasarla explicita.
comment on column crm.periodos_cerrados.automatico is
  'true = se sello sin sesion de usuario, que es como llega el ciclo diario (y como llegaria cualquier proceso con service_role). No es prueba de que lo hiciera el cron; para autoria humana, cerrado_por.';

commit;

-- ---------------------------------------------------------------------------
-- VUELTA ATRAS
-- ---------------------------------------------------------------------------
-- ⚠️ EL PRIMER PASO ES DESPROGRAMAR EL RELOJ, y no es opcional: si se revierten
-- las funciones dejando el job vivo, `crm-cierre-mes-diario` dispara todos los
-- dias contra una funcion que ya no existe. Eso deja un error diario en
-- `cron.job_run_details` —que nadie mira— y, peor, la sensacion de que el ciclo
-- sigue corriendo.
--
-- Esta es la PRIMERA migracion del repo que versiona un `cron.schedule` (las dos
-- del portal, 14:00 y 14:10, se crearon a mano en el dashboard). La convencion
-- que estrena: el job se programa en la migracion y se desprograma en su vuelta
-- atras, con `username = postgres`.
--
-- begin;
--   select cron.unschedule('crm-cierre-mes-diario');
--   drop function if exists crm.cierre_mes_estado_fn();
--   drop function if exists crm.ciclo_cierre_mes();
--   -- `crm.cerrar_periodo` y `private.registrar_ajuste_si_mes_cerrado` NO se
--   -- borran: se restauran reaplicando el cuerpo de 20260815002914 y
--   -- 20260815002100 respectivamente (son `create or replace`, no objetos
--   -- nuevos). Sin eso, el sistema queda sin la funcion que sella.
--   drop function if exists private.cierre_mes_pendiente(date);
--   drop function if exists private.cierre_mes_ventana_desde(date);
-- commit;
