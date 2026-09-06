-- ENCENDIDO de la identidad unificada (F2.b): UN solo UPDATE, en su propia transacción corta, con timeout explícito.
-- Regla (RETOMAR-60 / bloque 4, auditor y Codex): el cambio de bandera toma el candado EXCLUSIVO crm_flag_resolver_en_puertas
-- (trigger de D-5) y espera a las puertas en vuelo que la leyeron bajo el compartido; NUNCA cambiar la bandera dentro de una
-- transacción larga que toque filas de negocio (interbloqueo), ni desde una reversa que la apaga junto a otras cosas.
-- Ventana muerta (22:00–07:00 Lima o domingo), sin analistas operando; comprobar pg_stat_activity antes. Si el UPDATE espera
-- más de 30 s, aborta solo (lock_timeout): revisar qué puerta sigue en vuelo y repetir. Mientras espera, las llamadas nuevas a
-- las puertas se encolan detrás y las que llevan lock_timeout 5 s mueren con 55P03 (aceptable en ventana muerta).
-- Bitácora: trg_audit_multiempresa_flags registra el cambio en public.audit_log (actualizado_por queda null desde db query;
-- anotar en el ledger quién y cuándo). Se niega si D-5 (el trigger que serializa) no está aplicada: sin él no serializa nada.
begin;
set local lock_timeout = '30s';
do $$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'crm.multiempresa_flags'::regclass and tgname = 'trg_multiempresa_flags_00_serializa_puertas' and tgenabled = 'O') then
    raise exception 'F2.b: falta el trigger que serializa el cambio de bandera (D-5, 20260906140000): aplica D-5 antes de encender';
  end if;
end $$;
update crm.multiempresa_flags set activo = true, actualizado_en = now() where nombre = 'resolver_en_puertas';
select nombre, activo, actualizado_en from crm.multiempresa_flags where nombre = 'resolver_en_puertas';
commit;
