import { chromium, expect } from '../../CRM-Avance-Corp/app/node_modules/@playwright/test/index.mjs'
import { writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const carpeta = new URL('./', import.meta.url)
const navegador = await chromium.launch({ headless: true })
const page = await navegador.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' })
const errores = []
const externos = []
page.on('pageerror', e => errores.push(e.message))
page.on('request', r => { if (/^https?:/.test(r.url()) && new URL(r.url()).hostname !== '127.0.0.1') externos.push(r.url()) })
const destino = 'http://127.0.0.1:4180/prototypes/citas-avance.html'
try {
  await page.goto(destino)
  await expect(page.getByRole('heading', { name: 'Avance mensual por analista' })).toBeVisible()
  const tabla = page.locator('.ca-metas')
  const ana = tabla.getByRole('row').filter({ has: page.getByRole('button', { name: 'Ana Torres María León', exact: true }) })
  await expect(ana).toContainText('160')
  await expect(ana).toContainText('50%')
  await expect(ana).toContainText('70 entrevistas')
  await expect(ana).toContainText('42 clientes')
  await expect(page.getByRole('button', { name: 'No asistieron: 60. Ver personas', exact: true })).toBeVisible()
  await expect(page.locator('.ca-lista-recuperacion')).toHaveCount(0)
  await expect(page.getByText('1,25', { exact: false })).toHaveCount(0)
  await expect(ana.getByRole('button', { name: 'Avance de citas: 50%. A ritmo del mes. Ver detalle', exact: true })).toBeVisible()
  await expect(ana.locator('[data-senal="cumplida"]')).toHaveCount(2)
  const paola = tabla.getByRole('row').filter({ has: page.getByRole('button', { name: 'Paola Vega Jorge Ruiz', exact: true }) })
  await expect(paola.locator('[data-senal="prioridad"]')).toContainText('0%')
  await expect(paola.locator('[data-senal="sin_base"]')).toHaveCount(2)
  const prioridad = tabla.getByRole('button', { name: 'Conversión: 30%. Brecha alta: revisar. Ver detalle', exact: true })
  await prioridad.focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog')).toContainText('Diego Salas')
  await page.keyboard.press('Escape')
  await expect(prioridad).toBeFocused()
  const contrastes = await tabla.locator('tbody .ca-senal').evaluateAll(elementos => {
    const lienzo = document.createElement('canvas')
    lienzo.width = lienzo.height = 1
    const ctx = lienzo.getContext('2d')
    const rgb = color => {
      ctx.clearRect(0, 0, 1, 1)
      ctx.fillStyle = color
      ctx.fillRect(0, 0, 1, 1)
      return [...ctx.getImageData(0, 0, 1, 1).data]
    }
    const luminancia = valores => valores.slice(0, 3).map(v => v / 255).map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4).reduce((s, v, i) => s + v * [0.2126, 0.7152, 0.0722][i], 0)
    return elementos.map(el => {
      const estilo = getComputedStyle(el)
      let fondo = rgb(estilo.backgroundColor)
      let padre = el.parentElement
      while (fondo[3] === 0 && padre) {
        fondo = rgb(getComputedStyle(padre).backgroundColor)
        padre = padre.parentElement
      }
      const tinta = luminancia(rgb(estilo.color))
      const base = luminancia(fondo)
      return { estado: el.dataset.senal, contraste: (Math.max(tinta, base) + 0.05) / (Math.min(tinta, base) + 0.05) }
    })
  })
  for (const medicion of contrastes) expect(medicion.contraste).toBeGreaterThanOrEqual(4.5)
  await page.getByRole('heading', { name: 'Citas del equipo' }).click()
  await page.screenshot({ path: fileURLToPath(new URL('escritorio.png', carpeta)), fullPage: true })

  await page.getByLabel('Analista', { exact: true }).selectOption('ana')
  await expect(page.getByRole('button', { name: 'Reprogramaron: 12. Ver personas', exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Se hicieron clientes: 5. Ver personas', exact: true }).click()
  await expect(page.locator('.ca-lista-recuperacion tbody tr')).toHaveCount(5)
  await page.locator('.ca-lista-recuperacion tbody button').first().click()
  await expect(page.getByRole('dialog')).toContainText('Se convirtió en cliente')
  await expect(page.getByRole('dialog')).toContainText('Cita reprogramada')
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.locator('.ca-lista-recuperacion tbody button').first()).toBeFocused()

  await page.getByRole('button', { name: 'No asistieron: 20. Ver personas', exact: true }).click()
  await expect(page.locator('.ca-lista-recuperacion')).toContainText('1–8 de 20 personas')
  await page.locator('.ca-lista-recuperacion').getByRole('button', { name: 'Siguiente', exact: true }).click()
  await expect(page.locator('.ca-lista-recuperacion')).toContainText('9–16 de 20 personas')
  await page.getByRole('button', { name: 'Ocultar personas del recorrido' }).click()

  await page.getByRole('button', { name: 'Ana Torres María León', exact: true }).click()
  await expect(page.getByRole('dialog')).toContainText('32 manuales')
  await expect(page.getByRole('dialog')).toContainText('42 clientes / 60 personas entrevistadas')
  await expect(page.getByRole('dialog')).toContainText('10 entrevistas adicionales')
  await page.screenshot({ path: fileURLToPath(new URL('detalle-analista.png', carpeta)), fullPage: true })
  await page.getByRole('button', { name: 'Ver leads y citas' }).click()
  await page.getByLabel(/Solo leads sin citas/).check()
  await expect(page.getByRole('dialog').locator('.ca-persona')).toHaveCount(20)
  await page.getByRole('dialog').getByRole('button', { name: 'Siguiente', exact: true }).click()
  await expect(page.getByRole('dialog')).toContainText('21–40 de')
  await page.keyboard.press('Escape')

  await page.getByRole('button', { name: 'Cómo se calcula', exact: true }).click()
  await page.getByLabel('Base propuesta para la conversión').selectOption('entrevistas')
  await page.keyboard.press('Escape')
  await expect(ana.locator('td').nth(4)).toContainText('60%')
  await page.getByRole('button', { name: 'Cómo se calcula', exact: true }).click()
  await page.getByLabel('Base propuesta para la conversión').selectOption('personas')
  await page.keyboard.press('Escape')

  await page.getByLabel('Semana del seguimiento').selectOption('2')
  await expect(page.getByRole('button', { name: 'No asistieron: 0. Ver personas', exact: true })).toBeVisible()
  await expect(page.locator('.ca-aclaracion-semana')).toContainText('La tabla y la proyección conservan el acumulado mensual')
  await expect(ana).toContainText('50%')
  await page.getByRole('tab', { name: 'Bandeja comercial' }).click()
  await page.getByLabel('Estado', { exact: true }).selectOption('realizada')
  await expect(page.locator('.ca-operativa tbody tr')).not.toHaveCount(0)
  await page.getByRole('tab', { name: 'Agenda', exact: true }).focus()
  await page.keyboard.press('ArrowRight')
  await expect(page.getByRole('tab', { name: 'Resultados' })).toHaveAttribute('aria-selected', 'true')

  await page.getByRole('button', { name: 'Más filtros', exact: true }).click()
  await page.getByLabel('Registro del lead').selectOption('manual')
  await expect(ana.locator('td').first()).toHaveText('32')
  await page.getByLabel('Origen', { exact: true }).selectOption('Web')
  await expect(ana.locator('td').first()).toHaveText('10')
  await page.getByRole('button', { name: 'Restablecer filtros' }).click()
  await page.getByLabel('Supervisor', { exact: true }).selectOption('Jorge Ruiz')
  await expect(tabla.locator('tbody tr')).toHaveCount(2)
  await expect(page.getByLabel('Analista', { exact: true }).locator('option[value="ana"]')).toHaveCount(0)
  await page.getByLabel('Moneda', { exact: true }).selectOption('USD')
  await expect(page.getByRole('heading', { name: 'No hay datos de ejemplo para esta consulta' })).toBeVisible()
  await page.getByRole('button', { name: 'Volver al ejemplo' }).click()
  await page.getByLabel('Mes', { exact: true }).selectOption('2026-08')
  await expect(page.getByRole('heading', { name: 'No hay datos de ejemplo para esta consulta' })).toBeVisible()
  await page.getByRole('button', { name: 'Volver al ejemplo' }).click()
  const descarga = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Exportar', exact: true }).click()
  expect((await descarga).suggestedFilename()).toBe('ejemplo-citas-2026-09.csv')
  await page.getByRole('button', { name: 'Más filtros', exact: true }).click()

  const anchos = []
  for (const ancho of [1440, 1280, 768, 390]) {
    await page.setViewportSize({ width: ancho, height: ancho < 500 ? 844 : 1000 })
    // El menú compartido elige su estado inicial según el dispositivo al montar.
    // Una carga móvil debe probarse como tal, sin heredar el menú abierto del escritorio.
    await page.reload()
    await expect(page.getByRole('heading', { name: 'Citas del equipo' })).toBeVisible()
    const medicion = await page.evaluate(() => ({ ventana: innerWidth, documento: document.documentElement.scrollWidth, tabla: document.querySelector('.ca-metas').scrollWidth, visible: document.querySelector('.ca-metas').parentElement.clientWidth }))
    expect(medicion.documento).toBeLessThanOrEqual(ancho)
    if (ancho >= 1280) expect(medicion.tabla).toBeLessThanOrEqual(medicion.visible + 1)
    anchos.push(medicion)
    if (ancho === 390) {
      const titulo = await page.getByRole('heading', { name: 'Citas del equipo' }).boundingBox()
      expect(await page.evaluate(({ x, y }) => !!document.elementFromPoint(x, y)?.closest('main'), { x: titulo.x + titulo.width / 2, y: titulo.y + titulo.height / 2 })).toBe(true)
      await page.screenshot({ path: fileURLToPath(new URL('movil.png', carpeta)), fullPage: true })
    }
  }
  expect(errores).toEqual([])
  expect(externos).toEqual([])
  await writeFile(new URL('verificacion-visual.json', carpeta), JSON.stringify({ estado: 'PASS', url: destino, datos: 'ficticios', anchos, contrastes, errores, conexionesExternas: externos, comprobaciones: ['cifras y meta interna', 'recorrido vinculado', 'paginacion completa', 'detalle y retorno de foco', 'repeticion de entrevistas', 'dos bases de conversion', 'mes y semana', 'tabs por teclado', 'registro manual y origen', 'supervisor dependiente', 'monedas separadas', 'sin datos', 'exportacion', 'responsive', 'ritmo mensual sin falsa alerta', 'cero distinto de sin base', 'indicadores accionables por teclado', 'contraste de indicadores al menos 4.5:1'] }, null, 2) + '\n')
  console.log('PASS: cifras, filtros, recorrido, detalles, exportación, teclado, contraste de indicadores y cuatro anchos; sin errores ni conexiones externas.')
} finally {
  await navegador.close()
}
