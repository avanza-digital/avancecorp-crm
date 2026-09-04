import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { CalendarDays } from 'lucide-react'
import { listarReporteDerivacionesCoordinacion } from '@/data/crm-api'
import { useAhora } from '@/lib/ahora'
import { fmtFecha } from '@/lib/format'
import { paginar } from '@/lib/paginacion'
import type { ReporteDerivacionesCoordinacion } from '@/lib/reporte-derivaciones-coordinacion'
import { usePeriodoDerivaciones } from '@/lib/use-periodo-derivaciones'
import { ControlesPeriodoDerivaciones } from '@/components/common/controles-periodo-derivaciones'
import { Paginacion } from '@/components/common/paginacion'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { Card } from '@/components/ui/card'

const DIAS_POR_PAGINA = 7

interface EstadoReporte {
  datos: ReporteDerivacionesCoordinacion | null
  cargando: boolean
  error: string | null
}

/** Reporte histórico diario de todos los equipos para Coordinación y Gerencia. */
export function ReporteDiarioDerivaciones() {
  const ahora = useAhora()
  const {
    modo,
    setModo,
    desdeRango,
    setDesdeRango,
    hastaRango,
    setHastaRango,
    periodo,
    rangoValido,
    hoy,
  } = usePeriodoDerivaciones(ahora)
  const [estado, setEstado] = useState<EstadoReporte>({ datos: null, cargando: true, error: null })
  const [pagina, setPagina] = useState(0)
  const abortRef = useRef<AbortController | null>(null)

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    if (!rangoValido) {
      setEstado({ datos: null, cargando: false, error: null })
      return
    }
    const controlador = new AbortController()
    abortRef.current = controlador
    setEstado({ datos: null, cargando: true, error: null })
    try {
      const datos = await listarReporteDerivacionesCoordinacion(
        periodo.desde,
        periodo.hasta,
        controlador.signal,
      )
      if (controlador.signal.aborted) return
      setEstado({ datos, cargando: false, error: null })
    } catch (error) {
      if (controlador.signal.aborted) return
      setEstado({
        datos: null,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar el reporte diario.',
      })
    }
  }, [periodo.desde, periodo.hasta, rangoValido])

  useEffect(() => {
    setPagina(0)
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  const dias = useMemo(
    () => paginar(estado.datos?.dias ?? [], pagina, DIAS_POR_PAGINA),
    [estado.datos?.dias, pagina],
  )

  return (
    <Card className="overflow-hidden">
      <SectionHead
        icon={CalendarDays}
        title="Derivaciones diarias por analista"
        right={estado.datos ? (
          <span className="text-[11px] font-semibold tabular-nums text-muted-foreground">
            {estado.datos.total_derivados} {estado.datos.total_derivados === 1 ? 'lead' : 'leads'} en el período
          </span>
        ) : undefined}
      />
      <ControlesPeriodoDerivaciones
        modo={modo}
        desde={desdeRango}
        hasta={hastaRango}
        hoy={hoy}
        rangoInvalido={!rangoValido}
        titulo="Período del reporte diario"
        descripcion="Cada fecha muestra cuánto recibió cada analista."
        onModo={setModo}
        onDesde={(fecha) => {
          setModo('rango')
          setDesdeRango(fecha)
        }}
        onHasta={(fecha) => {
          setModo('rango')
          setHastaRango(fecha)
        }}
      />

      {!rangoValido ? (
        <p className="px-5 py-4 text-sm text-muted-foreground">
          Corrige el rango para consultar las derivaciones diarias.
        </p>
      ) : estado.cargando ? (
        <PanelCargando filas={5} />
      ) : estado.error ? (
        <PanelError mensaje={estado.error} onReintentar={() => void cargar()} reintentando={estado.cargando} />
      ) : estado.datos ? (
        <>
          <TablaEnvoltura ariaLabel="Derivaciones diarias por analista">
            <TheadCrm>
              <Th>Fecha</Th>
              <Th>Analista</Th>
              <Th>Supervisor</Th>
              <Th className="text-right">Leads derivados</Th>
            </TheadCrm>
            <tbody>
              {dias.visibles.flatMap((dia) => (
                dia.analistas.length === 0
                  ? [(
                      <tr key={dia.fecha} className="border-b border-border last:border-0">
                        <Td><time dateTime={dia.fecha}>{fmtFecha(dia.fecha)}</time></Td>
                        <Td colSpan={2} className="text-muted-foreground">Sin derivaciones</Td>
                        <Td className="text-right font-semibold tabular-nums">0</Td>
                      </tr>
                    )]
                  : dia.analistas.map((analista) => (
                      <tr
                        key={`${dia.fecha}-${analista.supervisor_id}-${analista.analista_id}`}
                        className="border-b border-border last:border-0"
                      >
                        <Td><time dateTime={dia.fecha}>{fmtFecha(dia.fecha)}</time></Td>
                        <Td className="font-medium">{analista.analista_nombre}</Td>
                        <Td className="text-muted-foreground">{analista.supervisor_nombre}</Td>
                        <Td className="text-right font-semibold tabular-nums">{analista.derivados}</Td>
                      </tr>
                    ))
              ))}
            </tbody>
          </TablaEnvoltura>
          <div className="border-t border-border px-4 py-2.5">
            <Paginacion
              paginaActual={dias.paginaActual}
              paginas={dias.paginas}
              total={estado.datos.dias.length}
              onCambio={setPagina}
              ariaLabel="Paginación de días del reporte de derivaciones"
            />
          </div>
          <p className="border-t border-border px-5 py-2 text-xs text-muted-foreground">
            Cuenta las entregas confirmadas desde la bandeja de cada supervisor; una devolución previa a la gestión no suma.
          </p>
        </>
      ) : null}
    </Card>
  )
}
