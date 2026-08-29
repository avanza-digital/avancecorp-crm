import * as v from 'valibot'
import { describe, expect, it } from 'vitest'
import { InicioAyudaVendedorSchema, ResultadoConsultaAyudaVendedorSchema } from './ayuda-vendedor'

const respuestaValida = {
  version: 1,
  tipo: 'respuesta',
  respuesta: {
    id: 'anular-tarea-pendiente',
    titulo: 'Quitar una acción pendiente de tu agenda',
    resumen: 'Anula una acción que ya no realizarás.',
    duracion: '1 min',
    pasos: [{ titulo: 'Ubica la acción', detalle: 'Encuéntrala en Agenda.' }],
    accion: { tipo: 'navegar', vista: 'agenda', etiqueta: 'Ir a Agenda' },
    fuente: 'Manual del analista · versión aprobada',
  },
} as const

describe('contrato público del centro de ayuda', () => {
  it.each([
    respuestaValida,
    {
      version: 1,
      tipo: 'aclaracion',
      aclaracion: {
        titulo: '¿Qué quieres quitar?',
        detalle: 'Elige una opción.',
        opciones: [
          {
            etiqueta: 'Una tarea',
            detalle: 'Está pendiente.',
            consulta: 'borrar tarea',
          },
          {
            etiqueta: 'Una actividad',
            detalle: 'Ya fue registrada.',
            consulta: 'borrar actividad',
          },
        ],
      },
    },
    { version: 1, tipo: 'sin_resultado', consulta: 'consulta desconocida' },
  ])('acepta únicamente uno de los tres resultados versionados', (payload) => {
    expect(v.safeParse(ResultadoConsultaAyudaVendedorSchema, payload).success).toBe(true)
  })

  it('rechaza puntuaciones internas aunque el resto de la respuesta sea válido', () => {
    const payload = { ...respuestaValida, puntuacion: 0.99 }
    expect(v.safeParse(ResultadoConsultaAyudaVendedorSchema, payload).success).toBe(false)
  })

  it('rechaza acciones hacia rutas que no existen en el CRM', () => {
    const payload = {
      ...respuestaValida,
      respuesta: {
        ...respuestaValida.respuesta,
        accion: {
          tipo: 'navegar',
          vista: 'administracion-secreta',
          etiqueta: 'Ir',
        },
      },
    }
    expect(v.safeParse(ResultadoConsultaAyudaVendedorSchema, payload).success).toBe(false)
  })

  it('limita a seis las preguntas frecuentes servidas', () => {
    expect(
      v.safeParse(InicioAyudaVendedorSchema, {
        version: 1,
        preguntas: Array.from({ length: 7 }, (_, indice) => `Pregunta ${indice + 1}`),
      }).success,
    ).toBe(false)
  })
})
