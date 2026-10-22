// D-53 (bloque 2.14): la marca «de baja» / «suspendido» junto al nombre del analista en «Citas del equipo», con el mismo
// estilo que el 2.12 (agenda del equipo): «de baja» apagado y «suspendido» con el color de «Suspendido en Portal». La marca
// dice la verdad de esta pantalla (P3-3 de Codex en el 2.12): el analista aparece porque tiene citas en la consulta.
import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import { MarcaAnalista } from './marca-analista'
import { sufijoEstado } from './modelo'

afterEach(cleanup)

describe('MarcaAnalista (D-53)', () => {
  it('«de baja»: etiqueta apagada con su explicación', () => {
    render(<MarcaAnalista estado="de_baja" />)
    const marca = screen.getByText('de baja')
    expect(marca).toHaveAttribute('title', expect.stringMatching(/dado de baja del equipo/i))
    expect(marca).toHaveAttribute('title', expect.stringContaining('sus citas, leads y capital del mes siguen en la consulta y en los totales'))
    expect(marca.style.getPropertyValue('--c')).toBe('var(--muted-foreground)')
  })
  it('«suspendido»: etiqueta con el color de «Suspendido en Portal» y su explicación', () => {
    render(<MarcaAnalista estado="suspendido" />)
    const marca = screen.getByText('suspendido')
    expect(marca).toHaveAttribute('title', expect.stringMatching(/suspendido en el Portal/i))
    expect(marca).toHaveAttribute('title', expect.stringContaining('su ficha del CRM sigue activa'))
    expect(marca.style.getPropertyValue('--c')).toBe('var(--destructive)')
  })
  it('activo o sin estado (servidor anterior): no pinta nada', () => {
    const { container } = render(<><MarcaAnalista estado="activo" /><MarcaAnalista /></>)
    expect(container).toBeEmptyDOMElement()
  })
  it('sufijoEstado: el texto para donde no cabe una etiqueta (las opciones del filtro)', () => {
    expect(sufijoEstado('de_baja')).toBe(' · de baja')
    expect(sufijoEstado('suspendido')).toBe(' · suspendido')
    expect(sufijoEstado('activo')).toBe('')
    expect(sufijoEstado(undefined)).toBe('')
  })
})
