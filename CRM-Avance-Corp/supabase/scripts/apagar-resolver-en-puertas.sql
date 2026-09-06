-- APAGADO de la identidad unificada (F2.b): UN solo UPDATE, en su propia transacción corta, con timeout explícito.
--
-- POR QUÉ ASÍ. El cambio de bandera toma el candado EXCLUSIVO `crm_flag_resolver_en_puertas` (trigger de D-5) y por
-- tanto ESPERA a las puertas en vuelo que lo leyeron bajo el compartido (D-5, D-15, D-17). Pero NO todas las funciones
-- que leen la bandera lo toman: el censo del 06/09/2026 encontró 14 más que la leen y escriben (la conversión Avance,
-- la reserva por persona, el alta de contrato, la fusión, la corrección de documento, el enlace, la reasignación, el
-- alta y la eliminación de cliente, el reingreso, el puente…). Para ésas, la garantía no es un candado sino el DRENAJE:
-- este script se niega a cambiar la bandera si hay alguna transacción de la aplicación viva contra la base. Por eso el
-- encendido va en VENTANA MUERTA (22:00–07:00 Lima o domingo) y sin nadie operando: si algo está en vuelo, aborta y se
-- repite. Nunca cambiar la bandera dentro de una transacción larga que toque filas de negocio (interbloqueo), ni desde
-- una reversa que la apaga junto a otras cosas.
--
-- APAGAR es la dirección segura (las puertas vuelven al comportamiento de siempre), pero se aplica el mismo rigor.
-- Si el UPDATE espera más de 30 s, aborta solo (lock_timeout): revisar qué puerta sigue en vuelo y repetir.
-- Bitácora: `trg_audit_multiempresa_flags` registra el cambio en `public.audit_log` (el `actualizado_por` queda vacío
-- al ejecutarlo desde `db query`: anotar en el ledger quién y cuándo). Se niega si D-5 no está aplicada.
begin;
set local lock_timeout = '30s';
do $$
declare v_vivas integer;
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'crm.multiempresa_flags'::regclass
                   and tgname = 'trg_multiempresa_flags_00_serializa_puertas' and tgenabled = 'O') then
    raise exception 'F2.b: falta el trigger que serializa el cambio de bandera (D-5, 20260906140000): aplica D-5 antes de apagar';
  end if;
  -- DRENAJE: ninguna transacción de la aplicación puede estar a medias (las que no toman el candado compartido
  -- terminarían con una bandera distinta de la que leyeron). `authenticator` es el rol de PostgREST; `service_role`
  -- y `authenticated` son los roles con los que corren las llamadas del CRM, del Portal y de las edges.
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
    raise exception 'F2.b: hay % transaccion(es) de la aplicacion en vuelo: espera a la ventana muerta y vuelve a intentarlo', v_vivas
      using hint = 'Con nadie operando, este contador queda en cero. Mira pg_stat_activity si se repite.';
  end if;
end $$;
update crm.multiempresa_flags set activo = false, actualizado_en = now() where nombre = 'resolver_en_puertas';
select nombre, activo, actualizado_en from crm.multiempresa_flags where nombre = 'resolver_en_puertas';
commit;
