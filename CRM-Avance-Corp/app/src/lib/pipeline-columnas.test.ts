// Contrato de las COLUMNAS del tablero y de la «gestión vigente» (01/10/2026).
//
// Estas funciones son el ESPEJO demo de `crm.cartera_filtrada_fn(p_gestion)`.
// Lo que se prueba no es «el filtro funciona», sino que la demo y el servidor
// digan lo MISMO: cada divergencia es un tablero que enseña un producto que no
// existe. La mitad de los casos son NEGATIVOS a propósito: el riesgo de una
// columna calculada no es quedarse corta, es afirmar una gestión que nadie hizo.
import { describe, expect, it } from 'vitest'
import {
  COLOR_GESTIONADO,
  COLUMNAS_TABLERO,
  agruparPorColumna,
  columnaDeLead,
  destinosDeMovimiento,
  etapaAlSoltar,
  inicioTenencia,
  tieneGestionVigente,
  type ClaveColumna,
} from './pipeline-columnas'
import { SEMAFORO } from './semaforo'
import { ETAPAS, TERMINALES, TIPOS_CONTACTO, type Actividad, type Etapa, type Lead, type TipoActividad } from './tipos'

// Recibió el lead el 01/09 a mediodía de Lima; todo se mide contra ese instante.
const TENENCIA = '2026-09-01T12:00:00-05:00'
const ANTES = '2026-09-01T11:59:59-05:00'
const DESPUES = '2026-09-01T12:00:01-05:00'

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'ROSA QUISPE',
    telefono: '987654321',
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 1000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: '2026-08-20T10:00:00-05:00',
    tenencia_desde: TENENCIA,
    activo: true,
    ...over,
  }
}

let serie = 0
function act(tipo: TipoActividad, creado_en: string, lead_id = 'lead-1'): Actividad {
  serie += 1
  return { id: `act-${serie}`, lead_id, tipo, detalle: null, autor_nombre: 'ANALISTA', creado_en }
}

describe('COLUMNAS_TABLERO — cinco columnas sobre cuatro etapas', () => {
  it('«Gestionado» va entre «Nuevo» y «Contactado», y el resto conserva su orden', () => {
    expect(COLUMNAS_TABLERO.map((c) => c.k)).toEqual<ClaveColumna[]>([
      'nuevo', 'gestionado', 'contactado', 'reunion_agendada', 'propuesta_enviada',
    ])
    expect(COLUMNAS_TABLERO.map((c) => c.label)).toEqual([
      'Nuevo', 'Gestionado', 'Contactado', 'Cita agendada', 'Entrevista realizada',
    ])
  })

  it('NO añade una etapa: ETAPAS sigue siendo el espejo del CHECK de la base', () => {
    expect(ETAPAS.map((e) => e.k)).toEqual(['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada'])
    // «Gestionado» es una vista de `nuevo`: por dentro la etapa no cambia.
    expect(COLUMNAS_TABLERO.find((c) => c.k === 'gestionado')).toMatchObject({ etapa: 'nuevo' })
    expect(new Set(COLUMNAS_TABLERO.map((c) => c.etapa))).toEqual(new Set(ETAPAS.map((e) => e.k)))
  })

  it('solo la etapa `nuevo` se parte por gestión; las demás no mandan el recorte', () => {
    const recorte = Object.fromEntries(COLUMNAS_TABLERO.map((c) => [c.k, c.gestion]))
    expect(recorte).toEqual({
      nuevo: 'sin_gestion',
      gestionado: 'con_gestion',
      contactado: undefined,
      reunion_agendada: undefined,
      propuesta_enviada: undefined,
    })
    for (const c of COLUMNAS_TABLERO.filter((x) => x.etapa !== 'nuevo')) expect(c).not.toHaveProperty('gestion')
  })

  it('las etapas reales heredan rótulo y color de ETAPAS (fuente única)', () => {
    for (const e of ETAPAS) {
      expect(COLUMNAS_TABLERO.find((c) => c.k === e.k)).toMatchObject({ label: e.label, color: e.color, etapa: e.k })
    }
  })

  it('«Gestionado» es la única columna que no es destino: se llena sola', () => {
    expect(COLUMNAS_TABLERO.filter((c) => !c.esDestino).map((c) => c.k)).toEqual(['gestionado'])
  })
})

describe('COLOR_GESTIONADO — propio, legible y sin verde', () => {
  const canales = (hex: string) => [1, 3, 5].map((i) => Number.parseInt(hex.slice(i, i + 2), 16))
  const luminancia = (hex: string) => {
    const [r, g, b] = canales(hex).map((c) => {
      const s = c / 255
      return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
    }) as [number, number, number]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }
  const contraste = (a: string, b: string) => {
    const [alto, bajo] = [luminancia(a), luminancia(b)].sort((x, y) => y - x) as [number, number]
    return (alto + 0.05) / (bajo + 0.05)
  }
  const matiz = (hex: string) => {
    const [r, g, b] = canales(hex).map((c) => c / 255) as [number, number, number]
    const max = Math.max(r, g, b)
    const delta = max - Math.min(r, g, b)
    const h = max === r ? ((g - b) / delta) % 6 : max === g ? (b - r) / delta + 2 : (r - g) / delta + 4
    return (h * 60 + 360) % 360
  }

  it('no repite ningún color que ya signifique otra cosa en el tablero', () => {
    const ocupados = [...ETAPAS, ...TERMINALES].map((e) => e.color.toLowerCase())
    expect(ocupados).not.toContain(COLOR_GESTIONADO)
    expect(Object.values(SEMAFORO).map((c) => c.toLowerCase())).not.toContain(COLOR_GESTIONADO)
  })

  it('alcanza 4,5:1 como TEXTO sobre los fondos donde se pinta', () => {
    // Página, tarjeta y carril de la columna (navy al 3 % sobre el fondo).
    for (const fondo of ['#f6f8fc', '#ffffff', '#eff1f6']) {
      expect(contraste(COLOR_GESTIONADO, fondo)).toBeGreaterThanOrEqual(4.5)
    }
  })

  it('es un azul turquesa: lejos del verde y de los matices ya usados', () => {
    const h = matiz(COLOR_GESTIONADO)
    // El verde vive entre 80° y 170°; el CRM no lo usa.
    expect(h < 80 || h > 170).toBe(true)
    // Rojo (0°), ámbar (32°), azul (221°) y morado (262°), con margen.
    for (const [nombre, color] of [['rojo', '#dc2626'], ['ámbar', '#d97706'], ['azul', '#2563eb'], ['morado', '#7c3aed']] as const) {
      const distancia = Math.abs(h - matiz(color))
      expect(Math.min(distancia, 360 - distancia), nombre).toBeGreaterThanOrEqual(25)
    }
  })
})

describe('tieneGestionVigente — espejo de p_gestion', () => {
  it.each(TIPOS_CONTACTO)('un contacto (%s) desde que el titular lo recibió SÍ es gestión', (tipo) => {
    expect(tieneGestionVigente(lead(), [act(tipo, DESPUES)])).toBe(true)
  })

  it('una NOTA no cuenta: escribir no es haber intentado contactar', () => {
    expect(tieneGestionVigente(lead(), [act('nota', DESPUES)])).toBe(false)
  })

  it.each(['cambio_etapa', 'reasignacion', 'conversion'] as const)(
    'lo que emite el SISTEMA (%s) tampoco es gestión',
    (tipo) => {
      expect(tieneGestionVigente(lead(), [act(tipo, DESPUES)])).toBe(false)
    },
  )

  it('una actividad ANTERIOR a la tenencia no cuenta: la hizo otro analista', () => {
    expect(tieneGestionVigente(lead(), [act('llamada_no_contestada', ANTES)])).toBe(false)
  })

  it('el instante exacto de la tenencia ya cuenta (>=, como el servidor)', () => {
    expect(tieneGestionVigente(lead(), [act('whatsapp_enviado', TENENCIA)])).toBe(true)
  })

  it('basta UNA gestión vigente aunque el resto del historial sea viejo', () => {
    expect(tieneGestionVigente(lead(), [
      act('llamada_no_contestada', ANTES),
      act('nota', DESPUES),
      act('whatsapp_enviado', DESPUES),
    ])).toBe(true)
  })

  it('SIN titular no hay gestión, aunque el lead tenga intentos y esté en una bandeja', () => {
    const parkeado = lead({ vendedor_id: null, asignado_supervisor_id: 'sup-1' })
    expect(tieneGestionVigente(parkeado, [act('llamada_no_contestada', DESPUES)])).toBe(false)
  })

  it('las actividades de OTRO lead no cuentan', () => {
    expect(tieneGestionVigente(lead(), [act('llamada_no_contestada', DESPUES, 'lead-2')])).toBe(false)
  })

  it('compara INSTANTES, no texto: 16:30Z es 11:30 de Lima, antes del mediodía', () => {
    // Como cadena, «…T16:30…Z» es mayor que «…T12:00…-05:00»; como instante, es anterior.
    expect(tieneGestionVigente(lead(), [act('llamada_no_contestada', '2026-09-01T16:30:00.000Z')])).toBe(false)
    expect(tieneGestionVigente(lead(), [act('llamada_no_contestada', '2026-09-01T17:30:00.000Z')])).toBe(true)
  })

  it('una fecha de actividad ilegible no se da por gestión', () => {
    expect(tieneGestionVigente(lead(), [act('llamada_no_contestada', 'no-es-fecha')])).toBe(false)
  })
})

// Regla del servidor (01/10): `and not (g.metadata ? 'deshecho_en')`. Un
// resultado de llamada deshecho «no ocurrió»: el lead vuelve a «Nuevo».
describe('tieneGestionVigente — un resultado de llamada DESHECHO no cuenta', () => {
  const deshecha = (over: Partial<Actividad> = {}): Actividad => ({
    ...act('llamada_no_contestada', DESPUES),
    metadata: { evento: 'resultado_llamada', resultado: 'no_contesto', deshecho_en: '2026-09-01T13:00:00-05:00' },
    ...over,
  })

  it('si el único intento está deshecho, no hay gestión: «Nuevo»', () => {
    expect(tieneGestionVigente(lead(), [deshecha()])).toBe(false)
    expect(columnaDeLead(lead(), [deshecha()])).toBe('nuevo')
  })

  it('un intento deshecho más OTRO válido en la tenencia sí es gestión', () => {
    expect(tieneGestionVigente(lead(), [deshecha(), act('whatsapp_enviado', DESPUES)])).toBe(true)
    expect(columnaDeLead(lead(), [deshecha(), act('whatsapp_enviado', DESPUES)])).toBe('gestionado')
  })

  it('un intento deshecho más otro válido pero ANTERIOR a la tenencia sigue sin gestión', () => {
    expect(tieneGestionVigente(lead(), [deshecha(), act('whatsapp_enviado', ANTES)])).toBe(false)
  })

  it('todos los intentos deshechos: sin gestión', () => {
    expect(tieneGestionVigente(lead(), [deshecha(), deshecha({ tipo: 'llamada_realizada' })])).toBe(false)
  })

  it('basta con que la clave exista, como el `?` de jsonb: también con valor nulo', () => {
    expect(tieneGestionVigente(lead(), [deshecha({ metadata: { deshecho_en: null } })])).toBe(false)
  })

  it('otra metadata —o una clave `deshecho_en` que no viaja— no anula la gestión', () => {
    // El resultado tipificado de una llamada viva lleva metadata, y cuenta.
    expect(tieneGestionVigente(lead(), [deshecha({ metadata: { evento: 'resultado_llamada', resultado: 'no_contesto' } })])).toBe(true)
    // `undefined` no existe en JSON: el servidor no vería la clave.
    expect(tieneGestionVigente(lead(), [deshecha({ metadata: { deshecho_en: undefined } })])).toBe(true)
    expect(tieneGestionVigente(lead(), [deshecha({ metadata: {} })])).toBe(true)
  })

  it('NO se deduce de un sello de último contacto: el lead lo trae posterior a su tenencia y aun así es «Nuevo»', () => {
    // La llamada existió (por eso hay `ultimo_contacto_en`) y se deshizo.
    const conSello = lead({ ultimo_contacto_en: DESPUES })
    expect(columnaDeLead(conSello, [deshecha()])).toBe('nuevo')
    expect(columnaDeLead(conSello, [])).toBe('nuevo')
  })
})

describe('inicioTenencia — el reloj del titular actual (criterio demo)', () => {
  const ms = (iso: string) => Date.parse(iso)

  it('con `tenencia_desde`, manda ese sello', () => {
    expect(inicioTenencia(lead(), [])).toBe(ms(TENENCIA))
  })

  // Campo AUSENTE y nulo EXPLÍCITO no son lo mismo. El demo no trae el campo
  // (respaldo: `creado_en`); un `null` es el servidor diciendo «sin tenencia».
  it('campo AUSENTE (modo demo): cae a `creado_en`, como los demás espejos demo', () => {
    const { tenencia_desde: _sello, ...demo } = lead()
    expect('tenencia_desde' in demo).toBe(false)
    expect(inicioTenencia(demo, [])).toBe(ms(demo.creado_en))
    // Y con ese respaldo el intento posterior al alta SÍ es gestión.
    expect(tieneGestionVigente(demo, [act('llamada_no_contestada', DESPUES)])).toBe(true)
  })

  it('nulo EXPLÍCITO: conserva su significado de contrato — sin tenencia no hay gestión', () => {
    const sinTenencia = lead({ tenencia_desde: null })
    expect(inicioTenencia(sinTenencia, [])).toBeNaN()
    // Ni `creado_en` ni el timeline la inventan: tiene titular e intentos, y sigue «Nuevo».
    expect(tieneGestionVigente(sinTenencia, [act('llamada_no_contestada', DESPUES)])).toBe(false)
    expect(inicioTenencia(sinTenencia, [act('reasignacion', '2026-09-10T09:00:00-05:00')])).toBeNaN()
    expect(columnaDeLead(sinTenencia, [act('reasignacion', '2026-09-10T09:00:00-05:00'), act('whatsapp_enviado', '2026-09-11T09:00:00-05:00')])).toBe('nuevo')
  })

  it('un sello presente pero ilegible no se sustituye por `creado_en`: no hay reloj, no hay gestión', () => {
    const roto = lead({ tenencia_desde: 'roto' })
    expect(inicioTenencia(roto, [])).toBeNaN()
    expect(tieneGestionVigente(roto, [act('llamada_no_contestada', DESPUES)])).toBe(false)
    // El tablero no se rompe: el lead cae en «Nuevo».
    expect(columnaDeLead(roto, [act('llamada_no_contestada', DESPUES)])).toBe('nuevo')
  })

  it('una reasignación POSTERIOR en el timeline reinicia el reloj (el demo no sella la tenencia)', () => {
    const { tenencia_desde: _sello, ...demo } = lead()
    const reasignado = '2026-09-10T09:00:00-05:00'
    expect(inicioTenencia(demo, [act('reasignacion', reasignado)])).toBe(ms(reasignado))
    // …y también gana sobre un sello que el demo dejó viejo.
    expect(inicioTenencia(lead(), [act('reasignacion', reasignado)])).toBe(ms(reasignado))
  })

  it('una reasignación ANTERIOR al sello no lo hace retroceder', () => {
    expect(inicioTenencia(lead(), [act('reasignacion', '2026-08-25T09:00:00-05:00')])).toBe(ms(TENENCIA))
  })

  it('de varias reasignaciones manda la última, y las de otro lead se ignoran', () => {
    const ultima = '2026-09-12T09:00:00-05:00'
    expect(inicioTenencia(lead(), [
      act('reasignacion', '2026-09-05T09:00:00-05:00'),
      act('reasignacion', ultima),
      act('reasignacion', '2026-09-20T09:00:00-05:00', 'lead-2'),
    ])).toBe(ms(ultima))
  })

  // El servidor también reinicia la tenencia al REABRIR un descartado. El store
  // demo lo deja escrito como un `cambio_etapa` «Descartado → …».
  it('una reapertura reinicia el reloj; cerrar o avanzar de etapa, no', () => {
    const { tenencia_desde: _sello, ...demo } = lead()
    const reabierto = '2026-09-10T09:00:00-05:00'
    const cambio = (detalle: string | null) => ({ ...act('cambio_etapa', reabierto), detalle })

    expect(inicioTenencia(demo, [cambio('Descartado → Nuevo')])).toBe(ms(reabierto))
    // Deshacer un descarte lo devuelve a su etapa anterior: también es reabrir.
    expect(inicioTenencia(demo, [cambio('Descartado → Contactado')])).toBe(ms(reabierto))
    // Lo que NO abre una tenencia: descartar, avanzar, o un cambio sin detalle.
    for (const detalle of ['Contactado → Descartado · Motivo: Sin fondos', 'Nuevo → Contactado', 'Nuevo → Descartado', null]) {
      expect(inicioTenencia(demo, [cambio(detalle)]), String(detalle)).toBe(ms(demo.creado_en))
    }
  })

  it('reabierto en demo, lo que se intentó antes del descarte ya no cuenta', () => {
    const { tenencia_desde: _sello, ...demo } = lead()
    const intento = act('llamada_no_contestada', '2026-09-02T10:00:00-05:00')
    const descarte = { ...act('cambio_etapa', '2026-09-03T10:00:00-05:00'), detalle: 'Nuevo → Descartado · Motivo: No responde' }
    const reapertura = { ...act('cambio_etapa', '2026-09-10T09:00:00-05:00'), detalle: 'Descartado → Nuevo' }

    expect(columnaDeLead(demo, [intento, descarte])).toBe('gestionado')
    expect(columnaDeLead(demo, [intento, descarte, reapertura])).toBe('nuevo')
    expect(columnaDeLead(demo, [intento, descarte, reapertura, act('whatsapp_enviado', '2026-09-10T15:00:00-05:00')])).toBe('gestionado')
  })

  it('sin ninguna fecha legible no hay reloj (NaN) y no se afirma gestión', () => {
    const { tenencia_desde: _sello, ...sinReloj } = lead({ creado_en: 'roto' })
    expect(inicioTenencia(sinReloj, [])).toBeNaN()
    expect(tieneGestionVigente(sinReloj, [act('llamada_no_contestada', DESPUES)])).toBe(false)
  })

  it('DECISIÓN DE MIGUEL: reasignado en demo, lo que intentó el analista anterior ya no cuenta', () => {
    const { tenencia_desde: _sello, ...demo } = lead()
    const intentoAnterior = act('llamada_no_contestada', '2026-09-02T10:00:00-05:00')
    const reasignacion = act('reasignacion', '2026-09-10T09:00:00-05:00')
    expect(tieneGestionVigente(demo, [intentoAnterior])).toBe(true)
    // Cambia de mano: vuelve a ser «Nuevo» para quien lo recibe…
    expect(tieneGestionVigente(demo, [intentoAnterior, reasignacion])).toBe(false)
    // …hasta que el titular ACTUAL lo intenta.
    const intentoNuevo = act('whatsapp_enviado', '2026-09-10T15:00:00-05:00')
    expect(tieneGestionVigente(demo, [intentoAnterior, reasignacion, intentoNuevo])).toBe(true)
  })
})

describe('columnaDeLead — dónde cae cada tarjeta en la demo', () => {
  it('`nuevo` sin gestión vigente → «Nuevo»', () => {
    expect(columnaDeLead(lead(), [])).toBe('nuevo')
    expect(columnaDeLead(lead(), [act('nota', DESPUES)])).toBe('nuevo')
    expect(columnaDeLead(lead(), [act('llamada_no_contestada', ANTES)])).toBe('nuevo')
  })

  it('`nuevo` con un intento vigente → «Gestionado»', () => {
    expect(columnaDeLead(lead(), [act('llamada_no_contestada', DESPUES)])).toBe('gestionado')
    expect(columnaDeLead(lead(), [act('whatsapp_enviado', DESPUES)])).toBe('gestionado')
  })

  it('`nuevo` sin titular → «Nuevo», tenga lo que tenga en el timeline', () => {
    expect(columnaDeLead(lead({ vendedor_id: null }), [act('whatsapp_enviado', DESPUES)])).toBe('nuevo')
  })

  it.each(['contactado', 'reunion_agendada', 'propuesta_enviada'] as const)(
    'las demás etapas (%s) van a su columna: la gestión solo parte `nuevo`',
    (etapa) => {
      expect(columnaDeLead(lead({ etapa }), [])).toBe(etapa)
      expect(columnaDeLead(lead({ etapa }), [act('llamada_no_contestada', DESPUES)])).toBe(etapa)
    },
  )

  it.each(['convertido', 'descartado'] as const)('un lead cerrado (%s) no va en el tablero', (etapa) => {
    expect(columnaDeLead(lead({ etapa }), [act('llamada_realizada', DESPUES)])).toBeNull()
  })

  it('un lead dado de baja no va en el tablero', () => {
    expect(columnaDeLead(lead({ activo: false }), [])).toBeNull()
  })

  it('una etapa que el tablero no conoce no se cuela en ninguna columna', () => {
    expect(columnaDeLead(lead({ etapa: 'archivado' as Etapa }), [])).toBeNull()
  })
})

describe('agruparPorColumna — el tablero demo de una pasada', () => {
  const leads = [
    lead({ id: 'a' }),
    lead({ id: 'b' }),
    lead({ id: 'c', etapa: 'contactado' }),
    lead({ id: 'd', etapa: 'convertido' }),
    lead({ id: 'e', vendedor_id: null }),
    lead({ id: 'f', etapa: 'propuesta_enviada' }),
    lead({ id: 'g' }),
  ]
  const actividades = [
    act('llamada_no_contestada', DESPUES, 'b'),
    act('llamada_realizada', DESPUES, 'c'),
    act('whatsapp_enviado', DESPUES, 'e'),
    act('nota', DESPUES, 'a'),
    act('whatsapp_enviado', ANTES, 'g'),
  ]

  it('cada lead cae en UNA sola columna y los cerrados quedan fuera', () => {
    const columnas = agruparPorColumna(leads, actividades)
    expect(Object.fromEntries(Object.entries(columnas).map(([k, v]) => [k, v.map((l) => l.id)]))).toEqual({
      nuevo: ['a', 'e', 'g'],
      gestionado: ['b'],
      contactado: ['c'],
      reunion_agendada: [],
      propuesta_enviada: ['f'],
    })
    const repartidos = Object.values(columnas).flat().map((l) => l.id)
    expect(new Set(repartidos).size).toBe(repartidos.length)
  })

  it('coincide con `columnaDeLead` lead por lead (no hay dos reglas)', () => {
    const columnas = agruparPorColumna(leads, actividades)
    for (const l of leads) {
      const k = columnaDeLead(l, actividades)
      for (const c of COLUMNAS_TABLERO) expect(columnas[c.k].includes(l)).toBe(c.k === k)
    }
  })

  it('sin leads devuelve las cinco columnas vacías, no un objeto a medias', () => {
    expect(agruparPorColumna([], actividades)).toEqual({
      nuevo: [], gestionado: [], contactado: [], reunion_agendada: [], propuesta_enviada: [],
    })
  })
})

describe('reglas de arrastre y del menú «Mover a»', () => {
  const columna = (k: ClaveColumna) => COLUMNAS_TABLERO.find((c) => c.k === k)!

  it('una tarjeta de «Gestionado» se mueve como una de «Nuevo»: es etapa `nuevo`', () => {
    for (const destino of ['contactado', 'reunion_agendada', 'propuesta_enviada'] as const) {
      expect(etapaAlSoltar(lead({ etapa: 'nuevo' }), columna(destino))).toBe(destino)
    }
  })

  it('«Gestionado» NUNCA es destino, venga la tarjeta de donde venga', () => {
    for (const etapa of ['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada'] as const) {
      expect(etapaAlSoltar(lead({ etapa }), columna('gestionado'))).toBeNull()
    }
  })

  it('soltar entre «Nuevo» y «Gestionado» no es un cambio de etapa: no pasa nada', () => {
    // De «Gestionado» a «Nuevo»: el lead ya tiene etapa `nuevo`.
    expect(etapaAlSoltar(lead({ etapa: 'nuevo' }), columna('nuevo'))).toBeNull()
    // De «Nuevo» a «Gestionado»: no es destino.
    expect(etapaAlSoltar(lead({ etapa: 'nuevo' }), columna('gestionado'))).toBeNull()
  })

  it('soltar una tarjeta en su propia columna tampoco hace nada', () => {
    expect(etapaAlSoltar(lead({ etapa: 'contactado' }), columna('contactado'))).toBeNull()
  })

  it('devolver un lead a «Nuevo» sigue siendo posible desde las etapas siguientes', () => {
    expect(etapaAlSoltar(lead({ etapa: 'contactado' }), columna('nuevo'))).toBe('nuevo')
  })

  it('el menú «Mover a» no ofrece «Gestionado» ni la etapa en la que ya está', () => {
    expect(destinosDeMovimiento(lead({ etapa: 'nuevo' })).map((c) => c.k)).toEqual([
      'contactado', 'reunion_agendada', 'propuesta_enviada',
    ])
    expect(destinosDeMovimiento(lead({ etapa: 'contactado' })).map((c) => c.k)).toEqual([
      'nuevo', 'reunion_agendada', 'propuesta_enviada',
    ])
    for (const etapa of ['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada'] as const) {
      expect(destinosDeMovimiento(lead({ etapa })).map((c) => c.k)).not.toContain('gestionado')
    }
  })
})
