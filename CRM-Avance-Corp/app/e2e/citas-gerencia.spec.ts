import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'
import { montarConsultaCitas } from './_citas'

test('Gerencia: consulta Citas dentro del CRM y conserva mes y semana entre vistas',async ({page}) => {
  await page.goto('/')
  await page.getByRole('button',{name:/explorar en modo demo/i}).click()
  await page.getByRole('button',{name:/^Gerencia/}).click()
  await page.getByRole('button',{name:'Citas',exact:true}).click()
  await expect(page.getByRole('heading',{name:'Citas del equipo'})).toBeVisible()
  await expect(page.getByLabel('Mes')).toBeVisible()
  await page.getByLabel('Semana',{exact:true}).selectOption('4')
  await page.getByRole('tab',{name:'Bandeja comercial'}).click()
  await expect(page.getByLabel('Semana',{exact:true})).toHaveValue('4')
  await page.getByRole('tab',{name:'Agenda',exact:true}).click()
  await expect(page.getByLabel('Semana',{exact:true})).toHaveValue('4')
  await page.getByRole('button',{name:'Restablecer consulta'}).click()
  await page.getByRole('button',{name:'Cómo usar Citas'}).click()
  await expect(page.getByRole('dialog',{name:'Cómo usar Citas'})).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('button',{name:'Cómo usar Citas'})).toBeFocused()
  await page.getByLabel('Mes').fill('2026-01')
  await expect(page.getByText('No hay citas con esta combinación')).toBeVisible()
  await expect(page.getByRole('button',{name:'Exportar citas'})).toBeDisabled()
})

test('una consulta no habilitada muestra el error y se recupera sin recurrir a cifras de ejemplo',async ({page}) => {
  await page.clock.setFixedTime(new Date('2026-09-04T15:00:00Z'))
  await montarBackendReal(page)
  await page.route('**/rest/v1/rpc/citas_gerencia_consulta_fn',route => route.fulfill({status:404,json:{code:'PGRST202',message:'Internal RPC detail'}}))
  await loginReal(page)
  await page.getByRole('button',{name:'Citas',exact:true}).click()
  await expect(page.getByRole('alert')).toContainText('aún no está habilitada')
  await expect(page.getByRole('button',{name:'Exportar citas'})).toBeDisabled()
  await expect(page.getByRole('table')).toHaveCount(0)
  await expect(page.getByText('Datos de ejemplo')).toHaveCount(0)
  await montarConsultaCitas(page)
  await page.getByRole('button',{name:'Reintentar',exact:true}).click()
  await expect(page.getByRole('button',{name:'No asistieron 2'})).toBeVisible()
  await expect(page.getByRole('button',{name:'Exportar citas'})).toBeEnabled()
})

test('Citas incorpora cambios de otro usuario al minuto y conserva la semana consultada',async ({page}) => {
  await page.clock.install({time:new Date('2026-09-04T15:00:00Z')})
  await montarBackendReal(page)
  await montarConsultaCitas(page,'pendiente')
  await loginReal(page)
  await page.getByRole('button',{name:'Citas',exact:true}).click()
  await expect(page.getByRole('button',{name:'No asistieron 2'})).toBeVisible()
  await page.getByLabel('Semana',{exact:true}).selectOption('1')
  // Otro analista cierra una cita vencida como inasistencia; no reescribe
  // los resultados de las citas que ya estaban cerradas.
  await montarConsultaCitas(page,'no_show')
  const refresco=page.waitForResponse('**/rest/v1/rpc/citas_gerencia_consulta_fn')
  await page.clock.fastForward('01:01')
  await refresco
  await expect(page.getByRole('button',{name:'No asistieron 3'})).toBeVisible()
  await expect(page.getByLabel('Semana',{exact:true})).toHaveValue('1')
})
