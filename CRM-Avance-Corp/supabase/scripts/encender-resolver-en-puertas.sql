-- ENCENDIDO de la identidad unificada (F2.b): UN solo UPDATE, en su propia transacción corta, con timeout explícito.
-- Regla (RETOMAR-60 / bloque 4, auditor y Codex): el cambio de bandera toma el candado EXCLUSIVO crm_flag_resolver_en_puertas
-- (trigger de D-5) y espera a las puertas en vuelo que la leyeron bajo el compartido; NUNCA cambiar la bandera dentro de una
-- transacción larga que toque filas de negocio (interbloqueo), ni desde una reversa que la apaga junto a otras cosas.
-- Ventana muerta (22:00–07:00 Lima o domingo), sin analistas operando; comprobar pg_stat_activity antes. Si el UPDATE espera
-- más de 30 s, aborta solo (lock_timeout): revisar qué puerta sigue en vuelo y repetir.
begin;
set local lock_timeout = '30s';
update crm.multiempresa_flags set activo = true, actualizado_en = now() where nombre = 'resolver_en_puertas';
select nombre, activo, actualizado_en from crm.multiempresa_flags where nombre = 'resolver_en_puertas';
commit;
