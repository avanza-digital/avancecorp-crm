// AuthGate del CRM — wrapper React delgado sobre lib/auth-maquina.ts (XState).
//   init → anon → resolviendo → listo | no_enrolado | error
// El rol se resuelve así: fila propia en crm.equipo (rol_crm) →
// si no hay, perfiles.rol ∈ {directorio, admin, superadmin} → 'directorio' (lector global) →
// si no, "no_enrolado" (privilegio mínimo: no ve nada del CRM).
// Modo DEMO: sesión falsa con rol elegible, sin tocar Supabase (para explorar la UI).
//
// La lógica de fases/carreras vive en la MÁQUINA (testeable sin React ni red);
// aquí solo se cablean Supabase, los listeners del navegador y el modo demo.
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { createActor } from 'xstate'
import { sb, type ClienteCrm } from './supabase'
import { DEMO_HABILITADO } from './config'
import { registrarAviso, registrarError } from './observabilidad'
import { AuthContext, type Fase } from './auth-context'
import {
  authMaquina,
  faseDe,
  ERROR_ACCESO,
  ERROR_SESION,
  type ResultadoVerificacion,
} from './auth-maquina'
import {
  esSesionAusente,
  guardarSesionDemo,
  leerSesionDemo,
  limpiarSesionDemo,
  mensajeSeguroDeLogin,
  normalizarCorreo,
  notificarAuthLimpia,
} from './seguridad'
import { esRol, type Rol } from './roles'
import type { Yo } from './tipos'

import { DEMO_YO } from './auth-demo'

async function resolverRol(cliente: ClienteCrm, userId: string): Promise<{ rol: Rol | null; nombre: string }> {
  // 1) ¿Enrolado en crm.equipo? (requiere F0 aplicada + esquema crm expuesto)
  const { data: miembro, error: errorEquipo } = await cliente.schema('crm').from('equipo')
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
    const { data: perfilMiembro, error: errorPerfilMiembro } = await cliente.from('perfiles')
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
  // usuario, así que propagamos (la máquina lo convierte en fase 'error').
  const { data: perfil, error: errPerfil } = await cliente.from('perfiles')
    .select('rol, activo, nombre_completo').eq('id', userId).maybeSingle()
  if (errPerfil) {
    registrarError('auth.resolver_rol.perfil_portal', errPerfil, { userId })
    throw new Error(ERROR_ACCESO)
  }
  if (perfil?.activo && ['directorio', 'admin', 'superadmin'].includes(perfil.rol)) {
    return { rol: 'directorio', nombre: perfil.nombre_completo ?? '' }
  }
  return { rol: null, nombre: '' }
}

/**
 * Verificación completa contra el SERVIDOR: getUser (getSession por sí solo
 * aceptaría un JWT local cuya sesión ya fue cerrada en otro dispositivo) y
 * después resolución de rol. Es la dependencia que se inyecta a la máquina.
 */
function crearVerificador(cliente: ClienteCrm): () => Promise<ResultadoVerificacion> {
  return async () => {
    const { data, error: errorUsuario } = await cliente.auth.getUser()
    if (errorUsuario) {
      if (esSesionAusente(errorUsuario)) return { tipo: 'sin_sesion' }
      registrarError('auth.validacion_servidor_fallida', errorUsuario)
      throw new Error(ERROR_SESION)
    }
    if (!data.user) return { tipo: 'sin_sesion' }

    const userId = data.user.id
    const { rol, nombre } = await resolverRol(cliente, userId)
    if (!rol) {
      registrarAviso('auth.acceso_revocado_o_no_enrolado', { userId })
      return { tipo: 'no_enrolado', userId }
    }
    return { tipo: 'acceso', userId, rol, nombre }
  }
}

type ActorAuth = ReturnType<typeof createActor<typeof authMaquina>>

export function AuthProvider({ children }: { children: ReactNode }) {
  const [fase, setFase] = useState<Fase>('init')
  const [yo, setYo] = useState<Yo | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [revision, setRevision] = useState(0)
  const yoRef = useRef<Yo | null>(null)
  yoRef.current = yo
  const actorRef = useRef<ActorAuth | null>(null)

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
    let ultimaRevalidacion = 0
    const temporizadores = new Set<ReturnType<typeof setTimeout>>()

    const diferir = (tarea: () => void) => {
      const id = setTimeout(() => {
        temporizadores.delete(id)
        if (!cancelado) tarea()
      }, 0)
      temporizadores.add(id)
    }

    const actor = createActor(authMaquina, {
      input: {
        verificar: crearVerificador(cliente),
        // Contrato con la capa de datos: borra la caché del acceso anterior.
        alLimpiar: notificarAuthLimpia,
      },
    })
    actorRef.current = actor

    const suscripcion = actor.subscribe((snapshot) => {
      if (cancelado) return
      const estado = snapshot.value as Parameters<typeof faseDe>[0]
      setFase(faseDe(estado, snapshot.context))
      setYo(snapshot.context.yo)
      setError(snapshot.context.error)
    })

    actor.start()

    // El callback se mantiene estrictamente síncrono. Los envíos se difieren
    // porque ejecutar llamadas a Supabase dentro de onAuthStateChange puede
    // bloquear el cliente (deadlock documentado por Supabase).
    const { data: sub } = cliente.auth.onAuthStateChange((_evento, session) => {
      if (cancelado) return
      const userId = session?.user.id ?? null
      diferir(() => actor.send({ type: 'SESION_CAMBIO', userId }))
    })

    const revalidarAlVolver = () => {
      if (cancelado || document.visibilityState !== 'visible') return
      const ahora = Date.now()
      // focus + visibilitychange suelen llegar juntos. Este enfriamiento evita
      // duplicar peticiones y bucles si el navegador emite varios focus seguidos.
      if (ahora - ultimaRevalidacion < 20_000) return
      ultimaRevalidacion = ahora
      actor.send({ type: 'REVALIDAR' })
    }
    window.addEventListener('focus', revalidarAlVolver)
    document.addEventListener('visibilitychange', revalidarAlVolver)

    return () => {
      cancelado = true
      sub.subscription.unsubscribe()
      window.removeEventListener('focus', revalidarAlVolver)
      document.removeEventListener('visibilitychange', revalidarAlVolver)
      for (const id of temporizadores) clearTimeout(id)
      temporizadores.clear()
      suscripcion.unsubscribe()
      // Detener el actor CANCELA cualquier verificación en vuelo.
      actor.stop()
      actorRef.current = null
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
      const { data, error: errorLogin } = await sb.auth.signInWithPassword({
        email: normalizarCorreo(correo),
        password: clave,
      })
      if (errorLogin) {
        registrarError('auth.login_rechazado', errorLogin)
        return { ok: false, error: mensajeSeguroDeLogin(errorLogin) }
      }
      // Arranque inmediato de la verificación (el listener llegará como eco
      // del mismo usuario y la máquina lo ignora).
      if (data.user) actorRef.current?.send({ type: 'SESION_CAMBIO', userId: data.user.id })
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
    // Desmonta el actor de la sesión real (cancela verificaciones en vuelo)
    // mientras se explora el demo.
    setRevision((actual) => actual + 1)
  }

  const reintentar = () => {
    if (actorRef.current) {
      setError(null)
      actorRef.current.send({ type: 'REINTENTAR' })
      return
    }
    yoRef.current = null
    setYo(null)
    setError(null)
    setFase('init')
    setRevision((actual) => actual + 1)
  }

  const salir = async () => {
    const eraDemo = yoRef.current?.demo === true
    limpiarSesionDemo()
    // SALIR cancela cualquier verificación en vuelo ANTES del signOut: una
    // respuesta tardía ya no puede recolocar la identidad anterior.
    actorRef.current?.send({ type: 'SALIR' })
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
