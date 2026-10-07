-- 20261007160937_crm_conversion_tope_referidos.sql
--
-- Conversión · tope de referidos: desde OCTUBRE 2026 un referido que cierra vale 1 entero, pero entre todos los referidos de un
-- analista solo cuentan, como máximo, el 15 % de los cierres de LEADS QUE EL SISTEMA LE ASIGNA (origen landing o formulario),
-- redondeado hacia arriba. Los referidos que pasan del tope valen 0: siguen en el historial, solo dejan de pesar en la
-- conversión. Decisión de Miguel (07/10/2026): «máximo 15 % de los cierres de leads asignados; el exceso queda sin efecto».
-- Respuestas: (1) peso 1 por referido que cuenta; (2) base = SOLO los cierres de leads landing/formulario del analista en el mes:
-- los referidos, las renovaciones, los upgrades y la base cargada NO entran en la base (los confirmó Miguel el 07/10/2026);
-- (3) redondeo hacia arriba; (4) quedan sin efecto los más recientes por fecha de cierre; (5) rige desde octubre, el pasado no
-- se toca; (6) sin cierres asignados la base es 0 y el tope es 0: todos los referidos de ese analista y mes valen 0.
-- Ejemplo aprobado: 10 asignados + 4 referidos + 3 renovaciones + 2 upgrades + 1 de base cargada ⇒ tope ceil(1,5) = 2.
--
-- QUÉ HACE
--   1. crm.conversion_pesos gana `tope_referidos_pct` (NULL = sin tope) y una versión nueva desde 2026-10-01: peso_referido 1,000
--      y tope 15,00. Agosto y septiembre conservan 0,15 y sin tope (la versión vigente de un mes es la de su vigente_desde).
--   2. NUEVA private.tope_referidos_conversion(date): el tope vigente de un mes, o NULL. Sin respaldo a la versión más antigua:
--      un mes sin versión de tope NO lleva tope.
--   3. NUEVA private.conversion_origen_base_tope(text): UNA definición de qué orígenes de lead forman la base del tope (landing y
--      formulario: los que asigna el sistema). Cambiar la lista es cambiar esa función.
--   4. private.conversion_episodios (UNA sola pieza donde nace el numerador de todas las puertas): calcula el tope por analista y
--      mes de cierre sobre el MES COMPLETO de ese analista (el ámbito se aplica antes: la base de uno no depende de los demás) y
--      después recorta al rango pedido. Así un rango parcial o la vista de un supervisor dan el mismo número que la empresa entera.
--      La base son solo los cierres no anulados de leads de origen de base; las operaciones de cartera salen como siempre.
--      Firma, dueño, ACL y columnas intactas.
--   5. crm.periodos_cerrados gana `tope_referidos_pct`: la foto guarda con qué tope se calculó el mes (como guarda los pesos).
--      crm.cerrar_periodo lo escribe. Mismo texto vivo, con ese único cambio.
--   6. private.conversion_fijar_sello_trg: al sellar, `incluida_en_sello` de un referido es verdadera solo si ese referido CUENTA
--      (está dentro del tope). Así la deuda por anular un referido que ya no pesaba es CERO y la de uno que sí pesaba es 1
--      (registrar_ajuste_si_mes_cerrado ya exige incluida_en_sello y toma el peso de la foto: no se toca).
--   7. Censo analítico: la declaración de crm.cerrar_periodo conserva su fila y su clase con la huella del cuerpo nuevo; se resella.
--   8. CHECK `conversion_pesos_referido_con_tope`: una versión con peso de referido mayor que 0,150 exige tope (no se puede apagar el tope por olvido).
--   9. Desempate: dos referidos con la misma fecha comercial (es un día) se ordenan por el instante en que se acreditó cada cierre.
-- QUÉ NO CAMBIA: el divisor, los pesos de renovación y upgrade, las firmas de las puertas de la API y sus ACL, los meses
--   anteriores a octubre, el origen del lead, las anulaciones (siguen siendo la única puerta), las tablas por origen y el
--   desglose de Coordinación (FASE B: hasta entonces muestran el referido sin tope; ver la nota de la fase).
-- EFECTO CONOCIDO: octubre se recalcula en vivo con la regla nueva (es lo pedido). El tope de un mes ya sellado NO se recalcula:
--   la foto manda; anular un cierre ajeno al referido NO vuelve a mover el tope de un mes sellado (la deuda es solo la del cierre
--   anulado).
-- PREFLIGHT: se niega si cambió alguno de los seis cuerpos, su dueño o su ACL, si ya existe alguna de las dos funciones nuevas, si crm.conversion_pesos no es exactamente la fila
--   conocida, si ya existe un mes sellado desde octubre (el tope no puede llegar tarde a una foto) o si el censo no está vigente.
-- POSTFLIGHT: huellas medidas en el banco, tope por mes (septiembre sin tope, octubre 15 %), pesos, columnas y el censo con
--   los MISMOS rojos que antes.
-- REVERSA: supabase/scripts/conversion-tope-referidos/reversa.sql.

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  r record;
begin
  for r in select * from (values
    ('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', '9c606dd40fb9e4b0ea816731b04b1cb1', '{postgres=X/postgres}'),
    ('crm.cerrar_periodo(date)', 'ce1ca52d4310345f9fc512413c13f3e8', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('private.conversion_fijar_sello_trg()', 'e2cb8d42e8d81889aa265396499aa1e6', '{postgres=X/postgres}'),
    ('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])', '155ce2b12754718388c8ca1644c84c90', '{postgres=X/postgres}'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', 'fec614f0df11c6d411bf132c776cce6e', '{postgres=X/postgres}'),
    ('private.peso_referido_conversion(date)', 'db78c8acbb0b0ea0ac3b0d2f0d25e7de', '{postgres=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl) then
      raise exception 'TOPE-REFERIDOS: % cambió desde el ensayo; revisar antes de aplicar', r.firma using errcode = 'P0409';
    end if;
  end loop;
  if to_regprocedure('private.conversion_origen_base_tope(text)') is not null then
    raise exception 'TOPE-REFERIDOS: private.conversion_origen_base_tope ya existe' using errcode = 'P0409';
  end if;
  if to_regprocedure('private.tope_referidos_conversion(date)') is not null then
    raise exception 'TOPE-REFERIDOS: private.tope_referidos_conversion ya existe' using errcode = 'P0409';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'crm' and table_name in ('conversion_pesos', 'periodos_cerrados') and column_name = 'tope_referidos_pct') then
    raise exception 'TOPE-REFERIDOS: la columna tope_referidos_pct ya existe' using errcode = 'P0409';
  end if;
  -- La única versión conocida del peso (07/10/2026): 2026-07-01, referido 0,150 y renovación 0,15.
  if (select count(*) from crm.conversion_pesos) <> 1
     or not exists (select 1 from crm.conversion_pesos cp where cp.vigente_desde = date '2026-07-01' and cp.peso_referido = 0.150 and cp.peso_renovacion = 0.15) then
    raise exception 'TOPE-REFERIDOS: crm.conversion_pesos no es la fila conocida; revisar antes de aplicar' using errcode = 'P0409';
  end if;
  -- El tope no puede llegar tarde a una foto: si ya hay un mes sellado desde octubre, esa foto se pagó sin tope.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= date '2026-10-01') then
    raise exception 'TOPE-REFERIDOS: ya hay un mes sellado desde octubre de 2026; revisar con Miguel antes de aplicar' using errcode = 'P0409';
  end if;
  -- Censo: la declaración de cerrar_periodo existe y está vigente, y el sello está al día.
  if not exists (select 1 from private.analitica_leads_citas_exenciones e join pg_proc p on p.oid = to_regprocedure(e.objeto)
                  where e.objeto = 'crm.cerrar_periodo(date)'
                    and e.huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))) then
    raise exception 'TOPE-REFERIDOS: la declaración analítica de crm.cerrar_periodo no está vigente' using errcode = 'P0409';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'TOPE-REFERIDOS: el sello del censo analítico no está al día' using errcode = 'P0409';
  end if;
end;
$preflight$;

-- Foto del censo ANTES (los rojos ajenos deben seguir exactamente iguales después).
create temporary table tope_censo_antes on commit drop as
  select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c;

-- ── 1 · Tablas: el tope se versiona con el peso y se guarda con la foto ───────────────────────────────────────────────
alter table crm.conversion_pesos
  add column tope_referidos_pct numeric(5,2)
  check (tope_referidos_pct is null or (tope_referidos_pct >= 0 and tope_referidos_pct <= 100));
comment on column crm.conversion_pesos.tope_referidos_pct is
  'Tope de referidos: porcentaje de los cierres del mes de un analista de leads asignados por el sistema (origen landing o formulario; sin referidos, renovaciones, upgrades ni base cargada; redondeado hacia arriba) que los referidos pueden contar. Los referidos que pasan del tope, del más reciente al más antiguo, valen 0. NULL = sin tope (agosto y septiembre de 2026). Rige desde la versión que lo trae (2026-10-01, 15,00). Cambiarlo es una decisión comercial: se inserta una versión nueva, el pasado no se mueve.';
comment on column crm.conversion_pesos.peso_referido is
  'Fracción con la que un cierre de referido suma al numerador. 0,150 hasta septiembre de 2026; desde 2026-10-01 vale 1,000 y está acotado por tope_referidos_pct (cuentan hasta el tope; el resto vale 0). El referido NO entra en el divisor.';

-- Un peso de referido mayor que el de antes (0,150) solo tiene sentido ACOTADO por un tope: si alguien inserta una versión
-- futura del peso y olvida el tope, la versión se rechaza en vez de pagar cada referido a 1 sin límite en silencio.
alter table crm.conversion_pesos
  add constraint conversion_pesos_referido_con_tope check (peso_referido <= 0.150 or tope_referidos_pct is not null);
comment on constraint conversion_pesos_referido_con_tope on crm.conversion_pesos is
  'Un peso de referido mayor que 0,150 exige un tope (tope_referidos_pct no nulo): quitar el tope exige bajar también el peso, nunca ocurre por olvido.';

alter table crm.periodos_cerrados
  add column tope_referidos_pct numeric(5,2)
  check (tope_referidos_pct is null or (tope_referidos_pct >= 0 and tope_referidos_pct <= 100));
comment on column crm.periodos_cerrados.tope_referidos_pct is
  'Tope de referidos con el que se calculó el mes al sellarlo (la foto es la memoria de la regla con la que se pagó). NULL = el mes se selló sin tope.';

insert into crm.conversion_pesos (vigente_desde, peso_referido, peso_renovacion, tope_referidos_pct, nota)
values (date '2026-10-01', 1.000, 0.15, 15.00,
  'Miguel 2026-10-07: desde octubre el referido que cierra vale 1, con tope del 15 % de los cierres del mes del analista de leads asignados por el sistema (landing y formulario; sin referidos, renovaciones, upgrades ni base cargada; redondeo hacia arriba; sin esos cierres el tope es 0); los referidos que pasan del tope, los más recientes, valen 0. Renovación sigue en 0,15. El pasado no se toca.');

-- ── 2 · El lector del tope ─────────────────────────────────────────────────────────────────────────────────────────────
create function private.tope_referidos_conversion(p_mes date)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select cp.tope_referidos_pct
    from crm.conversion_pesos cp
   where cp.vigente_desde <= p_mes
   order by cp.vigente_desde desc
   limit 1
$$;
revoke all on function private.tope_referidos_conversion(date) from public, anon, authenticated, service_role;
comment on function private.tope_referidos_conversion(date) is
  'Tope de referidos vigente para un mes (mayor vigente_desde <= mes), o NULL si esa versión no lo trae o no hay versión. A diferencia de private.peso_referido_conversion NO cae a la versión más antigua: un mes sin versión de tope no lleva tope. SECURITY DEFINER porque crm.conversion_pesos no tiene grants (RLS sin policies). Usada por private.conversion_episodios y crm.cerrar_periodo.';

-- ── 2b · Qué orígenes forman la base del tope ──────────────────────────────────────────────────────────────────────────
create function private.conversion_origen_base_tope(p_origen text)
returns boolean
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $$
  select p_origen in ('landing', 'formulario')
$$;
revoke all on function private.conversion_origen_base_tope(text) from public, anon, authenticated, service_role;
comment on function private.conversion_origen_base_tope(text) is
  'Tope de referidos (Miguel, 07/10/2026): UNA definición de qué orígenes de lead forman la BASE del tope, es decir, los leads que el sistema asigna al analista: landing y formulario. Quedan fuera referido, base_cargada (la carga el supervisor) y los orígenes que no cierran en conversión (oficina, otro, web, campania, whatsapp). NULL con origen NULL. Usada por private.conversion_episodios.';

-- ── 3 · El núcleo del numerador: el tope se aplica donde nace el aporte ───────────────────────────────────────────────
-- private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  -- Los meses COMPLETOS que toca la ventana: el tope de referidos es por analista y por mes de cierre, y su base son
  -- todos los cierres de leads asignados de ESE analista en ese mes, no solo los de un rango parcial. Como cada analista
  -- tiene su propia base, el ámbito (p_global/p_visibles) se aplica antes de calcular el tope sin cambiar su resultado.
  v_ini_mes timestamptz := date_trunc('month', p_ini at time zone 'America/Lima') at time zone 'America/Lima';
  v_mes_ult date := date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')::date;
  v_fin_mes timestamptz := (v_mes_ult::timestamp + interval '1 month') at time zone 'America/Lima';
begin
return query
with marcados as (
  -- El índice único del ledger garantiza un cierre por lead. El cierre queda
  -- en quien lo consiguió, no en quien recibió la llegada. Los otros canales
  -- siguen disponibles para consumidores operativos/capital, con aporte CERO.
  select c.*,
    -- El mes de CIERRE: el de la fecha comercial del cierre del lead.
    date_trunc('month', c.fecha_numerador at time zone 'America/Lima')::date as mes_cierre,
    -- Un cierre cuenta para la base del tope solo si NO está anulado y es el cierre de un lead que el sistema asigna
    -- (private.conversion_origen_base_tope: landing y formulario). Los referidos y la base cargada no entran en la base.
    (not c.anulado and private.conversion_origen_base_tope(c.origen)) as en_base,
    (c.fue_referido and not c.anulado) as es_referido,
    -- Desempate de dos cierres de la MISMA fecha comercial (es un día, sin hora): el que se acreditó antes cuenta antes.
    (select ca.acreditado_en from crm.conversion_acreditaciones ca where ca.lead_id = c.lead_id) as registrado_en
  from private.conversion_cierres(
    v_ini_mes, v_fin_mes, p_periodo, p_global, p_visibles, p_factor, null::uuid[]) c
), con_tope as (
  select m.*,
    count(*) filter (where m.en_base) over (partition by m.analista_id, m.mes_cierre) as base_cierres,
    -- Los referidos de cada analista y mes, del más antiguo al más reciente: cuentan los primeros.
    row_number() over (partition by m.analista_id, m.mes_cierre, m.es_referido
                       order by m.fecha_numerador, m.registrado_en, m.lead_id) as orden_referido,
    private.tope_referidos_conversion(m.mes_cierre) as tope_pct
  from marcados m
)
-- Una llegada por id, por su alta ORIGINAL en Lima. No depende del estado
-- actual ni de cuántas veces se asigne, descarte, rescate o cambie de dueño.
-- La primera asignación se busca en toda la historia ANTES de aplicar ámbito.
-- Sin asignación aún: cuenta en empresa, nunca se inventa un responsable.
select 'recibido'::text, primera.analista_id, l.id, null::uuid,
  l.origen = 'referido', coalesce(primera.aproximado, false),
  'llegada'::text, false, l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, l.creado_en, null::timestamptz,
  case when l.origen in ('landing', 'formulario') and not l.alta_manual
    then 1 else 0 end, 0::numeric
from crm.leads l
left join lateral (
  select la.analista_id, la.aproximado
  from crm.lead_asignaciones la
  where la.lead_id = l.id
  order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
  limit 1
) primera on true
where l.creado_en >= p_ini and l.creado_en < p_fin
  and l.origen in ('landing', 'formulario', 'referido')
  and (p_global or primera.analista_id = any(p_visibles))

union all

-- TOPE DE REFERIDOS (Miguel, 07/10/2026, desde octubre): por analista y mes de cierre, los referidos cuentan hasta el
-- tope % de sus cierres de leads asignados por el sistema (en_base; sin referidos, base cargada ni operaciones; redondeado
-- hacia arriba); los más recientes pasan a valer 0. Sin cierres asignados la base es 0 y todos sus referidos valen 0.
-- Sin tope vigente para el mes (agosto, septiembre) el aporte queda como siempre.
select t.tipo, t.analista_id, t.lead_id, t.operacion_id, t.fue_referido, t.aproximado, t.motivo, t.anulado, t.origen,
  t.categoria, t.mes_origen, t.monto, t.moneda, t.fecha_divisor, t.fecha_numerador, t.aporte_divisor,
  case when t.es_referido and t.tope_pct is not null
         and t.orden_referido > ceil(t.base_cierres * t.tope_pct / 100.0)
       then 0::numeric else t.aporte_numerador end
from con_tope t
where t.fecha_numerador >= p_ini and t.fecha_numerador < p_fin
  and (p_global or t.analista_id = any(p_visibles))

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Renovación usa su propio peso; Upgrade conserva 1.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
-- Las operaciones no entran en la base del tope: salen como siempre.
select 'operacion'::text,
  coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.tipo, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.tipo = 'renovacion' then
    case when p_periodo is not null then private.peso_renovacion_conversion(p_periodo)
      else private.peso_renovacion_conversion(o.periodo) end
    when o.tipo = 'upgrade' then 1 else 0 end
from (
  select o0.*, row_number() over (
    partition by o0.cliente_id, o0.periodo
    order by o0.fecha_operacion, o0.creado_en, o0.id
  ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.elegible_conversion
    and o0.periodo >= date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o0.periodo <= date_trunc('month', p_fin at time zone 'America/Lima')::date
) o
where o.orden_conversion = 1
  and o.fecha_operacion::timestamp at time zone 'America/Lima' >= p_ini
  and o.fecha_operacion::timestamp at time zone 'America/Lima' < p_fin
  and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),
                           o.vendedor_id) = any(p_visibles));
end;
$function$;

comment on function private.conversion_episodios(timestamptz, timestamptz, date, boolean, uuid[], numeric) is
  'Núcleo único de la conversión: llegadas (divisor), cierres de leads y operaciones de cartera (numerador). Desde 2026-10 aplica el TOPE DE REFERIDOS (private.tope_referidos_conversion) por analista y mes de cierre; su base son los cierres de leads asignados por el sistema (private.conversion_origen_base_tope), calculada sobre el mes completo de cada analista y recortada después al rango pedido.';

-- ── 4 · La foto guarda el tope ─────────────────────────────────────────────────────────────────────────────────────────
-- crm.cerrar_periodo(date): mismo texto vivo; el único cambio es que el INSERT de periodos_cerrados guarda tope_referidos_pct.
CREATE OR REPLACE FUNCTION crm.cerrar_periodo(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_fuera_ranking jsonb := '[]'::jsonb;
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
  -- CANDADO GLOBAL primero (20260815235500): serializa este sellado con
  -- CUALQUIER publicacion de metas en vuelo — tambien la de OTRO mes. El
  -- trigger del candado toma el mismo global antes de mirar; sin esto,
  -- publicar P durante el sellado de M>P paria metas muertas bajo el suelo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados')::bigint
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_periodo - date '2000-01-01')::integer
  );

  lock table crm.equipo in share mode;

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
    'modelo_conversion', 'llegadas_v2',
    'medible', v_medible,
    'suelo_historico', v_suelo,
    'motivo_no_medible', v_motivo
  );

  with conv as materialized (
    select cm.*
    from private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, '{}'::uuid[], v_factor
    ) cm
  ), prod as materialized (
    select r.*
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), car as materialized (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), roster as materialized (
    select distinct mv.vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
  ), personas as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
    union
    select p.vendedor_id from prod p where p.vendedor_id is not null
    union
    select c.vendedor_id from car c where c.vendedor_id is not null
  ), elegibles as (
    select r.vendedor_id as persona_id from roster r
    union
    select p.persona_id
    from personas p
    join crm.equipo e
      on e.perfil_id = p.persona_id and e.rol_crm = 'vendedor'
    join crm.equipo s
      on s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor'
  ), fuera as (
    select
      p.persona_id,
      coalesce(nullif(btrim(pf.nombre_completo), ''),
               '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
      coalesce(e.rol_crm, 'fuera_equipo') as rol_crm,
      case
        when e.rol_crm = 'vendedor' then 'analista_sin_supervisor'
        when e.rol_crm = 'supervisor' then 'supervisor'
        when e.rol_crm = 'gerencia' then 'gerencia'
        else 'fuera_estructura'
      end as motivo
    from personas p
    left join crm.equipo e on e.perfil_id = p.persona_id
    left join public.perfiles pf on pf.id = p.persona_id
    where not exists (
      select 1 from elegibles ok where ok.persona_id = p.persona_id
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
      'numerador', coalesce(cv.numerador, 0)
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

  v_cobertura := v_cobertura || jsonb_build_object(
    'fuera_ranking', v_fuera_ranking
  );

  -- Sin analista forma parte del total de empresa, no del ranking de personas.
  -- Se congela junto a la foto; una asignación posterior no reescribe el cierre.
  v_cobertura := v_cobertura || coalesce((
    select jsonb_build_object('conversion_sin_analista', to_jsonb(cm) - 'analista_id')
    from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
    where cm.analista_id is null
  ), '{}'::jsonb);

  -- El peso de la RENOVACION se guarda CON la foto desde el 23/09/2026. Antes
  -- solo se guardaba el del referido, y el de renovacion se RECONSTRUIA a
  -- partir de el al leer: mientras los dos valieron lo mismo no se noto, pero
  -- en cuanto se separan (migracion 20260923155859) un mes sellado contaria la
  -- renovacion con un peso que no es el que se uso. Y eso, una vez sellado, ya
  -- no se puede recuperar: la foto es la unica memoria de con que se calculo.
  -- Tope de referidos (07/10/2026): la foto guarda el tope con el que se calculó el mes, igual que guarda los pesos.
  insert into crm.periodos_cerrados (
    periodo, cerrado_por, automatico, ponderacion_referido, ponderacion_renovacion,
    tope_referidos_pct, meta_revision, cobertura
  ) values (
    p_periodo,
    case when v_automatico then null else v_uid end,
    v_automatico, v_factor, private.peso_renovacion_conversion(p_periodo),
    private.tope_referidos_conversion(p_periodo),
    v_revision, v_cobertura
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
  ), car as (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
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
    union
    select vendedor_id from car where vendedor_id is not null
  ), foto as (
    select
      pe.vendedor_id,
      r.meta_vendedor_id,
      coalesce(r.supervisor_id, supervisor_actual.perfil_id) as supervisor_id,
      coalesce(r.conversion_objetivo, 0::numeric) as conversion_objetivo
    from personas pe
    left join roster r on r.vendedor_id = pe.vendedor_id
    left join crm.equipo vendedor_actual
      on vendedor_actual.perfil_id = pe.vendedor_id
    left join crm.equipo supervisor_actual
      on supervisor_actual.perfil_id = vendedor_actual.supervisor_id
     and supervisor_actual.rol_crm = 'supervisor'
    where r.meta_vendedor_id is not null
       or (
         vendedor_actual.rol_crm = 'vendedor'
         and supervisor_actual.perfil_id is not null
       )
  )
  insert into crm.cierre_mes_vendedor (
    periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
    divisor, divisor_aproximado, divisor_por_motivo,
    cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
    numerador, conversion_pct, estado,
    referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia,
    ajuste_numerador, ajuste_pen, ajuste_usd,
    conversion_objetivo, detalles, cartera
  )
  select
    p_periodo,
    pe.vendedor_id,
    coalesce(nullif(btrim(pf.nombre_completo), ''),
             '(sin nombre · ' || left(pe.vendedor_id::text, 8) || ')'),
    pe.supervisor_id,
    coalesce(nullif(btrim(sup.nombre_completo), ''), '(sin ficha)'),
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
    pe.conversion_objetivo,
    coalesce(det.detalles, '[]'::jsonb),
    jsonb_build_object(
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
  from foto pe
  left join conv c on c.analista_id = pe.vendedor_id
  left join car on car.vendedor_id = pe.vendedor_id
  left join public.perfiles pf on pf.id = pe.vendedor_id
  left join public.perfiles sup on sup.id = pe.supervisor_id
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
      'categoria', dimensiones.categoria,
      'moneda', dimensiones.moneda,
      'capital_objetivo', coalesce(d.capital_objetivo, 0),
      'capital_real', greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0),
      'capital_cumplimiento_pct', case when coalesce(d.capital_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0)
                   / d.capital_objetivo, 2) end,
      'contratos_objetivo', coalesce(d.contratos_objetivo, 0),
      'contratos_real', greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0),
      'contratos_cumplimiento_pct', case when coalesce(d.contratos_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0)
                   / d.contratos_objetivo, 2) end,
      'capital_ajuste', coalesce(aj.capital, 0),
      'contratos_ajuste', coalesce(aj.contratos, 0)
    ) order by array_position(
      array['nuevo','renovacion','upgrade'], dimensiones.categoria
    ), dimensiones.moneda) as detalles
    from (values
      ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
      ('renovacion', 'PEN'), ('renovacion', 'USD'),
      ('upgrade', 'PEN'), ('upgrade', 'USD')
    ) dimensiones(categoria, moneda)
    left join crm.metas_vendedor_detalle d
      on d.meta_vendedor_id = pe.meta_vendedor_id
     and d.categoria = dimensiones.categoria
     and d.moneda = dimensiones.moneda
    left join prod pr on pr.vendedor_id = pe.vendedor_id
      and pr.categoria = dimensiones.categoria
     and pr.moneda = dimensiones.moneda
    left join lateral (
      select coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(sal.aplicado_detalle) e
      where e->>'categoria' = dimensiones.categoria
        and e->>'moneda' = dimensiones.moneda
      limit 1
    ) aj on true
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
$function$;

-- ── 5 · El sello: solo los referidos que CUENTAN quedan incluidos en la foto ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.conversion_fijar_sello_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cuentan uuid[];
begin
  if new.periodo>=date '2026-09-01' and exists(
    select 1 from crm.conversion_politica where activada_en is not null) then
    perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),
      (new.periodo-date '2000-01-01')::integer);
    -- Tope de referidos (07/10/2026): un referido que pasó del tope no se pagó, así que no queda «incluido en el sello» y
    -- anularlo no genera deuda. Los que sí cuentan salen del mismo núcleo que acaba de calcular el mes.
    if new.tope_referidos_pct is not null then
      select coalesce(array_agg(e.lead_id), '{}'::uuid[]) into v_cuentan
        from private.conversion_episodios(
               new.periodo::timestamp at time zone 'America/Lima',
               (new.periodo + interval '1 month')::timestamp at time zone 'America/Lima',
               new.periodo, true, '{}'::uuid[], new.ponderacion_referido) e
       where e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador > 0;
    end if;
    update crm.conversion_acreditaciones ca set sellado_en=new.cerrado_en,
      incluida_en_sello=(ca.estado='acreditada'
        and not private.cierre_externo_anulado(ca.lead_id)
        and private.conversion_exclusion_fuente(ca.fuente_tipo,ca.fuente_id)='elegible'
        and (new.tope_referidos_pct is null or ca.origen is distinct from 'referido' or ca.lead_id = any(v_cuentan))),
      actualizado_en=private.conversion_instante_servidor()
    where ca.periodo_comercial=new.periodo and ca.sellado_en is null;
  end if;
  return new;
end;
$function$;

-- ── 6 · Censo analítico: la declaración de cerrar_periodo con la huella del cuerpo nuevo, y el sello al día ─────────────
update private.analitica_leads_citas_exenciones e set
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
  razon = e.razon || ' 07/10/2026: la foto guarda también el tope de referidos con el que se calculó el mes; la conversión sigue saliendo de conversion_mensual_por_vendedor.'
from pg_proc p
where p.oid = to_regprocedure(e.objeto) and e.objeto = 'crm.cerrar_periodo(date)';
update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc(), sellado_en = now() where id;

-- ── 7 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  r record;
begin
  for r in select * from (values
    ('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', 'f80cd3802628cb3d9c9199b09afc0aee', '{postgres=X/postgres}'),
    ('crm.cerrar_periodo(date)', '05691c6715cf56fe7b44ea5e7cf27fb5', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('private.conversion_fijar_sello_trg()', 'c0ba50fae8b98f47114f7fefa183ba7e', '{postgres=X/postgres}'),
    ('private.tope_referidos_conversion(date)', 'b5f63af791860ba8f284a7302da15e9a', '{postgres=X/postgres}'),
    ('private.conversion_origen_base_tope(text)', 'e3a9b21edb15fbc819cd791fbbf35297', '{postgres=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl and p.prosecdef = (r.firma <> 'private.conversion_origen_base_tope(text)')) then
      raise exception 'TOPE-REFERIDOS postflight: % no quedó como se ensayó', r.firma;
    end if;
  end loop;
  -- El tope por mes y los pesos: septiembre y agosto como siempre; octubre en adelante, 15 % y peso 1.
  if private.tope_referidos_conversion(date '2026-08-01') is not null or private.tope_referidos_conversion(date '2026-09-01') is not null
     or private.tope_referidos_conversion(date '2026-10-01') is distinct from 15.00
     or private.tope_referidos_conversion(date '2026-11-01') is distinct from 15.00
     or private.peso_referido_conversion(date '2026-09-01') is distinct from 0.150
     or private.peso_referido_conversion(date '2026-10-01') is distinct from 1.000
     or private.peso_renovacion_conversion(date '2026-10-01') is distinct from 0.15 then
    raise exception 'TOPE-REFERIDOS postflight: los pesos o el tope por mes no dicen lo ensayado';
  end if;
  if not exists (select 1 from pg_constraint where conname = 'conversion_pesos_referido_con_tope' and conrelid = 'crm.conversion_pesos'::regclass and convalidated) then
    raise exception 'TOPE-REFERIDOS postflight: falta el CHECK que ata el peso al tope';
  end if;
  -- Las dos columnas nuevas existen.
  if (select count(*) from information_schema.columns
       where table_schema = 'crm' and table_name in ('conversion_pesos', 'periodos_cerrados') and column_name = 'tope_referidos_pct') <> 2 then
    raise exception 'TOPE-REFERIDOS postflight: faltan las columnas tope_referidos_pct';
  end if;
  -- Censo: la declaración tocada vigente, el sello al día y los rojos de antes, exactamente los mismos.
  if not exists (select 1 from private.contadores_crudos_leads_citas() c
                  where c.objeto = 'crm.cerrar_periodo(date)' and c.declarada and c.huella_ok) then
    raise exception 'TOPE-REFERIDOS postflight: la declaración analítica de cerrar_periodo no quedó vigente';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'TOPE-REFERIDOS postflight: el sello del censo no quedó al día';
  end if;
  if exists ((select tipo, objeto, declarada, huella_ok from pg_temp.tope_censo_antes
              except select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c)
             union all
             (select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c
              except select tipo, objeto, declarada, huella_ok from pg_temp.tope_censo_antes)) then
    raise exception 'TOPE-REFERIDOS postflight: el censo analítico cambió (rojos nuevos o desaparecidos)';
  end if;
end;
$postflight$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
