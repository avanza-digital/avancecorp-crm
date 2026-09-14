import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { useAuth } from '@/lib/auth-context'
import { puedeConfigurarCitas } from '@/lib/roles'
import { ControlCitasSchema, validarConsultaControlCitas, type ConsultaControlCitas, type GuardarControlCitasInput } from '@/lib/control-citas'
import { CrmApiError } from './crm-api'
import { crmQueryKeys } from './crm-queries'

function falloServidor(codigo?: string) {
  if (codigo === 'PGRST202') return new CrmApiError('El guardado del Control de Citas aún no está habilitado en este servidor.', codigo)
  if (codigo === '42501' || codigo === 'PGRST301') return new CrmApiError('Solo Superadmin puede acceder al Control de Citas.', codigo)
  if (codigo === 'PT409' || codigo === '40001' || codigo === '23505') return new CrmApiError('La configuración cambió en otra sesión. Tu edición se conserva; carga el último borrador antes de guardar.', codigo)
  if (codigo === '22023') return new CrmApiError('Completa las reglas y elige como inicio el mes actual o uno posterior antes de aplicar.', codigo)
  return new CrmApiError('No se pudo completar la operación. Reintenta; tu edición se conserva.', codigo)
}
function contrato(data: unknown): ConsultaControlCitas {
  const resultado = validarConsultaControlCitas(data)
  if (!resultado) throw new CrmApiError('La respuesta de configuración está incompleta. Reintenta la consulta.', 'CONTROL_CITAS_CONTRATO')
  return resultado
}
export async function cargarControlCitas(signal?: AbortSignal): Promise<ConsultaControlCitas> {
  if (!sb) throw falloServidor()
  const peticion = sb.schema('crm').rpc('control_citas_configuracion_fn')
  if (signal) peticion.abortSignal(signal)
  const { data, error } = await peticion
  if (error) throw falloServidor(error.code)
  return contrato(data)
}
export async function guardarControlCitas(input: GuardarControlCitasInput): Promise<ConsultaControlCitas> {
  const validada = v.safeParse(ControlCitasSchema, input.configuracion)
  if (!validada.success || !Number.isInteger(input.versionEsperada) || input.versionEsperada < 0 || input.nota.length > 500) {
    throw new CrmApiError('Revisa los valores antes de guardar.', 'CONTROL_CITAS_VALIDACION')
  }
  if (!sb) throw falloServidor()
  const { data, error } = await sb.schema('crm').rpc('guardar_control_citas_fn', {
    p_version_esperada: input.versionEsperada, p_configuracion: validada.output, p_nota: input.nota.trim(),
  })
  if (error) throw falloServidor(error.code)
  const resultado = contrato(data)
  if (resultado.version_actual !== input.versionEsperada + 1
    || !resultado.ultimo
    || Object.entries(validada.output).some(([clave, valor]) => resultado.ultimo!.configuracion[clave as keyof typeof validada.output] !== valor)) {
    throw new CrmApiError('No pudimos verificar el guardado. Recarga la configuración antes de repetir el cambio.', 'CONTROL_CITAS_GUARDADO')
  }
  return resultado
}

export async function aplicarControlCitas(version: number): Promise<ConsultaControlCitas> {
  if (!sb || !Number.isInteger(version) || version < 1) throw falloServidor('22023')
  const { data, error } = await sb.schema('crm').rpc('aplicar_control_citas_fn', { p_version_esperada: version })
  if (error) throw falloServidor(error.code)
  const resultado = contrato(data)
  if (resultado.version_actual !== version || !resultado.aplicaciones?.some(a => a.version === version)) {
    throw new CrmApiError('No pudimos verificar la aplicación. Actualiza la configuración antes de repetirla.', 'CONTROL_CITAS_GUARDADO')
  }
  return resultado
}

export function useControlCitas() {
  const { yo } = useAuth()
  const queryClient = useQueryClient()
  const permitido = puedeConfigurarCitas(yo) && yo?.demo === false
  const queryKey = ['control-citas-superadmin', yo?.id ?? null, yo?.demo ?? true] as const
  const consulta = useQuery({ queryKey, queryFn: ({ signal }) => cargarControlCitas(signal), enabled: permitido, retry: false, staleTime: 30_000 })
  const mutacion = useMutation({
    mutationFn: (input: GuardarControlCitasInput) => {
      if (!permitido) throw falloServidor('42501')
      return guardarControlCitas(input)
    },
    onSuccess: data => { queryClient.setQueryData(queryKey, data) },
    onError: error => {
      if (error instanceof CrmApiError && ['PT409', '40001', '23505', 'CONTROL_CITAS_GUARDADO', 'CONTROL_CITAS_CONTRATO'].includes(error.code ?? '')) void queryClient.invalidateQueries({ queryKey })
    },
    retry: false,
  })
  const aplicacion = useMutation({
    mutationFn: (version: number) => {
      if (!permitido) throw falloServidor('42501')
      return aplicarControlCitas(version)
    },
    onSuccess: data => {
      queryClient.setQueryData(queryKey, data)
      void queryClient.invalidateQueries({ queryKey: crmQueryKeys.citasGerenciaPrefijo() })
    },
    onError: () => { void queryClient.invalidateQueries({ queryKey }) },
    retry: false,
  })
  return { consulta, guardar: mutacion.mutateAsync, aplicar: aplicacion.mutateAsync, permitido }
}
