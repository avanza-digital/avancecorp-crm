// Retorno del foco del Sheet cuando su ORIGEN ya no existe (01/10/2026).
//
// El Sheet devuelve el foco al elemento desde el que se abrió. Pero ese nodo
// puede desaparecer mientras la ficha está abierta: en el Pipeline, registrar
// un intento saca la tarjeta de «Nuevo» y la pinta en «Gestionado» — el mismo
// lead, otro nodo. Sin más, al cerrar la ficha el foco caía a <body> y el
// siguiente Tab reiniciaba la página.
//
// La salida es una CLAVE ESTABLE: el origen declara `data-foco-clave` y, si al
// cerrar ya no está conectado, el Sheet enfoca a su gemela. Es aditivo: con el
// origen vivo, o sin clave, todo se comporta como antes.
import { useState, type ReactNode } from 'react'
import { describe, expect, it } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Sheet, SheetTitle } from './sheet'

type Lugar = 'nuevo' | 'gestionado' | 'fuera'

function Tablero({ conClave = true, modal = true, origenInterno = false, conDoble = false, conRespaldo = false, conInicial = false }: {
  conClave?: boolean; modal?: boolean; origenInterno?: boolean
  /** Otro elemento con la MISMA clave, antes que el origen en la página. */
  conDoble?: boolean
  /** La pantalla dice a dónde va el foco si el origen y su gemela ya no existen. */
  conRespaldo?: boolean
  /** La pantalla dice dónde empieza el foco al abrir. */
  conInicial?: boolean
}) {
  const [abierta, setAbierta] = useState(false)
  const [lugar, setLugar] = useState<Lugar>('nuevo')
  const clave = conClave ? { 'data-foco-clave': 'lead-1' } : {}
  // La «tarjeta»: el mismo lead, pero un nodo distinto en cada columna.
  const tarjeta = (): ReactNode => origenInterno
    ? (
      <div {...clave} role="button" tabIndex={0} aria-label="Tarjeta de ROSA" onClick={() => {}} onKeyDown={() => {}}>
        <button onClick={() => setAbierta(true)}>Abrir ficha</button>
      </div>
    )
    : <button {...clave} onClick={() => setAbierta(true)}>Tarjeta de ROSA</button>
  return (
    <>
      {conDoble && <button data-foco-clave="lead-1">Doble con la misma clave</button>}
      <section aria-label="Nuevo">{lugar === 'nuevo' && tarjeta()}</section>
      <section aria-label="Gestionado">{lugar === 'gestionado' && tarjeta()}</section>
      <button>Otro control</button>
      <button>Respaldo del foco</button>
      <Sheet
        open={abierta}
        onClose={() => setAbierta(false)}
        modal={modal}
        {...(conRespaldo ? { focoRespaldo: () => screen.getByRole('button', { name: 'Respaldo del foco' }) } : {})}
        {...(conInicial ? { focoInicial: () => document.getElementById('foco-inicial') } : {})}
      >
        <SheetTitle>Ficha</SheetTitle>
        <button onClick={() => setLugar('gestionado')}>Registrar intento</button>
        <button id="foco-inicial">Primer resultado</button>
        <button onClick={() => setLugar('fuera')}>Descartar</button>
      </Sheet>
    </>
  )
}

const tarjetaEn = (columna: string) => within(screen.getByRole('region', { name: columna })).getByRole('button', { name: 'Tarjeta de ROSA' })

async function abrirYRegistrar(usuario: ReturnType<typeof userEvent.setup>, accion = 'Registrar intento', disparador = 'Tarjeta de ROSA') {
  await usuario.click(screen.getByRole('button', { name: disparador }))
  expect(screen.getByRole('dialog', { name: 'Ficha' })).toBeInTheDocument()
  await usuario.click(screen.getByRole('button', { name: accion }))
}

describe('Sheet · retorno del foco con clave estable', () => {
  it('con el origen vivo devuelve el foco al MISMO nodo (comportamiento de siempre)', async () => {
    const usuario = userEvent.setup()
    render(<Tablero />)
    const origen = tarjetaEn('Nuevo')

    await usuario.click(origen)
    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(origen).toHaveFocus())
  })

  // El cambio es ADITIVO: mientras el origen exista, el foco vuelve a ESE nodo,
  // haya o no otro elemento con su misma clave en la página.
  it('con el origen vivo no busca gemelas: vuelve al origen aunque otro elemento lleve su clave', async () => {
    const usuario = userEvent.setup()
    render(<Tablero conDoble />)
    const origen = tarjetaEn('Nuevo')

    await usuario.click(origen)
    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(origen).toHaveFocus())
    expect(screen.getByRole('button', { name: 'Doble con la misma clave' })).not.toHaveFocus()
  })

  it('…y el inspector NO modal tampoco', async () => {
    const usuario = userEvent.setup()
    render(<Tablero conDoble modal={false} />)
    const origen = tarjetaEn('Nuevo')

    await usuario.click(origen)
    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Ficha' })).not.toBeInTheDocument())
    await waitFor(() => expect(origen).toHaveFocus())
  })

  it('si el origen cambió de sitio con la ficha abierta, el foco va a su gemela', async () => {
    const usuario = userEvent.setup()
    render(<Tablero />)
    await abrirYRegistrar(usuario)
    // El nodo de «Nuevo» ya no existe: el lead vive ahora en «Gestionado».
    expect(within(screen.getByRole('region', { name: 'Nuevo', hidden: true })).queryByRole('button', { hidden: true })).not.toBeInTheDocument()

    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Ficha' })).not.toBeInTheDocument())
    await waitFor(() => expect(tarjetaEn('Gestionado')).toHaveFocus())
  })

  it('si se abrió desde un control DE DENTRO de la tarjeta, la gemela es la tarjeta', async () => {
    const usuario = userEvent.setup()
    render(<Tablero origenInterno />)
    await abrirYRegistrar(usuario, 'Registrar intento', 'Abrir ficha')

    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(tarjetaEn('Gestionado')).toHaveFocus())
  })

  it('un inspector NO modal aplica la misma regla', async () => {
    const usuario = userEvent.setup()
    render(<Tablero modal={false} />)
    await abrirYRegistrar(usuario)

    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Ficha' })).not.toBeInTheDocument())
    await waitFor(() => expect(tarjetaEn('Gestionado')).toHaveFocus())
  })

  it('sin clave no inventa destino: se comporta como antes del cambio', async () => {
    const usuario = userEvent.setup()
    render(<Tablero conClave={false} />)
    await abrirYRegistrar(usuario)

    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Ficha' })).not.toBeInTheDocument())
    expect(tarjetaEn('Gestionado')).not.toHaveFocus()
    expect(screen.getByRole('button', { name: 'Otro control' })).not.toHaveFocus()
  })

  it('con clave pero sin gemela en la página (el lead salió del tablero) no revienta ni roba el foco', async () => {
    const usuario = userEvent.setup()
    render(<Tablero />)
    await abrirYRegistrar(usuario, 'Descartar')

    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Ficha' })).not.toBeInTheDocument())
    expect(screen.queryByRole('button', { name: 'Tarjeta de ROSA' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Otro control' })).not.toHaveFocus()
  })

  it('sin gemela, con respaldo: el foco va al respaldo (no cae en <body>)', async () => {
    const usuario = userEvent.setup()
    render(<Tablero conRespaldo />)
    await abrirYRegistrar(usuario, 'Descartar')

    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(screen.getByRole('button', { name: 'Respaldo del foco' })).toHaveFocus())
  })

  it('con la gemela viva el respaldo no se usa', async () => {
    const usuario = userEvent.setup()
    render(<Tablero conRespaldo />)
    await abrirYRegistrar(usuario)

    await usuario.keyboard('{Escape}')

    await waitFor(() => expect(tarjetaEn('Gestionado')).toHaveFocus())
    expect(screen.getByRole('button', { name: 'Respaldo del foco' })).not.toHaveFocus()
  })
})

describe('Sheet · foco inicial', () => {
  it('con focoInicial el foco empieza ahí; sin él, en el primer control (como siempre)', async () => {
    const usuario = userEvent.setup()
    const { unmount } = render(<Tablero conInicial />)
    await usuario.click(screen.getByRole('button', { name: 'Tarjeta de ROSA' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Primer resultado' })).toHaveFocus())
    unmount()
    render(<Tablero />)
    await usuario.click(screen.getByRole('button', { name: 'Tarjeta de ROSA' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Registrar intento' })).toHaveFocus())
  })
})
