import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { horaCorte, type AvisoCorte } from '@/lib/gestion-diaria-avisos'
import { Button } from '@/components/ui/button'

/** La lista, el popup y la campana abren exactamente el mismo registro. */
export function MiembrosAvisoCorte({ aviso, mostrarContexto = false }: { aviso: AvisoCorte; mostrarContexto?: boolean }) {
  const contexto = useGestionDiariaAvisos()
  return <ul className="divide-y divide-border text-base">{aviso.miembros.map((m) => {
    const persona = mostrarContexto ? contexto?.datos?.contexto?.equipo.find((e) => e.analista_id === m.analista_id) : null
    return <li key={m.analista_id} className="gd-persona-corte flex min-w-0 flex-wrap items-center justify-between gap-3 py-3">
      <div className="min-w-0 break-words"><strong>{m.nombre}</strong><p>{m.llamadas} llamadas al corte · mínimo {m.objetivo}
        {m.llamadas_recuperacion !== null ? ` · ${m.llamadas_recuperacion} llamadas en la ventana de recuperación` : ''}</p>
        {persona && <p>{persona.primera_llamada_en ? `Primera llamada de hoy: ${horaCorte(persona.primera_llamada_en)} Lima.` : 'Sin llamadas registradas hoy.'}</p>}</div>
      <Button variant="outline" className="h-auto min-h-11 max-w-full whitespace-normal text-base" disabled={!contexto || Boolean(contexto.error)}
        onClick={() => contexto?.abrirRegistro(aviso, m.analista_id)}>Ver registro de {m.nombre}</Button>
    </li>
  })}</ul>
}
