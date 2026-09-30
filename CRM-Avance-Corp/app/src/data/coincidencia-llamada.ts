// data/coincidencia-llamada.ts — pide al servidor los candidatos del número que
// trajo el celular y los clasifica (F1.3.2 del plan «Llamadas desde el celular
// al CRM», 30/09/2026). La regla de comparación vive en lib/coincidencia-telefono;
// aquí solo se decide QUÉ pedir y CUÁNTO: los dígitos nacionales (para que
// salgan las dos formas guardadas) y una página grande, para poder decir si se
// vio todo. Misma puerta que la barra de búsqueda (`cartera_pagina_fn`, INVOKER:
// el alcance lo pone la RLS). En la demo no hay servidor: se mira el ámbito local.
import { buscarLeadsGlobal, CrmApiError } from './crm-api'
import { coincideTextoCartera, textoBuscable } from '@/lib/cartera-keyset'
import {
  clasificarCoincidencia,
  digitosParaBuscar,
  numeroCanonico,
  type Coincidencia,
} from '@/lib/coincidencia-telefono'
import type { Lead } from '@/lib/tipos'

/**
 * Filas que se piden por número. La puerta admite hasta 200; con 50 una página
 * llena ya dice «hay demasiados leads con estos dígitos» y el resultado se marca
 * incompleto en vez de fingir unicidad.
 */
export const TOPE_CANDIDATOS = 50

/** Resultados de la búsqueda manual del aviso (los mismos que la barra). */
export const TOPE_BUSQUEDA_MANUAL = 8

export interface OpcionesResolucion {
  /** En la demo no hay servidor: se compara contra el ámbito local. */
  demo: boolean
  leadsLocales: readonly Lead[]
  signal?: AbortSignal | undefined
}

const MENSAJE_ERROR = 'No se pudo buscar el número en tus leads. Revisa tu conexión.'

export async function resolverNumeroLlamada(numero: string, opciones: OpcionesResolucion): Promise<Coincidencia<Lead>> {
  const canon = numeroCanonico(numero)
  const digitos = digitosParaBuscar(numero)
  if (digitos === null) return { estado: 'invalido', numero: canon }
  if (opciones.demo) return clasificarCoincidencia(numero, opciones.leadsLocales, true)
  try {
    const candidatos = await buscarLeadsGlobal(digitos, opciones.signal, TOPE_CANDIDATOS)
    return clasificarCoincidencia(numero, candidatos, candidatos.length < TOPE_CANDIDATOS)
  } catch (causa) {
    if (opciones.signal?.aborted) throw causa
    return { estado: 'error', numero: canon, mensaje: causa instanceof CrmApiError ? causa.message : MENSAJE_ERROR }
  }
}

/** Búsqueda manual desde el aviso (nombre, teléfono o DNI). Vacía por debajo del mínimo del servidor. */
export async function buscarLeadsManual(texto: string, opciones: OpcionesResolucion): Promise<Lead[]> {
  if (textoBuscable(texto) === null) return []
  if (opciones.demo) return opciones.leadsLocales.filter((l) => l.activo && coincideTextoCartera(l, texto)).slice(0, TOPE_BUSQUEDA_MANUAL)
  return buscarLeadsGlobal(texto, opciones.signal, TOPE_BUSQUEDA_MANUAL)
}
