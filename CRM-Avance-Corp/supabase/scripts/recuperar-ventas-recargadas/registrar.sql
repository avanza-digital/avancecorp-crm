-- REGISTRO en supabase_migrations.schema_migrations de 20261018032400_crm_recuperar_ventas_recargadas.
-- GENERADO por generar-registrador.mjs: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar
-- la migración. Idempotente; se niega si los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 2293ae62ee624cfb41f31faea939ea43).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_recuperar_ventas_recargadas_registro'));
do $chk$
begin
  if (
    to_regclass('crm.conversion_ventas_recuperadas') is not null
    and to_regprocedure('private.proteger_venta_recuperada()') is not null
    and (select count(*) from crm.conversion_ventas_recuperadas) = 5
  ) is not true then
    raise exception 'REGISTRO: la migración 20261018032400 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261018032400' and (coalesce(name, '') <> 'crm_recuperar_ventas_recargadas' or statements is distinct from array[$mig$-- 20261018032400_crm_recuperar_ventas_recargadas.sql
--
-- Recuperar CINCO ventas de leads que dejaron de contar en la conversión porque su contrato se BORRÓ y se volvió a cargar
-- (antes de que existiera «Reemplazar inversión», que es lo que evita que vuelva a pasar). Decisión de Miguel, 17/10/2026:
-- «esas ventas precisas hay que arreglar» y «ármalo con los cinco». Es una EXCEPCIÓN autorizada, por fila exacta, a la regla
-- de que una anulación es de un solo sentido (20260813235119): la anulación no se borra, queda rehabilitada.
--
-- POR QUÉ NO CUENTAN (medido en producción el 17/10 con solo lectura y con las mismas funciones de la métrica oficial)
--   · La acreditación de la venta (crm.conversion_acreditaciones) sigue apuntando al contrato BORRADO:
--     private.conversion_exclusion_fuente da «fuente_retirada» y private.conversion_cierres no emite el cierre.
--   · Dos de ellas además quedaron ANULADAS al borrar con «Eliminar inversión» (crm.cierres_avance_anulados y la copia en
--     crm.inversiones_eliminadas con conversion_anulada): private.cierre_anulado las da por anuladas para siempre.
--
-- LOS CINCO CASOS (constantes en el bloque CASOS; el preflight exige cada dato tal cual se midió)
--   1. JULIO CESAR NUÑEZ CORONEL · Astrid Centenaro · oct · borrado 001560 y recargado 001560 (c7e75b21) el 05/10.
--   2. NANCY MARIA ATUNCAR VASQUEZ · Nayra Gamero · oct · recargado 001510 (87fd8286) quedó con fecha comercial 30/09
--      (inferida); el original decía 01/10 (registro): se corrige al 01/10 para que la venta siga en octubre.
--   3. MARIA AURORA CCANCE DEL SOLAR · Vladimir Jurado · oct · ANULADA al eliminar 001626; recargado 001626 (6a3153d6).
--   4. VICTOR ANGEL ARANGO CRISOSTOMO · Adelayda Gaspar · oct · ANULADA al eliminar 001621; recargado 001621 (13fb9327).
--      Gerencia lo pasó de «upgrade» a «nuevo» con «Corregir categoría» el 17/10 (decisión de Miguel); el preflight lo exige.
--   5. JOSE PEDRO MEJIA BAZAN · Linda Condori · SEPTIEMBRE · original 001526 (30/09) borrado; recargado 001536 (25b94389)
--      con fecha 01/10: se corrige al 30/09. También pasado a «nuevo» el 17/10. Plazo de septiembre: 22/10 00:00 Lima.
--
-- QUÉ HACE
--   1. Tabla crm.conversion_ventas_recuperadas: UNA fila por venta recuperada, SOLO INSERCIÓN (rechaza UPDATE, DELETE y
--      TRUNCATE), con una validación al insertar (la anulación y la copia que rehabilita son DE ESE lead), RLS sin
--      políticas y sin grants para la API, auditada. Guarda el respaldo de cómo estaba todo. Nada se borra.
--   2. Cuatro funciones, por ancla y con huellas antes y después, pasan a respetar la rehabilitación de ESA fila exacta:
--      · private.cierre_anulado (la definición única de «venta anulada»: conversión, sello y Citas) — 2 anclas;
--      · crm.cierres_estado_fn (el chip «CIERRE ANULADO» de la cartera y la ficha) — 1 ancla;
--      · crm.altas_nuevas_por_analista_fn (el informe «Altas nuevas») — 1 ancla;
--      · crm.anular_cierre_avance (y con ella «Eliminar inversión» de esos contratos): una venta rehabilitada no se vuelve
--        a anular y lo dice con un mensaje entendible (antes diría «Ese cierre ya estaba anulado») — 1 ancla.
--      Una anulación futura de otro lead sigue contando: la excepción es por id de fila, no por lead ni general.
--   3. Por caso, con las filas y los meses bloqueados y sin sellos: corrige la fecha comercial si hace falta (misma
--      válvula que crm.corregir_fecha_cierre_comercial, fuente «correccion_manual», y revaloriza el capital), registra la
--      fila, mueve la acreditación al contrato vivo con su único escritor (private.conversion_acreditar_fuente), vuelve a
--      enlazar el lead (válvula crm.op_privilegiada) y deja una nota en su línea de tiempo. INVARIANTE: misma
--      acreditación, episodio, analista, persona y origen; estado «acreditada»; el mes esperado; venta ya no anulada.
--   4. Postflight: la conversión de septiembre y octubre (private.conversion_episodios, vista global) es IGUAL antes y
--      después para todos los demás leads y operaciones, y cada uno de los cinco tiene exactamente un cierre válido.
--      REFERIDOS (casos 1 y 2): el tope (crm.conversion_pesos: desde octubre un referido pesa 1 y el tope es 15 %) reparte
--      entre TODOS los referidos del analista en el mes, en orden de fecha; recuperar uno mueve el aporte individual de los
--      otros y el suyo puede quedar en 0. Lo que no cambia es la SUMA del analista: sube exactamente una cuota (15 %) por
--      referido recuperado, y así se comprueba (hallazgo P1 de Codex, 18/10/2026).
--
-- EFECTOS A SABER: la venta de 3 y 4 ya no se puede volver a anular (UNIQUE de crm.cierres_avance_anulados): «Anular el
-- cierre» y «Eliminar inversión» de esos contratos se niegan con un mensaje claro; si su inversión cambia, «Reemplazar
-- inversión». Mover la fecha mueve el capital del contrato de mes: 2 (10 000 PEN) pasa de septiembre a octubre y 5
-- (353 000 PEN) de octubre a septiembre. TOCA public.contratos (fecha comercial de 2 y 5) con OK explícito de Miguel
-- (17/10/2026; registrado en «excepciones a public» de MIGRACIONES.md). Deuda conocida del CRM: sin negocio_id (como sus
-- tablas hermanas del esquema crm). Tras aplicar, `npm run gen:types` (la tabla nueva aparece en los tipos sin grants).
--
-- CAPAS: datos + funciones privadas y puertas existentes + una tabla privada sin API. CENSO ANALÍTICO: sin count(.
-- Aplicar en UN mensaje (`supabase db query --linked --file`), ANTES del 22/10/2026 00:00 Lima y con poca actividad
-- (toma el candado global de periodos: mientras dura, se niegan sellar, reabrir, fijar plazo, corregir fecha y reemplazar).
-- REVERSA: supabase/scripts/recuperar-ventas-recargadas/reversa.sql (las cuatro funciones vuelven a su huella: 3 y 4
-- vuelven a contar como anuladas; 1, 2 y 5 siguen contando; las fechas no vuelven solas). PRUEBAS: probar.sh del kit.

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

-- READ COMMITTED a propósito: el escritor de acreditaciones vuelve a leer después de esperar sus candados.
begin;
set transaction isolation level read committed;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
set local search_path = '';
set local quote_all_identifiers = off;

-- Mismas llaves que crm.cerrar_periodo: nadie sella, reabre ni fija plazo mientras se corrige. Los meses de las ventas
-- (septiembre y octubre) se piden SIN esperar y EN ORDEN, antes de mirar nada; si alguno está ocupado no se hizo nada.
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
lock table crm.periodos_cerrados in share mode;
lock table crm.capital_mes_sellos in share mode;
-- Las dos fotos de la conversión (antes y después) tienen que ser comparables: mientras dura (segundos) nadie da de alta
-- ni asigna leads. SHARE no estorba a las lecturas; una escritura concurrente espera o la migración aborta (lock_timeout).
lock table crm.leads in share mode;
lock table crm.lead_asignaciones in share mode;
do $meses$
declare
  v_p date;
begin
  foreach v_p in array array[date '2026-09-01', date '2026-10-01'] loop
    if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'), (v_p - date '2000-01-01')::integer) then
      raise exception 'Otra operación está usando el mes %; vuelve a intentar en unos segundos. No se hizo ningún cambio',
        pg_catalog.to_char(v_p, 'MM/YYYY') using errcode = 'PT409';
    end if;
  end loop;
end
$meses$;

-- ── CASOS (inicio) ─────────────────────────────────────────────────────────────────────────────────────────────────────
create temporary table recuperar_casos (
  caso text primary key,
  lead_id uuid not null,
  perfil_id uuid not null,
  acreditacion_id uuid not null,
  analista_id uuid not null,
  fuente_borrada uuid not null,
  recargado uuid not null,
  capital numeric not null,
  moneda text not null,
  periodo date not null,
  fecha_actual date not null,
  fecha_final date not null,
  anulacion_id uuid,
  copia_anulada_id uuid
) on commit drop;
insert into pg_temp.recuperar_casos values
  ('1 JULIO', '0f091c66-89f1-4dc9-9d4a-120da8499a24', '0e54b414-6a78-4836-b7ca-bb0f8c2cbf7e', 'd6431eb9-0cb0-4935-9ab2-357f893ccac0',
   '2ec5954f-0490-44f2-87cd-af6210f3426f', '5bd38753-215b-4b36-adf2-e353c8216a61', 'c7e75b21-3f9e-454b-8677-0e1f40b79a03',
   60000.00, 'PEN', date '2026-10-01', date '2026-10-05', date '2026-10-05', null, null),
  ('2 NANCY', '3851878c-b5fb-4372-b45e-5f89d39afc85', '9eee9937-ea3f-4966-9275-9b1130e6268d', '09e4e23c-d6d0-4632-af4a-da73ddbf67a8',
   'ad36b962-5175-4e4e-b644-e546897c3a85', '17c2fa0c-df6e-41f7-ba49-26c7f36ccedf', '87fd8286-4082-4a9a-af57-5616935c7628',
   10000.00, 'PEN', date '2026-10-01', date '2026-09-30', date '2026-10-01', null, null),
  ('3 MARIA AURORA', '043ed717-8bf5-4201-99d8-cc0d0ef6233b', 'b36965aa-697e-475a-a142-a8b5f671a659', 'b6c6454c-7731-41d5-a4e7-27cf513c2983',
   '2c10b18a-a15d-4952-952b-c4ab91b96153', 'be35fc10-05e3-48e7-a09f-55ee09d2e503', '6a3153d6-5c4a-4c9f-9767-a8f8b8af689a',
   5000.00, 'PEN', date '2026-10-01', date '2026-10-16', date '2026-10-16', 'c83ee112-a16b-438b-a244-ae488088236b', '3d80caeb-d017-43c1-976b-6201459b1775'),
  ('4 VICTOR', '24eaface-ed34-482c-9c19-70987971aac0', 'cb294a23-bf1c-49d6-bb07-4441b18b2beb', '7f97a73d-890f-4994-bb6a-8696b7143384',
   '244439ac-dbc7-4d27-91d1-941c5dbc6dd5', '9c9e84d9-7168-4cf8-8427-1b0ee305e972', '13fb9327-f8da-4b28-ab40-3e8728f01a98',
   2000.00, 'PEN', date '2026-10-01', date '2026-10-15', date '2026-10-15', '05a8883c-ff8e-48b0-b288-2c77bd83763e', '8fbdc37e-9b30-4f73-86a6-ae8980e01d6e'),
  ('5 JOSE PEDRO', '8276ae9d-9a7c-4720-8248-60c2d99b1afe', '6c9544c4-f6c9-4e94-8e49-8eafd7fd0cf5', '9fe1c595-94cd-4f92-b800-b775369e9725',
   '1de5eba1-e6bb-435d-9eff-74286e881d01', '228a42a0-a00b-42c2-aece-39fb166455bd', '25b94389-1a2a-435f-bdb6-1c0421dc8317',
   353000.00, 'PEN', date '2026-09-01', date '2026-10-01', date '2026-09-30', null, null);
-- ── CASOS (fin) ────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Lo que se cambia, tal como estaba: huella y metadatos (el postflight exige los mismos metadatos después).
create temporary table recuperar_funciones on commit drop as
select p.oid as oid, p.oid::regprocedure::text as firma, p.proowner, p.prosecdef, p.provolatile, p.proconfig, p.proacl,
       md5(pg_catalog.pg_get_functiondef(p.oid)) as huella_antes
from pg_catalog.pg_proc p
where p.oid in ('private.cierre_anulado(uuid)'::regprocedure, 'crm.cierres_estado_fn(uuid[])'::regprocedure,
                'crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, 'crm.anular_cierre_avance(uuid,text)'::regprocedure);

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  v record;
  v_lead record;
  v_acr record;
  v_ctr record;
begin
  if not exists (select 1 from pg_catalog.pg_locks l
                 where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid() and l.granted
                   and l.mode = 'ExclusiveLock' and l.objsubid = 1
                   and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'PREFLIGHT recuperar_ventas: esta sesión no tiene el candado de migraciones';
  end if;
  -- Lo que se cambia y lo que se llama, tal como se ensayó (huellas medidas en producción y en el banco el 17/10/2026).
  if (select count(*) from pg_temp.recuperar_funciones) <> 4
     or (select pg_catalog.string_agg(f.firma || '=' || f.huella_antes, ',' order by f.firma) from pg_temp.recuperar_funciones f)
        is distinct from 'crm.altas_nuevas_por_analista_fn(integer)=b421dfb1f3a317776d9e4e1b9e69dd76,'
                         'crm.anular_cierre_avance(uuid,text)=03b673084dbbbbff7aef21c12e7f30b5,'
                         'crm.cierres_estado_fn(uuid[])=f543c8090d2266f26cfbcd6649b783f4,'
                         'private.cierre_anulado(uuid)=df71c2b1e3cd44b97c3ad84e00637266'
     or (md5(pg_catalog.pg_get_functiondef('private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure)) = '872930922a1d477e27b23243cbfe691a'
         and md5(pg_catalog.pg_get_functiondef('private.conversion_exclusion_fuente(text,uuid)'::regprocedure)) = 'ba11b6f937e4abd9aef9cf29dd21e333'
         and md5(pg_catalog.pg_get_functiondef('private.conversion_plazo_hasta(date)'::regprocedure)) = '4ce984684a471d20aa779365c9b92452'
         and md5(pg_catalog.pg_get_functiondef('private.leads_before_update()'::regprocedure)) = '4ae909f2d56ca650b5595b505e6aa51d'
         and md5(pg_catalog.pg_get_functiondef('private.materializar_capital_valoraciones_para(integer,text,uuid)'::regprocedure)) = '3ae629c22a85f7aaa4cb4923c1293bed') is not true then
    raise exception 'PREFLIGHT recuperar_ventas: cambió una función que la corrección cambia o llama';
  end if;
  if exists (select 1 from pg_temp.recuperar_funciones f where f.proowner <> 'postgres'::regrole)
     or (select f.prosecdef from pg_temp.recuperar_funciones f where f.firma = 'private.cierre_anulado(uuid)')
     or (select f.provolatile from pg_temp.recuperar_funciones f where f.firma = 'private.cierre_anulado(uuid)') <> 's' then
    raise exception 'PREFLIGHT recuperar_ventas: cambiaron los metadatos de una función que se cambia';
  end if;
  if to_regclass('crm.conversion_ventas_recuperadas') is not null
     or to_regprocedure('private.proteger_venta_recuperada()') is not null
     or to_regprocedure('private.validar_venta_recuperada()') is not null then
    raise exception 'PREFLIGHT recuperar_ventas: los objetos nuevos ya existen';
  end if;
  if (select count(*) from pg_temp.recuperar_casos) <> 5 then
    raise exception 'PREFLIGHT recuperar_ventas: se esperaban 5 casos';
  end if;
  -- Ningún mes de estas ventas (ni posterior) está sellado, ni en conversión ni en capital.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= date '2026-09-01')
     or exists (select 1 from crm.capital_mes_sellos s where s.periodo >= date '2026-09-01')
     or exists (select 1 from pg_temp.recuperar_casos c
                where least(c.periodo, pg_catalog.date_trunc('month', c.fecha_actual::timestamp)::date) < date '2026-09-01') then
    raise exception 'PREFLIGHT recuperar_ventas: un mes de estas ventas ya está sellado o queda fuera de septiembre-octubre';
  end if;

  -- Por caso: cada fila se BLOQUEA antes de mirarla (queda bloqueada hasta el final de la transacción).
  for v in select * from pg_temp.recuperar_casos order by caso loop
    select l.* into v_lead from crm.leads l where l.id = v.lead_id for update nowait;
    if not found or v_lead.etapa is distinct from 'convertido' or v_lead.perfil_id is distinct from v.perfil_id
       or (v_lead.contrato_id is not null and v_lead.contrato_id is distinct from v.fuente_borrada) then
      raise exception 'PREFLIGHT recuperar_ventas %: el lead no está como se midió (etapa, perfil o enlace)', v.caso;
    end if;
    select ca.* into v_acr from crm.conversion_acreditaciones ca
      where ca.id = v.acreditacion_id and ca.lead_id = v.lead_id for update nowait;
    if not found or v_acr.fuente_tipo is distinct from 'contrato' or v_acr.fuente_id is distinct from v.fuente_borrada
       or v_acr.estado is distinct from 'acreditada' or v_acr.analista_id is distinct from v.analista_id
       or v_acr.periodo_comercial is distinct from v.periodo or v_acr.sellado_en is not null
       or v_acr.incluida_en_sello is true or v_acr.ajuste_anulacion_en_sello is not null then
      raise exception 'PREFLIGHT recuperar_ventas %: la acreditación no está como se midió', v.caso;
    end if;
    if exists (select 1 from public.contratos c where c.id = v.fuente_borrada) then
      raise exception 'PREFLIGHT recuperar_ventas %: el contrato borrado existe', v.caso;
    end if;
    select c.* into v_ctr from public.contratos c where c.id = v.recargado for update nowait;
    if not found or v_ctr.cliente_id is distinct from v.perfil_id or coalesce(v_ctr.es_demo, false)
       or v_ctr.estado is distinct from 'activo' or v_ctr.analista_cierre_id is distinct from v.analista_id
       or v_ctr.fecha_cierre_comercial is distinct from v.fecha_actual
       or v_ctr.capital is distinct from v.capital or v_ctr.moneda is distinct from v.moneda then
      raise exception 'PREFLIGHT recuperar_ventas %: el contrato vivo no está como se midió', v.caso;
    end if;
    if v_ctr.categoria is distinct from 'nuevo' then
      raise exception 'PREFLIGHT recuperar_ventas %: el contrato vivo es «%»; antes hay que pasarlo a «nuevo» con «Corregir categoría»',
        v.caso, v_ctr.categoria;
    end if;
    if exists (select 1 from crm.conversion_acreditaciones o where o.fuente_tipo = 'contrato' and o.fuente_id = v.recargado) then
      raise exception 'PREFLIGHT recuperar_ventas %: el contrato vivo ya es la venta de otro lead', v.caso;
    end if;
    if exists (select 1 from crm.ajustes_mes_cerrado aj where aj.lead_id = v.lead_id) then
      raise exception 'PREFLIGHT recuperar_ventas %: el lead tiene un ajuste de mes cerrado; requiere revisión', v.caso;
    end if;
    if v.anulacion_id is null then
      if private.cierre_anulado(v.lead_id) then
        raise exception 'PREFLIGHT recuperar_ventas %: la venta está anulada y no figura como anulada en los casos', v.caso;
      end if;
    else
      if not exists (select 1 from crm.cierres_avance_anulados a where a.id = v.anulacion_id and a.lead_id = v.lead_id)
         or not exists (select 1 from crm.inversiones_eliminadas ie
                        where ie.id = v.copia_anulada_id and ie.lead_id = v.lead_id and ie.conversion_anulada
                          and ie.reemplazada_por is null and ie.fuente_tipo = 'contrato' and ie.fuente_id = v.fuente_borrada)
         or exists (select 1 from crm.inversiones_eliminadas ie
                    where ie.lead_id = v.lead_id and ie.conversion_anulada and ie.id <> v.copia_anulada_id)
         or exists (select 1 from crm.cierres_externos ce where ce.lead_id = v.lead_id and ce.es_cierre_inicial and ce.anulado_en is not null) then
        raise exception 'PREFLIGHT recuperar_ventas %: la anulación no es exactamente la medida', v.caso;
      end if;
    end if;
    -- Re-acreditar pone el reloj de la venta en AHORA: con el plazo de carga vencido quedaría fuera de plazo.
    if pg_catalog.clock_timestamp() >= private.conversion_plazo_hasta(v.periodo) then
      raise exception 'PREFLIGHT recuperar_ventas %: venció el plazo de carga de %; no se hizo ningún cambio',
        v.caso, pg_catalog.to_char(v.periodo, 'MM/YYYY');
    end if;
    if pg_catalog.date_trunc('month', v.fecha_final::timestamp)::date is distinct from v.periodo then
      raise exception 'PREFLIGHT recuperar_ventas %: la fecha final no cae en el mes esperado', v.caso;
    end if;
  end loop;
end
$preflight$;

-- La conversión de septiembre y octubre ANTES (vista global), con un corte FIJO que se reusa al final (un lead que entre
-- después del corte queda fuera) y con leads y asignaciones bajo SHARE (nada se da de alta ni se asigna mientras dura).
create temporary table recuperar_corte on commit drop as select pg_catalog.clock_timestamp() as fin;
create temporary table recuperar_episodios_antes on commit drop as
select x.tipo, x.analista_id, x.lead_id, x.operacion_id, x.fue_referido, x.anulado, x.categoria, x.mes_origen, x.aporte_divisor, x.aporte_numerador,
       pg_catalog.date_trunc('month', x.fecha_numerador at time zone 'America/Lima')::date as mes_cierre
from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', (select fin from pg_temp.recuperar_corte), null, true, null, 1) x;
-- Referidos recuperados por analista y mes, con la cuota que cada uno suma a la SUMA del analista: su peso, recortado al
-- tope (private.conversion_episodios reparte n × tope % entre los n referidos del analista y mes, en orden de fecha).
create temporary table recuperar_referidos on commit drop as
select ca.analista_id, c.periodo as mes_cierre, count(*)::integer as recuperados,
       case when private.tope_referidos_conversion(c.periodo) is null then private.peso_referido_conversion(c.periodo)
            else least(private.peso_referido_conversion(c.periodo), private.tope_referidos_conversion(c.periodo) / 100.0) end as cuota
from pg_temp.recuperar_casos c
join crm.conversion_acreditaciones ca on ca.id = c.acreditacion_id and ca.lead_id = c.lead_id
where ca.origen = 'referido'
group by ca.analista_id, c.periodo;
create temporary table recuperar_referidos_antes on commit drop as
select r.analista_id, r.mes_cierre, coalesce(sum(e.aporte_numerador), 0) as suma
from pg_temp.recuperar_referidos r
left join pg_temp.recuperar_episodios_antes e on e.tipo = 'cierre' and e.fue_referido and not e.anulado
  and e.analista_id = r.analista_id and e.mes_cierre = r.mes_cierre
group by r.analista_id, r.mes_cierre;

-- ── 1 · La tabla de ventas recuperadas ────────────────────────────────────────────────────────────────────────────────
create table crm.conversion_ventas_recuperadas (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null,
  acreditacion_id uuid not null,
  fuente_borrada_id uuid not null,
  contrato_vigente_id uuid not null,
  cierre_avance_anulado_id uuid unique references crm.cierres_avance_anulados(id) on delete restrict,
  inversion_eliminada_id uuid unique references crm.inversiones_eliminadas(id) on delete restrict,
  fecha_comercial_antes date not null,
  fecha_comercial_despues date not null,
  motivo text not null check (char_length(btrim(motivo)) between 5 and 300),
  autorizado_por text not null check (char_length(btrim(autorizado_por)) between 3 and 200),
  respaldo jsonb not null,
  transaccion xid8 not null default pg_catalog.pg_current_xact_id(),
  creado_en timestamptz not null default now(),
  constraint conversion_ventas_recuperadas_lead_unico unique (lead_id),
  constraint conversion_ventas_recuperadas_anulacion_completa
    check ((cierre_avance_anulado_id is null) = (inversion_eliminada_id is null))
);
alter table crm.conversion_ventas_recuperadas enable row level security;
revoke all on table crm.conversion_ventas_recuperadas from public, anon, authenticated, service_role;

create function private.proteger_venta_recuperada()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Una venta recuperada no se modifica ni se borra: queda como historia' using errcode = 'P0409';
end
$$;

-- Al insertar: la acreditación, la anulación y la copia que se rehabilitan son DE ESE lead (y la copia, del contrato
-- borrado y con la venta anulada). Sin esto, una fila mal armada podría des-anular la venta de OTRO lead.
create function private.validar_venta_recuperada()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from crm.conversion_acreditaciones ca where ca.id = new.acreditacion_id and ca.lead_id = new.lead_id) then
    raise exception 'Venta recuperada: la acreditación no es de ese lead' using errcode = '23514';
  end if;
  if new.cierre_avance_anulado_id is not null
     and not exists (select 1 from crm.cierres_avance_anulados a where a.id = new.cierre_avance_anulado_id and a.lead_id = new.lead_id) then
    raise exception 'Venta recuperada: la anulación no es de ese lead' using errcode = '23514';
  end if;
  if new.inversion_eliminada_id is not null
     and not exists (select 1 from crm.inversiones_eliminadas ie
                     where ie.id = new.inversion_eliminada_id and ie.lead_id = new.lead_id and ie.conversion_anulada
                       and ie.reemplazada_por is null and ie.fuente_tipo = 'contrato' and ie.fuente_id = new.fuente_borrada_id) then
    raise exception 'Venta recuperada: la copia anulada no es de ese lead y ese contrato' using errcode = '23514';
  end if;
  return new;
end
$$;
revoke all on function private.proteger_venta_recuperada() from public, anon, authenticated, service_role;
revoke all on function private.validar_venta_recuperada() from public, anon, authenticated, service_role;

create trigger trg_conversion_ventas_recuperadas_00_validar
  before insert on crm.conversion_ventas_recuperadas
  for each row execute function private.validar_venta_recuperada();
create trigger trg_conversion_ventas_recuperadas_inmutables
  before update or delete on crm.conversion_ventas_recuperadas
  for each row execute function private.proteger_venta_recuperada();
create trigger trg_conversion_ventas_recuperadas_no_truncate
  before truncate on crm.conversion_ventas_recuperadas
  for each statement execute function private.proteger_venta_recuperada();
create trigger trg_audit_conversion_ventas_recuperadas
  after insert on crm.conversion_ventas_recuperadas
  for each row execute function private.log_audit_crm();

-- ── 2 · Las cuatro funciones respetan la rehabilitación de ESA fila ───────────────────────────────────────────────────
-- Cuerpo vivo + cambios por ancla (cada ancla tiene que aparecer EXACTAMENTE una vez). CREATE OR REPLACE conserva dueño,
-- permisos, comentario y SECURITY; el postflight lo comprueba igual.
create function pg_temp.parchar(p_funcion regprocedure, p_cambios text[]) returns void language plpgsql as $$
declare
  v_def text := pg_catalog.pg_get_functiondef(p_funcion);
  i integer;
begin
  for i in 1 .. array_length(p_cambios, 1) loop
    if (length(v_def) - length(replace(v_def, p_cambios[i][1], ''))) / length(p_cambios[i][1]) <> 1 then
      raise exception 'PARCHE %: el ancla % no aparece exactamente una vez', p_funcion, i;
    end if;
    v_def := replace(v_def, p_cambios[i][1], p_cambios[i][2]);
  end loop;
  execute v_def;
end $$;

select pg_temp.parchar('private.cierre_anulado(uuid)'::regprocedure, array[
  array['    from crm.cierres_avance_anulados ca
    where ca.lead_id = p_lead_id
',
        '    from crm.cierres_avance_anulados ca
    where ca.lead_id = p_lead_id
      -- 18/10/2026: salvo que esa anulación exacta se haya rehabilitado (crm.conversion_ventas_recuperadas).
      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
'],
  array['    where ie.lead_id = p_lead_id and ie.conversion_anulada
',
        '    where ie.lead_id = p_lead_id and ie.conversion_anulada
      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.inversion_eliminada_id = ie.id)
']]);

select pg_temp.parchar('crm.cierres_estado_fn(uuid[])'::regprocedure, array[
  array['    left join crm.cierres_avance_anulados ca on ca.lead_id = l.id
',
        '    left join crm.cierres_avance_anulados ca on ca.lead_id = l.id
      -- 18/10/2026: una anulación rehabilitada (crm.conversion_ventas_recuperadas) ya no se muestra como vigente.
      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
']]);

select pg_temp.parchar('crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, array[
  array['    from crm.cierres_avance_anulados ca
    cross join lateral private.contratos_afectados_por_anulacion(ca.lead_id) x
',
        '    from crm.cierres_avance_anulados ca
    cross join lateral private.contratos_afectados_por_anulacion(ca.lead_id) x
    -- 18/10/2026: salvo una anulación rehabilitada (crm.conversion_ventas_recuperadas).
    where not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
']]);

select pg_temp.parchar('crm.anular_cierre_avance(uuid,text)'::regprocedure, array[
  array['  if exists (select 1 from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id) then
    raise exception using
      errcode = ''P0409'',
      message = ''Ese cierre ya estaba anulado'';
  end if;
',
        '  -- 18/10/2026: una venta anulada y después recuperada (crm.conversion_ventas_recuperadas) no se vuelve a anular.
  if exists (select 1 from crm.conversion_ventas_recuperadas r
             where r.lead_id = p_lead_id and r.cierre_avance_anulado_id is not null) then
    raise exception using
      errcode = ''P0409'',
      message = ''Esta venta se anuló y después se recuperó: no se vuelve a anular. Para corregir su inversión usa «Reemplazar inversión»'';
  end if;
  if exists (select 1 from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id) then
    raise exception using
      errcode = ''P0409'',
      message = ''Ese cierre ya estaba anulado'';
  end if;
']]);

-- ── 3 · Caso por caso ─────────────────────────────────────────────────────────────────────────────────────────────────
do $recuperar$
declare
  v record;
  v_acr record;
  v_acr2 record;
  v_lead record;
  v_ctr record;
  v_corr_previa text;
  v_priv_previa text := current_setting('crm.op_privilegiada', true);
  v_motivo constant text := 'Recuperación de venta perdida al borrar y recargar el contrato (decisión de Miguel, 17/10/2026)';
begin
  for v in select * from pg_temp.recuperar_casos order by caso loop
    -- Ya bloqueadas por el preflight (misma transacción): se releen para trabajar con el estado medido.
    select l.* into v_lead from crm.leads l where l.id = v.lead_id for update;
    select ca.* into v_acr from crm.conversion_acreditaciones ca where ca.id = v.acreditacion_id and ca.lead_id = v.lead_id for update;
    select c.* into v_ctr from public.contratos c where c.id = v.recargado for update;

    -- a. La fecha comercial del contrato vivo, si hace falta (misma válvula que crm.corregir_fecha_cierre_comercial).
    if v_ctr.fecha_cierre_comercial is distinct from v.fecha_final then
      v_corr_previa := current_setting('crm.correccion_periodo_comercial', true);
      perform pg_catalog.set_config('crm.correccion_periodo_comercial', 'on', true);
      update public.contratos c set fecha_cierre_comercial = v.fecha_final, fuente_cierre_comercial = 'correccion_manual'
        where c.id = v.recargado;
      perform pg_catalog.set_config('crm.correccion_periodo_comercial', coalesce(nullif(v_corr_previa, ''), 'off'), true);
      update crm.inversiones i set fecha_comercial = v.fecha_final where i.contrato_id = v.recargado and i.fecha_comercial is distinct from v.fecha_final;
      perform private.materializar_capital_valoraciones_para(1, 'contrato', v.recargado);
      if (select c.fecha_cierre_comercial from public.contratos c where c.id = v.recargado) is distinct from v.fecha_final then
        raise exception 'RECUPERAR %: no se pudo corregir la fecha comercial; no se hizo ningún cambio', v.caso using errcode = '55000';
      end if;
    end if;

    -- b. La fila de la venta recuperada (con la rehabilitación de la anulación exacta, si la hay) ANTES de mover la venta.
    insert into crm.conversion_ventas_recuperadas (lead_id, acreditacion_id, fuente_borrada_id, contrato_vigente_id,
      cierre_avance_anulado_id, inversion_eliminada_id, fecha_comercial_antes, fecha_comercial_despues, motivo, autorizado_por, respaldo)
    values (v.lead_id, v.acreditacion_id, v.fuente_borrada, v.recargado, v.anulacion_id, v.copia_anulada_id,
      v_ctr.fecha_cierre_comercial, v.fecha_final, v_motivo, 'Miguel Briceño (Gerencia), 17/10/2026',
      pg_catalog.jsonb_build_object('caso', v.caso, 'acreditacion_antes', to_jsonb(v_acr),
        'lead_antes', pg_catalog.jsonb_build_object('contrato_id', v_lead.contrato_id, 'perfil_id', v_lead.perfil_id, 'etapa', v_lead.etapa),
        'contrato_antes', pg_catalog.jsonb_build_object('fecha_cierre_comercial', v_ctr.fecha_cierre_comercial,
          'fuente_cierre_comercial', v_ctr.fuente_cierre_comercial, 'categoria', v_ctr.categoria,
          'capital', v_ctr.capital, 'moneda', v_ctr.moneda)));

    if private.cierre_anulado(v.lead_id) then
      raise exception 'RECUPERAR %: la venta sigue anulada después de rehabilitarla; no se hizo ningún cambio', v.caso using errcode = '55000';
    end if;

    -- c. La acreditación pasa al contrato vivo con su único escritor; luego el enlace del lead (entra por su rama idempotente).
    perform private.conversion_acreditar_fuente(v.lead_id, 'contrato', v.recargado, v_motivo);
    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
    update crm.leads l set contrato_id = v.recargado where l.id = v.lead_id;
    perform pg_catalog.set_config('crm.op_privilegiada', coalesce(nullif(v_priv_previa, ''), 'off'), true);
    if (select l.contrato_id from crm.leads l where l.id = v.lead_id) is distinct from v.recargado then
      raise exception 'RECUPERAR %: no se pudo volver a enlazar el lead; no se hizo ningún cambio', v.caso using errcode = '55000';
    end if;

    -- d. INVARIANTE: la misma venta (acreditación, episodio, analista, persona, origen), ahora acreditada al contrato vivo
    --    en el mes esperado.
    select ca.* into v_acr2 from crm.conversion_acreditaciones ca where ca.lead_id = v.lead_id;
    if v_acr2.id is distinct from v.acreditacion_id or v_acr2.fuente_tipo is distinct from 'contrato'
       or v_acr2.fuente_id is distinct from v.recargado or v_acr2.estado is distinct from 'acreditada'
       or v_acr2.episodio_id is distinct from v_acr.episodio_id or v_acr2.analista_id is distinct from v.analista_id
       or v_acr2.inversionista_id is distinct from v_acr.inversionista_id or v_acr2.origen is distinct from v_acr.origen
       or v_acr2.periodo_comercial is distinct from v.periodo then
      raise exception using errcode = 'P0409',
        message = 'RECUPERAR ' || v.caso || ': la venta no quedó como se esperaba; no se hizo ningún cambio',
        detail = pg_catalog.jsonb_build_object('estado', v_acr2.estado, 'periodo', v_acr2.periodo_comercial, 'fuente', v_acr2.fuente_id)::text;
    end if;

    -- e. Una nota en la línea de tiempo del lead (la anulación dejó la suya; la recuperación también).
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v.lead_id, 'nota',
      case when v.anulacion_id is not null then 'Se recuperó la venta anulada al borrar el contrato'
           else 'Se recuperó la venta perdida al borrar el contrato' end,
      pg_catalog.jsonb_build_object('accion', 'recuperacion_venta', 'motivo', v_motivo, 'contrato_id', v.recargado,
        'contrato_borrado_id', v.fuente_borrada, 'rehabilita_anulacion', v.anulacion_id is not null,
        'migracion', '20261018032400'),
      null);
  end loop;
end
$recuperar$;

-- ── 4 · Comentarios ───────────────────────────────────────────────────────────────────────────────────────────────────
comment on table crm.conversion_ventas_recuperadas is
  'Ventas de leads recuperadas tras borrar y recargar su contrato (migración 20261018032400, decisión de Miguel del 17/10/2026). '
  'Una fila por venta, solo inserción, sin API. Si rehabilita una anulación, private.cierre_anulado, crm.cierres_estado_fn, '
  'crm.altas_nuevas_por_analista_fn y crm.anular_cierre_avance dejan de tratar esa fila exacta como vigente.';
comment on column crm.conversion_ventas_recuperadas.id is 'Identificador de la fila.';
comment on column crm.conversion_ventas_recuperadas.lead_id is 'Lead cuya venta se recuperó (sin FK a propósito: no entra a los registros de dependencias de leads).';
comment on column crm.conversion_ventas_recuperadas.acreditacion_id is 'Acreditación de la venta (crm.conversion_acreditaciones), la misma fila antes y después (sin FK a propósito; la valida el trigger al insertar).';
comment on column crm.conversion_ventas_recuperadas.fuente_borrada_id is 'Contrato borrado al que apuntaba la venta (ya no existe).';
comment on column crm.conversion_ventas_recuperadas.contrato_vigente_id is 'Contrato vivo, recargado, al que pasa la venta (sin FK a propósito: no entra al registro de dependencias de contratos).';
comment on column crm.conversion_ventas_recuperadas.cierre_avance_anulado_id is 'Anulación de Avance que esta fila rehabilita (la anulación queda; deja de contar).';
comment on column crm.conversion_ventas_recuperadas.inversion_eliminada_id is 'Copia de «Eliminar inversión» con la venta anulada que esta fila rehabilita.';
comment on column crm.conversion_ventas_recuperadas.fecha_comercial_antes is 'Fecha comercial del contrato vivo antes de la corrección.';
comment on column crm.conversion_ventas_recuperadas.fecha_comercial_despues is 'Fecha comercial del contrato vivo después (igual si no se corrigió).';
comment on column crm.conversion_ventas_recuperadas.motivo is 'Por qué se recuperó.';
comment on column crm.conversion_ventas_recuperadas.autorizado_por is 'Quién lo decidió.';
comment on column crm.conversion_ventas_recuperadas.respaldo is 'Cómo estaban la acreditación, el lead y el contrato antes de la corrección.';
comment on column crm.conversion_ventas_recuperadas.transaccion is 'Transacción que la registró.';
comment on column crm.conversion_ventas_recuperadas.creado_en is 'Cuándo se registró.';
comment on function private.proteger_venta_recuperada() is 'Rechaza UPDATE, DELETE y TRUNCATE de crm.conversion_ventas_recuperadas: solo inserción.';
comment on function private.validar_venta_recuperada() is 'Al insertar en crm.conversion_ventas_recuperadas: la acreditación, la anulación y la copia son de ese lead y de ese contrato.';
comment on function private.cierre_anulado(uuid) is
  'El cierre (conversión) del lead está anulado: cierre externo inicial anulado, anulación de Avance, o conversión anulada y '
  'eliminada (crm.inversiones_eliminadas); desde 20261018032400, salvo que esa anulación exacta esté rehabilitada en '
  'crm.conversion_ventas_recuperadas.';

-- ── 5 · Postflight ────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_distintos integer;
begin
  -- El DDL resultante es EXACTAMENTE el ensayado en el banco, con los mismos metadatos que antes.
  if (select pg_catalog.string_agg(f.firma || '=' || md5(pg_catalog.pg_get_functiondef(f.oid)), ',' order by f.firma) from pg_temp.recuperar_funciones f)
     is distinct from 'crm.altas_nuevas_por_analista_fn(integer)=7136e6ea0786ae7ec166a7957f6e77d2,'
                      'crm.anular_cierre_avance(uuid,text)=9625124158f7d2d04a2a59c4be405942,'
                      'crm.cierres_estado_fn(uuid[])=965b778f15e64d3b5f41b257d6469ec8,'
                      'private.cierre_anulado(uuid)=878d19fffc19bc39649a5105bd51b082' then
    raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada no quedó como se ensayó';
  end if;
  if exists (select 1 from pg_temp.recuperar_funciones f join pg_catalog.pg_proc p on p.oid = f.oid
             where p.proowner is distinct from f.proowner or p.prosecdef is distinct from f.prosecdef
                or p.provolatile is distinct from f.provolatile or p.proconfig is distinct from f.proconfig
                or p.proacl is distinct from f.proacl) then
    raise exception 'POSTFLIGHT recuperar_ventas: cambiaron dueño, seguridad, volatilidad, configuración o permisos de una función';
  end if;
  if not exists (select 1 from pg_catalog.pg_class c where c.oid = 'crm.conversion_ventas_recuperadas'::regclass
                 and c.relrowsecurity and c.relowner = 'postgres'::regrole)
     or exists (select 1 from pg_catalog.pg_policy po where po.polrelid = 'crm.conversion_ventas_recuperadas'::regclass)
     or has_table_privilege('authenticated', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     or has_table_privilege('anon', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     or has_table_privilege('service_role', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     or has_any_column_privilege('authenticated', 'crm.conversion_ventas_recuperadas', 'select, insert, update, references')
     or has_any_column_privilege('anon', 'crm.conversion_ventas_recuperadas', 'select, insert, update, references')
     or has_any_column_privilege('service_role', 'crm.conversion_ventas_recuperadas', 'select, insert, update, references') then
    raise exception 'POSTFLIGHT recuperar_ventas: la tabla nueva tiene RLS, es de postgres, sin políticas y sin privilegios para la API';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in ('private.proteger_venta_recuperada()'::regprocedure, 'private.validar_venta_recuperada()'::regprocedure)
               and (p.proowner <> 'postgres'::regrole or p.prosecdef or p.proconfig is distinct from array['search_path=""']
                    or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                    or has_function_privilege('service_role', p.oid, 'execute'))) then
    raise exception 'POSTFLIGHT recuperar_ventas: las funciones de los triggers nuevos son de postgres, INVOKER y sin EXECUTE para la API';
  end if;
  if (select count(*) from crm.conversion_ventas_recuperadas) <> 5 then
    raise exception 'POSTFLIGHT recuperar_ventas: se esperaban 5 ventas recuperadas';
  end if;
  -- Cada uno de los cinco leads tiene EXACTAMENTE un cierre, sin anular, en el mes esperado y con aporte, salvo un
  -- referido: su aporte individual lo reparte el tope y puede ser 0 (lo que cuenta es la SUMA del analista, abajo).
  -- (fecha_numerador = la fecha comercial de la acreditación; mes_origen es el mes en que llegó el lead).
  if exists (select 1 from pg_temp.recuperar_casos c
             where (select count(*)
                    from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', (select fin from pg_temp.recuperar_corte), null, true, null, 1) x
                    where x.tipo = 'cierre' and x.lead_id = c.lead_id and not x.anulado and (x.aporte_numerador > 0 or x.fue_referido)
                      and x.fecha_numerador >= c.periodo::timestamp at time zone 'America/Lima'
                      and x.fecha_numerador < (c.periodo + interval '1 month')::timestamp at time zone 'America/Lima') <> 1) then
    raise exception 'POSTFLIGHT recuperar_ventas: una venta recuperada no cuenta exactamente una vez en la conversión';
  end if;
  -- Y NADA MÁS cambió en la conversión de septiembre y octubre: mismos episodios para todos los demás leads y operaciones.
  -- El aporte INDIVIDUAL de los referidos de los analistas y meses tocados se deja fuera (el tope lo reparte): se compara
  -- por su suma, abajo. Los candados SHARE sobre leads y asignaciones hacen comparables las dos fotos.
  with despues as (
    select x.tipo, x.analista_id, x.lead_id, x.operacion_id, x.fue_referido, x.anulado, x.categoria, x.mes_origen, x.aporte_divisor, x.aporte_numerador,
           pg_catalog.date_trunc('month', x.fecha_numerador at time zone 'America/Lima')::date as mes_cierre
    from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', (select fin from pg_temp.recuperar_corte), null, true, null, 1) x
  ), a as (
    select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.fue_referido, e.anulado, e.categoria, e.mes_origen, e.aporte_divisor,
           case when e.tipo = 'cierre' and e.fue_referido and not e.anulado
                     and exists (select 1 from pg_temp.recuperar_referidos r where r.analista_id = e.analista_id and r.mes_cierre = e.mes_cierre)
                then null else e.aporte_numerador end as aporte
    from pg_temp.recuperar_episodios_antes e where e.lead_id is null or e.lead_id not in (select lead_id from pg_temp.recuperar_casos)
  ), d as (
    select s.tipo, s.analista_id, s.lead_id, s.operacion_id, s.fue_referido, s.anulado, s.categoria, s.mes_origen, s.aporte_divisor,
           case when s.tipo = 'cierre' and s.fue_referido and not s.anulado
                     and exists (select 1 from pg_temp.recuperar_referidos r where r.analista_id = s.analista_id and r.mes_cierre = s.mes_cierre)
                then null else s.aporte_numerador end as aporte
    from despues s where s.lead_id is null or s.lead_id not in (select lead_id from pg_temp.recuperar_casos)
  )
  select count(*) into v_distintos from ((select * from a except all select * from d) union all (select * from d except all select * from a)) z;
  if v_distintos <> 0 then
    raise exception 'POSTFLIGHT recuperar_ventas: cambiaron % episodios de conversión que no son de las ventas recuperadas', v_distintos;
  end if;
  -- La SUMA de los referidos de cada analista y mes tocados sube EXACTAMENTE una cuota por referido recuperado.
  if exists (select 1 from pg_temp.recuperar_referidos r
             join pg_temp.recuperar_referidos_antes ra on ra.analista_id = r.analista_id and ra.mes_cierre = r.mes_cierre
             where (select coalesce(sum(x.aporte_numerador), 0)
                    from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', (select fin from pg_temp.recuperar_corte), null, true, null, 1) x
                    where x.tipo = 'cierre' and x.fue_referido and not x.anulado and x.analista_id = r.analista_id
                      and pg_catalog.date_trunc('month', x.fecha_numerador at time zone 'America/Lima')::date = r.mes_cierre)
                   <> ra.suma + r.recuperados * r.cuota) then
    raise exception 'POSTFLIGHT recuperar_ventas: la suma de referidos de un analista no subió exactamente una cuota por venta recuperada';
  end if;
  -- F7, vigencia del analista y censo analítico: las funciones cambiadas o nuevas no entran.
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and (p.oid in (select f.oid from pg_temp.recuperar_funciones f)
                    or p.oid in ('private.proteger_venta_recuperada()'::regprocedure, 'private.validar_venta_recuperada()'::regprocedure))
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada nombra una pieza cerrada de F7';
  end if;
  if exists (select 1 from private.puertas_analista_sin_vigencia() c
             where c.objeto in (select f.firma from pg_temp.recuperar_funciones f)
                or c.objeto in ('private.proteger_venta_recuperada()', 'private.validar_venta_recuperada()')) then
    raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada entró al censo de vigencia del analista';
  end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto in (select f.firma from pg_temp.recuperar_funciones f)
                or c.objeto in ('private.proteger_venta_recuperada()', 'private.validar_venta_recuperada()')) then
    raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada entró al censo analítico';
  end if;
end
$postflight$;

commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
$mig$])) then
    raise exception 'REGISTRO: la versión 20261018032400 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261018032400', 'crm_recuperar_ventas_recargadas', array[$mig$-- 20261018032400_crm_recuperar_ventas_recargadas.sql
--
-- Recuperar CINCO ventas de leads que dejaron de contar en la conversión porque su contrato se BORRÓ y se volvió a cargar
-- (antes de que existiera «Reemplazar inversión», que es lo que evita que vuelva a pasar). Decisión de Miguel, 17/10/2026:
-- «esas ventas precisas hay que arreglar» y «ármalo con los cinco». Es una EXCEPCIÓN autorizada, por fila exacta, a la regla
-- de que una anulación es de un solo sentido (20260813235119): la anulación no se borra, queda rehabilitada.
--
-- POR QUÉ NO CUENTAN (medido en producción el 17/10 con solo lectura y con las mismas funciones de la métrica oficial)
--   · La acreditación de la venta (crm.conversion_acreditaciones) sigue apuntando al contrato BORRADO:
--     private.conversion_exclusion_fuente da «fuente_retirada» y private.conversion_cierres no emite el cierre.
--   · Dos de ellas además quedaron ANULADAS al borrar con «Eliminar inversión» (crm.cierres_avance_anulados y la copia en
--     crm.inversiones_eliminadas con conversion_anulada): private.cierre_anulado las da por anuladas para siempre.
--
-- LOS CINCO CASOS (constantes en el bloque CASOS; el preflight exige cada dato tal cual se midió)
--   1. JULIO CESAR NUÑEZ CORONEL · Astrid Centenaro · oct · borrado 001560 y recargado 001560 (c7e75b21) el 05/10.
--   2. NANCY MARIA ATUNCAR VASQUEZ · Nayra Gamero · oct · recargado 001510 (87fd8286) quedó con fecha comercial 30/09
--      (inferida); el original decía 01/10 (registro): se corrige al 01/10 para que la venta siga en octubre.
--   3. MARIA AURORA CCANCE DEL SOLAR · Vladimir Jurado · oct · ANULADA al eliminar 001626; recargado 001626 (6a3153d6).
--   4. VICTOR ANGEL ARANGO CRISOSTOMO · Adelayda Gaspar · oct · ANULADA al eliminar 001621; recargado 001621 (13fb9327).
--      Gerencia lo pasó de «upgrade» a «nuevo» con «Corregir categoría» el 17/10 (decisión de Miguel); el preflight lo exige.
--   5. JOSE PEDRO MEJIA BAZAN · Linda Condori · SEPTIEMBRE · original 001526 (30/09) borrado; recargado 001536 (25b94389)
--      con fecha 01/10: se corrige al 30/09. También pasado a «nuevo» el 17/10. Plazo de septiembre: 22/10 00:00 Lima.
--
-- QUÉ HACE
--   1. Tabla crm.conversion_ventas_recuperadas: UNA fila por venta recuperada, SOLO INSERCIÓN (rechaza UPDATE, DELETE y
--      TRUNCATE), con una validación al insertar (la anulación y la copia que rehabilita son DE ESE lead), RLS sin
--      políticas y sin grants para la API, auditada. Guarda el respaldo de cómo estaba todo. Nada se borra.
--   2. Cuatro funciones, por ancla y con huellas antes y después, pasan a respetar la rehabilitación de ESA fila exacta:
--      · private.cierre_anulado (la definición única de «venta anulada»: conversión, sello y Citas) — 2 anclas;
--      · crm.cierres_estado_fn (el chip «CIERRE ANULADO» de la cartera y la ficha) — 1 ancla;
--      · crm.altas_nuevas_por_analista_fn (el informe «Altas nuevas») — 1 ancla;
--      · crm.anular_cierre_avance (y con ella «Eliminar inversión» de esos contratos): una venta rehabilitada no se vuelve
--        a anular y lo dice con un mensaje entendible (antes diría «Ese cierre ya estaba anulado») — 1 ancla.
--      Una anulación futura de otro lead sigue contando: la excepción es por id de fila, no por lead ni general.
--   3. Por caso, con las filas y los meses bloqueados y sin sellos: corrige la fecha comercial si hace falta (misma
--      válvula que crm.corregir_fecha_cierre_comercial, fuente «correccion_manual», y revaloriza el capital), registra la
--      fila, mueve la acreditación al contrato vivo con su único escritor (private.conversion_acreditar_fuente), vuelve a
--      enlazar el lead (válvula crm.op_privilegiada) y deja una nota en su línea de tiempo. INVARIANTE: misma
--      acreditación, episodio, analista, persona y origen; estado «acreditada»; el mes esperado; venta ya no anulada.
--   4. Postflight: la conversión de septiembre y octubre (private.conversion_episodios, vista global) es IGUAL antes y
--      después para todos los demás leads y operaciones, y cada uno de los cinco tiene exactamente un cierre válido.
--      REFERIDOS (casos 1 y 2): el tope (crm.conversion_pesos: desde octubre un referido pesa 1 y el tope es 15 %) reparte
--      entre TODOS los referidos del analista en el mes, en orden de fecha; recuperar uno mueve el aporte individual de los
--      otros y el suyo puede quedar en 0. Lo que no cambia es la SUMA del analista: sube exactamente una cuota (15 %) por
--      referido recuperado, y así se comprueba (hallazgo P1 de Codex, 18/10/2026).
--
-- EFECTOS A SABER: la venta de 3 y 4 ya no se puede volver a anular (UNIQUE de crm.cierres_avance_anulados): «Anular el
-- cierre» y «Eliminar inversión» de esos contratos se niegan con un mensaje claro; si su inversión cambia, «Reemplazar
-- inversión». Mover la fecha mueve el capital del contrato de mes: 2 (10 000 PEN) pasa de septiembre a octubre y 5
-- (353 000 PEN) de octubre a septiembre. TOCA public.contratos (fecha comercial de 2 y 5) con OK explícito de Miguel
-- (17/10/2026; registrado en «excepciones a public» de MIGRACIONES.md). Deuda conocida del CRM: sin negocio_id (como sus
-- tablas hermanas del esquema crm). Tras aplicar, `npm run gen:types` (la tabla nueva aparece en los tipos sin grants).
--
-- CAPAS: datos + funciones privadas y puertas existentes + una tabla privada sin API. CENSO ANALÍTICO: sin count(.
-- Aplicar en UN mensaje (`supabase db query --linked --file`), ANTES del 22/10/2026 00:00 Lima y con poca actividad
-- (toma el candado global de periodos: mientras dura, se niegan sellar, reabrir, fijar plazo, corregir fecha y reemplazar).
-- REVERSA: supabase/scripts/recuperar-ventas-recargadas/reversa.sql (las cuatro funciones vuelven a su huella: 3 y 4
-- vuelven a contar como anuladas; 1, 2 y 5 siguen contando; las fechas no vuelven solas). PRUEBAS: probar.sh del kit.

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

-- READ COMMITTED a propósito: el escritor de acreditaciones vuelve a leer después de esperar sus candados.
begin;
set transaction isolation level read committed;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
set local search_path = '';
set local quote_all_identifiers = off;

-- Mismas llaves que crm.cerrar_periodo: nadie sella, reabre ni fija plazo mientras se corrige. Los meses de las ventas
-- (septiembre y octubre) se piden SIN esperar y EN ORDEN, antes de mirar nada; si alguno está ocupado no se hizo nada.
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
lock table crm.periodos_cerrados in share mode;
lock table crm.capital_mes_sellos in share mode;
-- Las dos fotos de la conversión (antes y después) tienen que ser comparables: mientras dura (segundos) nadie da de alta
-- ni asigna leads. SHARE no estorba a las lecturas; una escritura concurrente espera o la migración aborta (lock_timeout).
lock table crm.leads in share mode;
lock table crm.lead_asignaciones in share mode;
do $meses$
declare
  v_p date;
begin
  foreach v_p in array array[date '2026-09-01', date '2026-10-01'] loop
    if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'), (v_p - date '2000-01-01')::integer) then
      raise exception 'Otra operación está usando el mes %; vuelve a intentar en unos segundos. No se hizo ningún cambio',
        pg_catalog.to_char(v_p, 'MM/YYYY') using errcode = 'PT409';
    end if;
  end loop;
end
$meses$;

-- ── CASOS (inicio) ─────────────────────────────────────────────────────────────────────────────────────────────────────
create temporary table recuperar_casos (
  caso text primary key,
  lead_id uuid not null,
  perfil_id uuid not null,
  acreditacion_id uuid not null,
  analista_id uuid not null,
  fuente_borrada uuid not null,
  recargado uuid not null,
  capital numeric not null,
  moneda text not null,
  periodo date not null,
  fecha_actual date not null,
  fecha_final date not null,
  anulacion_id uuid,
  copia_anulada_id uuid
) on commit drop;
insert into pg_temp.recuperar_casos values
  ('1 JULIO', '0f091c66-89f1-4dc9-9d4a-120da8499a24', '0e54b414-6a78-4836-b7ca-bb0f8c2cbf7e', 'd6431eb9-0cb0-4935-9ab2-357f893ccac0',
   '2ec5954f-0490-44f2-87cd-af6210f3426f', '5bd38753-215b-4b36-adf2-e353c8216a61', 'c7e75b21-3f9e-454b-8677-0e1f40b79a03',
   60000.00, 'PEN', date '2026-10-01', date '2026-10-05', date '2026-10-05', null, null),
  ('2 NANCY', '3851878c-b5fb-4372-b45e-5f89d39afc85', '9eee9937-ea3f-4966-9275-9b1130e6268d', '09e4e23c-d6d0-4632-af4a-da73ddbf67a8',
   'ad36b962-5175-4e4e-b644-e546897c3a85', '17c2fa0c-df6e-41f7-ba49-26c7f36ccedf', '87fd8286-4082-4a9a-af57-5616935c7628',
   10000.00, 'PEN', date '2026-10-01', date '2026-09-30', date '2026-10-01', null, null),
  ('3 MARIA AURORA', '043ed717-8bf5-4201-99d8-cc0d0ef6233b', 'b36965aa-697e-475a-a142-a8b5f671a659', 'b6c6454c-7731-41d5-a4e7-27cf513c2983',
   '2c10b18a-a15d-4952-952b-c4ab91b96153', 'be35fc10-05e3-48e7-a09f-55ee09d2e503', '6a3153d6-5c4a-4c9f-9767-a8f8b8af689a',
   5000.00, 'PEN', date '2026-10-01', date '2026-10-16', date '2026-10-16', 'c83ee112-a16b-438b-a244-ae488088236b', '3d80caeb-d017-43c1-976b-6201459b1775'),
  ('4 VICTOR', '24eaface-ed34-482c-9c19-70987971aac0', 'cb294a23-bf1c-49d6-bb07-4441b18b2beb', '7f97a73d-890f-4994-bb6a-8696b7143384',
   '244439ac-dbc7-4d27-91d1-941c5dbc6dd5', '9c9e84d9-7168-4cf8-8427-1b0ee305e972', '13fb9327-f8da-4b28-ab40-3e8728f01a98',
   2000.00, 'PEN', date '2026-10-01', date '2026-10-15', date '2026-10-15', '05a8883c-ff8e-48b0-b288-2c77bd83763e', '8fbdc37e-9b30-4f73-86a6-ae8980e01d6e'),
  ('5 JOSE PEDRO', '8276ae9d-9a7c-4720-8248-60c2d99b1afe', '6c9544c4-f6c9-4e94-8e49-8eafd7fd0cf5', '9fe1c595-94cd-4f92-b800-b775369e9725',
   '1de5eba1-e6bb-435d-9eff-74286e881d01', '228a42a0-a00b-42c2-aece-39fb166455bd', '25b94389-1a2a-435f-bdb6-1c0421dc8317',
   353000.00, 'PEN', date '2026-09-01', date '2026-10-01', date '2026-09-30', null, null);
-- ── CASOS (fin) ────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Lo que se cambia, tal como estaba: huella y metadatos (el postflight exige los mismos metadatos después).
create temporary table recuperar_funciones on commit drop as
select p.oid as oid, p.oid::regprocedure::text as firma, p.proowner, p.prosecdef, p.provolatile, p.proconfig, p.proacl,
       md5(pg_catalog.pg_get_functiondef(p.oid)) as huella_antes
from pg_catalog.pg_proc p
where p.oid in ('private.cierre_anulado(uuid)'::regprocedure, 'crm.cierres_estado_fn(uuid[])'::regprocedure,
                'crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, 'crm.anular_cierre_avance(uuid,text)'::regprocedure);

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  v record;
  v_lead record;
  v_acr record;
  v_ctr record;
begin
  if not exists (select 1 from pg_catalog.pg_locks l
                 where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid() and l.granted
                   and l.mode = 'ExclusiveLock' and l.objsubid = 1
                   and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'PREFLIGHT recuperar_ventas: esta sesión no tiene el candado de migraciones';
  end if;
  -- Lo que se cambia y lo que se llama, tal como se ensayó (huellas medidas en producción y en el banco el 17/10/2026).
  if (select count(*) from pg_temp.recuperar_funciones) <> 4
     or (select pg_catalog.string_agg(f.firma || '=' || f.huella_antes, ',' order by f.firma) from pg_temp.recuperar_funciones f)
        is distinct from 'crm.altas_nuevas_por_analista_fn(integer)=b421dfb1f3a317776d9e4e1b9e69dd76,'
                         'crm.anular_cierre_avance(uuid,text)=03b673084dbbbbff7aef21c12e7f30b5,'
                         'crm.cierres_estado_fn(uuid[])=f543c8090d2266f26cfbcd6649b783f4,'
                         'private.cierre_anulado(uuid)=df71c2b1e3cd44b97c3ad84e00637266'
     or (md5(pg_catalog.pg_get_functiondef('private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure)) = '872930922a1d477e27b23243cbfe691a'
         and md5(pg_catalog.pg_get_functiondef('private.conversion_exclusion_fuente(text,uuid)'::regprocedure)) = 'ba11b6f937e4abd9aef9cf29dd21e333'
         and md5(pg_catalog.pg_get_functiondef('private.conversion_plazo_hasta(date)'::regprocedure)) = '4ce984684a471d20aa779365c9b92452'
         and md5(pg_catalog.pg_get_functiondef('private.leads_before_update()'::regprocedure)) = '4ae909f2d56ca650b5595b505e6aa51d'
         and md5(pg_catalog.pg_get_functiondef('private.materializar_capital_valoraciones_para(integer,text,uuid)'::regprocedure)) = '3ae629c22a85f7aaa4cb4923c1293bed') is not true then
    raise exception 'PREFLIGHT recuperar_ventas: cambió una función que la corrección cambia o llama';
  end if;
  if exists (select 1 from pg_temp.recuperar_funciones f where f.proowner <> 'postgres'::regrole)
     or (select f.prosecdef from pg_temp.recuperar_funciones f where f.firma = 'private.cierre_anulado(uuid)')
     or (select f.provolatile from pg_temp.recuperar_funciones f where f.firma = 'private.cierre_anulado(uuid)') <> 's' then
    raise exception 'PREFLIGHT recuperar_ventas: cambiaron los metadatos de una función que se cambia';
  end if;
  if to_regclass('crm.conversion_ventas_recuperadas') is not null
     or to_regprocedure('private.proteger_venta_recuperada()') is not null
     or to_regprocedure('private.validar_venta_recuperada()') is not null then
    raise exception 'PREFLIGHT recuperar_ventas: los objetos nuevos ya existen';
  end if;
  if (select count(*) from pg_temp.recuperar_casos) <> 5 then
    raise exception 'PREFLIGHT recuperar_ventas: se esperaban 5 casos';
  end if;
  -- Ningún mes de estas ventas (ni posterior) está sellado, ni en conversión ni en capital.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= date '2026-09-01')
     or exists (select 1 from crm.capital_mes_sellos s where s.periodo >= date '2026-09-01')
     or exists (select 1 from pg_temp.recuperar_casos c
                where least(c.periodo, pg_catalog.date_trunc('month', c.fecha_actual::timestamp)::date) < date '2026-09-01') then
    raise exception 'PREFLIGHT recuperar_ventas: un mes de estas ventas ya está sellado o queda fuera de septiembre-octubre';
  end if;

  -- Por caso: cada fila se BLOQUEA antes de mirarla (queda bloqueada hasta el final de la transacción).
  for v in select * from pg_temp.recuperar_casos order by caso loop
    select l.* into v_lead from crm.leads l where l.id = v.lead_id for update nowait;
    if not found or v_lead.etapa is distinct from 'convertido' or v_lead.perfil_id is distinct from v.perfil_id
       or (v_lead.contrato_id is not null and v_lead.contrato_id is distinct from v.fuente_borrada) then
      raise exception 'PREFLIGHT recuperar_ventas %: el lead no está como se midió (etapa, perfil o enlace)', v.caso;
    end if;
    select ca.* into v_acr from crm.conversion_acreditaciones ca
      where ca.id = v.acreditacion_id and ca.lead_id = v.lead_id for update nowait;
    if not found or v_acr.fuente_tipo is distinct from 'contrato' or v_acr.fuente_id is distinct from v.fuente_borrada
       or v_acr.estado is distinct from 'acreditada' or v_acr.analista_id is distinct from v.analista_id
       or v_acr.periodo_comercial is distinct from v.periodo or v_acr.sellado_en is not null
       or v_acr.incluida_en_sello is true or v_acr.ajuste_anulacion_en_sello is not null then
      raise exception 'PREFLIGHT recuperar_ventas %: la acreditación no está como se midió', v.caso;
    end if;
    if exists (select 1 from public.contratos c where c.id = v.fuente_borrada) then
      raise exception 'PREFLIGHT recuperar_ventas %: el contrato borrado existe', v.caso;
    end if;
    select c.* into v_ctr from public.contratos c where c.id = v.recargado for update nowait;
    if not found or v_ctr.cliente_id is distinct from v.perfil_id or coalesce(v_ctr.es_demo, false)
       or v_ctr.estado is distinct from 'activo' or v_ctr.analista_cierre_id is distinct from v.analista_id
       or v_ctr.fecha_cierre_comercial is distinct from v.fecha_actual
       or v_ctr.capital is distinct from v.capital or v_ctr.moneda is distinct from v.moneda then
      raise exception 'PREFLIGHT recuperar_ventas %: el contrato vivo no está como se midió', v.caso;
    end if;
    if v_ctr.categoria is distinct from 'nuevo' then
      raise exception 'PREFLIGHT recuperar_ventas %: el contrato vivo es «%»; antes hay que pasarlo a «nuevo» con «Corregir categoría»',
        v.caso, v_ctr.categoria;
    end if;
    if exists (select 1 from crm.conversion_acreditaciones o where o.fuente_tipo = 'contrato' and o.fuente_id = v.recargado) then
      raise exception 'PREFLIGHT recuperar_ventas %: el contrato vivo ya es la venta de otro lead', v.caso;
    end if;
    if exists (select 1 from crm.ajustes_mes_cerrado aj where aj.lead_id = v.lead_id) then
      raise exception 'PREFLIGHT recuperar_ventas %: el lead tiene un ajuste de mes cerrado; requiere revisión', v.caso;
    end if;
    if v.anulacion_id is null then
      if private.cierre_anulado(v.lead_id) then
        raise exception 'PREFLIGHT recuperar_ventas %: la venta está anulada y no figura como anulada en los casos', v.caso;
      end if;
    else
      if not exists (select 1 from crm.cierres_avance_anulados a where a.id = v.anulacion_id and a.lead_id = v.lead_id)
         or not exists (select 1 from crm.inversiones_eliminadas ie
                        where ie.id = v.copia_anulada_id and ie.lead_id = v.lead_id and ie.conversion_anulada
                          and ie.reemplazada_por is null and ie.fuente_tipo = 'contrato' and ie.fuente_id = v.fuente_borrada)
         or exists (select 1 from crm.inversiones_eliminadas ie
                    where ie.lead_id = v.lead_id and ie.conversion_anulada and ie.id <> v.copia_anulada_id)
         or exists (select 1 from crm.cierres_externos ce where ce.lead_id = v.lead_id and ce.es_cierre_inicial and ce.anulado_en is not null) then
        raise exception 'PREFLIGHT recuperar_ventas %: la anulación no es exactamente la medida', v.caso;
      end if;
    end if;
    -- Re-acreditar pone el reloj de la venta en AHORA: con el plazo de carga vencido quedaría fuera de plazo.
    if pg_catalog.clock_timestamp() >= private.conversion_plazo_hasta(v.periodo) then
      raise exception 'PREFLIGHT recuperar_ventas %: venció el plazo de carga de %; no se hizo ningún cambio',
        v.caso, pg_catalog.to_char(v.periodo, 'MM/YYYY');
    end if;
    if pg_catalog.date_trunc('month', v.fecha_final::timestamp)::date is distinct from v.periodo then
      raise exception 'PREFLIGHT recuperar_ventas %: la fecha final no cae en el mes esperado', v.caso;
    end if;
  end loop;
end
$preflight$;

-- La conversión de septiembre y octubre ANTES (vista global), con un corte FIJO que se reusa al final (un lead que entre
-- después del corte queda fuera) y con leads y asignaciones bajo SHARE (nada se da de alta ni se asigna mientras dura).
create temporary table recuperar_corte on commit drop as select pg_catalog.clock_timestamp() as fin;
create temporary table recuperar_episodios_antes on commit drop as
select x.tipo, x.analista_id, x.lead_id, x.operacion_id, x.fue_referido, x.anulado, x.categoria, x.mes_origen, x.aporte_divisor, x.aporte_numerador,
       pg_catalog.date_trunc('month', x.fecha_numerador at time zone 'America/Lima')::date as mes_cierre
from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', (select fin from pg_temp.recuperar_corte), null, true, null, 1) x;
-- Referidos recuperados por analista y mes, con la cuota que cada uno suma a la SUMA del analista: su peso, recortado al
-- tope (private.conversion_episodios reparte n × tope % entre los n referidos del analista y mes, en orden de fecha).
create temporary table recuperar_referidos on commit drop as
select ca.analista_id, c.periodo as mes_cierre, count(*)::integer as recuperados,
       case when private.tope_referidos_conversion(c.periodo) is null then private.peso_referido_conversion(c.periodo)
            else least(private.peso_referido_conversion(c.periodo), private.tope_referidos_conversion(c.periodo) / 100.0) end as cuota
from pg_temp.recuperar_casos c
join crm.conversion_acreditaciones ca on ca.id = c.acreditacion_id and ca.lead_id = c.lead_id
where ca.origen = 'referido'
group by ca.analista_id, c.periodo;
create temporary table recuperar_referidos_antes on commit drop as
select r.analista_id, r.mes_cierre, coalesce(sum(e.aporte_numerador), 0) as suma
from pg_temp.recuperar_referidos r
left join pg_temp.recuperar_episodios_antes e on e.tipo = 'cierre' and e.fue_referido and not e.anulado
  and e.analista_id = r.analista_id and e.mes_cierre = r.mes_cierre
group by r.analista_id, r.mes_cierre;

-- ── 1 · La tabla de ventas recuperadas ────────────────────────────────────────────────────────────────────────────────
create table crm.conversion_ventas_recuperadas (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null,
  acreditacion_id uuid not null,
  fuente_borrada_id uuid not null,
  contrato_vigente_id uuid not null,
  cierre_avance_anulado_id uuid unique references crm.cierres_avance_anulados(id) on delete restrict,
  inversion_eliminada_id uuid unique references crm.inversiones_eliminadas(id) on delete restrict,
  fecha_comercial_antes date not null,
  fecha_comercial_despues date not null,
  motivo text not null check (char_length(btrim(motivo)) between 5 and 300),
  autorizado_por text not null check (char_length(btrim(autorizado_por)) between 3 and 200),
  respaldo jsonb not null,
  transaccion xid8 not null default pg_catalog.pg_current_xact_id(),
  creado_en timestamptz not null default now(),
  constraint conversion_ventas_recuperadas_lead_unico unique (lead_id),
  constraint conversion_ventas_recuperadas_anulacion_completa
    check ((cierre_avance_anulado_id is null) = (inversion_eliminada_id is null))
);
alter table crm.conversion_ventas_recuperadas enable row level security;
revoke all on table crm.conversion_ventas_recuperadas from public, anon, authenticated, service_role;

create function private.proteger_venta_recuperada()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Una venta recuperada no se modifica ni se borra: queda como historia' using errcode = 'P0409';
end
$$;

-- Al insertar: la acreditación, la anulación y la copia que se rehabilitan son DE ESE lead (y la copia, del contrato
-- borrado y con la venta anulada). Sin esto, una fila mal armada podría des-anular la venta de OTRO lead.
create function private.validar_venta_recuperada()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from crm.conversion_acreditaciones ca where ca.id = new.acreditacion_id and ca.lead_id = new.lead_id) then
    raise exception 'Venta recuperada: la acreditación no es de ese lead' using errcode = '23514';
  end if;
  if new.cierre_avance_anulado_id is not null
     and not exists (select 1 from crm.cierres_avance_anulados a where a.id = new.cierre_avance_anulado_id and a.lead_id = new.lead_id) then
    raise exception 'Venta recuperada: la anulación no es de ese lead' using errcode = '23514';
  end if;
  if new.inversion_eliminada_id is not null
     and not exists (select 1 from crm.inversiones_eliminadas ie
                     where ie.id = new.inversion_eliminada_id and ie.lead_id = new.lead_id and ie.conversion_anulada
                       and ie.reemplazada_por is null and ie.fuente_tipo = 'contrato' and ie.fuente_id = new.fuente_borrada_id) then
    raise exception 'Venta recuperada: la copia anulada no es de ese lead y ese contrato' using errcode = '23514';
  end if;
  return new;
end
$$;
revoke all on function private.proteger_venta_recuperada() from public, anon, authenticated, service_role;
revoke all on function private.validar_venta_recuperada() from public, anon, authenticated, service_role;

create trigger trg_conversion_ventas_recuperadas_00_validar
  before insert on crm.conversion_ventas_recuperadas
  for each row execute function private.validar_venta_recuperada();
create trigger trg_conversion_ventas_recuperadas_inmutables
  before update or delete on crm.conversion_ventas_recuperadas
  for each row execute function private.proteger_venta_recuperada();
create trigger trg_conversion_ventas_recuperadas_no_truncate
  before truncate on crm.conversion_ventas_recuperadas
  for each statement execute function private.proteger_venta_recuperada();
create trigger trg_audit_conversion_ventas_recuperadas
  after insert on crm.conversion_ventas_recuperadas
  for each row execute function private.log_audit_crm();

-- ── 2 · Las cuatro funciones respetan la rehabilitación de ESA fila ───────────────────────────────────────────────────
-- Cuerpo vivo + cambios por ancla (cada ancla tiene que aparecer EXACTAMENTE una vez). CREATE OR REPLACE conserva dueño,
-- permisos, comentario y SECURITY; el postflight lo comprueba igual.
create function pg_temp.parchar(p_funcion regprocedure, p_cambios text[]) returns void language plpgsql as $$
declare
  v_def text := pg_catalog.pg_get_functiondef(p_funcion);
  i integer;
begin
  for i in 1 .. array_length(p_cambios, 1) loop
    if (length(v_def) - length(replace(v_def, p_cambios[i][1], ''))) / length(p_cambios[i][1]) <> 1 then
      raise exception 'PARCHE %: el ancla % no aparece exactamente una vez', p_funcion, i;
    end if;
    v_def := replace(v_def, p_cambios[i][1], p_cambios[i][2]);
  end loop;
  execute v_def;
end $$;

select pg_temp.parchar('private.cierre_anulado(uuid)'::regprocedure, array[
  array['    from crm.cierres_avance_anulados ca
    where ca.lead_id = p_lead_id
',
        '    from crm.cierres_avance_anulados ca
    where ca.lead_id = p_lead_id
      -- 18/10/2026: salvo que esa anulación exacta se haya rehabilitado (crm.conversion_ventas_recuperadas).
      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
'],
  array['    where ie.lead_id = p_lead_id and ie.conversion_anulada
',
        '    where ie.lead_id = p_lead_id and ie.conversion_anulada
      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.inversion_eliminada_id = ie.id)
']]);

select pg_temp.parchar('crm.cierres_estado_fn(uuid[])'::regprocedure, array[
  array['    left join crm.cierres_avance_anulados ca on ca.lead_id = l.id
',
        '    left join crm.cierres_avance_anulados ca on ca.lead_id = l.id
      -- 18/10/2026: una anulación rehabilitada (crm.conversion_ventas_recuperadas) ya no se muestra como vigente.
      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
']]);

select pg_temp.parchar('crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, array[
  array['    from crm.cierres_avance_anulados ca
    cross join lateral private.contratos_afectados_por_anulacion(ca.lead_id) x
',
        '    from crm.cierres_avance_anulados ca
    cross join lateral private.contratos_afectados_por_anulacion(ca.lead_id) x
    -- 18/10/2026: salvo una anulación rehabilitada (crm.conversion_ventas_recuperadas).
    where not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
']]);

select pg_temp.parchar('crm.anular_cierre_avance(uuid,text)'::regprocedure, array[
  array['  if exists (select 1 from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id) then
    raise exception using
      errcode = ''P0409'',
      message = ''Ese cierre ya estaba anulado'';
  end if;
',
        '  -- 18/10/2026: una venta anulada y después recuperada (crm.conversion_ventas_recuperadas) no se vuelve a anular.
  if exists (select 1 from crm.conversion_ventas_recuperadas r
             where r.lead_id = p_lead_id and r.cierre_avance_anulado_id is not null) then
    raise exception using
      errcode = ''P0409'',
      message = ''Esta venta se anuló y después se recuperó: no se vuelve a anular. Para corregir su inversión usa «Reemplazar inversión»'';
  end if;
  if exists (select 1 from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id) then
    raise exception using
      errcode = ''P0409'',
      message = ''Ese cierre ya estaba anulado'';
  end if;
']]);

-- ── 3 · Caso por caso ─────────────────────────────────────────────────────────────────────────────────────────────────
do $recuperar$
declare
  v record;
  v_acr record;
  v_acr2 record;
  v_lead record;
  v_ctr record;
  v_corr_previa text;
  v_priv_previa text := current_setting('crm.op_privilegiada', true);
  v_motivo constant text := 'Recuperación de venta perdida al borrar y recargar el contrato (decisión de Miguel, 17/10/2026)';
begin
  for v in select * from pg_temp.recuperar_casos order by caso loop
    -- Ya bloqueadas por el preflight (misma transacción): se releen para trabajar con el estado medido.
    select l.* into v_lead from crm.leads l where l.id = v.lead_id for update;
    select ca.* into v_acr from crm.conversion_acreditaciones ca where ca.id = v.acreditacion_id and ca.lead_id = v.lead_id for update;
    select c.* into v_ctr from public.contratos c where c.id = v.recargado for update;

    -- a. La fecha comercial del contrato vivo, si hace falta (misma válvula que crm.corregir_fecha_cierre_comercial).
    if v_ctr.fecha_cierre_comercial is distinct from v.fecha_final then
      v_corr_previa := current_setting('crm.correccion_periodo_comercial', true);
      perform pg_catalog.set_config('crm.correccion_periodo_comercial', 'on', true);
      update public.contratos c set fecha_cierre_comercial = v.fecha_final, fuente_cierre_comercial = 'correccion_manual'
        where c.id = v.recargado;
      perform pg_catalog.set_config('crm.correccion_periodo_comercial', coalesce(nullif(v_corr_previa, ''), 'off'), true);
      update crm.inversiones i set fecha_comercial = v.fecha_final where i.contrato_id = v.recargado and i.fecha_comercial is distinct from v.fecha_final;
      perform private.materializar_capital_valoraciones_para(1, 'contrato', v.recargado);
      if (select c.fecha_cierre_comercial from public.contratos c where c.id = v.recargado) is distinct from v.fecha_final then
        raise exception 'RECUPERAR %: no se pudo corregir la fecha comercial; no se hizo ningún cambio', v.caso using errcode = '55000';
      end if;
    end if;

    -- b. La fila de la venta recuperada (con la rehabilitación de la anulación exacta, si la hay) ANTES de mover la venta.
    insert into crm.conversion_ventas_recuperadas (lead_id, acreditacion_id, fuente_borrada_id, contrato_vigente_id,
      cierre_avance_anulado_id, inversion_eliminada_id, fecha_comercial_antes, fecha_comercial_despues, motivo, autorizado_por, respaldo)
    values (v.lead_id, v.acreditacion_id, v.fuente_borrada, v.recargado, v.anulacion_id, v.copia_anulada_id,
      v_ctr.fecha_cierre_comercial, v.fecha_final, v_motivo, 'Miguel Briceño (Gerencia), 17/10/2026',
      pg_catalog.jsonb_build_object('caso', v.caso, 'acreditacion_antes', to_jsonb(v_acr),
        'lead_antes', pg_catalog.jsonb_build_object('contrato_id', v_lead.contrato_id, 'perfil_id', v_lead.perfil_id, 'etapa', v_lead.etapa),
        'contrato_antes', pg_catalog.jsonb_build_object('fecha_cierre_comercial', v_ctr.fecha_cierre_comercial,
          'fuente_cierre_comercial', v_ctr.fuente_cierre_comercial, 'categoria', v_ctr.categoria,
          'capital', v_ctr.capital, 'moneda', v_ctr.moneda)));

    if private.cierre_anulado(v.lead_id) then
      raise exception 'RECUPERAR %: la venta sigue anulada después de rehabilitarla; no se hizo ningún cambio', v.caso using errcode = '55000';
    end if;

    -- c. La acreditación pasa al contrato vivo con su único escritor; luego el enlace del lead (entra por su rama idempotente).
    perform private.conversion_acreditar_fuente(v.lead_id, 'contrato', v.recargado, v_motivo);
    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
    update crm.leads l set contrato_id = v.recargado where l.id = v.lead_id;
    perform pg_catalog.set_config('crm.op_privilegiada', coalesce(nullif(v_priv_previa, ''), 'off'), true);
    if (select l.contrato_id from crm.leads l where l.id = v.lead_id) is distinct from v.recargado then
      raise exception 'RECUPERAR %: no se pudo volver a enlazar el lead; no se hizo ningún cambio', v.caso using errcode = '55000';
    end if;

    -- d. INVARIANTE: la misma venta (acreditación, episodio, analista, persona, origen), ahora acreditada al contrato vivo
    --    en el mes esperado.
    select ca.* into v_acr2 from crm.conversion_acreditaciones ca where ca.lead_id = v.lead_id;
    if v_acr2.id is distinct from v.acreditacion_id or v_acr2.fuente_tipo is distinct from 'contrato'
       or v_acr2.fuente_id is distinct from v.recargado or v_acr2.estado is distinct from 'acreditada'
       or v_acr2.episodio_id is distinct from v_acr.episodio_id or v_acr2.analista_id is distinct from v.analista_id
       or v_acr2.inversionista_id is distinct from v_acr.inversionista_id or v_acr2.origen is distinct from v_acr.origen
       or v_acr2.periodo_comercial is distinct from v.periodo then
      raise exception using errcode = 'P0409',
        message = 'RECUPERAR ' || v.caso || ': la venta no quedó como se esperaba; no se hizo ningún cambio',
        detail = pg_catalog.jsonb_build_object('estado', v_acr2.estado, 'periodo', v_acr2.periodo_comercial, 'fuente', v_acr2.fuente_id)::text;
    end if;

    -- e. Una nota en la línea de tiempo del lead (la anulación dejó la suya; la recuperación también).
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v.lead_id, 'nota',
      case when v.anulacion_id is not null then 'Se recuperó la venta anulada al borrar el contrato'
           else 'Se recuperó la venta perdida al borrar el contrato' end,
      pg_catalog.jsonb_build_object('accion', 'recuperacion_venta', 'motivo', v_motivo, 'contrato_id', v.recargado,
        'contrato_borrado_id', v.fuente_borrada, 'rehabilita_anulacion', v.anulacion_id is not null,
        'migracion', '20261018032400'),
      null);
  end loop;
end
$recuperar$;

-- ── 4 · Comentarios ───────────────────────────────────────────────────────────────────────────────────────────────────
comment on table crm.conversion_ventas_recuperadas is
  'Ventas de leads recuperadas tras borrar y recargar su contrato (migración 20261018032400, decisión de Miguel del 17/10/2026). '
  'Una fila por venta, solo inserción, sin API. Si rehabilita una anulación, private.cierre_anulado, crm.cierres_estado_fn, '
  'crm.altas_nuevas_por_analista_fn y crm.anular_cierre_avance dejan de tratar esa fila exacta como vigente.';
comment on column crm.conversion_ventas_recuperadas.id is 'Identificador de la fila.';
comment on column crm.conversion_ventas_recuperadas.lead_id is 'Lead cuya venta se recuperó (sin FK a propósito: no entra a los registros de dependencias de leads).';
comment on column crm.conversion_ventas_recuperadas.acreditacion_id is 'Acreditación de la venta (crm.conversion_acreditaciones), la misma fila antes y después (sin FK a propósito; la valida el trigger al insertar).';
comment on column crm.conversion_ventas_recuperadas.fuente_borrada_id is 'Contrato borrado al que apuntaba la venta (ya no existe).';
comment on column crm.conversion_ventas_recuperadas.contrato_vigente_id is 'Contrato vivo, recargado, al que pasa la venta (sin FK a propósito: no entra al registro de dependencias de contratos).';
comment on column crm.conversion_ventas_recuperadas.cierre_avance_anulado_id is 'Anulación de Avance que esta fila rehabilita (la anulación queda; deja de contar).';
comment on column crm.conversion_ventas_recuperadas.inversion_eliminada_id is 'Copia de «Eliminar inversión» con la venta anulada que esta fila rehabilita.';
comment on column crm.conversion_ventas_recuperadas.fecha_comercial_antes is 'Fecha comercial del contrato vivo antes de la corrección.';
comment on column crm.conversion_ventas_recuperadas.fecha_comercial_despues is 'Fecha comercial del contrato vivo después (igual si no se corrigió).';
comment on column crm.conversion_ventas_recuperadas.motivo is 'Por qué se recuperó.';
comment on column crm.conversion_ventas_recuperadas.autorizado_por is 'Quién lo decidió.';
comment on column crm.conversion_ventas_recuperadas.respaldo is 'Cómo estaban la acreditación, el lead y el contrato antes de la corrección.';
comment on column crm.conversion_ventas_recuperadas.transaccion is 'Transacción que la registró.';
comment on column crm.conversion_ventas_recuperadas.creado_en is 'Cuándo se registró.';
comment on function private.proteger_venta_recuperada() is 'Rechaza UPDATE, DELETE y TRUNCATE de crm.conversion_ventas_recuperadas: solo inserción.';
comment on function private.validar_venta_recuperada() is 'Al insertar en crm.conversion_ventas_recuperadas: la acreditación, la anulación y la copia son de ese lead y de ese contrato.';
comment on function private.cierre_anulado(uuid) is
  'El cierre (conversión) del lead está anulado: cierre externo inicial anulado, anulación de Avance, o conversión anulada y '
  'eliminada (crm.inversiones_eliminadas); desde 20261018032400, salvo que esa anulación exacta esté rehabilitada en '
  'crm.conversion_ventas_recuperadas.';

-- ── 5 · Postflight ────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_distintos integer;
begin
  -- El DDL resultante es EXACTAMENTE el ensayado en el banco, con los mismos metadatos que antes.
  if (select pg_catalog.string_agg(f.firma || '=' || md5(pg_catalog.pg_get_functiondef(f.oid)), ',' order by f.firma) from pg_temp.recuperar_funciones f)
     is distinct from 'crm.altas_nuevas_por_analista_fn(integer)=7136e6ea0786ae7ec166a7957f6e77d2,'
                      'crm.anular_cierre_avance(uuid,text)=9625124158f7d2d04a2a59c4be405942,'
                      'crm.cierres_estado_fn(uuid[])=965b778f15e64d3b5f41b257d6469ec8,'
                      'private.cierre_anulado(uuid)=878d19fffc19bc39649a5105bd51b082' then
    raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada no quedó como se ensayó';
  end if;
  if exists (select 1 from pg_temp.recuperar_funciones f join pg_catalog.pg_proc p on p.oid = f.oid
             where p.proowner is distinct from f.proowner or p.prosecdef is distinct from f.prosecdef
                or p.provolatile is distinct from f.provolatile or p.proconfig is distinct from f.proconfig
                or p.proacl is distinct from f.proacl) then
    raise exception 'POSTFLIGHT recuperar_ventas: cambiaron dueño, seguridad, volatilidad, configuración o permisos de una función';
  end if;
  if not exists (select 1 from pg_catalog.pg_class c where c.oid = 'crm.conversion_ventas_recuperadas'::regclass
                 and c.relrowsecurity and c.relowner = 'postgres'::regrole)
     or exists (select 1 from pg_catalog.pg_policy po where po.polrelid = 'crm.conversion_ventas_recuperadas'::regclass)
     or has_table_privilege('authenticated', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     or has_table_privilege('anon', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     or has_table_privilege('service_role', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     or has_any_column_privilege('authenticated', 'crm.conversion_ventas_recuperadas', 'select, insert, update, references')
     or has_any_column_privilege('anon', 'crm.conversion_ventas_recuperadas', 'select, insert, update, references')
     or has_any_column_privilege('service_role', 'crm.conversion_ventas_recuperadas', 'select, insert, update, references') then
    raise exception 'POSTFLIGHT recuperar_ventas: la tabla nueva tiene RLS, es de postgres, sin políticas y sin privilegios para la API';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in ('private.proteger_venta_recuperada()'::regprocedure, 'private.validar_venta_recuperada()'::regprocedure)
               and (p.proowner <> 'postgres'::regrole or p.prosecdef or p.proconfig is distinct from array['search_path=""']
                    or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                    or has_function_privilege('service_role', p.oid, 'execute'))) then
    raise exception 'POSTFLIGHT recuperar_ventas: las funciones de los triggers nuevos son de postgres, INVOKER y sin EXECUTE para la API';
  end if;
  if (select count(*) from crm.conversion_ventas_recuperadas) <> 5 then
    raise exception 'POSTFLIGHT recuperar_ventas: se esperaban 5 ventas recuperadas';
  end if;
  -- Cada uno de los cinco leads tiene EXACTAMENTE un cierre, sin anular, en el mes esperado y con aporte, salvo un
  -- referido: su aporte individual lo reparte el tope y puede ser 0 (lo que cuenta es la SUMA del analista, abajo).
  -- (fecha_numerador = la fecha comercial de la acreditación; mes_origen es el mes en que llegó el lead).
  if exists (select 1 from pg_temp.recuperar_casos c
             where (select count(*)
                    from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', (select fin from pg_temp.recuperar_corte), null, true, null, 1) x
                    where x.tipo = 'cierre' and x.lead_id = c.lead_id and not x.anulado and (x.aporte_numerador > 0 or x.fue_referido)
                      and x.fecha_numerador >= c.periodo::timestamp at time zone 'America/Lima'
                      and x.fecha_numerador < (c.periodo + interval '1 month')::timestamp at time zone 'America/Lima') <> 1) then
    raise exception 'POSTFLIGHT recuperar_ventas: una venta recuperada no cuenta exactamente una vez en la conversión';
  end if;
  -- Y NADA MÁS cambió en la conversión de septiembre y octubre: mismos episodios para todos los demás leads y operaciones.
  -- El aporte INDIVIDUAL de los referidos de los analistas y meses tocados se deja fuera (el tope lo reparte): se compara
  -- por su suma, abajo. Los candados SHARE sobre leads y asignaciones hacen comparables las dos fotos.
  with despues as (
    select x.tipo, x.analista_id, x.lead_id, x.operacion_id, x.fue_referido, x.anulado, x.categoria, x.mes_origen, x.aporte_divisor, x.aporte_numerador,
           pg_catalog.date_trunc('month', x.fecha_numerador at time zone 'America/Lima')::date as mes_cierre
    from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', (select fin from pg_temp.recuperar_corte), null, true, null, 1) x
  ), a as (
    select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.fue_referido, e.anulado, e.categoria, e.mes_origen, e.aporte_divisor,
           case when e.tipo = 'cierre' and e.fue_referido and not e.anulado
                     and exists (select 1 from pg_temp.recuperar_referidos r where r.analista_id = e.analista_id and r.mes_cierre = e.mes_cierre)
                then null else e.aporte_numerador end as aporte
    from pg_temp.recuperar_episodios_antes e where e.lead_id is null or e.lead_id not in (select lead_id from pg_temp.recuperar_casos)
  ), d as (
    select s.tipo, s.analista_id, s.lead_id, s.operacion_id, s.fue_referido, s.anulado, s.categoria, s.mes_origen, s.aporte_divisor,
           case when s.tipo = 'cierre' and s.fue_referido and not s.anulado
                     and exists (select 1 from pg_temp.recuperar_referidos r where r.analista_id = s.analista_id and r.mes_cierre = s.mes_cierre)
                then null else s.aporte_numerador end as aporte
    from despues s where s.lead_id is null or s.lead_id not in (select lead_id from pg_temp.recuperar_casos)
  )
  select count(*) into v_distintos from ((select * from a except all select * from d) union all (select * from d except all select * from a)) z;
  if v_distintos <> 0 then
    raise exception 'POSTFLIGHT recuperar_ventas: cambiaron % episodios de conversión que no son de las ventas recuperadas', v_distintos;
  end if;
  -- La SUMA de los referidos de cada analista y mes tocados sube EXACTAMENTE una cuota por referido recuperado.
  if exists (select 1 from pg_temp.recuperar_referidos r
             join pg_temp.recuperar_referidos_antes ra on ra.analista_id = r.analista_id and ra.mes_cierre = r.mes_cierre
             where (select coalesce(sum(x.aporte_numerador), 0)
                    from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', (select fin from pg_temp.recuperar_corte), null, true, null, 1) x
                    where x.tipo = 'cierre' and x.fue_referido and not x.anulado and x.analista_id = r.analista_id
                      and pg_catalog.date_trunc('month', x.fecha_numerador at time zone 'America/Lima')::date = r.mes_cierre)
                   <> ra.suma + r.recuperados * r.cuota) then
    raise exception 'POSTFLIGHT recuperar_ventas: la suma de referidos de un analista no subió exactamente una cuota por venta recuperada';
  end if;
  -- F7, vigencia del analista y censo analítico: las funciones cambiadas o nuevas no entran.
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and (p.oid in (select f.oid from pg_temp.recuperar_funciones f)
                    or p.oid in ('private.proteger_venta_recuperada()'::regprocedure, 'private.validar_venta_recuperada()'::regprocedure))
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada nombra una pieza cerrada de F7';
  end if;
  if exists (select 1 from private.puertas_analista_sin_vigencia() c
             where c.objeto in (select f.firma from pg_temp.recuperar_funciones f)
                or c.objeto in ('private.proteger_venta_recuperada()', 'private.validar_venta_recuperada()')) then
    raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada entró al censo de vigencia del analista';
  end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto in (select f.firma from pg_temp.recuperar_funciones f)
                or c.objeto in ('private.proteger_venta_recuperada()', 'private.validar_venta_recuperada()')) then
    raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada entró al censo analítico';
  end if;
end
$postflight$;

commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261018032400' and name = 'crm_recuperar_ventas_recargadas' and cardinality(statements) = 1
                   and md5(statements[1]) = '2293ae62ee624cfb41f31faea939ea43') then
    raise exception 'REGISTRO: la fila 20261018032400 / crm_recuperar_ventas_recargadas no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261018032400 / crm_recuperar_ventas_recargadas (1 sentencia: el archivo entero)';
end $post$;
commit;
