import type { JSX } from 'react'
import { Badge } from '@/components/ui/badge'
import type { EstadoAnalista } from './modelo'

/**
 * D-53 (bloque 2.14): la marca del analista en «Citas del equipo», junto a su nombre donde aparece. El servidor
 * (`crm.citas_gerencia_consulta_fn`) manda `analista_estado` con las definiciones del 2.12: «de baja» = ficha del CRM
 * inactiva; «suspendido» = ficha activa y perfil del Portal inactivo (si ambas, «de baja»). Mismo estilo que la agenda del
 * equipo (2.12): «de baja» apagado (como «inactivo» de Mi cartera) y «suspendido» con el color de «Suspendido en Portal».
 * La marca dice la verdad de esta pantalla: el analista aparece porque tiene citas (o leads, o capital) en la consulta.
 */
const TITULO_DE_BAJA = 'Dado de baja del equipo: sus citas, leads y capital del mes siguen en la consulta y en los totales'
const TITULO_SUSPENDIDO = 'Suspendido en el Portal: no puede entrar, pero su ficha del CRM sigue activa; sus citas, leads y capital del mes siguen en la consulta y en los totales'

export function MarcaAnalista({ estado }: { estado?: EstadoAnalista | undefined }): JSX.Element | null {
  if (estado === 'de_baja') return <Badge color="var(--muted-foreground)" className="shrink-0" title={TITULO_DE_BAJA}>de baja</Badge>
  if (estado === 'suspendido') return <Badge color="var(--destructive)" className="shrink-0" title={TITULO_SUSPENDIDO}>suspendido</Badge>
  return null
}
