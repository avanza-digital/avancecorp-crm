import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Network, UserRound, Users } from 'lucide-react'
import { panelDistribucionReparto } from '@/data/crm-api'
import {
  etiquetaOrigen,
  ORIGENES_TODOS,
  type DistribucionAnalista,
  type DistribucionSupervisor,
  type PanelDistribucionReparto as PanelDistribucionRepartoData,
} from '@/lib/tipos'
import { paginar } from '@/lib/paginacion'
import { Card } from '@/components/ui/card'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { ReporteDiarioDerivaciones } from '@/components/app/reporte-diario-derivaciones'

const POR_PAGINA = 10

interface Filtros {
  supervisorId: string
  analistaId: string
  origen: string
}

interface EstadoPanel {
  datos: PanelDistribucionRepartoData | null
  cargando: boolean
  error: string | null
}

interface CatalogoResponsables {
  supervisores: DistribucionSupervisor[]
  analistas: DistribucionAnalista[]
}

/**
 * Tablero compacto de la tenencia actual. Los conteos viven en la RPC: el
 * navegador no ve ni cuenta leads individuales, y cada tabla se pagina de a
 * diez para que el panel no se convierta en una lista interminable.
 */
export function PanelDistribucionReparto() {
  const [filtros, setFiltros] = useState<Filtros>({ supervisorId: '', analistaId: '', origen: '' })
  const [estado, setEstado] = useState<EstadoPanel>({ datos: null, cargando: true, error: null })
  const [catalogo, setCatalogo] = useState<CatalogoResponsables | null>(null)
  const [paginaSupervisores, setPaginaSupervisores] = useState(0)
  const [paginaAnalistas, setPaginaAnalistas] = useState(0)
  const abortRef = useRef<AbortController | null>(null)

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setEstado((prev) => ({ ...prev, cargando: true, error: null }))
    try {
      const datos = await panelDistribucionReparto({
        ...(filtros.supervisorId ? { supervisorId: filtros.supervisorId } : {}),
        ...(filtros.analistaId ? { analistaId: filtros.analistaId } : {}),
        ...(filtros.origen ? { origen: filtros.origen as (typeof ORIGENES_TODOS)[number]['k'] } : {}),
      }, ctrl.signal)
      if (ctrl.signal.aborted) return
      setEstado({ datos, cargando: false, error: null })
      // El catálogo se conserva sin filtros para que al elegir un supervisor
      // siga siendo posible cambiar directamente a cualquier otro.
      setCatalogo((actual) => actual ?? {
        supervisores: datos.supervisores,
        analistas: datos.analistas,
      })
    } catch (error) {
      if (ctrl.signal.aborted) return
      setEstado((prev) => ({
        ...prev,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar el panel de distribución.',
      }))
    }
  }, [filtros])

  useEffect(() => {
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  const cambiarFiltros = useCallback((siguiente: Partial<Filtros>) => {
    setFiltros((actual) => ({ ...actual, ...siguiente }))
    setPaginaSupervisores(0)
    setPaginaAnalistas(0)
  }, [])

  const analistasElegibles = useMemo(
    () => (catalogo?.analistas ?? []).filter((analista) => (
      !filtros.supervisorId || analista.supervisor_id === filtros.supervisorId
    )),
    [catalogo, filtros.supervisorId],
  )
  const supervisores = paginar(estado.datos?.supervisores ?? [], paginaSupervisores, POR_PAGINA)
  const analistas = paginar(estado.datos?.analistas ?? [], paginaAnalistas, POR_PAGINA)
  if (estado.cargando && !estado.datos) {
    return (
      <div className="space-y-4">
        <ReporteDiarioDerivaciones />
        <Card className="overflow-hidden">
          <SectionHead icon={Network} title="Cartera activa actual" />
          <PanelCargando filas={5} />
        </Card>
      </div>
    )
  }

  if (estado.error && !estado.datos) {
    return (
      <div className="space-y-4">
        <ReporteDiarioDerivaciones />
        <Card className="overflow-hidden">
          <SectionHead icon={Network} title="Cartera activa actual" />
          <PanelError mensaje={estado.error} onReintentar={() => void cargar()} reintentando={estado.cargando} />
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <ReporteDiarioDerivaciones />

      <AvisoDegradacion
        activo={Boolean(estado.error)}
        queReintenta="del panel de distribución"
        onReintentar={() => { void cargar() }}
      >
        No se pudo actualizar el panel. Se conserva la última foto cargada.
      </AvisoDegradacion>

      <Card className="overflow-hidden">
        <SectionHead
          icon={Network}
          title="Cartera activa actual"
          right={(
            <span className="text-[11px] font-semibold tabular-nums text-muted-foreground" role="status">
              {estado.cargando ? 'Actualizando…' : `${estado.datos?.total_leads ?? 0} activos`}
            </span>
          )}
        />
        <p className="px-5 pb-3 text-xs text-muted-foreground">
          Consulta dónde están hoy los leads que continúan activos. Esta foto no reemplaza el historial de entregas de arriba.
        </p>
        <div className="grid gap-3 border-t border-border bg-muted/15 px-5 py-4 sm:grid-cols-3">
          <label className="grid gap-1.5 text-xs font-semibold text-foreground">
            Supervisor actual
            <Select
              value={filtros.supervisorId}
              aria-label="Filtrar cartera actual por supervisor"
              onChange={(event) => cambiarFiltros({ supervisorId: event.target.value, analistaId: '' })}
            >
              <option value="">Todos los supervisores</option>
              {(catalogo?.supervisores ?? []).map((supervisor) => (
                <option key={supervisor.perfil_id} value={supervisor.perfil_id}>{supervisor.nombre}</option>
              ))}
            </Select>
          </label>
          <label className="grid gap-1.5 text-xs font-semibold text-foreground">
            Analista actual
            <Select
              value={filtros.analistaId}
              aria-label="Filtrar cartera actual por analista"
              onChange={(event) => cambiarFiltros({ analistaId: event.target.value })}
            >
              <option value="">Todos los analistas</option>
              {analistasElegibles.map((analista) => (
                <option key={analista.perfil_id} value={analista.perfil_id}>{analista.nombre}</option>
              ))}
            </Select>
          </label>
          <label className="grid gap-1.5 text-xs font-semibold text-foreground">
            Origen
            <Select
              value={filtros.origen}
              aria-label="Filtrar cartera actual por origen"
              onChange={(event) => cambiarFiltros({ origen: event.target.value })}
            >
              <option value="">Todos los orígenes</option>
              {ORIGENES_TODOS.map((origen) => (
                <option key={origen.k} value={origen.k}>{origen.label}</option>
              ))}
            </Select>
          </label>
        </div>
        <p className="border-t border-border px-5 py-2 text-xs text-muted-foreground">
          {filtros.origen
            ? `Mostrando únicamente el origen ${etiquetaOrigen(filtros.origen)}.`
            : 'Incluye Referidos, LANDING, FORMULARIO, Walking y los orígenes históricos.'}
        </p>
      </Card>

      <Card className="overflow-hidden">
        <SectionHead
          icon={Users}
          title="Leads por supervisor"
          right={<span className="text-[11px] font-semibold text-muted-foreground">Bandeja propia + analistas a cargo</span>}
        />
        {supervisores.visibles.length === 0 ? (
          <PanelVacio
            icono={Users}
            titulo="No hay supervisores que coincidan"
            detalle="Prueba con otros filtros para ver la distribución actual."
          />
        ) : (
          <>
            <TablaEnvoltura ariaLabel="Leads distribuidos por supervisor">
              <TheadCrm>
                <Th>Supervisor</Th>
                <Th className="text-right">Leads</Th>
              </TheadCrm>
              <tbody>
                {supervisores.visibles.map((supervisor) => (
                  <tr key={supervisor.perfil_id} className="border-b border-border last:border-0">
                    <Td className="font-medium">{supervisor.nombre}</Td>
                    <Td className="text-right font-semibold tabular-nums">{supervisor.total_leads}</Td>
                  </tr>
                ))}
              </tbody>
            </TablaEnvoltura>
            <div className="border-t border-border px-4 py-2.5">
              <Paginacion
                paginaActual={supervisores.paginaActual}
                paginas={supervisores.paginas}
                total={estado.datos?.supervisores.length ?? 0}
                onCambio={setPaginaSupervisores}
                ariaLabel="Paginación de supervisores"
              />
            </div>
          </>
        )}
      </Card>

      <Card className="overflow-hidden">
        <SectionHead
          icon={UserRound}
          title="Leads por analista"
          right={<span className="text-[11px] font-semibold text-muted-foreground">Asignados directamente</span>}
        />
        {analistas.visibles.length === 0 ? (
          <PanelVacio
            icono={UserRound}
            titulo="No hay analistas que coincidan"
            detalle="Prueba con otros filtros para ver la distribución actual."
          />
        ) : (
          <>
            <TablaEnvoltura ariaLabel="Leads distribuidos por analista">
              <TheadCrm>
                <Th>Analista</Th>
                <Th className="hidden sm:table-cell">Supervisor</Th>
                <Th className="text-right">Leads</Th>
              </TheadCrm>
              <tbody>
                {analistas.visibles.map((analista) => (
                  <tr key={analista.perfil_id} className="border-b border-border last:border-0">
                    <Td className="font-medium">{analista.nombre}</Td>
                    <Td className="hidden sm:table-cell text-muted-foreground">{analista.supervisor_nombre}</Td>
                    <Td className="text-right font-semibold tabular-nums">{analista.total_leads}</Td>
                  </tr>
                ))}
              </tbody>
            </TablaEnvoltura>
            <div className="border-t border-border px-4 py-2.5">
              <Paginacion
                paginaActual={analistas.paginaActual}
                paginas={analistas.paginas}
                total={estado.datos?.analistas.length ?? 0}
                onCambio={setPaginaAnalistas}
                ariaLabel="Paginación de analistas"
              />
            </div>
          </>
        )}
      </Card>
    </div>
  )
}
