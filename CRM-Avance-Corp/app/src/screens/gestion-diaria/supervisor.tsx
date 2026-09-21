import { useEffect, useLayoutEffect, useRef, useState, type JSX } from 'react'
import { RefreshCw, Users } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { filtrarOrdenarEquipo, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
import type { PestanaRegistro } from '@/lib/gestion-diaria'
import { useDiaEquipo } from '@/data/gestion-diaria-equipo-queries'
import { CrmApiError } from '@/data/crm-api'
import { TablaEquipoDiaria } from '@/components/gestion-diaria/tabla-equipo-diaria'
import { RegistroActividad } from '@/components/gestion-diaria/registro-actividad'
import { PanelVacio } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

export function GestionDiariaSupervisor(): JSX.Element {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  const consulta = useDiaEquipo(hoy)
  const [filtros, setFiltros] = useState<FiltrosEquipo>({ busqueda: '', soloProblemas: false, orden: 'atencion', ascendente: false })
  // Atar la selección al actor impide conservar un analista de otra sesión.
  const [registro, setRegistro] = useState<{ actor: string; analista: string | null; nombre: string | null; pestana: PestanaRegistro; apertura: number } | null>(null)
  const [avisoCierre, setAvisoCierre] = useState<string | null>(null)
  const apertura = useRef(0)
  const tituloEquipo = useRef<HTMLHeadingElement>(null)
  const tituloRegistro = useRef<HTMLHeadingElement>(null)
  const contenedorRegistro = useRef<HTMLElement>(null)
  const disparadorRegistro = useRef<HTMLElement | null>(null)
  const dia = consulta.error ? null : consulta.dia
  const filas = dia ? filtrarOrdenarEquipo(dia.equipo, filtros) : []
  const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  const seleccion = registro?.actor === yo?.id ? registro : null
  const analista = dia?.equipo.find((f) => f.analista_id === seleccion?.analista)
  const fueraDeAmbito = seleccion !== null && (sinPermiso || (dia !== null && seleccion.analista !== null && analista === undefined))
  // Un fallo transitorio del resumen no destruye el registro: tiene su propia
  // lectura autorizada. Una revocación o salida confirmada sí lo cierra antes
  // de pintar, avisa y devuelve el foco sólo si estaba dentro del registro.
  useLayoutEffect(() => {
    if (!fueraDeAmbito) return
    const focoDentro = contenedorRegistro.current?.contains(document.activeElement)
    setRegistro(null)
    setAvisoCierre('Se cerró el registro porque su ámbito ya no está autorizado. Revisa el equipo antes de abrir otro.')
    if (focoDentro) tituloEquipo.current?.focus()
  }, [fueraDeAmbito])
  useEffect(() => {
    if (seleccion) tituloRegistro.current?.focus()
  }, [seleccion])
  const abrirRegistro = (id: string | null, pestana: PestanaRegistro = 'todo') => {
    disparadorRegistro.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    setAvisoCierre(null)
    setRegistro({ actor: yo!.id, analista: id, nombre: dia?.equipo.find((f) => f.analista_id === id)?.nombre_completo ?? null,
      pestana, apertura: ++apertura.current })
  }
  const cerrarRegistro = () => {
    setRegistro(null)
    // El disparador de una fila permanece montado; el general puede volver
    // recién en el próximo render. No se busca un botón de otra identidad.
    requestAnimationFrame(() => {
      if (disparadorRegistro.current?.isConnected) disparadorRegistro.current.focus()
      else tituloEquipo.current?.focus()
    })
  }
  const ordenar = (orden: OrdenEquipo) => setFiltros((f) => ({ ...f, orden,
    ascendente: orden === f.orden ? !f.ascendente : orden === 'nombre' }))

  if (yo?.rol !== 'supervisor') return <p role="alert">Esta vista está disponible para supervisores autorizados.</p>

  return (
    <div className="mx-auto w-full max-w-[1640px] space-y-8">
      <section aria-label="Mi equipo hoy" className="space-y-5 text-base">
        <header className="flex flex-wrap items-start justify-between gap-4">
          <div className="max-w-3xl">
            <h2 ref={tituloEquipo} tabIndex={-1} className="text-2xl font-bold text-primary focus-visible:outline-2 focus-visible:outline-ring">¿Qué está pasando hoy en mi equipo?</h2>
            <p className="mt-2 text-[var(--muted-foreground-strong)]">Actividad registrada, pendientes y personas que necesitan atención.</p>
            <p className="mt-1 text-[var(--muted-foreground-strong)]">Hoy, {hoy} · Hora de Lima{yo?.demo ? ' · Demostración' : ''}</p>
          </div>
          <Button variant="outline" className="min-h-11 text-base" disabled={consulta.enVuelo} onClick={() => { void consulta.recargar() }}>
            <RefreshCw className="size-4" aria-hidden />{consulta.enVuelo ? 'Actualizando…' : 'Actualizar'}
          </Button>
        </header>

        {consulta.error ? (
          <div role="alert" className="rounded-xl border border-border bg-card p-6">
            <h3 className="font-semibold">{sinPermiso ? 'Ya no tienes autorización para ver este equipo' : 'No pudimos consultar la actividad y los pendientes del equipo'}</h3>
            <p className="mt-2">{sinPermiso ? 'Revisa tu acceso con gerencia. No se muestran los datos anteriores.' : 'Los datos no están disponibles; esto no significa que el equipo no tenga actividad o pendientes.'}</p>
            {!sinPermiso && <Button className="mt-4 min-h-11 text-base" disabled={consulta.enVuelo} onClick={() => { void consulta.recargar() }}>Reintentar</Button>}
          </div>
        ) : consulta.cargando || !dia ? (
          <p role="status" aria-busy="true" className="py-10">Consultando el equipo completo…</p>
        ) : dia.equipo.length === 0 ? (
          <PanelVacio icono={Users} tamano="grande" titulo="No tienes analistas activos asignados" detalle="Gerencia puede revisar la composición de tu equipo. No es un resultado de actividad cero." />
        ) : (
          <>
            <div className="border-y border-border py-4">
              <p className="leading-8"><strong>{dia.resumen.analistas} {dia.resumen.analistas === 1 ? 'analista' : 'analistas'}</strong>: {dia.resumen.con_actividad} con actividad registrada, {dia.resumen.sin_actividad} sin actividad registrada, {dia.resumen.con_pendientes} con pendientes y <strong>{dia.resumen.requieren_atencion} {dia.resumen.requieren_atencion === 1 ? 'necesita' : 'necesitan'} atención</strong>.</p>
              <p className="mt-1 text-[var(--muted-foreground-strong)]">Datos consultados a las {horaLimaDe(dia.generado_en)}. Actualización cada minuto.</p>
            </div>
            <div className="flex flex-wrap items-end justify-between gap-4">
              <label className="w-full space-y-2 sm:max-w-sm">
                <span className="block font-medium">Buscar analista</span>
                <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))}
                  className="min-h-11 text-base" placeholder="Nombre del analista" />
              </label>
              <Button variant={filtros.soloProblemas ? 'default' : 'outline'} className="min-h-11 text-base"
                aria-pressed={filtros.soloProblemas} onClick={() => setFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}>Con problema hoy ({dia.resumen.requieren_atencion})</Button>
            </div>
            <p aria-live="polite">{filas.length} de {dia.resumen.analistas} analistas</p>
            <div className="overflow-hidden rounded-xl border border-border bg-card">
              <TablaEquipoDiaria key={`${yo.id}:${hoy}`} dia={dia.dia} filas={filas} filtros={filtros} ordenar={ordenar}
                abrirRegistro={abrirRegistro} />
            </div>
            <div className="max-w-3xl space-y-2 text-[var(--muted-foreground-strong)]">
              <p>La tasa usa llamadas útiles; número errado y otra persona quedan fuera. Se califica desde {dia.umbrales.minimo_llamadas_utiles} llamadas útiles.</p>
              <p>Los pendientes reflejan su estado actual. La actividad registrada no acredita presencia ni explica una ausencia. Los cortes de jornada aún no se evalúan en esta vista.</p>
              {dia.modo_sla !== 'activo' && <p>Los primeros intentos fuera de plazo no se evalúan con el control actual. «No evaluado» no significa cero.</p>}
            </div>
            <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirRegistro(null, 'llamadas')}>Ver registro del equipo</Button>
          </>
        )}
      </section>
      {avisoCierre && <p role="status" className="text-base text-[var(--warning-text)]">{avisoCierre}</p>}
      {seleccion && (
        <section ref={contenedorRegistro} aria-label="Registro seleccionado" className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h3 ref={tituloRegistro} tabIndex={-1} className="rounded text-xl font-semibold text-primary focus-visible:outline-2 focus-visible:outline-ring">{seleccion.analista !== null ? `Registro de ${analista?.nombre_completo ?? seleccion.nombre}` : 'Registro del equipo'}</h3>
            <Button variant="outline" className="min-h-11 text-base" onClick={cerrarRegistro}>Cerrar registro</Button>
          </div>
          <p className="text-base text-[var(--muted-foreground-strong)]">{hoy} · Hora de Lima. Abre el nombre del lead para revisar su ficha; al cerrarla vuelves a este registro.</p>
          <RegistroActividad key={`${yo?.id}:${hoy}:${seleccion.apertura}`} dia={hoy} pestanaInicial={seleccion.pestana}
            analistaIds={seleccion.analista === null ? null : [seleccion.analista]} mostrarAnalista permitirExportar={false} />
        </section>
      )}
    </div>
  )
}
