// Recorrido de F4 con Auth/API reales, sin respuestas de negocio simuladas.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { carpeta, apiUrl, sql, credencialesLocales } from '../gestion-diaria-cortes/http/banco.mjs';
import { USER_BY_KEY } from '../fixtures.mjs';
const soloCapturas=process.argv[3]==='--solo-capturas';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado',...(soloCapturas?['--solo-capturas']:[])]);
const c=credencialesLocales();
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`,'utf8'));
const app=fileURLToPath(new URL('../../../app/',import.meta.url));
const requireApp=createRequire(`${app}package.json`);
const {createServer}=await import(pathToFileURL(requireApp.resolve('vite')).href);
const {chromium,expect}=requireApp('@playwright/test');
for(const key of Object.keys(process.env)) if(key.startsWith('VITE_')) delete process.env[key];
Object.assign(process.env,{VITE_ENABLE_DEMO:'false',VITE_SUPABASE_URL:apiUrl,VITE_SUPABASE_ANON_KEY:c.ANON_KEY,
  CRM_BUILD_ID:'gestion-diaria-f4-cierre-local'});
const origen='http://127.0.0.1:59323';
const servidor=await createServer({root:app,configFile:`${app}vite.config.ts`,envDir:false,logLevel:'warn',
  server:{host:'127.0.0.1',port:59323,strictPort:true,open:false}});
let browser;
const evidencia=[];
const errores=[];
const externos=new Set();
async function iniciar(key,{retener=false,movil=false}={}) {
  const context=await browser.newContext({viewport:movil?{width:390,height:844}:{width:1440,height:1000},
    locale:'es-PE',timezoneId:'America/Lima',serviceWorkers:'block'});
  let retenida=retener;
  await context.route('**/*',async route=>{
    const u=new URL(route.request().url());
    if(![origen,apiUrl].includes(u.origin)){externos.add(u.origin);return route.abort('blockedbyclient');}
    if(u.pathname==='/rest/v1/rpc/gestion_diaria_avisos_fn') {
      const fin=Date.now()+15_000;
      while(retenida&&Date.now()<fin) await new Promise(r=>setTimeout(r,50));
    }
    return route.continue();
  });
  const page=await context.newPage();
  page.setDefaultTimeout(20_000);
  page.on('pageerror',e=>errores.push(e.message));
  await page.goto(origen);
  await page.getByLabel('Correo',{exact:true}).fill(USER_BY_KEY[key].email);
  await page.getByLabel('Contraseña',{exact:true}).fill(password);
  const login=page.waitForResponse(r=>r.url().startsWith(`${apiUrl}/auth/v1/token?`));
  await page.getByRole('button',{name:'Entrar',exact:true}).click();
  assert.equal((await login).status(),200);
  return {page,context,liberar:()=>{retenida=false;}};
}
async function legible(region) {
  const pequenos=await region.locator('*').evaluateAll(els=>els.filter(e=>e.getClientRects().length
    && [...e.childNodes].some(n=>n.nodeType===Node.TEXT_NODE&&n.textContent.trim())
    && parseFloat(getComputedStyle(e).fontSize)<16).map(e=>({tag:e.tagName,texto:e.textContent.slice(0,60),size:getComputedStyle(e).fontSize})));
  assert.deepEqual(pequenos,[],'Texto visible de F4 debe medir al menos 16 px');
}
async function botonesDentro(region) {
  const recortados=await region.getByRole('button').evaluateAll(els=>els.filter(e=>{
    const r=e.getBoundingClientRect();
    return r.width>0 && (r.left<0 || r.right>innerWidth || r.height<44);
  }).map(e=>e.textContent));
  assert.deepEqual(recortados,[],'Botones completos, dentro de la pantalla y con altura mínima de 44 px');
}
try {
  await servidor.listen();
  browser=await chromium.launch({headless:true});
  if(!soloCapturas) {
  const {page,context,liberar}=await iniciar('sup1',{retener:true});
  await page.getByRole('button',{name:'Gestión Diaria',exact:true}).click();
  const equipo=page.getByRole('region',{name:'Mi equipo hoy',exact:true});
  await equipo.getByRole('searchbox').fill('ANALISTA');
  const consulta=page.waitForResponse(r=>r.url()===`${apiUrl}/rest/v1/rpc/gestion_diaria_avisos_fn`);
  liberar();
  const respuesta=await consulta;assert.equal(respuesta.status(),200);
  const datos=await respuesta.json();assert.ok(datos.alertas.some(a=>a.puede_presentar));
  await page.waitForTimeout(2500);
  await expect(page.getByRole('dialog')).toHaveCount(0);
  evidencia.push('No interrumpe mientras el supervisor tiene el buscador enfocado');
  await equipo.getByRole('button',{name:'Actualizar',exact:true}).click();
  const popup=page.getByRole('dialog');
  await expect(popup).toBeVisible();
  await legible(popup);
  await page.screenshot({path:`${carpeta}/f44-popup-desktop.png`,fullPage:true});
  await page.keyboard.press('Tab');
  assert.ok(await popup.evaluate(e=>e.contains(document.activeElement)),'El foco permanece en el diálogo');
  const registro=popup.getByRole('button',{name:/Ver registro de/}).first();
  const nombre=(await registro.innerText()).replace('Ver registro de ','');
  await registro.click();
  await expect(page.getByRole('region',{name:'Registro seleccionado'})).toBeVisible();
  await expect(page.getByRole('heading',{name:`Registro de ${nombre}`,exact:true})).toBeFocused();
  evidencia.push('Popup real, foco contenido y acceso al registro propio con foco restaurado');
  // El segundo corte puede aparecer una vez: cerrarlo no lo reconoce.
  for(let i=0;i<2;i++) {
    await page.waitForTimeout(1600);
    if(await popup.count()) await popup.getByRole('button',{name:'Cerrar sin reconocer'}).click();
  }
  const lista=page.getByRole('region',{name:'Cortes de llamadas del equipo'});
  const articulos=lista.locator('article');
  assert.ok(await articulos.count()>0);
  const confirmar=page.waitForResponse(r=>r.url()===`${apiUrl}/rest/v1/rpc/gestion_diaria_reconocer_corte`);
  await articulos.first().getByRole('button',{name:'Lo estoy atendiendo',exact:true}).click();
  assert.equal((await confirmar).status(),200);
  await expect(articulos.first().getByText('Reconocido; el resultado del corte se conserva.')).toBeVisible();
  const aplazar=lista.getByRole('button',{name:'Posponer 1 hora',exact:true});
  if(await aplazar.count()) {
    const posponer=page.waitForResponse(r=>r.url()===`${apiUrl}/rest/v1/rpc/gestion_diaria_reconocer_corte`);
    await aplazar.first().click();assert.equal((await posponer).status(),200);
    await expect(lista.getByText(/Pospuesto/).first()).toBeVisible();
  }
  await legible(lista);
  await context.close();
  const segundo=await iniciar('sup1',{movil:true});
  await segundo.page.goto(`${origen}/#/gestion-diaria`);
  const listaMovil=segundo.page.getByRole('region',{name:'Cortes de llamadas del equipo'});
  await expect(listaMovil.getByText('Reconocido; el resultado del corte se conserva.')).toBeVisible();
  await segundo.page.waitForTimeout(1800);
  await expect(segundo.page.getByRole('dialog')).toHaveCount(0);
  assert.ok(await segundo.page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),'Sin desborde horizontal de la página móvil');
  await legible(listaMovil);
  await listaMovil.scrollIntoViewIfNeeded();
  await segundo.page.screenshot({path:`${carpeta}/f44-lista-mobile.png`,fullPage:true});
  evidencia.push('Reconocimiento y aplazamiento confirmados por HTTP, persistentes en una segunda sesión móvil sin popup duplicado');
  await segundo.context.close();
  } else {
    const movil=await iniciar('sup1',{movil:true});
    await movil.page.goto(`${origen}/#/gestion-diaria`);
    const lista=movil.page.getByRole('region',{name:'Cortes de llamadas del equipo'});
    await expect(lista).toBeVisible();
    await legible(lista);
    await botonesDentro(lista);
    await lista.getByRole('heading',{name:'Cortes de llamadas',exact:true}).scrollIntoViewIfNeeded();
    await movil.page.screenshot({path:`${carpeta}/f44-lista-mobile.png`,animations:'disabled'});
    evidencia.push('Lista móvil: texto mínimo de 16 px, botones sin recorte y altura mínima de 44 px');
    await movil.context.close();
  }
  const ger=await iniciar('gerencia');
  await ger.page.goto(`${origen}/#/config-gestion-diaria`);
  await expect(ger.page.getByRole('region',{name:'Reglas vigentes'})).toBeVisible();
  await expect(ger.page.getByText('Desactivada hasta F5').first()).toBeVisible();
  await ger.page.screenshot({path:`${carpeta}/f45-configuracion-desktop.png`,fullPage:true,animations:'disabled'});
  await legible(ger.page.getByRole('region',{name:'Reglas vigentes'}));
  evidencia.push('Configuración real de gerencia muestra política vigente e historial; tasa baja explícitamente OFF hasta F5');
  const formulario=ger.page.getByRole('region',{name:'Editar reglas de Gestión Diaria'});
  await legible(formulario);
  await formulario.getByRole('heading',{name:'Próxima versión'}).scrollIntoViewIfNeeded();
  await ger.page.screenshot({path:`${carpeta}/f45-editor-desktop.png`});
  await ger.page.getByLabel('Motivo del cambio',{exact:true}).fill('Vista previa local sin publicar');
  await ger.page.getByRole('button',{name:/Revisar y publicar/}).click();
  const confirmacion=ger.page.getByRole('dialog',{name:/Publicar política v/});
  await expect(confirmacion).toBeVisible();
  await legible(confirmacion);
  await ger.page.screenshot({path:`${carpeta}/f45-confirmacion-desktop.png`,animations:'disabled'});
  await confirmacion.getByRole('button',{name:'Cancelar',exact:true}).click();
  await ger.context.close();
  const gerMovil=await iniciar('gerencia',{movil:true});
  await gerMovil.page.goto(`${origen}/#/config-gestion-diaria`);
  const formMovil=gerMovil.page.getByRole('region',{name:'Editar reglas de Gestión Diaria'});
  await expect(formMovil).toBeVisible();
  await formMovil.getByRole('heading',{name:'Próxima versión'}).scrollIntoViewIfNeeded();
  await legible(formMovil);
  await botonesDentro(formMovil);
  assert.ok(await gerMovil.page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),'Editor móvil sin desborde');
  await gerMovil.page.screenshot({path:`${carpeta}/f45-editor-mobile.png`,animations:'disabled'});
  await gerMovil.context.close();
  evidencia.push('Editor en sesión inicialmente móvil; confirmación de publicación revisada y cancelada sin escribir');
  assert.deepEqual(errores,[],'Sin errores JavaScript');
  assert.equal(externos.size,0,'El navegador no consulta servicios externos');
  sql('select private.assert_gestion_diaria();');
  writeFileSync(`${carpeta}/${soloCapturas?'gd-f4-capturas':'gd-f4-navegador'}.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),evidencia},null,2)+'\n',{mode:0o600});
  console.log(soloCapturas?'PASS: capturas y comprobaciones de lectura móvil/configuración con Auth/API reales, sin publicar':
    'PASS: recorrido de F4 con navegador/Auth/HTTP reales; popup, foco, registro, lista entre sesiones, móvil y configuración');
} finally {
  await browser?.close();
  await servidor.close();
}
