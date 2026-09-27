import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

const id = '10000000-0000-4000-8000-000000000991'
const usuario = {
  perfil_id: id, nombre_completo: 'ANALISTA DE PRUEBA', tipo_documento: 'DNI',
  documento: '78912345', correo: 'analista@example.test', telefono: null, whatsapp: null, cargo: null,
  tipo_cuenta: 'solo_crm', estado: 'activo', rol_crm: 'vendedor', supervisor_id: null,
  activo_crm: true, activo_portal: true, version_perfil: '2026-09-25T10:00:00Z',
  version_equipo: '2026-09-25T10:00:00Z', total: 1,
}

for (const pendientes of [false, true]) test(`Gerencia elimina con confirmación; pendientes=${pendientes}`, async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'gerencia', rolPortal: 'admin' })
  let borrado = false
  let llamadas = 0
  await page.route('**/rest/v1/rpc/usuarios_administrables_fn', (route) => route.fulfill({
    json: borrado ? [] : [usuario],
  }))
  await page.route('**/rest/v1/rpc/impacto_eliminacion_usuario_fn', (route) => route.fulfill({ json: {
    pendientes: { perfil_id: id, subordinados_activos: 0, leads_abiertos: 0, leads_en_bandeja: 0,
      tareas_pendientes: pendientes ? 2 : 0, clientes_activos: 0, requiere_reemplazo: pendientes },
    conserva_historial: true,
  } }))
  await page.route('**/rest/v1/rpc/eliminar_usuario_fn', async (route) => {
    llamadas++
    expect(route.request().postDataJSON()).toMatchObject({ p_perfil_id: id, p_nombre_confirmacion: usuario.nombre_completo })
    borrado = true
    await route.fulfill({ json: { perfil_id: id, resultado: 'historial_conservado' } })
  })
  await loginReal(page)
  await page.evaluate(() => { window.location.hash = '#/config-usuarios' })
  await page.getByRole('button', { name: `Eliminar a ${usuario.nombre_completo}` }).click()
  const dialogo = page.getByRole('dialog', { name: 'Eliminar usuario del CRM' })
  await expect(dialogo).toBeVisible()
  if (pendientes) {
    await expect(dialogo.getByRole('button', { name: 'Confirmar eliminación' })).toHaveCount(0)
    await dialogo.getByRole('button', { name: 'Transferir pendientes' }).click()
    await expect(page.getByLabel('Reemplazo activo del mismo rol')).toBeVisible()
    expect(llamadas).toBe(0)
  } else {
    await expect(dialogo.getByRole('button', { name: 'Confirmar eliminación' })).toBeDisabled()
    await dialogo.getByLabel('Escribe su nombre completo para confirmar').fill(usuario.nombre_completo)
    await dialogo.getByRole('button', { name: 'Confirmar eliminación' }).click()
    await expect(page.getByText('Acceso retirado. Se conserva su nombre como autor del historial.')).toBeVisible()
    await expect(page.getByRole('button', { name: `Eliminar a ${usuario.nombre_completo}` })).toHaveCount(0)
    expect(llamadas).toBe(1)
  }
})
