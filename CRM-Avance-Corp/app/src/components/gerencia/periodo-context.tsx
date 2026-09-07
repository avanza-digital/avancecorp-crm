import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type Dispatch,
  type JSX,
  type ReactNode,
  type SetStateAction,
} from 'react'
import { fechaLima } from '@/lib/agenda-derivada'
import type { FuenteConversion } from '@/lib/conversion-vendedores'
import { periodoInicialGerencia, type PeriodoGerencia } from './periodo'
import { PeriodoGerenciaContext } from './periodo-context-base'

function mismoPeriodo(a: PeriodoGerencia, b: PeriodoGerencia): boolean {
  return a.desde === b.desde && a.hasta === b.hasta
}

function milisegundosHastaMedianocheLima(ahora: number): number {
  const hoy = fechaLima(ahora)
  const anio = Number(hoy.slice(0, 4))
  const mes = Number(hoy.slice(5, 7))
  const dia = Number(hoy.slice(8, 10))
  // Lima opera en UTC-5 y no observa horario de verano.
  const siguienteMedianoche = Date.UTC(anio, mes - 1, dia + 1, 5)
  return Math.max(1, siguienteMedianoche - ahora)
}

export function PeriodoGerenciaProvider({ children }: { children: ReactNode }): JSX.Element {
  const [periodo, setPeriodoInterno] = useState<PeriodoGerencia>(periodoInicialGerencia)
  const [diaLima, setDiaLima] = useState(() => fechaLima(Date.now()))
  const [origenFiltrado, setOrigenFiltrado] = useState<FuenteConversion | null>(null)
  const automaticoRef = useRef(true)
  const setPeriodo = useCallback<Dispatch<SetStateAction<PeriodoGerencia>>>((actualizador) => {
    setPeriodoInterno((anterior) => {
      const siguiente = typeof actualizador === 'function'
        ? actualizador(anterior)
        : actualizador
      automaticoRef.current = mismoPeriodo(siguiente, periodoInicialGerencia())
      return siguiente
    })
  }, [])

  useEffect(() => {
    let temporizador: ReturnType<typeof setTimeout>

    const programarSiguienteDia = (): void => {
      temporizador = setTimeout(() => {
        setDiaLima(fechaLima(Date.now()))
        if (automaticoRef.current) setPeriodoInterno(periodoInicialGerencia())
        programarSiguienteDia()
      }, milisegundosHastaMedianocheLima(Date.now()))
    }

    programarSiguienteDia()
    return () => clearTimeout(temporizador)
  }, [])

  const value = useMemo(
    () => ({ periodo, setPeriodo, diaLima, origenFiltrado, setOrigenFiltrado }),
    [diaLima, origenFiltrado, periodo, setPeriodo],
  )
  return <PeriodoGerenciaContext.Provider value={value}>{children}</PeriodoGerenciaContext.Provider>
}
