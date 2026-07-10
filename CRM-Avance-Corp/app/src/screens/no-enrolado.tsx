import { ShieldAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/lib/auth'

export function NoEnrolado() {
  const { salir } = useAuth()
  return (
    <div className="flex min-h-svh items-center justify-center bg-background p-6">
      <div className="max-w-sm space-y-4 text-center ac-rise">
        <span className="mx-auto flex size-12 items-center justify-center rounded-2xl bg-warning/10 text-warning">
          <ShieldAlert className="size-6" />
        </span>
        <h1 className="text-xl font-extrabold tracking-tight text-primary">Sin acceso al CRM</h1>
        <p className="text-sm text-muted-foreground">
          Tu cuenta existe pero aún no está enrolada en el equipo comercial. Pide a gerencia que
          te agregue al CRM (o, si la base del CRM todavía no se aplicó, es lo esperado por ahora).
        </p>
        <Button variant="outline" onClick={() => void salir()}>Volver al inicio de sesión</Button>
      </div>
    </div>
  )
}
