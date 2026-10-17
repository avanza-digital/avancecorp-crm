-- Reversa de nuevas altas. Coordinar con la pantalla de meses calendario.
-- Conserva todos los contratos ya pactados a 360 días y sus correcciones.
begin;
set local lock_timeout='5s';
alter table crm.cierres_externos alter column base_plazo set default 'calendario';
create or replace function private.coopac_validar_condiciones(p_inicio date,p_plazo_meses integer,p_tasa_anual numeric)
returns date language plpgsql immutable set search_path='' as $function$
begin
  return private.coopac_validar_condiciones_base(p_inicio,p_plazo_meses,p_tasa_anual,'calendario');
end;
$function$;
comment on function private.coopac_validar_condiciones(date,integer,numeric) is
  'Reversa COOPAC: altas nuevas por meses calendario; contratos ya pactados conservan su base.';
commit;
