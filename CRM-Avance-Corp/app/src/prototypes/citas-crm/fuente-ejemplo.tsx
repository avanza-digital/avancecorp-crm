import type { ReactNode } from 'react'
import { ContextoCitas } from '@/components/citas/contexto'
import { CITAS_CRM } from './datos'
import { DEPOSITOS_EJEMPLO } from './depositos'
import { CORTE } from '../../../prototypes/citas-assets/model.mjs'
export function FuenteEjemplo({ children }: { children: ReactNode }) {
  return <ContextoCitas value={{ citas:CITAS_CRM, corte:CORTE, depositos:DEPOSITOS_EJEMPLO, depositosDisponibles:true, mesInicial:'2026-09', modoDemo:true, meses:Array.from({length:12},(_,i) => `2026-${String(i+1).padStart(2,'0')}`) }}>{children}</ContextoCitas>
}
