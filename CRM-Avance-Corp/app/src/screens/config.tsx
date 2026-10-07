import type { CSSProperties } from 'react'
import {
  Package, Target, Users, Clock, Settings, ChevronRight, Eye, RefreshCw, type LucideIcon,
  Percent, Smartphone,
} from 'lucide-react'
import { Card, CardContent, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { SectionHead } from '@/components/common/section-head'
import { CalendarioGoogle } from '@/components/app/calendario-google'
import { NotificacionesTasa } from '@/components/app/notificaciones-tasa'
import { ConfiguracionRespuestasTasa } from '@/components/app/respuestas-tasa'
import {
  useCatalogoUsuariosAdministrables,
  useConfiguracionMetas,
  useConfiguracionProductos,
  useConfiguracionSla,
} from '@/data/crm-config-queries'
import {
  administraSoloRolesCrm,
  can,
  ROL_LABEL,
  puedeAdministrarRolesCrm,
  puedeConfigurarCitas,
  puedeEscribir,
} from '@/lib/roles'
import { useAuth } from '@/lib/auth-context'
import { llamadasCelularHabilitadas } from '@/lib/config'
import { periodoLima } from '@/lib/objetivos'
import { hashDe, type VistaConfiguracion } from '@/lib/router'
import { minutosLegibles } from '@/lib/sla-versionado'
import { vistaPermitida } from '@/lib/vistas'

interface Seccion {
  icon: LucideIcon
  t: string
  d: string
  vista: VistaConfiguracion
  color: string
}
const SECCIONES: Seccion[] = [
  { icon: Users, t: 'Usuarios y jerarquía', d: 'Altas, membresía CRM, roles y estructura comercial', vista: 'config-usuarios', color: 'var(--chart-2)' },
  { icon: Package, t: 'Productos de inversión', d: 'Catálogo versionado, condiciones, montos y tasas', vista: 'config-productos', color: 'var(--chart-1)' },
  { icon: Target, t: 'Metas', d: 'Objetivos por analista, categoría, moneda y mes', vista: 'config-metas', color: 'var(--chart-4)' },
  { icon: Clock, t: 'Tiempos de atención', d: 'Primera gestión, contacto y máximos por etapa', vista: 'config-sla', color: 'var(--chart-3)' },
  { icon: Clock, t: 'Gestión Diaria', d: 'Cortes de llamadas, contacto y cambios desde una jornada futura', vista: 'config-gestion-diaria', color: 'var(--chart-2)' },
  { icon: Percent, t: 'Política de rentabilidad', d: 'Tasa base, herencia en renovación y upgrade, excepciones de Gerencia', vista: 'config-rentabilidad', color: 'var(--chart-5)' },
  { icon: Target, t: 'Control de Citas', d: 'Metas, leads que cuentan y reglas de avance', vista: 'config-citas', color: 'var(--accent)' },
  { icon: Smartphone, t: 'Celulares', d: 'Asignar, rotar y cerrar los celulares que capturan llamadas, y ver si están vivos', vista: 'config-celulares', color: 'var(--chart-4)' },
]

interface PasoEstado {
  vista: VistaConfiguracion
  icono: LucideIcon
  etiqueta: string
  detalle: string
  cargando: boolean
  error: boolean
  recargar: () => void
}

/**
 * La línea hace visible la dependencia operativa real del CRM: primero quién
 * puede trabajar, luego qué puede vender, contra qué objetivo y bajo qué plazo.
 */
export function RielEstadoConfiguracion({ pasos }: { pasos: PasoEstado[] }) {
  if (pasos.length === 0) return null
  return (
    <Card>
      <CardContent className="p-4 sm:p-5">
        <div className="mb-4 flex flex-wrap items-baseline justify-between gap-2">
          <div>
            <p className="text-[10px] font-extrabold uppercase tracking-[0.12em] text-muted-foreground">
              Estado operativo
            </p>
            <p className="mt-1 text-xs text-foreground/75">
              Personas → catálogo → metas → atención
            </p>
          </div>
          <span className="text-[10px] font-semibold text-muted-foreground">Lectura vigente por permiso</span>
        </div>

        <ol
          aria-label="Estado operativo de la configuración"
          className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4 xl:gap-4"
        >
          {pasos.map((paso) => (
            <li
              key={paso.vista}
              className="relative border-l-2 border-accent/25 pl-4 xl:border-l-0 xl:border-t-2 xl:pl-0 xl:pt-4"
            >
              <span
                aria-hidden
                className={`absolute -left-[5px] top-1.5 size-2 rounded-full ring-4 ring-card xl:-top-[5px] xl:left-0 ${
                  paso.error
                    ? 'bg-destructive'
                    : paso.cargando
                      ? 'animate-pulse bg-muted-foreground motion-reduce:animate-none'
                      : 'bg-accent'
                }`}
              />
              <div className="flex min-h-16 items-start gap-3">
                <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-primary/[0.07] text-primary">
                  <paso.icono className="size-4" aria-hidden />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-[11px] font-extrabold text-primary">{paso.etiqueta}</p>
                  {paso.cargando ? (
                    <p className="mt-1 text-[11px] text-muted-foreground" role="status">
                      Verificando…
                    </p>
                  ) : paso.error ? (
                    <div className="mt-1 flex flex-wrap items-center gap-2">
                      <span className="text-[11px] font-semibold text-destructive">Lectura no disponible</span>
                      <button
                        type="button"
                        onClick={paso.recargar}
                        className="inline-flex items-center gap-1 rounded px-1 py-0.5 text-[10px] font-bold text-foreground hover:bg-muted focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                        aria-label={`Reintentar ${paso.etiqueta}`}
                      >
                        <RefreshCw className="size-3" aria-hidden /> Reintentar
                      </button>
                    </div>
                  ) : (
                    <p className="mt-1 text-[11px] font-semibold tabular-nums text-foreground/75">{paso.detalle}</p>
                  )}
                  <a
                    href={hashDe(paso.vista)}
                    className="mt-1 inline-flex items-center gap-0.5 rounded-sm text-[10px] font-bold text-accent hover:text-primary focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                    aria-label={`Abrir ${paso.etiqueta}`}
                  >
                    Revisar <ChevronRight className="size-3" aria-hidden />
                  </a>
                </div>
              </div>
            </li>
          ))}
        </ol>
      </CardContent>
    </Card>
  )
}

export function Config() {
  const { yo } = useAuth()
  const edita = Boolean(yo && !yo.demo && can(yo.rol, 'editarConfiguracion'))
  const soloRoles = administraSoloRolesCrm(yo)
  const rolPortalAutorizado = puedeAdministrarRolesCrm(yo) ? 'superadmin' : null
  // «Celulares» (F4-c) comparte el interruptor de la integración del celular: hasta que la base
  // esté aplicada en producción sus puertas no existen y la tarjeta no se ofrece (en la demo sí).
  const celularesAbiertos = llamadasCelularHabilitadas(yo?.demo === true)
  const secciones = SECCIONES.filter((seccion) =>
    vistaPermitida(seccion.vista, yo?.rol, true, rolPortalAutorizado)
    && (seccion.vista !== 'config-celulares' || celularesAbiertos),
  )
  const autorizada = (vista: VistaConfiguracion) =>
    secciones.some((seccion) => seccion.vista === vista)
  const usuarios = useCatalogoUsuariosAdministrables(autorizada('config-usuarios'))
  const productos = useConfiguracionProductos(autorizada('config-productos'))
  const metas = useConfiguracionMetas(periodoLima(Date.now()), autorizada('config-metas'))
  const sla = useConfiguracionSla(autorizada('config-sla'))

  const pasos: PasoEstado[] = []
  if (autorizada('config-usuarios')) {
    const activos = usuarios.data?.filter((fila) => fila.activo_crm === true && fila.activo_portal).length ?? 0
    pasos.push({
      vista: 'config-usuarios',
      icono: Users,
      etiqueta: 'Personas activas',
      detalle: usuarios.data ? `${activos} de ${usuarios.data.length} habilitadas` : 'Sin información',
      cargando: usuarios.isPending,
      error: usuarios.isError,
      recargar: () => { void usuarios.refetch() },
    })
  }
  if (autorizada('config-productos')) {
    const activos = productos.data?.productos.filter((producto) => producto.estado === 'activo') ?? []
    const revision = activos.reduce((mayor, producto) => Math.max(mayor, producto.revision), 0)
    pasos.push({
      vista: 'config-productos',
      icono: Package,
      etiqueta: 'Catálogo y revisión',
      detalle: productos.data ? `${activos.length} productos · revisión ${revision}` : 'Sin información',
      cargando: productos.isPending,
      error: productos.isError,
      recargar: () => { void productos.refetch() },
    })
  }
  if (autorizada('config-metas')) {
    pasos.push({
      vista: 'config-metas',
      icono: Target,
      etiqueta: 'Metas del mes',
      detalle: metas.data
        ? `${metas.data.vendedores.length} ${metas.data.vendedores.length === 1 ? 'analista' : 'analistas'} · revisión ${metas.data.revision}`
        : 'Sin información',
      cargando: metas.isPending,
      error: metas.isError,
      recargar: () => { void metas.refetch() },
    })
  }
  if (autorizada('config-sla')) {
    pasos.push({
      vista: 'config-sla',
      icono: Clock,
      etiqueta: 'SLA vigente',
      detalle: sla.data
        ? `v${sla.data.politica.version} · gestión ${minutosLegibles(sla.data.politica.primera_gestion_minutos)}`
        : 'Sin información',
      cargando: sla.isPending,
      error: sla.isError,
      recargar: () => { void sla.refetch() },
    })
  }

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* Encabezado de página */}
      <Card>
        <SectionHead
          icon={Settings}
          title="Configuración del CRM"
          right={yo?.rol && <Badge color="var(--accent)" variant="outline">{ROL_LABEL[yo.rol]}</Badge>}
        />
        <CardContent className="pt-0">
          <p className="text-xs text-muted-foreground">
            Gobierno de personas, oferta comercial, objetivos y tiempos de atención.
            Cada cambio queda versionado y validado por el servidor.
          </p>
        </CardContent>
      </Card>

      {/* Banner de modo auditoría — SOLO para quien de verdad viene a auditar.
          Desde que el analista entra aquí a conectar su calendario (2026-07-25),
          `!edita` ya no significa "auditor": significa "no es gerencia". Al
          analista le salía un cartel diciéndole que está en modo auditoría cuando
          lo único que vino a hacer es exportar SU agenda. */}
      {yo?.demo ? (
        <div className="flex items-center gap-2.5 rounded-xl bg-accent/[0.08] px-4 py-3 text-primary ring-1 ring-accent/20">
          <Eye className="size-4 shrink-0" aria-hidden />
          <p className="text-xs font-semibold">
            Demostración de solo lectura: explora una fotografía ficticia sin consultar ni modificar datos reales.
          </p>
        </div>
      ) : soloRoles ? (
        <div className="flex items-center gap-2.5 rounded-xl bg-accent/[0.08] px-4 py-3 text-primary ring-1 ring-accent/20">
          <Users className="size-4 shrink-0" aria-hidden />
          <p className="text-xs font-semibold">
            Gobierno de roles y Control de Citas: administra las opciones disponibles para Superadmin.
          </p>
        </div>
      ) : !edita && !puedeEscribir(yo?.rol) && (
        <div className="flex items-center gap-2.5 rounded-xl bg-warning/10 px-4 py-3 text-warning ring-1 ring-warning/20">
          <Eye className="size-4 shrink-0" />
          <p className="text-xs font-semibold">
            Modo auditoría: puedes ver la configuración pero no editarla.
          </p>
        </div>
      )}

      {/* Mi calendario de Google: personal, cada miembro conecta el suyo.
          El directorio (solo lectura) no agenda tareas — no tiene qué conectar. */}
      {yo && !soloRoles && puedeEscribir(yo.rol) && <CalendarioGoogle perfilId={yo.id} demo={yo.demo} />}

      <NotificacionesTasa />
      <ConfiguracionRespuestasTasa />
      <RielEstadoConfiguracion pasos={pasos} />

      {/* Áreas de gobierno disponibles para la identidad actual. */}
      {secciones.length > 0 && <div className="grid gap-4 sm:grid-cols-2">
        {secciones.map((s) => {
          const administra = !yo?.demo
            && (edita || (s.vista === 'config-usuarios' && puedeAdministrarRolesCrm(yo))
              || (s.vista === 'config-citas' && puedeConfigurarCitas(yo)))
          return (
          <Card key={s.t} className="ac-lift">
            <CardContent className="flex items-start gap-4 p-5">
              <span
                className="ac-chip grid size-10 shrink-0 place-items-center rounded-xl"
                style={{ '--c': s.color } as CSSProperties}
              >
                <s.icon className="size-5" />
              </span>

              <div className="min-w-0 flex-1">
                <CardTitle className="text-primary">{s.t}</CardTitle>
                <CardDescription className="mt-1">{s.d}</CardDescription>

                <div className="mt-3 flex items-center justify-between gap-2">
                  <Badge color={s.color} variant="outline">
                    {administra ? 'Administración' : 'Solo lectura'}
                  </Badge>

                  <a
                    href={hashDe(s.vista)}
                    className="inline-flex h-8 shrink-0 items-center gap-1 rounded-md px-3 text-xs font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                  >
                    Abrir <ChevronRight className="size-4" aria-hidden />
                  </a>
                </div>
              </div>
            </CardContent>
          </Card>
          )
        })}
      </div>}
    </div>
  )
}
