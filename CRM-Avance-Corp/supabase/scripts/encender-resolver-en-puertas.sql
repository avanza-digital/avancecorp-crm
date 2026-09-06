-- ENCENDIDO de la identidad unificada (F2.b): UN solo UPDATE, en su propia transacción corta, con timeout explícito.
--
-- POR QUÉ ASÍ. El cambio de bandera toma el candado EXCLUSIVO `crm_flag_resolver_en_puertas` (trigger de D-5) y por
-- tanto ESPERA a toda llamada en vuelo que la haya leído bajo el compartido. Desde **D-19 (20260906200000) eso son
-- TODAS**: las 34 funciones que leen `resolver_en_puertas` pasan por `private.resolver_en_puertas_bajo_candado()`, que
-- exige READ COMMITTED, toma el compartido y solo entonces lee. Antes de D-19 quedaban fuera 18 —incluidos los
-- validadores BEFORE de `crm.leads`, que son el camino directo del front— y la única garantía era el DRENAJE de este
-- script. **Codex demostró que el drenaje NO cierra la admisión**: una llamada puede empezar justo después del recuento
-- y justo antes del UPDATE, y el recuento tampoco ve una edge que va por dos operaciones SQL separadas. Por eso el
-- recuento se conserva como AVISO informativo, no como compuerta: con D-19 lo correcto es **esperar**, no rehusar.
--
-- Sigue siendo buena práctica hacerlo en VENTANA MUERTA (22:00–07:00 Lima o domingo). Nunca cambiar la bandera dentro
-- de una transacción larga que toque filas de negocio (interbloqueo), ni desde una reversa que la apaga junto a otras cosas.
--
-- Si el UPDATE espera más de 30 s, aborta solo (lock_timeout): mira qué sigue en vuelo y repite.
-- Bitácora: `trg_audit_multiempresa_flags` registra el cambio en `public.audit_log` (el actor queda vacío al ejecutarlo
-- desde `db query`: anotar en el ledger quién y cuándo). Se niega si D-5 no está aplicada.
begin;
set local lock_timeout = '30s';
do $$
declare v_vivas integer;
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'crm.multiempresa_flags'::regclass
                   and tgname = 'trg_multiempresa_flags_00_serializa_puertas' and tgenabled = 'O') then
    raise exception 'F2.b: falta el trigger que serializa el cambio de bandera (D-5, 20260906140000): aplica D-5 antes de encender';
  end if;
  -- AVISO (ya no compuerta): cuántas transacciones de la aplicación hay a medias. Con D-19 todas toman el candado
  -- compartido, así que este UPDATE las ESPERA en vez de tener que rehusar. Se informa por si el número sorprende.
  select count(*) into v_vivas
  from pg_stat_activity
  where datname = current_database()
    and pid <> pg_backend_pid()
    and (usename in ('authenticator', 'authenticated', 'service_role')
         or application_name ilike '%postgrest%' or application_name ilike '%supabase%')
    -- «active» = ejecutando algo ahora. «idle in transaction» solo cuenta si YA hizo trabajo: una conexión recién
    -- tomada del pool se queda con el BEGIN a secas y no tiene nada en vuelo (falso positivo si se contara).
    and (state = 'active'
         or (state like 'idle in transaction%' and coalesce(query, '') !~* '^\s*begin'));
  if v_vivas > 0 then
    raise notice 'F2.b: hay % transaccion(es) de la aplicacion en vuelo; el cambio de bandera las ESPERA (D-19). Si el UPDATE aborta por lock_timeout, repite.', v_vivas;
  end if;
  -- Sí es compuerta: sin D-19 el drenaje volvería a ser la única (falsa) garantía.
  if to_regprocedure('private.resolver_en_puertas_bajo_candado()') is null then
    raise exception 'F2.b: falta D-19 (20260906200000): sin ella hay funciones que leen la bandera sin candado y este cambio puede pillarlas a medias';
  end if;
end $$;
update crm.multiempresa_flags set activo = true, actualizado_en = now() where nombre = 'resolver_en_puertas';
select nombre, activo, actualizado_en from crm.multiempresa_flags where nombre = 'resolver_en_puertas';
commit;
