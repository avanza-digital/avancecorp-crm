import { createContext, useContext } from 'react'
import type { SolicitudTasa } from '@/data/crm-api'

export interface EstadoRespuestasTasa {
  habilitado: boolean
  configurado: boolean
  sonido: boolean
  escritorio: boolean
  ocupado: boolean
  mensaje: string
  error: string
  cargando: boolean
  sinLeer: number
  solicitudes: SolicitudTasa[]
  esLeida: (s: SolicitudTasa) => boolean
  activar: () => Promise<void>
  cambiarSonido: () => Promise<void>
  cambiarEscritorio: () => Promise<void>
  probar: () => void
  abrirBandeja: () => void
  abrirSolicitud: (id: string) => void
  marcarLeidas: () => Promise<void>
  reintentar: () => void
}

export const RespuestasTasaContext = createContext<EstadoRespuestasTasa>({
  habilitado: false, configurado: false, sonido: false, escritorio: false, ocupado: false,
  mensaje: '', error: '', cargando: false, sinLeer: 0, solicitudes: [], esLeida: () => true,
  activar: async () => {}, cambiarSonido: async () => {}, cambiarEscritorio: async () => {},
  probar: () => {}, abrirBandeja: () => {}, abrirSolicitud: () => {}, marcarLeidas: async () => {}, reintentar: () => {},
})

export function useRespuestasTasa() { return useContext(RespuestasTasaContext) }
