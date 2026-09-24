import type { CriterioBusqueda } from '@/data/cliente-existente-api'

// Reglas de pantalla de la venta cruzada, sin red. El servidor vuelve a validar todo.

const SEPARADORES = /[\s\-+().]/g

/**
 * Lo escrito en el buscador de la Cartera es un dato exacto (documento, teléfono o número de
 * contrato) y no un nombre: lleva dígitos y, sin separadores, al menos 6 caracteres. Una
 * búsqueda así no se recorta por el mes de cierre: encontrar a la persona importa más que el
 * mes en que cerró.
 */
export function esBusquedaExacta(texto: string): boolean {
  const limpio = texto.trim().replace(SEPARADORES, '')
  return /\d/.test(limpio) && limpio.length >= 6 && /^[A-Za-z0-9]+$/.test(limpio)
}

/**
 * El criterio con el que abrir la búsqueda en otras carteras a partir de lo escrito: 8
 * dígitos es un DNI; un celular peruano (9 dígitos que empiezan con 9, con o sin 51) es un
 * teléfono; otros solo dígitos, un carné de extranjería; con letras, un pasaporte. Un número
 * de contrato no se ofrece. Quien busca puede corregirlo en el diálogo.
 */
export function criterioDesdeTexto(texto: string): CriterioBusqueda | undefined {
  // Un número de contrato (2026-01-000123) se busca sin mes, pero no es un documento.
  if (/^\s*\d{4}-\d{2}-\d{3,}\s*$/.test(texto)) return undefined
  const limpio = texto.trim().replace(SEPARADORES, '').toUpperCase()
  if (!esBusquedaExacta(limpio)) return undefined
  if (/^\d{8}$/.test(limpio)) return {tipo: 'documento', tipoDocumento: 'DNI', numero: limpio}
  if (/^(51)?9\d{8}$/.test(limpio)) return {tipo: 'telefono', telefono: limpio}
  if (/^\d{9,12}$/.test(limpio)) return {tipo: 'documento', tipoDocumento: 'CE', numero: limpio}
  if (/^[A-Z0-9]{6,12}$/.test(limpio)) return {tipo: 'documento', tipoDocumento: 'PASAPORTE', numero: limpio}
  return undefined
}
