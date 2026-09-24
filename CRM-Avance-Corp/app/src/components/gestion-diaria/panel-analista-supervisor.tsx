import { useLayoutEffect, useRef, useState, type RefObject } from 'react'
import { Title as TituloDialogo } from '@radix-ui/react-dialog'
import { Maximize2, Minimize2, X, Users } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Tabs } from '@/components/ui/tabs'
import { DetalleAnalista } from './detalle-analista'
import { RegistroActividad } from './registro-actividad'
import { PendientesSupervisor } from './pendientes-supervisor'
import { UltimasGestionesSupervisor } from './ultimas-gestiones-supervisor'
import { MOTIVOS_EQUIPO, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
import type { PestanaRegistro } from '@/lib/gestion-diaria'
import { textoTasa } from '@/lib/gestion-diaria-analista'

export interface SeleccionSupervisor { analista: string | null; nombre: string | null; apertura: number; pestana: PestanaRegistro; enfocar: boolean }
type PestanaPanel = 'resumen' | 'registro' | 'pendientes'

export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, tituloRef, ampliado, ampliar, cerrar, puedeAmpliar, oculta, limpiar, actualizacion, revalidar }: {
  id: string
  seleccion: SeleccionSupervisor | null
  fila: FilaEquipoPresentada | undefined
  dia: string
  minimo: number | undefined
  tituloRef: RefObject<HTMLHeadingElement | null>
  ampliado: boolean
  puedeAmpliar: boolean
  ampliar: () => void
  cerrar: () => void
  oculta: boolean
  limpiar: () => void
  actualizacion: number
  revalidar: () => void
}) {
  const titulo = seleccion ? seleccion.analista === null ? 'Registro del equipo' : `Detalle de ${fila?.nombre_completo ?? seleccion.nombre}` : 'Detalle del analista'
  return (
    <section id={id} aria-label={titulo} className="gd-panel">
      <header className="gd-panel-cabecera">
        <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1}>{titulo}</h3></TituloDialogo>
        {seleccion && <div className="flex shrink-0">
          {puedeAmpliar && <Button variant="ghost" size="icon" className="size-11" aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden /> : <Maximize2 aria-hidden />}</Button>}
          <Button variant="ghost" size="icon" className="size-11" aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden /></Button>
        </div>}
      </header>
      {!seleccion ? <div className="gd-panel-inicial"><Users className="size-10 text-muted-foreground" aria-hidden /><p>Selecciona un analista de la tabla para consultar su día.</p></div>
        : <ContenidoSeleccionado key={`${seleccion.analista ?? 'equipo'}:${seleccion.apertura}`} seleccion={seleccion} fila={fila} dia={dia} minimo={minimo}
          tituloRef={tituloRef} oculta={oculta} limpiar={limpiar} actualizacion={actualizacion} revalidar={revalidar} />}
    </section>
  )
}

function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta, limpiar, actualizacion, revalidar }: Pick<Parameters<typeof PanelAnalistaSupervisor>[0], 'seleccion' | 'fila' | 'dia' | 'minimo' | 'tituloRef' | 'oculta' | 'limpiar' | 'actualizacion' | 'revalidar'> & { seleccion: SeleccionSupervisor }) {
  const equipo = seleccion.analista === null
  const [pestana, setPestana] = useState<PestanaPanel>(equipo || seleccion.enfocar ? 'registro' : 'resumen')
  const [registro, setRegistro] = useState<{ pestana: PestanaRegistro; apertura: number } | null>(equipo || seleccion.enfocar ? { pestana: seleccion.pestana, apertura: 0 } : null)
  const [pendientes, setPendientes] = useState<{ soloVencidas: boolean; apertura: number; enfocar: boolean } | null>(null)
  const tituloRegistro = useRef<HTMLHeadingElement>(null)
  const [focoRegistro, setFocoRegistro] = useState(0)
  useLayoutEffect(() => {
    if (seleccion.enfocar) tituloRef.current?.focus({ preventScroll: true })
  }, [seleccion.enfocar, tituloRef])
  useLayoutEffect(() => {
    if (focoRegistro) tituloRegistro.current?.focus({ preventScroll: true })
  }, [focoRegistro])
  const cambiar = (valor: PestanaPanel) => {
    setPestana(valor)
    if (valor === 'registro' && !registro) setRegistro({ pestana: 'todo', apertura: 0 })
    if (valor === 'pendientes' && !pendientes) setPendientes({ soloVencidas: false, apertura: 0, enfocar: false })
  }
  const abrirRegistro = (inicial: PestanaRegistro) => {
    setRegistro((r) => ({ pestana: inicial, apertura: (r?.apertura ?? 0) + 1 }))
    setPestana('registro')
    setFocoRegistro((n) => n + 1)
  }
  const abrirPendientes = (soloVencidas: boolean) => {
    setPendientes(p => ({ soloVencidas, apertura: (p?.apertura ?? 0) + 1, enfocar: true }))
    setPestana('pendientes')
  }
  const contenido = <>
    <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
      {!fila ? <p role="status">El resumen no está disponible. El registro conserva su consulta independiente.</p> : <>
        <div className="gd-resumen-principal"><strong>{fila.marcador.llamadas}</strong><span>Llamadas registradas</span></div>
        <p className="mb-3 text-[var(--muted-foreground-strong)]">{fila.gestiones_hoy} gestiones · {dia} · Lima</p>
        <p><strong>Contacto: {textoTasa(fila.marcador)}</strong> · {fila.marcador.contestadas} de {fila.marcador.utiles} llamadas útiles. {fila.marcador.utiles === 0 ? 'Sin llamadas útiles.' : fila.marcador.nivel === null ? 'Sin muestra suficiente.' : ''} Mínimo: {minimo ?? 'no disponible'}.</p>
        <p className="mt-2 text-[var(--muted-foreground-strong)]">Número errado y otra persona quedan fuera del contacto útil.</p>
        {fila.motivos_atencion.length > 0 && <div className="gd-atencion-detalle"><h4 className="font-semibold">Necesita atención</h4><ul className="list-disc pl-5">{fila.motivos_atencion.map((m) => <li key={m}>{MOTIVOS_EQUIPO[m]}</li>)}</ul></div>}
        <div className="my-3 flex flex-wrap gap-2">
          <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirPendientes(false)}>Ver pendientes ({fila.tareas_pendientes})</Button>
          {fila.tareas_vencidas > 0 && <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirPendientes(true)}>{fila.tareas_vencidas} tareas vencidas</Button>}
        </div>
        <DetalleAnalista fila={fila} dia={dia} abrirLlamadas={() => abrirRegistro('llamadas')} />
      </>}
      {seleccion.analista !== null && <>
        <UltimasGestionesSupervisor analista={seleccion.analista} dia={dia} visible={pestana === 'resumen'} actualizacion={actualizacion} revalidar={revalidar} />
        <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirRegistro('todo')}>Ver registro</Button>
      </>}
    </div>
    <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
      {registro && <section aria-label="Registro seleccionado">
        <h4 ref={tituloRegistro} tabIndex={-1} className="mb-3 font-semibold">{equipo ? 'Registro del equipo' : `Registro de ${seleccion.nombre}`}</h4>
        <RegistroActividad key={registro.apertura} dia={dia} pestanaInicial={registro.pestana}
          analistaIds={seleccion.analista === null ? null : [seleccion.analista]} mostrarAnalista={equipo} permitirEquipo={false} permitirExportar={false} actualizacion={actualizacion} onSinPermiso={revalidar} compartirPrimeraPagina={!equipo} />
      </section>}
    </div>
    <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'pendientes'} inert={pestana !== 'pendientes'}>
      {pendientes && seleccion.analista !== null && <PendientesSupervisor key={pendientes.apertura}
        analista={seleccion.analista} nombre={fila?.nombre_completo ?? seleccion.nombre ?? 'Analista'} dia={dia} fila={fila}
        visible={pestana === 'pendientes'} soloVencidasInicial={pendientes.soloVencidas} apertura={pendientes.apertura}
        enfocar={pendientes.enfocar} actualizacion={actualizacion} revalidar={revalidar} />}
    </div>
  </>
  return <>
    {oculta && <div className="gd-seleccion-oculta">La selección está fuera de los filtros.<Button variant="ghost" className="min-h-11 text-base" onClick={limpiar}>Limpiar filtros</Button></div>}
    {equipo ? contenido : <Tabs className="gd-pestanas-panel" tamano="grande" etiqueta="Detalle del analista" valor={pestana} onCambio={cambiar}
      pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, { valor: 'pendientes', etiqueta: 'Pendientes' }]}>{contenido}</Tabs>}
  </>
}
