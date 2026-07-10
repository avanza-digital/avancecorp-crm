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

/** Resultado de verificar sesión + rol contra el servidor. */
export type ResultadoVerificacion =
  | { tipo: 'sin_sesion' }
  | { tipo: 'acceso'; userId: string; rol: Rol; nombre: string }
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
      const { userId, rol, nombre } = output
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
        !anterior.demo
      return {
        yo: sinCambios ? anterior : ({ id: userId, nombre_completo: nombre, rol, demo: false } satisfies Yo),
        ultimoUser: userId,
        error: null,
        arrancando: false,
        limpiezaNotificada: false,
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
    revalidando: {
      invoke: {
        src: 'verificar',
        input: ({ context }) => ({ verificar: context.verificar }),
        onDone: [
          { guard: 'esSinSesion', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null })] },
          { guard: 'esNoEnrolado', target: 'no_enrolado', actions: 'limpiarIdentidad' },
          { target: 'listo', actions: 'aplicarResultado' },
        ],
        onError: {
          target: 'error',
          actions: ['limpiarIdentidad', assign(({ event }) => ({ error: mensajeDeError((event as { error: unknown }).error, ERROR_SESION) }))],
        },
      },
      after: {
        [LIMITE_VERIFICACION_MS]: {
          target: 'error',
          actions: ['limpiarIdentidad', assign({ error: ERROR_TIMEOUT })],
        },
      },
      on: {
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null })] },
          { guard: 'esOtroUsuario', target: 'verificando', reenter: true, actions: ['limpiarIdentidad', assign(({ event }) => ({ ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId }))] },
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
        REINTENTAR: { target: 'verificando', actions: assign({ error: null }) },
        SESION_CAMBIO: [
          { guard: 'sinUsuario', target: 'anon', actions: ['limpiarIdentidad', assign({ ultimoUser: null, error: null })] },
          { guard: 'esOtroUsuario', target: 'verificando', actions: assign(({ event }) => ({ ultimoUser: (event as Extract<EventoAuth, { type: 'SESION_CAMBIO' }>).userId, error: null })) },
        ],
      },
    },
  },
})

/** Fase pública (contrato de auth-context) derivada del estado de la máquina. */
export type EstadoAuth = 'verificando' | 'revalidando' | 'anon' | 'listo' | 'no_enrolado' | 'error'

export function faseDe(estado: EstadoAuth, contexto: Pick<ContextoAuth, 'arrancando'>): 'init' | 'anon' | 'resolviendo' | 'listo' | 'no_enrolado' | 'error' {
  switch (estado) {
    case 'verificando':
      return contexto.arrancando ? 'init' : 'resolviendo'
    case 'revalidando':
      return 'listo' // silenciosa: sin parpadeo de spinner
    default:
      return estado
  }
}
