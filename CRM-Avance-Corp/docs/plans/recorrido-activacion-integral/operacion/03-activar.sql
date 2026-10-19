-- NO EJECUTAR sin la autorización del paquete y de esta activación.
-- Actuación técnica con ADMINISTRADOR AVANCE CORP; no simula un login humano.
-- Ejecutar solo después del postflight de instalación y capacitación.
begin;
set local statement_timeout='30s';
set local lock_timeout='3s';
do $$
declare c crm.recorrido_control%rowtype;
begin
  select * into strict c from crm.recorrido_control where id for update;
  if c.modo<>'observacion' or c.revision<>1 or c.cohorte_desde is not null then
    raise exception 'El control cambio desde la propuesta; revisar antes de activar' using errcode='55000';
  end if;
end $$;
select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
set local role authenticated;
select crm.recorrido_configurar_fn('exigir',
  'Activacion tecnica autorizada por Miguel: toda primera conversion pendiente requiere asistencia y entrevista de la misma cita y ciclo.',1);
reset role;
do $$begin
  if not exists(select 1 from crm.recorrido_control where id and modo='exigir' and revision=2
    and cohorte_desde between transaction_timestamp() and clock_timestamp()) then
    raise exception 'La activacion no cumple el resultado aprobado';
  end if;
end $$;
commit;
