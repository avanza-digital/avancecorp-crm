import { useEffect, useRef, useState } from 'react'
import { X } from 'lucide-react'
import { conversionCierresCoordinacion } from '@/data/crm-api'
import type { DetalleCierresCoordinacion } from '@/lib/conversion-cierres-coordinacion'
import type { ConsultaConversion } from '@/lib/conversion-coordinacion'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'

const origenes: Record<string, string> = {
  formulario: 'Formulario', formulario_3: 'Formulario 3', landing: 'Landing', referido: 'Referido', oficina: 'Oficina',
  base_cargada: 'Base cargada', otro: 'Otro', upgrade: 'Upgrade', renovacion: 'Renovación',
}
const registros = { manual: 'Registro manual', sistema: 'Registro del sistema', cartera: 'Operación de cartera' }
const fecha = (valor: string) => new Intl.DateTimeFormat('es-PE', {
  day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'UTC',
}).format(new Date(`${valor}T12:00:00Z`))

export function ConversionCierresCoordinacion({ analista, consulta, desde, hasta, onCerrar, focoRespaldo }: {
  analista: { analista_id: string; nombre: string | null }
  consulta: ConsultaConversion
  desde: string
  hasta: string
  focoRespaldo?: () => HTMLElement | null
  onCerrar: () => void
}) {
  const [pagina, setPagina] = useState(0)
  const [intento, setIntento] = useState(0)
  const [datos, setDatos] = useState<DetalleCierresCoordinacion | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [cargando, setCargando] = useState(true)
  const contenido = useRef<HTMLDivElement>(null)
  const enfocar = useRef(false)
  useEffect(() => {
    const controlador = new AbortController()
    setCargando(true)
    setDatos(null)
    void conversionCierresCoordinacion(analista.analista_id, consulta, pagina, controlador.signal)
      .then((respuesta) => {
        if (!controlador.signal.aborted) {
          setDatos(respuesta)
          setError(null)
        }
      }).catch((fallo: unknown) => {
        if (!controlador.signal.aborted) setError(fallo instanceof Error ? fallo.message : 'No se pudieron cargar los cierres.')
      }).finally(() => {
        if (!controlador.signal.aborted) setCargando(false)
      })
    return () => controlador.abort()
  }, [analista.analista_id, consulta, pagina, intento])

  useEffect(() => {
    if (datos && enfocar.current) {
      enfocar.current = false
      contenido.current?.focus()
    }
  }, [datos])

  return (
    <Sheet open onClose={onCerrar} focoRespaldo={() => focoRespaldo?.() ?? null} className="w-[560px]">
      <SheetHeader>
        <div className="flex items-start justify-between gap-3">
          <SheetTitle>Cierres de {analista.nombre ?? 'analista'}</SheetTitle>
          <Button type="button" variant="ghost" size="icon" onClick={onCerrar} aria-label="Cerrar detalle de cierres"><X aria-hidden /></Button>
        </div>
        <p className="text-sm text-muted-foreground">Del {fecha(desde)} al {fecha(hasta)}</p>
      </SheetHeader>
      <SheetBody>
        <p role="status" className="sr-only">{cargando ? 'Cargando cierres…' : error ?? (datos?.disponible ? `${datos.total} cierres y operaciones. Página ${datos.pagina + 1}.` : 'Detalle no disponible para el mes cerrado.')}</p>
        {error ? <PanelError mensaje={error} reintentando={cargando} onReintentar={() => { contenido.current?.focus(); enfocar.current = true; setIntento((n) => n + 1) }} />
          : cargando ? <PanelCargando filas={3} /> : null}
        <div ref={contenido} tabIndex={-1} className="outline-none" aria-busy={cargando}>
        {datos ? <>
          {!datos.disponible ? <p className="text-sm text-muted-foreground">El mes está cerrado. Su foto conserva las cifras, pero no guarda la lista de clientes.</p>
            : datos.total === 0 ? <p className="text-sm text-muted-foreground">No hay cierres acreditados ni operaciones de conversión en este período.</p>
              : <>
                <p className="mb-4 text-sm text-muted-foreground">{datos.total} cierres y operaciones. El aporte indica cuánto cuenta cada uno antes de los ajustes. Las cifras de meses abiertos pueden actualizarse.</p>
                <div role="list" className="divide-y divide-border" aria-label="Clientes de los cierres">
                  {datos.filas.map((fila, indice) => <div role="listitem" key={`${datos.pagina}-${indice}`} className="py-4 first:pt-0">
                    <p className="font-semibold">{fila.nombre}</p>
                    <p className="mt-1 text-sm">{origenes[fila.origen] ?? fila.origen} · {fecha(fila.fecha)}</p>
                    <div className="mt-2 flex flex-wrap justify-between gap-2 text-xs text-muted-foreground">
                      <span>{registros[fila.registro]}</span>
                      <span>Aporte a conversión: {fila.aporte.toLocaleString('es-PE', { maximumFractionDigits: 2 })}</span>
                    </div>
                  </div>)}
                </div>
                <div className="mt-4">
                  <Paginacion paginaActual={datos.pagina} paginas={Math.ceil(datos.total / datos.por_pagina)} total={datos.total}
                    ariaLabel="Paginación de cierres" onCambio={(n) => { contenido.current?.focus(); enfocar.current = true; setError(null); setPagina(n) }} />
                </div>
              </>}
        </> : null}
        </div>
      </SheetBody>
    </Sheet>
  )
}
