// lib/auth-maquina.ts — Máquina de estados del acceso (XState v5).
//
// Por qué una máquina: el flujo anterior coordinaba a mano promesas en vuelo,
// contadores de secuencia y flags de closure — y una confirmación de sesión en
// curso NO se invalidaba al cerrar sesión, así que una respuesta tardía podía
// recolocar temporalmente la identidad anterior tras logout/cambio de cuenta.
// Con XState el actor invocado se CANCELA solo al salir del estado (XSTATE_STOP
// → AbortController.abort() + descarte de resolves tardíos): una verificación
// vieja jamás entrega resultado después de SALIR o de un SESION_CAMBIO.
//
// La máquina es PURA respecto a Supabase: recibe `verificar` por input
// (inversión de dependencia), así los tests la ejercitan con promesas
// demoradas sin red ni mocks de módulo.
import { assign, fromPromise, setup } from 'xstate'
import type { Rol } from './roles'
import type { Yo } from './tipos'

export const ERROR_ACCESO = 'No pudimos verificar tu acceso. Inténtalo de nuevo en unos segundos.'
export const ERROR_SESION = 'No pudimos validar tu sesión. Revisa tu conexión e inténtalo de nuevo.'
export const ERROR_TIMEOUT = 'No pudimos cargar tu sesión. Revisa tu conexión e inténtalo de nuevo.'

/** Presupuesto máximo de una verificación (getUser + resolución de rol). */
export const LIMITE_VERIFICACION_MS = 12_000

/**
 * Esperas del reintento SILENCIOSO cuando una revalidación no pudo PREGUNTAR
 * (red caída / servidor inalcanzable). Backoff corto→largo: un parpadeo de wifi
 * se recupera casi al instante y una caída larga no machaca al servidor.
 *
 * POR QUÉ existe: "el servidor dice que no hay sesión" y "no pude preguntar" no
 * son lo mismo. Lo primero es un hecho y cierra la sesión; lo segundo es
 * ignorancia y, si se trata como cierre, un parpadeo de red al volver a la
 * pestaña EXPULSA al asesor al Login con la conversión a medio llenar. No
 * abre ningún dato de más: la autoridad sigue siendo la RLS del servidor, así
 * que una sesión de verdad muerta no puede leer nada aunque la UI siga montada.
 */
export const ESPERAS_REVALIDACION_MS = [3_000, 10_000, 30_000] as const

/** Espera del intento N (1-based), acotada al último tramo del backoff. */
function esperaRevalidacionDe(intento: number): number {
  const indice = Math.min(Math.max(intento, 1), ESPERAS_REVALIDACION_MS.length) - 1
  return ESPERAS_REVALIDACION_MS[indice] ?? ESPERAS_REVALIDACION_MS[0]
}

/** Resultado de verificar sesión + rol contra el servidor. */
export type ResultadoVerificacion =
  | { tipo: 'sin_sesion' }
  | {
      tipo: 'acceso'
      userId: string
      rol: Rol
      nombre: string
      puedeContratar: boolean
      /** Rol global del Portal; ausente solo en dobles de prueba antiguos. */
      rolPortal?: string
      capacidadesConfig?: {
        puedeListarUsuarios: boolean
        puedeAdministrarUsuarios: boolean
        puedeOrganizarJerarquia: boolean
        puedeAdministrarRoles: boolean
      }
    }
  | { tipo: 'no_enrolado'; userId: string }

/** La dependencia inyectada: valida la sesión en el SERVIDOR y resuelve el rol. */
export type Verificar = () => Promise<ResultadoVerificacion>

export type EventoAuth =
  | { type: 'SESION_CAMBIO'; userId: string | null } // de onAuthStateChange
  | { type: 'REVALIDAR' } // focus/visibilitychange (con enfriamiento en el wrapper)
  | { type: 'SALIR' } // logout explícito — cancela cualquier verificación en vuelo
  | { type: 'REINTENTAR' }

export interface ContextoAuth {
  verificar: Verificar
  yo: Yo | null
  error: string | null
  /** Último user id confirmado por el servidor (para ignorar ecos del listener). */
  ultimoUser: string | null
  /** true hasta que la primera verificación termina (fase pública 'init'). */
  arrancando: boolean
  /** Evita notificar la limpieza de caché dos veces seguidas. */
  limpiezaNotificada: boolean
  /**
   * Revalidaciones seguidas que NO pudieron preguntar (red). Elige la espera
   * del backoff y se reinicia en cuanto el servidor vuelve a contestar.
   */
  reintentosRevalidacion: number
}

export interface InputAuth {
  verificar: Verificar
  /** Se invoca al limpiar identidad (borra caché de datos del acceso anterior). */
  alLimpiar: () => void
}

const mensajeDeError = (causa: unknown, porDefecto: string): string =>
  causa instanceof Error && (causa.message === ERROR_ACCESO || causa.message === ERROR_SESION)
    ? causa.message
    : porDefecto

export const authMaquina = setup({
  types: {
    context: {} as ContextoAuth & { alLimpiar: () => void },
    events: {} as EventoAuth,
    input: {} as InputAuth,
  },
  actors: {
    verificar: fromPromise<ResultadoVerificacion, { verificar: Verificar }>(({ input }) =>
      input.verificar(),
    ),
  },
  delays: {
    // Espera del reintento silencioso: crece con los fallos consecutivos.
    esperaRevalidacion: ({ context }) => esperaRevalidacionDe(context.reintentosRevalidacion),
  },
  actions: {
    limpiarIdentidad: assign(({ context }) => {
      if (!context.limpiezaNotificada) context.alLimpiar()
      return { yo: null, limpiezaNotificada: true }
    }),
    aplicarResultado: assign(({ context, event }) => {
      // Solo se llama desde onDone del actor `verificar` con tipo 'acceso'
      // (los eventos done.invoke no forman parte del union EventoAuth).
      const output = (event as unknown as { output: ResultadoVerificacion }).output
      if (output.tipo !== 'acceso') return {}
      const { userId, rol, nombre, puedeContratar, rolPortal, capacidadesConfig } = output
      const anterior = context.yo
      // Cambio de cuenta o de rol: la caché del acceso anterior muere ANTES
      // de exponer la identidad nueva.
      if (anterior && (anterior.id !== userId || anterior.rol !== rol || anterior.demo)) {
        if (!context.limpiezaNotificada) context.alLimpiar()
      }
      const sinCambios =
        anterior != null &&
        anterior.id === userId &&
        anterior.nombre_completo === nombre &&
        anterior.rol === rol &&
        anterior.rol_portal === rolPortal &&
        anterior.capacidades_config?.puede_listar_usuarios === capacidadesConfig?.puedeListarUsuarios &&
        anterior.capacidades_config?.puede_administrar_usuarios === capacidadesConfig?.puedeAdministrarUsuarios &&
        anterior.capacidades_config?.puede_organizar_jerarquia === capacidadesConfig?.puedeOrganizarJerarquia &&
        anterior.capacidades_config?.puede_administrar_roles === capacidadesConfig?.puedeAdministrarRoles &&
        anterior.puede_contratar === puedeContratar &&
        !anterior.demo
      return {
        yo: sinCambios
          ? anterior
          : ({
              id: userId,
              nombre_completo: nombre,
              rol,
              ...(rolPortal ? { rol_portal: rolPortal } : {}),
              ...(capacidadesConfig ? {
                capacidades_config: {
                  puede_listar_usuarios: capacidadesConfig.puedeListarUsuarios,
                  puede_administrar_usuarios: capacidadesConfig.puedeAdministrarUsuarios,
                  puede_organizar_jerarquia: capacidadesConfig.puedeOrganizarJerarquia,
                  puede_administrar_roles: capacidadesConfig.puedeAdministrarRoles,
                },
              } : {}),
              demo: false,
              puede_contratar: puedeContratar,
            } satisfies Yo),
        ultimoUser: userId,
        error: null,
        arrancando: false,
        limpiezaNotificada: false,
        // El servidor contestó: el backoff de red vuelve a cero.
        reintentosRevalidacion: 0,
      }
    }),
  },
  guards: {
    esSinSesion: ({ event }) =>
      (event as { output?: ResultadoVerificacion }).output?.tipo === 'sin_sesion',
    esNoEnrolado: ({ event }) =>
      (event as { output?: ResultadoVerificacion }).output?.tipo === 'no_enrolado',
    esOtroUsuario: ({ context, event }) => {
      const e = event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>
      return e.userId != null && e.userId !== context.ultimoUser
    },
    sinUsuario: ({ event }) =>
      (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId == null,
    /** ¿Queda presupuesto de reintentos silenciosos para esta caída de red? */
    puedeReintentarRevalidacion: ({ context }) =>
      context.reintentosRevalidacion < ESPERAS_REVALIDACION_MS.length,
  },
}).createMachine({
  id: 'auth',
  context: ({ input }) => ({
    verificar: input.verificar,
    alLimpiar: input.alLimpiar,
    yo: null,
    error: null,
    ultimoUser: null,
    arrancando: true,
    limpiezaNotificada: false,
    reintentosRevalidacion: 0,
  }),
  initial: 'verificando',
  // SALIR gana SIEMPRE: salir de `verificando`/`revalidando` cancela el actor
  // invocado — la respuesta tardía se descarta (no puede recolocar identidad).
  on: {
    SALIR: {
      target: '.anon',
      actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null, arrancando: false })],
    },
  },
  states: {
    verificando: {
      invoke: {
        src: 'verificar',
        input: ({ context }) => ({ verificar: context.verificar }),
        onDone: [
          {
            guard: 'esSinSesion',
            target: 'anon',
            actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null, arrancando: false })],
          },
          {
            guard: 'esNoEnrolado',
            target: 'no_enrolado',
            actions: [
              'limpiarIdentidad',
              assign(({ event }) => ({
                ultimoUser: (event as { output: ResultadoVerificacion }).output.tipo === 'no_enrolado'
                  ? (event as { output: Extract<ResultadoVerificacion, { tipo: 'no_enrolado' }> }).output.userId
                  : null,
                error: null,
                arrancando: false,
              })),
            ],
          },
          { target: 'listo', actions: 'aplicarResultado' },
        ],
        onError: {
          target: 'error',
          actions: [
            'limpiarIdentidad',
            assign(({ event }) => ({
              error: mensajeDeError((event as { error: unknown }).error, ERROR_SESION),
              arrancando: false,
            })),
          ],
        },
      },
      // Presupuesto duro: si el servidor no responde, fallo seguro (el actor
      // invocado se cancela al salir del estado).
      after: {
        [LIMITE_VERIFICACION_MS]: {
          target: 'error',
          actions: ['limpiarIdentidad', assign({ error: ERROR_TIMEOUT, arrancando: false })],
        },
      },
      on: {
        // Reintento EXPLÍCITO del usuario mientras se verifica (la salida del
        // splash atascado): reinicia la verificación en vez de caer en saco
        // roto. `reenter` cancela la anterior — no quedan dos en vuelo.
        REINTENTAR: { target: 'verificando', reenter: true, actions: assign({ error: null }) },
        // Cambio de cuenta a mitad de verificación: reinicia el actor (reenter
        // cancela el invoke anterior — su respuesta ya no puede aplicar).
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null, arrancando: false })] },
          { guard: 'esOtroUsuario', target: 'verificando', reenter: true, actions: ['limpiarIdentidad', assign(({ event }) => ({ ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId }))] },
        ],
      },
    },

    // Igual que `verificando` pero silencioso: la fase pública sigue 'listo'
    // (revalidación al volver a la pestaña — sin parpadeo de spinner).
    //
    // DIFERENCIA CLAVE con `verificando`: aquí ya hay una sesión CONFIRMADA por
    // el servidor. Solo una respuesta del servidor puede quitarla:
    //  · 'sin_sesion' / 'no_enrolado'  → el servidor HABLÓ: se cierra (fail-closed).
    //  · error de red o timeout        → NO pudimos preguntar: se CONSERVA la
    //    sesión y se reintenta sola. Tratar la ignorancia como cierre expulsaba
    //    al asesor al Login con la conversión a medio llenar (bug 2026-07-25).
    revalidando: {
      invoke: {
        src: 'verificar',
        input: ({ context }) => ({ verificar: context.verificar }),
        onDone: [
          { guard: 'esSinSesion', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null, reintentosRevalidacion: 0 })] },
          { guard: 'esNoEnrolado', target: 'no_enrolado', actions: ['limpiarIdentidad', assign({ reintentosRevalidacion: 0 })] },
          { target: 'listo', actions: 'aplicarResultado' },
        ],
        onError: [
          {
            guard: 'puedeReintentarRevalidacion',
            target: 'revalidacion_diferida',
            actions: assign(({ context }) => ({ reintentosRevalidacion: context.reintentosRevalidacion + 1 })),
          },
          // Agotado el backoff: la sesión SIGUE viva y la pantalla intacta. El
          // contador se reinicia para que el próximo foco/REVALIDAR (o el
          // regreso de la red) vuelva a tener su presupuesto completo.
          { target: 'listo', actions: assign({ reintentosRevalidacion: 0 }) },
        ],
      },
      after: {
        // Un cuelgue tampoco es "no hay sesión": mismo trato que el fallo de red.
        [LIMITE_VERIFICACION_MS]: [
          {
            guard: 'puedeReintentarRevalidacion',
            target: 'revalidacion_diferida',
            actions: assign(({ context }) => ({ reintentosRevalidacion: context.reintentosRevalidacion + 1 })),
          },
          { target: 'listo', actions: assign({ reintentosRevalidacion: 0 }) },
        ],
      },
      on: {
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null })] },
          { guard: 'esOtroUsuario', target: 'verificando', reenter: true, actions: ['limpiarIdentidad', assign(({ event }) => ({ ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId }))] },
        ],
      },
    },

    // Sala de espera del reintento silencioso: identidad INTACTA, fase pública
    // 'listo' (el asesor sigue trabajando y no se entera de nada). Al vencer la
    // espera se vuelve a preguntar; SALIR/SESION_CAMBIO siguen mandando.
    revalidacion_diferida: {
      after: {
        esperaRevalidacion: { target: 'revalidando' },
      },
      on: {
        // Volver a la pestaña (o un gesto explícito) no espera al backoff.
        REVALIDAR: { target: 'revalidando' },
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null, reintentosRevalidacion: 0 })] },
          { guard: 'esOtroUsuario', target: 'verificando', actions: ['limpiarIdentidad', assign(({ event }) => ({ ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId, reintentosRevalidacion: 0 }))] },
        ],
      },
    },

    anon: {
      on: {
        SESION_CAMBIO: {
          guard: 'esOtroUsuario',
          target: 'verificando',
          actions: assign(({ event }) => ({ ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId })),
        },
      },
    },

    listo: {
      on: {
        REVALIDAR: { target: 'revalidando' },
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null })] },
          { guard: 'esOtroUsuario', target: 'verificando', actions: ['limpiarIdentidad', assign(({ event }) => ({ ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId }))] },
          // mismo usuario: eco del listener — se ignora
        ],
      },
    },

    no_enrolado: {
      on: {
        REINTENTAR: { target: 'verificando' },
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: assign({ ultimoUser: null, error: null }) },
          { guard: 'esOtroUsuario', target: 'verificando', actions: assign(({ event }) => ({ ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId })) },
        ],
      },
    },

    error: {
      on: {
        // Gesto EXPLÍCITO («Reintentar verificación»): el asesor pidió el
        // reintento, así que sí se le enseña el spinner.
        REINTENTAR: { target: 'verificando', actions: assign({ error: null }) },
        // Volver a la pestaña con la app en error también reintenta: si el
        // servidor ya volvió, el asesor recupera su sesión sin tocar nada.
        // Pero EN SILENCIO (ver `revalidando_error`): nadie pidió esto, así que
        // no puede desmontar el Login que el asesor está llenando.
        REVALIDAR: { target: 'revalidando_error' },
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null })] },
          // OJO: aquí NO se filtra por `esOtroUsuario`. Tras un error, `ultimoUser`
          // conserva al usuario de la sesión caída, así que volver a entrar con la
          // MISMA cuenta llegaba como "eco" y se descartaba: el botón «Entrar»
          // quedaba muerto y solo se salía recargando a mano (bug 2026-07-25).
          // En `error` no hay identidad viva que proteger de ecos — cualquier
          // sesión anunciada es una orden de re-verificar.
          {
            target: 'verificando',
            reenter: true,
            actions: assign(({ event }) => ({
              ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId,
              error: null,
            })),
          },
        ],
      },
    },

    // Re-verificación SILENCIOSA con la app en `error`: la misma pregunta que
    // `verificando`, pero la fase pública sigue siendo 'error' (ver `faseDe`).
    //
    // POR QUÉ existe: en `error` la pantalla montada es el LOGIN. Mandar el
    // REVALIDAR del focus/visibilitychange a `verificando` cambiaba la fase a
    // 'resolviendo' → App pintaba el splash → el Login se DESMONTABA y volver a
    // la pestaña borraba el correo y la clave a medio teclear (regresión
    // 2026-07-25). El reintento automático se conserva entero; lo único que
    // cambia es que ya no se ve — que es justo lo que "silencioso" significa.
    // El error del contexto NO se limpia al entrar: el aviso sigue en pantalla
    // hasta que haya respuesta (sin parpadeo), y solo un resultado lo cambia.
    revalidando_error: {
      invoke: {
        src: 'verificar',
        input: ({ context }) => ({ verificar: context.verificar }),
        onDone: [
          { guard: 'esSinSesion', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null })] },
          { guard: 'esNoEnrolado', target: 'no_enrolado', actions: ['limpiarIdentidad', assign({ error: null })] },
          { target: 'listo', actions: 'aplicarResultado' },
        ],
        // Sigue sin poder verificarse: se vuelve al error de siempre (mismo
        // Login, mismo aviso) y el próximo foco lo intentará otra vez.
        onError: {
          target: 'error',
          actions: assign(({ event }) => ({
            error: mensajeDeError((event as { error: unknown }).error, ERROR_SESION),
          })),
        },
      },
      after: {
        [LIMITE_VERIFICACION_MS]: { target: 'error', actions: assign({ error: ERROR_TIMEOUT }) },
      },
      on: {
        // El gesto explícito manda sobre el silencioso (reenter cancela el
        // actor en vuelo: no quedan dos verificaciones vivas).
        REINTENTAR: { target: 'verificando', reenter: true, actions: assign({ error: null }) },
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null })] },
          // Igual que en `error` y por el mismo motivo: sin filtro `esOtroUsuario`.
          // Aquí tampoco hay identidad viva que proteger de ecos, y el botón
          // «Entrar» con la MISMA cuenta debe funcionar aunque el reintento
          // silencioso esté en vuelo.
          {
            target: 'verificando',
            reenter: true,
            actions: assign(({ event }) => ({
              ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId,
              error: null,
            })),
          },
        ],
      },
    },
  },
})

/** Fase pública (contrato de auth-context) derivada del estado de la máquina. */
export type EstadoAuth =
  | 'verificando'
  | 'revalidando'
  | 'revalidacion_diferida'
  | 'revalidando_error'
  | 'anon'
  | 'listo'
  | 'no_enrolado'
  | 'error'

export function faseDe(estado: EstadoAuth, contexto: Pick<ContextoAuth, 'arrancando'>): 'init' | 'anon' | 'resolviendo' | 'listo' | 'no_enrolado' | 'error' {
  switch (estado) {
    case 'verificando':
      return contexto.arrancando ? 'init' : 'resolviendo'
    case 'revalidando':
    case 'revalidacion_diferida':
      // Silenciosas: la sesión confirmada sigue en pie mientras se re-pregunta
      // (o se espera a que vuelva la red). Ni spinner ni Login.
      return 'listo'
    case 'revalidando_error':
      // También silenciosa, pero desde el otro lado: la pantalla montada es el
      // Login. Mantener la fase en 'error' es lo que impide desmontarlo (y
      // perder lo que el asesor ya tecleó) mientras se re-pregunta.
      return 'error'
    default:
      return estado
  }
}
