import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { funcionesLeadsVisibles } from '@/lib/config'
import { administraSoloRolesCrm } from '@/lib/roles'
import { CrmApiError } from './crm-api'
import { gestionDiariaKeys } from './gestion-diaria-queries'
import { controlarAvisosGestionDiaria, obtenerAvisosCortes, obtenerConfiguracionGestionDiaria,
  publicarGestionDiaria, reconocerCorte, type PublicacionGestionDiaria } from './gestion-diaria-seguimiento-api'

export const seguimientoKeys = {
  raiz: ['crm', 'gestion-diaria-seguimiento'] as const,
  avisos: (id: string | null) => [...seguimientoKeys.raiz, 'avisos', id] as const,
  configuracion: (id: string | null, rol: string | null) => [...seguimientoKeys.raiz, 'configuracion', id, rol] as const,
}

export function useAvisosCortes() {
  const { yo } = useAuth()
  const habilitada = Boolean(yo && !yo.demo && yo.rol === 'supervisor' && !administraSoloRolesCrm(yo)
    && funcionesLeadsVisibles(yo.demo, yo.rol))
  const cliente = useQueryClient()
  const clave = seguimientoKeys.avisos(yo?.id ?? null)
  const consulta = useQuery({ queryKey: clave, queryFn: ({ signal }) => obtenerAvisosCortes(yo!.id, signal),
    enabled: habilitada, refetchInterval: 60_000, refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' })
  const accion = useMutation({
    mutationFn: async (p: { alertaId: string; accion: 'reconocer' | 'posponer'; solicitudId: string }) => {
      if (!habilitada) throw new CrmApiError('Entra con una cuenta real de supervisor.', 'SIN_PERMISO')
      return reconocerCorte(yo!.id, p.alertaId, p.accion, p.solicitudId)
    },
    // Nada optimista: solo la respuesta confirmada puede silenciar el popup.
    onSuccess: async () => {
      await cliente.cancelQueries({ queryKey: clave })
      // La escritura confirma solo cortes. El contexto SLA se consulta una
      // vez después del commit, sin mantener el lock del supervisor.
      await Promise.all([
        cliente.invalidateQueries({ queryKey: clave }),
        cliente.invalidateQueries({ queryKey: gestionDiariaKeys.raiz() }),
      ])
    },
  })
  return { consulta, accion, habilitada, datos: habilitada && !consulta.error ? consulta.data ?? null : null }
}

export function useConfiguracionGestionDiaria() {
  const { yo } = useAuth()
  const cliente = useQueryClient()
  const habilitada = Boolean(yo && !yo.demo && ['gerencia', 'directorio'].includes(yo.rol))
  const clave = seguimientoKeys.configuracion(yo?.id ?? null, yo?.rol ?? null)
  const consulta = useQuery({ queryKey: clave, queryFn: ({ signal }) => obtenerConfiguracionGestionDiaria(signal),
    enabled: habilitada, refetchOnWindowFocus: 'always' })
  const confirmar = async (respuesta: Awaited<ReturnType<typeof obtenerConfiguracionGestionDiaria>>) => {
    await cliente.cancelQueries({ queryKey: clave })
    cliente.setQueryData(clave, respuesta)
    await Promise.all([
      cliente.invalidateQueries({ queryKey: seguimientoKeys.raiz }),
      cliente.invalidateQueries({ queryKey: gestionDiariaKeys.raiz() }),
    ])
  }
  const exigirGerencia = () => {
    if (!habilitada || yo?.rol !== 'gerencia') throw new CrmApiError('Solo gerencia publica cambios.', 'SIN_PERMISO')
  }
  const publicar = useMutation({ mutationFn: (p: PublicacionGestionDiaria) => {
    exigirGerencia()
    return publicarGestionDiaria(p)
  }, onSuccess: confirmar })
  const controlar = useMutation({ mutationFn: (p: { version: number; habilitados: boolean; motivo: string }) => {
    exigirGerencia()
    return controlarAvisosGestionDiaria(p)
  }, onSuccess: confirmar })
  return { consulta, publicar, controlar, habilitada,
    datos: habilitada && !consulta.error ? consulta.data ?? null : null }
}
