import { Component, Fragment, type ErrorInfo, type ReactNode } from 'react'
import { AlertTriangle, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { idCorrelacionCorto, registrarError } from '@/lib/observabilidad'

interface ErrorBoundaryProps {
  children: ReactNode
  /** Nombre humano de la sección protegida (aparece en consola y en el mensaje). */
  etiqueta?: string
}

interface ErrorBoundaryState {
  hayError: boolean
  /** Cambia en cada reintento: remonta el subárbol desde cero (key). */
  intento: number
}

/**
 * Barrera de errores: si una sección revienta, el resto de la app sigue viva.
 * Fallback amable en es-PE con botón «Reintentar» que REMONTA los hijos desde
 * cero (key por intento) — ante un error determinista, solo resetear el flag
 * volvía a renderizar el mismo árbol roto y el botón parpadeaba sin efecto.
 */
export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hayError: false, intento: 0 }

  static getDerivedStateFromError(): Partial<ErrorBoundaryState> {
    return { hayError: true }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    registrarError('ui.error_boundary', error, {
      seccion: this.props.etiqueta ?? 'sin_etiqueta',
      // El stack de componentes no contiene props ni valores de formulario.
      componentStack: info.componentStack,
    })
  }

  private reintentar = () => {
    this.setState((s) => ({ hayError: false, intento: s.intento + 1 }))
  }

  render() {
    if (this.state.hayError) {
      return (
        <div className="flex min-h-[220px] flex-col items-center justify-center gap-3 rounded-xl border border-border bg-card p-8 text-center">
          <div className="flex size-11 items-center justify-center rounded-full bg-destructive/10">
            <AlertTriangle className="size-5 text-destructive" />
          </div>
          <div className="space-y-1">
            <p className="text-sm font-semibold text-foreground">Algo salió mal en esta sección</p>
            <p className="max-w-xs text-xs leading-relaxed text-muted-foreground">
              Puedes volver a intentarlo. Si el problema continúa, avísanos.
            </p>
            <p className="text-[10px] tabular-nums text-muted-foreground">
              Código de diagnóstico: {idCorrelacionCorto()}
            </p>
          </div>
          <Button variant="outline" size="sm" onClick={this.reintentar}>
            <RotateCcw /> Reintentar
          </Button>
        </div>
      )
    }
    return <Fragment key={this.state.intento}>{this.props.children}</Fragment>
  }
}
