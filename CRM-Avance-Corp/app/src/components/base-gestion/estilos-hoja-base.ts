import { ENCABEZADO as ENCABEZADO_COMUN } from '@/components/ui/estilos-hoja'
import { cn } from '@/lib/utils'

export { CELDA } from '@/components/ui/estilos-hoja'
// Base, Vetados y Bases cargadas conservan su tamaño previo; Facturación usa el común de 14 px.
export const ENCABEZADO = cn(ENCABEZADO_COMUN, 'text-[13px]')
