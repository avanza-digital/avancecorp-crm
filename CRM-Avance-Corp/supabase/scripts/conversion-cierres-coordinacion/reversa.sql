-- Retirar primero el frontend que consume esta puerta. Sin cambios en datos.
begin;
drop function crm.conversion_cierres_coordinacion_fn(uuid,date,date,date,integer);
drop function private.conversion_cierres_coordinacion(uuid,date,date,integer);
commit;
