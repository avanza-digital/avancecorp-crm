import { useState, type FormEvent } from 'react'
import { AlertCircle, Eye, RefreshCw, ShieldCheck, TrendingUp, Users } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { DEMO_HABILITADO, HAY_SUPABASE } from '@/lib/config'
import { idCorrelacionCorto } from '@/lib/observabilidad'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { BrandLockup, BrandMark } from '@/components/app/brand'
import { ROL_LABEL, type Rol } from '@/lib/roles'

// Identidad demo que asume cada botón (espejo de DEMO_YO en lib/auth.tsx).
const DEMO_SUB: Record<Rol, string> = {
  vendedor: 'como VENDEDOR UNO',
  supervisor: 'como SUPERVISOR UNO — equipo de 2',
  gerencia: 'visión total',
  directorio: 'auditoría · solo lectura',
}

export function Login() {
  const { error: errorAuth, entrar, entrarDemo, reintentar } = useAuth()
  const [correo, setCorreo] = useState('')
  const [clave, setClave] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [cargando, setCargando] = useState(false)
  const [demoAbierto, setDemoAbierto] = useState(false)

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setError(null)
    setCargando(true)
    try {
      const resultado = await entrar(correo, clave)
      if (!resultado.ok) setError(resultado.error ?? 'No se pudo iniciar sesión')
    } finally {
      setCargando(false)
    }
  }

  return (
    <div className="relative z-10 flex min-h-svh">
      {/* Panel de marca (navy con aurora propia + logo real) */}
      <div className="relative hidden w-[46%] flex-col justify-between overflow-hidden p-10 text-white lg:flex"
        style={{ background: 'linear-gradient(160deg, #16264f 0%, #111e3d 45%, #0b1530 100%)' }}>
        {/* blooms sutiles internos */}
        <div className="pointer-events-none absolute -left-24 -top-24 size-96 rounded-full opacity-60 blur-3xl"
          style={{ background: 'radial-gradient(circle, rgba(37,99,235,0.35), transparent 60%)' }} />
        <div className="pointer-events-none absolute -bottom-28 -right-16 size-96 rounded-full opacity-50 blur-3xl"
          style={{ background: 'radial-gradient(circle, rgba(124,58,237,0.28), transparent 60%)' }} />

        <div className="relative">
          <BrandLockup tone="dark" size={44} subtitle="CRM Comercial" />
        </div>

        <div className="relative space-y-6">
          <div className="space-y-3">
            <h2 className="text-[2rem] font-extrabold leading-[1.15] tracking-tight">
              La cartera de inversiones,<br />bajo control.
            </h2>
            <p className="max-w-sm text-sm leading-relaxed text-white/70">
              Captación, seguimiento y renovaciones de contratos de Asociación en Participación —
              con la trazabilidad que exige una futura financiera regulada.
            </p>
          </div>
          <div className="grid max-w-md grid-cols-3 gap-3">
            {[
              { icon: TrendingUp, k: 'Pipeline', v: 'por etapa' },
              { icon: Users, k: 'Equipo', v: '4 niveles' },
              { icon: ShieldCheck, k: 'Privacidad', v: 'por rol' },
            ].map((f) => (
              <div key={f.k} className="rounded-xl bg-white/[0.06] p-3 ring-1 ring-white/10 backdrop-blur-sm">
                <f.icon className="mb-2 size-4 text-accent" />
                <p className="text-[13px] font-bold">{f.k}</p>
                <p className="text-[11px] text-white/55">{f.v}</p>
              </div>
            ))}
          </div>
        </div>

        <p className="relative text-[11px] text-white/40">Avance Corp S.A.C. · Grupo MasCapital</p>
      </div>

      {/* Formulario */}
      <div className="flex flex-1 items-center justify-center p-6">
        <div className="w-full max-w-sm space-y-6 ac-rise">
          <div className="lg:hidden">
            <BrandMark size={44} />
          </div>
          <div>
            <h1 className="text-2xl font-extrabold tracking-tight text-primary">Inicia sesión</h1>
            <p className="text-sm text-muted-foreground">Acceso para el equipo comercial y directorio.</p>
          </div>

          {errorAuth && (
            <div className="space-y-3 rounded-xl border border-destructive/20 bg-destructive/10 p-3" role="alert">
              <div className="flex items-start gap-2.5">
                <AlertCircle className="mt-0.5 size-4 shrink-0 text-destructive" aria-hidden />
                <div className="min-w-0 space-y-1">
                  <p className="text-sm font-semibold text-destructive">No pudimos verificar tu acceso</p>
                  <p className="text-xs text-foreground/80">{errorAuth}</p>
                  <p className="text-[10px] text-muted-foreground">
                    Código de diagnóstico: {idCorrelacionCorto()}
                  </p>
                </div>
              </div>
              <Button type="button" variant="outline" size="sm" className="w-full" onClick={reintentar}>
                <RefreshCw className="size-3.5" aria-hidden /> Reintentar verificación
              </Button>
            </div>
          )}

          <form onSubmit={onSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="correo">Correo</Label>
              <Input
                id="correo" type="email" autoComplete="username" required
                placeholder="tucorreo@avancecorp.pe"
                value={correo} onChange={(e) => setCorreo(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="clave">Contraseña</Label>
              <Input
                id="clave" type="password" autoComplete="current-password" required
                placeholder="••••••••"
                value={clave} onChange={(e) => setClave(e.target.value)}
              />
            </div>
            {error && (
              <p className="rounded-lg bg-destructive/10 px-3 py-2 text-xs font-medium text-destructive" role="alert">
                {error}
              </p>
            )}
            <Button type="submit" className="w-full" disabled={cargando || !HAY_SUPABASE}>
              {cargando ? 'Entrando…' : 'Entrar'}
            </Button>
            {!HAY_SUPABASE && (
              <p className="text-center text-[11px] text-muted-foreground">
                {DEMO_HABILITADO
                  ? 'El acceso con cuenta aún no está disponible aquí — explora con el modo demo.'
                  : 'El acceso con cuenta aún no está disponible aquí.'}
              </p>
            )}
          </form>

          {DEMO_HABILITADO && (
          <div className="border-t border-border pt-4">
            {!demoAbierto ? (
              <button
                type="button"
                onClick={() => setDemoAbierto(true)}
                className="mx-auto flex items-center gap-1.5 text-xs font-semibold text-accent hover:underline cursor-pointer"
              >
                <Eye className="size-3.5" /> Explorar en modo demo
              </button>
            ) : (
              <div className="space-y-2">
                <p className="text-center text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                  Ver el CRM como…
                </p>
                <div className="grid grid-cols-2 gap-2">
                  {(Object.keys(ROL_LABEL) as Rol[]).map((r) => (
                    <Button
                      key={r}
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => entrarDemo(r)}
                      className="h-auto flex-col items-center gap-0 py-2"
                    >
                      <span>{ROL_LABEL[r]}</span>
                      <span className="text-[10px] font-normal leading-tight text-muted-foreground">
                        {DEMO_SUB[r]}
                      </span>
                    </Button>
                  ))}
                </div>
              </div>
            )}
          </div>
          )}
        </div>
      </div>
    </div>
  )
}
