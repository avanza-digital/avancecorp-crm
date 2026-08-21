import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CrmApiError } from './crm-api'
import {
  actualizarBorradorProducto,
  actualizarJerarquiaUsuario,
  actualizarUsuarioAdministrable,
  archivarProducto,
  asignarRolUsuario,
  cerrarCompatibilidadLegacyProductos,
  crearCandidatoUsuario,
  crearProductoInversion,
  crearVersionProducto,
  fijarMembresiaUsuario,
  listarProductosSeleccionables,
  listarCatalogoUsuariosAdministrables,
  listarEstadoSlaLeads,
  listarUsuariosAdministrables,
  obtenerConfiguracionMetas,
  obtenerConfiguracionProductos,
  obtenerConfiguracionSla,
  obtenerImpactoDesactivacion,
  obtenerMetricasSla,
  publicarMetas,
  publicarPoliticaSla,
  publicarVersionProducto,
} from './crm-config-api'
import { crmQueryKeys } from './crm-queries'
import { useAuth } from '@/lib/auth-context'

type FuenteConfiguracion = 'demo' | 'real'

function useFuenteConfiguracion(): {
  fuente: FuenteConfiguracion
  demo: boolean
  autenticada: boolean
} {
  const { yo } = useAuth()
  const demo = yo?.demo === true
  return { fuente: demo ? 'demo' : 'real', demo, autenticada: yo != null }
}

function mutacionSoloReal<TInput, TOutput>(
  demo: boolean,
  ejecutar: (input: TInput) => Promise<TOutput>,
): (input: TInput) => Promise<TOutput> {
  return async (input) => {
    if (demo) {
      throw new CrmApiError(
        'El modo demo es de solo lectura. Entra con una cuenta real autorizada para guardar cambios.',
        'DEMO_SOLO_LECTURA',
      )
    }
    return ejecutar(input)
  }
}

export function useUsuariosAdministrables(
  busqueda: string,
  limite: number,
  desde: number,
  habilitada = true,
) {
  const { fuente, demo, autenticada } = useFuenteConfiguracion()
  return useQuery({
    queryKey: [...crmQueryKeys.configUsuarios(busqueda, limite, desde), fuente],
    queryFn: async ({ signal }) => demo
      ? (await import('@/lib/demo-config')).usuariosAdministrablesDemo(busqueda, limite, desde)
      : listarUsuariosAdministrables(busqueda, limite, desde, signal),
    enabled: habilitada && autenticada,
    staleTime: 0,
  })
}

export function useCatalogoUsuariosAdministrables(habilitada = true) {
  const { fuente, demo, autenticada } = useFuenteConfiguracion()
  return useQuery({
    queryKey: [...crmQueryKeys.configUsuariosCatalogo(), fuente],
    queryFn: async ({ signal }) => demo
      ? (await import('@/lib/demo-config')).catalogoUsuariosAdministrablesDemo()
      : listarCatalogoUsuariosAdministrables(signal),
    enabled: habilitada && autenticada,
    staleTime: 0,
  })
}

export function useConfiguracionProductos(habilitada = true) {
  const { fuente, demo, autenticada } = useFuenteConfiguracion()
  return useQuery({
    queryKey: [...crmQueryKeys.configProductos(), fuente],
    queryFn: async ({ signal }) => demo
      ? (await import('@/lib/demo-config')).configuracionProductosDemo()
      : obtenerConfiguracionProductos(signal),
    enabled: habilitada && autenticada,
  })
}

export function useProductosSeleccionables(habilitada = true) {
  const { fuente, demo, autenticada } = useFuenteConfiguracion()
  return useQuery({
    queryKey: [...crmQueryKeys.productosSeleccionables(), fuente],
    queryFn: async ({ signal }) => demo
      ? (await import('@/lib/demo-config')).productosSeleccionablesDemo()
      : listarProductosSeleccionables(signal),
    enabled: habilitada && autenticada,
  })
}

export function useConfiguracionMetas(periodo: string, habilitada = true) {
  const { fuente, demo, autenticada } = useFuenteConfiguracion()
  return useQuery({
    queryKey: [...crmQueryKeys.configMetas(periodo), fuente],
    queryFn: async ({ signal }) => demo
      ? (await import('@/lib/demo-config')).configuracionMetasDemo(periodo)
      : obtenerConfiguracionMetas(periodo, signal),
    enabled: habilitada && autenticada && Boolean(periodo),
    staleTime: 0,
  })
}

export function useConfiguracionSla(habilitada = true) {
  const { fuente, demo, autenticada } = useFuenteConfiguracion()
  return useQuery({
    queryKey: [...crmQueryKeys.configSla(), fuente],
    queryFn: async ({ signal }) => demo
      ? (await import('@/lib/demo-config')).configuracionSlaDemo()
      : obtenerConfiguracionSla(signal),
    enabled: habilitada && autenticada,
  })
}

export function useMetricasSla(
  desde: string,
  hasta: string,
  habilitada = true,
) {
  const { fuente, demo, autenticada } = useFuenteConfiguracion()
  return useQuery({
    queryKey: [...crmQueryKeys.metricasSla(desde, hasta), fuente],
    queryFn: async ({ signal }) => demo
      ? (await import('@/lib/demo-config')).metricasSlaDemo(desde, hasta)
      : obtenerMetricasSla(desde, hasta, signal),
    enabled: habilitada && autenticada && Boolean(desde) && Boolean(hasta),
  })
}

export function useEstadoSlaLeads(habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.estadoSlaLeads(),
    queryFn: ({ signal }) => listarEstadoSlaLeads(signal),
    enabled: habilitada,
    staleTime: 30_000,
  })
}

function useInvalidarUsuarios() {
  const queryClient = useQueryClient()
  return async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: [...crmQueryKeys.config(), 'usuarios'] }),
      queryClient.invalidateQueries({ queryKey: crmQueryKeys.configUsuariosCatalogo() }),
    ])
  }
}

function useInvalidarProductos() {
  const queryClient = useQueryClient()
  return async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: crmQueryKeys.configProductos() }),
      queryClient.invalidateQueries({ queryKey: crmQueryKeys.productosSeleccionables() }),
      queryClient.invalidateQueries({ queryKey: crmQueryKeys.contratos() }),
    ])
  }
}

export function useCrearCandidatoUsuario() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarUsuarios()
  return useMutation({ mutationFn: mutacionSoloReal(demo, crearCandidatoUsuario), onSuccess: invalidar })
}

export function useActualizarUsuarioAdministrable() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarUsuarios()
  return useMutation({ mutationFn: mutacionSoloReal(demo, actualizarUsuarioAdministrable), onSuccess: invalidar })
}

export function useAsignarRolUsuario() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarUsuarios()
  return useMutation({ mutationFn: mutacionSoloReal(demo, asignarRolUsuario), onSuccess: invalidar })
}

export function useActualizarJerarquiaUsuario() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarUsuarios()
  return useMutation({ mutationFn: mutacionSoloReal(demo, actualizarJerarquiaUsuario), onSuccess: invalidar })
}

export function useImpactoDesactivacionUsuario() {
  const { demo } = useFuenteConfiguracion()
  return useMutation({ mutationFn: mutacionSoloReal(demo, obtenerImpactoDesactivacion) })
}

export function useFijarMembresiaUsuario() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarUsuarios()
  return useMutation({ mutationFn: mutacionSoloReal(demo, fijarMembresiaUsuario), onSuccess: invalidar })
}

export function useCrearProductoInversion() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarProductos()
  return useMutation({ mutationFn: mutacionSoloReal(demo, crearProductoInversion), onSuccess: invalidar })
}

export function useCrearVersionProducto() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarProductos()
  return useMutation({ mutationFn: mutacionSoloReal(demo, crearVersionProducto), onSuccess: invalidar })
}

export function useActualizarBorradorProducto() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarProductos()
  return useMutation({ mutationFn: mutacionSoloReal(demo, actualizarBorradorProducto), onSuccess: invalidar })
}

export function usePublicarVersionProducto() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarProductos()
  return useMutation({
    mutationFn: mutacionSoloReal(
      demo,
      ({ versionId, expectedRevision }: { versionId: string; expectedRevision: number }) =>
        publicarVersionProducto(versionId, expectedRevision),
    ),
    onSuccess: invalidar,
  })
}

export function useArchivarProducto() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarProductos()
  return useMutation({
    mutationFn: mutacionSoloReal(
      demo,
      ({ productoId, expectedRevision }: { productoId: string; expectedRevision: number }) =>
        archivarProducto(productoId, expectedRevision),
    ),
    onSuccess: invalidar,
  })
}

export function useCerrarCompatibilidadLegacyProductos() {
  const { demo } = useFuenteConfiguracion()
  const invalidar = useInvalidarProductos()
  return useMutation({ mutationFn: mutacionSoloReal(demo, cerrarCompatibilidadLegacyProductos), onSuccess: invalidar })
}

export function usePublicarMetas(periodo: string) {
  const { demo } = useFuenteConfiguracion()
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: mutacionSoloReal(demo, publicarMetas),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: crmQueryKeys.configMetas(periodo) })
    },
  })
}

export function usePublicarPoliticaSla() {
  const { demo } = useFuenteConfiguracion()
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: mutacionSoloReal(demo, publicarPoliticaSla),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.configSla() }),
        queryClient.invalidateQueries({ queryKey: [...crmQueryKeys.metricas(), 'sla'] }),
      ])
    },
  })
}
