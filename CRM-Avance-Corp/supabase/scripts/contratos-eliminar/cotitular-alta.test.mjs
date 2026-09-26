// Banco Docker sintético exclusivo. Ninguna URL ni proyecto remoto; ROLLBACK por caso.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

function sql(consulta) {
  const r=spawnSync('docker',['exec','-i','supabase_db_crm-avance-corp-local','psql','-XqAt',
    '-U','postgres','-d','contratos_cotitular_v3_20260925','-v','ON_ERROR_STOP=1','-f','-'],
  {input:`begin; ${consulta} rollback;`,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr || r.error?.message);
  return r.stdout.trim();
}

// Réplica del caso 001471, con datos exclusivamente sintéticos. Se invoca el
// escritor real de vínculos del alta; ninguna guarda se desactiva al eliminar.
const fixture=`
  select id into strict a from public.perfiles where rol='admin' and activo limit 1;
  perform set_config('request.jwt.claim.sub',a::text,true);
  c:=gen_random_uuid(); i:=gen_random_uuid(); s:=gen_random_uuid();
  set local session_replication_role=replica;
  insert into public.contratos select (jsonb_populate_record(null::public.contratos,to_jsonb(x)||
    jsonb_build_object('id',c,'numero_contrato','COTITULAR-'||c,'renovado_a_id',null,'cerrado_en',null,'estado','activo'))).*
    from public.contratos x where numero_contrato='BANCO-A2';
  if not found then raise exception 'Falta contrato base sintético'; end if;
  insert into crm.inversiones select (jsonb_populate_record(null::crm.inversiones,to_jsonb(x)||
    jsonb_build_object('id',i,'contrato_id',c))).*
    from crm.inversiones x join public.contratos k on k.id=x.contrato_id where k.numero_contrato='BANCO-A2';
  insert into crm.inversion_solicitudes select (jsonb_populate_record(null::crm.inversion_solicitudes,to_jsonb(x)||
    jsonb_build_object('id',s,'inversion_id',i,'inversionista_id',v.inversionista_id,'empresa_id',v.empresa_id,
      'estado','confirmada','resultado',jsonb_build_object('fuente',jsonb_build_object('id',c))))).*
    from crm.inversion_solicitudes x cross join crm.inversiones v where v.id=i limit 1;
  insert into public.contrato_titulares(contrato_id,orden,tipo_documento,documento,nombre_completo,creado_por)
    select c,1,d.tipo_documento,d.documento_original,'COTITULAR SINTETICO',a
    from crm.inversionista_identificadores d where d.estado='vigente' and d.verificado
      and d.inversionista_id<>(select inversionista_id from crm.inversiones where id=i) limit 1;
  insert into public.cronograma_pagos(contrato_id,numero_cuota,fecha_programada,monto_programado,estado)
    select c,n,current_date+n,125,'pendiente' from generate_series(1,7) n;
  insert into private.contrato_pdf_jobs(id,contrato_id,storage_path,nombre_archivo,snapshot,solicitado_por)
    select j,c,c::text||'/v2/'||j::text||'/contrato.pdf','PRUEBA.pdf','{}',a from (select gen_random_uuid() j) x;
  set local session_replication_role=origin;
  perform private.inversion_cotitulares_vincular(i,'alta');
  if (select count(*) from crm.inversion_cotitular_origenes where inversion_id=i)<>1 then
    raise exception 'Falta vínculo de alta'; end if;
  insert into crm.inversion_eventos(inversion_id,tipo,motivo,creado_por) values(i,'registro','Alta sintética',a);
`;
const declara='a uuid; c uuid; i uuid; s uuid;';

for (const rol of ['admin','superadmin']) {
  test(`${rol}: siete cuotas, pago, alta y cotitular archivados exactamente; replay estable`,()=>{
    sql(`do $t$ declare ${declara} copia jsonb; origen jsonb; titulares jsonb; pagos jsonb; eventos jsonb; solicitud jsonb; r jsonb;
    begin ${fixture}
      select id into strict a from public.perfiles where rol='${rol}' and activo limit 1;
      update public.cronograma_pagos set estado='pagado',monto_pagado=125,fecha_pago_real=current_date,registrado_por=a
        where contrato_id=c and numero_cuota=1;
      select jsonb_agg(to_jsonb(x) order by id) into origen from crm.inversion_cotitular_origenes x where inversion_id=i;
      select jsonb_agg(to_jsonb(x) order by id) into titulares from public.contrato_titulares x where contrato_id=c;
      select jsonb_agg(to_jsonb(x) order by id) into pagos from public.cronograma_pagos x where contrato_id=c;
      select jsonb_agg(to_jsonb(x) order by id) into eventos from crm.inversion_eventos x where inversion_id=i;
      select jsonb_agg(to_jsonb(x) order by id) into solicitud from crm.inversion_solicitudes x where inversion_id=i;
      r:=crm.contrato_eliminar_auditado(c,a);
      select snapshot into strict copia from crm.contratos_eliminados_auditoria where contrato_id=c and eliminado_por=a;
      if copia->>'version'<>'4' or copia->'inversion_cotitular_origenes' is distinct from origen
        or copia->'titulares' is distinct from titulares or copia->'cronograma' is distinct from pagos
        or copia->'inversion_eventos' is distinct from eventos or copia->'inversion_solicitudes' is distinct from solicitud
        then raise exception 'Copia incompleta'; end if;
      if exists(select 1 from public.contratos where id=c) or exists(select 1 from crm.inversiones where id=i)
        or exists(select 1 from crm.inversion_cotitular_origenes where inversion_id=i)
        or not exists(select 1 from crm.inversion_solicitudes where id=s and estado='cancelada' and inversion_id is null)
        then raise exception 'Eliminación incompleta'; end if;
      if not exists(select 1 from crm.inversionistas where id=(origen->0->>'persona_origen_id')::uuid)
        or not exists(select 1 from crm.inversionista_identificadores where id=(origen->0->>'identificador_origen_id')::uuid)
        then raise exception 'Se perdió identidad compartida'; end if;
      if crm.contrato_eliminar_auditado(c,a) is distinct from r then raise exception 'Replay divergente'; end if;
    end $t$;`);
  });
}

for (const [nombre,cambio,codigo] of [
  ['analista',"select id into strict a from public.perfiles where rol='analista' limit 1;",'42501'],
  ['cliente',"select id into strict a from public.perfiles where rol='cliente' limit 1;",'42501'],
  ['admin inactivo',"update public.perfiles set activo=false where id=a;",'42501'],
  ['historial posterior',"insert into crm.inversion_eventos(inversion_id,tipo,motivo,creado_por) values(i,'correccion','Posterior',a);",'55000'],
  ['origen conciliado',"alter table crm.inversion_cotitular_origenes disable trigger trg_cotitular_origen_inmutable; update crm.inversion_cotitular_origenes set origen_registro='conciliacion' where inversion_id=i; alter table crm.inversion_cotitular_origenes enable trigger trg_cotitular_origen_inmutable;",'55000'],
  ['hash incoherente',"alter table crm.inversion_cotitular_origenes disable trigger trg_cotitular_origen_inmutable; update crm.inversion_cotitular_origenes set hash_fuente='incorrecto' where inversion_id=i; alter table crm.inversion_cotitular_origenes enable trigger trg_cotitular_origen_inmutable;",'55000'],
  ['fuente de otro contrato',"alter table crm.inversion_cotitular_origenes disable trigger trg_cotitular_origen_inmutable; update crm.inversion_cotitular_origenes set fuente_snapshot=jsonb_set(fuente_snapshot,'{contrato_id}',to_jsonb(gen_random_uuid()::text)) where inversion_id=i; alter table crm.inversion_cotitular_origenes enable trigger trg_cotitular_origen_inmutable;",'55000'],
]) {
  test(`${nombre}: rechaza sin efectos parciales`,()=>{
    sql(`do $t$ declare ${declara} begin ${fixture} ${cambio}
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'Permitió una eliminación indebida';
      exception when sqlstate '${codigo}' then null; end;
      if not exists(select 1 from public.contratos where id=c)
        or not exists(select 1 from crm.inversion_cotitular_origenes where inversion_id=i)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
        or exists(select 1 from private.contrato_eliminaciones where contrato_id=c)
        then raise exception 'Rechazo con efectos parciales'; end if;
    end $t$;`);
  });
}

test('Un fallo final restaura contrato, cotitular, registro y solicitud',()=>{
  sql(`create function pg_temp.fallar() returns trigger language plpgsql as $f$
    begin raise exception 'Fallo final sintético' using errcode='23503'; end $f$;
    create trigger prueba_fallo before delete on public.contratos for each row execute function pg_temp.fallar();
    do $t$ declare ${declara} origen jsonb; solicitud jsonb; begin ${fixture}
      select to_jsonb(x) into origen from crm.inversion_cotitular_origenes x where inversion_id=i;
      select to_jsonb(x) into solicitud from crm.inversion_solicitudes x where id=s;
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'No ocurrió fallo final';
      exception when foreign_key_violation then null; end;
      if origen is distinct from (select to_jsonb(x) from crm.inversion_cotitular_origenes x where inversion_id=i)
        or solicitud is distinct from (select to_jsonb(x) from crm.inversion_solicitudes x where id=s)
        or not exists(select 1 from crm.inversion_eventos where inversion_id=i)
        or not exists(select 1 from public.contratos where id=c)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
        then raise exception 'Rollback incompleto'; end if;
    end $t$;`);
});

test('Una variable falsificada no permite borrar el origen ni editarlo',()=>{
  sql(`do $t$ declare ${declara} begin ${fixture}
    perform set_config('crm.contrato_registro_eliminacion',gen_random_uuid()::text,true);
    begin delete from crm.inversion_cotitular_origenes where inversion_id=i; raise exception 'Borró sin reserva';
    exception when sqlstate 'P0409' then null; end;
    begin update crm.inversion_cotitular_origenes set origen_registro='administracion' where inversion_id=i;
      raise exception 'Editó historial'; exception when sqlstate 'P0409' then null; end;
    begin delete from public.contrato_titulares where contrato_id=c; raise exception 'Borró titular protegido';
    exception when sqlstate '55000' then null; end;
  end $t$;`);
});

test('Una dependencia futura del origen detiene la eliminación antes de archivar',()=>{
  sql(`create table crm.prueba_hija_origen(id uuid primary key,origen_id uuid references crm.inversion_cotitular_origenes(id) on delete cascade);
    do $t$ declare ${declara} begin ${fixture}
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'Ignoró dependencia futura';
      exception when sqlstate '55000' then if sqlerrm not like '%dependencias nuevas%' then raise; end if; end;
      if exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c) then raise exception 'Archivó tras rechazar'; end if;
    end $t$;`);
});

test('Sólo service_role ejecuta la RPC; nadie de API ejecuta los triggers privados',()=>{
  assert.equal(sql(`select has_function_privilege('service_role','crm.contrato_eliminar_auditado(uuid,uuid)','execute')
    and not has_function_privilege('authenticated','crm.contrato_eliminar_auditado(uuid,uuid)','execute')
    and not has_function_privilege('anon','crm.contrato_eliminar_auditado(uuid,uuid)','execute')
    and not has_function_privilege('service_role','private.f4_proteger_origen_cotitular()','execute')
    and not has_function_privilege('authenticated','private.f4_proteger_origen_cotitular()','execute')
    and not has_function_privilege('anon','private.f4_proteger_origen_cotitular()','execute');`),'t');
});

test('Reserva real no permite otro contrato ni otro actor; restaura el token al salir',()=>{
  sql(`create function pg_temp.comprobar_reserva() returns trigger language plpgsql as $f$
    declare actor text; otro uuid;
    begin
      if pg_trigger_depth()>1 then return old; end if;
      actor:=current_setting('request.jwt.claim.sub');
      select inversion_id into otro from crm.inversion_cotitular_origenes where inversion_id<>old.inversion_id limit 1;
      if otro is null then raise exception 'Falta segundo origen'; end if;
      begin delete from crm.inversion_cotitular_origenes where inversion_id=otro; raise sqlstate 'ZX001';
      exception when sqlstate 'P0409' then null; end;
      perform set_config('request.jwt.claim.sub',(select id::text from public.perfiles where rol='superadmin' limit 1),true);
      begin delete from crm.inversion_cotitular_origenes where id=old.id; raise sqlstate 'ZX001';
      exception when sqlstate 'P0409' then null; end;
      perform set_config('request.jwt.claim.sub',actor,true);
      return old;
    end $f$;
    do $t$ declare ${declara} c2 uuid; i2 uuid; begin ${fixture} c2:=c; i2:=i; ${fixture}
      create trigger aaa_comprobar_reserva before delete on crm.inversion_cotitular_origenes
        for each row execute function pg_temp.comprobar_reserva();
      perform crm.contrato_eliminar_auditado(c,a);
      drop trigger aaa_comprobar_reserva on crm.inversion_cotitular_origenes;
      if coalesce(current_setting('crm.contrato_registro_eliminacion',true),'')<>'' then raise exception 'Token residual'; end if;
      begin delete from crm.inversion_cotitular_origenes where inversion_id=i2; raise sqlstate 'ZX001';
      exception when sqlstate 'P0409' then null; end;
    end $t$;`);
});

for (const mezcla of [false,true]) test(`Dos cotitulares; mezcla histórica=${mezcla}`,()=>{
  sql(`do $t$ declare ${declara} titular uuid; begin ${fixture}
    set local session_replication_role=replica;
    insert into public.contrato_titulares(contrato_id,orden,tipo_documento,documento,nombre_completo,creado_por)
      select contrato_id,2,tipo_documento,documento,nombre_completo,creado_por from public.contrato_titulares where contrato_id=c returning id into titular;
    insert into crm.inversion_cotitular_origenes select (jsonb_populate_record(null::crm.inversion_cotitular_origenes,
      to_jsonb(o)||jsonb_build_object('id',gen_random_uuid(),'contrato_titular_id',titular,
        'fuente_snapshot',to_jsonb(t),'hash_fuente',private.idem_hash(to_jsonb(t)),
        'origen_registro','${mezcla ? 'conciliacion' : 'alta'}'))).*
      from crm.inversion_cotitular_origenes o cross join public.contrato_titulares t where o.inversion_id=i and t.id=titular;
    set local session_replication_role=origin;
    ${mezcla ? `begin perform crm.contrato_eliminar_auditado(c,a); raise sqlstate 'ZX001'; exception when sqlstate '55000' then null; end;
      if (select count(*) from crm.inversion_cotitular_origenes where inversion_id=i)<>2
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c) then raise exception 'Rollback parcial'; end if;`
      : `perform crm.contrato_eliminar_auditado(c,a);
      if (select jsonb_array_length(snapshot->'inversion_cotitular_origenes') from crm.contratos_eliminados_auditoria where contrato_id=c)<>2
        then raise exception 'Copia incompleta'; end if;`}
  end $t$;`);
});
