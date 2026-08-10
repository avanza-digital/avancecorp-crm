import { useEffect, useState } from 'react'

/**
 * Valor que se estabiliza tras `ms` sin cambios. Nace con la cartera keyset
 * (F2): desde que la búsqueda la resuelve el SERVIDOR, teclear «MARIA» sin
 * diferir dispara cinco consultas de las que solo importa la última.
 *
 * El valor inicial NO se difiere (se devuelve tal cual en el primer render):
 * diferir un estado que ya está asentado solo retrasaría la primera carga.
 */
export function useValorDiferido<T>(valor: T, ms = 300): T {
  const [diferido, setDiferido] = useState(valor)

  useEffect(() => {
    if (Object.is(valor, diferido)) return
    const id = setTimeout(() => { setDiferido(valor) }, ms)
    // Cada tecla cancela el temporizador anterior: solo sobrevive la pausa.
    return () => { clearTimeout(id) }
  }, [diferido, ms, valor])

  return diferido
}
