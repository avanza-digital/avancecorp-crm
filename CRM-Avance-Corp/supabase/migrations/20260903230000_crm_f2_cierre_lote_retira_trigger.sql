-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — Cierre del lote: retirar el trigger 200000
-- ============================================================================
--
-- QUE: cierra el lote Contrato-F2. Las dos puertas (convertir_lead 210000 y
-- convertir_lead_externo 220000) YA reconocen la identidad ADENTRO, así que el
-- trigger-only trg_leads_reconocer_identidad (200000) sobra y se RETIRA (el
-- diseño lo ordena; el auditor lo marcó como bloqueante de lote).
--
-- BANDERA EN ESTADO EXPLÍCITO = APAGADA. F2 aterriza ADITIVA (sin cambio visible),
-- igual que F1 y el backfill: el reconocimiento en las puertas queda DORMIDO hasta
-- una ACTIVACIÓN deliberada —migración aparte— tras el ensayo en banco, el visto
-- de Miguel y (para «N inversiones por persona») la fase F5. Por eso aquí la
-- bandera se fuerza a false, neutralizando el encendido que hacía 200000, se
-- aplique o no ese archivo (los DROP y el UPDATE son idempotentes).
--
-- Requiere que las dos puertas F2 estén reescritas (210000, 220000). Reversa:
-- rollback-f2-puertas.sql (no recrea el trigger; las puertas ya lo sustituyen).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_cierre_lote'));

do $guard$
begin
  if to_regprocedure('crm.convertir_lead(uuid,uuid)') is null
     or to_regprocedure('crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)') is null then
    raise exception 'F2 cierre: faltan las puertas reescritas (210000/220000)';
  end if;
  if not exists (select 1 from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'F2 cierre: falta la bandera resolver_en_puertas (F1)';
  end if;
end
$guard$;

-- Retirar el trigger-only 200000 y su función (reemplazados por las puertas).
drop trigger if exists trg_leads_reconocer_identidad on crm.leads;
drop function if exists private.leads_reconocer_identidad_al_convertir();

-- Bandera APAGADA (aterrizaje aditivo). La activación es un paso deliberado aparte.
update crm.multiempresa_flags
   set activo = false, actualizado_en = now()
 where nombre = 'resolver_en_puertas' and activo = true;

do $post$
begin
  if exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    where t.tgname = 'trg_leads_reconocer_identidad'
      and c.relname = 'leads' and c.relnamespace = 'crm'::regnamespace
      and not t.tgisinternal
  ) then
    raise exception 'POSTFLIGHT F2 cierre: el trigger trg_leads_reconocer_identidad no se retiró';
  end if;
  if to_regprocedure('private.leads_reconocer_identidad_al_convertir()') is not null then
    raise exception 'POSTFLIGHT F2 cierre: la función del trigger sigue viva';
  end if;
  if (select activo from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'POSTFLIGHT F2 cierre: la bandera quedó ENCENDIDA (F2 debe aterrizar apagada)';
  end if;
  raise notice 'F2 cierre OK: trigger retirado, puertas vigentes, bandera APAGADA (aditiva).';
end
$post$;

commit;
