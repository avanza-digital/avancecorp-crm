// Corrección de contrato — espejo del "Corregir" del portal (analista.js:
// abrirModalContratoCorregir + guardarContrato). Reglas que NO se negocian:
//  - Ventana de 5 h: la decide el SERVIDOR (la RPC revalida creado_por → 5 h →
//    cartera y su rechazo llega como P0001); aquí lib/ventana es solo cortesía.
//  - TRAMPA 1: p_contrato SIEMPRE lleva notas_internas (si la clave falta, el
//    servidor las BORRA) → se precargan del contrato y viajan aunque sean null.
//  - TRAMPA 2: 'titulares' presente REEMPLAZA el set completo → se cargan los
//    actuales ANTES de habilitar el guardado; si su carga falló, la clave se
//    OMITE (ausente = el servidor no los toca) y se avisa.
//  - N° de contrato: prefijo FIJO '2026-01-' + 6 dígitos OBLIGATORIOS.
//  - El cronograma se REGENERA con lib/cronograma (mismo generador del preview);
//    el servidor conserva las cuotas ya pagadas.
// Se monta DENTRO de <Dialog> (mismo patrón que ContratoNuevo).
import { useEffect, useMemo, useState } from 'react'
import { FileSignature, Plus, RotateCcw, Save, X } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { ERROR_MONTO, parseMonto } from '@/lib/numero'
import { fmtFecha, money, type Moneda } from '@/lib/format'
import {
  actualizarContrato,
  CrmApiError,
  obtenerTitulares,
  type ActualizarContratoInput,
} from '@/data/crm-api'
import {
  generarCronograma,
  parseDateLocal,
  vencimientoDesdePlazo,
  type CategoriaContrato,
  type ModalidadContrato,
  type TipoInteres,
} from '@/lib/cronograma'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento } from '@/lib/documento'
import { normalizarTitulares } from '@/lib/titulares'
import { useVentana } from '@/lib/ventana'
import { MAX_TITULARES, type ContratoRow } from '@/lib/clientes-tipos'

const CATEGORIAS: { k: CategoriaContrato; label: string }[] = [
  { k: 'nuevo', label: 'Nuevo' },
  { k: 'renovacion', label: 'Renovación' },
  { k: 'upgrade', label: 'Upgrade' },
]
const MODALIDADES: { k: ModalidadContrato; label: string }[] = [
  { k: 'mensual', label: 'Mensual' },
  { k: 'trimestral', label: 'Trimestral' },
  { k: 'semestral', label: 'Semestral' },
  { k: 'anual', label: 'Anual' },
]
// Prefijo fijo del N° de contrato (espejo de PREFIJO_CONTRATO de analista.js):
// el asesor solo escribe los 6 dígitos, el prefijo es imposible de borrar.
const PREFIJO_CONTRATO = '2026-01-'
const RE_SEIS_DIGITOS = /^\d{6}$/
// Presets del select de plazo del portal; los años exactos sirven para compuesto.
const PLAZOS: { meses: number; label: string; anioExacto: boolean }[] = [
  { meses: 6, label: '6 meses', anioExacto: false },
  { meses: 12, label: '1 año', anioExacto: true },
  { meses: 24, label: '2 años', anioExacto: true },
  { meses: 36, label: '3 años', anioExacto: true },
  { meses: 48, label: '4 años', anioExacto: true },
  { meses: 60, label: '5 años', anioExacto: true },
]

// Meses calendario entre dos fechas YYYY-MM-DD (espejo de mesesEntre de
// analista.js) — deriva el preset del select sin tocar el vencimiento real.
function mesesEntre(inicio: string, fin: string): number {
  const a = parseDateLocal(inicio)
  const b = parseDateLocal(fin)
  return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth())
}

/** Fila cruda del editor de co-titulares (se normaliza recién al guardar). */
interface FilaTitular {
  nombre: string
  tipo: TipoDocumento
  documento: string
}

export interface ContratoCorregirProps {
  contrato: ContratoRow
  onGuardado: () => void
  onCerrar: () => void
}

export function ContratoCorregir({ contrato, onGuardado, onCerrar }: ContratoCorregirProps) {
  const ventana = useVentana(contrato.creado_en)

  // Solo los 6 dígitos del formato nuevo; una numeración vieja (AC-2026-XXXX)
  // deja el casillero vacío y obliga a asignar el formato actual al guardar.
  const numeroInicial = new RegExp(`^${PREFIJO_CONTRATO}(\\d{6})$`).exec(contrato.numero_contrato)?.[1] ?? ''
  const esNumeracionVieja = numeroInicial === ''

  const [numero, setNumero] = useState(numeroInicial)
  const [categoria, setCategoria] = useState<CategoriaContrato | ''>(contrato.categoria ?? '')
  const [tipoInteres, setTipoInteres] = useState<TipoInteres>(contrato.tipo_interes)
  const [modalidad, setModalidad] = useState<ModalidadContrato>(contrato.modalidad)
  const [capital, setCapital] = useState(String(contrato.capital))
  const [moneda, setMoneda] = useState<Moneda>(contrato.moneda)
  const [tasa, setTasa] = useState(String(contrato.tasa_anual))
  const [fechaInicio, setFechaInicio] = useState(contrato.fecha_inicio)
  const mesesIniciales = mesesEntre(contrato.fecha_inicio, contrato.fecha_vencimiento)
  const [plazo, setPlazo] = useState(
    PLAZOS.some((p) => p.meses === mesesIniciales) ? String(mesesIniciales) : '12',
  )
  // Se PRESERVA el vencimiento REAL al abrir (espejo del portal): recalcularlo
  // de un plazo no-preset lo pisaría sin querer. Solo cambia si el usuario toca
  // inicio o plazo.
  const [venc, setVenc] = useState(contrato.fecha_vencimiento)
  const [notas, setNotas] = useState(contrato.notas_internas ?? '')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Co-titulares ACTUALES cargados antes de habilitar el guardado (la trampa del
  // reemplazo). 'error' NO bloquea el resto de la corrección: se omite la clave.
  const [titulares, setTitulares] = useState<FilaTitular[]>([])
  const [estadoTitulares, setEstadoTitulares] = useState<'cargando' | 'ok' | 'error'>('cargando')
  const [reintentoTitulares, setReintentoTitulares] = useState(0)

  useEffect(() => {
    const ctrl = new AbortController()
    setEstadoTitulares('cargando')
    void (async () => {
      try {
        const filas = await obtenerTitulares(contrato.id, ctrl.signal)
        if (ctrl.signal.aborted) return
        setTitulares(filas.map((t) => ({ nombre: t.nombre_completo, tipo: t.tipo_documento, documento: t.documento })))
        setEstadoTitulares('ok')
      } catch {
        // Sin los actuales NO se puede mandar la clave (mandar [] los borraría):
        // el guardado seguirá disponible pero omitiendo 'titulares' (no tocar).
        if (!ctrl.signal.aborted) setEstadoTitulares('error')
      }
    })()
    return () => ctrl.abort()
  }, [contrato.id, reintentoTitulares])

  const esCompuesto = tipoInteres === 'compuesto'
  // parseMonto rechaza separadores de miles ('125,000' NO es 125) — ver lib/numero.
  const capitalNum = parseMonto(capital) ?? NaN
  const tasaNum = parseMonto(tasa) ?? NaN

  const cambiarInicio = (v: string) => {
    setFechaInicio(v)
    if (v) setVenc(vencimientoDesdePlazo(v, parseInt(plazo, 10)))
  }
  const cambiarPlazo = (v: string) => {
    setPlazo(v)
    if (fechaInicio) setVenc(vencimientoDesdePlazo(fechaInicio, parseInt(v, 10)))
  }

  // Mismo generador del preview de ContratoNuevo: lo que se ve es lo que viaja.
  const cronograma = useMemo(() => {
    if (
      !Number.isFinite(capitalNum) || capitalNum <= 0 ||
      !Number.isFinite(tasaNum) || tasaNum <= 0 || tasaNum > 50 ||
      !fechaInicio || !venc
    ) {
      return []
    }
    return generarCronograma(capitalNum, tasaNum, fechaInicio, venc, modalidad, tipoInteres)
  }, [capitalNum, tasaNum, fechaInicio, venc, modalidad, tipoInteres])

  const totalCronograma = cronograma.reduce((a, c) => a + c.monto_programado, 0)

  // ── Editor de co-titulares ────────────────────────────────────────────────
  const setFila = (i: number, patch: Partial<FilaTitular>) =>
    setTitulares((filas) => filas.map((f, j) => (j === i ? { ...f, ...patch } : f)))
  const agregarFila = () => setTitulares((filas) => [...filas, { nombre: '', tipo: 'DNI', documento: '' }])
  const quitarFila = (i: number) => setTitulares((filas) => filas.filter((_, j) => j !== i))

  const guardar = async () => {
    if (enviando) return // guard anti doble-submit (además del disabled del botón)
    setError(null)
    // Validaciones espejo de guardarContrato de analista.js (mensajes tal cual).
    if (!RE_SEIS_DIGITOS.test(numero)) {
      setError('El N° de contrato debe tener exactamente 6 dígitos (después de 2026-01-).')
      return
    }
    if (capital.trim() && parseMonto(capital) == null) {
      setError(ERROR_MONTO)
      return
    }
    if (!Number.isFinite(capitalNum) || !capitalNum || !fechaInicio || !venc) {
      setError('Completa capital, fecha de inicio y plazo.')
      return
    }
    if (!Number.isFinite(tasaNum) || tasaNum <= 0 || tasaNum > 50) {
      setError('La tasa anual debe estar entre 0 y 50%.')
      return
    }
    if (capitalNum < 100) {
      setError('El capital debe ser de al menos 100.')
      return
    }
    if (!categoria) {
      setError('Selecciona la categoría de la inversión (Nuevo, Renovación o Upgrade).')
      return
    }
    if (cronograma.length === 0) {
      setError(
        esCompuesto
          ? 'El interés compuesto requiere un plazo en años exactos (12, 24, 36, 48 o 60 meses).'
          : 'Las fechas/modalidad no permiten generar un cronograma.',
      )
      return
    }
    // Co-titulares: solo si sus valores ACTUALES cargaron (presente = reemplazar).
    // La normalización es la de lib/titulares (misma fuente que ContratoNuevo:
    // filas vacías se ignoran, error con posición, duplicados rechazados, máx 5).
    const tit = estadoTitulares === 'ok'
      ? normalizarTitulares(titulares.map((t) => ({
          nombre_completo: t.nombre,
          tipo_documento: t.tipo,
          documento: t.documento,
        })))
      : null
    if (tit && !tit.ok) {
      setError(tit.error)
      return
    }

    const input: ActualizarContratoInput = {
      capital: capitalNum,
      moneda,
      tasa_anual: tasaNum,
      // En compuesto la modalidad no aplica (capitaliza anual) — regla del portal.
      modalidad: esCompuesto ? 'anual' : modalidad,
      tipo_interes: tipoInteres,
      categoria,
      fecha_inicio: fechaInicio,
      fecha_vencimiento: venc,
      numero_contrato: PREFIJO_CONTRATO + numero,
      // TRAMPA 1: la clave viaja SIEMPRE (aunque sea null) o el servidor la borra.
      notas_internas: notas.trim() || null,
    }
    if (tit?.ok) input.titulares = tit.titulares

    setEnviando(true)
    try {
      await actualizarContrato(contrato.id, input, cronograma)
      // Toast honesto: mismo copy del portal (el servidor conservó las pagadas).
      toast.success('Contrato corregido y cronograma regenerado.')
      onGuardado()
    } catch (e) {
      // Los mensajes del servidor (RPC) ya vienen en español y claros — ventana
      // vencida, fuera de cartera, cuotas pagadas — y se muestran TAL CUAL.
      setError(e instanceof CrmApiError ? e.message : 'No se pudo guardar el contrato.')
    } finally {
      setEnviando(false)
    }
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <FileSignature className="size-4 text-primary" aria-hidden />
          Corregir contrato {contrato.numero_contrato}
        </DialogTitle>
        <DialogDescription>
          Cliente: <b className="text-foreground">{contrato.cliente_nombre ?? '—'}</b> · Ventana de corrección:{' '}
          {/* Sin verde en el sistema ("positivo" = azul): vigente accent, vencida destructive. */}
          <span className={`font-semibold tabular-nums ${ventana.vigente ? 'text-accent' : 'text-destructive'}`}>
            {ventana.texto}
          </span>
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="max-h-[65vh] space-y-3 overflow-y-auto">
        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-numero">N° de contrato</Label>
            <div className="flex items-center gap-1.5">
              <span className="flex h-9 shrink-0 items-center rounded-lg border border-input bg-muted px-2.5 text-sm font-semibold tabular-nums text-muted-foreground">
                {PREFIJO_CONTRATO}
              </span>
              <Input
                id="cc-numero"
                inputMode="numeric"
                value={numero}
                // Solo dígitos, máx 6 — bloquea letras/espacios al teclear o pegar.
                onChange={(e) => setNumero(e.target.value.replace(/\D/g, '').slice(0, 6))}
                placeholder="000123"
                disabled={enviando}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cc-categoria">Categoría</Label>
            <Select
              id="cc-categoria"
              value={categoria}
              onChange={(e) => setCategoria(e.target.value as CategoriaContrato | '')}
              disabled={enviando}
            >
              <option value="">— Seleccionar —</option>
              {CATEGORIAS.map((c) => (
                <option key={c.k} value={c.k}>{c.label}</option>
              ))}
            </Select>
          </div>
        </div>
        {esNumeracionVieja && (
          <p className="text-[11px] text-warning">
            Este contrato tiene la numeración antigua ({contrato.numero_contrato}): asígnale los 6
            dígitos del formato actual al guardar.
          </p>
        )}

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-tipo">Tipo de interés</Label>
            <Select
              id="cc-tipo"
              value={tipoInteres}
              onChange={(e) => setTipoInteres(e.target.value as TipoInteres)}
              disabled={enviando}
            >
              <option value="simple">Simple</option>
              <option value="compuesto">Compuesto</option>
            </Select>
          </div>
          {!esCompuesto && (
            <div className="space-y-1.5">
              <Label htmlFor="cc-modalidad">Modalidad de pago</Label>
              <Select
                id="cc-modalidad"
                value={modalidad}
                onChange={(e) => setModalidad(e.target.value as ModalidadContrato)}
                disabled={enviando}
              >
                {MODALIDADES.map((m) => (
                  <option key={m.k} value={m.k}>{m.label}</option>
                ))}
              </Select>
            </div>
          )}
        </div>

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-capital">Capital</Label>
            <Input
              id="cc-capital"
              inputMode="decimal"
              value={capital}
              onChange={(e) => setCapital(e.target.value)}
              disabled={enviando}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cc-moneda">Moneda</Label>
            <Select
              id="cc-moneda"
              value={moneda}
              onChange={(e) => setMoneda(e.target.value as Moneda)}
              disabled={enviando}
            >
              <option value="PEN">Soles (PEN)</option>
              <option value="USD">Dólares (USD)</option>
            </Select>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-tasa">Tasa anual (%)</Label>
            <Input
              id="cc-tasa"
              inputMode="decimal"
              value={tasa}
              onChange={(e) => setTasa(e.target.value)}
              disabled={enviando}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cc-inicio">Fecha de inicio</Label>
            <Input
              id="cc-inicio"
              type="date"
              value={fechaInicio}
              onChange={(e) => cambiarInicio(e.target.value)}
              disabled={enviando}
            />
          </div>
        </div>

        <div className="grid grid-cols-2 items-end gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-plazo">Plazo</Label>
            <Select
              id="cc-plazo"
              value={plazo}
              onChange={(e) => cambiarPlazo(e.target.value)}
              disabled={enviando}
            >
              {PLAZOS.map((p) => (
                <option key={p.meses} value={String(p.meses)} disabled={esCompuesto && !p.anioExacto}>
                  {p.label}
                </option>
              ))}
            </Select>
          </div>
          <p className="pb-2 text-[11px] text-muted-foreground">
            Vence el <b className="text-foreground">{fmtFecha(venc)}</b>
            {/* El vencimiento REAL se preserva al abrir; cambiar inicio/plazo lo recalcula. */}
          </p>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="cc-notas">Notas internas</Label>
          <Textarea
            id="cc-notas"
            value={notas}
            maxLength={500}
            onChange={(e) => setNotas(e.target.value)}
            placeholder="—"
            disabled={enviando}
          />
        </div>

        {/* ── Co-titulares (cuentas mancomunadas, máx 5) ─────────────────────── */}
        <div className="space-y-2 rounded-xl border border-border bg-muted/40 p-3">
          <div className="flex items-center justify-between gap-2">
            <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
              Co-titulares (opcional)
            </p>
            {estadoTitulares === 'ok' && (
              <Button
                type="button"
                variant="ghost"
                size="xs"
                onClick={agregarFila}
                disabled={enviando || titulares.length >= MAX_TITULARES}
              >
                <Plus aria-hidden /> Agregar co-titular
              </Button>
            )}
          </div>
          {estadoTitulares === 'cargando' && (
            <p className="text-xs text-muted-foreground" aria-busy>
              Cargando los co-titulares actuales…
            </p>
          )}
          {estadoTitulares === 'error' && (
            <div className="space-y-2">
              <p className="text-xs font-semibold text-destructive">
                No se pudieron cargar los co-titulares actuales. Se conservarán tal cual están en el
                servidor; para editarlos, reintenta la carga.
              </p>
              <Button variant="outline" size="xs" onClick={() => setReintentoTitulares((n) => n + 1)}>
                <RotateCcw aria-hidden /> Reintentar
              </Button>
            </div>
          )}
          {estadoTitulares === 'ok' && titulares.length === 0 && (
            <p className="text-xs text-muted-foreground">Sin co-titulares.</p>
          )}
          {estadoTitulares === 'ok' &&
            titulares.map((t, i) => (
              // Índice como key: las filas solo se reordenan al quitar y no llevan
              // estado propio fuera del array (el editor del portal hace lo mismo).
              <div key={i} className="grid grid-cols-[1fr_auto] gap-1.5 sm:grid-cols-[1.4fr_0.9fr_1fr_auto]">
                <Input
                  aria-label={`Nombre del co-titular ${i + 1}`}
                  value={t.nombre}
                  onChange={(e) => setFila(i, { nombre: e.target.value })}
                  placeholder="Nombre completo"
                  disabled={enviando}
                />
                <Select
                  aria-label={`Tipo de documento del co-titular ${i + 1}`}
                  value={t.tipo}
                  onChange={(e) => setFila(i, { tipo: e.target.value as TipoDocumento })}
                  disabled={enviando}
                >
                  {TIPOS_DOCUMENTO_K.map((k) => (
                    <option key={k} value={k}>{TIPOS_DOCUMENTO[k].etiqueta}</option>
                  ))}
                </Select>
                <Input
                  aria-label={`Documento del co-titular ${i + 1}`}
                  inputMode={TIPOS_DOCUMENTO[t.tipo].inputmode}
                  // Tope ÚNICO de 12 (regla de lib/documento): un tope por tipo
                  // truncaría EN SILENCIO un CE pegado en modo DNI.
                  maxLength={12}
                  value={t.documento}
                  onChange={(e) => setFila(i, { documento: e.target.value })}
                  placeholder={TIPOS_DOCUMENTO[t.tipo].placeholder}
                  disabled={enviando}
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  aria-label={`Quitar co-titular ${i + 1}`}
                  onClick={() => quitarFila(i)}
                  disabled={enviando}
                >
                  <X aria-hidden />
                </Button>
              </div>
            ))}
        </div>

        {/* ── Vista previa del cronograma que se REGENERARÁ al guardar ───────── */}
        <div className="rounded-xl border border-border bg-muted/40 p-3">
          <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
            Cronograma (se regenera al guardar — las cuotas ya pagadas se conservan)
          </p>
          {cronograma.length === 0 ? (
            <p className="mt-1 text-xs text-muted-foreground">
              {esCompuesto
                ? 'El interés compuesto requiere un plazo en años exactos (12, 24, 36, 48 o 60 meses).'
                : 'Completa capital, tasa y fechas para previsualizar el cronograma.'}
            </p>
          ) : (
            <div className="mt-1.5 space-y-0.5 text-xs">
              <p className="text-foreground">
                <b>{cronograma.length}</b> {cronograma.length === 1 ? 'cuota' : 'cuotas'} · total programado{' '}
                <b className="tabular-nums text-primary">{money(totalCronograma, moneda)}</b>
              </p>
              <p className="text-muted-foreground">
                Primera: {fmtFecha(cronograma[0]!.fecha_programada)} · Última:{' '}
                {fmtFecha(cronograma[cronograma.length - 1]!.fecha_programada)}
              </p>
            </div>
          )}
        </div>

        {error && (
          <p role="alert" className="text-xs font-semibold text-destructive">
            {error}
          </p>
        )}
      </DialogBody>
      <DialogFooter className="justify-between">
        <Button variant="ghost" size="sm" onClick={onCerrar} disabled={enviando}>
          Cancelar
        </Button>
        <Button
          size="sm"
          onClick={guardar}
          // El disabled por ventana es cortesía visual: la autoridad es la RPC
          // (P0001). Mientras cargan los co-titulares NO se puede guardar — un
          // guardado muy rápido con el editor vacío los borraría (lección del portal).
          disabled={enviando || estadoTitulares === 'cargando' || !ventana.vigente}
          title={ventana.vigente ? undefined : 'La ventana de corrección de 5 horas ya venció'}
        >
          <Save aria-hidden /> {enviando ? 'Guardando…' : 'Guardar corrección'}
        </Button>
      </DialogFooter>
    </>
  )
}
