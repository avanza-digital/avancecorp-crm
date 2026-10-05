// La carga de un archivo frente a lo INCIERTO (Codex F5 r1): elegir otro archivo mientras se lee el primero (solo la última
// lectura cuenta y el informe es el del archivo realmente cargado), un lote cuya respuesta se perdió tras guardarse
// («Terminar aquí» lo repite con su MISMO id antes de cerrar) y un fallo incierto al crear la base (se reintenta con el
// MISMO id; solo un rechazo de negocio vuelve al formulario). El lector se simula para controlar cuándo termina cada uno.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { TablaArchivo } from '@/lib/bases-cargadas'

const { lecturas } = vi.hoisted(() => ({ lecturas: new Map<string, { resolver: (t: TablaArchivo) => void; promesa: Promise<TablaArchivo> }>() }))
vi.mock('@/lib/bases-cargadas-archivo', async (original) => ({
  ...(await original<typeof import('@/lib/bases-cargadas-archivo')>()),
  leerArchivoBase: (archivo: File) => {
    let resolver: (t: TablaArchivo) => void = () => undefined
    const promesa = new Promise<TablaArchivo>((r) => { resolver = r })
    lecturas.set(archivo.name, { resolver, promesa })
    return promesa
  },
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), info: vi.fn(), error: vi.fn() } }))

const { ErrorBases } = await import('@/data/bases-cargadas-api')
const { CargaArchivo } = await import('./carga-archivo')

const BASE = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const fuente = {
  crearBase: vi.fn(), cargarBaseLote: vi.fn(),
  seguimientoBases: vi.fn(), seguimientoBase: vi.fn(), seguimientoBaseDetalle: vi.fn(), contactosDeBase: vi.fn(),
  armarBaseCrm: vi.fn(), repartirBase: vi.fn(), recogerDeBase: vi.fn(),
}
const tabla = (filas: [string, string][]): TablaArchivo => ({ encabezados: ['Nombre', 'Celular'], filas: filas.map((celdas, i) => ({ numero: i + 2, celdas })) })
const respuesta = (filas: { fila: number }[]) => ({
  ok: true as const, base_id: BASE, lote: { cargadas: filas.length, ya_existian: 0, no_contactar: 0, invalidas: 0, repetidas: 0 },
  base: { filas_recibidas: 0, cargadas: 0 }, filas: filas.map((f) => ({ fila: f.fila, veredicto: 'cargada', motivo: null, lead_id: null })),
})

function montar() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(
    <QueryClientProvider client={cliente}>
      <CargaArchivo puertas={{ fuente, modo: 'real', activa: true }} esGerencia={false} supervisores={[]} onVerBase={vi.fn()} onEnCurso={vi.fn()} />
    </QueryClientProvider>,
  )
}
async function elegir(nombre: string) {
  await userEvent.upload(screen.getByLabelText(/(Elegir|Cambiar) archivo/), new File(['x'], nombre))
}

beforeEach(() => {
  lecturas.clear()
  fuente.crearBase.mockResolvedValue({ ok: true, base_id: BASE, supervisor_id: 'sup' })
  fuente.cargarBaseLote.mockImplementation(async ({ filas }: { filas: { fila: number }[] }) => respuesta(filas))
})
afterEach(() => vi.clearAllMocks())

describe('elegir otro archivo mientras se lee el primero', () => {
  it('solo la ÚLTIMA lectura escribe; «Cargar» espera a que termine; el informe es el del archivo realmente cargado', async () => {
    montar()
    await elegir('a.csv')
    await elegir('b.csv')
    // Termina B primero y A después (tarde): A no pisa nada.
    lecturas.get('b.csv')?.resolver(tabla([['DE B UNO', '987000001'], ['DE B DOS', '987000002']]))
    expect(await screen.findByText('b.csv · 2 filas con datos')).toBeInTheDocument()
    lecturas.get('a.csv')?.resolver(tabla([['DE A', '987000009']]))
    await new Promise((r) => setTimeout(r, 0))
    expect(screen.getByText('b.csv · 2 filas con datos')).toBeInTheDocument()
    expect(screen.getByLabelText('Nombre de la base')).toHaveValue('b')
    // Mientras se lee otro archivo, «Cargar» no carga (aria-disabled y lo dice).
    await elegir('c.csv')
    const cargar = screen.getByRole('button', { name: /Cargar 2 contactos/ })
    expect(cargar).toHaveAttribute('aria-disabled', 'true')
    await userEvent.click(cargar)
    expect(screen.getByRole('alert')).toHaveTextContent('Espera a que termine de leerse el archivo')
    expect(fuente.crearBase).not.toHaveBeenCalled()
    lecturas.get('c.csv')?.resolver(tabla([['DE C', '987000003']]))
    await userEvent.click(await screen.findByRole('button', { name: /Cargar 1 contacto/ }))
    expect(await screen.findByRole('heading', { name: /Informe de «b»/ })).toBeInTheDocument()
    expect(fuente.crearBase).toHaveBeenCalledWith(expect.objectContaining({ archivoNombre: 'c.csv' }))
    expect(fuente.cargarBaseLote).toHaveBeenCalledWith(expect.objectContaining({ filas: [{ fila: 2, nombre: 'DE C', telefono: '+51987000003' }] }))
    expect(screen.getByText(/1 filas de c\.csv/)).toBeInTheDocument()
  })
})

async function prepararYCargar(filas: [string, string][]) {
  montar()
  await elegir('feria.csv')
  lecturas.get('feria.csv')?.resolver(tabla(filas))
  await userEvent.click(await screen.findByRole('button', { name: /^Cargar \d+ contacto/ }))
}

describe('«Terminar aquí» con un lote de resultado incierto', () => {
  it('la respuesta se perdió TRAS guardarse: antes de cerrar se repite con el MISMO id y sus filas salen con su veredicto real', async () => {
    let primera = true
    fuente.cargarBaseLote.mockImplementation(async ({ filas }: { filas: { fila: number }[] }) => {
      if (primera) { primera = false; throw new ErrorBases('Se cortó la conexión', 'RED') }
      return respuesta(filas)
    })
    await prepararYCargar([['UNO', '987000001'], ['DOS', '987000002']])
    await userEvent.click(await screen.findByRole('button', { name: 'Terminar aquí y ver el informe' }))
    await screen.findByRole('heading', { name: 'Carga detenida: «feria»' })
    const ids = fuente.cargarBaseLote.mock.calls.map(([e]) => (e as { operacionId: string }).operacionId)
    expect(ids).toHaveLength(2)
    expect(ids[0]).toBe(ids[1])
    const tipos = screen.getByRole('group', { name: 'Resultado por tipo' })
    expect(within(tipos).getByRole('button', { name: /Cargadas:\s?2/ })).toBeInTheDocument()
    expect(within(tipos).queryByRole('button', { name: /Sin enviar/ })).toBeNull()
  })

  it('si el replay tampoco responde, ese lote sale «Sin confirmar» (no «Sin enviar»)', async () => {
    fuente.cargarBaseLote.mockRejectedValue(new ErrorBases('Se cortó la conexión', 'RED'))
    await prepararYCargar([['UNO', '987000001'], ['DOS', '987000002']])
    await userEvent.click(await screen.findByRole('button', { name: 'Terminar aquí y ver el informe' }))
    await screen.findByRole('heading', { name: 'Carga detenida: «feria»' })
    const tipos = screen.getByRole('group', { name: 'Resultado por tipo' })
    expect(within(tipos).getByRole('button', { name: /Sin confirmar:\s?2/ })).toBeInTheDocument()
    expect(within(tipos).queryByRole('button', { name: /Sin enviar/ })).toBeNull()
    expect(screen.getAllByText(/Se envió pero no hubo respuesta/)).toHaveLength(2)
  })

  it('un rechazo concreto del servidor (nada se guardó) no se repite: lo pendiente sale «Sin enviar»', async () => {
    fuente.cargarBaseLote.mockRejectedValue(new ErrorBases('Una base recibe hasta 5000 filas', 'REGLA_SERVIDOR'))
    await prepararYCargar([['UNO', '987000001']])
    await userEvent.click(await screen.findByRole('button', { name: 'Terminar aquí y ver el informe' }))
    await screen.findByRole('heading', { name: 'Carga detenida: «feria»' })
    expect(fuente.cargarBaseLote).toHaveBeenCalledTimes(1)
    expect(within(screen.getByRole('group', { name: 'Resultado por tipo' })).getByRole('button', { name: /Sin enviar:\s?1/ })).toBeInTheDocument()
  })
})

describe('fallo incierto al CREAR la base', () => {
  it('no descarta el plan: «Reintentar» repite crear_base con el MISMO id (replay) y sigue', async () => {
    fuente.crearBase.mockRejectedValueOnce(new ErrorBases('El servidor no confirmó la base.', 'BASES_CONTRACT'))
    await prepararYCargar([['UNO', '987000001']])
    expect(await screen.findByRole('alert')).toHaveTextContent('El servidor no confirmó la base')
    expect(screen.queryByRole('button', { name: 'Terminar aquí y ver el informe' })).toBeNull()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(await screen.findByRole('heading', { name: /Informe de «feria»/ })).toBeInTheDocument()
    const ids = fuente.crearBase.mock.calls.map(([e]) => (e as { operacionId: string }).operacionId)
    expect(ids).toHaveLength(2)
    expect(ids[0]).toBe(ids[1])
  })

  it('un rechazo de negocio definitivo vuelve al formulario: sin permiso → el foco al botón «Cargar», que lleva el error', async () => {
    fuente.crearBase.mockRejectedValueOnce(new ErrorBases('Solo Supervisión y Gerencia cargan y arman bases', 'SIN_PERMISO'))
    await prepararYCargar([['UNO', '987000001']])
    const cargar = await screen.findByRole('button', { name: /Cargar 1 contacto/ })
    expect(cargar).toHaveAccessibleDescription(/Solo Supervisión y Gerencia/)
    await waitFor(() => expect(cargar).toHaveFocus())
  })
})

describe('foco al validar', () => {
  it('sin nombre de la base, el foco va al campo del nombre', async () => {
    montar()
    await elegir('x.csv')
    lecturas.get('x.csv')?.resolver(tabla([['UNO', '987000001']]))
    await userEvent.clear(await screen.findByLabelText('Nombre de la base'))
    await userEvent.click(screen.getByRole('button', { name: /Cargar 1 contacto/ }))
    expect(screen.getByLabelText('Nombre de la base')).toHaveFocus()
    expect(screen.getByLabelText('Cambiar archivo')).toBeInTheDocument()
  })
})
