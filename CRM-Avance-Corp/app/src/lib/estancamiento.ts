// lib/estancamiento.ts — el semáforo por ETAPA de la tarjeta del kanban.
//
// Hoy la card pinta los días desde `creado_en` en gris, siempre igual: un lead
// que lleva 6 días en "Propuesta enviada" (dentro de su plazo) se ve idéntico a
// uno que lleva 6 días en "Nuevo" (seis veces por encima del suyo). El analista
// tiene que saberse los umbrales de memoria para leer su propio tablero.
//
// DOS DECISIONES DE FONDO, las dos obligatorias:
//
// 1. UN SOLO RELOJ. La referencia sale de `referenciaEspera` (lib/inteligencia),
//    la MISMA que usa la cola de acción — no una copia. Dos fórmulas gemelas
//    divergen, y entonces Hoy y Pipeline dan días distintos sobre el mismo lead.
//
// 2. EL NÚMERO CAMBIA CON EL COLOR. La card mostraba días desde `creado_en`,
//    que es el reloj del CLIENTE; el umbral es del ANALISTA. Dejar el número viejo
//    al lado de un punto rojo calculado con otro reloj hace que la card mienta
//    por adyacencia (el ojo lee "rojo por ESE número"). Con el circuito vivo
//    —origen → hoja → cola de Rosa → bandeja → analista— un lead pasa días
//    antes de llegar a un analista: ese es justo el bug que ya se corrigió en la
//    cola el 2026-07-24.
import { SEMAFORO } from './semaforo'
import { referenciaEspera, diasDesdeReferencia, type IndiceUltimaActividad } from './inteligencia'
import type { EstadoSlaLead } from './sla-versionado'
import type { Lead } from './tipos'

const DIA_MS = 86_400_000

export interface SemaforoEtapa {
  /** Días (con fracción) dentro del episodio vigente de la etapa. */
  dias: number
  /** Color del punto, o `null` si esa etapa no tiene umbral (terminales). */
  color: string | null
  /** ¿Cruzó el umbral de SU etapa? */
  estancado: boolean
  /** Plazo sellado en el episodio; null cuando no existe fotografía confiable. */
  objetivoMinutos: number | null
  politicaVersion: number | null
  aproximado: boolean
}

/**
 * Semáforo de una card: azul dentro de plazo · ámbar pasado el umbral · rojo al
 * doble. El escalón del doble existe para que un lead a 5 días en `nuevo`
 * (5× su umbral) no se vea igual que uno a 25 h.
 */
export function semaforoEstancamiento(
  lead: Lead,
  indice: IndiceUltimaActividad,
  ahora: number,
  estado?: EstadoSlaLead,
): SemaforoEtapa {
  const diasContacto = diasDesdeReferencia(referenciaEspera(lead, indice), ahora)
  if (
    !estado
    || estado.etapa !== lead.etapa
    || estado.etapa_iniciada_en == null
    || estado.etapa_limite_en == null
    || estado.etapa_objetivo_minutos == null
  ) {
    return {
      dias: diasContacto,
      color: null,
      estancado: false,
      objetivoMinutos: null,
      politicaVersion: null,
      aproximado: false,
    }
  }

  const inicio = Date.parse(estado.etapa_iniciada_en)
  const limite = Date.parse(estado.etapa_limite_en)
  if (!Number.isFinite(inicio) || !Number.isFinite(limite) || limite < inicio) {
    return {
      dias: diasContacto,
      color: null,
      estancado: false,
      objetivoMinutos: null,
      politicaVersion: null,
      aproximado: false,
    }
  }

  const dias = Math.max(0, (ahora - inicio) / DIA_MS)
  const duracion = limite - inicio
  const comun = {
    dias,
    objetivoMinutos: estado.etapa_objetivo_minutos,
    politicaVersion: estado.etapa_politica_version,
    aproximado: estado.etapa_aproximada ?? false,
  }
  if (ahora >= limite + duracion) return { ...comun, color: SEMAFORO.critico, estancado: true }
  if (ahora >= limite) return { ...comun, color: SEMAFORO.atencion, estancado: true }
  return { ...comun, color: SEMAFORO.ok, estancado: false }
}
