import { useEffect, useState } from 'react'
import { useAuth } from '@/lib/auth'
import { can } from '@/lib/roles'
import { Sidebar } from '@/components/app/sidebar'
import { Topbar } from '@/components/app/topbar'
import { LeadDrawer } from '@/components/app/lead-drawer'
import { LeadNuevo } from '@/components/app/lead-nuevo'
import { Login } from '@/screens/login'
import { NoEnrolado } from '@/screens/no-enrolado'
import { Hoy } from '@/screens/hoy'
import { Pipeline } from '@/screens/pipeline'
import { Cartera } from '@/screens/cartera'
import { Agenda } from '@/screens/agenda'
import { Equipo } from '@/screens/equipo'
import { Config } from '@/screens/config'
import { Skeleton } from '@/components/ui/skeleton'

export type Vista = 'hoy' | 'pipeline' | 'cartera' | 'agenda' | 'equipo' | 'config'

function Splash() {
  return (
    <div className="flex min-h-svh items-center justify-center">
      <div className="w-64 space-y-3">
        <Skeleton className="h-8 w-32" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-3/4" />
        <p className="pt-2 text-center text-xs text-muted-foreground">Preparando tu información…</p>
      </div>
    </div>
  )
}

function Workspace() {
  const { yo } = useAuth()
  const [vista, setVista] = useState<Vista>('hoy')
  const rol = yo?.rol

  // Guard por capacidad: el nav ya oculta, esto expulsa (doble defensa, patrón VITANOVA)
  useEffect(() => {
    if (vista === 'config' && !can(rol, 'verConfiguracion')) setVista('hoy')
    if (vista === 'equipo' && !can(rol, 'verEquipo')) setVista('hoy')
  }, [vista, rol])

  return (
    <div className="relative z-10 flex h-svh overflow-hidden">
      <Sidebar vista={vista} setVista={setVista} />
      <main className="ac-scroll flex min-w-0 flex-1 flex-col">
        <Topbar vista={vista} />
        <div className="ac-scroll flex-1 overflow-auto p-6" key={vista}>
          {vista === 'hoy' && <Hoy />}
          {vista === 'pipeline' && <Pipeline />}
          {vista === 'cartera' && <Cartera />}
          {vista === 'agenda' && <Agenda />}
          {vista === 'equipo' && <Equipo />}
          {vista === 'config' && <Config />}
        </div>
      </main>
      {/* Paneles globales: cualquier pantalla los abre vía useStore() */}
      <LeadDrawer />
      <LeadNuevo />
    </div>
  )
}

export default function App() {
  const { fase } = useAuth()

  const content =
    fase === 'init' || fase === 'resolviendo' ? (
      <Splash />
    ) : fase === 'anon' || fase === 'error' ? (
      <Login />
    ) : fase === 'no_enrolado' ? (
      <NoEnrolado />
    ) : (
      <Workspace />
    )

  return (
    <>
      <div className="ac-aurora" aria-hidden>
        <i />
      </div>
      {content}
    </>
  )
}
