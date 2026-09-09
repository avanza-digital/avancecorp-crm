import type { ComponentProps } from 'react'
import { FichaRecorrido as Ficha } from '@/components/citas/ficha-recorrido'
import { FuenteEjemplo } from './fuente-ejemplo'
export function FichaRecorrido(props: ComponentProps<typeof Ficha>) { return <FuenteEjemplo><Ficha {...props} /></FuenteEjemplo> }
