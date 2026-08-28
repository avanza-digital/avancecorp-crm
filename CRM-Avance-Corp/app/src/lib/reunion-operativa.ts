import type { ModalidadReunion } from './tipos'

const MAX_UBICACION = 300
const MAX_ENLACE = 1000

export type ModalidadReunionOperativa = 'presencial' | 'virtual'

/** Campos crudos de una reunión, antes de validar y limpiar incompatibilidades. */
export interface EntradaReunionOperativa {
  modalidad?: ModalidadReunion | '' | null | undefined
  ubicacion?: string | null | undefined
  enlace?: string | null | undefined
}

export type CodigoReunionOperativa =
  | 'modalidad_reunion_obligatoria'
  | 'destino_reunion_obligatorio'
  | 'enlace_reunion_invalido'

export type ReunionOperativaNormalizada =
  | {
      modalidad: 'presencial'
      ubicacion: string
      enlace: null
    }
  | {
      modalidad: 'virtual'
      ubicacion: null
      enlace: string | null
    }

export interface ReunionOperativaInvalida {
  ok: false
  codigo: CodigoReunionOperativa
  error: string
}

export type ReunionOperativaValidada =
  | (ReunionOperativaNormalizada & { ok: true })
  | ReunionOperativaInvalida

/**
 * Proyección tolerante para consumidores de datos ya persistidos.
 *
 * No valida ni normaliza: la frontera de escritura usa
 * `validarReunionOperativa`. Esta derivación conserva la semántica histórica de
 * agenda para filas antiguas o incompletas: presencial usa ubicación; cualquier
 * otra modalidad prefiere enlace y conserva ubicación como respaldo.
 */
export interface ReunionOperativaDerivada {
  modalidad: ModalidadReunionOperativa | null
  enlace: string | null
  destino: string | null
}

export function derivarReunionOperativa(
  input: EntradaReunionOperativa,
): ReunionOperativaDerivada {
  return {
    modalidad: esModalidadReunionOperativa(input.modalidad) ? input.modalidad : null,
    enlace: input.enlace ?? null,
    destino: input.modalidad === 'presencial'
      ? (input.ubicacion ?? null)
      : (input.enlace ?? input.ubicacion ?? null),
  }
}

function esModalidadReunionOperativa(
  modalidad: EntradaReunionOperativa['modalidad'],
): modalidad is ModalidadReunionOperativa {
  return modalidad === 'presencial' || modalidad === 'virtual'
}

function reunionInvalida(
  codigo: CodigoReunionOperativa,
  error: string,
): ReunionOperativaInvalida {
  return { ok: false, codigo, error }
}

function errorDeEnlaceHttps(enlace: string): string | null {
  if (enlace.length > MAX_ENLACE || /\s/.test(enlace)) {
    return 'El enlace debe ser una URL HTTPS válida y sin espacios'
  }

  try {
    const url = new URL(enlace)
    if (url.protocol !== 'https:' || !url.hostname || url.username || url.password) {
      return 'El enlace debe ser una URL HTTPS válida y sin credenciales'
    }
  } catch {
    return 'El enlace debe ser una URL HTTPS válida'
  }

  return null
}

export function validarReunionOperativa(
  input: EntradaReunionOperativa,
): ReunionOperativaValidada {
  if (!esModalidadReunionOperativa(input.modalidad)) {
    return reunionInvalida(
      'modalidad_reunion_obligatoria',
      'Selecciona si la cita será presencial o virtual',
    )
  }

  if (input.modalidad === 'presencial') {
    const ubicacion = input.ubicacion?.trim() ?? ''
    if (!ubicacion || ubicacion.length > MAX_UBICACION) {
      return reunionInvalida(
        'destino_reunion_obligatorio',
        `Ingresa un lugar o dirección de hasta ${MAX_UBICACION} caracteres`,
      )
    }
    return { ok: true, modalidad: 'presencial', ubicacion, enlace: null }
  }

  const enlace = input.enlace?.trim() ?? ''
  if (!enlace) {
    return { ok: true, modalidad: 'virtual', ubicacion: null, enlace: null }
  }

  const errorEnlace = errorDeEnlaceHttps(enlace)
  if (errorEnlace) return reunionInvalida('enlace_reunion_invalido', errorEnlace)

  return { ok: true, modalidad: 'virtual', ubicacion: null, enlace }
}
