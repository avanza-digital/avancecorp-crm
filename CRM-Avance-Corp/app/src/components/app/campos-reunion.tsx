/* eslint-disable react-refresh/only-export-components -- El formulario comparte su contrato y proyeccion con sus consumidores. */
import type { JSX } from 'react'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import type { ReunionOperativaNormalizada } from '@/lib/reunion-operativa'
import {
  MODALIDADES_REUNION,
  type ModalidadReunion,
  type ModalidadReunionOperativa,
} from '@/lib/tipos'

/**
 * Estado del formulario como unión discriminada: el campo incompatible siempre
 * está vacío y no puede volver a colarse en un payload al cambiar modalidad.
 */
export type EstadoCamposReunion =
  | { modalidad: ''; ubicacion: ''; enlace: '' }
  | { modalidad: 'presencial'; ubicacion: string; enlace: '' }
  | { modalidad: 'virtual'; ubicacion: ''; enlace: string }

export const CAMPOS_REUNION_VACIOS: EstadoCamposReunion = {
  modalidad: '',
  ubicacion: '',
  enlace: '',
}

export interface CamposTareaReunion {
  modalidad_reunion: ModalidadReunionOperativa | null
  ubicacion_reunion: string | null
  enlace_reunion: string | null
}

/** Única proyección del resultado validado al contrato de tareas/RPC. */
export function camposTareaDeReunion(
  reunion: ReunionOperativaNormalizada | null | undefined,
): CamposTareaReunion {
  return {
    modalidad_reunion: reunion?.modalidad ?? null,
    ubicacion_reunion: reunion?.ubicacion ?? null,
    enlace_reunion: reunion?.enlace ?? null,
  }
}

/** Etiqueta de lectura derivada del catálogo; conserva el fallback legacy. */
export function etiquetaModalidadReunion(
  modalidad: ModalidadReunion | null | undefined,
): string | null {
  if (!modalidad) return null
  return MODALIDADES_REUNION.find((opcion) => opcion.k === modalidad)?.label ?? 'Sin clasificar'
}

interface ConfiguracionDestino {
  ariaLabel: string
  placeholder: string
  maxLength: number
  type?: 'url'
}

const DESTINO_POR_MODALIDAD: Record<ModalidadReunionOperativa, ConfiguracionDestino> = {
  presencial: {
    ariaLabel: 'Lugar de la reunión',
    placeholder: 'Lugar o dirección',
    maxLength: 300,
  },
  virtual: {
    ariaLabel: 'Enlace de la reunión',
    placeholder: 'Enlace de Meet, Zoom o Teams',
    maxLength: 1000,
    type: 'url',
  },
}

export interface CamposReunionProps {
  valor: EstadoCamposReunion
  onChange: (valor: EstadoCamposReunion) => void
}

export function CamposReunion({ valor, onChange }: CamposReunionProps): JSX.Element {
  const configuracion = valor.modalidad ? DESTINO_POR_MODALIDAD[valor.modalidad] : null
  const destino = valor.modalidad === 'presencial'
    ? valor.ubicacion
    : valor.modalidad === 'virtual'
      ? valor.enlace
      : ''

  return (
    <div className="grid gap-2 sm:grid-cols-2">
      <Select
        aria-label="Modalidad de la reunión"
        value={valor.modalidad}
        onChange={(evento) => {
          const modalidad = evento.target.value
          if (modalidad === valor.modalidad) {
            onChange(valor)
          } else if (modalidad === '') {
            onChange(CAMPOS_REUNION_VACIOS)
          } else if (modalidad === 'presencial') {
            onChange({ modalidad, ubicacion: '', enlace: '' })
          } else if (modalidad === 'virtual') {
            onChange({ modalidad, ubicacion: '', enlace: '' })
          }
        }}
      >
        <option value="">Selecciona modalidad</option>
        {MODALIDADES_REUNION.map((opcion) => (
          <option key={opcion.k} value={opcion.k}>{opcion.label}</option>
        ))}
      </Select>
      {configuracion && (
        <Input
          aria-label={configuracion.ariaLabel}
          type={configuracion.type}
          placeholder={configuracion.placeholder}
          value={destino}
          maxLength={configuracion.maxLength}
          onChange={(evento) => {
            if (valor.modalidad === 'presencial') {
              onChange({ ...valor, ubicacion: evento.target.value })
            } else if (valor.modalidad === 'virtual') {
              onChange({ ...valor, enlace: evento.target.value })
            }
          }}
        />
      )}
    </div>
  )
}
