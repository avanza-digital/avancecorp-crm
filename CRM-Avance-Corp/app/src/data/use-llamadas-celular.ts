// Fuente de la pestaña «Llamadas del celular» (F4-b). En la DEMO, las llamadas de lib/demo-llamadas-celular con sus
// acciones en memoria. En la sesión real devuelve `null` —la pestaña no se muestra— hasta que las puertas tengan sus
// tipos generados desde el esquema con las migraciones aplicadas (estándar de 4 capas: nunca a mano;
// F4B-PLAN-CORTO.md, B3). Entonces aquí se llamará a data/llamadas-celular-api.ts, la única capa que habla con ellas.
import { useCallback, useState } from 'react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { demoPendientesCelular, demoResueltasHoyCelular } from '@/lib/demo-llamadas-celular'
import { etiquetaMotivoDescarte, numeroLegible, type FilaBandeja, type MotivoDescarte, type ResueltaHoy } from '@/lib/llamadas-celular'
import type { Lead } from '@/lib/tipos'

export interface FuenteLlamadasCelular {
  pendientes: readonly FilaBandeja[]
  resueltas: readonly ResueltaHoy[]
  /** evento_id con una acción en curso. */
  ocupado: string | null
  descartar: (fila: FilaBandeja, motivo: MotivoDescarte, detalle: string | null) => void
  elegirLead: (fila: FilaBandeja, lead: Lead) => void
}

const quien = (fila: FilaBandeja) => fila.lead_nombre ?? numeroLegible(fila.numero)

export function useLlamadasCelular(): FuenteLlamadasCelular | null {
  const { yo } = useAuth()
  const demo = yo?.demo === true
  const [estado, setEstado] = useState(() => ({
    pendientes: demoPendientesCelular(Date.now()),
    resueltas: demoResueltasHoyCelular(Date.now()),
  }))

  const descartar = useCallback((fila: FilaBandeja, motivo: MotivoDescarte, detalle: string | null) => {
    setEstado((e) => ({
      pendientes: e.pendientes.filter((f) => f.evento_id !== fila.evento_id),
      resueltas: [{
        evento_id: fila.evento_id, resuelto_en: new Date().toISOString(), recibido_en: fila.recibido_en, ocurrio_en: fila.ocurrio_en, numero: fila.numero,
        atencion: 'descartado_con_motivo', lead_id: fila.lead_id, lead_nombre: fila.lead_nombre, analista_id: fila.analista_id,
        es_propia: fila.es_propia, etiqueta: 'C1', actividad_id: null, resultado: null, deshecho: false, via: null,
        motivo_descarte: motivo, motivo_descarte_detalle: detalle,
      }, ...e.resueltas],
    }))
    toast.success(`Descartada: ${quien(fila)} (${etiquetaMotivoDescarte(motivo, detalle).toLowerCase()}). No cuenta como gestión del lead.`)
  }, [])

  const elegirLead = useCallback((fila: FilaBandeja, lead: Lead) => {
    setEstado((e) => ({
      ...e,
      pendientes: e.pendientes.map((f) => (f.evento_id === fila.evento_id
        ? { ...f, identificacion: 'identificado', atencion: 'requiere_resultado', lead_id: lead.id, lead_nombre: lead.nombre_completo }
        : f)),
    }))
    toast.success(`La llamada quedó asociada a ${lead.nombre_completo}. Ahora pide su resultado.`)
  }, [])

  if (!demo) return null
  return { pendientes: estado.pendientes, resueltas: estado.resueltas, ocupado: null, descartar, elegirLead }
}
