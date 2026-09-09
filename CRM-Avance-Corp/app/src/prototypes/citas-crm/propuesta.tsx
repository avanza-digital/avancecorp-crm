import { TableroCitas } from '@/components/citas/propuesta'
import { MenuCRM } from './marco'
import { FuenteEjemplo } from './fuente-ejemplo'
export function PropuestaCitasCRM() {
  return <FuenteEjemplo><div className="citas-crm flex"><MenuCRM /><div className="min-w-0 flex-1"><div className="citas-contenido"><TableroCitas /></div></div></div></FuenteEjemplo>
}
