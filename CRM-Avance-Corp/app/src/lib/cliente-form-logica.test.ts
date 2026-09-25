// Tests de la lógica PURA del formulario de cliente — espejo de analista.js.
// Los MENSAJES se afirman VERBATIM: son los mismos que muestra el portal y
// cambiarlos rompería la paridad del traspaso.
import { describe, expect, it } from 'vitest'
import type { ClienteDetalle, CuentaBancariaSeleccionable } from './clientes-tipos'
import {
  BANCOS_PE,
  SECCION_BANCARIA_VACIA,
  armarPatchBancarios,
  hayCuentaEnLedger,
  normNombrePersona,
  seccionPenDesdeDetalle,
  seccionUsdDesdeDetalle,
  validarBancariosForm,
  validarClienteForm,
  validarDomicilioLegal,
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
    domicilio: '  Av. Javier Prado Este 123, San Isidro, Lima  ',
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
    telefono: '999111222',
    domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    creado_en: '2026-07-16T10:00:00.000Z',
    banca_visible: true,
    cuentas_bancarias_visibles: true,
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
  it('trae las 34 entidades en 3 apartados, sin "Otro" (lo agrega el select al final)', () => {
    const planas = BANCOS_PE.flatMap((g) => [...g.opciones])
    expect(planas).toHaveLength(34)
    expect(BANCOS_PE.map((g) => g.grupo)).toEqual(['Bancos', 'Cajas municipales', 'Financieras'])
    expect(planas).not.toContain('Otro')
    // Casos que el portal agregó a propósito y no deben perderse en el espejo.
    expect(planas).toContain('Banco SIP')
    // Alfin Banco (ex Banco Azteca Perú) — agregado 2026-09-01 a pedido de
    // Miguel: hay clientes con cuenta ahí que caían en "Otro". Nombre EXACTO
    // el de la SBS, porque es el que se imprime en el contrato.
    expect(planas).toContain('Alfin Banco')
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
      .toEqual({ ok: false, error: 'El N° de cuenta (Soles) solo admite letras, números y guiones (máximo 30).' })
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

  it('aplica los límites bancarios de la RPC antes de enviar el formulario', () => {
    expect(validarSeccionBancaria(seccionPenCompleta({ banco: 'B'.repeat(101) }), 'Soles'))
      .toEqual({ ok: false, error: 'El banco (Soles) no puede superar 100 caracteres.' })
    expect(validarSeccionBancaria(seccionPenCompleta({ numero_cuenta: '1'.repeat(31) }), 'Soles'))
      .toEqual({ ok: false, error: 'El N° de cuenta (Soles) solo admite letras, números y guiones (máximo 30).' })
    expect(validarSeccionBancaria(seccionPenCompleta({
      titular_distinto: true, beneficiario_nombre: 'A'.repeat(201), beneficiario_dni: '12345678',
    }), 'Soles'))
      .toEqual({ ok: false, error: 'El nombre del beneficiario (Soles) no puede superar 200 caracteres.' })
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
    expect(r.cliente.domicilio).toBe('Av. Javier Prado Este 123, San Isidro, Lima')
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

  it('rechaza un domicilio vacío porque el PDF legal no puede inventarlo', () => {
    expect(validarClienteForm(valores({ domicilio: '   ' })))
      .toEqual({ ok: false, error: 'Completa el domicilio legal del cliente.' })
  })

  it('rechaza domicilio corto, largo o con caracteres de control', () => {
    // El mínimo pasó de 5 a 15 (2026-08-19): decidido con los 19 domicilios
    // reales de producción, cuyo más corto tiene 28 caracteres. Con 5 pasaban
    // «LIMA.», «no tiene» y «PENDIENTE».
    expect(validarClienteForm(valores({ domicilio: 'Lima' })))
      .toEqual({ ok: false, error: 'El domicilio legal debe tener entre 15 y 240 caracteres.' })
    expect(validarClienteForm(valores({ domicilio: `Av. Lima 1 ${'x'.repeat(231)}` })))
      .toEqual({ ok: false, error: 'El domicilio legal debe tener entre 15 y 240 caracteres.' })
    // U+0085 (NEL) NO es un control a estos efectos: los tres lados lo tratan
    // como espacio y lo colapsan. Un control de verdad (campana) sí cae.
    expect(validarClienteForm(valores({ domicilio: 'Av. Lima 123\u0007 San Isidro' })))
      .toEqual({ ok: false, error: 'El domicilio legal contiene caracteres no permitidos.' })
  })

  it('el listón nuevo: exige número, y rechaza el relleno y la dirección de la empresa', () => {
    expect(validarDomicilioLegal('Avenida sin numero, San Isidro, Lima')).toEqual({
      ok: false,
      error: 'El domicilio legal necesita el número de la calle, el lote o la manzana.',
    })
    expect(validarDomicilioLegal('xxxxxxxxxxxxxxxxxxxx')).toEqual({
      ok: false,
      error: 'El domicilio legal necesita el número de la calle, el lote o la manzana.',
    })
    expect(validarDomicilioLegal('11111111111111111111')).toEqual({
      ok: false,
      error: 'El domicilio legal no puede ser un solo carácter repetido.',
    })
    // Ya ocurrió de verdad: se tecleó como domicilio de una clienta y el PDF
    // habría dejado a las dos partes domiciliadas en la misma oficina.
    for (const variante of [
      'Av. República de Panamá 3635',
      'AV REPUBLICA DE PANAMA N.° 3635, Urb. El Palomar, San Isidro',
      'av republica de panama 3635 lima',
    ]) {
      const r = validarDomicilioLegal(variante)
      expect(r.ok).toBe(false)
      if (r.ok) return
      expect(r.error).toMatch(/dirección de Avance Corp/)
    }
  })

  it('cuenta puntos de código, no unidades UTF-16, en los dos límites', () => {
    // Un emoji ocupa 2 unidades UTF-16 y 1 punto de código: si se midiera mal,
    // estas dos aserciones caerían del lado contrario.
    const justo = `Av. Lima 123 ${'x'.repeat(226)}😀`
    expect(Array.from(justo)).toHaveLength(240)
    expect(validarDomicilioLegal(justo)).toEqual({ ok: true, valor: justo })

    const pasado = `Av. Lima 123 ${'x'.repeat(227)}😀`
    expect(Array.from(pasado)).toHaveLength(241)
    expect(validarDomicilioLegal(pasado)).toEqual({
      ok: false,
      error: 'El domicilio legal debe tener entre 15 y 240 caracteres.',
    })
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

describe('hayCuentaEnLedger + la regla «al menos una» perdonada (rediseño tras veto Codex 2026-08-11)', () => {
  const cuentaLedger = (over: Partial<CuentaBancariaSeleccionable> = {}): CuentaBancariaSeleccionable => ({
    cuenta_id: 'cta-1',
    moneda: 'USD',
    banco: 'BBVA',
    tipo_cuenta: 'corriente',
    numero_cuenta: '72728282828282',
    cci: '27273827282828282828',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    origen: 'contrato',
    es_cuenta_perfil: false,
    creada_en: '2026-08-11T19:36:47.000Z',
    ...over,
  })

  it('cuenta la copia histórica del perfil y la de contrato; la fila es_cuenta_perfil NO cuenta (es la propia casilla)', () => {
    expect(hayCuentaEnLedger([cuentaLedger()])).toBe(true)
    expect(hayCuentaEnLedger([cuentaLedger({ origen: 'perfil' })])).toBe(true)
    expect(hayCuentaEnLedger([
      cuentaLedger({ cuenta_id: null, es_cuenta_perfil: true, origen: 'perfil', creada_en: null }),
    ])).toBe(false)
    expect(hayCuentaEnLedger([])).toBe(false)
  })

  it('ambas casillas vacías SIN respaldo del ledger: bloquea con el mensaje del portal (verbatim)', () => {
    const r = validarBancariosForm(seccion(), seccion(), { cuentaEnLedger: false })
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.error).toBe(
        'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
      )
    }
  })

  it('ambas casillas vacías CON cuenta en el ledger: pasa y el patch va TODO en null (perfiles intacto)', () => {
    // La clave anti-backfill: perdonar la regla JAMÁS copia la cuenta del
    // ledger a perfiles — el patch conserva las 14 columnas en null.
    const r = validarBancariosForm(seccion(), seccion(), { cuentaEnLedger: true })
    expect(r.ok).toBe(true)
    if (r.ok) {
      expect(r.bancarios.banco).toBeNull()
      expect(r.bancarios.numero_cuenta).toBeNull()
      expect(r.bancarios.cci).toBeNull()
      expect(r.bancarios.banco_usd).toBeNull()
      expect(r.bancarios.numero_cuenta_usd).toBeNull()
      expect(r.bancarios.cci_usd).toBeNull()
      expect(r.bancarios.titular_distinto).toBe(false)
      expect(r.bancarios.titular_distinto_usd).toBe(false)
    }
  })

  it('el ledger NO perdona una sección malformada: se corrige o se vacía, jamás pasa a medias', () => {
    const r = validarBancariosForm(seccion({ cci: '123' }), seccion(), { cuentaEnLedger: true })
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.error).toMatch(/Soles/)
  })

  it('sin opciones se comporta EXACTO como siempre (alta y conversión de lead intactas)', () => {
    const r = validarBancariosForm(seccion(), seccion())
    expect(r.ok).toBe(false)
  })
})

// ── Domicilio legal: las trampas invisibles (auditoría adversaria 2026-08-19) ──
// Un domicilio hecho de caracteres de ancho cero pasaba TODOS los controles
// —incluido el CHECK vivo de producción, comprobado— se imprimiría en el
// contrato como NADA, y cerraría el hueco para siempre: el domicilio no se
// puede volver a poner en NULL y la RPC nunca pisa uno existente.
describe('validarDomicilioLegal — lo que se imprimiría como nada', () => {
  const invisibles: [string, string][] = [
    ['espacio de ancho cero', '\u200B'],
    ['guion suave', '\u00AD'],
    ['unión de palabras', '\u2060'],
  ]
  for (const [nombre, caracter] of invisibles) {
    it(`rechaza un domicilio hecho solo de ${nombre}`, () => {
      const r = validarDomicilioLegal(caracter.repeat(6))
      expect(r.ok).toBe(false)
      if (r.ok) return
      expect(r.error).toMatch(/invisibles/)
    })
    it(`rechaza ${nombre} escondido dentro de una dirección con pinta legítima`, () => {
      const r = validarDomicilioLegal(`Av. Los Alamos${caracter} 123, San Isidro, Lima`)
      expect(r.ok).toBe(false)
    })
  }

  // U+FEFF es el caso raro: JavaScript lo considera espacio (\s y .trim() lo
  // comen) y PostgreSQL no. Cada lado lo neutraliza a su manera y ninguno lo
  // deja pasar a la impresión: el navegador lo NORMALIZA y manda el texto ya
  // limpio; el servidor, que no puede normalizarlo, lo RECHAZA. Se afirma el
  // comportamiento real de cada uno en vez de forzar una simetría falsa.
  it('el navegador limpia U+FEFF en vez de rechazarlo, y manda el texto ya sano', () => {
    expect(validarDomicilioLegal('\uFEFF'.repeat(6)).ok).toBe(false)
    const r = validarDomicilioLegal('Av. Los Alamos\uFEFF 123, San Isidro, Lima')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.valor).toBe('Av. Los Alamos 123, San Isidro, Lima')
    expect(r.valor).not.toMatch(/\uFEFF/)
  })

  // El servidor usa btrim (solo U+0020) y el navegador .trim() (todo el espacio
  // Unicode): sin normalizar, el mismo texto valía 4 caracteres aquí y 7 allí.
  it('normaliza los espacios exóticos para medir lo MISMO que el servidor', () => {
    expect(validarDomicilioLegal('\u00A0\u00A0Lima\u00A0').ok).toBe(false)
    const r = validarDomicilioLegal('Av.\u00A0\u00A0Grau   456,\u3000Lima')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.valor).toBe('Av. Grau 456, Lima')
  })

  // U+0085 (NEL) es un salto de línea, no un control a estos efectos:
  // PostgreSQL lo trata como espacio y lo colapsa (medido contra producción el
  // 2026-08-19), así que rechazarlo solo aquí rompía el espejo entre los tres
  // lados. Se normaliza igual que \n.
  it('normaliza U+0085 como espacio, igual que PostgreSQL', () => {
    const r = validarDomicilioLegal('Av. Lima 123\u0085San Isidro')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.valor).toBe('Av. Lima 123 San Isidro')
    expect(r.valor).not.toMatch(/\u0085/)
  })

  it('no toca las direcciones reales con tildes, guiones largos u ordinales', () => {
    const r = validarDomicilioLegal('  Jr. Ancash 999 — 2.º piso, Cercado, Lima  ')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.valor).toBe('Jr. Ancash 999 — 2.º piso, Cercado, Lima')
  })
})
