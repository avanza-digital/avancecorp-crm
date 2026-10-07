-- Solo lectura: debe dar true en todas las columnas antes de instalar.
begin read only;
select
  md5(pg_get_functiondef('private.repartir_lead_implementacion(uuid,uuid)'::regprocedure))='e549e5cf52d588c926a2eb3b466fc2cd' as escritor_compatible,
  md5(pg_get_functiondef('crm.agenda_reparto_diaria(date,integer)'::regprocedure))='164aed8ed9b1732624afa7e7dc87230c' as agenda_compatible,
  to_regclass('crm.configuracion_reparto') is null as tabla_nueva,
  to_regprocedure('crm.configuracion_reparto_fn()') is null as lectura_nueva,
  to_regprocedure('crm.guardar_configuracion_reparto_fn(boolean,integer)') is null as escritura_nueva;
rollback;
