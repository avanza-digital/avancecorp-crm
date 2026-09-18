// Tests de las MUTACIONES del store demo (lib/store.tsx) — write-gating,
// validación compartida, dedup vivo, ámbito jerárquico y ciclo de vida del lead.
// Mismo patrón de montaje que store.test.tsx: sesión demo inyectada por
// AuthContext + stub de VITE_ENABLE_DEMO ANTES de importar el store (config.ts
// lee el flag en tiempo de carga del módulo).
import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, waitFor } from '@testing-library/react'
import { AuthContext, type AuthContextValue } from './auth-context'
import { useCRMData } from './store-context'
import { DEMO_YO } from './auth-demo'
import type { Rol } from './roles'
import type { EtapaActiva, TipoActividadManual } from './tipos'
import type { NuevoLeadInput, StoreDataApi } from './store'

vi.stubEnv('VITE_ENABLE_DEMO', 'true')
const { StoreProvider } = await import('./store')

// Los gates de runtime del store son la ÚLTIMA defensa: estos casts burlan el
// tipado a propósito (igual que lo haría un consumidor JS o datos externos).
const ETAPA_TERMINAL_FORZADA = 'convertido' as unknown as EtapaActiva
const TIPO_AUTO_FORZADO = 'cambio_etapa' as unknown as TipoActividadManual

function sesionDemo(rol: Rol): AuthContextValue {
  return {
    fase: 'listo',
    yo: { ...DEMO_YO[rol], rol, demo: true, puede_contratar: true },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  }
}

interface Montaje {
  /** Lectura SIEMPRE fresca de la api (la referencia cambia en cada render). */
  api: () => StoreDataApi
  /** Ejecuta una mutación dentro de act() y devuelve su resultado. */
  mutar: <T>(fn: (api: StoreDataApi) => T) => T
}

/** Monta StoreProvider con una sesión demo del rol dado y espera la siembra. */
async function montarStore(rol: Rol): Promise<Montaje> {
  const ref: { actual: StoreDataApi | null } = { actual: null }
  function Sonda(): null {
    ref.actual = useCRMData()
    return null
  }
  render(
    <AuthContext.Provider value={sesionDemo(rol)}>
      <StoreProvider>
        <Sonda />
      </StoreProvider>
    </AuthContext.Provider>,
  )
  const api = (): StoreDataApi => {
    if (!ref.actual) throw new Error('StoreProvider aún no montado')
    return ref.actual
  }
  // Los fixtures llegan por import() dinámico: esperar los 20 leads sembrados.
  await waitFor(() => expect(api().leads).toHaveLength(20))
  function mutar<T>(fn: (a: StoreDataApi) => T): T {
    let resultado!: T
    act(() => {
      resultado = fn(api())
    })
    return resultado
  }
  return { api, mutar }
}

/** Input mínimo válido para crearLead (teléfono único fuera de los fixtures). */
function inputBase(extra?: Partial<NuevoLeadInput>): NuevoLeadInput {
  return {
    nombre_completo: 'LEAD DE PRUEBA',
    telefono: '900000001',
    origen: 'formulario',
    monto_estimado: 1000,
    moneda: 'PEN',
    vendedor_id: 'd-v1',
    ...extra,
  }
}

describe('mutaciones del store demo', () => {
  beforeEach(() => window.sessionStorage.clear())
  afterAll(() => vi.unstubAllEnvs())

  describe('crearLead', () => {
    it.each(['monto_estimado', 'moneda'] as const)(
      'rechaza creación si la propiedad obligatoria %s fue omitida en runtime',
      async (campo) => {
        const { api, mutar } = await montarStore('vendedor')
        const incompleto = { ...inputBase() } as Partial<NuevoLeadInput>
        delete incompleto[campo]

        const res = mutar((a) => a.crearLead(incompleto as NuevoLeadInput))

        expect(res).toMatchObject({
          ok: false,
          codigo: campo === 'monto_estimado' ? 'monto_invalido' : 'moneda_invalida',
          campo,
        })
        expect(api().leads).toHaveLength(20)
      },
    )

    it.each([null, 0, -1] as const)('rechaza capital estimado no positivo: %s', async (monto) => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.crearLead(inputBase({ monto_estimado: monto as unknown as number })))

      expect(res).toMatchObject({ ok: false, codigo: 'monto_invalido', campo: 'monto_estimado' })
      expect(api().leads).toHaveLength(20)
    })

    it.each([0.001, 5000.999, 10_000_000_000])(
      'rechaza capital fuera de la precisión/rango numeric(12,2): %s',
      async (monto) => {
        const { api, mutar } = await montarStore('vendedor')

        const res = mutar((a) => a.crearLead(inputBase({ monto_estimado: monto })))

        expect(res).toMatchObject({ ok: false, codigo: 'monto_invalido', campo: 'monto_estimado' })
        expect(api().leads).toHaveLength(20)
      },
    )

    it('rechaza una moneda fuera del catálogo aunque un consumidor burle TypeScript', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) =>
        a.crearLead(inputBase({ moneda: 'EUR' as unknown as NuevoLeadInput['moneda'] })),
      )

      expect(res).toMatchObject({ ok: false, codigo: 'moneda_invalida', campo: 'moneda' })
      expect(api().leads).toHaveLength(20)
    })

    it('crea un lead válido auto-asignado al analista y lo expone en su ámbito', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.crearLead(inputBase()))

      expect(res).toMatchObject({ ok: true })
      const id = res.id ?? ''
      expect(id).not.toBe('')
      // Aparece en el ámbito del analista (recorte por vendedor_id === yo.id)
      const enAmbito = api().ambito.leads.find((l) => l.id === id)
      expect(enAmbito).toBeDefined()
      expect(enAmbito).toMatchObject({
        nombre_completo: 'LEAD DE PRUEBA',
        telefono: '+51900000001', // normalizado a formato +51
        etapa: 'nuevo',
        vendedor_id: 'd-v1',
        vendedor_nombre: 'ANALISTA UNO',
        activo: true,
      })
      expect(api().leads).toHaveLength(21)
    })

    it('rechaza un teléfono inválido con código y campo anclados', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.crearLead(inputBase({ telefono: '12345' })))

      expect(res).toMatchObject({ ok: false, codigo: 'telefono_invalido', campo: 'telefono' })
      expect(res.id).toBeUndefined()
      expect(api().leads).toHaveLength(20)
    })

    it('rechaza el teléfono de otro lead abierto (dedup vivo)', async () => {
      const { api, mutar } = await montarStore('vendedor')

      // 987654321 normaliza a +51987654321 → mismo teléfono que l1 (abierto)
      const res = mutar((a) => a.crearLead(inputBase({ telefono: '987654321' })))

      expect(res).toMatchObject({ ok: false, codigo: 'duplicado_telefono', campo: 'telefono' })
      expect(api().leads).toHaveLength(20)
    })

    it('rechaza el DNI de otro lead abierto (dedup vivo)', async () => {
      const { api, mutar } = await montarStore('vendedor')

      // 45871236 es el DNI de l2 (contactado → abierto)
      const res = mutar((a) => a.crearLead(inputBase({ dni: '45871236' })))

      expect(res).toMatchObject({ ok: false, codigo: 'duplicado_dni', campo: 'dni' })
      expect(api().leads).toHaveLength(20)
    })

    it('el dedup solo mira leads ABIERTOS: teléfono/DNI de cerrados se pueden reutilizar', async () => {
      const { mutar } = await montarStore('vendedor')

      // Teléfono de l10 (descartado) + DNI de l9 (convertido) → permitido
      const res = mutar((a) =>
        a.crearLead(inputBase({ telefono: '976543210', dni: '41236587' })),
      )

      expect(res).toMatchObject({ ok: true })
    })

    it('un lead nunca nace en etapa terminal', async () => {
      const { mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.crearLead(inputBase({ etapa: ETAPA_TERMINAL_FORZADA })))

      expect(res).toMatchObject({ ok: false, codigo: 'etapa_terminal_al_nacer' })
    })

    it('el analista solo puede crear leads asignados a sí mismo', async () => {
      const { api, mutar } = await montarStore('vendedor')

      // Asignar a OTRO analista → bloqueado
      const aOtro = mutar((a) => a.crearLead(inputBase({ vendedor_id: 'd-v2' })))
      expect(aOtro).toMatchObject({ ok: false, codigo: 'solo_autoasignar' })

      // Parkear (vendedor_id null) también es privilegio de supervisor/gerencia
      const parkeado = mutar((a) => a.crearLead(inputBase({ vendedor_id: null })))
      expect(parkeado).toMatchObject({ ok: false, codigo: 'solo_autoasignar' })

      expect(api().leads).toHaveLength(20)
    })

    // Hallazgo de auditoría 2026-07-10 (corregido): el dedup es global (espejo
    // del unique index) pero el mensaje solo revela el NOMBRE si el actor puede
    // ver el lead en conflicto — sin fuga de PII por sondeo de teléfonos/DNIs.
    it('el error de duplicado NO revela el nombre de un lead fuera del ámbito', async () => {
      const { mutar } = await montarStore('vendedor')

      // +51987654324 es l4 (ANA TORRES QUISPE), de d-v3 — invisible para d-v1
      const res = mutar((a) => a.crearLead(inputBase({ telefono: '987654324' })))

      expect(res).toMatchObject({ ok: false, codigo: 'duplicado_telefono' })
      expect(res.error).not.toContain('ANA TORRES')
      expect(res.error).toContain('otro lead abierto de la empresa')
    })

    it('el error de duplicado SÍ nombra al lead en conflicto cuando es visible para el actor', async () => {
      const { mutar } = await montarStore('vendedor')

      // +51987654322 es l2 (MARÍA LÓPEZ CASTRO), del propio d-v1
      const res = mutar((a) => a.crearLead(inputBase({ telefono: '987654322' })))

      expect(res).toMatchObject({ ok: false, codigo: 'duplicado_telefono' })
      expect(res.error).toContain('MARÍA LÓPEZ CASTRO')
    })
  })

  describe('write-gating por rol', () => {
    it('directorio (solo lectura total): CUALQUIER mutación devuelve sin_permiso y no toca los datos', async () => {
      const { api, mutar } = await montarStore('directorio')
      const leadsAntes = api().leads
      const actividadesAntes = api().actividades
      const tareasAntes = api().tareas
      const tareaId = tareasAntes[0]?.id ?? 'sin-tarea'

      const resultados = [
        mutar((a) => a.crearLead(inputBase())),
        mutar((a) => a.editarLead('l1', { nota: 'intento de escritura' })),
        mutar((a) => a.cambiarEtapa('l1', 'contactado')),
        mutar((a) => a.descartar('l1', 'sin_interes')),
        mutar((a) => a.convertir('l1')),
        mutar((a) => a.reabrir('l8')),
        mutar((a) => a.registrarActividad('l1', 'nota', 'intento')),
        mutar((a) => a.reasignar('l1', 'd-v2')),
        // Los cuatro verbos de agenda entran al gate ANTES de validar payload o
        // tocar estado: el directorio no puede modificarle la agenda a nadie.
        mutar((a) => a.crearTarea({
          lead_id: 'l1',
          tipo: 'reunion',
          titulo: '',
          vence_en: 'fecha-manipulada',
        })),
        mutar((a) => a.completarTarea({ tarea_id: tareaId, estado: 'completada' })),
        mutar((a) => a.reprogramarTarea(tareaId, 'fecha-manipulada')),
        mutar((a) => a.anularTarea(tareaId)),
      ]

      for (const res of resultados) {
        expect(res).toMatchObject({ ok: false, codigo: 'sin_permiso' })
      }
      // Ninguna mutación disparó setDatos: mismas referencias, mismo contenido
      expect(api().leads).toBe(leadsAntes)
      expect(api().actividades).toBe(actividadesAntes)
      expect(api().tareas).toBe(tareasAntes)
      expect(api().lead('l1')?.etapa).toBe('nuevo')
      expect(api().lead('l8')?.etapa).toBe('descartado')
    })
  })

  // ── LA CITA ATENDIDA ES LA ENTREVISTA (pedido de Miguel, 2026-09-18) ───────
  // Espejo de `crm.cerrar_reunion_v3` + `private.entrevista_registrar`. Si una
  // regla cambia aquí, cambia en la migración EN LA MISMA ENTREGA.
  describe('cerrar una cita como realizada registra la entrevista', () => {
    const CAPITAL = { monto_estimado: 57_500, moneda: 'PEN' } as const
    const citaDe = (api: () => StoreDataApi, mutar: Montaje['mutar'], leadId: string) => {
      const res = mutar((a) =>
        a.crearTarea({
          lead_id: leadId,
          tipo: 'reunion',
          titulo: 'Cita con el inversionista',
          vence_en: new Date(Date.now() + 86_400_000).toISOString(),
          modalidad_reunion: 'virtual',
        }),
      )
      expect(res.ok).toBe(true)
      void api
      return res.id as string
    }

    it('sube el lead a «Entrevista realizada» y asienta el capital propuesto', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const cita = citaDe(api, mutar, 'l1')

      const res = mutar((a) =>
        a.completarTarea({
          tarea_id: cita,
          estado: 'completada',
          resultado_tipo: 'reunion_realizada',
          resultado_reunion: 'propuesta',
          capital: CAPITAL,
        }),
      )

      expect(res).toMatchObject({ ok: true, avance: 'propuesta_enviada' })
      expect(api().lead('l1')).toMatchObject({
        etapa: 'propuesta_enviada',
        monto_estimado: 57_500,
        moneda: 'PEN',
      })
    })

    it('SIN capital no se cierra NADA: la cita sigue pendiente', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const cita = citaDe(api, mutar, 'l1')
      const etapaAntes = api().lead('l1')?.etapa

      const res = mutar((a) =>
        a.completarTarea({
          tarea_id: cita,
          estado: 'completada',
          resultado_tipo: 'reunion_realizada',
          resultado_reunion: 'propuesta',
        }),
      )

      expect(res).toMatchObject({ ok: false, codigo: 'monto_invalido', campo: 'monto_estimado' })
      expect(api().tareas.find((t) => t.id === cita)?.estado).toBe('pendiente')
      expect(api().lead('l1')?.etapa).toBe(etapaAntes)
    })

    it.each([0, -1, 5000.999] as const)('rechaza un capital imposible (%s)', async (monto) => {
      const { api, mutar } = await montarStore('vendedor')
      const cita = citaDe(api, mutar, 'l1')

      const res = mutar((a) =>
        a.completarTarea({
          tarea_id: cita,
          estado: 'completada',
          resultado_tipo: 'reunion_realizada',
          resultado_reunion: 'propuesta',
          capital: { monto_estimado: monto, moneda: 'PEN' },
        }),
      )

      expect(res).toMatchObject({ ok: false, codigo: 'monto_invalido' })
      expect(api().tareas.find((t) => t.id === cita)?.estado).toBe('pendiente')
    })

    it('la SEGUNDA entrevista no mueve la etapa, pero sí reasienta el capital', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const primera = citaDe(api, mutar, 'l1')
      mutar((a) =>
        a.completarTarea({
          tarea_id: primera,
          estado: 'completada',
          resultado_tipo: 'reunion_realizada',
          resultado_reunion: 'propuesta',
          capital: CAPITAL,
        }),
      )
      const segunda = citaDe(api, mutar, 'l1')

      const res = mutar((a) =>
        a.completarTarea({
          tarea_id: segunda,
          estado: 'completada',
          resultado_tipo: 'reunion_realizada',
          resultado_reunion: 'inicia_registro',
          capital: { monto_estimado: 90_000, moneda: 'USD' },
        }),
      )

      expect(res.ok).toBe(true)
      expect(res.avance).toBeUndefined()
      expect(api().lead('l1')).toMatchObject({
        etapa: 'propuesta_enviada',
        monto_estimado: 90_000,
        moneda: 'USD',
      })
    })

    it('un PLANTÓN no registra entrevista: ni etapa ni capital se mueven', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const cita = citaDe(api, mutar, 'l1')
      const antes = api().lead('l1')

      const res = mutar((a) => a.completarTarea({ tarea_id: cita, estado: 'no_show' }))

      expect(res.ok).toBe(true)
      expect(api().lead('l1')).toMatchObject({
        etapa: antes?.etapa as string,
        monto_estimado: antes?.monto_estimado as number,
        moneda: antes?.moneda as string,
      })
    })
    // «No interesado»: la entrevista ocurrió, pero nadie le propuso capital.
    // Hallazgo de la auditoría del 18/09: exigir una cifra ahí es pedirle al
    // analista que la invente, y esa invención entra al capital en proceso.
    it('«No interesado» registra la entrevista SIN pedir capital y sin tocar la cifra', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const cita = citaDe(api, mutar, 'l1')
      const montoAntes = api().lead('l1')?.monto_estimado
      const monedaAntes = api().lead('l1')?.moneda

      const res = mutar((a) =>
        a.completarTarea({
          tarea_id: cita,
          estado: 'completada',
          resultado_tipo: 'reunion_realizada',
          resultado_reunion: 'no_interesado',
        }),
      )

      expect(res).toMatchObject({ ok: true, avance: 'propuesta_enviada' })
      expect(api().lead('l1')).toMatchObject({
        etapa: 'propuesta_enviada',
        monto_estimado: montoAntes as number,
        moneda: monedaAntes as string,
      })
    })

    it('«No interesado» CON capital se rechaza: nadie propuso nada', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const cita = citaDe(api, mutar, 'l1')

      const res = mutar((a) =>
        a.completarTarea({
          tarea_id: cita,
          estado: 'completada',
          resultado_tipo: 'reunion_realizada',
          resultado_reunion: 'no_interesado',
          capital: CAPITAL,
        }),
      )

      expect(res).toMatchObject({ ok: false, codigo: 'monto_invalido' })
      expect(api().tareas.find((t) => t.id === cita)?.estado).toBe('pendiente')
    })

    it('un PLANTÓN con capital se rechaza igual', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const cita = citaDe(api, mutar, 'l1')

      const res = mutar((a) =>
        a.completarTarea({ tarea_id: cita, estado: 'no_show', capital: CAPITAL }),
      )

      expect(res).toMatchObject({ ok: false, codigo: 'monto_invalido' })
      expect(api().tareas.find((t) => t.id === cita)?.estado).toBe('pendiente')
    })
  })

  describe('reasignar', () => {
    it('supervisor NO puede reasignar hacia un analista de otro equipo', async () => {
      const { api, mutar } = await montarStore('supervisor')

      // d-v3 reporta a d-sup2 — fuera del ámbito de d-sup1
      const res = mutar((a) => a.reasignar('l1', 'd-v3'))

      expect(res).toMatchObject({ ok: false, codigo: 'vendedor_fuera_ambito' })
      expect(api().lead('l1')?.vendedor_id).toBe('d-v1')
    })

    it('supervisor reasigna dentro de su equipo y queda actividad automática', async () => {
      const { api, mutar } = await montarStore('supervisor')

      const res = mutar((a) => a.reasignar('l1', 'd-v2'))

      expect(res).toMatchObject({ ok: true })
      expect(api().lead('l1')).toMatchObject({
        vendedor_id: 'd-v2',
        vendedor_nombre: 'ANALISTA DOS',
        asignado_supervisor_id: null,
      })
      const ultima = api().actividadesDe('l1')[0]
      expect(ultima).toMatchObject({
        tipo: 'reasignacion',
        detalle: 'ANALISTA UNO → ANALISTA DOS',
        autor_nombre: 'SUPERVISOR UNO',
      })
    })

    it('Gerencia libera bandejas y reasigna leads en todo el ámbito', async () => {
      const { api, mutar } = await montarStore('gerencia')
      expect(api().lead('l5')).toMatchObject({
        vendedor_id: null,
        asignado_supervisor_id: 'd-sup1',
      })

      const res = mutar((a) => a.reasignar('l5', null))

      expect(res).toMatchObject({ ok: true })
      expect(api().lead('l5')).toMatchObject({
        vendedor_id: null,
        asignado_supervisor_id: null,
      })
      expect(api().actividadesDe('l5')[0]).toMatchObject({
        tipo: 'reasignacion',
        detalle: 'Bandeja de SUPERVISOR UNO → Sin asignar',
        autor_nombre: 'GERENCIA DEMO',
      })
    })

    it('analista no tiene el permiso de reasignar (ni siquiera hacia sí mismo)', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.reasignar('l5', 'd-v1'))

      expect(res).toMatchObject({ ok: false, codigo: 'sin_permiso_reasignar' })
      // l5 es un parkeado de supervisor: para el analista ni siquiera es visible
      expect(api().lead('l5')).toBeUndefined()
      expect(api().leads.find((l) => l.id === 'l5')?.vendedor_id).toBeNull()
    })

    // Hallazgo de auditoría 2026-07-10 (corregido): las mutaciones buscan el
    // lead SOLO dentro del ámbito del actor (espejo del USING de leads_update).
    // Fuera del ámbito → no_encontrado, igual que RLS (0 filas), sin revelar
    // siquiera que el lead existe.
    it('supervisor NO puede mutar un lead fuera de su ámbito (espejo del USING)', async () => {
      const { api, mutar } = await montarStore('supervisor')

      // l4 pertenece a d-v3 (equipo de d-sup2): invisible para d-sup1
      expect(api().lead('l4')).toBeUndefined()
      const resultados = [
        mutar((a) => a.reasignar('l4', 'd-v2')),
        mutar((a) => a.editarLead('l4', { nota: 'intento cruzado' })),
        mutar((a) => a.cambiarEtapa('l4', 'contactado')),
        mutar((a) => a.descartar('l4', 'sin_interes')),
        mutar((a) => a.convertir('l4')),
        mutar((a) => a.registrarActividad('l4', 'nota', 'intento')),
      ]
      for (const res of resultados) {
        expect(res).toMatchObject({ ok: false, codigo: 'no_encontrado' })
      }
      // El timeline de un lead ajeno tampoco es visible
      expect(api().actividadesDe('l4')).toHaveLength(0)
    })
  })

  describe('cambiarEtapa', () => {
    it('no permite cerrar por cambiarEtapa: las terminales van por convertir/descartar', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.cambiarEtapa('l1', ETAPA_TERMINAL_FORZADA))

      expect(res).toMatchObject({ ok: false, codigo: 'cerrar_con_flujo' })
      expect(api().lead('l1')?.etapa).toBe('nuevo')
    })

    it('rechaza mover de etapa un lead ya cerrado', async () => {
      const { api, mutar } = await montarStore('vendedor')

      // l8 está descartado (terminal)
      const res = mutar((a) => a.cambiarEtapa('l8', 'contactado'))

      expect(res).toMatchObject({ ok: false, codigo: 'lead_cerrado' })
      expect(api().lead('l8')?.etapa).toBe('descartado')
    })

    it('mueve un lead abierto y registra la actividad automática de cambio', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.cambiarEtapa('l1', 'contactado'))

      expect(res).toMatchObject({ ok: true })
      expect(api().lead('l1')?.etapa).toBe('contactado')
      expect(api().actividadesDe('l1')[0]).toMatchObject({
        tipo: 'cambio_etapa',
        detalle: 'Nuevo → Contactado',
        autor_nombre: 'ANALISTA UNO',
      })
    })
  })

  describe('ciclo de cierre y reapertura', () => {
    it('descartar cierra el lead con motivo y deja el detalle en el timeline', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.descartar('l1', 'sin_interes', 'prefiere otro producto'))

      expect(res).toMatchObject({ ok: true })
      expect(api().lead('l1')).toMatchObject({ etapa: 'descartado', motivo_descarte: 'sin_interes' })
      const ultima = api().actividadesDe('l1')[0]
      expect(ultima?.tipo).toBe('cambio_etapa')
      expect(ultima?.detalle).toContain('Motivo: Sin interés')
      expect(ultima?.detalle).toContain('prefiere otro producto')
    })

    it('convertir cierra el lead como convertido con actividad de conversión', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.convertir('l2'))

      expect(res).toMatchObject({ ok: true })
      expect(api().lead('l2')).toMatchObject({ etapa: 'convertido', motivo_descarte: null })
      expect(api().actividadesDe('l2')[0]?.tipo).toBe('conversion')
    })

    it('no convierte un lead parqueado: primero necesita analista responsable', async () => {
      const { mutar } = await montarStore('supervisor')

      const res = mutar((a) => a.convertir('l5'))

      expect(res).toMatchObject({ ok: false, codigo: 'sin_analista' })
      expect(res.error).toContain('Asigna el lead a un analista')
    })

    it('reabrir un descartado lo devuelve a nuevo y limpia el motivo', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.reabrir('l8'))

      expect(res).toMatchObject({ ok: true })
      expect(api().lead('l8')).toMatchObject({ etapa: 'nuevo', motivo_descarte: null })
      expect(api().actividadesDe('l8')[0]).toMatchObject({
        tipo: 'cambio_etapa',
        detalle: 'Descartado → Nuevo',
      })
    })

    it('solo se puede reabrir un lead DESCARTADO (ni abiertos ni convertidos)', async () => {
      const { api, mutar } = await montarStore('vendedor')

      // l2 está abierto (contactado) y l9 convertido
      const abierto = mutar((a) => a.reabrir('l2'))
      const convertido = mutar((a) => a.reabrir('l9'))

      expect(abierto).toMatchObject({ ok: false, codigo: 'solo_reabrir_descartado' })
      expect(convertido).toMatchObject({ ok: false, codigo: 'solo_reabrir_descartado' })
      expect(api().lead('l2')?.etapa).toBe('contactado')
      expect(api().lead('l9')?.etapa).toBe('convertido')
    })
  })

  describe('registrarActividad', () => {
    it('veta los tipos automáticos aunque se burle el tipado', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const antes = api().actividadesDe('l1').length

      const res = mutar((a) => a.registrarActividad('l1', TIPO_AUTO_FORZADO, 'forzado'))

      expect(res).toMatchObject({ ok: false, codigo: 'tipo_actividad_reservado' })
      expect(api().actividadesDe('l1')).toHaveLength(antes)
    })

    it('rechaza registrar actividad manual en un lead cerrado', async () => {
      const { mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.registrarActividad('l8', 'nota', 'no debería entrar'))

      expect(res).toMatchObject({ ok: false, codigo: 'lead_cerrado' })
    })

    it('registra una actividad manual y aparece primero en el timeline del lead', async () => {
      const { api, mutar } = await montarStore('vendedor')

      // `l1` está en `nuevo`, así que una CONVERSACIÓN además lo avanza de
      // etapa (2026-07-25) y el `cambio_etapa` queda ENCIMA: ocurrió después.
      const res = mutar((a) => a.registrarActividad('l1', 'llamada_realizada', 'habló con el titular'))

      expect(res).toMatchObject({ ok: true })
      expect(api().actividadesDe('l1')[1]).toMatchObject({
        tipo: 'llamada_realizada',
        detalle: 'habló con el titular',
        autor_nombre: 'ANALISTA UNO',
      })
      // También visible en el timeline recortado al ámbito
      expect(
        api().actividadesDelAmbito.some(
          (a) => a.lead_id === 'l1' && a.detalle === 'habló con el titular',
        ),
      ).toBe(true)
    })

    // ── Avance automático de etapa (pedido de Miguel, 2026-07-25) ────────────
    // Espejo optimista de `trg_zz_actividades_avance_etapa`, y la ÚNICA
    // implementación en modo demo. Ver lib/avance-automatico.ts.
    describe('avance automático de etapa al registrar contacto', () => {
      it('una CONVERSACIÓN sube el lead de nuevo a contactado y lo deja escrito en el timeline', async () => {
        const { api, mutar } = await montarStore('vendedor')
        expect(api().lead('l1')?.etapa).toBe('nuevo')

        const res = mutar((a) => a.registrarActividad('l1', 'llamada_realizada'))

        expect(res).toMatchObject({ ok: true, avance: 'contactado' })
        expect(api().lead('l1')?.etapa).toBe('contactado')
        expect(api().actividadesDe('l1')[0]).toMatchObject({
          tipo: 'cambio_etapa',
          detalle: 'Nuevo → Contactado',
        })
      })

      it.each(['llamada_no_contestada', 'whatsapp_enviado', 'nota'] as const)(
        'un INTENTO (%s) registra pero NO mueve la etapa — el embudo no se infla solo',
        async (tipo) => {
          const { api, mutar } = await montarStore('vendedor')

          const res = mutar((a) => a.registrarActividad('l1', tipo))

          expect(res).toMatchObject({ ok: true })
          expect(res).not.toHaveProperty('avance')
          expect(api().lead('l1')?.etapa).toBe('nuevo')
          expect(api().actividadesDe('l1')[0]).toMatchObject({ tipo })
        },
      )

      it('no avanza dos veces: el segundo contacto ya no mueve nada', async () => {
        const { api, mutar } = await montarStore('vendedor')

        mutar((a) => a.registrarActividad('l1', 'llamada_realizada'))
        const segundo = mutar((a) => a.registrarActividad('l1', 'whatsapp_recibido'))

        expect(segundo).toMatchObject({ ok: true })
        expect(segundo).not.toHaveProperty('avance')
        expect(api().lead('l1')?.etapa).toBe('contactado')
        expect(api().actividadesDe('l1').filter((a) => a.tipo === 'cambio_etapa')).toHaveLength(1)
      })
    })
  })

  // El avance de etapa que provoca agendar una reunión NO puede quedarse dentro
  // del store: los otros dos escritores (registrarActividad, completarTarea) ya
  // lo devuelven y la UI lo canta. Sin esto, agendar desde la ficha movía el
  // lead de etapa en silencio y el analista veía saltar el stepper solo.
  describe('crearTarea (avance automático de etapa, expuesto al llamador)', () => {
    const manana = (): string => new Date(Date.now() + 86_400_000).toISOString()

    it('agendar una reunión futura sube el lead a "reunion_agendada" Y lo devuelve', async () => {
      // l2: contactado, con dueño (d-v1) y con una llamada_realizada en su
      // timeline → cumple todas las guardas de avancePorReunion.
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión con María', vence_en: manana(), modalidad_reunion: 'virtual', enlace_reunion: 'https://meet.google.com/abc-defg-hij' }),
      )

      expect(res).toMatchObject({ ok: true, avance: 'reunion_agendada' })
      expect(api().lead('l2')?.etapa).toBe('reunion_agendada')
    })

    it('presenta «cita» en el formulario, pero conserva «reunión» en el modelo interno', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) =>
        a.crearTarea({
          lead_id: 'l2',
          tipo: 'reunion',
          titulo: 'Cita con María',
          vence_en: manana(),
          modalidad_reunion: 'virtual',
          enlace_reunion: 'https://meet.google.com/abc-defg-hij',
        }),
      )

      expect(res).toMatchObject({ ok: true })
      expect(api().tareas.find((t) => t.id === res.id)?.titulo).toBe('Reunión con María')
    })

    it('rechaza una reunión nueva sin modalidad explícita', async () => {
      const { mutar } = await montarStore('vendedor')

      const res = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión sin clasificar', vence_en: manana() }),
      )

      expect(res).toMatchObject({ ok: false, codigo: 'modalidad_reunion_obligatoria' })
    })

    it('acepta una reunión virtual sin enlace y sigue rechazando URLs inseguras', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const sinEnlace = mutar((a) =>
        a.crearTarea({
          lead_id: 'l2',
          tipo: 'reunion',
          titulo: 'Reunión sin enlace',
          vence_en: manana(),
          modalidad_reunion: 'virtual',
        }),
      )
      const insegura = mutar((a) =>
        a.crearTarea({
          lead_id: 'l2',
          tipo: 'reunion',
          titulo: 'Reunión insegura',
          vence_en: manana(),
          modalidad_reunion: 'virtual',
          enlace_reunion: 'http://meet.example.com/sala',
        }),
      )

      expect(sinEnlace).toMatchObject({ ok: true })
      expect(api().tareas.find((t) => t.id === sinEnlace.id)).toMatchObject({
        modalidad_reunion: 'virtual',
        ubicacion_reunion: null,
        enlace_reunion: null,
      })
      expect(insegura).toMatchObject({ ok: false, codigo: 'enlace_reunion_invalido' })
    })

    it('normaliza la reunión una sola vez y elimina campos incompatibles del payload manipulado', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const presencial = mutar((a) => a.crearTarea({
        lead_id: 'l2',
        tipo: 'reunion',
        titulo: 'Reunión presencial',
        vence_en: manana(),
        modalidad_reunion: 'presencial',
        ubicacion_reunion: '  Av. Arequipa 123  ',
        enlace_reunion: 'https://no-debe-persistir.example.com',
      }))
      const virtual = mutar((a) => a.crearTarea({
        lead_id: 'l2',
        tipo: 'reunion',
        titulo: 'Reunión virtual',
        vence_en: manana(),
        modalidad_reunion: 'virtual',
        ubicacion_reunion: 'No debe persistir',
        enlace_reunion: '  https://meet.google.com/abc-defg-hij  ',
      }))

      expect(api().tareas.find((t) => t.id === presencial.id)).toMatchObject({
        modalidad_reunion: 'presencial',
        ubicacion_reunion: 'Av. Arequipa 123',
        enlace_reunion: null,
      })
      expect(api().tareas.find((t) => t.id === virtual.id)).toMatchObject({
        modalidad_reunion: 'virtual',
        ubicacion_reunion: null,
        enlace_reunion: 'https://meet.google.com/abc-defg-hij',
      })
    })

    it('sin avance real no se inventa el campo (una llamada no es una reunión)', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'llamada', titulo: 'Llamar a María', vence_en: manana() }),
      )

      expect(res.ok).toBe(true)
      expect(res.avance).toBeUndefined()
      expect(api().lead('l2')?.etapa).toBe('contactado')
    })
  })

  // ANULAR — el cuarto verbo (pedido de Miguel 2026-07-26). El escenario exacto
  // que lo motivó: agendas la reunión y la llamada vieja sobra. Antes de esto,
  // sacarla de la agenda EXIGÍA cerrarla con «Contestó»/«No contestó» —una
  // afirmación falsa sobre el cliente, en un log inmutable, que además podía
  // subir la etapa del lead.
  describe('anularTarea (la tarea que dejó de tener sentido)', () => {
    const manana = (): string => new Date(Date.now() + 86_400_000).toISOString()

    it('el caso de Miguel: agendar la reunión y anular la llamada que sobra', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const previas = api().tareasDe('l2').length // l2 ya trae una sembrada

      const llamada = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'llamada', titulo: 'Llamar a María', vence_en: manana() }),
      )
      const reunion = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión con María', vence_en: manana(), modalidad_reunion: 'presencial', ubicacion_reunion: 'Av. Arequipa 123' }),
      )
      expect(api().tareasDe('l2')).toHaveLength(previas + 2)

      const res = mutar((a) => a.anularTarea(llamada.id ?? ''))

      expect(res).toMatchObject({ ok: true })
      // La llamada desaparece de las pendientes; la reunión sigue en pie.
      const quedan = api().tareasDe('l2')
      expect(quedan).toHaveLength(previas + 1)
      expect(quedan.map((t) => t.id)).not.toContain(llamada.id)
      expect(quedan.map((t) => t.id)).toContain(reunion.id)
      // …y la tarea quedó CANCELADA, no completada: no cuenta como gestión.
      expect(api().tareas.find((t) => t.id === llamada.id)?.estado).toBe('cancelada')
    })

    it('NO escribe actividad: anular no puede pasar por "atendí al cliente"', async () => {
      // Si anular dejara cualquier fila en el timeline (aunque fuera una nota),
      // movería `referenciaEspera` —el reloj con el que la cola decide a quién
      // destapar— y escondería el lead justo al quedarse SIN plan.
      const { api, mutar } = await montarStore('vendedor')
      const t = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'llamada', titulo: 'Llamar', vence_en: manana() }),
      )
      const antes = api().actividadesDe('l2')

      mutar((a) => a.anularTarea(t.id ?? ''))

      expect(api().actividadesDe('l2')).toEqual(antes)
    })

    // ── EL RETROCESO DE ETAPA ────────────────────────────────────────────────
    // Miguel, 2026-07-26: «si se anula la reu y no se reagenda una en ese mismo
    // momento, debería bajar de etapa». Corrige la regla anterior de esta misma
    // suite —"anular una reunión NO baja la etapa"— que venía de la doctrina de
    // los AUTOMATISMOS (nunca bajan). Aquí no hay automatismo: hay una persona
    // declarando que la reunión ya no existe, y sostener `reunion_agendada` sin
    // reunión viva es sostener un hecho falso.
    it('anular la ÚNICA reunión devuelve el lead a Contactado (y lo dice)', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const reunion = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión', vence_en: manana(), modalidad_reunion: 'virtual', enlace_reunion: 'https://meet.google.com/abc-defg-hij' }),
      )
      expect(api().lead('l2')?.etapa).toBe('reunion_agendada')

      const res = mutar((a) => a.anularTarea(
        reunion.id ?? '',
        { motivo: 'cancelada_cliente' },
      ))

      expect(api().lead('l2')?.etapa).toBe('contactado')
      // Viaja al llamador para que la UI lo CANTE: bajar de etapa en silencio
      // es justo lo que el resto del CRM evita anunciando cada avance.
      expect(res).toMatchObject({ ok: true, retroceso: 'contactado' })
    })

    it('el retroceso deja su rastro de cambio_etapa en el timeline', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const reunion = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión', vence_en: manana(), modalidad_reunion: 'virtual', enlace_reunion: 'https://meet.google.com/abc-defg-hij' }),
      )

      mutar((a) => a.anularTarea(reunion.id ?? '', { motivo: 'cancelada_cliente' }))

      // Es la ÚNICA fila que anular escribe, y no rompe la regla de "no escribe
      // actividad": la cola se mide contra el último CONTACTO REAL, y los
      // cambio_etapa del sistema quedan fuera de ese reloj por diseño.
      const ultima = api().actividadesDe('l2')[0]
      expect(ultima?.tipo).toBe('cambio_etapa')
      expect(ultima?.detalle).toContain('Contactado')
    })

    it('si QUEDA otra reunión viva no baja nada: es el «y no se reagenda»', async () => {
      const { api, mutar } = await montarStore('vendedor')
      const primera = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión A', vence_en: manana(), modalidad_reunion: 'presencial', ubicacion_reunion: 'Av. Arequipa 123' }),
      )
      mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión B', vence_en: manana(), modalidad_reunion: 'virtual', enlace_reunion: 'https://meet.google.com/abc-defg-hij' }),
      )

      const res = mutar((a) => a.anularTarea(
        primera.id ?? '',
        { motivo: 'cancelada_cliente' },
      ))

      expect(res).toMatchObject({ ok: true })
      expect(res.retroceso).toBeUndefined()
      expect(api().lead('l2')?.etapa).toBe('reunion_agendada')
    })

    it('anular una LLAMADA nunca mueve la etapa', async () => {
      const { api, mutar } = await montarStore('vendedor')
      mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión', vence_en: manana(), modalidad_reunion: 'virtual', enlace_reunion: 'https://meet.google.com/abc-defg-hij' }),
      )
      const llamada = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'llamada', titulo: 'Llamar', vence_en: manana() }),
      )

      const res = mutar((a) => a.anularTarea(llamada.id ?? ''))

      expect(res.retroceso).toBeUndefined()
      expect(api().lead('l2')?.etapa).toBe('reunion_agendada')
    })

    it('una tarea ya anulada no se puede volver a anular (espejo del `for update`)', async () => {
      const { mutar } = await montarStore('vendedor')
      const t = mutar((a) =>
        a.crearTarea({ lead_id: 'l2', tipo: 'llamada', titulo: 'Llamar', vence_en: manana() }),
      )
      mutar((a) => a.anularTarea(t.id ?? ''))

      const segunda = mutar((a) => a.anularTarea(t.id ?? ''))

      expect(segunda).toMatchObject({ ok: false, codigo: 'no_encontrado' })
    })

    it('una tarea inexistente no revienta el store', async () => {
      const { mutar } = await montarStore('vendedor')

      expect(mutar((a) => a.anularTarea('no-existe'))).toMatchObject({
        ok: false,
        codigo: 'no_encontrado',
      })
    })
  })

  describe('editarLead (paridad de validación con crearLead)', () => {
    it.each([null, 0, -1] as const)('rechaza capital estimado no positivo al editar: %s', async (monto) => {
      const { api, mutar } = await montarStore('vendedor')
      const anterior = api().lead('l1')?.monto_estimado

      const res = mutar((a) =>
        a.editarLead('l1', { monto_estimado: monto as unknown as number }),
      )

      expect(res).toMatchObject({ ok: false, codigo: 'monto_invalido', campo: 'monto_estimado' })
      expect(api().lead('l1')?.monto_estimado).toBe(anterior)
    })

    it('edita capital y moneda como una sola clasificación comercial', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.editarLead('l1', { monto_estimado: 25_000, moneda: 'USD' }))

      expect(res).toMatchObject({ ok: true })
      expect(api().lead('l1')).toMatchObject({ monto_estimado: 25_000, moneda: 'USD' })
    })

    it('rechaza una moneda inválida al editar', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) =>
        a.editarLead('l1', { moneda: 'EUR' as unknown as NuevoLeadInput['moneda'] }),
      )

      expect(res).toMatchObject({ ok: false, codigo: 'moneda_invalida', campo: 'moneda' })
      expect(api().lead('l1')?.moneda).toBe('PEN')
    })

    it('rechaza un correo inválido al editar', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.editarLead('l1', { correo: 'no-es-correo' }))

      expect(res).toMatchObject({ ok: false, codigo: 'correo_invalido', campo: 'correo' })
      expect(api().lead('l1')?.correo).toBeUndefined()
    })

    it('rechaza un teléfono inválido al editar', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) => a.editarLead('l1', { telefono: 'abc' }))

      expect(res).toMatchObject({ ok: false, codigo: 'telefono_invalido', campo: 'telefono' })
      expect(api().lead('l1')?.telefono).toBe('+51987654321')
    })

    it('aplica el dedup vivo también al editar (teléfono de otro abierto)', async () => {
      const { api, mutar } = await montarStore('vendedor')

      // 987654322 es el teléfono de l2 (abierto)
      const res = mutar((a) => a.editarLead('l1', { telefono: '987654322' }))

      expect(res).toMatchObject({ ok: false, codigo: 'duplicado_telefono', campo: 'telefono' })
      expect(api().lead('l1')?.telefono).toBe('+51987654321')
    })

    // GUARD DE TERMINAL. Era el único escritor de leads sin él, y de esa grieta
    // colgaba una cifra de negocio: cada edición reescribe `actualizado_en`, que
    // era el "mes de cierre" del marcador — tocar un convertido de julio en
    // agosto le sumaba un cierre falso a agosto y se lo quitaba a julio.
    it.each([
      ['l9', 'convertido', /ya es cliente/i],
      ['l8', 'descartado', /reábrelo/i],
    ] as const)('un lead %s (%s) NO se edita: la ficha cerrada es un acta', async (id, _etapa, mensaje) => {
      const { api, mutar } = await montarStore('vendedor')
      const antes = api().lead(id)?.nota

      const res = mutar((a) => a.editarLead(id, { nota: 'retoque tardío', telefono: '900555444' }))

      expect(res).toMatchObject({ ok: false, codigo: 'lead_cerrado' })
      expect(res.error).toMatch(mensaje)
      expect(api().lead(id)?.nota).toBe(antes)
      expect(api().lead(id)?.telefono).not.toBe('+51900555444')
    })

    it('edita y normaliza campos válidos (trim de nombre, correo y +51 en teléfono)', async () => {
      const { api, mutar } = await montarStore('vendedor')

      const res = mutar((a) =>
        a.editarLead('l1', {
          nombre_completo: '  JUAN P. ROJAS  ',
          correo: ' juan.rojas@mail.com ',
          telefono: '900 000 111',
        }),
      )

      expect(res).toMatchObject({ ok: true })
      expect(api().lead('l1')).toMatchObject({
        nombre_completo: 'JUAN P. ROJAS',
        correo: 'juan.rojas@mail.com',
        telefono: '+51900000111',
      })
    })
  })
})
