// El aviso de degradación es fuente ÚNICA para las 9 franjas «no se pudieron
// cargar los indicadores» del CRM. Estos tests fijan los defectos que el patrón
// arrastraba clonado, para que ningún aviso nuevo los reintroduzca.
//
// ⚠️ El reintento SIEMPRE se resuelve de forma ASÍNCRONA aquí. Una primera
// versión de este archivo lo resolvía dentro del propio click y daba verde con
// un rescate de foco que en producción era código muerto: el refetch real tarda
// cientos de ms y el aviso se desmonta mucho después del click.
import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { AvisoDegradacion } from './aviso-degradacion'

/** Pantalla de mentira: el reintento tarda, como el de verdad. */
function Pantalla({ exito, demora = 30 }: { exito: boolean; demora?: number }) {
  const [fallando, setFallando] = useState(true)
  return (
    <>
      <button type="button">antes</button>
      <AvisoDegradacion
        activo={fallando}
        queReintenta="de los indicadores"
        onReintentar={() => { setTimeout(() => { if (exito) setFallando(false) }, demora) }}
      >
        No se pudieron cargar los indicadores.
      </AvisoDegradacion>
      <button type="button">después</button>
    </>
  )
}

describe('AvisoDegradacion', () => {
  it('sin error no anuncia nada (el ancla de foco no es un aviso)', () => {
    render(
      <AvisoDegradacion activo={false} queReintenta="de los indicadores" onReintentar={vi.fn()}>
        No se pudieron cargar los indicadores.
      </AvisoDegradacion>,
    )
    expect(screen.queryByRole('button')).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toBeEmptyDOMElement()
  })

  it('con error anuncia el motivo por una región viva y ofrece reintentar', async () => {
    const reintentar = vi.fn()
    render(
      <AvisoDegradacion activo queReintenta="de los indicadores de la cola" onReintentar={reintentar}>
        No se pudieron cargar los indicadores de la cola.
      </AvisoDegradacion>,
    )
    expect(screen.getByRole('status')).toHaveTextContent('No se pudieron cargar los indicadores de la cola.')

    await userEvent.setup().click(screen.getByRole('button'))
    expect(reintentar).toHaveBeenCalledTimes(1)
  })

  it('el botón se distingue de otros «Reintentar» por su nombre accesible', () => {
    render(
      <AvisoDegradacion activo queReintenta="de los plazos del reloj SLA" onReintentar={vi.fn()}>
        No se pudo cargar el reloj SLA.
      </AvisoDegradacion>,
    )
    // Y el complemento llega declinado: «de + el» jamás debe salir en voz alta.
    expect(screen.getByRole('button', { name: 'Reintentar la carga de los plazos del reloj SLA' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /de el /i })).not.toBeInTheDocument()
  })

  it('si el reintento TARDA y funciona, el foco no cae a <body> al desaparecer el aviso', async () => {
    render(<Pantalla exito />)

    const boton = screen.getByRole('button', { name: /^Reintentar/ })
    boton.focus()
    await userEvent.setup().click(boton)

    // El aviso sigue mientras vuela la petición: nada que rescatar todavía.
    expect(screen.getByRole('status')).toHaveTextContent('No se pudieron cargar')

    await waitFor(() => expect(screen.queryByRole('button', { name: /^Reintentar/ })).not.toBeInTheDocument())
    await waitFor(() => expect(document.activeElement).not.toBe(document.body))
  })

  it('si el reintento falla, el aviso sigue y nadie toca el foco', async () => {
    render(<Pantalla exito={false} />)

    const boton = screen.getByRole('button', { name: /^Reintentar/ })
    boton.focus()
    await userEvent.setup().click(boton)

    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('No se pudieron cargar'))
    expect(document.activeElement).toBe(boton)
  })

  it('si el usuario se movió a otro control mientras tardaba, NO se le roba el foco', async () => {
    render(<Pantalla exito demora={60} />)
    const usuario = userEvent.setup()

    const boton = screen.getByRole('button', { name: /^Reintentar/ })
    boton.focus()
    await usuario.click(boton)
    const otro = screen.getByRole('button', { name: 'después' })
    otro.focus()

    await waitFor(() => expect(screen.queryByRole('button', { name: /^Reintentar/ })).not.toBeInTheDocument())
    expect(document.activeElement).toBe(otro)
  })
})
