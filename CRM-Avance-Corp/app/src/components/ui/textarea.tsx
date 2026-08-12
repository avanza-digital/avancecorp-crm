// Espejo de input.tsx para texto multilínea (F1b).
import { forwardRef, type TextareaHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(
  ({ className, ...props }, ref) => (
    <textarea
      ref={ref}
      data-slot="textarea"
      className={cn(
        'flex min-h-[72px] w-full resize-none rounded-lg border border-input bg-background px-3 py-2 text-sm shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30 focus-visible:border-ring disabled:cursor-not-allowed disabled:opacity-50',
        // Espejo de input.tsx: la marca visual del campo inválido (ver allí).
        'aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/25',
        className,
      )}
      {...props}
    />
  ),
)
Textarea.displayName = 'Textarea'
