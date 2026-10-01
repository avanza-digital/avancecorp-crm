// Potencial del lead: caché y hooks de las cuatro vistas que lo pintan.
//
// Lectura APARTE, por ids, como el estado de los cierres: cada vista pregunta
// por los leads que tiene en pantalla y cruza la respuesta por `lead_id`. No se
// toca el tipo `Lead`, ni su mapeador, ni el store: en el store «la fila nueva
// manda» y una marca que viajara en la fila de la lista se perdería al abrir la
// ficha, que relee el lead por otra vía.
import { useCallback, useContext, useMemo, useSyncExternalStore } from 'react'
import {
  QueryClientContext, useMutation, useQuery,
  type QueryClient, type QueryKey,
} from '@tanstack/react-query'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { fechaLima } from '@/lib/agenda-derivada'
import { normalizarLeadIds } from '@/lib/cierre-estado'
import { queryClient as clienteDeLaApp } from '@/lib/query-client'
import {
  indexarPotencial, potencialRecienMarcado,
  type NivelPotencial, type PotencialLead, type PotencialLeads,
} from '@/lib/potencial'
import {
  leerPotencialDemo, marcarPotencialDemo, potencialDemoDe, suscribirPotencialDemo,
} from '@/lib/potencial-demo'
import { CrmApiError } from './crm-api'
import { marcarPotencialLead, obtenerPotencialLeads } from './potencial-api'

/**
 * Claves propias, colgadas A PROPÓSITO del prefijo de leads (`['crm', 'leads']`
 * = `crmQueryKeys.leads()`): cada mutación de un lead que pasa por el store ya
 * invalida ese prefijo, y con él esta lectura. Registrar una gestión, cerrar o
 * reasignar un lead refresca la marca sin que el store sepa que existe.
 * (Se escribe literal y no se importa de `crm-queries` para que una pantalla
 * que sustituye ese módulo en sus pruebas no arrastre a este; hay una prueba
 * que fija que los dos prefijos coinciden.)
 */
export const potencialKeys = {
  raiz: () => ['crm', 'leads', 'potencial'] as const,
  leads: (ids: readonly string[]) => [...potencialKeys.raiz(), ids] as const,
  /** Clave de la MUTACIÓN de marcar: permite saber si ya hay una en curso. */
  marcar: () => [...potencialKeys.raiz(), 'marcar'] as const,
}

export interface PotencialDeLeads {
  /** false = bandera apagada, sin sesión o aún sin respuesta: no se pinta nada. */
  habilitada: boolean
  porLead: ReadonlyMap<string, PotencialLead>
}

const SIN_POTENCIAL: PotencialDeLeads = { habilitada: false, porLead: new Map() }

/**
 * La caché donde vive el potencial: la de la pantalla (la única de la app). Una
 * pantalla montada SIN proveedor —las pruebas de pantalla que sustituyen sus
 * hooks de datos— se queda con el potencial apagado en vez de caerse: es un
 * adorno de cuatro vistas, no puede tumbar ninguna.
 */
function useCachePotencial(): { cache: QueryClient; disponible: boolean } {
  const delProveedor = useContext(QueryClientContext)
  return { cache: delProveedor ?? clienteDeLaApp, disponible: delProveedor !== undefined }
}

/**
 * Lo que OTRA lista en caché ya sabe de todos los leads pedidos. Sirve para el
 * primer instante: la ficha se abre desde una tabla o un tablero que ya trae la
 * marca de ese lead, y así su sección no aparece con retraso empujando el resto
 * de la ficha. La lectura propia se hace igual; esto solo cubre la espera.
 */
function loQueYaSeSabe(cache: QueryClient, ids: readonly string[]): PotencialLeads | undefined {
  for (const [, foto] of cache.getQueriesData<PotencialLeads>({ queryKey: potencialKeys.raiz() })) {
    if (!foto?.habilitada) continue
    const porLead = indexarPotencial(foto.items)
    const items = ids.flatMap((id) => porLead.get(id) ?? [])
    if (items.length === ids.length) return { version: 1, habilitada: true, items }
  }
  return undefined
}

/** Quien marca en la demo: el analista y el supervisor, como en el servidor. */
function puedeMarcarEnDemo(rol: string | undefined): boolean {
  return rol === 'vendedor' || rol === 'supervisor'
}

/**
 * La marca de potencial de los leads en pantalla, indexada por lead.
 * En sesión real viene de `crm.potencial_leads_fn`; en demo, de las marcas en
 * memoria, con la misma forma.
 */
export function usePotencialLeads(leadIds: readonly string[]): PotencialDeLeads {
  const { yo } = useAuth()
  const demo = yo?.demo === true
  const { cache, disponible } = useCachePotencial()
  const ids = normalizarLeadIds(leadIds)
  const consulta = useQuery({
    queryKey: potencialKeys.leads(ids),
    queryFn: ({ signal }) => obtenerPotencialLeads(ids, signal),
    enabled: disponible && yo != null && !demo && ids.length > 0,
    // Mientras llega la respuesta de ESTA lista: al cargar otra página cambia la
    // clave y se conservan las marcas ya pintadas en vez de parpadear; y si es
    // una lista nueva, se empieza con lo que otra lista ya sabe de esos leads.
    placeholderData: (anterior) => anterior ?? loQueYaSeSabe(cache, ids),
  }, cache)
  const marcasDemo = useSyncExternalStore(suscribirPotencialDemo, leerPotencialDemo, leerPotencialDemo)
  const rol = yo?.rol
  const clave = ids.join(',')
  const real = consulta.data
  return useMemo(() => {
    if (demo) {
      const contexto = { puedeMarcar: puedeMarcarEnDemo(rol), hoy: fechaLima(Date.now()) }
      const lista = clave === '' ? [] : clave.split(',')
      return { habilitada: true, porLead: new Map(lista.map((id) => [id, potencialDemoDe(id, marcasDemo, contexto)])) }
    }
    if (!real?.habilitada) return SIN_POTENCIAL
    return { habilitada: true, porLead: indexarPotencial(real.items) }
  }, [demo, rol, clave, marcasDemo, real])
}

/** La marca de UN lead (ficha). Comparte caché con las listas que ya lo traen. */
export function usePotencialLead(leadId: string): { habilitada: boolean; item: PotencialLead | undefined } {
  const ids = useMemo(() => [leadId], [leadId])
  const { habilitada, porLead } = usePotencialLeads(ids)
  return { habilitada, item: porLead.get(leadId) }
}

type FotosPrevias = Array<[QueryKey, PotencialLeads | undefined]>

/**
 * Marcar el potencial. Optimista: el NIVEL cambia al instante en todas las
 * listas en caché que traen ese lead (tabla, tablero, cola y ficha); si el
 * servidor la rechaza, se deshace y se avisa.
 *
 * El optimismo llega hasta ahí: cuándo y a qué nivel bajará la marca NO se
 * calcula aquí (esa regla es del servidor y no se copia). `marcando` sigue en
 * true hasta que termina la relectura —`onSettled` devuelve su promesa—, así
 * que quien pinta la marca puede decir «guardando» mientras tanto y, al
 * terminar, enseñar exactamente lo que contestó el servidor.
 */
export function useMarcarPotencial(): { marcar: (leadId: string, nivel: NivelPotencial) => void; marcando: boolean } {
  const { yo } = useAuth()
  const demo = yo?.demo === true
  const { cache } = useCachePotencial()
  const mutacion = useMutation({
    mutationKey: potencialKeys.marcar(),
    mutationFn: ({ leadId, nivel }: { leadId: string; nivel: NivelPotencial }) => marcarPotencialLead(leadId, nivel),
    onMutate: async ({ leadId, nivel }): Promise<{ previas: FotosPrevias }> => {
      await cache.cancelQueries({ queryKey: potencialKeys.raiz() })
      const previas = cache.getQueriesData<PotencialLeads>({ queryKey: potencialKeys.raiz() })
      const ahora = Date.now()
      cache.setQueriesData<PotencialLeads>({ queryKey: potencialKeys.raiz() }, (foto) => foto && {
        ...foto,
        items: foto.items.map((item) => (item.lead_id === leadId ? potencialRecienMarcado(item, nivel, ahora) : item)),
      })
      return { previas }
    },
    onError: (error, _variables, contexto) => {
      for (const [clave, foto] of contexto?.previas ?? []) cache.setQueryData(clave, foto)
      toast.error(error instanceof CrmApiError ? error.message : 'No se pudo guardar la marca de potencial.')
    },
    onSettled: () => cache.invalidateQueries({ queryKey: potencialKeys.raiz() }),
  }, cache)
  const { mutate } = mutacion
  const marcar = useCallback((leadId: string, nivel: NivelPotencial) => {
    if (demo) {
      marcarPotencialDemo(leadId, nivel)
      return
    }
    // Una sola marca a la vez, y la guarda NO depende de que la pantalla se haya
    // vuelto a pintar: dos activaciones en el mismo instante (doble clic, Enter
    // repetido) llegan aquí antes de que nadie vea `marcando`. La caché sí lo
    // sabe al momento.
    if (cache.isMutating({ mutationKey: potencialKeys.marcar() }) > 0) return
    mutate({ leadId, nivel })
  }, [demo, cache, mutate])
  return { marcar, marcando: mutacion.isPending }
}
