// AuthGate del CRM (máquina de fases, patrón VITANOVA adaptado):
//   init → anon → resolviendo → listo | no_enrolado | error
// El rol se resuelve así: fila propia en crm.equipo (rol_crm) →
// si no hay, perfiles.rol ∈ {directorio, admin, superadmin} → 'directorio' (lector global) →
// si no, "no_enrolado" (privilegio mínimo: no ve nada del CRM).
// Modo DEMO: sesión falsa con rol elegible, sin tocar Supabase (para explorar la UI).
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import { sb } from './supabase'
import type { Rol } from './roles'
import type { Yo } from './tipos'

export type Fase = 'init' | 'anon' | 'resolviendo' | 'listo' | 'no_enrolado' | 'error'

interface AuthCtx {
  fase: Fase
  yo: Yo | null
  error: string | null
  entrar: (correo: string, clave: string) => Promise<{ ok: boolean; error?: string }>
  entrarDemo: (rol: Rol) => void
  salir: () => Promise<void>
}

const Ctx = createContext<AuthCtx | null>(null)

const DEMO_KEY = 'ac-crm-demo'

// Identidades demo — espejo de miembros REALES de EQUIPO_DEMO (lib/demo.ts)
// para que el ámbito jerárquico del store funcione (contrato F1c).
// Directorio NO está en crm.equipo (es lector global del portal), igual que
// en producción: conserva un id sintético fuera del organigrama.
const DEMO_YO: Record<Rol, { id: string; nombre_completo: string }> = {
  vendedor: { id: 'd-v1', nombre_completo: 'VENDEDOR UNO' },
  supervisor: { id: 'd-sup1', nombre_completo: 'SUPERVISOR UNO' },
  gerencia: { id: 'd-ger', nombre_completo: 'GERENCIA DEMO' },
  directorio: { id: 'demo-directorio', nombre_completo: 'DIRECTORIO (DEMO)' },
}

async function resolverRol(userId: string): Promise<{ rol: Rol | null; nombre: string }> {
  // 1) ¿Enrolado en crm.equipo? (requiere F0 aplicada + esquema crm expuesto)
  try {
    const { data } = await sb!.schema('crm').from('equipo')
      .select('rol_crm, activo').eq('perfil_id', userId).maybeSingle()
    if (data?.activo && data.rol_crm) {
      const { data: p } = await sb!.from('perfiles').select('nombre_completo').eq('id', userId).maybeSingle()
      return { rol: data.rol_crm as Rol, nombre: p?.nombre_completo ?? '' }
    }
  } catch {
    // esquema crm aún no expuesto/aplicado: seguimos al fallback del portal
  }
  // 2) ¿Lector global del portal?
  const { data: perfil } = await sb!.from('perfiles')
    .select('rol, activo, nombre_completo').eq('id', userId).maybeSingle()
  if (perfil?.activo && ['directorio', 'admin', 'superadmin'].includes(perfil.rol)) {
    return { rol: 'directorio', nombre: perfil.nombre_completo ?? '' }
  }
  return { rol: null, nombre: perfil?.nombre_completo ?? '' }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [fase, setFase] = useState<Fase>('init')
  const [yo, setYo] = useState<Yo | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    // Sesión demo persistida
    try {
      const demo = sessionStorage.getItem(DEMO_KEY)
      if (demo) {
        const rol = JSON.parse(demo).rol as Rol
        const base = DEMO_YO[rol]
        if (base) {
          setYo({ ...base, rol, demo: true })
          setFase('listo')
          return
        }
        sessionStorage.removeItem(DEMO_KEY) // rol demo desconocido → sesión limpia
      }
    } catch { /* sessionStorage no disponible */ }

    if (!sb) { setFase('anon'); return }

    let cancelado = false
    const boot = async (userId: string) => {
      setFase('resolviendo')
      try {
        const { rol, nombre } = await resolverRol(userId)
        if (cancelado) return
        if (!rol) { setFase('no_enrolado'); return }
        setYo({ id: userId, nombre_completo: nombre, rol, demo: false })
        setFase('listo')
      } catch (e) {
        if (!cancelado) { setError(e instanceof Error ? e.message : 'Error al cargar'); setFase('error') }
      }
    }

    sb.auth.getSession().then(({ data }) => {
      if (cancelado) return
      if (data.session) void boot(data.session.user.id)
      else setFase('anon')
    })

    // Comparamos por user.id (no por access_token) para NO re-bootear en cada
    // TOKEN_REFRESHED — quirk documentado de VITANOVA (docs/recon/02 §5).
    let ultimoUser: string | null = null
    const { data: sub } = sb.auth.onAuthStateChange((_ev, session) => {
      if (cancelado) return
      if (!session) { ultimoUser = null; setYo(null); setFase('anon'); return }
      if (session.user.id !== ultimoUser) { ultimoUser = session.user.id; void boot(session.user.id) }
    })
    return () => { cancelado = true; sub.subscription.unsubscribe() }
  }, [])

  const entrar = async (correo: string, clave: string) => {
    if (!sb) return { ok: false, error: 'Falta configurar Supabase (.env) — usa el modo demo' }
    const { error: e } = await sb.auth.signInWithPassword({ email: correo.trim(), password: clave })
    if (e) return { ok: false, error: /invalid/i.test(e.message) ? 'Correo o contraseña incorrectos' : e.message }
    return { ok: true }
  }

  const entrarDemo = (rol: Rol) => {
    try { sessionStorage.setItem(DEMO_KEY, JSON.stringify({ rol })) } catch { /* privado */ }
    setYo({ ...DEMO_YO[rol], rol, demo: true })
    setFase('listo')
  }

  const salir = async () => {
    try { sessionStorage.removeItem(DEMO_KEY) } catch { /* nada */ }
    setYo(null)
    if (sb) await sb.auth.signOut()
    setFase('anon')
  }

  return <Ctx.Provider value={{ fase, yo, error, entrar, entrarDemo, salir }}>{children}</Ctx.Provider>
}

export function useAuth(): AuthCtx {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useAuth fuera de AuthProvider')
  return ctx
}
