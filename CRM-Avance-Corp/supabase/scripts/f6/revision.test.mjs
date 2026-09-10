import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {como,contenedor,leer,literal as q,rpc,sql} from '../f5/banco-local.mjs';

const f=leer('fixtures.json'),actor=r=>f.usuarios[r].id;
const claims=r=>`select set_config('request.jwt.claims',${q(JSON.stringify({sub:actor(r),role:'authenticated'}))},true);`;
const exigir=(condicion,mensaje)=>`do $$begin if not (${condicion}) then raise exception '${mensaje}';end if;end$$;`;
const agendar=(persona,tarea)=>`select crm.postventa_agendar_fn(${q(tarea)},${q(persona)},jsonb_build_object('tipo','llamada','titulo','Seguimiento de revisión F6','vence_en',clock_timestamp()+interval '2 days'));`;
async function bloquearFlag(){
 const p=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});
 const salida=once(p,'exit');let error='';p.stderr.on('data',b=>error+=b);
 const listo=new Promise((resolve,reject)=>{let s='';p.stdout.on('data',b=>{s+=b;if(s.includes('F6_REVISION_LOCK'))resolve();});p.once('exit',()=>reject(new Error(error)));});
 p.stdin.write("begin;select nombre from crm.multiempresa_flags where nombre='postventa_neutral' for update;select 'F6_REVISION_LOCK';\n");await listo;
 return async()=>{p.stdin.end('rollback;\n\\q\n');await salida;};
}

test('F6: regresiones verificadas tras revisión independiente',async t=>{
 const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
 const x=JSON.parse(sql(`select jsonb_build_object('persona',i.id,'perfil',i.perfil_id,'lead',l.id) from crm.inversionistas i
   join crm.leads l on l.inversionista_id=i.id and l.activo
   where i.responsable_relacion_id=${q(actor('vendedor'))} and not i.no_contactar and not l.no_contactar
     and i.perfil_id is not null and exists(select 1 from private.cartera_f5_fuentes() f where f.inversionista_id=i.id and f.empresa='qorilazo' and not f.es_demo)
   order by i.id limit 1`));
 try {
  sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','ficha_360_neutral','postventa_neutral')");
  await t.test('la cola propia del supervisor conserva F5 pero no revela tareas ni historia F6',()=>{
   const tarea=randomUUID();
   sql(`begin;${claims('gerencia')}${agendar(x.persona,tarea)}
    select set_config('crm.op_privilegiada','on',true);
    update crm.leads set vendedor_id=null,asignado_supervisor_id=${q(actor('supervisor'))} where id=${q(x.lead)};
    update crm.inversionistas set responsable_relacion_id=null where id=${q(x.persona)};
    ${claims('supervisor')}
    ${exigir(`exists(select 1 from private.cartera_f5_personas_visibles() where inversionista_id=${q(x.persona)})`,'La prueba no ejercita la cola F5')}
    ${exigir(`not private.postventa_visible(${q(x.persona)})`,'La cola F6 debe ser exclusiva de Gerencia')}
    set local role authenticated;
    do $$declare ficha jsonb;begin ficha:=crm.inversionista_ficha_fn(${q(x.persona)});
      if ficha is null or (ficha->'capacidades'->>'postventa')::boolean
        or exists(select 1 from jsonb_array_elements(ficha->'historial') h where h->>'origen'='postventa')
        or exists(select 1 from jsonb_array_elements(ficha->'tareas') h where h->>'inversionista_id' is not null)
      then raise exception 'La ficha F5 reveló postventa fuera del ámbito';end if;end$$;
    rollback;`);
  });
  await t.test('un cambio de modo F6 no impide abrir F5 ni devolver la agenda legada',async()=>{
   const token=await como('vendedor'),soltar=await bloquearFlag();
   try {
    const agenda=await rpc('postventa_agenda_fn',{},token);assert.equal(agenda.ok,true,JSON.stringify(agenda.data));assert.deepEqual(agenda.data,[]);
    const ficha=await rpc('inversionista_ficha_fn',{p_inversionista:x.persona},token);
    assert.equal(ficha.ok,true,JSON.stringify(ficha.data));assert.equal(ficha.data.persona.inversionista_id,x.persona);assert.equal(ficha.data.capacidades.postventa,false);
   } finally {await soltar();}
  });
  await t.test('contrato explícito enlaza el perfil y devuelve la revisión realmente persistida',()=>{
   const tarea=randomUUID();
   sql(`begin;${claims('gerencia')}${agendar(x.persona,tarea)}
    do $$declare a jsonb;r jsonb;begin
     select e into a from jsonb_array_elements(crm.postventa_agenda_fn()) e where e->>'id'=${q(tarea)};
     if a is null or a ? 'creado_por' or a ? 'cancelada_por_id' or not (a->'postventa_perfil_ids' ? ${q(x.perfil)})
       or a->>'perfil_id' is not null then raise exception 'Proyección neutral incorrecta';end if;
     r:=crm.postventa_tarea_fn(${q(randomUUID())},${q(tarea)},1,'reprogramar',jsonb_build_object('vence_en',clock_timestamp()+interval '3 days','detalle','Fecha acordada en la revisión'));
     if (r->'tarea'->>'postventa_revision')::int<>(select postventa_revision from crm.tareas where id=${q(tarea)})
       or (r->'tarea'->>'reprogramaciones')::int<>(select reprogramaciones from crm.tareas where id=${q(tarea)})
       or exists(select 1 from crm.postventa_escrituras) then raise exception 'Respuesta anterior a los triggers';end if;
    end$$;rollback;`);
  });
  await t.test('la agenda tiene una cota de 2000 filas incluso para Gerencia',()=>{
   const persona=randomUUID();
   sql(`begin;${claims('gerencia')}
    insert into crm.inversionistas(id,responsable_relacion_id,creado_por) values(${q(persona)},${q(actor('gerencia'))},${q(actor('gerencia'))});
    do $$begin for i in 1..2001 loop
     perform private.postventa_insertar_tarea(gen_random_uuid(),${q(persona)},jsonb_build_object('tipo','llamada','titulo','Ensayo de cota','vence_en',clock_timestamp()+interval '1 hour'));
    end loop;end$$;
    ${exigir('jsonb_array_length(crm.postventa_agenda_fn())=2000','La agenda no limita su payload')}
    rollback;`);
  });
  await t.test('cancelar no permite programar otro contacto ni dejar un recibo parcial',()=>{
   const tarea=randomUUID(),clave=randomUUID();
   sql(`begin;${claims('gerencia')}${agendar(x.persona,tarea)}
    do $$begin begin
     perform crm.postventa_tarea_fn(${q(clave)},${q(tarea)},1,'cerrar',jsonb_build_object('estado','cancelada','detalle','Cancelación del ensayo',
       'siguiente',jsonb_build_object('tipo','llamada','titulo','Contacto indebido','vence_en',clock_timestamp()+interval '3 days')));
     raise exception 'Se programó tras cancelar';exception when sqlstate '22023' then null;end;end$$;
    ${exigir(`(select estado='pendiente' from crm.tareas where id=${q(tarea)}) and not exists(select 1 from crm.postventa_operaciones where clave=${q(clave)})`,'Cancelación parcial')}
    rollback;`);
  });
  await t.test('veto explica el cierre en el lead y aparece una sola vez en la ficha unificada',()=>{
   sql(`begin;${claims('gerencia')}
    select crm.postventa_veto_fn(${q(randomUUID())},${q(x.persona)},true,'Traza del veto revisada en el ensayo');
    do $$declare g uuid;ficha jsonb;begin
     select id into g from crm.inversionista_gestiones where inversionista_id=${q(x.persona)} and tipo='veto' and detalle='No contactar: Traza del veto revisada en el ensayo' order by creado_en desc limit 1;
     if not exists(select 1 from crm.actividades where lead_id=${q(x.lead)} and metadata->>'postventa_gestion_id'=g::text) then raise exception 'El lead perdió el motivo';end if;
     ficha:=crm.inversionista_ficha_fn(${q(x.persona)});
     if (select count(*) from jsonb_array_elements(ficha->'historial') h where h->>'detalle'='No contactar: Traza del veto revisada en el ensayo')<>1 then raise exception 'Gestión duplicada en la ficha';end if;
    end$$;rollback;`);
  });
 } finally {for(const [nombre,activo] of Object.entries(flags))sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);}
});
