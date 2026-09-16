import assert from 'node:assert/strict';
import test from 'node:test';

export function probarAuditoria(sql) {
const transaccion=c=>sql(`begin; ${c} rollback;`);

test('Admin elimina un contrato con pagos; copia exacta, archivos referenciados y replay estable',()=>{
  transaccion(`do $t$
  declare a uuid; c uuid; r jsonb; r2 jsonb; antes jsonb; copia jsonb; n integer;
  begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    select k.id into strict c from public.contratos k
    where k.numero_contrato='F4-BASE-INICIAL';
    insert into public.documentos(contrato_id,nombre,tipo,storage_path,subido_por)
      values(c,'EVIDENCIA SINTÉTICA.pdf','otro',c::text||'/evidencia-sintetica.pdf',a);
    update public.cronograma_pagos set estado='pagado',monto_pagado=monto_programado,
      fecha_pago_real=current_date,registrado_por=a
      where id=(select id from public.cronograma_pagos where contrato_id=c order by numero_cuota limit 1);
    select jsonb_agg(to_jsonb(p) order by p.id),count(*) into antes,n
      from public.cronograma_pagos p where contrato_id=c;
    if n=0 or not exists(select 1 from public.cronograma_pagos where contrato_id=c and estado='pagado') then
      raise exception 'Fixture sin pago'; end if;
    r:=crm.contrato_eliminar_auditado(c,a);
    if exists(select 1 from public.contratos where id=c) or exists(select 1 from public.cronograma_pagos where contrato_id=c) then
      raise exception 'No eliminó la operación'; end if;
    select snapshot into strict copia from crm.contratos_eliminados_auditoria
      where contrato_id=c and eliminado_por=a and id=(r->>'auditoria_id')::uuid;
    if copia->'cronograma' is distinct from antes or copia->'contrato'->>'id'<>c::text then
      raise exception 'La auditoría no coincide con los datos previos'; end if;
    if not exists(select 1 from crm.contratos_eliminados_auditoria x,
      jsonb_array_elements(x.archivos) o where x.contrato_id=c
      and o->>'bucket'='documentos' and o->>'path'=c::text||'/evidencia-sintetica.pdf')
      or not exists(select 1 from jsonb_array_elements(copia->'documentos') d where d->>'nombre'='EVIDENCIA SINTÉTICA.pdf') then
      raise exception 'No conservó las referencias documentales'; end if;
    if not exists(select 1 from public.audit_log where tabla='contratos' and fila_id=c::text and operacion='DELETE' and usuario_id=a) then
      raise exception 'DELETE sin actor'; end if;
    r2:=crm.contrato_eliminar_auditado(c,a);
    if r2 is distinct from r then raise exception 'Replay duplicó o cambió auditoría'; end if;
    begin
      update crm.contratos_eliminados_auditoria set snapshot='{}' where contrato_id=c;
      raise exception 'Permitió adulterar auditoría';
    exception when insufficient_privilege then null; end;
    begin
      delete from crm.contratos_eliminados_auditoria where contrato_id=c;
      raise exception 'Permitió borrar auditoría';
    exception when insufficient_privilege then null; end;
    begin
      truncate crm.contratos_eliminados_auditoria;
      raise exception 'Permitió vaciar auditoría';
    exception when insufficient_privilege then null; end;
  end $t$;`);
});

test('Deniega roles ajenos; una inversión con historial propio revierte sin auditoría ni borrados',()=>{
  transaccion(`do $t$
  declare a uuid; c uuid; p record; n integer;
  begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    select i.contrato_id into strict c from crm.inversiones i where i.contrato_id is not null
      and exists(select 1 from crm.inversion_eventos e where e.inversion_id=i.id) limit 1;
    for p in select id from public.perfiles where rol in ('analista','directorio','cliente') loop
      begin
        perform crm.contrato_eliminar_auditado(c,p.id);
        raise exception 'Rol no autorizado pudo eliminar';
      exception when insufficient_privilege then null; end;
    end loop;
    begin
      perform crm.contrato_eliminar_auditado(c,null);
      raise exception 'Aceptó actor nulo';
    exception when insufficient_privilege then null; end;
    begin
      perform crm.contrato_eliminar_auditado(c,a);
      raise exception 'Permitió destruir historial';
    exception when sqlstate '55000' then
      if sqlerrm not like '%historial propio%' then raise; end if;
    end;
    if not exists(select 1 from public.contratos where id=c) or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
      or not exists(select 1 from crm.inversiones where contrato_id=c) then
      raise exception 'El rechazo dejó efectos parciales'; end if;
    select count(*) into n from private.contrato_eliminaciones where contrato_id=c;
    if n<>0 then raise exception 'El rechazo dejó reserva'; end if;
  end $t$;`);
});

test('Una inversión multiempresa con pagos y sin historial propio se archiva y se retira con el contrato',()=>{
  transaccion(`do $t$
  declare a uuid; c uuid; i uuid; r jsonb; copia jsonb; inv_antes jsonb; tit_antes jsonb; pagos_antes jsonb;
  begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    select k.id into strict c from public.contratos k where k.numero_contrato='AC-2026-0001';
    select x.id, to_jsonb(x) into strict i, inv_antes from crm.inversiones x where x.contrato_id=c;
    if exists(select 1 from crm.inversion_eventos where inversion_id=i)
      or exists(select 1 from crm.inversion_solicitudes where inversion_id=i) then
      raise exception 'Fixture con historial'; end if;
    select jsonb_agg(to_jsonb(t) order by t.id) into strict tit_antes from crm.inversion_titulares t where t.inversion_id=i;
    update public.cronograma_pagos set estado='pagado',monto_pagado=monto_programado,
      fecha_pago_real=current_date,registrado_por=a
      where id=(select id from public.cronograma_pagos where contrato_id=c order by numero_cuota limit 1);
    if not found or tit_antes is null then raise exception 'Fixture sin cuota o titulares'; end if;
    select jsonb_agg(to_jsonb(p) order by p.id) into pagos_antes from public.cronograma_pagos p where contrato_id=c;
    r:=crm.contrato_eliminar_auditado(c,a);
    if exists(select 1 from public.contratos where id=c) or exists(select 1 from crm.inversiones where id=i)
      or exists(select 1 from crm.inversion_titulares where inversion_id=i) then
      raise exception 'No retiró la inversión con el contrato'; end if;
    select snapshot into strict copia from crm.contratos_eliminados_auditoria
      where contrato_id=c and id=(r->>'auditoria_id')::uuid;
    if (copia->>'version')<>'2' or copia->'inversion' is distinct from inv_antes
      or copia->'inversion_titulares' is distinct from tit_antes
      or copia->'cronograma' is distinct from pagos_antes then
      raise exception 'La auditoría no conserva la inversión y sus titulares'; end if;
    if not exists(select 1 from public.audit_log where tabla='crm.inversiones' and fila_id=i::text and operacion='DELETE' and usuario_id=a) then
      raise exception 'DELETE de la inversión sin actor'; end if;
    if r->>'contrato_id'<>c::text or (select count(*) from jsonb_object_keys(r))<>4 then
      raise exception 'La respuesta cambió de forma'; end if;
  end $t$;`);
});

test('Un contrato sin inversión sigue archivándose con inversión nula en la copia',()=>{
  transaccion(`do $t$ declare a uuid; c uuid; copia jsonb;
  begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    select id into strict c from public.contratos where numero_contrato='F4-BASE-INICIAL';
    if exists(select 1 from crm.inversiones where contrato_id=c) then raise exception 'Fixture vinculado'; end if;
    perform crm.contrato_eliminar_auditado(c,a);
    select snapshot into strict copia from crm.contratos_eliminados_auditoria where contrato_id=c;
    if jsonb_typeof(copia->'inversion')<>'null' or copia->'inversion_titulares'<>'[]'::jsonb then
      raise exception 'La copia inventó una inversión'; end if;
  end $t$;`);
});

test('Una tabla hija nueva de crm.inversiones impide retirar la inversión sin revisarla',()=>{
  transaccion(`create table crm.prueba_dependencia_inversion(id uuid primary key, inversion_id uuid references crm.inversiones(id));
    do $t$ declare a uuid; c uuid;
    begin
      select id into strict a from public.perfiles where rol='admin' and activo limit 1;
      select id into strict c from public.contratos where numero_contrato='AC-2026-0001';
      begin
        perform crm.contrato_eliminar_auditado(c,a);
        raise exception 'Permitió una dependencia desconocida de la inversión';
      exception when sqlstate '55000' then
        if sqlerrm not like '%inversión del contrato tiene dependencias nuevas%' then raise; end if;
      end;
      if not exists(select 1 from public.contratos where id=c) or not exists(select 1 from crm.inversiones where contrato_id=c)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c) then
        raise exception 'El bloqueo cambió datos'; end if;
    end $t$;`);
});

test('La RPC solo acepta service_role y la evidencia no se expone por Data API',()=>{
  assert.equal(sql(`select bool_and(not has_function_privilege(r,'crm.contrato_eliminar_auditado(uuid,uuid)','execute'))
    from unnest(array['anon','authenticated']) r;`),'t');
  assert.equal(sql(`select has_function_privilege('service_role','crm.contrato_eliminar_auditado(uuid,uuid)','execute');`),'t');
  assert.equal(sql(`select bool_and(not has_table_privilege(r,'crm.contratos_eliminados_auditoria','select,insert,update,delete'))
    from unnest(array['anon','authenticated','service_role']) r;`),'t');
  assert.equal(sql(`select relrowsecurity from pg_class where oid='crm.contratos_eliminados_auditoria'::regclass;`),'t');
  assert.equal(sql(`select not has_function_privilege('service_role','crm.contrato_eliminacion_preparar(uuid,uuid)','execute')
    and not has_function_privilege('service_role','crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)','execute');`),'t');
});

test('Una dependencia CASCADE nueva impide borrar evidencia que aún no se archiva',()=>{
  transaccion(`create table crm.prueba_dependencia_pago(id uuid primary key, cuota_id uuid references public.cronograma_pagos(id) on delete cascade);
    do $t$ declare a uuid; c uuid;
    begin
      select id into strict a from public.perfiles where rol='admin' and activo limit 1;
      select id into strict c from public.contratos where numero_contrato='F4-BASE-INICIAL';
      begin
        perform crm.contrato_eliminar_auditado(c,a);
        raise exception 'Permitió cascada desconocida';
      exception when sqlstate '55000' then
        if sqlerrm not like '%dependencias nuevas%' then raise; end if;
      end;
      if not exists(select 1 from public.contratos where id=c)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c) then
        raise exception 'El bloqueo cambió datos'; end if;
    end $t$;`);
});

test('Una baja de Admin bloquea el borrado; un fallo durante DELETE revierte también la copia',()=>{
  transaccion(`
    create function pg_temp.rechazar_borrado_prueba() returns trigger language plpgsql as $f$
    begin raise exception 'Fallo sintético posterior al archivo' using errcode='23503'; end $f$;
    create trigger prueba_rechazar_borrado before delete on public.contratos
      for each row execute function pg_temp.rechazar_borrado_prueba();
    do $t$
    declare a uuid; c uuid;
    begin
      select id into strict a from public.perfiles where rol='admin' and activo limit 1;
      select id into strict c from public.contratos where numero_contrato='F4-BASE-INICIAL';
      update public.perfiles set activo=false where id=a;
      begin
        perform crm.contrato_eliminar_auditado(c,a);
        raise exception 'Admin inactivo autorizado';
      exception when insufficient_privilege then null; end;
      update public.perfiles set activo=true where id=a;
      begin
        perform crm.contrato_eliminar_auditado(c,a);
        raise exception 'Faltó el fallo de DELETE';
      exception when foreign_key_violation then null; end;
      if not exists(select 1 from public.contratos where id=c)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
        or exists(select 1 from private.contrato_eliminaciones where contrato_id=c) then
        raise exception 'Falló la atomicidad'; end if;
    end $t$;
  `);
});

test('No confirma una eliminación anterior si el mismo UUID vuelve a existir',()=>{
  transaccion(`do $t$ declare a uuid; c uuid;
    begin
      select id into strict a from public.perfiles where rol='admin' and activo limit 1;
      select id into strict c from public.contratos where numero_contrato='F4-BASE-INICIAL';
      -- Estado de una restauración parcial: historial anterior + contrato vivo.
      insert into crm.contratos_eliminados_auditoria(contrato_id,eliminado_por,snapshot,archivos)
        values(c,a,'{}','[]');
      begin
        perform crm.contrato_eliminar_auditado(c,a);
        raise exception 'Confirmó un borrado que no ocurrió';
      exception when sqlstate '55000' then
        if sqlerrm not like '%identificador del contrato%' then raise; end if;
      end;
      if not exists(select 1 from public.contratos where id=c) then
        raise exception 'Alteró el contrato en colisión'; end if;
    end $t$;`);
});

test('Una relación conocida con una acción de borrado distinta también se rechaza',()=>{
  transaccion(`do $t$ declare a uuid; c uuid; fk name;
    begin
      select conname into strict fk from pg_constraint
        where conrelid='public.documentos'::regclass and confrelid='public.contratos'::regclass and contype='f';
      execute format('alter table public.documentos drop constraint %I',fk);
      alter table public.documentos add constraint prueba_documentos_setnull
        foreign key(contrato_id) references public.contratos(id) on delete set null;
      select id into strict a from public.perfiles where rol='admin' and activo limit 1;
      select id into strict c from public.contratos where numero_contrato='F4-BASE-INICIAL';
      begin
        perform crm.contrato_eliminar_auditado(c,a);
        raise exception 'Permitió modificar la semántica de la evidencia';
      exception when sqlstate '55000' then
        if sqlerrm not like '%dependencias nuevas%' then raise; end if;
      end;
      if not exists(select 1 from public.contratos where id=c)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c) then
        raise exception 'El rechazo dejó efectos'; end if;
    end $t$;`);
});

for (const caso of [
  {nombre:'FK conocida retirada',ddl:`do $f$ declare fk name; begin
    select conname into strict fk from pg_constraint where conrelid='crm.inversion_eventos'::regclass and confrelid='crm.inversiones'::regclass and contype='f';
    execute format('alter table crm.inversion_eventos drop constraint %I',fk);
  end $f$;`},
  {nombre:'descendiente CASCADE del titular',ddl:`create table crm.prueba_hija_titular(id uuid primary key, titular_id uuid references crm.inversion_titulares(id) on delete cascade);`},
  {nombre:'segunda columna de una tabla conocida',ddl:`alter table crm.inversion_eventos add column inversion_alterna uuid references crm.inversiones(id) on delete set null;`},
  {nombre:'acción CASCADE en una relación conocida',ddl:`do $f$ declare fk name; begin
    select conname into strict fk from pg_constraint where conrelid='crm.inversion_titulares'::regclass and confrelid='crm.inversiones'::regclass and contype='f';
    execute format('alter table crm.inversion_titulares drop constraint %I',fk);
    alter table crm.inversion_titulares add constraint prueba_cascada foreign key(inversion_id) references crm.inversiones(id) on delete cascade;
  end $f$;`},
]) test(`Rechaza esquema inesperado: ${caso.nombre}`,()=>{
  transaccion(caso.ddl+`do $t$ declare a uuid; c uuid; begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    select id into strict c from public.contratos where numero_contrato='AC-2026-0001';
    begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'Admitió esquema no archivado';
    exception when sqlstate '55000' then
      if sqlerrm not like '%inversión del contrato tiene dependencias nuevas%' then raise; end if;
    end;
    if not exists(select 1 from public.contratos where id=c)
      or not exists(select 1 from crm.inversiones where contrato_id=c)
      or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
      or exists(select 1 from private.contrato_eliminaciones where contrato_id=c) then
      raise exception 'El rechazo dejó efectos'; end if;
  end $t$;`);
});

test('Un fallo después de retirar la inversión restaura también sus titulares y el actor',()=>{
  transaccion(`
    create function pg_temp.rechazar_borrado_vinculado() returns trigger language plpgsql as $f$
    begin raise exception 'Fallo sintético posterior a retirar inversión' using errcode='23503'; end $f$;
    create trigger prueba_rechazar_borrado before delete on public.contratos
      for each row execute function pg_temp.rechazar_borrado_vinculado();
    do $t$ declare a uuid; c uuid; i uuid; antes jsonb; titulares jsonb;
    begin
      select id into strict a from public.perfiles where rol='admin' and activo limit 1;
      select id into strict c from public.contratos where numero_contrato='AC-2026-0001';
      select id,to_jsonb(x) into strict i,antes from crm.inversiones x where contrato_id=c;
      select jsonb_agg(to_jsonb(x) order by id) into titulares from crm.inversion_titulares x where inversion_id=i;
      perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'Faltó el fallo inyectado';
      exception when foreign_key_violation then null; end;
      if antes is distinct from (select to_jsonb(x) from crm.inversiones x where id=i)
        or titulares is distinct from (select jsonb_agg(to_jsonb(x) order by id) from crm.inversion_titulares x where inversion_id=i)
        or not exists(select 1 from public.contratos where id=c)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
        or exists(select 1 from private.contrato_eliminaciones where contrato_id=c)
        or current_setting('request.jwt.claim.sub')<>'00000000-0000-0000-0000-000000000001' then
        raise exception 'Rollback incompleto'; end if;
    end $t$;
  `);
});

for (const tabla of ['inversion_solicitudes','inversion_ajustes_mes_cerrado','inversion_cotitular_origenes']) {
  test(`Conserva contrato e inversión cuando hay ${tabla}`,()=>{
    transaccion(`do $t$ declare a uuid; c uuid; i uuid; begin
      select id into strict a from public.perfiles where rol='admin' and activo limit 1;
      select id into strict c from public.contratos where numero_contrato='AC-2026-0001';
      select id into strict i from crm.inversiones where contrato_id=c;
      -- Sembrar una referencia sintética sin ejecutar efectos ajenos de creación.
      set local session_replication_role=replica;
      update crm.${tabla} set inversion_id=i where ctid=(select ctid from crm.${tabla} limit 1);
      if not found then raise exception 'Falta fixture de historial'; end if;
      set local session_replication_role=origin;
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'Eliminó un historial protegido';
      exception when sqlstate '55000' then if sqlerrm not like '%historial propio%' then raise; end if; end;
      if not exists(select 1 from public.contratos where id=c)
        or not exists(select 1 from crm.inversiones where id=i)
        or not exists(select 1 from crm.${tabla} where inversion_id=i)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
        or exists(select 1 from private.contrato_eliminaciones where contrato_id=c) then
        raise exception 'El rechazo dejó efectos'; end if;
    end $t$;`);
  });
}


test('Un contrato vinculado de un mes cerrado conserva todas las filas',()=>{
  transaccion(`do $t$ declare a uuid; c uuid; mes date; begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    select id into strict c from public.contratos where numero_contrato='AC-2026-0001';
    select periodo into strict mes from crm.periodos_cerrados limit 1;
    set local session_replication_role=replica;
    insert into crm.operaciones_cartera select (jsonb_populate_record(null::crm.operaciones_cartera,to_jsonb(x)||jsonb_build_object('id',gen_random_uuid(),'contrato_nuevo_id',c,'periodo',mes,'fecha_operacion',mes))).* from crm.operaciones_cartera x limit 1;
    if not found then raise exception 'Falta operación sintética'; end if;
    set local session_replication_role=origin;
    begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'Eliminó mes cerrado';
    exception when sqlstate 'P0409' then if sqlerrm not like '%mes comercial cerrado%' then raise; end if; end;
    if not exists(select 1 from public.contratos where id=c)
      or not exists(select 1 from crm.inversiones where contrato_id=c)
      or not exists(select 1 from crm.operaciones_cartera where contrato_nuevo_id=c)
      or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
      or exists(select 1 from private.contrato_eliminaciones where contrato_id=c) then
      raise exception 'El cierre no protegió todas las filas'; end if;
  end $t$;`);
});

test('La restricción heredada de renovación revierte íntegramente inversión y auditoría',()=>{
  transaccion(`do $t$ declare a uuid; c uuid; origen uuid; inv uuid; antes jsonb; eventos jsonb; op uuid; mes date:=date '2099-01-01'; begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    select id into strict c from public.contratos where numero_contrato='AC-2026-0001';
    select i.contrato_id,i.id,to_jsonb(i) into strict origen,inv,antes from crm.inversiones i where i.contrato_id is not null and i.contrato_id<>c limit 1;
    select coalesce(jsonb_agg(to_jsonb(e) order by id),'[]') into eventos from crm.inversion_eventos e where inversion_id=inv;
    set local session_replication_role=replica;
    update public.contratos set estado='renovado',renovado_a_id=c,cerrado_en=now(),cerrado_por=a where id=origen;
    insert into crm.operaciones_cartera select (jsonb_populate_record(null::crm.operaciones_cartera,to_jsonb(x)||jsonb_build_object('id',gen_random_uuid(),'contrato_nuevo_id',c,'tipo','renovacion','contrato_origen_id',origen,'periodo',mes,'fecha_operacion',mes,'capital_renovado',1,'capital_adicional',0,'elegible_conversion',true,'desglose_completo',true))).* from crm.operaciones_cartera x limit 1 returning id into op;
    if not found then raise exception 'Falta operación sintética'; end if;
    set local session_replication_role=origin;
    begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'No conservó la restricción heredada';
    exception when others then if sqlerrm not like 'Transición de estado no permitida:%' then raise; end if; end;
    if not exists(select 1 from public.contratos where id=c) or not exists(select 1 from crm.inversiones where contrato_id=c)
      or not exists(select 1 from crm.operaciones_cartera where id=op)
      or not exists(select 1 from public.contratos where id=origen and renovado_a_id=c and cerrado_en is not null and cerrado_por=a and estado='renovado')
      or antes is distinct from (select to_jsonb(i) from crm.inversiones i where id=inv)
      or eventos is distinct from (select coalesce(jsonb_agg(to_jsonb(e) order by id),'[]') from crm.inversion_eventos e where inversion_id=inv)
      or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
      or exists(select 1 from private.contrato_eliminaciones where contrato_id=c) then
      raise exception 'El rechazo heredado dejó efectos parciales'; end if;
  end $t$;`);
});

test('Superadmin conserva la restauración de una renovación sin alterar la inversión origen',()=>{
  transaccion(`do $t$ declare a uuid; c uuid; origen uuid; inv uuid; antes jsonb; eventos jsonb; op uuid; mes date:=date '2099-01-01'; begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    update public.perfiles set rol='superadmin' where id=a;
    select id into strict c from public.contratos where numero_contrato='AC-2026-0001';
    select i.contrato_id,i.id,to_jsonb(i) into strict origen,inv,antes from crm.inversiones i where i.contrato_id is not null and i.contrato_id<>c limit 1;
    select coalesce(jsonb_agg(to_jsonb(e) order by id),'[]') into eventos from crm.inversion_eventos e where inversion_id=inv;
    set local session_replication_role=replica;
    update public.contratos set estado='renovado',renovado_a_id=c,cerrado_en=now(),cerrado_por=a where id=origen;
    insert into crm.operaciones_cartera select (jsonb_populate_record(null::crm.operaciones_cartera,to_jsonb(x)||jsonb_build_object('id',gen_random_uuid(),'contrato_nuevo_id',c,'tipo','renovacion','contrato_origen_id',origen,'periodo',mes,'fecha_operacion',mes,'capital_renovado',1,'capital_adicional',0,'elegible_conversion',true,'desglose_completo',true))).* from crm.operaciones_cartera x limit 1 returning id into op;
    if not found then raise exception 'Falta operación sintética'; end if;
    set local session_replication_role=origin;
    perform crm.contrato_eliminar_auditado(c,a);
    if exists(select 1 from public.contratos where id=c) or exists(select 1 from crm.inversiones where contrato_id=c)
      or exists(select 1 from crm.operaciones_cartera where id=op)
      or not exists(select 1 from public.contratos where id=origen and renovado_a_id is null and cerrado_en is null and cerrado_por is null and estado in ('activo','vencido'))
      or antes is distinct from (select to_jsonb(i) from crm.inversiones i where id=inv)
      or eventos is distinct from (select coalesce(jsonb_agg(to_jsonb(e) order by id),'[]') from crm.inversion_eventos e where inversion_id=inv)
      or not exists(select 1 from crm.contratos_eliminados_auditoria x,jsonb_array_elements(x.snapshot->'operaciones') o where x.contrato_id=c and o->>'id'=op::text)
      or exists(select 1 from private.contrato_eliminaciones where contrato_id=c) then
      raise exception 'Restauración o conservación de origen incorrecta'; end if;
  end $t$;`);
});

}
