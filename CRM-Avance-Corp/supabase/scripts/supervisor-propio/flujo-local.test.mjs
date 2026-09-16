// Banco sintético exclusivo. Cada caso termina en ROLLBACK; no acepta destinos externos.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const contenedor='supabase_db_avancecorp-f5-bank', db='supervisor_propio_vigente_20260916';
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function ejecutar(sql) {
  return spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','supabase_admin','-d',db,'-v','ON_ERROR_STOP=1','-f','-'],
    {input:"\\set VERBOSITY verbose\nset timezone='America/Lima';set plpgsql.check_asserts=on;\n"+sql,encoding:'utf8',maxBuffer:8*1024*1024});
}
function sql(s) {const r=ejecutar(s);assert.equal(r.status,0,r.stderr||r.error?.message);return r.stdout.trim();}
assert.equal(sql('select current_database()'),db);
const actores=JSON.parse(sql("select jsonb_object_agg(split_part(correo,'.',1),id) from public.perfiles where correo in ('sup1.crm@demo.avancecorp.pe','sup2.crm@demo.avancecorp.pe','vend1.crm@demo.avancecorp.pe','gerencia.crm@demo.avancecorp.pe')"));
for(const rol of ['sup1','sup2','vend1','gerencia']) assert.ok(actores[rol],`Falta actor sintético ${rol}`);
const actor=k=>`reset role;set local request.jwt.claim.sub=${q(actores[k])};set local request.jwt.claims=${q(JSON.stringify({sub:actores[k],role:'authenticated'}))};set local role authenticated;`;
const preparar=`update crm.piloto_f8_control set activo=false where singleton;
update crm.multiempresa_flags set activo=(nombre<>'metricas_multiempresa_sombra');
-- Completa el único cierre heredado ficticio sin identidad de la matriz RLS.
set local crm.op_privilegiada='on';
update crm.cierres_externos set inversionista_id=private.inversionista_resolver('DNI','96169999',true,'fixture_supervisor')
where id='fcd4baa6-49d9-40e1-9c09-0e81b801ee55' and inversionista_id is null;
set local crm.op_privilegiada='off';
update public.perfiles set dni='96169998',telefono='+51996169998'
where id=${q(actores.sup1)};`;
const lead='96160000-0000-4000-8000-000000000001', perfil='96160000-0000-4000-8000-000000000002';
const alta=(destino=actores.sup1,origen='oficina')=>`crm.crear_lead_si_disponible(p_nombre_completo=>'QA SUPERVISOR PROPIO',p_telefono=>'996160001',p_origen=>${q(origen)},p_monto_estimado=>20000,p_moneda=>'PEN',p_id=>${q(lead)},p_dni=>'96160001',p_vendedor_id=>${destino?q(destino)+'::uuid':'null'})`;
const crear=(destino=actores.sup1)=>`do $$ begin assert (${alta(destino)}->>'estado')='creado','No creó el lead';end $$;`;
const condiciones=`jsonb_build_object('categoria','nuevo','capital',20000,'moneda','PEN','modalidad','mensual','tipo_interes','simple','fecha_inicio',current_date,'fecha_vencimiento',(current_date+interval '1 year')::date,'tasa_anual',15)`;
const reservar=tasa=>`crm.reservar_conversion_lead(${q(lead)},'DNI','96160001',jsonb_build_object('correo','supervisor-propio@example.invalid','nombre_completo','QA SUPERVISOR PROPIO','domicilio','Calle QA 123','condiciones_tasa',${tasa??condiciones}))`;
function caso(cuerpo) {return sql(`begin;set local statement_timeout='20s';${preparar}${cuerpo}rollback;`);}
const rechaza=(consulta,codigo)=>`do $$ begin begin perform ${consulta};raise exception 'Faltó rechazo';exception when sqlstate '${codigo}' then null;end;end $$;`;

const baseRanking=`${actor('gerencia')}
select set_config('qa.conversion_antes',crm.conversion_mensual_fn(date_trunc('month',current_date)::date)::text,true);`;
const verificarRanking=`${actor('gerencia')}
do $$ declare c jsonb;m jsonb;antes jsonb;begin
  antes:=current_setting('qa.conversion_antes')::jsonb;
  c:=crm.conversion_mensual_fn(date_trunc('month',current_date)::date);
  m:=crm.cumplimiento_metas_fn(date_trunc('month',current_date)::date);
  -- Oficina/alta manual tiene aporte cero en el KPI, tanto para analistas como supervisores.
  assert c->'total'=antes->'total','Alta de oficina alteró el KPI de conversión';
  assert not exists(select 1 from jsonb_array_elements(c->'responsables') x where x->>'vendedor_id'=${q(actores.sup1)}),'Supervisor entró al ranking de conversión';
  assert not exists(select 1 from jsonb_array_elements(m->'vendedores') x where x->>'vendedor_id'=${q(actores.sup1)}),'Supervisor entró al ranking de metas';
  assert exists(select 1 from jsonb_array_elements(m->'fuera_ranking') x where x->>'persona_id'=${q(actores.sup1)} and x->>'motivo'='supervisor' and exists(select 1 from jsonb_array_elements(x->'detalles') d where d->>'categoria'='nuevo' and d->>'moneda'='PEN' and (d->>'capital_real')::numeric=20000 and (d->>'contratos_real')::int=1)),'Capital supervisor ausente de Fuera del ranking';
end $$;`;

test('alta propia persiste autor y responsable, sin entrar al reparto, y el reintento no duplica',()=>{
  caso(`${actor('sup1')}${crear()}
    do $$ begin
      assert (select vendedor_id=${q(actores.sup1)} and creado_por=${q(actores.sup1)} and asignado_supervisor_id is null from crm.leads where id=${q(lead)}),'Responsabilidad o autoría perdida';
      assert (${alta()}->>'lead_id')=${q(lead)},'Reintento alteró el id';
      assert (select count(*)=1 from crm.leads where id=${q(lead)}),'Lead duplicado';
      assert (crm.mi_acceso_fn()->>'puede_contratar')::boolean,'Supervisor sin capacidad contractual';
    end $$;`);
});

test('mantiene las opciones de analista de equipo y bandeja pendiente',()=>{
  for(const destino of [actores.vend1,null]) caso(`${actor('sup1')}${crear(destino)}
    do $$ begin assert (select vendedor_id is not distinct from ${destino?q(destino)+'::uuid':'null'} and
      asignado_supervisor_id is not distinct from ${destino?'null':q(actores.sup1)+'::uuid'} from crm.leads where id=${q(lead)}),'Destino alterado';end $$;`);
});

test('Referido sigue reservado al analista; supervisor ajeno no recibe el alta',()=>{
  caso(`${actor('sup1')}${rechaza(alta(actores.sup1,'referido'),'42501')}${rechaza(alta(actores.sup2),'42501')}`);
});

test('otro supervisor no puede leer ni reservar el lead propio',()=>{
  caso(`${actor('sup1')}${crear()}${actor('sup2')}
    do $$ begin assert not exists(select 1 from crm.leads where id=${q(lead)}),'Fuga de lead ajeno';end $$;
    ${rechaza(reservar(),'P0001')}`);
});

test('revocar el perfil impide crear un lead propio y convertir',()=>{
  caso(`update public.perfiles set activo=false where id=${q(actores.sup1)};
    ${actor('sup1')}${rechaza(alta(),'42501')}${rechaza(reservar(),'42501')}`);
});

test('una tasa superior sin autorización continúa bloqueada para el supervisor',()=>{
  caso(`insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
    select max(version)+1,clock_timestamp()-interval '1 minute',15,28,1,'enforcement' from crm.politica_rentabilidad;
    ${actor('sup1')}${crear()}${rechaza(reservar(`(${condiciones} || '{"tasa_anual":27}'::jsonb)`),'P0410')}`);
});

test('conversión cooperativa conserva al supervisor y aparece en su Cartera',()=>{
  caso(`${baseRanking}${actor('sup1')}${crear()}
    do $$ declare r jsonb;c jsonb;begin
      r:=crm.convertir_lead_externo(p_lead_id=>${q(lead)},p_cooperativa=>'qorilazo',p_monto=>20000,p_moneda=>'PEN',p_documento_tipo=>'DNI',p_documento=>'96160001',p_nombre=>'QA SUPERVISOR PROPIO',p_numero_transaccion=>'QA-SUP-9616',p_plazo_meses=>12,p_tasa_anual=>15);
      assert (r->>'ok')::boolean,'No convirtió';
      assert (select etapa='convertido' and vendedor_id=${q(actores.sup1)} from crm.leads where id=${q(lead)}),'Cierre perdió responsable';
      c:=crm.cartera_inversionistas_filtrada_fn(p_texto=>'96160001');
      assert (c->>'total')::int=1,'Cliente no aparece en Cartera';
      assert c->'filas'->0->>'responsable_id'=${q(actores.sup1)},'Cartera cambió el responsable';
    end $$;${verificarRanking}`);
});

test('conversión Avance, contrato y Cartera conservan la responsabilidad del supervisor',()=>{
  caso(`${baseRanking}${actor('sup1')}${crear()}
    do $$ declare r jsonb;begin
      r:=${reservar()};
      perform crm.marcar_efectos_conversion(${q(lead)},(r->>'claim_id')::uuid,r->>'token');
    end $$;
    reset role;
    -- Efecto administrativo que realiza la Edge después de autorizar: perfil sintético.
    insert into auth.users(id) values(${q(perfil)});
    insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,asesor_perfil_id,domicilio,correo)
    values(${q(perfil)},'QA SUPERVISOR PROPIO','cliente','DNI','96160001',${q(actores.sup1)},'Calle QA 123','supervisor-propio@example.invalid');
    ${actor('sup1')}
    do $$ declare r jsonb;c jsonb;contrato uuid;begin
      r:=crm.convertir_lead(${q(lead)},${q(perfil)});
      assert (r->>'ok')::boolean,'No convirtió';
      r:=crm.convertir_lead(${q(lead)},${q(perfil)});
      assert (r->>'reintento')::boolean,'Reintento no idempotente';
      r:=crm.crear_contrato_con_cuenta_pdf_v2(${condiciones}||jsonb_build_object('cliente_id',${q(perfil)},'analista_cierre_id',${q(actores.sup1)},'numero_contrato','QA-SUP-9616'),
        jsonb_build_array(jsonb_build_object('numero_cuota',1,'fecha_programada',(current_date+interval '1 month')::date,'monto_programado',250,'tipo','cuota'),jsonb_build_object('numero_cuota',2,'fecha_programada',(current_date+interval '1 year')::date,'monto_programado',20000,'tipo','retorno')),
        jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','QA96160001','cci','00200000961600000001','titular_distinto',false));
      contrato:=(r->>'id')::uuid;
      assert contrato is not null,'No creó contrato';
      c:=crm.cartera_inversionistas_filtrada_fn(p_texto=>'96160001');
      assert (c->>'total')::int=1,'Cliente Avance no aparece en Cartera';
      assert c->'filas'->0->>'responsable_id'=${q(actores.sup1)},'Cartera cambió responsable';
    end $$;
    reset role;
    -- Verificación de persistencia como administrador; el comercial consulta por RPC.
    do $$ begin
      assert (select asesor_perfil_id=${q(actores.sup1)} from public.perfiles where id=${q(perfil)}),'Cliente perdió responsable';
      assert (select analista_cierre_id=${q(actores.sup1)} from public.contratos where cliente_id=${q(perfil)} and numero_contrato='QA-SUP-9616'),'Contrato perdió atribución';
    end $$;${verificarRanking}`);
});
