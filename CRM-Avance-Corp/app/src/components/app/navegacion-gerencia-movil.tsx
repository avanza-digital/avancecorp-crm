import { useRef, useState } from 'react'
import * as Dialog from '@radix-ui/react-dialog'
import { ChevronDown, ChevronRight, Ellipsis, LogOut, X, type LucideIcon } from 'lucide-react'
import type { Vista } from '@/lib/router'
import { Avatar } from '@/components/ui/avatar'
import './navegacion-gerencia-movil.css'

interface Entrada { id: Vista; label: string; icon: LucideIcon }
interface Grupo { grupo: string; label: string; items: readonly Entrada[] }
const PRINCIPALES: readonly Vista[] = ['hoy', 'reuniones', 'gestion-diaria']

/** Recibe exactamente las entradas que el menú lateral ya autorizó. */
export function NavegacionGerenciaMovil({ vista, grupos, nombre, demo, onNavegar, onSalir, esActiva }: {
  vista: Vista
  grupos: readonly Grupo[]
  nombre: string
  demo: boolean
  onNavegar: (vista: Vista) => void
  onSalir: () => void
  esActiva: (vista: Vista) => boolean
}) {
  const [panel, setPanel] = useState({ vista, abierto: false })
  // Atrás, adelante y enlaces externos también cierran el panel de navegación.
  if (panel.vista !== vista) setPanel({ vista, abierto: false })
  const abierto = panel.vista === vista && panel.abierto
  const navegando = useRef(false)
  const disparador = useRef<HTMLButtonElement>(null)
  const entradas = grupos.flatMap(g => g.items)
  const accesos = PRINCIPALES.flatMap(id => entradas.filter(n => n.id === id))
  const secundarios = grupos.map(g => ({ ...g, items: g.items.filter(n => !PRINCIPALES.includes(n.id)) }))
    .filter(g => g.items.length > 0)
  const masActivo = secundarios.some(g => g.items.some(n => esActiva(n.id)))
  const cambiar = (destino: Vista) => {
    navegando.current = true
    setPanel({ vista, abierto: false })
    onNavegar(destino)
  }
  const entrada = (n: Entrada) => <button key={n.id} type="button" className="gm-menu-entrada"
    aria-current={esActiva(n.id) ? 'page' : undefined} onClick={() => cambiar(n.id)}>
    <n.icon size={20} aria-hidden /><span>{n.label}</span><ChevronRight size={16} aria-hidden />
  </button>

  return <Dialog.Root open={abierto} onOpenChange={valor => {
    navegando.current = false
    setPanel({ vista, abierto: valor })
  }}>
    <nav className="gm-barra" aria-label="Navegación principal de Gerencia">
      {accesos.map(n => <button key={n.id} type="button" className="gm-destino"
        aria-current={esActiva(n.id) ? 'page' : undefined} onClick={() => onNavegar(n.id)}>
        <span className="gm-icono"><n.icon size={22} aria-hidden /></span>
        <span>{n.label}</span>
      </button>)}
      <Dialog.Trigger asChild>
        <button ref={disparador} type="button" className="gm-destino"
          aria-current={masActivo ? 'true' : undefined} data-activo={masActivo || abierto ? '' : undefined}>
          <span className="gm-icono"><Ellipsis size={24} aria-hidden /></span><span>Más</span>
        </button>
      </Dialog.Trigger>
    </nav>
    <Dialog.Portal>
      <Dialog.Overlay className="gm-overlay" />
      <Dialog.Content className="gm-panel" onCloseAutoFocus={evento => {
        // Al pasar a tablet el disparador desaparece: devolver el foco al contenido.
        if (navegando.current || !disparador.current?.isConnected) {
          evento.preventDefault()
          requestAnimationFrame(() => document.querySelector<HTMLElement>('main')?.focus({ preventScroll: true }))
          navegando.current = false
        }
      }}>
        <div className="gm-panel-cabecera">
          <div><Dialog.Title>Más opciones</Dialog.Title>
            <Dialog.Description>Todos tus módulos, a mano.</Dialog.Description></div>
          <Dialog.Close className="gm-cerrar" aria-label="Cerrar más opciones"><X size={22} aria-hidden /></Dialog.Close>
        </div>
        <div className="gm-modulos ac-scroll">
          {secundarios.map(g => g.grupo === 'principal'
            ? <section key={g.grupo} aria-label="Gestión del equipo" className="gm-prioritarios">{g.items.map(entrada)}</section>
            : <details key={g.grupo} className="gm-grupo" open={g.items.some(n => esActiva(n.id)) || undefined}>
              <summary>{g.label}<ChevronDown size={18} aria-hidden /></summary>
              <div>{g.items.map(entrada)}</div>
            </details>)}
        </div>
        <div className="gm-cuenta">
          <Avatar nombre={nombre} color="#2563eb" className="size-9" />
          <div className="gm-identidad"><strong>{nombre}</strong><span>Gerencia{demo ? ' · Demo' : ''}</span></div>
          <button type="button" onClick={onSalir} aria-label="Cerrar sesión" title="Cerrar sesión"><LogOut size={20} aria-hidden /></button>
        </div>
      </Dialog.Content>
    </Dialog.Portal>
  </Dialog.Root>
}
