begin;
create temporary table prueba_reversion(lead uuid default gen_random_uuid());
insert into prueba_reversion default values;
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
 select lead,'BANCO REVERSION HOSTED','987654001','oficina',1000,'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002' from prueba_reversion;
do $$ declare v_c crm.recorrido_control%rowtype;v_original timestamptz;v_modo text;v_lead uuid;v_r jsonb;v_rechazo boolean:=false;
begin
 select cohorte_desde into v_original from crm.recorrido_control where id;
 select lead into v_lead from prueba_reversion;
 perform set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
 foreach v_modo in array array['observacion','apagado','exigir'] loop
  select * into strict v_c from crm.recorrido_control where id;
  perform crm.recorrido_configurar_fn(v_modo,'Reversion y reactivacion sinteticas del ensayo hosted',v_c.revision);
  if (select cohorte_desde is distinct from v_original from crm.recorrido_control where id) then raise exception 'Cambio la fecha inicial';end if;
  if v_modo='exigir' then
   begin perform private.recorrido_exigir(v_lead,'reversion_hosted');
   exception when sqlstate 'P0409' then v_rechazo:=true;end;
   if not v_rechazo then raise exception 'Exigir no volvio a bloquear sin hechos';end if;
  else
   v_r:=private.recorrido_exigir(v_lead,'reversion_hosted');
   if (v_r->>'exigible')::boolean is distinct from false then raise exception 'La reversion no quito la exigencia';end if;
  end if;
  raise notice 'PASS hosted: modo %, fecha inmutable y comportamiento del servidor coherente',v_modo;
 end loop;
end $$;
rollback;