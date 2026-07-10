// AuthGate del CRM (máquina de fases, patrón VITANOVA adaptado):
//   init → anon → resolviendo → listo | no_enrolado | error
// El rol se resuelve así: fila propia en crm.equipo (rol_crm) →
// si no hay, perfiles.rol ∈ {directorio, admin, superadmin} → 'directorio' (lector global) →
// si no, "no_enrolado" (privilegio mínimo: no ve nada del CRM).
// Modo DEMO: sesión falsa con rol elegible, sin tocar Supabase (para explorar la UI).
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { sb } from './supabase'
import { DEMO_HABILITADO } from './config'
import { registrarAviso, registrarError } from './observabilidad'
import { AuthContext, type Fase } from './auth-context'
import {
  esSesionAusente,
  guardarSesionDemo,
  leerSesionDemo,
  limpiarSesionDemo,
  mensajeSeguroDeLogin,
  normalizarCorreo,
  notificarAuthLimpia,
} from './seguridad'
import type { Rol } from './roles'
import type { Yo } from './tipos'

const ERROR_ACCESO = 'No pudimos verificar tu acceso. Inténtalo de nuevo en unos segundos.'
const ERROR_SESION = 'No pudimos validar tu sesión. Revisa tu conexión e inténtalo de nuevo.'
const ERROR_TIMEOUT = 'No pudimos cargar tu sesión. Revisa tu conexión e inténtalo de nuevo.'
const ROLES: readonly Rol[] = ['vendedor', 'supervisor', 'gerencia', 'directorio']

function esRol(valor: unknown): valor is Rol {
  return typeof valor === 'string' && ROLES.includes(valor as Rol)
}

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
  const { data: miembro, error: errorEquipo } = await sb!.schema('crm').from('equipo')
    .select('rol_crm, activo').eq('perfil_id', userId).maybeSingle()
  if (errorEquipo) {
    registrarError('auth.resolver_rol.equipo', errorEquipo, { userId })
    throw new Error(ERROR_ACCESO)
  }

  if (miembro) {
    // Una fila CRM inactiva es una revocación explícita: no cae al fallback.
    if (!miembro.activo || !esRol(miembro.rol_crm)) {
      if (miembro.activo && !esRol(miembro.rol_crm)) {
        registrarAviso('auth.rol_crm_desconocido', { userId })
      }
      return { rol: null, nombre: '' }
    }

    // La cuenta del portal también debe seguir activa; equipo.activo por sí solo
    // no basta para mantener acceso a una cuenta deshabilitada.
    const { data: perfilMiembro, error: errorPerfilMiembro } = await sb!.from('perfiles')
      .select('nombre_completo, activo').eq('id', userId).maybeSingle()
    if (errorPerfilMiembro) {
      registrarError('auth.resolver_rol.perfil_miembro', errorPerfilMiembro, { userId })
      throw new Error(ERROR_ACCESO)
    }
    if (!perfilMiembro?.activo) return { rol: null, nombre: '' }
    return { rol: miembro.rol_crm, nombre: perfilMiembro.nombre_completo ?? '' }
  }

  // 2) ¿Lector global del portal?
  // Un error aquí NO se traga: sin esta respuesta no sabemos quién es el
  // usuario, así que propagamos (boot lo convierte en fase 'error').
  const { data: perfil, error: errPerfil } = await sb!.from('perfiles')
    .select('rol, activo, nombre_completo').eq('id', userId).maybeSingle()
  if (errPerfil) {
    registrarError('auth.resolver_rol.perfil_portal', errPerfil, { userId })
    throw new Error(ERROR_ACCESO)
  }
  if (perfil?.activo && ['directorio', 'admin', 'superadmin'].includes(perfil.rol)) {
    return { rol: 'directorio', nombre: perfil.nombre_completo ?? '' }
  }
  return { rol: null, nombre: perfil?.nombre_completo ?? '' }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [fase, setFase] = useState<Fase>('init')
  const [yo, setYo] = useState<Yo | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [revision, setRevision] = useState(0)
  const yoRef = useRef<Yo | null>(null)
  yoRef.current = yo

  useEffect(() => {
    // Una sesión demo vieja jamás sobrevive si el build ya no permite demo.
    const demoGuardada = leerSesionDemo()
    if (!DEMO_HABILITADO) {
      if (limpiarSesionDemo()) notificarAuthLimpia()
    } else if (demoGuardada) {
      try {
        const dato = JSON.parse(demoGuardada) as { rol?: unknown }
        if (esRol(dato.rol)) {
          const base = DEMO_YO[dato.rol]
          notificarAuthLimpia()
          setYo({ ...base, rol: dato.rol, demo: true })
          setError(null)
          setFase('listo')
          return
        }
      } catch {
        // JSON corrupto o manipulado: se descarta abajo.
      }
      if (limpiarSesionDemo()) notificarAuthLimpia()
    }

    if (!sb) { setFase('anon'); return }
    const cliente = sb

    let cancelado = false
    let inicioVerificado = false
    let ultimoUser: string | null = null
    let ultimaRevalidacion = 0
    let secuencia = 0
    let limpiezaNotificada = false
    let accesoEnCurso: { userId: string; promesa: Promise<void> } | null = null
    let confirmacionEnCurso: Promise<void> | null = null
    const temporizadores = new Set<ReturnType<typeof setTimeout>>()

    const diferir = (tarea: () => void) => {
      const id = setTimeout(() => {
        temporizadores.delete(id)
        if (!cancelado) tarea()
      }, 0)
      temporizadores.add(id)
    }

    const limpiarDatosSensibles = () => {
      yoRef.current = null
      setYo(null)
      if (!limpiezaNotificada) {
        notificarAuthLimpia()
        limpiezaNotificada = true
      }
    }

    const sinSesion = () => {
      ultimoUser = null
      secuencia += 1 // invalida cualquier resolución tardía
      limpiarDatosSensibles()
      setError(null)
      setFase('anon')
    }

    const falloSeguro = (mensaje: string) => {
      limpiarDatosSensibles()
      setError(mensaje)
      setFase('error')
    }

    const conLimite = async <T,>(promesa: Promise<T>, mensaje: string): Promise<T> => {
      let id: ReturnType<typeof setTimeout> | undefined
      const limite = new Promise<never>((_, rechazar) => {
        id = setTimeout(() => rechazar(new Error(mensaje)), 12_000)
        temporizadores.add(id)
      })
      try {
        return await Promise.race([promesa, limite])
      } finally {
        if (id) {
          clearTimeout(id)
          temporizadores.delete(id)
        }
      }
    }

    const resolverAcceso = (userId: string, silenciosa: boolean): Promise<void> => {
      if (accesoEnCurso?.userId === userId) return accesoEnCurso.promesa
      const solicitud = ++secuencia

      const promesa = (async () => {
        if (!silenciosa || !yoRef.current) setFase('resolviendo')
        setError(null)
        try {
          const { rol, nombre } = await conLimite(resolverRol(userId), ERROR_TIMEOUT)
          if (cancelado || solicitud !== secuencia) return

          if (!rol) {
            registrarAviso('auth.acceso_revocado_o_no_enrolado', { userId })
            limpiarDatosSensibles()
            setFase('no_enrolado')
            return
          }

          const anterior = yoRef.current
          if (anterior && (anterior.id !== userId || anterior.rol !== rol || anterior.demo)) {
            limpiarDatosSensibles()
          }
          const identidadSinCambios = anterior
            && anterior.id === userId
            && anterior.nombre_completo === nombre
            && anterior.rol === rol
            && !anterior.demo
          if (!identidadSinCambios) {
            const identidad: Yo = { id: userId, nombre_completo: nombre, rol, demo: false }
            yoRef.current = identidad
            setYo(identidad)
          }
          limpiezaNotificada = false
          setFase('listo')
        } catch (causa) {
          if (cancelado || solicitud !== secuencia) return
          registrarError('auth.resolucion_acceso_fallida', causa, { userId })
          const mensaje = causa instanceof Error && causa.message === ERROR_TIMEOUT
            ? ERROR_TIMEOUT
            : ERROR_ACCESO
          falloSeguro(mensaje)
        }
      })()

      accesoEnCurso = { userId, promesa }
      void promesa.finally(() => {
        if (accesoEnCurso?.promesa === promesa) accesoEnCurso = null
      })
      return promesa
    }

    const confirmarSesion = (userIdEsperado?: string, silenciosa = false): Promise<void> => {
      if (confirmacionEnCurso) return confirmacionEnCurso
      const promesa = (async () => {
        try {
          const { data, error: errorUsuario } = await conLimite(cliente.auth.getUser(), ERROR_TIMEOUT)
          if (cancelado) return
          if (errorUsuario) {
            if (esSesionAusente(errorUsuario)) { sinSesion(); return }
            registrarError('auth.validacion_servidor_fallida', errorUsuario)
            falloSeguro(ERROR_SESION)
            return
          }
          if (!data.user) { sinSesion(); return }

          const cambioDeCuenta = Boolean(userIdEsperado && data.user.id !== userIdEsperado)
            || Boolean(ultimoUser && data.user.id !== ultimoUser)
          if (cambioDeCuenta) limpiarDatosSensibles()
          ultimoUser = data.user.id
          await resolverAcceso(data.user.id, silenciosa && !cambioDeCuenta)
        } catch (causa) {
          if (cancelado) return
          registrarError('auth.validacion_sesion_fallida', causa)
          falloSeguro(causa instanceof Error && causa.message === ERROR_TIMEOUT ? ERROR_TIMEOUT : ERROR_SESION)
        }
      })()
      confirmacionEnCurso = promesa
      void promesa.finally(() => {
        if (confirmacionEnCurso === promesa) confirmacionEnCurso = null
      })
      return promesa
    }

    // El callback se mantiene estrictamente síncrono. Las llamadas a Supabase
    // se difieren porque ejecutarlas dentro de onAuthStateChange puede bloquear
    // el cliente (deadlock documentado por Supabase).
    const { data: sub } = cliente.auth.onAuthStateChange((_evento, session) => {
      if (cancelado) return
      if (!inicioVerificado) return
      if (!session) { sinSesion(); return }
      if (session.user.id === ultimoUser) return

      ultimoUser = session.user.id
      limpiarDatosSensibles()
      setError(null)
      setFase('resolviendo')
      diferir(() => { void confirmarSesion(session.user.id) })
    })

    // getUser consulta al servidor; getSession por sí solo aceptaría un JWT local
    // cuya sesión ya fue cerrada en otro dispositivo.
    void confirmarSesion().finally(() => {
      inicioVerificado = true
    })

    const revalidarAlVolver = () => {
      if (cancelado || document.visibilityState !== 'visible' || !ultimoUser) return
      const ahora = Date.now()
      // focus + visibilitychange suelen llegar juntos. Este enfriamiento evita
      // duplicar peticiones y bucles si el navegador emite varios focus seguidos.
      if (ahora - ultimaRevalidacion < 20_000) return
      ultimaRevalidacion = ahora
      void confirmarSesion(ultimoUser, true)
    }
    window.addEventListener('focus', revalidarAlVolver)
    document.addEventListener('visibilitychange', revalidarAlVolver)

    return () => {
      cancelado = true
      secuencia += 1
      sub.subscription.unsubscribe()
      window.removeEventListener('focus', revalidarAlVolver)
      document.removeEventListener('visibilitychange', revalidarAlVolver)
      for (const id of temporizadores) clearTimeout(id)
      temporizadores.clear()
    }
  }, [revision])

  const entrar = async (correo: string, clave: string) => {
    if (!sb) {
      return {
        ok: false,
        error: DEMO_HABILITADO
          ? 'El acceso con cuenta no está configurado. Usa el modo demo.'
          : 'El acceso con cuenta no está configurado.',
      }
    }
    try {
      const { error: errorLogin } = await sb.auth.signInWithPassword({
        email: normalizarCorreo(correo),
        password: clave,
      })
      if (errorLogin) {
        registrarError('auth.login_rechazado', errorLogin)
        return { ok: false, error: mensajeSeguroDeLogin(errorLogin) }
      }
      setError(null)
      setFase('resolviendo')
      return { ok: true }
    } catch (causa) {
      registrarError('auth.login_fallido', causa)
      return { ok: false, error: mensajeSeguroDeLogin(causa) }
    }
  }

  const entrarDemo = (rol: Rol) => {
    if (!DEMO_HABILITADO) {
      if (limpiarSesionDemo()) notificarAuthLimpia()
      registrarAviso('auth.demo_rechazado_en_build_no_dev')
      return
    }
    guardarSesionDemo(JSON.stringify({ rol }))
    notificarAuthLimpia()
    const identidad: Yo = { ...DEMO_YO[rol], rol, demo: true }
    yoRef.current = identidad
    setYo(identidad)
    setError(null)
    setFase('listo')
    // Desmonta los listeners de la sesión real mientras se explora el demo.
    setRevision((actual) => actual + 1)
  }

  const reintentar = () => {
    yoRef.current = null
    setYo(null)
    setError(null)
    setFase('init')
    setRevision((actual) => actual + 1)
  }

  const salir = async () => {
    const eraDemo = yoRef.current?.demo === true
    limpiarSesionDemo()
    yoRef.current = null
    setYo(null)
    setError(null)
    setFase('anon')
    notificarAuthLimpia()
    if (!sb) {
      if (eraDemo) setRevision((actual) => actual + 1)
      return
    }
    try {
      const { error: errorSalida } = await sb.auth.signOut({ scope: 'local' })
      if (errorSalida) registrarError('auth.salida_incompleta', errorSalida)
    } catch (causa) {
      registrarError('auth.salida_fallida', causa)
    } finally {
      // Al salir del demo no había listener Supabase montado; lo inicializamos.
      if (eraDemo) setRevision((actual) => actual + 1)
    }
  }

  return (
    <AuthContext.Provider value={{ fase, yo, error, entrar, entrarDemo, reintentar, salir }}>
      {children}
    </AuthContext.Provider>
  )
}
