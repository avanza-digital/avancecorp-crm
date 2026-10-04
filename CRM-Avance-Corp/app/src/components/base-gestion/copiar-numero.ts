import { toast } from 'sonner'

// En la laptop un `tel:` no marca nada: se copia el número (el mismo de enlaceTel) para marcarlo desde el celular.
export function copiarNumero(tel: string, legible: string): void {
  const copia = navigator.clipboard?.writeText(tel.slice('tel:'.length)) ?? Promise.reject(new Error('sin portapapeles'))
  void copia.then(
    () => { toast.success(`Número copiado: ${legible} — márcalo desde tu celular`) },
    () => { toast.info(`Marca ${legible} desde tu celular`) },
  )
}
