// Regresión del 001457: el alta unificada genera registro y solicitud confirmada.
// Solo banco local sintético; cada prueba termina en ROLLBACK.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const db=process.env.CONTRATOS_AUDITORIA_BANCO || 'contratos_registro_20260921';
assert.ok(['contratos_vinculados_20260916','contratos_registro_20260921'].includes(db), 'Banco local no autorizado');
function sql(consulta) {
  const r=spawnSync('docker',['exec','-i','supabase_db_avancecorp-f5-bank','psql','-XqAt',
    '-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-'],
  {input:`begin; ${consulta} rollback;`,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr || r.error?.message);
  return r.stdout.trim();
}
const fixture=`
  select id into strict a from public.perfiles where rol='admin' and activo limit 1;
  select id into strict c from public.contratos where numero_contrato='AC-2026-0002';
  select id into strict i from crm.inversiones where contrato_id=c;
  select id into strict s from crm.inversion_solicitudes where inversion_id=i;
`;

test('Admin archiva el alta inicial, conserva solicitudes y revisiones y cancela su replay',()=>{
  sql(`do $t$ declare a uuid; c uuid; i uuid; s uuid; r jsonb; copia jsonb;
    eventos jsonb; solicitudes jsonb; revisiones jsonb; correcciones jsonb; actor uuid; rev integer;
  begin
    ${fixture}
    insert into crm.inversion_solicitud_correcciones
      select (jsonb_populate_record(null::crm.inversion_solicitud_correcciones,to_jsonb(x)||
        jsonb_build_object('id',gen_random_uuid(),'solicitud_id',s,'revision_anterior',98,'revision',99))).*
      from crm.inversion_solicitud_correcciones x limit 1;
    if not found then raise exception 'Fixture sin corrección de solicitud'; end if;
    select jsonb_agg(to_jsonb(e) order by id) into eventos from crm.inversion_eventos e where inversion_id=i;
    select jsonb_agg(to_jsonb(x) order by id) into solicitudes from crm.inversion_solicitudes x where inversion_id=i;
    select jsonb_agg(to_jsonb(x) order by id) into revisiones from crm.inversion_solicitud_revisiones x where solicitud_id=s;
    select jsonb_agg(to_jsonb(x) order by id) into correcciones from crm.inversion_solicitud_correcciones x where solicitud_id=s;
    if eventos is null or solicitudes is null then raise exception 'Fixture sin alta inicial'; end if;
    r:=crm.contrato_eliminar_auditado(c,a);
    select snapshot into strict copia from crm.contratos_eliminados_auditoria where contrato_id=c and eliminado_por=a;
    if copia->'inversion_eventos' is distinct from eventos or copia->'inversion_solicitudes' is distinct from solicitudes
      or copia->>'version'<>'3' then raise exception 'No archivó exactamente el alta'; end if;
    if exists(select 1 from public.contratos where id=c) or exists(select 1 from crm.inversiones where id=i)
      or exists(select 1 from crm.inversion_eventos where inversion_id=i)
      or not exists(select 1 from crm.inversion_solicitudes where id=s and estado='cancelada' and inversion_id is null)
      then raise exception 'No retiró el contrato y su inversión/canceló solicitud'; end if;
    if revisiones is distinct from (select jsonb_agg(to_jsonb(x) order by id) from crm.inversion_solicitud_revisiones x where solicitud_id=s)
      or correcciones is distinct from (select jsonb_agg(to_jsonb(x) order by id) from crm.inversion_solicitud_correcciones x where solicitud_id=s)
      then raise exception 'Modificó revisiones o correcciones'; end if;
    if crm.contrato_eliminar_auditado(c,a) is distinct from r then raise exception 'Replay no idempotente'; end if;
    select creado_por,revision_datos into actor,rev from crm.inversion_solicitudes where id=s;
    update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura';
    perform set_config('request.jwt.claim.sub',actor::text,true);
    begin
      perform crm.confirmar_inversion_fn(s);
      raise exception 'El replay de alta revivió el contrato';
    exception when sqlstate 'P0409' then
      if sqlerrm not like '%cancelada%' then raise; end if;
    end;
  end $t$;`);
});

test('Ni Admin ni una variable falsificada pueden borrar o editar el registro por fuera de la RPC',()=>{
  sql(`do $t$ declare a uuid; c uuid; i uuid; s uuid; begin
    ${fixture}
    perform set_config('request.jwt.claim.sub',a::text,true);
    perform set_config('crm.contrato_registro_eliminacion',gen_random_uuid()::text,true);
    begin delete from crm.inversion_eventos where inversion_id=i;
      raise exception 'Permitió borrar sin copia ni reserva';
    exception when sqlstate 'P0409' then null; end;
    begin update crm.inversion_eventos set motivo='alterado' where inversion_id=i;
      raise exception 'Permitió editar historial';
    exception when sqlstate 'P0409' then null; end;
  end $t$;`);
});

test('Un fallo posterior restaura el registro, solicitud, contrato e inversión completos',()=>{
  sql(`create function pg_temp.fallar_tras_cancelar() returns trigger language plpgsql as $f$
    begin raise exception 'Fallo sintético final' using errcode='23503'; end $f$;
    create trigger prueba_fallo_final before delete on public.contratos
      for each row execute function pg_temp.fallar_tras_cancelar();
    do $t$ declare a uuid; c uuid; i uuid; s uuid; eventos jsonb; solicitud jsonb;
    begin
      ${fixture}
      select jsonb_agg(to_jsonb(x) order by id) into eventos from crm.inversion_eventos x where inversion_id=i;
      select to_jsonb(x) into solicitud from crm.inversion_solicitudes x where id=s;
      perform set_config('crm.contrato_registro_eliminacion','test-anterior',true);
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'Faltó fallo final';
      exception when foreign_key_violation then null; end;
      if solicitud is distinct from (select to_jsonb(x) from crm.inversion_solicitudes x where id=s)
        or eventos is distinct from (select jsonb_agg(to_jsonb(x) order by id) from crm.inversion_eventos x where inversion_id=i)
        or not exists(select 1 from public.contratos where id=c)
        or not exists(select 1 from crm.inversiones where id=i)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
        or exists(select 1 from private.contrato_eliminaciones where contrato_id=c)
        or current_setting('crm.contrato_registro_eliminacion')<>'test-anterior'
        then raise exception 'Rollback incompleto'; end if;
    end $t$;`);
});

test('Una dependencia nueva de los eventos bloquea el borrado sin perder evidencia',()=>{
  sql(`create table crm.prueba_hija_evento(id uuid primary key,evento_id uuid references crm.inversion_eventos(id) on delete cascade);
    do $t$ declare a uuid; c uuid; i uuid; s uuid; begin
      ${fixture}
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'No detectó nueva dependencia';
      exception when sqlstate '55000' then if sqlerrm not like '%dependencias nuevas%' then raise; end if; end;
      if not exists(select 1 from crm.inversion_eventos where inversion_id=i)
        or not exists(select 1 from crm.inversion_solicitudes where id=s and estado='confirmada')
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
        then raise exception 'Dejó efectos parciales'; end if;
    end $t$;`);
});

for (const tipo of ['correccion','anulacion']) {
  test(`El historial posterior ${tipo} conserva su bloqueo`,()=>{
    sql(`do $t$ declare a uuid; c uuid; i uuid; s uuid; begin
      ${fixture}
      insert into crm.inversion_eventos(inversion_id,tipo,motivo,creado_por) values(i,'${tipo}','Prueba posterior',a);
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'No protegió historial posterior';
      exception when sqlstate '55000' then if sqlerrm not like '%historial propio%' then raise; end if; end;
    end $t$;`);
  });
}

for (const [caso,cambio] of [
  ['fuente ajena',"resultado=jsonb_set(resultado,'{fuente,id}',to_jsonb(gen_random_uuid()::text))"],
  ['persona ajena',"inversionista_id=(select id from crm.inversionistas where id<>(select inversionista_id from crm.inversiones where id=i) limit 1)"],
  ['empresa ajena',"empresa_id=(select id from crm.empresas where id<>(select empresa_id from crm.inversiones where id=i) limit 1)"],
  ['solicitud no confirmada',"estado='preparada',resultado=null"],
]) {
  test(`Una solicitud con ${caso} bloquea la eliminación completa`,()=>{
    sql(`do $t$ declare a uuid; c uuid; i uuid; s uuid; begin
      ${fixture}
      update crm.inversion_solicitudes set ${cambio} where id=s;
      begin perform crm.contrato_eliminar_auditado(c,a); raise exception 'Aceptó solicitud incoherente';
      exception when sqlstate '55000' then if sqlerrm not like '%historial propio%' then raise; end if; end;
      if not exists(select 1 from public.contratos where id=c)
        or not exists(select 1 from crm.inversion_eventos where inversion_id=i)
        or exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=c)
        then raise exception 'El rechazo dejó efectos'; end if;
    end $t$;`);
  });
}
