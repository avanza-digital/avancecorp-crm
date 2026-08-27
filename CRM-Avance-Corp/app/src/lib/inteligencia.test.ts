import { describe, expect, it } from 'vitest'
import {
  capitalPrincipal,
  colaDe,
  colorMeta,
  comparativaEquipos,
  diasSinActividad,
  diasTxt,
  duracionTexto,
  redactarMotivoCola,
  estancados,
  haceCortoTexto,
  haceTexto,
  indexarUltimaActividad,
  metricasPorVendedor,
  sinProximaAccion,
} from './inteligencia'
import { money } from './format'
import type { EstadoSlaLead } from './sla-versionado'
import type { Actividad, Lead, Miembro } from './tipos'

const DIA_MS = 86_400_000
const AHORA = Date.UTC(2026, 6, 10, 12)
const haceDias = (dias: number) => new Date(AHORA - dias * DIA_MS).toISOString()

const baseLead: Lead = {
  id: 'lead-base',
  nombre_completo: 'CLIENTE PRUEBA',
  telefono: '+51999999999',
  etapa: 'nuevo',
  origen: 'referido',
  monto_estimado: 10_000,
  moneda: 'PEN',
  vendedor_id: 'v1',
  creado_en: haceDias(1),
  activo: true,
}

const lead = (cambios: Partial<Lead>): Lead => ({ ...baseLead, ...cambios })

const actividad = (
  leadId: string,
  dias: number,
  cambios: Partial<Actividad> = {},
): Actividad => ({
  id: `act-${leadId}-${dias}`,
  lead_id: leadId,
  tipo: 'nota',
  detalle: null,
  autor_nombre: 'VENDEDOR',
  creado_en: haceDias(dias),
  ...cambios,
})

const miembro = (perfilId: string, cambios: Partial<Miembro> = {}): Miembro => ({
  perfil_id: perfilId,
  nombre_completo: perfilId.toUpperCase(),
  rol_crm: 'vendedor',
  activo: true,
  ...cambios,
})

const estadoSla = (
  leadId: string,
  cambios: Partial<EstadoSlaLead> = {},
): EstadoSlaLead => ({
  lead_id: leadId,
  ciclo_politica_id: '00000000-0000-4000-8000-000000000001',
  ciclo_politica_version: 2,
  primera_gestion_limite_en: haceDias(1),
  primera_gestion_en: null,
  primer_contacto_limite_en: haceDias(0.5),
  primer_contacto_en: null,
  ciclo_aproximado: false,
  asignacion_id: '00000000-0000-4000-8000-000000000002',
  asignacion_politica_id: '00000000-0000-4000-8000-000000000001',
  asignacion_politica_version: 2,
  asignacion_primera_gestion_limite_en: haceDias(1),
  asignacion_primera_gestion_en: null,
  asignacion_primer_contacto_limite_en: haceDias(0.5),
  asignacion_primer_contacto_en: null,
  etapa_politica_id: null,
  etapa_politica_version: null,
  etapa: null,
  etapa_iniciada_en: null,
  etapa_limite_en: null,
  etapa_objetivo_minutos: null,
  etapa_aproximada: null,
  ...cambios,
})

describe('tiempo e índices de actividad', () => {
  it('indexa la última actividad por lead aunque llegue desordenada', () => {
    const anterior = actividad('l1', 4)
    const reciente = actividad('l1', 1)
    const ajena = actividad('l2', 0.5)

    expect(indexarUltimaActividad([reciente, anterior, ajena])).toEqual(
      new Map([
        ['l1', reciente],
        ['l2', ajena],
      ]),
    )
    expect(indexarUltimaActividad([ajena]).get('sin-actividad')).toBeUndefined()
  })

  it('calcula desde la actividad o creación y nunca devuelve días negativos', () => {
    const l1 = lead({ id: 'l1', creado_en: haceDias(5) })
    expect(diasSinActividad(l1, [actividad('l1', 2.5)], AHORA)).toBe(2.5)
    expect(diasSinActividad(l1, [], AHORA)).toBe(5)
    expect(diasSinActividad(lead({ creado_en: 'invalida' }), [], AHORA)).toBe(0)
    expect(diasSinActividad(lead({ creado_en: new Date(AHORA + DIA_MS).toISOString() }), [], AHORA)).toBe(0)
  })
})

describe('señales comerciales', () => {
  it.each([
    [39.9, '#dc2626'],
    [40, '#d97706'],
    [74.9, '#d97706'],
    [75, '#2563eb'],
    [120, '#2563eb'],
  ] as const)('asigna el semáforo de meta para %s%%', (pct, color) => {
    expect(colorMeta(pct)).toBe(color)
  })

  it('clasifica una sola acción por lead y ordena por severidad y antigüedad', () => {
    const leads = [
      lead({ id: 'sin-responder', creado_en: haceDias(2) }),
      lead({ id: 'por-repartir', etapa: 'contactado', vendedor_id: null, creado_en: haceDias(1) }),
      lead({ id: 'propuesta', etapa: 'propuesta_enviada', creado_en: haceDias(8) }),
      lead({ id: 'seguimiento', etapa: 'contactado', creado_en: haceDias(7) }),
      lead({ id: 'fresco', etapa: 'contactado', creado_en: haceDias(2) }),
      lead({ id: 'convertido', etapa: 'convertido', creado_en: haceDias(20) }),
      lead({ id: 'inactivo', activo: false, creado_en: haceDias(20) }),
    ]
    const acts = [
      actividad('propuesta', 6),
      actividad('seguimiento', 4),
      actividad('fresco', 1),
    ]

    const cola = colaDe(
      leads,
      acts,
      AHORA,
      undefined,
      new Map([['sin-responder', estadoSla('sin-responder')]]),
    )

    expect(cola.map((item) => [item.lead.id, item.bucket, item.sev])).toEqual([
      ['sin-responder', 'sin_responder', 'critica'],
      ['por-repartir', 'por_repartir', 'critica'],
      ['propuesta', 'propuesta_sin_respuesta', 'media'],
      ['seguimiento', 'seguimiento', 'baja'],
    ])
    expect(cola[0]?.motivo).toContain('hace 2 días')
    expect(cola[1]?.motivo).toContain('hace 1 día')
  })

  it('dice minutos y horas antes de completar el primer día (antes: «hace horas» plano)', () => {
    const seisHoras = colaDe([lead({ id: 'horas', creado_en: haceDias(0.25) })], [], AHORA)
    expect(seisHoras[0]).toMatchObject({ bucket: 'sin_responder', sev: 'media' })
    expect(seisHoras[0]?.motivo).toContain('hace 6 horas')

    // El caso del bug de Miguel (2026-08-16): un lead repartido hace MINUTOS
    // decía «Entró hace horas y nadie lo ha contactado».
    const minutos = colaDe([lead({ id: 'min', creado_en: haceDias(6 / 1440) })], [], AHORA)
    expect(minutos[0]?.motivo).toContain('hace 6 minutos')

    const recien = colaDe([lead({ id: 'recien', creado_en: haceDias(0.0005) })], [], AHORA)
    expect(recien[0]?.motivo).toContain('hace un momento')
  })

  // La escala única del tiempo relativo (2026-08-16). Antes TODO lo sub-diario
  // colapsaba en la cadena literal «hace horas» — y el colapso estaba copiado
  // en cuatro pantallas más ('hoy', 'hace minutos'…). Mutante que debe morir
  // aquí: restaurar `if (dias < 1) return 'hace horas'` en haceTexto.
  describe('haceTexto / duracionTexto — la escala única', () => {
    it('bordes: momento → minutos → horas → días', () => {
      expect(haceTexto(0)).toBe('hace un momento')
      expect(haceTexto(59 / 86_400)).toBe('hace un momento')
      expect(haceTexto(60 / 86_400)).toBe('hace 1 minuto')
      expect(haceTexto(59.4 / 1440)).toBe('hace 59 minutos')
      expect(haceTexto(1 / 24)).toBe('hace 1 hora')
      expect(haceTexto(23.9 / 24)).toBe('hace 23 horas')
      // El tramo ≥ 1 día es EL de siempre, byte a byte.
      expect(haceTexto(1)).toBe('hace 1 día')
      expect(haceTexto(2.5)).toBe('hace 2 días')
    })

    it('13 minutos exactos NO pierden un minuto por coma flotante', () => {
      // 780000 ms / DIA_MS × 1440 = 12.999999999999998: sin redondear a
      // SEGUNDO antes de trocear, el floor diría «hace 12 minutos». Pasa en
      // 83 de los 1440 minutos exactos (13, 26, 49, 52…). Mutante que debe
      // morir: `Math.floor(dias * 1440)` directo en vez de pasar por segundos.
      expect(haceTexto(780_000 / DIA_MS)).toBe('hace 13 minutos')
    })

    it('lo raro cae al suelo, nunca a un número inventado', () => {
      expect(haceTexto(-0.5)).toBe('hace un momento')
      expect(haceTexto(Number.NaN)).toBe('hace un momento')
      expect(duracionTexto(0)).toBe('menos de un minuto')
      expect(duracionTexto(45 / 1440)).toBe('45 minutos')
    })

    it('la redacción aprobada por Miguel (2026-08-16), palabra por palabra', () => {
      // Con vencimiento el estado del contacto ya está dicho — no se repite.
      expect(redactarMotivoCola('sin_responder', 2 / 1440, 'nuevo', { gestion_vencida: true }))
        .toBe('Venció la primera gestión · entró hace 2 minutos')
      expect(redactarMotivoCola('sin_responder', 25 / 1440, 'nuevo', { contacto_vencido: true }))
        .toBe('Venció el primer contacto · entró hace 25 minutos')
      // La de dos relojes conserva los dos aunque haya vencimiento.
      expect(redactarMotivoCola('sin_responder', 2, 'nuevo', { espera_cliente_dias: 6, contacto_vencido: true }))
        .toBe('Venció el primer contacto · Asignado hace 2 días · el cliente escribió hace 6 días')
      expect(redactarMotivoCola('insistir', 1, 'nuevo', { ultimo_intento_dias: 40 / 1440 }))
        .toBe('Último intento hace 40 minutos, sin respuesta — cambia de canal')
      expect(redactarMotivoCola('propuesta_sin_respuesta', 5, 'propuesta_enviada', {}))
        .toBe('Propuesta enviada hace 5 días y sin respuesta')
    })

    it('diasTxt/haceCortoTexto: misma escala, abreviada («hoy» ya no tapa 24 horas)', () => {
      expect(diasTxt(0.5 / 1440)).toBe('recién')
      expect(diasTxt(40 / 1440)).toBe('40 min')
      expect(diasTxt(5 / 24)).toBe('5 h')
      expect(diasTxt(3.7)).toBe('3 d') // el tramo ≥ 1 día, idéntico al de siempre
      expect(haceCortoTexto(40 / 1440)).toBe('hace 40 min')
      expect(haceCortoTexto(0)).toBe('recién')
    })
  })

  // El reloj del asesor (pedido de Miguel, 2026-07-24): con el circuito vivo un
  // lead pasa días en la cola de Rosa y en la bandeja del supervisor antes de
  // llegar a un vendedor. Medir desde `creado_en` lo pintaba en rojo el primer
  // segundo que lo veía.
  describe('mide la espera ante el DUEÑO ACTUAL, no desde que entró el lead', () => {
    it('un lead viejo recién asignado NO nace en crítico', () => {
      const cola = colaDe(
        [lead({ id: 'recien', creado_en: haceDias(3), tenencia_desde: haceDias(0.02) })],
        [],
        AHORA,
      )
      expect(cola[0]).toMatchObject({ bucket: 'sin_responder', sev: 'media' })
      // …pero la espera del CLIENTE no se esconde: va en el mismo motivo.
      // (0.02 días = 1728 s = 28.8 min; floor por tramo → 28.)
      expect(cola[0]?.motivo).toContain('Asignado hace 28 minutos')
      expect(cola[0]?.motivo).toContain('el cliente escribió hace 3 días')
    })

    it('el snapshot de la asignación vuelve crítico el SLA vencido', () => {
      const cola = colaDe(
        [lead({ id: 'moroso', creado_en: haceDias(5), tenencia_desde: haceDias(2) })],
        [],
        AHORA,
        undefined,
        new Map([['moroso', estadoSla('moroso')]]),
      )
      expect(cola[0]).toMatchObject({ bucket: 'sin_responder', sev: 'critica' })
      expect(cola[0]?.dias).toBeCloseTo(2)
    })

    it('sin dueño (cola de Rosa) sigue midiéndose desde que entró', () => {
      const cola = colaDe(
        [lead({ id: 'sin-duenio', vendedor_id: null, creado_en: haceDias(4) })],
        [],
        AHORA,
      )
      expect(cola[0]).toMatchObject({ bucket: 'por_repartir', sev: 'critica' })
      expect(cola[0]?.dias).toBeCloseTo(4)
    })

    it('el transferido no le hereda al nuevo dueño la mora del anterior', () => {
      // Actividad vieja del asesor previo + transferencia reciente: manda la
      // transferencia (el MÁXIMO de las dos referencias).
      const cola = colaDe(
        [lead({ id: 'transferido', etapa: 'contactado', creado_en: haceDias(30), tenencia_desde: haceDias(0.5) })],
        [actividad('transferido', 20)],
        AHORA,
      )
      expect(cola).toHaveLength(0) // 0.5 días de tenencia < los 3 de seguimiento
    })

    it('sin fotografía SLA conserva la cola pero no inventa severidad crítica', () => {
      const cola = colaDe([lead({ id: 'legacy', creado_en: haceDias(2) })], [], AHORA)
      expect(cola[0]).toMatchObject({ bucket: 'sin_responder', sev: 'media' })
      expect(cola[0]?.motivo).toBe('Entró hace 2 días · primer contacto pendiente')
    })

    it('un ISO corrupto degrada a la referencia de siempre en vez de romper la cola', () => {
      const cola = colaDe(
        [lead({ id: 'corrupto', creado_en: haceDias(2), tenencia_desde: 'no-es-fecha' })],
        [],
        AHORA,
      )
      expect(cola[0]).toMatchObject({ bucket: 'sin_responder', sev: 'media' })
      expect(cola[0]?.dias).toBeCloseTo(2)
    })
  })

  // Auditoría 2026-07-25 (hallazgo crítico verificado en prod): el timeline se
  // llena de actividades que emite el SISTEMA. Como la cola preguntaba "¿tiene
  // ALGUNA actividad?", TODO lead repartido salía de la cola en el instante en
  // que se asignaba — llegaba con su `reasignacion` puesta. El vendedor veía
  // "Al día ✦ sin pendientes" sobre un lead que nadie había llamado.
  describe('solo el CONTACTO REAL saca un lead de la cola', () => {
    // El caso EXACTO de producción: el trigger del servidor escribe la
    // `reasignacion` con el mismo instante que `tenencia_desde`.
    const asignadoHace = (dias: number) => ({
      lead: lead({ id: 'repartido', creado_en: haceDias(3), tenencia_desde: haceDias(dias) }),
      acts: [actividad('repartido', dias, { tipo: 'reasignacion' })],
    })

    it('un lead recién repartido SIGUE en sin_responder pese a su actividad de reasignación', () => {
      const { lead: l, acts } = asignadoHace(0.02)
      const cola = colaDe([l], acts, AHORA)
      expect(cola[0]).toMatchObject({ bucket: 'sin_responder', sev: 'media' })
      expect(cola[0]?.motivo).toContain('el cliente escribió hace 3 días')
    })

    it('un cambio de etapa automático tampoco cuenta como haberlo contactado', () => {
      const cola = colaDe(
        [lead({ id: 'movido', creado_en: haceDias(3), tenencia_desde: haceDias(2) })],
        [actividad('movido', 1, { tipo: 'cambio_etapa' })],
        AHORA,
      )
      expect(cola[0]).toMatchObject({ bucket: 'sin_responder', sev: 'media' })
    })

    it('una nota interna tampoco: escribirla no es haber hablado con la persona', () => {
      const cola = colaDe(
        [lead({ id: 'anotado', creado_en: haceDias(3), tenencia_desde: haceDias(2) })],
        [actividad('anotado', 1, { tipo: 'nota' })],
        AHORA,
      )
      expect(cola[0]).toMatchObject({ bucket: 'sin_responder', sev: 'media' })
    })

    it.each([
      'llamada_realizada',
      'llamada_no_contestada',
      'whatsapp_enviado',
      'whatsapp_recibido',
      'reunion_realizada',
    ] as const)('una %s SÍ lo saca de sin_responder', (tipo) => {
      const cola = colaDe(
        [lead({ id: 'contactado-ya', creado_en: haceDias(3), tenencia_desde: haceDias(2) })],
        [actividad('contactado-ya', 1, { tipo })],
        AHORA,
      )
      // Etapa 'nuevo' con contacto ya no es speed-to-lead; y sin ser
      // contactado/propuesta tampoco cae en los buckets por inactividad.
      expect(cola.find((i) => i.lead.id === 'contactado-ya')?.bucket).not.toBe('sin_responder')
    })

    // Segunda mitad del mismo agujero (auditoría 2026-07-25). Arreglar el
    // índice de contacto salvó al lead recién repartido, pero dejó vivo el
    // caso de al lado: el `nuevo` al que YA se intentó llamar no caía en
    // NINGÚN bucket — `sin_responder` exige `!ultima` y los otros tres solo
    // miran contactado/reunion_agendada/propuesta_enviada. Bastaba pulsar "No
    // contestó" una vez para que el lead se evaporara de la cola para siempre.
    describe('el lead ya intentado vuelve a la cola en vez de evaporarse', () => {
      const intentado = (tipo: 'llamada_no_contestada' | 'whatsapp_enviado', dias: number) =>
        colaDe(
          [lead({ id: 'insistir', creado_en: haceDias(5), tenencia_desde: haceDias(4) })],
          [actividad('insistir', dias, { tipo })],
          AHORA,
        )

      it.each(['llamada_no_contestada', 'whatsapp_enviado'] as const)(
        'un lead nuevo con %s hace 2 días cae en `insistir`, no en la nada',
        (tipo) => {
          const cola = intentado(tipo, 2)
          expect(cola).toHaveLength(1)
          expect(cola[0]).toMatchObject({ bucket: 'insistir', sev: 'media' })
          expect(cola[0]?.motivo).toContain('cambia de canal')
        },
      )

      it('el mismo día NO reaparece: volver a las horas se lee como ruido', () => {
        expect(intentado('llamada_no_contestada', 0.3)).toHaveLength(0)
      })

      it('si ya tiene tarea agendada vive en la agenda, no aquí (sin doble aviso)', () => {
        const cola = colaDe(
          [lead({ id: 'insistir', creado_en: haceDias(5), tenencia_desde: haceDias(4) })],
          [actividad('insistir', 2, { tipo: 'llamada_no_contestada' })],
          AHORA,
          { vigente: new Set(['insistir']), vencido: new Map() },
        )
        expect(cola).toHaveLength(0)
      })

      it('si HABLARON pero sigue en Nuevo, el motivo no miente: dice que lo muevan', () => {
        // Solo ocurre con datos anteriores al avance automático de etapa (o si
        // el trigger no llegó a correr). El bucket lo saca a la superficie sin
        // afirmar que el cliente no respondió.
        const cola = colaDe(
          [lead({ id: 'hablado', creado_en: haceDias(5), tenencia_desde: haceDias(4) })],
          [actividad('hablado', 2, { tipo: 'llamada_realizada' })],
          AHORA,
        )
        expect(cola[0]).toMatchObject({ bucket: 'insistir' })
        expect(cola[0]?.motivo).toContain('sigue en Nuevo')
      })
    })

    it('el cronómetro tiene de dónde salir: dias se mide desde la tenencia, no desde la reasignación', () => {
      // La reasignación comparte instante con tenencia_desde (mismo statement
      // en el servidor), así que ambos dan lo mismo — pero el lead DEBE estar
      // en la cola para que el cronómetro llegue a pintarse.
      const { lead: l, acts } = asignadoHace(0.02)
      const cola = colaDe([l], acts, AHORA)
      expect(cola).toHaveLength(1)
      expect(cola[0]?.dias).toBeCloseTo(0.02, 2)
    })
  })
})

describe('agregaciones comerciales', () => {
  it('separa capital por moneda y calcula conversión y abandono por vendedor', () => {
    const vendedores = [miembro('v2'), miembro('v1')]
    const leads = [
      lead({ id: 'pen', vendedor_id: 'v1', monto_estimado: 100, creado_en: haceDias(3) }),
      lead({ id: 'usd', vendedor_id: 'v1', monto_estimado: 50, moneda: 'USD', creado_en: haceDias(4) }),
      lead({ id: 'ganado', vendedor_id: 'v1', etapa: 'convertido', monto_estimado: 999 }),
      lead({ id: 'perdido', vendedor_id: 'v1', etapa: 'descartado' }),
      lead({ id: 'inactivo', vendedor_id: 'v1', activo: false, monto_estimado: 10_000 }),
      lead({ id: 'sin-vendedor', vendedor_id: null, monto_estimado: 10_000 }),
    ]

    const filas = metricasPorVendedor(vendedores, leads, [actividad('pen', 2)], AHORA)

    expect(filas[0]).toMatchObject({
      m: { perfil_id: 'v1' },
      activos: 2,
      capitalPEN: 100,
      capitalUSD: 50,
      convertidos: 1,
      conversion: 25,
      // 2, no 1: `sinTocar` cuenta CONTACTO (llamada/WhatsApp/reunión) y la
      // única actividad del fixture es una `nota`. Escribir una nota interna no
      // es haber hablado con el cliente — decisión de Miguel 2026-07-25.
      sinTocar: 2,
      // …pero "Última actividad" sigue midiendo actividad a secas, así que la
      // nota de hace 2 días SÍ cuenta aquí: el máximo lo pone 'usd' con 4.
      diasSinActividadMax: 4,
    })
    expect(filas[1]).toMatchObject({
      m: { perfil_id: 'v2' },
      activos: 0,
      capitalPEN: 0,
      capitalUSD: 0,
      conversion: 0,
    })
  })




  it('detecta estancados abiertos usando la referencia más reciente', () => {
    const leads = [
      lead({ id: 'diez', etapa: 'contactado', creado_en: haceDias(10) }),
      lead({ id: 'ocho', etapa: 'propuesta_enviada', creado_en: haceDias(12) }),
      lead({ id: 'seis', etapa: 'contactado', creado_en: haceDias(6) }),
      lead({ id: 'terminal', etapa: 'descartado', creado_en: haceDias(30) }),
    ]

    expect(estancados(leads, [actividad('ocho', 8)], 7, AHORA).map((fila) => fila.lead.id)).toEqual([
      'diez',
      'ocho',
    ])
  })

  it('compara equipos con su jerarquía, parqueados y monedas separadas', () => {
    const equipo = [
      miembro('s1', { rol_crm: 'supervisor' }),
      miembro('s2', { rol_crm: 'supervisor' }),
      miembro('v1', { supervisor_id: 's1' }),
      miembro('v2', { supervisor_id: 's1', activo: false }),
    ]
    const leads = [
      lead({ id: 'propio-s1', vendedor_id: 's1', monto_estimado: 50 }),
      lead({ id: 'pen-v1', vendedor_id: 'v1', monto_estimado: 100 }),
      lead({ id: 'usd-v1', vendedor_id: 'v1', monto_estimado: 20, moneda: 'USD' }),
      lead({ id: 'ganado-v1', vendedor_id: 'v1', etapa: 'convertido' }),
      lead({ id: 'vendedor-inactivo', vendedor_id: 'v2', monto_estimado: 1_000 }),
      lead({ id: 'park-s1', vendedor_id: null, asignado_supervisor_id: 's1', monto_estimado: 5_000 }),
      lead({ id: 'park-s2', vendedor_id: null, asignado_supervisor_id: 's2', monto_estimado: 5_000 }),
    ]

    const filas = comparativaEquipos(equipo, leads, [])

    expect(filas[0]).toMatchObject({
      supervisor: { perfil_id: 's1' },
      vendedores: 1,
      activos: 3,
      capitalPEN: 150,
      capitalUSD: 20,
      convertidos: 1,
      conversion: 25,
      parkeados: 1,
    })
    expect(filas[1]).toMatchObject({
      supervisor: { perfil_id: 's2' },
      vendedores: 0,
      activos: 0,
      capitalPEN: 0,
      capitalUSD: 0,
      convertidos: 0,
      conversion: 0,
      parkeados: 1,
    })
  })
})

describe('Fase B — la cola y estancados respetan el PLAN (tareas pendientes)', () => {
  const base = () => [
    lead({ id: 'con-plan', etapa: 'contactado' }),
    lead({ id: 'sin-plan', etapa: 'contactado' }),
    lead({ id: 'nuevo-frio', etapa: 'nuevo' }),
    lead({ id: 'parkeado', vendedor_id: null }),
  ]

  // El escudo del plan muerto (2026-07-25): una tarea pendiente vencida hace
  // semanas escondía al lead de la cola. Al levantarlo, el lead vuelve por su
  // propio pie al bucket que le toca; `plan_vencido` es el RESIDUO que captura
  // solo al que no cae en ninguno.
  describe('una tarea vencida ya no es plan', () => {
    const muerta = (leadId: string, venceEn: string) => ({
      vigente: new Set<string>(),
      vencido: new Map([[leadId, {
        id: 'tm', lead_id: leadId, tipo: 'llamada' as const, titulo: 'Llamar a Ana',
        vence_en: venceEn, estado: 'pendiente' as const, reprogramaciones: 0,
        activo: true, creado_en: haceDias(20),
      }]]),
    })

    it('el lead vuelve al bucket que le toca por inactividad, con SU motivo', () => {
      const cola = colaDe(
        [lead({ id: 'olvidado', etapa: 'propuesta_enviada', creado_en: haceDias(30), tenencia_desde: haceDias(20) })],
        [actividad('olvidado', 10, { tipo: 'whatsapp_enviado' })],
        AHORA,
        muerta('olvidado', haceDias(12)),
      )
      // NO se degrada a 'plan_vencido': eso bajaría la severidad de media a
      // baja y cambiaría el motivo a "cierra una tarea", que no vende nada.
      expect(cola[0]).toMatchObject({ bucket: 'propuesta_sin_respuesta', sev: 'media' })
    })

    it('el trabajado hace poco con tarea muerta cae en `plan_vencido` — antes era invisible', () => {
      const cola = colaDe(
        [lead({ id: 'reciente', etapa: 'contactado', creado_en: haceDias(30), tenencia_desde: haceDias(20) })],
        [actividad('reciente', 0.5, { tipo: 'llamada_realizada' })],
        AHORA,
        muerta('reciente', haceDias(9)),
      )
      expect(cola[0]).toMatchObject({ bucket: 'plan_vencido', sev: 'baja' })
      expect(cola[0]?.motivo).toContain('«Llamar a Ana»')
      expect(cola[0]?.motivo).toContain('hace 9 días')
    })

    it('con plan VIVO el lead sigue fuera de la cola (la agenda es su cola)', () => {
      const cola = colaDe(
        [lead({ id: 'con-plan', etapa: 'contactado', creado_en: haceDias(30), tenencia_desde: haceDias(20) })],
        [actividad('con-plan', 10, { tipo: 'llamada_realizada' })],
        AHORA,
        { vigente: new Set(['con-plan']), vencido: new Map() },
      )
      expect(cola).toHaveLength(0)
    })
  })

  it('lead con tarea pendiente sale del fallback por inactividad; asignación y speed-to-lead se mantienen', () => {
    const ahora = Date.now()
    const plan = { vigente: new Set(['con-plan', 'nuevo-frio', 'parkeado']), vencido: new Map() }
    const cola = colaDe(base(), [], ahora, plan)
    const buckets = new Map(cola.map((i) => [i.lead.id, i.bucket]))
    expect(buckets.has('con-plan')).toBe(false) // tiene plan → su cola es la agenda
    expect(buckets.get('sin-plan')).toBe('seguimiento') // fallback para quien no tiene
    expect(buckets.get('nuevo-frio')).toBe('sin_responder') // speed-to-lead NUNCA se apaga
    expect(buckets.get('parkeado')).toBe('por_repartir') // la tenencia tampoco
  })

  it('estancados excluye leads con tarea futura (el riesgo deja de pelearse con el plan)', () => {
    const ahora = Date.now()
    const alertas = estancados(base(), [], 5, ahora, undefined, new Set(['con-plan']))
    const ids = alertas.map((a) => a.lead.id)
    expect(ids).not.toContain('con-plan')
    expect(ids).toContain('sin-plan')
  })

  it('sinProximaAccion: abiertos CON vendedor y sin plan, capital PEN primero desc', () => {
    const leads = [
      lead({ id: 'usd-grande', moneda: 'USD', monto_estimado: 90_000 }),
      lead({ id: 'pen-chico', moneda: 'PEN', monto_estimado: 10_000 }),
      lead({ id: 'pen-grande', moneda: 'PEN', monto_estimado: 50_000 }),
      lead({ id: 'con-plan', moneda: 'PEN', monto_estimado: 99_000 }),
      lead({ id: 'parkeado', vendedor_id: null }),
      lead({ id: 'cerrado', etapa: 'convertido' }),
    ]
    const ids = sinProximaAccion(leads, new Set(['con-plan'])).map((l) => l.id)
    // PEN desc primero (nunca mezclado con USD), USD después; sin parkeados ni cerrados.
    expect(ids).toEqual(['pen-grande', 'pen-chico', 'usd-grande'])
  })
})

// ── El chip de capital: qué moneda MANDA en el número grande ──────────────────
// Pedido de Miguel (2026-07-26): tres pantallas pintan el mismo capital y las
// tres fijaban PEN a mano. Una cartera íntegramente en dólares se anunciaba como
// "S/ 0.00" con el capital real en la letra chica. El criterio vive ahora una
// sola vez aquí.
describe('capitalPrincipal — la moneda que manda en el número grande', () => {
  it('una cartera ÍNTEGRAMENTE en dólares se anuncia en dólares, no como "S/ 0"', () => {
    const c = capitalPrincipal(0, 40_000)
    expect(c).toMatchObject({ soloDolares: true, moneda: 'USD', sub: 'USD', otra: null })
    expect(c.valor).toBe(money(40_000, 'USD'))
    // El defecto exacto: un "S/ 0.00" enorme con el dinero escondido debajo.
    expect(c.valor).not.toBe(money(0))
  })

  it('con soles manda el PEN y el USD se dice aparte — JAMÁS sumados', () => {
    const c = capitalPrincipal(120_000, 40_000)
    expect(c).toMatchObject({ soloDolares: false, moneda: 'PEN', otra: 'US$ 40k' })
    expect(c.valor).toBe(money(120_000))
    expect(c.sub).toBe('PEN · +US$ 40k')
    // Los 160 000 mixtos no existen en ninguna parte del chip.
    expect(c.valor).not.toBe(money(160_000))
  })

  it('solo soles: no menciona la otra moneda', () => {
    expect(capitalPrincipal(120_000, 0)).toMatchObject({ soloDolares: false, otra: null, sub: 'PEN' })
  })

  it('cartera sin montos estimados: PEN en cero (no hay dólares que promover)', () => {
    const c = capitalPrincipal(0, 0)
    expect(c).toMatchObject({ soloDolares: false, moneda: 'PEN', sub: 'PEN' })
    expect(c.valor).toBe(money(0))
  })
})

// ── El bucket `sin_avance` y la fotografía del EPISODIO ──────────────────────
describe('`sin_avance` usa el episodio sellado, no constantes del navegador', () => {
  const fotografia = estadoSla('clavado', {
    etapa_politica_id: '00000000-0000-4000-8000-000000000001',
    etapa_politica_version: 4,
    etapa: 'contactado',
    etapa_iniciada_en: haceDias(20),
    etapa_limite_en: haceDias(17),
    etapa_objetivo_minutos: 4_320,
    etapa_aproximada: false,
  })

  const clavado = (snapshot?: EstadoSlaLead) => colaDe(
    [lead({
      id: 'clavado',
      etapa: 'contactado',
      creado_en: haceDias(40),
      tenencia_desde: haceDias(0.5),
    })],
    [actividad('clavado', 1, { tipo: 'llamada_realizada' })],
    AHORA,
    undefined,
    snapshot ? new Map([['clavado', snapshot]]) : undefined,
  )

  it('sin fotografía no fabrica un estancamiento con la política vigente', () => {
    expect(clavado().find((item) => item.bucket === 'sin_avance')).toBeUndefined()
  })

  it('pasado el doble del plazo sellado dispara con días y versión del episodio', () => {
    const cola = clavado(fotografia)
    expect(cola[0]).toMatchObject({ bucket: 'sin_avance', sev: 'media', dias: 20 })
    expect(cola[0]?.motivo).toContain('Lleva 20 días en Contactado')
    expect(cola[0]?.motivo).toContain('SLA v4 vencido')
  })

  it('una transferencia reciente no reescribe retroactivamente la etapa', () => {
    expect(clavado(fotografia)[0]).toMatchObject({ bucket: 'sin_avance' })
  })

  it('una nueva versión solo afecta episodios nuevos, no el deadline recibido', () => {
    const mismaFechaOtraVersion = { ...fotografia, etapa_politica_version: 99 }
    expect(clavado(mismaFechaOtraVersion)[0]?.dias).toBe(clavado(fotografia)[0]?.dias)
  })
})
