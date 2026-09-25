import { ColaSlaPanel, SlaOperacionBoundary } from '@/components/app/sla-operacion'
import { Card, CardContent } from '@/components/ui/card'
import { useAuth } from '@/lib/auth-context'

/** Cola actual compartida durante la transición de Seguimiento a Gestión Diaria. */
export function ColaSeguimiento() {
  const { yo } = useAuth()
  return (
    <SlaOperacionBoundary legado={(
      <Card>
        <CardContent className="space-y-2 p-6">
          <h2 className="text-base font-bold">Seguimiento comercial</h2>
          <p role="status" className="text-sm text-muted-foreground">
            {yo?.demo
              ? 'El seguimiento comercial operativo está disponible en la sesión real.'
              : 'El seguimiento comercial no está activo. Este módulo estará disponible cuando se activen las reglas de seguimiento.'}
          </p>
        </CardContent>
      </Card>
    )}>
      <ColaSlaPanel />
    </SlaOperacionBoundary>
  )
}
