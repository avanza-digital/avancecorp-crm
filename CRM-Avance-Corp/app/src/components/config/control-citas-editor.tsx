import { useRef, useState, type FormEvent } from 'react'
import * as v from 'valibot'
import { Save, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import {
  ControlCitasSchema, controlCitasInicial, ejemploControlCitas, numeroControlCitas,
  MesControlCitasSchema, textoNumeroControlCitas,
  OPCIONES_CONTROL_CITAS, pendientesControlCitas, REGLAS_CONTROL_CITAS,
  type ConsultaControlCitas, type ControlCitas, type GuardarControlCitasInput,
} from '@/lib/control-citas'

const CAMPOS_META = [
  { clave: 'citas_por_lead', etiqueta: 'Citas por lead', ayuda: 'Meta interna. No se muestra en el tablero.', maximo: 10 },
  { clave: 'entrevistas_porcentaje', etiqueta: 'Objetivo de entrevistas (%)', ayuda: 'Porcentaje que quieres alcanzar con la gestión.', maximo: 100 },
  { clave: 'depositos_porcentaje', etiqueta: 'Objetivo de depósitos (%)', ayuda: 'Cada persona convertida cuenta una sola vez.', maximo: 100 },
] as const
type CampoMeta = (typeof CAMPOS_META)[number]['clave']
const textosMetas = (config: ControlCitas) => Object.fromEntries(
  CAMPOS_META.map(campo => [campo.clave, textoNumeroControlCitas(config[campo.clave])]),
) as Record<CampoMeta, string>
const numero = (valor: number) => new Intl.NumberFormat('es-PE', { maximumFractionDigits: 2 }).format(valor)

/** El borrador no se reemplaza por un refetch: conserva la versión que se editó. */
export function ControlCitasEditor({ consulta, guardar, aplicar, practica = false }: {
  consulta: ConsultaControlCitas
  guardar: (input: GuardarControlCitasInput) => Promise<ConsultaControlCitas>
  aplicar?: (version: number) => Promise<ConsultaControlCitas>
  practica?: boolean
}) {
  const [base, setBase] = useState(consulta)
  const [config, setConfig] = useState(() => consulta.ultimo?.configuracion ?? controlCitasInicial())
  const [metas, setMetas] = useState(() => textosMetas(config))
  const [nota, setNota] = useState('')
  const [ocupado, setOcupado] = useState(false)
  const [errores, setErrores] = useState<Partial<Record<CampoMeta, string>>>({})
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')
  const [errorMes, setErrorMes] = useState('')
  const [confirmarCarga, setConfirmarCarga] = useState(false)
  const [confirmarAplicacion, setConfirmarAplicacion] = useState(false)
  const reglasRef = useRef<HTMLDetailsElement>(null)
  const guardarRef = useRef<HTMLButtonElement>(null)

  const candidata = { ...config }
  for (const campo of CAMPOS_META) candidata[campo.clave] = numeroControlCitas(metas[campo.clave]) ?? Number.NaN
  const valida = v.safeParse(ControlCitasSchema, candidata)
  const pendientes = pendientesControlCitas(config)
  const ejemplo = valida.success ? ejemploControlCitas(valida.output) : null
  const original = base.ultimo?.configuracion ?? controlCitasInicial()
  const edicionCambiada = nota.trim() !== ''
    || JSON.stringify(candidata) !== JSON.stringify(original)
  const cambios = base.version_actual === 0 || edicionCambiada
  const desactualizada = consulta.version_actual > base.version_actual
  const aplicada = consulta.aplicaciones?.find(a => a.version === base.version_actual)
  const puedeAplicar = Boolean(aplicar && consulta.aplicaciones && base.version_actual > 0
    && !edicionCambiada && !desactualizada && pendientes.length === 0 && !aplicada)

  async function aplicarVersion() {
    if (!aplicar || !puedeAplicar || ocupado) return
    setOcupado(true); setError(''); setMensaje('')
    try {
      const resultado = await aplicar(base.version_actual)
      setBase(resultado); setConfirmarAplicacion(false)
      setMensaje(`Versión ${base.version_actual} aplicada desde ${config.mes_inicio}. Citas usará estas reglas en los meses correspondientes.`)
    } catch (fallo) {
      setError(fallo instanceof Error ? fallo.message : 'No se pudo aplicar. El tablero conserva su configuración anterior.')
      setConfirmarAplicacion(false)
    } finally { setOcupado(false) }
  }

  function restaurar() {
    const destino = consulta.ultimo?.configuracion ?? controlCitasInicial()
    setBase(consulta); setConfig(destino); setMetas(textosMetas(destino))
    setNota(''); setErrores({}); setErrorMes(''); setError(''); setConfirmarCarga(false); setMensaje('Se cargó el último borrador guardado.')
  }

  async function enviar(evento: FormEvent<HTMLFormElement>) {
    evento.preventDefault()
    if (ocupado || !cambios || desactualizada) return
    setMensaje(''); setError('')
    const fallos: Partial<Record<CampoMeta, string>> = {}
    for (const campo of CAMPOS_META) {
      const valor = numeroControlCitas(metas[campo.clave])
      const minimo = campo.clave === 'citas_por_lead' ? 0.01 : 1
      if (valor === null || valor < minimo || valor > campo.maximo) {
        fallos[campo.clave] = `Escribe un valor entre ${numero(minimo)} y ${campo.maximo}, con hasta dos decimales.`
      }
    }
    setErrores(fallos)
    const primerFallo = CAMPOS_META.find(campo => fallos[campo.clave])
    if (primerFallo) { evento.currentTarget.querySelector<HTMLInputElement>(`#control-${primerFallo.clave}`)?.focus(); return }
    if (!v.safeParse(MesControlCitasSchema, config.mes_inicio).success) {
      setErrorMes('Escribe un mes válido, por ejemplo 2026-09, o deja el campo vacío.')
      if (reglasRef.current) reglasRef.current.open = true
      evento.currentTarget.querySelector<HTMLInputElement>('#control-mes')?.focus()
      return
    }
    setErrorMes('')
    if (!valida.success || nota.trim().length > 500) { setError('Revisa el mes y los valores de la configuración.'); return }
    setOcupado(true)
    guardarRef.current?.focus()
    try {
      const guardada = await guardar({ versionEsperada: base.version_actual, configuracion: valida.output, nota: nota.trim() })
      setBase(guardada); setConfig(guardada.ultimo!.configuracion); setMetas(textosMetas(guardada.ultimo!.configuracion)); setNota('')
      setMensaje(practica ? 'Borrador guardado en esta vista de prueba.' : 'Borrador guardado. Todavía no está aplicado al tablero de Citas.')
    } catch (fallo) {
      setError(fallo instanceof Error ? fallo.message : 'No se pudo guardar. Tu borrador sigue en el editor.')
    } finally { setOcupado(false) }
  }

  return (
    <form onSubmit={evento => void enviar(evento)} className="space-y-4" noValidate aria-label="Configuración de Citas">
      <Card>
        <CardContent className="space-y-5 p-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-sm font-bold text-primary">Metas de gestión</h2>
              <p className="mt-1 text-xs text-muted-foreground">Para todos los analistas. Puedes completar las reglas por etapas.</p>
            </div>
            <span className="text-xs text-muted-foreground">{aplicada ? `Aplicada desde ${aplicada.mes_inicio}` : `Borrador ${base.version_actual > 0 ? `v${base.version_actual}` : 'nuevo'}`}</span>
          </div>
          <div className="grid gap-4 md:grid-cols-3">
            {CAMPOS_META.map(campo => (
              <div key={campo.clave} className="space-y-1.5">
                <Label htmlFor={`control-${campo.clave}`}>{campo.etiqueta}</Label>
                <Input id={`control-${campo.clave}`} inputMode="decimal" value={metas[campo.clave]}
                  onChange={e => setMetas({ ...metas, [campo.clave]: e.target.value })} disabled={ocupado}
                  aria-invalid={Boolean(errores[campo.clave])} aria-describedby={`ayuda-${campo.clave}`} className="h-11 text-base font-semibold tabular-nums" />
                <p id={`ayuda-${campo.clave}`} className={`text-xs ${errores[campo.clave] ? 'text-destructive' : 'text-muted-foreground'}`}>
                  {errores[campo.clave] ?? campo.ayuda}
                </p>
              </div>
            ))}
          </div>
          <div className="border-t border-border pt-4">
            <h3 className="text-sm font-bold text-primary">Leads que cuentan</h3>
            <p className="mt-1 text-xs text-muted-foreground">Todos los asignados durante el mes, incluso si todavía no tienen cita.</p>
            <label className="mt-2 flex min-h-11 cursor-pointer items-center gap-3 text-sm">
              <input type="checkbox" checked={config.excluir_manuales_base} disabled={ocupado}
                onChange={e => setConfig({ ...config, excluir_manuales_base: e.target.checked })}
                className="size-4 shrink-0 accent-accent focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring" />
              Excluir los que el propio analista registra manualmente
            </label>
          </div>
          <div className="rounded-lg bg-muted/40 p-4" role="group" aria-label="Ejemplo de la meta de citas">
            <p className="text-xs font-semibold text-primary">Ejemplo con 100 leads asignados, de los cuales 20 son de registro manual</p>
            <p className="mt-2 text-sm tabular-nums">
              {ejemplo ? <><strong>{ejemplo.leadsBase}</strong> leads que cuentan <span aria-hidden> → </span><strong>{numero(ejemplo.citas)}</strong> citas como meta interna</> : 'Introduce metas válidas para ver el ejemplo.'}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">Las metas de cantidad se redondean hacia arriba en este ejemplo.</p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-5">
          <details ref={reglasRef}>
            <summary className="cursor-pointer rounded text-sm font-bold text-primary focus-visible:outline-2 focus-visible:outline-ring">
              Reglas de avance <span className="ml-2 font-normal text-muted-foreground">{pendientes.length ? `${pendientes.length} por definir` : 'Completas'}</span>
            </summary>
            <div className="mt-5 grid gap-5 md:grid-cols-2">
              {REGLAS_CONTROL_CITAS.map(clave => {
                const regla = OPCIONES_CONTROL_CITAS[clave]
                return <div key={clave} className="space-y-1.5">
                  <Label htmlFor={`regla-${clave}`}>{regla.etiqueta}</Label>
                  <Select id={`regla-${clave}`} value={config[clave] ?? ''} disabled={ocupado} aria-describedby={`ayuda-${clave}`}
                    onChange={e => setConfig({ ...config, [clave]: e.target.value || null })} className="h-11">
                    <option value="">Por definir</option>
                    {Object.entries(regla.opciones).map(([valor, etiqueta]) => <option key={valor} value={valor}>{etiqueta}</option>)}
                  </Select>
                  <p id={`ayuda-${clave}`} className="text-xs text-muted-foreground">{regla.ayuda}</p>
                </div>
              })}
              <div className="space-y-1.5">
                <Label htmlFor="control-mes">Mes de inicio previsto</Label>
                <Input id="control-mes" type="month" min="2000-01" max="2099-12" value={config.mes_inicio ?? ''}
                  onChange={e => setConfig({ ...config, mes_inicio: e.target.value || null })} disabled={ocupado} className="h-11"
                  aria-invalid={Boolean(errorMes)} aria-describedby="control-mes-ayuda" />
                <p id="control-mes-ayuda" className={`text-xs ${errorMes ? 'text-destructive' : 'text-muted-foreground'}`}>
                  {errorMes || 'Se conserva como parte del borrador; guardar no activa las reglas.'}
                </p>
              </div>
            </div>
            <p className="mt-5 rounded-lg bg-muted/40 p-3 text-xs leading-relaxed text-muted-foreground">
              Un depósito se acredita cuando el lead se convierte en cliente. Cada persona cuenta una sola vez, aunque tenga varias citas.
            </p>
          </details>
        </CardContent>
      </Card>

      <div className="space-y-3">
        <div className="space-y-1.5">
          <Label htmlFor="control-nota">Nota del cambio (opcional)</Label>
          <Input id="control-nota" value={nota} onChange={e => setNota(e.target.value)} maxLength={500} disabled={ocupado}
            placeholder="Por qué ajustas estas reglas" />
        </div>
        {desactualizada && <p className="text-sm text-warning-text" role="alert">Hay una versión más reciente. Tu edición sigue aquí. Carga el último borrador para revisarla.</p>}
        {error && <p className="text-sm text-destructive" role="alert">{error}</p>}
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-xs text-muted-foreground" role="status">{mensaje || (cambios ? 'Cambios sin guardar. El tablero conserva su configuración actual.' : aplicada ? `Versión aplicada desde ${aplicada.mes_inicio}.` : 'Borrador guardado; pendiente de aplicación al tablero.')}</p>
          <div className="flex flex-wrap gap-2">
            <Button type="button" variant="outline" onClick={() => edicionCambiada ? setConfirmarCarga(true) : restaurar()} disabled={ocupado}><RotateCcw aria-hidden /> Cargar último borrador</Button>
            <Button ref={guardarRef} type="submit" aria-disabled={ocupado || !cambios || desactualizada} className="aria-disabled:opacity-50"><Save aria-hidden /> {ocupado ? 'Guardando…' : 'Guardar borrador'}</Button>
            {aplicar && consulta.aplicaciones && <Button type="button" variant="accent" disabled={ocupado || !puedeAplicar} onClick={() => setConfirmarAplicacion(true)}>Aplicar al tablero</Button>}
          </div>
        </div>
      </div>
      <Dialog open={confirmarCarga} onClose={() => setConfirmarCarga(false)} ariaLabel="Reemplazar la edición actual">
        <DialogHeader>
          <DialogTitle>Cargar el último borrador</DialogTitle>
          <DialogDescription>Se descartarán los cambios que todavía no guardaste en este formulario.</DialogDescription>
        </DialogHeader>
        <DialogBody><p className="text-sm">Se cargará {consulta.version_actual ? `la versión ${consulta.version_actual}` : 'la configuración inicial'}. Puedes cancelar para conservar tu edición.</p></DialogBody>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => setConfirmarCarga(false)}>Conservar mi edición</Button>
          <Button type="button" onClick={restaurar}>Descartar cambios y cargar</Button>
        </DialogFooter>
      </Dialog>
      <Dialog open={confirmarAplicacion} onClose={() => { if (!ocupado) setConfirmarAplicacion(false) }} ariaLabel="Aplicar configuración de Citas">
        <DialogHeader><DialogTitle>Aplicar versión {base.version_actual}</DialogTitle><DialogDescription>Estas reglas se usarán desde {config.mes_inicio}. Los meses anteriores conservarán su configuración.</DialogDescription></DialogHeader>
        <DialogBody><p className="text-sm">Meta interna: {textoNumeroControlCitas(config.citas_por_lead)} citas por lead. Entrevistas: {config.entrevistas_porcentaje}%. Depósitos: {config.depositos_porcentaje}%. El cambio quedará registrado en el historial.</p></DialogBody>
        <DialogFooter><Button type="button" variant="outline" disabled={ocupado} onClick={() => setConfirmarAplicacion(false)}>Cancelar</Button><Button type="button" disabled={ocupado} onClick={() => void aplicarVersion()}>{ocupado ? 'Aplicando…' : 'Confirmar aplicación'}</Button></DialogFooter>
      </Dialog>
    </form>
  )
}
