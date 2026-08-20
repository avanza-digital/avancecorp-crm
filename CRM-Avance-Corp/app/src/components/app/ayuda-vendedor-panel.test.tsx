import { useState } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ResultadoConsultaAyudaVendedor } from '@/lib/ayuda-vendedor'
import type { Vista } from '@/lib/router'
import { AyudaVendedorPanel } from './ayuda-vendedor-panel'

const api = vi.hoisted(() => ({
  consultar: vi.fn(),
  inicio: vi.fn(),
  mensaje: vi.fn((error: unknown, porDefecto: string) => (error instanceof Error ? error.message : porDefecto)),
}))

vi.mock('@/data/crm-api', () => ({
  consultarAyudaVendedor: api.consultar,
  obtenerInicioAyudaVendedor: api.inicio,
  mensajeDeError: api.mensaje,
}))

const reprogramar: ResultadoConsultaAyudaVendedor = {
  version: 1,
  tipo: 'respuesta',
  respuesta: {
    id: 'reprogramar-reunion',
    titulo: 'Reprogramar una reunión sin perder el seguimiento',
    resumen: 'Muévela desde Agenda y conserva su historial.',
    duracion: '1 min',
    pasos: [{ titulo: 'Elige el nuevo plazo', detalle: 'Usa +1d, +3d o +1sem.' }],
    accion: { tipo: 'navegar', vista: 'agenda', etiqueta: 'Ir a Agenda' },
    fuente: 'Manual del vendedor · Agenda · versión aprobada',
  },
}

const registrarLead: ResultadoConsultaAyudaVendedor = {
  version: 1,
  tipo: 'respuesta',
  respuesta: {
    id: 'registrar-lead',
    titulo: 'Registrar un lead y dejarlo listo para trabajar',
    resumen: 'Crea el contacto y termina con una siguiente acción.',
    duracion: '2 min',
    pasos: [{ titulo: 'Abre Nuevo lead', detalle: 'Usa el botón azul.' }],
    accion: { tipo: 'nuevo_lead', etiqueta: 'Abrir Nuevo lead' },
    fuente: 'Manual del vendedor · Leads · versión aprobada',
  },
}

const anularTarea: ResultadoConsultaAyudaVendedor = {
  version: 1,
  tipo: 'respuesta',
  respuesta: {
    id: 'anular-tarea-pendiente',
    titulo: 'Quitar una acción pendiente de tu agenda',
    resumen: 'Anula la acción que ya no realizarás.',
    duracion: '1 min',
    traduccion: {
      lenguajeVendedor: 'Eliminar o borrar una acción',
      lenguajeCrm: 'Anular tarea',
    },
    pasos: [{ titulo: 'Ubica la acción', detalle: 'Encuéntrala en Agenda.' }],
    accion: { tipo: 'navegar', vista: 'agenda', etiqueta: 'Ir a Agenda' },
    fuente: 'Manual del vendedor · Acciones pendientes · versión aprobada',
  },
}

const corregirActividad: ResultadoConsultaAyudaVendedor = {
  version: 1,
  tipo: 'respuesta',
  respuesta: {
    id: 'corregir-actividad-registrada',
    titulo: 'Corregir una gestión que ya quedó en el historial',
    resumen: 'La corrección se deja como una Nota.',
    duracion: '1 min',
    pasos: [{ titulo: 'Registra una Nota', detalle: 'Explica el dato correcto.' }],
    accion: { tipo: 'navegar', vista: 'cartera', etiqueta: 'Ir a Leads' },
    fuente: 'Manual del vendedor · Historial · versión aprobada',
  },
}

function respuestaPara(consulta: string): ResultadoConsultaAyudaVendedor {
  const normalizada = consulta.toLocaleLowerCase('es-PE')
  if (normalizada.includes('reprogramo')) return reprogramar
  if (normalizada.includes('registro y empiezo')) return registrarLead
  if (normalizada.includes('sacar un pendiente')) return anularTarea
  if (normalizada.includes('eliminar algo')) {
    return {
      version: 1,
      tipo: 'aclaracion',
      aclaracion: {
        titulo: '¿Qué quieres quitar?',
        detalle: 'Indica qué elemento quieres quitar.',
        opciones: [
          {
            etiqueta: 'Una acción que todavía está pendiente',
            detalle: 'Una tarea que no realizarás.',
            consulta: 'como elimino una accion',
          },
          {
            etiqueta: 'Una gestión ya registrada',
            detalle: 'Una actividad guardada por error.',
            consulta: 'como elimino una actividad',
          },
        ],
      },
    }
  }
  if (normalizada.includes('elimino una actividad')) return corregirActividad
  return { version: 1, tipo: 'sin_resultado', consulta }
}

function AyudaControlada({
  vista = 'hoy',
  onNavegar = vi.fn(),
  onAbrirNuevoLead = vi.fn(),
}: {
  vista?: Vista
  onNavegar?: (vista: Vista) => void
  onAbrirNuevoLead?: () => void
}) {
  const [abierto, setAbierto] = useState(true)
  return (
    <AyudaVendedorPanel
      abierto={abierto}
      onAbiertoChange={setAbierto}
      vista={vista}
      onNavegar={onNavegar}
      onAbrirNuevoLead={onAbrirNuevoLead}
    />
  )
}

beforeEach(() => {
  api.consultar.mockReset()
  api.inicio.mockReset()
  api.mensaje.mockClear()
  api.inicio.mockResolvedValue({
    version: 1,
    preguntas: ['¿Cómo reprogramo una reunión?', '¿Cómo registro y empiezo a trabajar un lead?'],
  })
  api.consultar.mockImplementation(async (consulta: string) => respuestaPara(consulta))
})

describe('AyudaVendedorPanel — manual resuelto por el servidor', () => {
  it('muestra Derivar leads pero reutiliza el contexto de ayuda de equipo', async () => {
    const user = userEvent.setup()
    render(<AyudaControlada vista="derivaciones" />)

    expect(await screen.findByText('Derivar leads')).toBeVisible()
    expect(api.inicio).toHaveBeenCalledWith('equipo', expect.any(AbortSignal))

    await user.type(
      screen.getByRole('textbox', { name: '¿Qué necesitas resolver?' }),
      'Quiero revisar el reparto',
    )
    await user.click(screen.getByRole('button', { name: 'Buscar en el manual' }))

    expect(api.consultar).toHaveBeenCalledWith(
      'Quiero revisar el reparto',
      'equipo',
      expect.any(AbortSignal),
    )
  })

  it('consulta una pregunta del servidor, navega y conserva la guía al minimizar', async () => {
    const user = userEvent.setup()
    const onNavegar = vi.fn()
    render(<AyudaControlada vista="agenda" onNavegar={onNavegar} />)

    await user.click(
      await screen.findByRole('button', {
        name: '¿Cómo reprogramo una reunión?',
      }),
    )

    expect(
      await screen.findByRole('heading', {
        name: 'Reprogramar una reunión sin perder el seguimiento',
      }),
    ).toBeVisible()
    expect(api.consultar).toHaveBeenCalledWith('¿Cómo reprogramo una reunión?', 'agenda', expect.any(AbortSignal))
    expect(screen.getByText('Elige el nuevo plazo')).toBeVisible()

    await user.click(screen.getByRole('button', { name: 'Ir a Agenda' }))
    expect(onNavegar).toHaveBeenCalledWith('agenda')

    await user.click(screen.getByRole('button', { name: 'Minimizar ayuda' }))
    const continuar = screen.getByRole('button', {
      name: 'Continuar guía: Reprogramar una reunión sin perder el seguimiento',
    })
    await user.click(continuar)
    expect(
      screen.getByRole('heading', {
        name: 'Reprogramar una reunión sin perder el seguimiento',
      }),
    ).toBeVisible()
  })

  it('abre el alta real desde una acción autorizada por el contrato', async () => {
    const user = userEvent.setup()
    const onAbrirNuevoLead = vi.fn()
    render(<AyudaControlada onAbrirNuevoLead={onAbrirNuevoLead} />)

    await user.click(
      await screen.findByRole('button', {
        name: '¿Cómo registro y empiezo a trabajar un lead?',
      }),
    )
    await user.click(await screen.findByRole('button', { name: 'Abrir Nuevo lead' }))

    expect(onAbrirNuevoLead).toHaveBeenCalledOnce()
  })

  it('distingue una consulta sin resultado de una recomendación', async () => {
    const user = userEvent.setup()
    render(<AyudaControlada />)

    await user.type(
      screen.getByRole('textbox', { name: '¿Qué necesitas resolver?' }),
      '¿Cómo registro una cobranza bancaria?',
    )
    await user.click(screen.getByRole('button', { name: 'Buscar en el manual' }))

    expect(await screen.findByText('Esa respuesta aún no está en el manual')).toBeVisible()
    expect(
      screen.queryByRole('heading', {
        name: 'Registrar un lead y dejarlo listo para trabajar',
      }),
    ).not.toBeInTheDocument()
  })

  it('pinta la traducción de lenguaje comercial devuelta por el servidor', async () => {
    const user = userEvent.setup()
    render(<AyudaControlada vista="agenda" />)

    await user.type(screen.getByRole('textbox', { name: '¿Qué necesitas resolver?' }), 'Quiero sacar un pendiente')
    await user.click(screen.getByRole('button', { name: 'Buscar en el manual' }))

    expect(
      await screen.findByRole('heading', {
        name: 'Quitar una acción pendiente de tu agenda',
      }),
    ).toBeVisible()
    expect(screen.getByText('“Eliminar o borrar una acción”')).toBeVisible()
    expect(screen.getByText('Anular tarea')).toBeVisible()
  })

  it('solicita una aclaración antes de cargar la guía elegida', async () => {
    const user = userEvent.setup()
    render(<AyudaControlada />)

    await user.type(screen.getByRole('textbox', { name: '¿Qué necesitas resolver?' }), 'Quiero eliminar algo')
    await user.click(screen.getByRole('button', { name: 'Buscar en el manual' }))

    expect(await screen.findByRole('heading', { name: '¿Qué quieres quitar?' })).toBeVisible()
    await user.click(screen.getByRole('button', { name: /Una gestión ya registrada/ }))
    expect(
      await screen.findByRole('heading', {
        name: 'Corregir una gestión que ya quedó en el historial',
      }),
    ).toBeVisible()
  })

  it('muestra un fallo del servidor como error y no como sin resultado', async () => {
    api.consultar.mockRejectedValueOnce(new Error('Servicio temporalmente no disponible.'))
    const user = userEvent.setup()
    render(<AyudaControlada />)

    await user.type(screen.getByRole('textbox', { name: '¿Qué necesitas resolver?' }), 'Quiero revisar una tarea')
    await user.click(screen.getByRole('button', { name: 'Buscar en el manual' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Servicio temporalmente no disponible.')
    expect(screen.queryByText('Esa respuesta aún no está en el manual')).not.toBeInTheDocument()
  })
})
