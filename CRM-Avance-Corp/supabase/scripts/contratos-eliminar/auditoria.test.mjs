import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

// Banco propio, sintético y cerrado: nunca acepta un destino del ambiente.
const contenedor='supabase_db_avancecorp-f5-bank';
const db='contratos_eliminar_20260915';
function sql(consulta) {
  const r=spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,
    '-v','ON_ERROR_STOP=1','-f','-'],{input:consulta,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr || r.error?.message);
  return r.stdout.trim();
}
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

test('Deniega roles ajenos; historial protegido revierte sin auditoría ni borrados',()=>{
  transaccion(`do $t$
  declare a uuid; c uuid; p record; n integer;
  begin
    select id into strict a from public.perfiles where rol='admin' and activo limit 1;
    select contrato_id into strict c from crm.inversiones where contrato_id is not null limit 1;
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
    exception when sqlstate '55000' then null; end;
    if not exists(select 1 from public.contratos where id=c) or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c) then
      raise exception 'El rechazo dejó efectos parciales'; end if;
    select count(*) into n from private.contrato_eliminaciones where contrato_id=c;
    if n<>0 then raise exception 'El rechazo dejó reserva'; end if;
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
