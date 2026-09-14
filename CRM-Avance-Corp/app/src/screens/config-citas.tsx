import { RefreshCw, Target } from 'lucide-react'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { ControlCitasEditor } from '@/components/config/control-citas-editor'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { useAuth } from '@/lib/auth-context'
import { administraSoloRolesCrm, puedeConfigurarCitas } from '@/lib/roles'
import { fechaHora } from '@/lib/format'
import { useControlCitas } from '@/data/control-citas'
import { textoNumeroControlCitas } from '@/lib/control-citas'

export function ConfigCitas() {
  const { yo } = useAuth()
  const { consulta, guardar, aplicar, permitido } = useControlCitas()
  if (!puedeConfigurarCitas(yo)) return <p role="alert">El Control de Citas está disponible únicamente para Superadmin.</p>
  return <ConfiguracionShell icono={Target} titulo="Control de Citas"
    descripcion="Configura las metas y reglas de gestión. Guarda un borrador, revísalo y aplícalo desde el mes elegido. Cada cambio conserva su historial."
    soloLectura={false} volverA={administraSoloRolesCrm(yo) ? 'config-usuarios' : 'config'}
    estado={{ etiqueta: 'Metas y reglas', detalle: 'Administración exclusiva de Superadmin' }}>
    {!permitido ? <p className="text-sm text-muted-foreground">La configuración compartida requiere una sesión real de Superadmin.</p>
      : consulta.isPending ? <p role="status">Cargando la configuración de Citas…</p>
      : consulta.isError && !consulta.data ? <Card><CardContent className="space-y-3 p-5">
        <p role="alert" className="text-sm text-destructive">{consulta.error instanceof Error ? consulta.error.message : 'No se pudo cargar la configuración.'}</p>
        <Button variant="outline" onClick={() => void consulta.refetch()}><RefreshCw aria-hidden /> Reintentar</Button>
      </CardContent></Card>
      : consulta.data && <>
        {consulta.isError && <div className="flex flex-wrap items-center gap-3">
          <p role="alert" className="text-sm text-destructive">No se pudo actualizar el borrador guardado. Tu edición sigue en el formulario.</p>
          <Button variant="outline" onClick={() => void consulta.refetch()}>Reintentar actualización</Button>
        </div>}
        <ControlCitasEditor key={yo?.id} consulta={consulta.data} guardar={guardar} aplicar={aplicar} />
        {consulta.data.historial.length > 0 && <Card><CardContent className="p-5">
          <details>
            <summary className="cursor-pointer rounded text-sm font-bold text-primary focus-visible:outline-2 focus-visible:outline-ring">Historial de borradores</summary>
            <ol className="mt-3 divide-y divide-border text-xs" aria-label="Historial de borradores de Citas">
              {consulta.data.historial.map(fila => <li key={fila.version} className="space-y-1 py-3">
                <div className="flex flex-wrap justify-between gap-2"><strong>Versión {fila.version}</strong><span>{fechaHora(fila.guardado_en)}</span></div>
                <p className="text-muted-foreground">Citas por lead: {textoNumeroControlCitas(fila.configuracion.citas_por_lead)} · Entrevistas: {textoNumeroControlCitas(fila.configuracion.entrevistas_porcentaje)}% · Depósitos: {textoNumeroControlCitas(fila.configuracion.depositos_porcentaje)}%</p>
                {fila.nota && <p>{fila.nota}</p>}
                {consulta.data?.aplicaciones?.filter(a => a.version === fila.version).map(a => <p key={a.version} className="font-medium text-accent-press">Aplicada desde {a.mes_inicio} · {fechaHora(a.aplicado_en)}</p>)}
              </li>)}
            </ol>
            <p className="mt-2 text-xs text-muted-foreground">Se muestran los últimos 20 borradores. Las versiones anteriores se conservan.</p>
          </details>
        </CardContent></Card>}
      </>}
  </ConfiguracionShell>
}
