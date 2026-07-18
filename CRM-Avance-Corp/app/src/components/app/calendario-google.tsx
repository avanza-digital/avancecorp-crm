// Tarjeta "Mi calendario de Google" (Configuración): la suscripción ICS de la
// agenda en tres pasos. El miembro genera su enlace secreto UNA vez, lo pega en
// Google Calendar ("Desde una URL") y sus tareas pendientes aparecen solas.
//
// API inyectable (props con default a crm-api): el test ejercita los estados
// sin red, igual que el patrón de DistribucionLeadsGerencia (props-driven).
import { useCallback, useEffect, useState } from 'react'
import { CalendarPlus, Check, Copy, RefreshCw } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { SectionHead } from '@/components/common/section-head'
import { CONFIG } from '@/lib/config'
import { PASOS_GOOGLE_CALENDAR, urlFeedIcs } from '@/lib/agenda-ics'
import { crearTokenIcs, mensajeDeError, obtenerTokenIcs, rotarTokenIcs } from '@/data/crm-api'

export interface CalendarioGoogleApi {
  obtener: (perfilId: string) => Promise<string | null>
  crear: (perfilId: string) => Promise<string>
  rotar: (perfilId: string) => Promise<string>
}

const API_REAL: CalendarioGoogleApi = {
  obtener: obtenerTokenIcs,
  crear: crearTokenIcs,
  rotar: rotarTokenIcs,
}

export interface CalendarioGoogleProps {
  /** Perfil del miembro autenticado (null = sin sesión utilizable). */
  perfilId: string | null
  /** En demo no hay fila real que crear: la tarjeta solo se anuncia. */
  demo: boolean
  api?: CalendarioGoogleApi
  supabaseUrl?: string
}

type Fase = 'cargando' | 'sin_token' | 'con_token' | 'error'

export function CalendarioGoogle({
  perfilId,
  demo,
  api = API_REAL,
  supabaseUrl = CONFIG.SUPABASE_URL ?? '',
}: CalendarioGoogleProps) {
  const [fase, setFase] = useState<Fase>('cargando')
  const [token, setToken] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [ocupado, setOcupado] = useState(false)
  const [copiado, setCopiado] = useState(false)

  const usable = !demo && !!perfilId && !!supabaseUrl

  useEffect(() => {
    if (!usable || !perfilId) return
    let vivo = true
    api
      .obtener(perfilId)
      .then((t) => {
        if (!vivo) return
        setToken(t)
        setFase(t ? 'con_token' : 'sin_token')
      })
      .catch((e: unknown) => {
        if (!vivo) return
        setError(mensajeDeError(e, 'No se pudo consultar tu calendario.'))
        setFase('error')
      })
    return () => {
      vivo = false
    }
  }, [usable, perfilId, api])

  const conectar = useCallback(async () => {
    if (!perfilId) return
    setOcupado(true)
    setError(null)
    try {
      const t = await api.crear(perfilId)
      setToken(t)
      setFase('con_token')
    } catch (e: unknown) {
      setError(mensajeDeError(e, 'No se pudo generar tu enlace.'))
    } finally {
      setOcupado(false)
    }
  }, [api, perfilId])

  const rotar = useCallback(async () => {
    if (!perfilId) return
    setOcupado(true)
    setError(null)
    try {
      const t = await api.rotar(perfilId)
      setToken(t)
      setCopiado(false)
    } catch (e: unknown) {
      setError(mensajeDeError(e, 'No se pudo renovar tu enlace.'))
    } finally {
      setOcupado(false)
    }
  }, [api, perfilId])

  const url = token ? urlFeedIcs(supabaseUrl, token) : null

  const copiar = useCallback(async () => {
    if (!url) return
    try {
      await navigator.clipboard.writeText(url)
      setCopiado(true)
      setTimeout(() => setCopiado(false), 2500)
    } catch {
      // Sin clipboard (permiso/navegador): el campo de abajo queda para copiar a mano.
    }
  }, [url])

  return (
    <Card className="ac-pop">
      <SectionHead
        icon={CalendarPlus}
        title="Mi calendario de Google"
        right={<Badge color="var(--accent)" variant="outline">Nuevo</Badge>}
      />
      <CardContent className="space-y-3 pt-0">
        <p className="text-xs text-muted-foreground">
          Conecta tu agenda del CRM con tu Google Calendar: tus tareas pendientes aparecen
          solas en tu celular (Google las refresca cada algunas horas).
        </p>

        {demo || !usable ? (
          <p className="text-xs font-semibold text-muted-foreground">
            Disponible al entrar con tu cuenta real del CRM.
          </p>
        ) : fase === 'cargando' ? (
          <p className="text-xs text-muted-foreground" role="status">Consultando tu calendario…</p>
        ) : (
          <>
            {fase !== 'con_token' && (
              <Button size="sm" onClick={conectar} disabled={ocupado}>
                <CalendarPlus className="size-4" />
                {ocupado ? 'Generando…' : 'Generar mi enlace secreto'}
              </Button>
            )}

            {url && (
              <div className="space-y-2.5">
                <div className="flex items-center gap-2">
                  <input
                    readOnly
                    value={url}
                    aria-label="Tu enlace secreto de calendario"
                    onFocus={(e) => e.currentTarget.select()}
                    className="min-w-0 flex-1 rounded-lg border border-border bg-muted/40 px-2.5 py-1.5 text-[11px] text-muted-foreground"
                  />
                  <Button size="sm" onClick={copiar} aria-label="Copiar enlace">
                    {copiado ? <Check className="size-4" /> : <Copy className="size-4" />}
                    {copiado ? 'Copiado' : 'Copiar'}
                  </Button>
                </div>

                <ol className="list-decimal space-y-1 pl-5 text-xs text-muted-foreground">
                  {PASOS_GOOGLE_CALENDAR.map((paso) => (
                    <li key={paso}>{paso}</li>
                  ))}
                </ol>

                <div className="flex items-center justify-between gap-2">
                  <p className="text-[11px] text-muted-foreground">
                    Es un enlace personal: no lo compartas. ¿Se filtró? Renuévalo y el anterior muere.
                  </p>
                  <Button
                    variant="ghost"
                    size="xs"
                    onClick={rotar}
                    disabled={ocupado}
                    className="shrink-0 text-muted-foreground hover:text-foreground"
                  >
                    <RefreshCw className="size-3.5" /> Renovar enlace
                  </Button>
                </div>
              </div>
            )}
          </>
        )}

        {error && (
          <p className="text-xs font-semibold text-warning" role="alert">{error}</p>
        )}
      </CardContent>
    </Card>
  )
}
