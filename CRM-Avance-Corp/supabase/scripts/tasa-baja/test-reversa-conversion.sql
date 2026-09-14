-- Fixture comprometido sin contrato: solo en la copia local que elimina el runner.
begin;
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
values('d7140000-0000-4000-8000-000000000040','QA REVERSA TASA','+51999014040','71409040','otro',20000,
 'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001');
do $$
declare v_saga jsonb;
begin
 assert not exists(select 1 from crm.ledger_rentabilidad where detalle->>'tasa_inferior_sin_excepcion'='true'),
   'El ensayo de reversa por conversión requiere ausencia de contratos a tasa inferior';
 v_saga:=crm.reservar_conversion_lead('d7140000-0000-4000-8000-000000000040','DNI','71409040',
   jsonb_build_object('correo','qa-reversa@example.invalid','nombre_completo','QA REVERSA TASA','domicilio','Calle QA 123',
    'condiciones_tasa',jsonb_build_object('categoria','nuevo','capital',20000,'moneda','PEN','modalidad','mensual',
      'tipo_interes','simple','fecha_inicio','2026-09-15','fecha_vencimiento','2027-09-15','tasa_anual',12.5)));
 perform crm.marcar_efectos_conversion('d7140000-0000-4000-8000-000000000040',(v_saga->>'claim_id')::uuid,v_saga->>'token');
 assert exists(select 1 from crm.conversion_reservas where lead_id='d7140000-0000-4000-8000-000000000040'
   and efectos_iniciados_en is not null and (condiciones_tasa->>'tasa_anual')::numeric=12.5),'Falta reserva sellada';
 assert not exists(select 1 from crm.ledger_rentabilidad where detalle->>'tasa_inferior_sin_excepcion'='true'),'No debe haber contrato';
end $$;
commit;
