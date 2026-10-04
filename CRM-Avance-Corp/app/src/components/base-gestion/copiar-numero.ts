import { toast } from 'sonner'

// En la laptop un `tel:` no marca nada: se copia el número (el mismo de enlaceTel) para marcarlo desde el celular.
// `para = 'copiar'` es el botón «Copiar número» de la ficha: copia sin dar por hecho que se va a marcar.
export function copiarNumero(tel: string, legible: string, para: 'marcar' | 'copiar' = 'marcar'): void {
  const copia = navigator.clipboard?.writeText(tel.slice('tel:'.length)) ?? Promise.reject(new Error('sin portapapeles'))
  void copia.then(
    () => { toast.success(para === 'marcar' ? `Número copiado: ${legible} — márcalo desde tu celular` : `Número copiado: ${legible}`) },
    () => { toast.info(para === 'marcar' ? `Marca ${legible} desde tu celular` : `No se pudo copiar: el número es ${legible}`) },
  )
}
