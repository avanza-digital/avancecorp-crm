import { describe, expect, it } from 'vitest'
import type { GrupoCartera } from './cartera-vista'
import type { ClienteBasico, ContratoRow } from './clientes-tipos'
import {
  construirVistaCliente360,
  resolverContextoFichaCliente,
  type ResolverContextoFichaClienteInput,
} from './cliente-ficha-modelo'
import type { Miembro, Tarea } from './tipos'

function cliente(sobre: Partial<ClienteBasico> = {}): ClienteBasico {
  return {
    id: 'cliente-1',
    nombres: 'María',
    apellidos: 'Quispe',
    nombre_completo: 'MARÍA QUISPE',
    tipo_documento: 'DNI',
    dni: '12345678',
    correo: 'maria@correo.pe',
    telefono: '+51999111222',
    asesor_perfil_id: 'vendedor-1',
    creado_por: 'vendedor-1',
    activo: true,
    creado_en: '2026-01-01T10:00:00.000Z',
    ...sobre,
  }
}

function contrato(sobre: Partial<ContratoRow> = {}): ContratoRow {
  return {
    id: 'contrato-1',
    numero_contrato: '2026-01-000001',
    cliente_id: 'cliente-1',
    cliente_nombre: 'MARÍA QUISPE',
    capital: 10_000,
    moneda: 'PEN',
    tasa_anual: 12,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    categoria: 'nuevo',
    estado: 'activo',
    fecha_inicio: '2026-01-01',
    fecha_vencimiento: '2026-08-25',
    notas_internas: null,
    creado_por: 'vendedor-1',
    creado_en: '2026-01-01T10:00:00.000Z',
    revision_contrato: '2026-08-25T15:00:00.000Z',
    producto_condicion_id: '10000000-0000-4000-8000-000000000001',
    producto_id: '20000000-0000-4000-8000-000000000001',
    producto_codigo: 'RENTA-BASE',
    producto_version_id: '30000000-0000-4000-8000-000000000001',
    producto_version: 1,
    producto_nombre: 'Plan base',
    producto_version_estado: 'publicada',
    ...sobre,
  }
}

function grupo(sobre: Partial<GrupoCartera> = {}): GrupoCartera {
  return {
    cliente: cliente(),
    contratos: [contrato()],
    capitalActivoPen: 10_000,
    capitalActivoUsd: 0,
    contratosActivos: 1,
    tieneCapital: true,
    proximoVencimiento: '2026-08-25',
    ...sobre,
  }
}

function miembro(sobre: Partial<Miembro> = {}): Miembro {
  return {
    perfil_id: 'vendedor-1',
    nombre_completo: 'Andrea Vendedora',
    rol_crm: 'vendedor',
    supervisor_id: 'supervisor-1',
    activo: true,
    ...sobre,
  }
}

function tarea(sobre: Partial<Tarea> = {}): Tarea {
  return {
    id: 'tarea-1',
    lead_id: null,
    perfil_id: 'cliente-1',
    vendedor_id: 'vendedor-1',
    asignado_supervisor_id: 'supervisor-1',
    tipo: 'llamada',
    titulo: 'Llamar al cliente',
    nota: null,
    vence_en: '2026-08-25T15:00:00.000Z',
    estado: 'pendiente',
    reprogramaciones: 0,
    activo: true,
    creado_en: '2026-08-20T10:00:00.000Z',
    ...sobre,
  }
}

const EQUIPO: Miembro[] = [
  miembro(),
  miembro({
    perfil_id: 'vendedor-2',
    nombre_completo: 'Bruno Vendedor',
    supervisor_id: 'supervisor-1',
  }),
  miembro({
    perfil_id: 'vendedor-ajeno',
    nombre_completo: 'Carmen Vendedora',
    supervisor_id: 'supervisor-otro',
  }),
  miembro({
    perfil_id: 'supervisor-1',
    nombre_completo: 'Sofía Supervisora',
    rol_crm: 'supervisor',
    supervisor_id: null,
  }),
]

function contexto(sobre: Partial<ResolverContextoFichaClienteInput> = {}) {
  return resolverContextoFichaCliente({
    grupo: grupo(),
    equipo: EQUIPO,
    yoId: 'vendedor-1',
    rol: 'vendedor',
    puedeContratar: true,
    ...sobre,
  })
}

describe('resolverContextoFichaCliente — lectura, escritura y operabilidad', () => {
  it('el vendedor consulta y gestiona solo su propia cartera', () => {
    expect(contexto()).toEqual({
      clienteId: 'cliente-1',
      asesorNombre: 'Andrea Vendedora',
      consultable: true,
      puedeVerCuentas: true,
      gestionable: true,
      accionable: true,
      operable: true,
      motivoNoOperable: null,
      edicionGlobal: false,
    })

    const ajeno = contexto({
      grupo: grupo({
        cliente: cliente({
          asesor_perfil_id: 'vendedor-2',
          creado_por: 'vendedor-1',
        }),
      }),
    })
    expect(ajeno.consultable).toBe(false)
    expect(ajeno.gestionable).toBe(false)
    expect(ajeno.accionable).toBe(false)
  })

  it('el supervisor consulta cada fila ya autorizada por la cartera del servidor', () => {
    const deSuEquipo = contexto({
      grupo: grupo({
        cliente: cliente({
          asesor_perfil_id: 'vendedor-2',
          creado_por: 'vendedor-2',
        }),
      }),
      yoId: 'supervisor-1',
      rol: 'supervisor',
    })
    expect(deSuEquipo).toMatchObject({
      asesorNombre: 'Bruno Vendedor',
      consultable: true,
      puedeVerCuentas: true,
      gestionable: true,
      accionable: true,
      operable: true,
      edicionGlobal: false,
    })

    const asesorFueraDelRosterOperativo = contexto({
      grupo: grupo({
        cliente: cliente({
          asesor_perfil_id: 'vendedor-ajeno',
          creado_por: 'vendedor-ajeno',
        }),
      }),
      equipo: EQUIPO.filter((persona) => persona.perfil_id !== 'vendedor-ajeno'),
      yoId: 'supervisor-1',
      rol: 'supervisor',
    })
    expect(asesorFueraDelRosterOperativo).toMatchObject({
      asesorNombre: 'No disponible',
      consultable: true,
      operable: false,
    })
  })

  it('Gerencia consulta y opera globalmente, con edición sin ventana del asesor', () => {
    const resultado = contexto({
      grupo: grupo({
        cliente: cliente({
          asesor_perfil_id: 'vendedor-ajeno',
          creado_por: 'vendedor-ajeno',
        }),
      }),
      yoId: 'gerencia-1',
      rol: 'gerencia',
    })
    expect(resultado).toMatchObject({
      consultable: true,
      puedeVerCuentas: true,
      gestionable: true,
      accionable: true,
      operable: true,
      edicionGlobal: true,
    })
  })

  it('Directorio puede abrir la ficha global, pero permanece en solo lectura', () => {
    const resultado = contexto({
      grupo: grupo({
        cliente: cliente({
          asesor_perfil_id: 'vendedor-ajeno',
          creado_por: 'vendedor-ajeno',
        }),
      }),
      yoId: 'directorio-1',
      rol: 'directorio',
    })
    expect(resultado).toMatchObject({
      consultable: true,
      puedeVerCuentas: false,
      gestionable: false,
      accionable: false,
      operable: true,
      motivoNoOperable: null,
      edicionGlobal: false,
    })
  })

  it('mantiene el seguimiento separado de la autoridad para registrar inversiones', () => {
    const resultado = contexto({ puedeContratar: false })
    expect(resultado.consultable).toBe(true)
    expect(resultado.gestionable).toBe(true)
    expect(resultado.accionable).toBe(false)
    expect(resultado.edicionGlobal).toBe(false)
  })

  it('un cliente inactivo sigue siendo consultable, pero no se puede gestionar ni operar', () => {
    const resultado = contexto({
      grupo: grupo({ cliente: cliente({ activo: false }) }),
    })
    expect(resultado).toMatchObject({
      consultable: true,
      puedeVerCuentas: false,
      gestionable: false,
      accionable: false,
      operable: false,
      motivoNoOperable: 'Este cliente está dado de baja. Solicita su reactivación para continuar.',
    })
  })

  it('un asesor inactivo bloquea la operación y lo explica en lenguaje comercial', () => {
    const resultado = contexto({
      equipo: EQUIPO.map((persona) => (persona.perfil_id === 'vendedor-1' ? { ...persona, activo: false } : persona)),
    })
    expect(resultado.consultable).toBe(true)
    expect(resultado.gestionable).toBe(true)
    expect(resultado.accionable).toBe(true)
    expect(resultado.operable).toBe(false)
    expect(resultado.motivoNoOperable).toBe(
      'Este cliente no tiene un asesor disponible. Solicita su asignación para continuar.',
    )
  })

  it('sin asesor asignado, el creador no hereda lectura; solo los roles globales consultan', () => {
    const clienteSinAsesor = grupo({
      cliente: cliente({ asesor_perfil_id: null, creado_por: 'vendedor-1' }),
    })
    const vendedor = contexto({ grupo: clienteSinAsesor })
    const supervisor = contexto({
      grupo: clienteSinAsesor,
      yoId: 'supervisor-1',
      rol: 'supervisor',
    })
    const gerencia = contexto({
      grupo: clienteSinAsesor,
      yoId: 'gerencia-1',
      rol: 'gerencia',
    })
    const directorio = contexto({
      grupo: clienteSinAsesor,
      yoId: 'directorio-1',
      rol: 'directorio',
    })

    expect(vendedor).toMatchObject({ consultable: false, puedeVerCuentas: false, operable: false })
    expect(supervisor).toMatchObject({ consultable: false, puedeVerCuentas: false, operable: false })
    expect(gerencia).toMatchObject({ consultable: true, puedeVerCuentas: true, operable: false })
    expect(directorio).toMatchObject({ consultable: true, puedeVerCuentas: false, operable: false })
  })
})

describe('construirVistaCliente360 — continuidad comercial', () => {
  it('conserva el capital vigente de PEN y USD en importes separados', () => {
    const origen = grupo({
      capitalActivoPen: 12_500.25,
      capitalActivoUsd: 3_750.5,
      contratosActivos: 2,
    })
    const vista = construirVistaCliente360(origen, [], Date.parse('2026-08-25T17:00:00.000Z'))

    expect(vista.capitalVigente).toEqual({ PEN: 12_500.25, USD: 3_750.5 })
    expect(vista.contratosActivos).toBe(2)
    expect(origen.capitalActivoPen).toBe(12_500.25)
    expect(origen.capitalActivoUsd).toBe(3_750.5)
  })

  it('filtra solo tareas pendientes y activas del cliente, las ordena y elige la próxima', () => {
    const entrada = [
      tarea({ id: 'despues', vence_en: '2026-08-26T15:00:00.000Z' }),
      tarea({ id: 'otro-cliente', perfil_id: 'cliente-2', vence_en: '2026-08-23T15:00:00.000Z' }),
      tarea({ id: 'completada', estado: 'completada', vence_en: '2026-08-22T15:00:00.000Z' }),
      tarea({ id: 'inactiva', activo: false, vence_en: '2026-08-21T15:00:00.000Z' }),
      tarea({ id: 'primero', vence_en: '2026-08-25T09:00:00-05:00' }),
      tarea({ id: 'entre-medio', vence_en: '2026-08-25T14:30:00.000Z' }),
    ]
    const ordenOriginal = entrada.map((item) => item.id)
    const vista = construirVistaCliente360(grupo(), entrada, Date.parse('2026-08-25T12:00:00.000Z'))

    expect(vista.tareasPendientes.map((item) => item.id)).toEqual(['primero', 'entre-medio', 'despues'])
    expect(vista.proximaTarea?.id).toBe('primero')
    expect(entrada.map((item) => item.id)).toEqual(ordenOriginal)
  })

  it('descarta una tarea con fecha inválida para que no rompa la ficha', () => {
    const vista = construirVistaCliente360(
      grupo(),
      [
        tarea({ id: 'sin-fecha-valida', vence_en: 'fecha-pendiente-de-corregir' }),
        tarea({ id: 'fecha-valida', vence_en: '2026-08-25T16:00:00.000Z' }),
      ],
      Date.parse('2026-08-25T12:00:00.000Z'),
    )
    expect(vista.tareasPendientes.map((item) => item.id)).toEqual(['fecha-valida'])
    expect(vista.proximaTarea?.id).toBe('fecha-valida')
  })

  it('usa el cambio de día de Lima para habilitar la renovación en el momento correcto', () => {
    const caso = grupo({
      contratos: [contrato({ fecha_vencimiento: '2026-08-26', estado: 'activo' })],
    })
    const antesDeMedianoche = construirVistaCliente360(caso, [], Date.parse('2026-08-26T04:59:59.000Z'))
    const enMedianoche = construirVistaCliente360(caso, [], Date.parse('2026-08-26T05:00:00.000Z'))

    expect(antesDeMedianoche.hoyLima).toBe('2026-08-25')
    expect(antesDeMedianoche.contratos[0]?.renovable).toBe(false)
    expect(enMedianoche.hoyLima).toBe('2026-08-26')
    expect(enMedianoche.contratos[0]?.renovable).toBe(true)
  })

  it('marca cada contrato según fecha final y estado permitido para renovar', () => {
    const vista = construirVistaCliente360(
      grupo({
        contratos: [
          contrato({ id: 'activo-termino', estado: 'activo', fecha_vencimiento: '2026-08-25' }),
          contrato({ id: 'vencido', estado: 'vencido', fecha_vencimiento: '2026-08-24' }),
          contrato({ id: 'activo-futuro', estado: 'activo', fecha_vencimiento: '2026-08-27' }),
          contrato({ id: 'renovado', estado: 'renovado', fecha_vencimiento: '2026-08-24' }),
          contrato({ id: 'retirado', estado: 'retirado', fecha_vencimiento: '2026-08-24' }),
          contrato({ id: 'fecha-invalida', estado: 'activo', fecha_vencimiento: '2026-02-31' }),
        ],
      }),
      [],
      Date.parse('2026-08-26T17:00:00.000Z'),
    )

    expect(Object.fromEntries(vista.contratos.map(({ contrato: item, renovable }) => [item.id, renovable]))).toEqual({
      'activo-termino': true,
      vencido: true,
      'activo-futuro': false,
      renovado: false,
      retirado: false,
      'fecha-invalida': false,
    })
  })

  it('destaca una renovación pendiente cuando el cliente solo tiene un contrato vencido', () => {
    const vista = construirVistaCliente360(
      grupo({
        contratos: [contrato({ estado: 'vencido', fecha_vencimiento: '2026-08-24' })],
        capitalActivoPen: 0,
        capitalActivoUsd: 0,
        contratosActivos: 0,
        tieneCapital: false,
        proximoVencimiento: null,
      }),
      [],
      Date.parse('2026-08-25T17:00:00.000Z'),
    )

    const renovacionPendiente = vista.proximoVencimiento != null && vista.proximoVencimiento <= vista.hoyLima
    expect(vista.proximoVencimiento).toBe('2026-08-24')
    expect(renovacionPendiente).toBe(true)
    expect(vista.contratos[0]?.renovable).toBe(true)
  })
})
