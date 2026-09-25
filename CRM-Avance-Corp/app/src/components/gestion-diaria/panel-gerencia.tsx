import { type ReactNode, type RefObject } from 'react'
import { Title as TituloDialogo } from '@radix-ui/react-dialog'
import { Maximize2, Minimize2, Users, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PanelSupervisorAdaptable } from './panel-supervisor-adaptable'

export function PanelGerencia({ id, titulo, abierto, estrecho, ampliado, ampliar, cerrar, tituloRef, children, vacio, etiqueta = 'Detalle de la operación' }: {
  id: string
  titulo: string
  abierto: boolean
  estrecho: boolean
  ampliado: boolean
  ampliar: () => void
  cerrar: () => void
  tituloRef: RefObject<HTMLHeadingElement | null>
  children: ReactNode
  vacio: string
  etiqueta?: string
}) {
  return <PanelSupervisorAdaptable modal={abierto && (estrecho || ampliado)} cerrar={cerrar} tituloRef={tituloRef}>
    <section id={id} className="gd-panel gp-detalle" aria-label={etiqueta}>
      <header className="gd-panel-cabecera">
        <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1}>{titulo}</h3></TituloDialogo>
        {abierto && <div className="flex shrink-0">
          {!estrecho && <Button variant="ghost" size="icon" className="size-11" aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden /> : <Maximize2 aria-hidden />}</Button>}
          <Button variant="ghost" size="icon" className="size-11" aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden /></Button>
        </div>}
      </header>
      {abierto ? children : <div className="gd-panel-inicial"><Users className="size-10" aria-hidden /><p>{vacio}</p></div>}
    </section>
  </PanelSupervisorAdaptable>
}
