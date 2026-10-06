import { useId, useState, type ReactNode } from 'react'
import { SlidersHorizontal } from 'lucide-react'
import { Button } from '@/components/ui/button'

/** Una sola instancia de los controles: se pliegan por CSS solo en Gerencia móvil. */
export function ControlesMoviles({ titulo, resumen, aviso, children }: { titulo: string; resumen: string; aviso?: ReactNode; children: ReactNode }) {
  const [abiertos, setAbiertos] = useState(false)
  const id = useId()
  return <div className="gm-controles">
    <div className="gm-controles-resumen"><p>{resumen}</p><Button type="button" variant="outline" aria-controls={id} aria-expanded={abiertos} onClick={() => setAbiertos(v => !v)}><SlidersHorizontal aria-hidden />{titulo}</Button></div>
    {aviso}
    <div id={id} className="gm-controles-campos" data-abiertos={abiertos}>{children}</div>
  </div>
}
