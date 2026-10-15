import { useState } from 'react'
import { esFiltroCampania, type FiltroCampania } from './campania'

function leer(clave: string | null): FiltroCampania {
  try {
    const valor = clave ? sessionStorage.getItem(clave) : null
    return esFiltroCampania(valor) ? valor : 'todas'
  } catch {
    return 'todas'
  }
}

/** Conserva la selección al recargar esta pestaña, separada por cuenta y demo. */
export function useFiltroCampania(actor: string | null) {
  const clave = actor ? `crm:cartera:campania:${actor}` : null
  const [estado, setEstado] = useState(() => ({ clave, valor: leer(clave) }))
  const actual = estado.clave === clave ? estado : { clave, valor: leer(clave) }
  // Un cambio de cuenta no debe renderizar ni consultar con la selección anterior.
  if (estado.clave !== clave) setEstado(actual)
  function seleccionar(valor: FiltroCampania) {
    setEstado({ clave, valor })
    try {
      if (clave) sessionStorage.setItem(clave, valor)
    } catch { /* La selección sigue funcionando si el navegador impide guardar. */ }
  }
  return [actual.valor, seleccionar] as const
}
