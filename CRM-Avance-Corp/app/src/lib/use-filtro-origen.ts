import { useState } from 'react'
import { esOrigen, type Origen } from './tipos'

type FiltroOrigen = Origen | 'todos'

function leer(actor: string | null): FiltroOrigen {
  if (!actor) return 'todos'
  try {
    const clave = `crm:cartera:origen:${actor}`
    const valor = sessionStorage.getItem(clave)
    if (valor === 'todos' || esOrigen(valor)) return valor
    // La campaña F3 se convirtió en origen. Migrar solo la preferencia de esta
    // cuenta, sin mantener un segundo filtro invisible que oculte resultados.
    const anterior = sessionStorage.getItem(`crm:cartera:campania:${actor}`)
    const origen = anterior === 'Formulario 3' ? 'formulario_3' : 'todos'
    sessionStorage.setItem(clave, origen)
    return origen
  } catch { return 'todos' }
}

export function useFiltroOrigen(actor: string | null) {
  const [estado, setEstado] = useState(() => ({ actor, valor: leer(actor) }))
  const actual = estado.actor === actor ? estado : { actor, valor: leer(actor) }
  if (estado.actor !== actor) setEstado(actual)
  function seleccionar(valor: FiltroOrigen) {
    setEstado({ actor, valor })
    try {
      if (actor) sessionStorage.setItem(`crm:cartera:origen:${actor}`, valor)
    } catch { /* El filtro funciona también sin almacenamiento. */ }
  }
  return [actual.valor, seleccionar] as const
}
