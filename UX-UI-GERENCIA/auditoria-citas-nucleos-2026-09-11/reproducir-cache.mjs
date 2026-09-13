import assert from 'node:assert/strict'
import { readFile, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { resolve } from 'node:path'

// Reproducción aislada: sin Supabase, sin credenciales, sin escrituras de negocio.
const app = resolve('CRM-Avance-Corp/app')
const requireApp = createRequire(resolve(app, 'package.json'))
const { QueryClient, QueryObserver } = requireApp('@tanstack/react-query')
const reader = await readFile(resolve(app, 'src/data/citas-gerencia.ts'), 'utf8')
const keys = await readFile(resolve(app, 'src/data/crm-queries.ts'), 'utf8')
const store = await readFile(resolve(app, 'src/lib/store.tsx'), 'utf8')
assert(reader.includes("queryKey:[...crmQueryKeys.metricas(),'citas-detalle',actorId,mes]"))
assert(keys.includes("metricasReunionesPrefijo: () => [...crmQueryKeys.metricas(), 'reuniones']"))
assert(store.includes('queryKey: crmQueryKeys.metricasReunionesPrefijo()'))
assert(!store.includes('citas-detalle'))
const queryClient = new QueryClient()
let requests = 0
const observer = new QueryObserver(queryClient, {
  queryKey: ['crm', 'metricas', 'citas-detalle', 'actor-ficticio', '2026-09'],
  queryFn: async () => ({ revision: ++requests }),
  staleTime: 30000, retry: false,
})
const unsubscribe = observer.subscribe(() => {})
await observer.refetch()
const initial = requests
await queryClient.invalidateQueries({ queryKey: ['crm', 'metricas', 'reuniones'] })
const afterActualInvalidation = requests
assert.equal(afterActualInvalidation, initial, 'El prefijo viejo no debe alcanzar citas-detalle')
await queryClient.invalidateQueries({ queryKey: ['crm', 'metricas', 'citas-detalle'] })
assert.equal(requests, initial + 1, 'El prefijo del tablero sí dispara la lectura')
const evidence = {
  result: 'DEFECTO_REPRODUCIDO',
  initialRequests: initial,
  afterStoreInvalidation: afterActualInvalidation,
  afterMatchingInvalidation: requests,
  expectedBusinessBehavior: 'Refrescar Citas después de guardar, cerrar o reprogramar una cita',
  limitation: 'Reproduce el contrato de claves con QueryClient real; no ejecuta una escritura en servidor ni el flujo completo del navegador',
}
unsubscribe()
queryClient.clear()
await writeFile(new URL('./reproduccion-cache.json', import.meta.url), JSON.stringify(evidence, null, 2) + '\n')
console.log(JSON.stringify(evidence))
