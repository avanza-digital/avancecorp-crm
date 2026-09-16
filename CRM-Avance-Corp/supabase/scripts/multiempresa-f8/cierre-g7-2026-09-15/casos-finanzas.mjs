// Ensayo financiero SQL autenticado. Todo se revierte, incluso el mes sellado.
import assert from 'node:assert/strict';
import {randomUUID,randomInt,createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {sql,objeto,q,j,db} from './banco-http.mjs';
import {contratoPrueba} from '../../f4/operaciones-fixture.mjs';
const inicio=new Date().toISOString(),archivo=new URL('casos-finanzas.json',import.meta.url);
writeFileSync(archivo,JSON.stringify({estado:'RUNNING',inicio,banco:db})+'\n');
const cliente=randomUUID(),documento=String(randomInt(87000000,87999999));
const plantilla=(categoria,inicio,capital)=>contratoPrueba(cliente,null,{categoria,inicio,capital});
const base=plantilla('nuevo','2025-07-01',1000),upgrade=plantilla('upgrade','2025-08-01',700),renovacion=plantilla('renovacion','2026-08-01',800);
const huella=()=>sql(`select md5(jsonb_build_object('contratos',(select jsonb_agg(to_jsonb(c) order by id) from public.contratos c),
  'personas',(select jsonb_agg(to_jsonb(c) order by id) from crm.inversionistas c),
  'cierres',(select jsonb_agg(to_jsonb(c) order by id) from crm.cierres_externos c),
  'periodos',(select jsonb_agg(to_jsonb(c) order by periodo) from crm.periodos_cerrados c),
  'fotos',(select jsonb_agg(to_jsonb(c) order by periodo,vendedor_id) from crm.cierre_mes_vendedor c),
  'flags',(select jsonb_agg(to_jsonb(c) order by nombre) from crm.multiempresa_flags c),
  'perfiles',(select jsonb_agg(to_jsonb(c) order by id) from public.perfiles c),
  'inversiones',(select jsonb_agg(to_jsonb(c) order by id) from crm.inversiones c),
  'solicitudes',(select jsonb_agg(to_jsonb(c) order by id) from crm.inversion_solicitudes c),
  'ajustes',(select jsonb_agg(to_jsonb(c) order by inversion_id) from crm.inversion_ajustes_mes_cerrado c),
  'objetos',(select jsonb_agg(to_jsonb(c) order by id) from storage.objects c),
  'usuarios',(select jsonb_agg(to_jsonb(c) order by id) from auth.users c))::text)`);
let antes,resultados,exito=false;
try {
  antes=huella();
  resultados=objeto(`begin;set local lock_timeout='2s';set local statement_timeout='45s';
    do $pruebas$
    declare g uuid;v uuid;ajeno uuid;persona uuid;origen uuid;cabeza uuid;hija uuid;s uuid;
      datos jsonb;res jsonb;autor uuid;foto text;filas integer;valor numeric;relacion uuid;ajustes integer;inversion uuid;
      pruebas jsonb:='[]';hoy date:=(now() at time zone 'America/Lima')::date;
    begin
      if current_database()<>'g7_cierre_20260915' then raise exception 'Banco incorrecto';end if;
      if exists(select 1 from crm.periodos_cerrados where periodo>='2026-08-01') then
        raise exception 'El ensayo necesita agosto abierto; no se reescribe un sello';end if;
      select perfil_id into strict g from crm.equipo where rol_crm='gerencia' and activo;
      select perfil_id into strict v from crm.equipo where rol_crm='vendedor' and activo order by perfil_id limit 1;
      select perfil_id into strict ajeno from crm.equipo where rol_crm='vendedor' and activo and perfil_id<>v;
      if ajeno is null or ajeno=v then raise exception 'Se requieren dos analistas distintos';end if;
      update crm.multiempresa_flags set activo=(nombre in('resolver_en_puertas','inversiones_escritura','ficha_360_neutral','postventa_neutral'));
      insert into auth.users(id) values(${q(cliente)});
      insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,activo,asesor_perfil_id,domicilio,correo)
        values(${q(cliente)},'CLIENTE SINTETICO G7 FINANZAS','cliente','DNI',${q(documento)},true,v,
          'CALLE FICTICIA 123, LIMA',${q('g7.finanzas.'+cliente+'@pruebas.example')});
      perform set_config('request.jwt.claim.sub',g::text,true);
      perform set_config('request.jwt.claims',jsonb_build_object('sub',g,'role','authenticated')::text,true);
      datos:=${j(base.contrato)}||jsonb_build_object('analista_cierre_id',v);
      set local role authenticated;
      res:=crm.crear_contrato_con_cuenta_pdf_v2(datos,${j(base.cronograma)},${j(base.cuenta)});
      reset role;origen:=(res->>'id')::uuid;
      select id into strict persona from crm.inversionistas where perfil_id=${q(cliente)} and estado='activo';
      s:=gen_random_uuid();datos:=jsonb_build_object('inversionista_id',persona,'empresa','avance',
        'contrato',${j(upgrade.contrato)}||jsonb_build_object('analista_cierre_id',v,'contrato_origen_id',origen),
        'cronograma',${j(upgrade.cronograma)},'cuenta',${j(upgrade.cuenta)});
      set local role authenticated;
      perform crm.preparar_inversion_fn(s,datos);res:=crm.confirmar_inversion_revisada_fn(s,0);
      reset role;cabeza:=(res#>>'{fuente,id}')::uuid;
      s:=gen_random_uuid();datos:=jsonb_build_object('inversionista_id',persona,'empresa','avance',
        'contrato',${j(renovacion.contrato)}||jsonb_build_object('analista_cierre_id',v,'contrato_origen_id',cabeza,'capital_renovado',700,'capital_adicional',100),
        'cronograma',${j(renovacion.cronograma)},'cuenta',${j(renovacion.cuenta)});
      set local role authenticated;
      perform crm.preparar_inversion_fn(s,datos);res:=crm.confirmar_inversion_revisada_fn(s,0);
      reset role;hija:=(res#>>'{fuente,id}')::uuid;
      if (select estado from public.contratos where id=cabeza)<>'renovado' then raise exception 'Cabeza no renovada';end if;
      select monto into strict valor from private.capital_episodios('-infinity','infinity',true,'{}') where contrato_id=hija and medida='stock';
      if valor<>800 then raise exception 'Stock duplicado o incorrecto';end if;
      select monto into strict valor from private.capital_episodios('-infinity','infinity',true,'{}') where contrato_id=hija and tipo='desglose_renovado';
      if valor<>700 then raise exception 'Capital renovado incorrecto';end if;
      select monto into strict valor from private.capital_episodios('-infinity','infinity',true,'{}') where contrato_id=hija and tipo='desglose_adicional';
      if valor<>100 then raise exception 'Capital adicional incorrecto';end if;
      pruebas:=pruebas||jsonb_build_array(jsonb_build_object('caso','Renovación de línea upgrade: 800 de stock, 700 renovados y 100 adicionales','estado','PASS'));
      set local role authenticated;res:=crm.cerrar_periodo('2026-08-01');reset role;
      select count(*) into filas from crm.cierre_mes_vendedor where periodo='2026-08-01';
      if filas<1 then raise exception 'Sello sin fotografías: evidencia insuficiente';end if;
      select md5(jsonb_build_object('mes',(select to_jsonb(p) from crm.periodos_cerrados p where periodo='2026-08-01'),
        'fotos',(select jsonb_agg(to_jsonb(f) order by vendedor_id) from crm.cierre_mes_vendedor f where periodo='2026-08-01'))::text) into foto;
      select creado_por into autor from public.contratos where id=cabeza;
      set local role authenticated;perform public.reasignar_analista_contrato(cabeza,ajeno,'Reasignación sintética de la cabeza upgrade G7');reset role;
      select analista_id into strict relacion from private.capital_episodios('-infinity','infinity',true,'{}') where contrato_id=hija and medida='stock';
      if relacion is distinct from ajeno then raise exception 'No se trasladó atribución de renovación';end if;
      if (select creado_por from public.contratos where id=cabeza) is distinct from autor then raise exception 'Autor histórico reescrito';end if;
      pruebas:=pruebas||jsonb_build_array(jsonb_build_object('caso','Reasignar cabeza upgrade mueve atribución viva de su renovación y conserva autor','estado','PASS'));
      s:=gen_random_uuid();datos:=jsonb_build_object('inversionista_id',persona,'empresa','qorilazo','monto',425,'moneda','PEN',
        'fecha_comercial','2026-08-15','vence_en',private.coopac_validar_condiciones('2026-08-15',12,12),'plazo_meses',12,'tasa_anual',12,
        'numero_transaccion','G7-SELLO-'||s,'referencia','ENSAYO SINTETICO',
        'evidencia',jsonb_build_object('ruta',persona||'/'||s||'/comprobante.png'));
      set local role authenticated;perform crm.preparar_inversion_fn(s,datos);reset role;
      insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',datos#>>'{evidencia,ruta}','{"size":12,"mimetype":"image/png"}');
      set local role authenticated;res:=crm.confirmar_inversion_revisada_fn(s,0);reset role;
      if res#>>'{fuente,fecha_comercial}'<>'2026-08-15' or (res#>>'{fuente,fecha_imputacion}')::date<>hoy
        or (res#>>'{fuente,ajuste_mes_cerrado}')::boolean is distinct from true then raise exception 'Fecha/imputación incorrecta';end if;
      if (select count(*) from crm.inversion_ajustes_mes_cerrado where inversion_id=(res->>'inversion_id')::uuid)<>1 then raise exception 'Ajuste no único';end if;
      set local role authenticated;perform crm.confirmar_inversion_revisada_fn(s,0);reset role;
      inversion:=(res->>'inversion_id')::uuid;
      select count(*) into ajustes from crm.inversion_ajustes_mes_cerrado where inversion_id=inversion;
      if ajustes<>1 or (select count(*) from crm.inversiones where cierre_externo_id=(res#>>'{fuente,cierre_id}')::uuid)<>1 then
        raise exception 'El reintento duplicó inversión o ajuste';end if;
      if (select md5(jsonb_build_object('mes',(select to_jsonb(p) from crm.periodos_cerrados p where periodo='2026-08-01'),
        'fotos',(select jsonb_agg(to_jsonb(f) order by vendedor_id) from crm.cierre_mes_vendedor f where periodo='2026-08-01'))::text)) is distinct from foto then
          raise exception 'La reasignación o inversión posterior reescribió el sello';end if;
      pruebas:=pruebas||jsonb_build_array(jsonb_build_object('caso','Mes sellado no vacío conserva todas sus filas tras reasignar, invertir y reintentar',
        'estado','PASS','fotografias',filas,'ajustes_nuevos',ajustes));
      perform set_config('g7.finanzas',pruebas::text,true);
    end $pruebas$;
    select current_setting('g7.finanzas')::jsonb;
    rollback;`,{admin:true});
  assert.equal(huella(),antes);exito=true;
} finally {
  const sinCambios=antes!==undefined&&huella()===antes;
  writeFileSync(archivo,JSON.stringify({estado:exito&&sinCambios?'PASS':'FAIL',inicio,fin:new Date().toISOString(),banco:db,
    resultados:resultados??[],rollback_completo:sinCambios,
    sha256:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
    dependencias_sha256:Object.fromEntries(['banco-http.mjs','dependencias-local.sql','../../f4/operaciones-fixture.mjs'].map(f=>[f,
      createHash('sha256').update(readFileSync(new URL(f,import.meta.url))).digest('hex')])),
    limites:['SQL authenticated en copia sintética; no Auth/HTTP para este suplemento.',
      'Perfil Auth y metadatos Storage como fixtures explícitos; operaciones mediante RPC vigentes.',
      'No comisiones calculadas ni firma financiera; todo se revierte.']},null,2)+'\n');
  console.log(JSON.stringify({estado:exito&&sinCambios?'PASS':'FAIL',resultados,rollback_completo:sinCambios}));
}
