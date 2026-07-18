// Tests de la lógica PURA del formulario de cliente — espejo de analista.js.
// Los MENSAJES se afirman VERBATIM: son los mismos que muestra el portal y
// cambiarlos rompería la paridad del traspaso.
import { describe, expect, it } from 'vitest'
import type { ClienteDetalle } from './clientes-tipos'
import {
  BANCOS_PE,
  SECCION_BANCARIA_VACIA,
  armarPatchBancarios,
  normNombrePersona,
  seccionPenDesdeDetalle,
  seccionUsdDesdeDetalle,
  validarBancariosForm,
  validarClienteForm,
  validarSeccionBancaria,
  type SeccionBancariaForm,
  type ValoresClienteForm,
} from './cliente-form-logica'

function seccion(over: Partial<SeccionBancariaForm> = {}): SeccionBancariaForm {
  return { ...SECCION_BANCARIA_VACIA, ...over }
}

function seccionPenCompleta(over: Partial<SeccionBancariaForm> = {}): SeccionBancariaForm {
  return seccion({
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    ...over,
  })
}

function valores(over: Partial<ValoresClienteForm> = {}): ValoresClienteForm {
  return {
    apellidos: 'diaz huayta',
    nombres: 'hugo gualberto',
    tipo_documento: 'DNI',
    documento: '45781234',
    telefono: ' 999 111 222 ',
    correo: 'hugo@correo.pe',
    pen: seccionPenCompleta(),
    usd: seccion(),
    ...over,
  }
}

function detalle(over: Partial<ClienteDetalle> = {}): ClienteDetalle {
  return {
    id: 'cli-1',
    nombre_completo: 'PORTAL UNO CLIENTE',
    nombres: 'CLIENTE',
    apellidos: 'PORTAL UNO',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'cliente1@correo.pe',
    telefono: '+51999888777',
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    creado_en: '2026-07-16T10:00:00.000Z',
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    banco_usd: 'Interbank',
    tipo_cuenta_usd: 'corriente',
    numero_cuenta_usd: '20099887766554',
    cci_usd: '00320099887766554321',
    titular_distinto_usd: true,
    beneficiario_nombre_usd: 'TERCERO USD',
    beneficiario_dni_usd: '87654321',
    ...over,
  }
}

describe('BANCOS_PE (catálogo del portal)', () => {
  it('trae las 33 entidades en 3 apartados, sin "Otro" (lo agrega el select al final)', () => {
    const planas = BANCOS_PE.flatMap((g) => [...g.opciones])
    expect(planas).toHaveLength(33)
    expect(BANCOS_PE.map((g) => g.grupo)).toEqual(['Bancos', 'Cajas municipales', 'Financieras'])
    expect(planas).not.toContain('Otro')
    // Casos que el portal agregó a propósito y no deben perderse en el espejo.
    expect(planas).toContain('Banco SIP')
    expect(planas).toContain('Caja Huancayo')
    // Caja Sullana quedó excluida a propósito (intervenida por la SBS en 2024).
    expect(planas).not.toContain('Caja Sullana')
  })
})

describe('normNombrePersona', () => {
  it('MAYÚSCULA, sin extremos y colapsando espacios internos (norma 2026-06-04)', () => {
    expect(normNombrePersona('  juan  pérez ')).toBe('JUAN PÉREZ')
    expect(normNombrePersona('')).toBe('')
  })
})

describe('validarSeccionBancaria (espejo de leerYValidarBancarios)', () => {
  it('sección completamente vacía = cuenta no provista (ok, vacia, todo null)', () => {
    const r = validarSeccionBancaria(seccion(), 'Soles')
    expect(r).toEqual({
      ok: true,
      vacia: true,
      datos: {
        banco: null,
        numero_cuenta: null,
        tipo_cuenta: null,
        cci: null,
        titular_distinto: false,
        beneficiario_nombre: null,
        beneficiario_dni: null,
      },
    })
  })

  it('si algo se llenó, exige el set completo con el mensaje del portal (y su moneda)', () => {
    expect(validarSeccionBancaria(seccion({ numero_cuenta: '123' }), 'Soles'))
      .toEqual({ ok: false, error: 'Selecciona el banco de la cuenta (Soles).' })
    expect(validarSeccionBancaria(seccion({ banco: 'BCP' }), 'Dólares'))
      .toEqual({ ok: false, error: 'El N° de cuenta (Dólares) es obligatorio.' })
    // Cuentas de cajas municipales llevan letras/guiones (Caja Cusco, 2026-07-18):
    // letras y guiones pasan; espacios y otros símbolos no.
    expect(validarSeccionBancaria(seccion({ banco: 'BCP', numero_cuenta: '12 34' }), 'Soles'))
      .toEqual({ ok: false, error: 'El N° de cuenta (Soles) solo puede contener letras, números y guiones (sin espacios).' })
    expect(validarSeccionBancaria(seccion({ banco: 'BCP', numero_cuenta: 'A105-201332' }), 'Soles'))
      .toEqual({ ok: false, error: 'Selecciona el tipo de cuenta (Soles).' })
    expect(validarSeccionBancaria(seccion({ banco: 'BCP', numero_cuenta: '123' }), 'Soles'))
      .toEqual({ ok: false, error: 'Selecciona el tipo de cuenta (Soles).' })
    expect(
      validarSeccionBancaria(seccion({ banco: 'BCP', numero_cuenta: '123', tipo_cuenta: 'sueldo' }), 'Soles'),
    ).toEqual({ ok: false, error: 'Tipo de cuenta (Soles) inválido.' })
    // CCI obligatorio cuando la sección se llena — regla del portal (analista.js).
    expect(
      validarSeccionBancaria(seccion({ banco: 'BCP', numero_cuenta: '123', tipo_cuenta: 'ahorros' }), 'Soles'),
    ).toEqual({ ok: false, error: 'El CCI (Soles) es obligatorio.' })
    expect(validarSeccionBancaria(seccionPenCompleta({ cci: '123' }), 'Soles'))
      .toEqual({ ok: false, error: 'El CCI (Soles) debe tener exactamente 20 dígitos.' })
  })

  it('beneficiario: solo se exige con el check activo, con doc de 8–12 dígitos', () => {
    expect(validarSeccionBancaria(seccionPenCompleta({ titular_distinto: true }), 'Soles'))
      .toEqual({ ok: false, error: 'Escribe el nombre completo del beneficiario (Soles) (titular de la cuenta).' })
    expect(
      validarSeccionBancaria(
        seccionPenCompleta({ titular_distinto: true, beneficiario_nombre: 'tercero uno' }),
        'Soles',
      ),
    ).toEqual({ ok: false, error: 'El DNI del beneficiario (Soles) es obligatorio.' })
    expect(
      validarSeccionBancaria(
        seccionPenCompleta({ titular_distinto: true, beneficiario_nombre: 'tercero', beneficiario_dni: '1234567' }),
        'Soles',
      ),
    ).toEqual({ ok: false, error: 'El DNI del beneficiario (Soles) debe tener entre 8 y 12 dígitos.' })
  })

  it('feliz con beneficiario: normaliza el nombre (MAYÚSCULA, espacios colapsados)', () => {
    const r = validarSeccionBancaria(
      seccionPenCompleta({
        titular_distinto: true,
        beneficiario_nombre: ' juana  perez ',
        beneficiario_dni: '87654321',
      }),
      'Soles',
    )
    expect(r).toEqual({
      ok: true,
      vacia: false,
      datos: {
        banco: 'BCP',
        numero_cuenta: '19112345678901',
        tipo_cuenta: 'ahorros',
        cci: '00219112345678901234',
        titular_distinto: true,
        beneficiario_nombre: 'JUANA PEREZ',
        beneficiario_dni: '87654321',
      },
    })
  })

  it('solo el check activo (resto vacío) NO cuenta como sección vacía: pide el banco', () => {
    expect(validarSeccionBancaria(seccion({ titular_distinto: true }), 'Dólares'))
      .toEqual({ ok: false, error: 'Selecciona el banco de la cuenta (Dólares).' })
  })
})

describe('armarPatchBancarios / precarga desde el detalle', () => {
  it('PEN va a columnas base y USD al sufijo _usd (las 14 exactas)', () => {
    const d = detalle()
    const pen = validarSeccionBancaria(seccionPenDesdeDetalle(d), 'Soles')
    const usd = validarSeccionBancaria(seccionUsdDesdeDetalle(d), 'Dólares')
    if (!pen.ok || !usd.ok) throw new Error('las secciones del detalle deben validar')
    const patch = armarPatchBancarios(pen.datos, usd.datos)
    expect(patch).toEqual({
      banco: 'BCP',
      tipo_cuenta: 'ahorros',
      numero_cuenta: '19112345678901',
      cci: '00219112345678901234',
      titular_distinto: false,
      beneficiario_nombre: null,
      beneficiario_dni: null,
      banco_usd: 'Interbank',
      tipo_cuenta_usd: 'corriente',
      numero_cuenta_usd: '20099887766554',
      cci_usd: '00320099887766554321',
      titular_distinto_usd: true,
      beneficiario_nombre_usd: 'TERCERO USD',
      beneficiario_dni_usd: '87654321',
    })
  })
})

describe('validarClienteForm — identidad (espejo de guardarCliente)', () => {
  it('feliz: normaliza y deriva nombre_completo con APELLIDOS primero', () => {
    const r = validarClienteForm(valores())
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.cliente.nombre_completo).toBe('DIAZ HUAYTA HUGO GUALBERTO')
    expect(r.cliente.apellidos).toBe('DIAZ HUAYTA')
    expect(r.cliente.nombres).toBe('HUGO GUALBERTO')
    expect(r.cliente.dni).toBe('45781234')
    expect(r.cliente.telefono).toBe('999 111 222')
    expect(r.cliente.correo).toBe('hugo@correo.pe')
    expect(r.cliente.bancarios.banco).toBe('BCP')
    expect(r.cliente.bancarios.banco_usd).toBeNull()
  })

  it('teléfono vacío viaja como null (columna nullable)', () => {
    const r = validarClienteForm(valores({ telefono: '   ' }))
    expect(r.ok && r.cliente.telefono).toBeNull()
  })

  it('un solo campo del nombre lleno → mensaje "ambos campos"', () => {
    expect(validarClienteForm(valores({ nombres: ' ' })))
      .toEqual({ ok: false, error: 'Completa Apellidos y Nombres (ambos campos).' })
  })

  it('ambos vacíos en el ALTA → error (no hay legacy que conservar)', () => {
    expect(validarClienteForm(valores({ apellidos: '', nombres: '' })))
      .toEqual({ ok: false, error: 'Completa los apellidos y nombres del cliente.' })
  })

  it('LEGACY sin separar (corregir): ambos vacíos conservan su nombre_completo original', () => {
    const legacy = detalle({ apellidos: null, nombres: null, nombre_completo: 'NOMBRE VIEJO JUNTO' })
    const r = validarClienteForm(valores({ apellidos: '', nombres: '' }), legacy)
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.cliente.nombre_completo).toBe('NOMBRE VIEJO JUNTO')
    expect(r.cliente.apellidos).toBeNull()
    expect(r.cliente.nombres).toBeNull()
  })

  it('sin correo o sin documento → mensaje combinado del portal', () => {
    expect(validarClienteForm(valores({ correo: ' ' })))
      .toEqual({ ok: false, error: 'Completa apellidos, nombres, documento y correo.' })
    expect(validarClienteForm(valores({ documento: '' })))
      .toEqual({ ok: false, error: 'Completa apellidos, nombres, documento y correo.' })
  })
})

describe('validarClienteForm — documento por tipo + grandfathering', () => {
  it('valida por tipo con el mensaje de la regla (DNI de 7 dígitos)', () => {
    expect(validarClienteForm(valores({ documento: '4578123' })))
      .toEqual({ ok: false, error: 'El DNI debe tener exactamente 8 dígitos.' })
  })

  it('pasaporte se normaliza a MAYÚSCULA antes de viajar', () => {
    const r = validarClienteForm(valores({ tipo_documento: 'PASAPORTE', documento: 'ab1234' }))
    expect(r.ok && r.cliente.dni).toBe('AB1234')
  })

  it('GRANDFATHERING: documento legado sin tocar pasa tal cual aunque hoy no valide', () => {
    const legado = detalle({ dni: '1234' }) // 4 dígitos: hoy inválido
    const r = validarClienteForm(valores({ documento: '1234' }), legado)
    expect(r.ok && r.cliente.dni).toBe('1234')
  })

  it('si el documento SÍ se tocó en la corrección, vuelve a validar por tipo', () => {
    const legado = detalle({ dni: '1234' })
    expect(validarClienteForm(valores({ documento: '12345' }), legado))
      .toEqual({ ok: false, error: 'El DNI debe tener exactamente 8 dígitos.' })
  })

  it('cambiar solo el TIPO también rompe el grandfathering (se revalida)', () => {
    const legado = detalle({ dni: '45781234', tipo_documento: 'DNI' })
    // Mismo número, tipo distinto: como CE necesita 9–12 dígitos → error.
    expect(validarClienteForm(valores({ tipo_documento: 'CE', documento: '45781234' }), legado))
      .toEqual({ ok: false, error: 'El Carné de Extranjería debe tener entre 9 y 12 dígitos.' })
  })
})

describe('validarClienteForm — regla bancaria "al menos una cuenta"', () => {
  it('ambas secciones vacías → mensaje del portal', () => {
    expect(validarClienteForm(valores({ pen: seccion(), usd: seccion() }))).toEqual({
      ok: false,
      error: 'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    })
  })

  it('el error de una sección sube con su moneda en el mensaje', () => {
    expect(validarClienteForm(valores({ usd: seccion({ banco: 'Interbank' }) })))
      .toEqual({ ok: false, error: 'El N° de cuenta (Dólares) es obligatorio.' })
  })

  it('solo USD llena también es válido (PEN puede quedar vacía)', () => {
    const r = validarClienteForm(valores({
      pen: seccion(),
      usd: seccionPenCompleta({ banco: 'Interbank' }),
    }))
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.cliente.bancarios.banco).toBeNull()
    expect(r.cliente.bancarios.banco_usd).toBe('Interbank')
  })
})

// La comparte el alta directa (vía validarClienteForm) y la CONVERSIÓN de lead,
// que valida la identidad por su lado pero exige los MISMOS bancarios.
describe('validarBancariosForm (compartida: alta directa y conversión de lead)', () => {
  it('ambas secciones vacías → mensaje verbatim del portal ("al menos una cuenta")', () => {
    expect(validarBancariosForm(seccion(), seccion())).toEqual({
      ok: false,
      error: 'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    })
  })

  it('el error de una sección sube con su moneda en el mensaje', () => {
    expect(validarBancariosForm(seccion(), seccion({ banco: 'Interbank' })))
      .toEqual({ ok: false, error: 'El N° de cuenta (Dólares) es obligatorio.' })
    expect(validarBancariosForm(seccionPenCompleta({ cci: '123' }), seccion()))
      .toEqual({ ok: false, error: 'El CCI (Soles) debe tener exactamente 20 dígitos.' })
  })

  it('feliz solo PEN: arma el patch de 14 columnas con USD en null', () => {
    const r = validarBancariosForm(seccionPenCompleta(), seccion())
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.bancarios).toEqual({
      banco: 'BCP',
      tipo_cuenta: 'ahorros',
      numero_cuenta: '19112345678901',
      cci: '00219112345678901234',
      titular_distinto: false,
      beneficiario_nombre: null,
      beneficiario_dni: null,
      banco_usd: null,
      tipo_cuenta_usd: null,
      numero_cuenta_usd: null,
      cci_usd: null,
      titular_distinto_usd: false,
      beneficiario_nombre_usd: null,
      beneficiario_dni_usd: null,
    })
  })

  it('feliz solo USD: PEN puede quedar vacía (regla por moneda, no por par)', () => {
    const r = validarBancariosForm(seccion(), seccionPenCompleta({ banco: 'Interbank' }))
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.bancarios.banco).toBeNull()
    expect(r.bancarios.banco_usd).toBe('Interbank')
    expect(r.bancarios.cci_usd).toBe('00219112345678901234')
  })
})
