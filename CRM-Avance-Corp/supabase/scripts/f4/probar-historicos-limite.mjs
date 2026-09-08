import { entorno } from './banco-local.mjs';
// Lote máximo: 100 cierres distintos o 96 cierres y cuatro contratos anteriores.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { sql as sqlOriginal, leer, literal as q } from './banco-local.mjs';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { cargarHistoricosPrueba } from './cargar-historicos-prueba.mjs';

const tablas=['public.contratos','public.cronograma_pagos','public.perfiles','crm.cierres_externos','crm.leads',
  'crm.inversionistas','crm.inversionista_identificadores','crm.backfill_multiempresa_mapa',
  'crm.inversiones','crm.inversion_titulares','crm.inversion_backfill_lotes','private.contrato_pdfs'];
const foto=`select jsonb_object_agg(tabla,huella) from (${tablas.map(t=>`select ${q(t)} tabla,
  private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')) huella from ${t} t`).join(' union all ')}) x`;
const sinVinculo=process.argv.includes('--sin-vinculo'),mixto=process.argv.includes('--mixto');
const nCierres=mixto?96:100;
const antes=sqlOriginal(foto),copia=crearCopiaSql('historicos_limite');
const {sql}=copia;
assert.equal(sql(foto),antes);
assert.equal(cargarHistoricosPrueba(sql).instalado,true);
const f=leer('fixtures.json'),prefijo=`F4-MAX-${copia.id.toUpperCase()}-`;
const fuentesSql=`select 'cierre' tipo,id from crm.cierres_externos where numero_transaccion like ${q(prefijo+'%')}
  ${mixto?`union all select 'contrato',id from public.contratos where numero_contrato like 'F4-BASE-%'`:''}`;
let resultado;
try {
  sql(`begin;
    set local statement_timeout='30s';
    set local request.jwt.claims=${q(JSON.stringify({sub:f.usuarios.gerencia.id,role:'authenticated'}))};
    do $fixture$ declare n integer; lead uuid; doc text; v_telefono text; r jsonb;
    begin
      if private.inversiones_escritura_bajo_candado() then raise exception 'La fixture exige F4 apagada'; end if;
      for n in 1..${nCierres} loop
        loop
          doc:='97'||lpad(trunc(random()*1000000)::text,6,'0');
          exit when not exists(select 1 from crm.inversionista_identificadores where documento_normalizado=doc);
        end loop;
        loop
          v_telefono:='988'||lpad(trunc(random()*1000000)::text,6,'0');
          exit when not exists(select 1 from crm.leads l where l.telefono=v_telefono);
        end loop;
        lead:=gen_random_uuid();
        insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
          values(lead,'PERSONA FICTICIA LOTE MAXIMO '||n,v_telefono,100,'propuesta_enviada',
            ${q(f.usuarios.vendedor.id)},${q(f.usuarios.vendedor.id)},'otro');
        r:=crm.convertir_lead_externo(p_lead_id=>lead,p_cooperativa=>case when n%2=0 then 'qorilazo' else 'prodelco' end,
          p_monto=>100,p_moneda=>'PEN',p_documento_tipo=>'DNI',p_documento=>doc,
          p_nombre=>'PERSONA FICTICIA LOTE MAXIMO '||n,p_numero_transaccion=>${q(prefijo)}||n,
          p_referencia=>'REFERENCIA FICTICIA LOTE MAXIMO',p_vence_en=>current_date+365,p_nota=>'Ensayo SQL aislado');
      end loop;
    end; $fixture$;
    commit;`);
  if(sinVinculo) sql(`begin;set local crm.op_privilegiada='on';
    update crm.cierres_externos set inversionista_id=null where numero_transaccion like ${q(prefijo+'%')};commit;`);
  const economia=()=>sql(`select private.idem_hash(jsonb_agg(to_jsonb(ce)-'inversionista_id' order by id)) from crm.cierres_externos ce`);
  const economiaAntes=economia();
  const fotoSemilla=JSON.parse(sql(foto));
  resultado=JSON.parse(sql(`begin;
    -- Presupuesto del llamador, no confundir lock_timeout con duración total.
    set local statement_timeout='4s';
    set local crm.op_privilegiada='off';
    create temp table _resultado_limite(datos jsonb);
    do $medir$ declare mapa jsonb; r jsonb; lote uuid:=gen_random_uuid(); t timestamptz;
      ms_censo numeric; ms_aplicacion numeric; ms_reintento numeric; n integer;
    begin
      t:=clock_timestamp();
      select jsonb_agg(private.inversion_historica_estado(tipo,id) order by tipo,id) into mapa from (${fuentesSql}) fuentes;
      ms_censo:=extract(epoch from clock_timestamp()-t)*1000;
      if jsonb_array_length(mapa)<>100 or exists(select 1 from jsonb_array_elements(mapa) x where x->>'estado'<>'pendiente') then
        raise exception 'Se exigen cien fuentes pendientes'; end if;
      select count(distinct x->>'persona') into n from jsonb_array_elements(mapa) x;
      if n<${nCierres} then raise exception 'Se exigen identidades distintas en cada conversión cooperativa'; end if;
      t:=clock_timestamp();r:=private.inversion_historica_aplicar(lote,mapa);
      ms_aplicacion:=extract(epoch from clock_timestamp()-t)*1000;
      if current_setting('crm.op_privilegiada')<>'off' then raise exception 'Quedó privilegio temporal'; end if;
      if jsonb_array_length(r->'fuentes')<>100 then raise exception 'Resultado parcial'; end if;
      if exists(select 1 from (${fuentesSql}) fuentes where private.inversion_historica_estado(tipo,id)->>'estado'<>'resuelto') then raise exception 'Fuente sin resolver'; end if;
      t:=clock_timestamp();
      if private.inversion_historica_aplicar(lote,mapa)<>r then raise exception 'Reintento distinto'; end if;
      ms_reintento:=extract(epoch from clock_timestamp()-t)*1000;
      insert into _resultado_limite values(jsonb_build_object('fuentes',100,'personas',n,'msCenso',ms_censo,
        'msAplicacion',ms_aplicacion,'msReintento',ms_reintento,'presupuestoSentenciaMs',4000,'fuentesSinPersona',${sinVinculo ? nCierres : 0},'contratos',${mixto?4:0},'privilegioRestituido',true));
    end; $medir$;
    select datos from _resultado_limite;
    commit;`));
  const despues=JSON.parse(sql(foto));
  for(const [tabla,huella] of Object.entries(fotoSemilla)){
    if(['crm.inversiones','crm.inversion_titulares','crm.inversion_backfill_lotes'].includes(tabla))continue;
    if(sinVinculo && tabla==='crm.cierres_externos')continue;
    assert.equal(despues[tabla],huella,`El lote cambió ${tabla}`);
  }
  if(mixto) assert.equal(sql(`select count(*) from crm.inversion_titulares t join crm.inversiones i on i.id=t.inversion_id
    join public.contratos c on c.id=i.contrato_id where c.numero_contrato like 'F4-BASE-%' and t.rol='principal'`),'4');
  assert.equal(economia(),economiaAntes,'Los campos económicos de cierres no cambian');
  assert.equal(sql(`select count(*) from crm.inversiones i join crm.cierres_externos ce on ce.id=i.cierre_externo_id where ce.numero_transaccion like ${q(prefijo+'%')}`),String(nCierres));
  assert.equal(sql(`select count(*) from crm.inversion_titulares t join crm.inversiones i on i.id=t.inversion_id join crm.cierres_externos ce on ce.id=i.cierre_externo_id
    where ce.numero_transaccion like ${q(prefijo+'%')} and t.rol='principal'`),String(nCierres));
} finally {assert.equal(sqlOriginal(foto),antes,'El banco original debe permanecer intacto');}
writeFileSync(new URL(`../evidencia-f4/historicos-limite-${copia.id}.json`,import.meta.url),JSON.stringify({
  entorno,baseCopia:copia.nombre,ejecucion:copia.id,terminadoEn:new Date().toISOString(),resultado,
  md5Funcion:sql("select md5(pg_get_functiondef('private.inversion_historica_aplicar(uuid,jsonb)'::regprocedure))"),
  sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
  bancoOriginalSinCambios:true,creacionPorRpcReal:true,
  limite:'Medición en copia SQL sintética local; no garantiza tiempo productivo ni sustituye el ensayo del corpus F2 histórico y del entorno final.',
},null,2)+'\n',{flag:'wx'});
console.log(`PASS: 100 fuentes/${resultado.personas} personas; ${mixto?'4 contratos y 96 cierres':'100 cierres'} (${sinVinculo?'sin vínculo previo':'con vínculo previo'}); aplicar ${resultado.msAplicacion} ms, reintentar ${resultado.msReintento} ms; banco original intacto.`);
