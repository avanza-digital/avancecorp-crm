// «Base para gestión» de Supervisión y Gerencia (F4, decisión de Miguel del 03/10/2026): dos pestañas.
//  · «Descartes del mes»: el Centro de rescate de siempre (franja de meses, mosaico, carpeta en otra pestaña y
//    reparto), INTACTO. Es la pestaña por defecto: al entrar abre ahí.
//  · «Gestión de la base»: cómo va el trabajo de la base por analista (panel), la hoja del equipo y los «No contactar».
// La pestaña y el analista elegido viven en la URL (`?rescate_vista=gestion&rescate_analista=…`, el patrón de la
// carpeta): sobreviven a recargar. Al salir de la pantalla se limpian, para que al volver se entre por «Descartes».
// Una pestaña ya visitada se conserva montada (oculta): volver no recarga el mes ni pierde la carpeta elegida.
import { useCallback, useEffect, useState, type JSX } from 'react'
import { Tabs } from '@/components/ui/tabs'
import { RescateDescartados } from '@/screens/rescate-descartados'
import { GestionSupervisor } from '@/screens/rescate/gestion-supervisor'
import { SIN_DATO } from '@/lib/base-gestion'
import {
  ANALISTA_URL_SIN,
  escribirEstadoSupervision,
  estadoSupervisionDe,
  type EstadoSupervision,
  type VistaSupervision,
} from '@/lib/base-gestion-url'

const PESTANAS = [
  { valor: 'descartes', etiqueta: 'Descartes del mes' },
  { valor: 'gestion', etiqueta: 'Gestión de la base' },
] as const satisfies readonly { valor: VistaSupervision; etiqueta: string }[]

export function BaseGestionSupervision(): JSX.Element {
  const [estado, setEstado] = useState<EstadoSupervision>(() => estadoSupervisionDe(window.location.href))
  const [visitadas, setVisitadas] = useState<ReadonlySet<VistaSupervision>>(() => new Set([estado.vista]))

  // La URL sigue al estado; al desmontar (otra pantalla) se limpia: «al entrar abre Descartes del mes».
  useEffect(() => { escribirEstadoSupervision(estado) }, [estado])
  useEffect(() => () => escribirEstadoSupervision({ vista: 'descartes', analista: null }), [])

  const cambiarVista = (vista: VistaSupervision) => {
    // El analista se recuerda aunque se pase a «Descartes» (la hoja oculta lo conserva); la URL solo lo lleva en «Gestión».
    setEstado((e) => (e.vista === vista ? e : { ...e, vista }))
    setVisitadas((v) => (v.has(vista) ? v : new Set([...v, vista])))
  }
  // El filtro de la hoja usa la clave «sin dato» para la bandeja; la URL, una palabra legible.
  const alCambiarAnalista = useCallback((analista: string | null) => {
    const enUrl = analista === SIN_DATO ? ANALISTA_URL_SIN : analista
    setEstado((e) => (e.analista === enUrl ? e : { ...e, analista: enUrl }))
  }, [])
  const [analistaInicial] = useState(() => (estado.analista === ANALISTA_URL_SIN ? SIN_DATO : estado.analista))

  return (
    <div className="mx-auto w-full max-w-[1640px]">
      <Tabs
        etiqueta="Base para gestión"
        pestanas={PESTANAS}
        valor={estado.vista}
        onCambio={cambiarVista}
        variante="subrayado"
      >
        {visitadas.has('descartes') && (
          <div hidden={estado.vista !== 'descartes'}>
            <RescateDescartados />
          </div>
        )}
        {visitadas.has('gestion') && (
          <div hidden={estado.vista !== 'gestion'}>
            <GestionSupervisor analistaInicial={analistaInicial} onAnalista={alCambiarAnalista} />
          </div>
        )}
      </Tabs>
    </div>
  )
}
