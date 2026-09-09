import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID, createHash} from 'node:crypto';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {apiUrl, banco, como, leer, guardar, literal as q, rpc, sql, http} from './banco-local.mjs';
import {contratoPrueba} from '../f4/operaciones-fixture.mjs';
import {pdfEnBanco, pedirPdf, descargarFirmado} from './pdf-fixture.mjs';
import {crearHandlerDocumentoInversion} from '../../../../_supabase_functions/functions/crm-inversion-documento/handler.mjs';

test('G5: PDF vigente pendiente, recuperación, descarga F5 e inversión única', async t => {
  const e=leer('evidencia-flujo.json'), f=leer('fixtures.json');
  const persona=sql(`select private.inversionista_canonica(${q(e.persona)})`);
  const token=await como('vendedor'), ajeno=await como('ajeno');
  const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
  const inicio=JSON.parse(readFileSync(`${banco}/start.log`,'utf8'));
  const documento=crearHandlerDocumentoInversion({supabaseUrl:apiUrl,anonKey:inicio.ANON_KEY,serviceKey:inicio.SERVICE_ROLE_KEY});
  const ok=r=>{assert.equal(r.ok,true,JSON.stringify(r.data));return r.data;};
  const archivos=[];
  const bucket=await http('/storage/v1/bucket/contratos-generados',{method:'GET',admin:true});
  if(!bucket.ok) {
    assert.equal(Number(bucket.data?.statusCode ?? bucket.status),404);
    ok(await http('/storage/v1/bucket',{admin:true,body:{id:'contratos-generados',name:'contratos-generados',public:false,
      file_size_limit:10*1024*1024,allowed_mime_types:['application/pdf']}}));
  }
  assert.equal(sql("select public from storage.buckets where id='contratos-generados'"),'f');
  try {
    sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral')");
    for(const moneda of ['PEN','USD']) await t.test(`${moneda}: fallo de render → recuperar PDF con los mismos IDs y bytes`,async()=>{
      const clave=randomUUID();
      const datos={inversionista_id:persona,empresa:'avance',...contratoPrueba(e.perfil,f.usuarios.vendedor.id,{moneda,inicio:'2026-09-01',capital:1500})};
      datos.contrato.titulares=[{nombre_completo:'COTITULAR FICTICIO F5',tipo_documento:'DNI',documento:'92000002'}];
      ok(await rpc('preparar_inversion_fn',{p_clave:clave,p_datos:datos},token));
      const confirmado=ok(await rpc('confirmar_inversion_revisada_fn',{p_solicitud:clave,p_revision_datos_esperada:0},token));
      const id=confirmado.fuente.id;
      const estado=()=>JSON.parse(sql(`select jsonb_build_object('id',id,'estado',estado,'intentos',intentos,'ruta',storage_path,
        'snapshot_sha',encode(extensions.digest(snapshot::text,'sha256'),'hex')) from private.contrato_pdf_jobs where contrato_id=${q(id)}`));
      const antes=estado();assert.equal(antes.estado,'pendiente');assert.equal(antes.intentos,0);
      const fallido=await pedirPdf(pdfEnBanco(async(nombre,ejecutar)=>{
        if(nombre==='renderizar') throw new Error('Fallo sintético transitorio de render F5');
        return ejecutar();
      }),token,id);
      assert.equal(fallido.status,503);assert.equal(estado().estado,'error_reintentable');
      const normal=pdfEnBanco(), recuperado=ok(await pedirPdf(normal,token,id));
      assert.equal(recuperado.pdf.estado,'sellado');
      const bytes=await descargarFirmado(recuperado.url), sha=createHash('sha256').update(bytes).digest('hex');
      assert.equal(recuperado.pdf.sha256,sha);assert.equal(recuperado.pdf.bytes,bytes.length);
      for(const accion of ['ensure','status']) {
        const repetida=ok(await pedirPdf(normal,token,id,accion));
        assert.equal(repetida.pdf.job_id,recuperado.pdf.job_id);
        assert.equal(repetida.pdf.sha256,sha);assert.deepEqual(await descargarFirmado(repetida.url),bytes);
      }
      const final=estado();assert.equal(final.id,antes.id);assert.equal(final.snapshot_sha,antes.snapshot_sha);assert.equal(final.intentos,2);
      assert.equal(sql(`select count(*) from private.contrato_pdfs where contrato_id=${q(id)}`),'1');
      assert.equal(sql(`select count(*) from storage.objects where bucket_id='contratos-generados' and name=${q(final.ruta)}`),'1');
      assert.equal(sql(`select count(*) from crm.inversiones where contrato_id=${q(id)}`),'1');
      const otra=ok(await rpc('confirmar_inversion_revisada_fn',{p_solicitud:clave,p_revision_datos_esperada:0},token));
      assert.equal(otra.inversion_id,confirmado.inversion_id);assert.equal(otra.fuente.id,id);
      const ficha=ok(await rpc('inversionista_ficha_fn',{p_inversionista:persona},token));
      const fuente=ficha.inversiones.find(x=>x.fuente_id===id);
      assert.equal(fuente.cotitulares[0].nombre,'COTITULAR FICTICIO F5');
      assert.equal(fuente.pdf.estado,'sellado');assert.equal(fuente.documentos.length,1);
      const pedir=actor=>documento(new Request(`${apiUrl}/functions/v1/crm-inversion-documento`,{method:'POST',
        headers:{Authorization:`Bearer ${actor}`},body:JSON.stringify({inversionista_id:persona,fuente_id:id,documento_id:fuente.documentos[0].id})}));
      const descargado=await pedir(token);assert.equal(descargado.status,200);
      assert.deepEqual(Buffer.from(await descargado.arrayBuffer()),bytes);
      assert.equal((await pedir(ajeno)).status,403);
      mkdirSync(`${banco}/pdf-f5`,{recursive:true});
      const archivo=`${banco}/pdf-f5/contrato-ficticio-${moneda}.pdf`;
      writeFileSync(archivo,bytes,{mode:0o600});
      archivos.push({moneda,archivo,bytes:bytes.length,sha256:sha,contrato:id});
    });
    guardar('evidencia-pdf.json',{estado:'PASS',runtime:'handler y renderer publicados sin modificar en Node; Auth, PostgREST y Storage reales del banco local',archivos});
  } finally {for(const[nombre,activo]of Object.entries(flags)) sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);}
});
