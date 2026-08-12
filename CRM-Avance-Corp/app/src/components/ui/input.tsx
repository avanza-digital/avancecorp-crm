import { forwardRef, type InputHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  ({ className, type, ...props }, ref) => (
    <input
      ref={ref}
      type={type}
      className={cn(
        'flex h-9 w-full rounded-lg border border-input bg-background px-3 py-1 text-sm shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30 focus-visible:border-ring disabled:cursor-not-allowed disabled:opacity-50',
        // Un campo marcado como inválido tiene que VERSE inválido: hasta ahora
        // `aria-invalid` solo se lo contaba al lector de pantalla, y quien mira
        // un formulario de 7 campos leía un mensaje rojo al fondo sin saber
        // cuál corregir. La marca vive aquí y no en cada formulario para que
        // ningún campo nuevo nazca sin ella.
        'aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/25',
        className,
      )}
      {...props}
    />
  ),
)
Input.displayName = 'Input'
