// Recorrido con navegador, Auth y API reales. No MSW, JWT inyectado ni sesión demo.
// El navegador integrado no estuvo disponible: fallback explícito a Playwright.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { carpeta, apiUrl, sql, credencialesLocales } from './banco.mjs';
import { USER_BY_KEY } from '../../fixtures.mjs';

const args=process.argv.slice(2);
const registrar=args.includes('--registrar-seguimiento');
assert.deepEqual(args,registrar?['--solo-banco-autorizado','--registrar-seguimiento']:['--solo-banco-autorizado']);
const instalada=sql("select to_regclass('crm.politica_gestion_diaria') is not null")==='t';
if(instalada) assert.equal(sql('select count(*)=1 and bool_and(version=1 and not cortes_activos) from crm.politica_gestion_diaria'),'t');
const c=credencialesLocales();
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`,'utf8'));
const app=fileURLToPath(new URL('../../../../app/',import.meta.url));
const requireApp=createRequire(`${app}package.json`);
const {createServer}=await import(pathToFileURL(requireApp.resolve('vite')).href);
const {chromium,expect}=requireApp('@playwright/test');
for(const key of Object.keys(process.env)) if(key.startsWith('VITE_')) delete process.env[key];
Object.assign(process.env,{VITE_ENABLE_DEMO:'false',VITE_SUPABASE_URL:apiUrl,VITE_SUPABASE_ANON_KEY:c.ANON_KEY,
  CRM_BUILD_ID:'gestion-diaria-f4-http-local'});
const origen='http://127.0.0.1:59323';
const servidor=await createServer({root:app,configFile:`${app}vite.config.ts`,envDir:false,logLevel:'warn',
  server:{host:'127.0.0.1',port:59323,strictPort:true,open:false}});
let browser;
const evidencias=[];
const modoSla=sql('select modo from crm.sla_operacion_control where id');
const etiqueta=(instalada?'candidato':'revertido')+(modoSla==='activo'?'-sla-activo':'')+(registrar?'-seguimiento':'');
try {
  await servidor.listen();
  browser=await chromium.launch({headless:true});
  for(const key of ['sup1','sup2','vend1']) {
    const context=await browser.newContext({viewport:{width:1440,height:1000},locale:'es-PE',timezoneId:'America/Lima',serviceWorkers:'block'});
    const externos=new Set();
    let falloEquipo=false;
    await context.route('**/*',route=>{
      const u=new URL(route.request().url());
      if(![origen,apiUrl].includes(u.origin)) {externos.add(u.origin);return route.abort('blockedbyclient');}
      // Fallo de transporte deliberado: no se fabrica una respuesta de negocio.
      if(falloEquipo&&u.pathname==='/rest/v1/rpc/gestion_diaria_equipo_fn') return route.abort('connectionfailed');
      return route.continue();
    });
    const page=await context.newPage();
    page.setDefaultTimeout(20_000);
    await page.goto(origen);
    await expect(page.getByRole('button',{name:'Explorar en modo demo'})).toHaveCount(0);
    await page.getByLabel('Correo',{exact:true}).fill(USER_BY_KEY[key].email);
    await page.getByLabel('Contraseña',{exact:true}).fill(password);
    const login=page.waitForResponse(r=>r.url().startsWith(`${apiUrl}/auth/v1/token?`));
    await page.getByRole('button',{name:'Entrar',exact:true}).click();
    assert.equal((await login).status(),200,'El formulario debe iniciar una sesión real');
    const tipo=key==='vend1'?'analista':'equipo';
    const lectura=page.waitForResponse(r=>r.url()===`${apiUrl}/rest/v1/rpc/gestion_diaria_${tipo}_fn`&&r.request().method()==='POST');
    await page.getByRole('button',{name:'Gestión Diaria',exact:true}).click();
    const respuesta=await lectura;
    assert.equal(respuesta.status(),200);
    const dato=await respuesta.json();
    assert.equal('politica_version' in dato.umbrales,instalada);
    if(tipo==='equipo') {
      assert.equal('cortes' in dato,instalada);
      if(instalada) assert.equal(dato.cortes.estado,'desactivados');
      const vista=page.getByRole('region',{name:'Mi equipo hoy',exact:true});
      await expect(vista.getByRole('table')).toBeVisible();
      assert.ok(dato.equipo.length>=2);
      await expect(vista.locator('tr[data-analista]')).toHaveCount(dato.equipo.length);
      for(const fila of dato.equipo) await expect(vista.getByText(fila.nombre_completo,{exact:true})).toBeVisible();
      const propio=key==='sup1'?'ANALISTA UNO':'ANALISTA TRES';
      const ajeno=key==='sup1'?'ANALISTA TRES':'ANALISTA UNO';
      await expect(vista.getByText(ajeno,{exact:true})).toHaveCount(0);
      await vista.getByRole('searchbox').fill(propio);
      await expect(vista.locator('tr[data-analista]')).toHaveCount(1);
      await vista.locator('details summary').click();
      await expect(vista.getByText('Llamadas por lead',{exact:true})).toBeVisible();
      const registro=page.waitForResponse(r=>r.url()===`${apiUrl}/rest/v1/rpc/registro_actividad_fn`&&r.request().method()==='POST');
      await vista.getByRole('button',{name:`Ver llamadas del día de ${propio}`,exact:true}).click();
      assert.equal((await registro).status(),200);
      const panel=page.getByRole('region',{name:'Registro seleccionado',exact:true});
      await expect(panel.getByRole('heading',{name:`Registro de ${propio}`,exact:true})).toBeVisible();
      await expect(panel.getByRole('tab',{name:'Llamadas',exact:true})).toHaveAttribute('aria-selected','true');
      await page.screenshot({path:`${carpeta}/ui-${etiqueta}-${key}.png`,fullPage:true});
      await page.getByRole('button',{name:'Cerrar registro',exact:true}).click();
      if(key==='sup1') {
        falloEquipo=true;
        await vista.getByRole('button',{name:'Actualizar',exact:true}).click();
        await expect(vista.getByRole('alert')).toContainText('no significa que el equipo no tenga actividad');
        await expect(vista.getByRole('table')).toHaveCount(0);
        falloEquipo=false;
        await vista.getByRole('button',{name:'Reintentar',exact:true}).click();
        await expect(vista.getByRole('table')).toBeVisible();
        await page.setViewportSize({width:390,height:844});
        await page.getByRole('button',{name:'Ocultar menú',exact:true}).click();
        await vista.getByRole('heading',{level:2}).scrollIntoViewIfNeeded();
        assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),'Sin desbordamiento móvil');
        await page.screenshot({path:`${carpeta}/ui-${etiqueta}-movil.png`,fullPage:true});
      }
      evidencias.push({actor:key,login:200,rpc:200,roster:dato.equipo.length,llamadas:dato.equipo.reduce((n,f)=>n+f.marcador.llamadas,0),detalle:true,registro:true});
    } else {
      await expect(page.getByRole('heading',{name:'¿A quién llamo ahora?',exact:true})).toBeVisible();
      await page.getByRole('button',{name:/^Mi actividad/}).click();
      await expect(page.getByRole('list',{name:'Marcador de hoy',exact:true})).toBeVisible();
      await expect(page.getByRole('region',{name:'Mi equipo hoy',exact:true})).toHaveCount(0);
      if(registrar) {
        const titulo=`SEGUIMIENTO HTTP F43 ${Date.now()}`;
        const ahora=page.getByRole('region',{name:'Ahora',exact:true});
        await ahora.getByRole('button',{name:/^Más acciones para /}).click();
        await page.getByRole('menuitem',{name:'Registrar resultado',exact:true}).click();
        const dialogo=page.getByRole('dialog',{name:/Cómo salió la llamada/});
        await expect(dialogo.locator('input[name="resultado-llamada"]')).toHaveCount(7);
        await dialogo.getByRole('radio',{name:/no le interesa/}).check();
        await expect(dialogo.locator('input[name="resultado-llamada"]')).toHaveCount(1);
        await dialogo.getByLabel(/¿Por qué no le interesa/).selectOption('sin_fondos_ahora');
        await dialogo.getByRole('checkbox',{name:/Agendar próxima acción/}).check();
        await dialogo.getByLabel('Tipo de próxima acción').selectOption('whatsapp');
        await dialogo.getByLabel('Título',{exact:true}).fill(titulo);
        await dialogo.getByLabel('Nota de la llamada',{exact:true}).fill(titulo);
        await expect(dialogo.getByRole('checkbox',{name:/Descartar y enviar/})).not.toBeChecked();
        const guardado=page.waitForResponse(r=>r.url()===`${apiUrl}/rest/v1/rpc/registrar_llamada_v4`&&r.request().method()==='POST');
        await dialogo.getByRole('button',{name:'Guardar',exact:true}).click();
        const confirmacion=await guardado;
        assert.equal(confirmacion.status(),200,'La escritura debe confirmarse por API real');
        const pedido=confirmacion.request().postDataJSON();
        assert.equal(pedido.p_resultado,'no_interesado');
        assert.equal(pedido.p_descartar,false);
        assert.match(pedido.p_lead_id,/^[a-f0-9-]{36}$/i);
        assert.match(dato.analista_id,/^[a-f0-9-]{36}$/i);
        await expect(dialogo).toHaveCount(0);
        assert.equal(sql(`select count(*) from crm.actividades where lead_id='${pedido.p_lead_id}'
          and creado_por='${dato.analista_id}' and detalle='${titulo}' and metadata->>'resultado'='no_interesado'`),'1');
        assert.equal(sql(`select count(*) from crm.tareas where lead_id='${pedido.p_lead_id}'
          and titulo='${titulo}' and tipo='whatsapp' and estado='pendiente' and vence_en>now()`),'1');
        assert.equal(sql(`select count(*) from crm.leads where id='${pedido.p_lead_id}'
          and vendedor_id='${dato.analista_id}' and activo and etapa not in ('descartado','convertido') and motivo_descarte is null`),'1');
        evidencias.push({recorrido:'resultado-contraído → no_interesado → seguimiento WhatsApp',http:200,
          actividadPersistida:1,tareaPersistida:1,conservaLead:true});
      }
      await page.screenshot({path:`${carpeta}/ui-${etiqueta}-${key}.png`,fullPage:true});
      evidencias.push({actor:key,login:200,rpc:200,llamadas:dato.marcador.llamadas,cartera:dato.cartera.length,miActividad:true});
    }
    assert.equal(externos.size,0,`Orígenes inesperados bloqueados: ${[...externos].join(', ')}`);
    await context.close();
    console.log(`PASS navegador real: ${key}, ${etiqueta}`);
  }
  writeFileSync(`${carpeta}/navegador-${etiqueta}.json`,JSON.stringify({estado:'PASS',api:apiUrl,interfaz:origen,
    cortesInstalados:instalada,cortesActivos:false,modoSla,registrar,evidencias},null,2)+'\n',{mode:0o600});
} catch(error) {
  let seguro=String(error?.stack??error);
  for(const secreto of [password,c.ANON_KEY,c.SERVICE_ROLE_KEY,c.DB_URL]) seguro=seguro.replaceAll(secreto,'[REDACTADO]');
  seguro=seguro.replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,'[JWT_REDACTADO]');
  writeFileSync(`${carpeta}/navegador-${etiqueta}.json`,JSON.stringify({estado:'FAIL',modoSla,registrar,evidencias,error:seguro},null,2)+'\n',{mode:0o600});
  console.error(seguro);
  process.exitCode=1;
} finally {
  if(browser) await browser.close();
  await servidor.close();
}
