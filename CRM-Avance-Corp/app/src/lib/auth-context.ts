import { createContext, useContext } from 'react'
import type { Rol } from './roles'
import type { Yo } from './tipos'

export type Fase = 'init' | 'anon' | 'resolviendo' | 'listo' | 'no_enrolado' | 'error'

export interface AuthContextValue {
  fase: Fase
  yo: Yo | null
  error: string | null
  entrar: (correo: string, clave: string) => Promise<{ ok: boolean; error?: string }>
  entrarDemo: (rol: Rol) => void
  reintentar: () => void
  salir: () => Promise<void>
}

export const AuthContext = createContext<AuthContextValue | null>(null)

export function useAuth(): AuthContextValue {
  const contexto = useContext(AuthContext)
  if (!contexto) throw new Error('useAuth fuera de AuthProvider')
  return contexto
}
