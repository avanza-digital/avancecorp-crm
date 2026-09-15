import { readFile } from 'node:fs/promises'
import vm from 'node:vm'
import test from 'node:test'
import assert from 'node:assert/strict'
import { JSDOM } from '../../../app/node_modules/jsdom/lib/api.js'
import { guardarCorreoCliente, validarCorreccionCorreo } from '../../../../public_html/js/admin/correo-cliente-core.js'

const portal = new URL('../../../../public_html/', import.meta.url)
const html = await readFile(new URL('admin/clientes.html', portal), 'utf8')
const codigo = (await readFile(new URL('js/admin/clientes.js', portal), 'utf8'))
  .replace(/^import[\s\S]*? from ['"][^'"]+['"]\n/gm, '')
  .split(';(async () => {')[0]

function montar(permitido) {
  const dom = new JSDOM(html, { url: 'https://miavance.com/admin/clientes' })
  const llamadas = []
  const contexto = vm.createContext({
    document: dom.window.document, window: dom.window, setTimeout, console,
    guardarCorreoCliente, validarCorreccionCorreo,
    mensajeErrorGuardarCliente: e => e.message,
    formatearFecha: () => 'fecha',
    validarDocumento: () => ({ ok: true, valor: '12345678' }),
    supabase: {
      from: () => ({ update: datos => ({ eq: async () => { llamadas.push(['perfil', datos]); return { error: null } } }) }),
      functions: { invoke: async (nombre, opciones) => { llamadas.push([nombre, opciones.body]); return { data: { ok: true }, error: null } } },
    },
    mostrarExito: mensaje => llamadas.push(['exito', mensaje]),
    mostrarError: mensaje => llamadas.push(['error', mensaje]),
  })
  vm.runInContext(codigo, contexto)
  const doc = dom.window.document
  for (const id of ['e_tipo_documento']) doc.getElementById(id).innerHTML = '<option value="DNI">DNI</option>'
  vm.runInContext(`PUEDE_EDITAR_CORREO_CLIENTE=${permitido}; PUEDE_EDITAR_DOCUMENTO_CLIENTE=${permitido}; recargar=async()=>{};
    abrirModalEditar({id:'cliente',nombre_completo:'CLIENTE PRUEBA',apellidos:'PRUEBA',nombres:'CLIENTE',dni:'12345678',tipo_documento:'DNI',correo:'anterior@example.test'});`, contexto)
  return { doc, llamadas, ejecutar: code => vm.runInContext(code, contexto), cerrar: () => dom.window.close() }
}

test('el formulario real de Admin permite corregir, exige motivo y manda solo la Edge', async () => {
  const vista = montar(true)
  try {
    assert.equal(vista.doc.getElementById('e_correo').readOnly, false)
    assert.equal(vista.doc.getElementById('e_correo_motivo_group').classList.contains('hidden'), true)
    vista.doc.getElementById('e_correo').value = 'Nuevo@example.test'
    vista.ejecutar('actualizarMotivoCorreo()')
    assert.equal(vista.doc.getElementById('e_correo_motivo_group').classList.contains('hidden'), false)
    await vista.ejecutar('guardarEdicion({preventDefault(){}})')
    assert.match(vista.doc.getElementById('modalEditarError').textContent, /motivo/)
    assert.equal(vista.llamadas.length, 0)
    vista.doc.getElementById('e_correo_motivo').value = 'Corrección solicitada'
    await vista.ejecutar('guardarEdicion({preventDefault(){}})')
    assert.equal(vista.llamadas[0][0], 'perfil')
    assert.equal(Object.hasOwn(vista.llamadas[0][1], 'correo'), false)
    assert.equal(vista.llamadas[1][0], 'corregir-correo-cliente')
    assert.equal(vista.llamadas[1][1].correo, 'nuevo@example.test')
    assert.match(vista.llamadas[2][1], /misma contraseña/)
  } finally { vista.cerrar() }
})

test('el formulario real sin permiso mantiene el correo de solo lectura', async () => {
  const vista = montar(false)
  try {
    assert.equal(vista.doc.getElementById('e_correo').readOnly, true)
    vista.doc.getElementById('e_correo').value = 'forzado@example.test'
    vista.doc.getElementById('e_correo_motivo').value = 'Forzado desde consola'
    await vista.ejecutar('guardarEdicion({preventDefault(){}})')
    assert.match(vista.doc.getElementById('modalEditarError').textContent, /administrador/)
    assert.equal(vista.llamadas.length, 0)
  } finally { vista.cerrar() }
})
