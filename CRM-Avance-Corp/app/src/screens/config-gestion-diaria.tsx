import { useEffect, useState } from 'react'
import * as v from 'valibot'
import { Clock, RefreshCw } from 'lucide-react'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { useConfiguracionGestionDiaria } from '@/data/gestion-diaria-seguimiento-queries'
import { mensajeDeError } from '@/data/crm-api'
import { desplazarJornada, ejemploSegundoCorte, jornadaLimaIso, PoliticaGestionDiariaSchema,
  ultimaRevision, type PoliticaGestionDiaria } from '@/lib/politica-gestion-diaria'
import { fechaLima } from '@/lib/agenda-derivada'

const CAMPOS = [
  ['corte_1_hora', 'Hora del primer corte', 'time'],
  ['corte_1_minimo', 'Mínimo de llamadas al primer corte', 'number'],
  ['corte_2_hora', 'Hora del segundo corte', 'time'],
  ['corte_2_incremento_pct', 'Crecimiento exigido (%)', 'number'],
  ['corte_2_piso', 'Piso de llamadas al segundo corte', 'number'],
  ['corte_2_techo', 'Techo de llamadas al segundo corte', 'number'],
  ['sabado_minimo', 'Mínimo del sábado', 'number'],
  ['bien_min_pct', 'Contacto: Bien desde (%)', 'number'],
  ['atencion_min_pct', 'Contacto: Atención desde (%)', 'number'],
  ['minimo_llamadas_utiles', 'Muestra mínima de llamadas útiles', 'number'],
  ['tasa_baja_diferencia_pp', 'Tasa muy baja (reservada para F5)', 'number'],
] as const

function fechaRevision(valor: string): string {
  return valor === '-infinity' ? 'Histórica, sin cortes' : fechaLima(Date.parse(valor))
}

function ResumenReglas({ config }: { config: PoliticaGestionDiaria }) {
  return <dl className="grid gap-x-5 gap-y-2 sm:grid-cols-2">
    <div><dt className="font-medium">Cortes</dt><dd>{config.cortes_activos ? 'Activos' : 'Desactivados'}</dd></div>
    {CAMPOS.map(([clave, etiqueta]) => <div key={clave}><dt className="font-medium">{etiqueta}</dt>
      <dd>{config[clave] ?? 'Desactivada hasta F5'}</dd></div>)}
  </dl>
}

export function ConfigGestionDiaria() {
  const { consulta, publicar, controlar, datos, habilitada } = useConfiguracionGestionDiaria()
  const [borrador, setBorrador] = useState<{ version: number; configuracion: PoliticaGestionDiaria } | null>(null)
  const [jornada, setJornada] = useState('')
  const [motivo, setMotivo] = useState('')
  const [motivoControl, setMotivoControl] = useState('')
  const [confirmacion, setConfirmacion] = useState<{ tipo: 'politica' } | { tipo: 'control'; version: number; habilitados: boolean; motivo: string } | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [exito, setExito] = useState<string | null>(null)
  const [baseEjemplo, setBaseEjemplo] = useState(8)
  const ocupado = publicar.isPending || controlar.isPending
  const editable = Boolean(datos?.puede_editar)
  const conflicto = Boolean(datos && borrador && datos.expected_version !== borrador.version)
  const conflictoControl = confirmacion?.tipo === 'control' && datos?.control_avisos.version !== confirmacion.version
  const config = borrador?.configuracion
  const valido = config ? v.safeParse(PoliticaGestionDiariaSchema, config).success : false
  const minimoDia = datos ? desplazarJornada(datos.dia, 1) : ''
  const maximoDia = datos ? desplazarJornada(datos.dia, 90) : ''
  const ultimaFecha = datos ? fechaRevision(ultimaRevision(datos).vigente_desde) : ''
  const vigenciaValida = jornada >= minimoDia && jornada <= maximoDia
    && (!/^\d{4}-/.test(ultimaFecha) || jornada >= ultimaFecha)

  // Un refresco no pisa una edición en curso. Si cambió la versión se exige
  // revisar los cambios recibidos; la misma condición se valida en servidor.
  useEffect(() => {
    if (!datos || borrador) return
    const ultima = ultimaRevision(datos)
    setBorrador({ version: datos.expected_version, configuracion: { ...ultima.configuracion } })
    const futura = fechaRevision(ultima.vigente_desde)
    setJornada(/^\d{4}-/.test(futura) && futura > datos.dia ? futura : desplazarJornada(datos.dia, 1))
  }, [datos, borrador])

  const confirmar = async () => {
    if (!datos || !borrador || ocupado || !editable || conflictoControl) return
    setError(null)
    try {
      if (confirmacion?.tipo === 'politica') {
        await publicar.mutateAsync({ version: borrador.version, configuracion: borrador.configuracion,
          vigenteDesde: jornadaLimaIso(jornada), motivo })
        setExito(`Reglas publicadas para la jornada del ${jornada}. Las reglas de hoy se conservan.`)
        setBorrador(null)
        setMotivo('')
      } else if (confirmacion?.tipo === 'control') {
        await controlar.mutateAsync({ version: confirmacion.version,
          habilitados: confirmacion.habilitados, motivo: confirmacion.motivo })
        setExito(!confirmacion.habilitados
          ? 'Canal de avisos detenido. Los resultados y pendientes siguen visibles.'
          : 'Canal de avisos reanudado según la política vigente.')
        setMotivoControl('')
      }
      setConfirmacion(null)
    } catch (e) {
      setError(mensajeDeError(e, 'No se pudo confirmar el cambio. Revisa la configuración antes de reintentar.'))
    }
  }

  if (!habilitada) return <p className="text-base">Esta configuración requiere una cuenta real de gerencia o directorio.</p>
  if (consulta.error) return <div role="alert" className="space-y-3 text-base">
    <p>No se pudo consultar la configuración. No se muestran valores anteriores.</p>
    <Button onClick={() => { void consulta.refetch() }}>Reintentar</Button>
  </div>
  if (!datos || !config) return <p role="status" className="text-base">Consultando reglas de Gestión Diaria…</p>
  const ejemplo = ejemploSegundoCorte(baseEjemplo, config)

  return <ConfiguracionShell lecturaAmplia icono={Clock} titulo="Gestión Diaria" soloLectura={!editable}
    descripcion="Reglas de llamadas y contacto para acompañar al equipo. Las nuevas versiones comienzan en una jornada futura."
    estado={{ etiqueta: `Política vigente v${datos.vigente.version}`, detalle: datos.vigente.configuracion.cortes_activos ? 'Cortes activos' : 'Cortes desactivados' }}
    acciones={<Button variant="outline" className="min-h-11 text-base" disabled={consulta.isFetching || ocupado} onClick={() => { void consulta.refetch() }}><RefreshCw aria-hidden /> Actualizar</Button>}>
    <div className="space-y-6 text-base">
      {exito && <p role="status" className="rounded-xl border border-border bg-card p-4">{exito}</p>}
      <section aria-label="Reglas vigentes" className="space-y-4 rounded-xl border border-border bg-card p-5">
        <h2 className="text-xl font-bold">Reglas de hoy · v{datos.vigente.version}</h2>
        <ResumenReglas config={datos.vigente.configuracion} />
      </section>
      {conflicto && <div role="alert" className="space-y-3 rounded-xl border border-border p-4">
        <p>Se publicó otra versión mientras editabas. Revisa la nueva configuración antes de guardar.</p>
        <Button variant="outline" className="min-h-11 text-base" onClick={() => { setBorrador(null); setError(null) }}>Cargar última versión</Button>
      </div>}
      <section className="space-y-4 rounded-xl border border-border bg-card p-5" aria-label="Reglas programadas">
        <h2 className="text-xl font-bold">Versiones programadas</h2>
        {datos.revisiones_pendientes.length === 0 ? <p>No hay cambios programados.</p>
          : <ul className="space-y-2">{datos.revisiones_pendientes.map((p) => <li key={p.version}>
            <details><summary className="cursor-pointer"><strong>v{p.version} · {fechaRevision(p.vigente_desde)}</strong> — {p.motivo}</summary>
              <div className="mt-3"><ResumenReglas config={p.configuracion} /></div></details>
          </li>)}</ul>}
        <p>Si hay varias versiones para una jornada, se aplica la de mayor número. Corregir una revisión conserva las anteriores.</p>
      </section>
      <section className="space-y-5 rounded-xl border border-border bg-card p-5" aria-label="Editar reglas de Gestión Diaria">
        <h2 className="text-xl font-bold">Próxima versión</h2>
        <p>Lunes a viernes: 09:00–18:00. Sábado: 09:00–13:00, un corte. Domingo sin avisos de jornada.</p>
        <fieldset disabled={!editable || ocupado || conflicto} className="space-y-5">
          <label className="flex min-h-11 items-center gap-3"><input type="checkbox" checked={config.cortes_activos}
            onChange={(e) => setBorrador((b) => b && ({ ...b, configuracion: { ...b.configuracion, cortes_activos: e.target.checked } }))} />
            Activar cortes desde la jornada elegida</label>
          <div className="grid gap-5 sm:grid-cols-2">
            {CAMPOS.filter(([clave]) => clave !== 'tasa_baja_diferencia_pp').map(([clave, etiqueta, tipo]) => <label key={clave} className="space-y-2">
              <span className="block font-medium">{etiqueta}</span>
              <Input type={tipo} step={tipo === 'number' ? 'any' : undefined} value={config[clave] ?? ''}
                className="min-h-11 text-base" onChange={(e) => {
                  const valor = tipo === 'time' ? e.target.value
                    : Number(e.target.value)
                  setBorrador((b) => b && ({ ...b, configuracion: { ...b.configuracion, [clave]: valor } }))
                }} />
            </label>)}
          </div>
          <p>La alerta de tasa muy baja permanece apagada hasta definirla con los datos de F5.</p>
          <div className="space-y-3 border-y border-border py-4">
            <label className="block max-w-xs space-y-2">Llamadas al primer corte para el ejemplo
              <Input type="number" min={0} step={1} value={baseEjemplo} className="min-h-11 text-base"
                onChange={(e) => setBaseEjemplo(Math.max(0, Math.trunc(Number(e.target.value) || 0)))} />
            </label>
            <p aria-live="polite">Con {baseEjemplo} llamadas a las {config.corte_1_hora}, el crecimiento pide {ejemplo.sinLimites}.
              Aplicando piso y techo, el objetivo final a las {config.corte_2_hora} es <strong>{ejemplo.objetivo} llamadas acumuladas</strong>.</p>
          </div>
          <label className="block space-y-2">Jornada de inicio (Lima)
            <Input type="date" min={minimoDia} max={maximoDia} value={jornada} className="min-h-11 max-w-xs text-base" onChange={(e) => setJornada(e.target.value)} />
          </label>
          <label className="block space-y-2">Motivo del cambio
            <Input value={motivo} maxLength={500} className="min-h-11 text-base" onChange={(e) => setMotivo(e.target.value)} />
          </label>
          {!valido && <p role="alert">Revisa las horas, cantidades y umbrales. El primer corte debe estar entre las 09:00 y las 13:00, y el segundo antes de las 18:00.</p>}
          {!vigenciaValida && <p role="alert">Elige una jornada futura dentro de 90 días, igual o posterior a la última revisión programada.</p>}
          <Button disabled={!valido || !vigenciaValida || motivo.trim().length < 3} className="min-h-11 text-base"
            onClick={() => { setError(null); setConfirmacion({ tipo: 'politica' }) }}>Revisar y publicar v{borrador!.version + 1}</Button>
        </fieldset>
      </section>
      <section className="space-y-4 rounded-xl border border-border bg-card p-5" aria-label="Control de emergencia">
        <h2 className="text-xl font-bold">Canal de avisos</h2>
        <p>{datos.control_avisos.habilitados ? 'Disponible según la política vigente.' : 'Detenido por gerencia.'} Detenerlo evita nuevas apariciones; los resultados y pendientes se conservan.</p>
        {editable && <><label className="block space-y-2">Motivo para {datos.control_avisos.habilitados ? 'detener' : 'reanudar'}
          <Input value={motivoControl} maxLength={500} disabled={ocupado} className="min-h-11 text-base" onChange={(e) => setMotivoControl(e.target.value)} />
        </label><Button variant="outline" disabled={ocupado || motivoControl.trim().length < 3} className="min-h-11 text-base"
          onClick={() => { setError(null); setConfirmacion({ tipo: 'control', version: datos.control_avisos.version, habilitados: !datos.control_avisos.habilitados, motivo: motivoControl }) }}>{datos.control_avisos.habilitados ? 'Detener avisos' : 'Reanudar avisos'}</Button></>}
      </section>
      <details className="rounded-xl border border-border bg-card p-5">
        <summary className="cursor-pointer font-semibold">Historial de reglas ({datos.historial.length})</summary>
        <ul className="mt-4 space-y-3">{datos.historial.map((p) => <li key={p.version}><details>
          <summary className="cursor-pointer"><strong>v{p.version} · {fechaRevision(p.vigente_desde)}</strong> — {p.motivo}</summary>
          <div className="mt-3"><ResumenReglas config={p.configuracion} /></div></details></li>)}</ul>
        <p className="mt-4">Las consultas de días anteriores usan sus reglas de ese día y el equipo y la jerarquía actuales.</p>
      </details>
    </div>
    <Dialog open={confirmacion !== null} onClose={() => { if (!ocupado) setConfirmacion(null) }} ariaLabel="Confirmar cambios de Gestión Diaria">
      <DialogHeader><DialogTitle className="text-xl">{confirmacion?.tipo === 'politica' ? `Publicar política v${borrador!.version + 1}` : 'Confirmar control de avisos'}</DialogTitle></DialogHeader>
      <DialogBody className="space-y-4 text-base">
        {confirmacion?.tipo === 'politica' ? <><p>Rige desde la jornada del <strong>{jornada}</strong>, hora de Lima. Las versiones publicadas no se editan.</p>
          <p>Cortes {config.cortes_activos ? 'activos' : 'desactivados'}; {config.corte_1_minimo} llamadas a las {config.corte_1_hora}.
            Segundo corte {config.corte_2_hora}: crecimiento {config.corte_2_incremento_pct} %, piso {config.corte_2_piso}, techo {config.corte_2_techo}. Sábado: {config.sabado_minimo}.</p>
          <p>Contacto: Bien desde {config.bien_min_pct} %, Atención desde {config.atencion_min_pct} % y muestra mínima {config.minimo_llamadas_utiles}.
            Tasa muy baja: {config.tasa_baja_diferencia_pp === null ? 'desactivada' : `diferencia ${config.tasa_baja_diferencia_pp} puntos`}.</p>
          <p>{motivo}</p></> : <p>{confirmacion?.tipo === 'control' && <>{confirmacion.habilitados ? 'Se reanudará el canal según la política vigente.' : 'Se detendrán nuevas apariciones de avisos.'} {confirmacion.motivo}</>}</p>}
        {error && <p role="alert">{error}</p>}
        {conflictoControl && <p role="alert">Otro gerente cambió el canal. Cancela esta confirmación y revisa su estado actual.</p>}
      </DialogBody>
      <DialogFooter><Button variant="outline" className="min-h-11 text-base" disabled={ocupado} onClick={() => setConfirmacion(null)}>Cancelar</Button>
        <Button className="min-h-11 text-base" disabled={ocupado || !editable || conflictoControl || (confirmacion?.tipo === 'politica' && conflicto)} onClick={() => { void confirmar() }}>{ocupado ? 'Guardando…' : 'Confirmar'}</Button></DialogFooter>
    </Dialog>
  </ConfiguracionShell>
}
