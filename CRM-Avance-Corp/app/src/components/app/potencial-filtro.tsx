// Fila «Por potencial» de la tabla de Leads: cuatro pastillas con su conteo
// (Frío · Tibio · Estrella · Sin marcar). La cifra ES el filtro, igual que en
// «Por etapa»: tocarla deja la lista, los totales y el capital con ese nivel;
// volver a tocarla lo quita. Un nivel a la vez (decisión de Miguel, 01/10/2026).
//
// Los conteos llegan del servidor (`resumen.potencial`) contados ANTES de
// aplicar este filtro: no cambian al elegir un nivel. Aquí no se cuenta nada.
import { useLayoutEffect, useRef } from 'react'
import { Check, CircleDashed } from 'lucide-react'
import { cn } from '@/lib/utils'
import { PILDORA, PILDORA_INACTIVA } from '@/components/gestion-diaria/estilos-gestion'
import {
  ETIQUETA_FILTRO_POTENCIAL, FILTROS_POTENCIAL, type ConteosPotencial, type FiltroPotencial,
} from '@/lib/potencial'
import { IconoPotencial } from './potencial-chip'

export function FiltroPotencialCartera({ conteos, valor, sinCifras, ocupado, onCambio, alRetirarConFoco }: {
  /** Los conteos vigentes o, mientras llega la consulta nueva, los últimos conocidos. */
  conteos: ConteosPotencial
  valor: FiltroPotencial | null
  /** Sin resumen vigente (cargando o con error): las pastillas se quedan, sin número. */
  sinCifras: boolean
  /** Consulta en vuelo: no se pulsa, pero la pastilla no se desmonta ni pierde el foco. */
  ocupado: boolean
  onCambio: (siguiente: FiltroPotencial | null) => void
  /**
   * Se llama si la fila se retira con el foco DENTRO (el servidor apagó el
   * potencial), para que quien la monta lo lleve a otro control: nunca se deja
   * caer al `<body>`. Debe ser ESTABLE (`useCallback`): si cambiara de identidad
   * en cada pintada, se llamaría sin que la fila se haya ido.
   */
  alRetirarConFoco?: () => void
}) {
  const refGrupo = useRef<HTMLDivElement>(null)
  // La limpieza de un efecto de capa corre ANTES de que React quite el nodo: ahí
  // todavía se sabe con certeza si el foco estaba dentro de la fila.
  useLayoutEffect(() => {
    const grupo = refGrupo.current
    return () => { if (grupo?.contains(document.activeElement)) alRetirarConFoco?.() }
  }, [alRetirarConFoco])
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-border px-4 py-2.5">
      {/* Misma tira que «Por etapa»: en móvil, scroll horizontal propio; el p-1
          deja sitio al contorno de foco, que el scroll recortaría. */}
      <div ref={refGrupo} role="group" aria-label="Distribución por potencial" aria-busy={ocupado || undefined}
        className="flex w-full items-center gap-1.5 overflow-x-auto p-1 sm:w-auto sm:flex-wrap sm:overflow-visible sm:p-0">
        <span aria-hidden className="mr-1 min-w-[4.75rem] shrink-0 text-[11px] font-semibold text-muted-foreground">Por potencial</span>
        {FILTROS_POTENCIAL.map((k) => {
          const activa = valor === k
          const n = conteos[k]
          // Una cifra en cero no se abre (sería un filtro vacío a propósito); la
          // elegida siempre se puede soltar. Sin cifras por un error, se puede
          // soltar o cambiar; con la consulta en vuelo, nada.
          const vacia = !activa && !sinCifras && n === 0
          const inerte = ocupado || vacia
          return (
            <button key={k} type="button" aria-pressed={activa} aria-disabled={inerte || undefined}
              onClick={inerte ? undefined : () => { onCambio(activa ? null : k) }}
              className={cn(PILDORA, 'pot-filtro shrink-0 aria-disabled:cursor-default', `pot-filtro--${k}`,
                !activa && PILDORA_INACTIVA, vacia && 'pot-filtro--vacia')}>
              {activa
                ? <Check aria-hidden className="size-3.5" />
                : k === 'sin_marca'
                  ? <CircleDashed aria-hidden className="pot-filtro-ico" strokeWidth={2.25} />
                  : <IconoPotencial nivel={k} relleno={k === 'estrella'} grosor={2.25} className="pot-filtro-ico" />}
              {ETIQUETA_FILTRO_POTENCIAL[k]}{' '}
              <span className="font-bold tabular-nums">
                {sinCifras
                  ? <><span aria-hidden="true">—</span><span className="sr-only">{ocupado ? 'cargando' : 'sin dato'}</span></>
                  : n}
              </span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
