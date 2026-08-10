// Mundo de demostración del gobierno comercial.
//
// Este módulo solo se carga con import() desde crm-config-queries.ts cuando la
// identidad tiene `demo=true`. Así una sesión demo puede recorrer Configuración
// sin Supabase y estos datos ficticios no entran al camino real del CRM.
import type { ConfiguracionMetas, DetalleMeta } from './metas-versionadas'
import type {
  ConfiguracionProductos,
  ProductoCondicionSeleccion,
} from './productos-inversion'
import type { ConfiguracionSla, MetricasSla } from './sla-versionado'
import type { UsuarioAdministrable } from './usuarios-config'

const GENERADO_EN = '2026-08-07T15:30:00.000Z'

const IDS = {
  gerencia: '11000000-0000-4000-8000-000000000001',
  supervisorNorte: '11000000-0000-4000-8000-000000000002',
  supervisorSur: '11000000-0000-4000-8000-000000000003',
  vendedorAna: '11000000-0000-4000-8000-000000000004',
  vendedorBruno: '11000000-0000-4000-8000-000000000005',
  vendedorCarla: '11000000-0000-4000-8000-000000000006',
  vendedorDiego: '11000000-0000-4000-8000-000000000007',
  directorio: '11000000-0000-4000-8000-000000000008',
  candidato: '11000000-0000-4000-8000-000000000009',
  productoCrecimiento: '21000000-0000-4000-8000-000000000001',
  productoFlexible: '21000000-0000-4000-8000-000000000002',
  versionCrecimientoPublicada: '22000000-0000-4000-8000-000000000001',
  versionCrecimientoBorrador: '22000000-0000-4000-8000-000000000002',
  versionFlexiblePublicada: '22000000-0000-4000-8000-000000000003',
  politicaSla: '41000000-0000-4000-8000-000000000001',
} as const

function clonar<T>(valor: T): T {
  return structuredClone(valor)
}

function usuario(
  perfilId: string,
  nombre: string,
  documento: string,
  rol: UsuarioAdministrable['rol_crm'],
  supervisorId: string | null,
  cargo: string,
): UsuarioAdministrable {
  return {
    perfil_id: perfilId,
    nombre_completo: nombre,
    tipo_documento: 'DNI',
    documento,
    correo: `${nombre.toLocaleLowerCase('es-PE').replaceAll(' ', '.')}@demo.avance.test`,
    telefono: '+51 900 000 000',
    whatsapp: '+51 900 000 000',
    cargo,
    tipo_cuenta: 'solo_crm',
    estado: 'activo',
    rol_crm: rol,
    supervisor_id: supervisorId,
    activo_crm: true,
    activo_portal: true,
    version_perfil: GENERADO_EN,
    version_equipo: GENERADO_EN,
    total: 0,
  }
}

const USUARIOS_BASE: UsuarioAdministrable[] = [
  usuario(IDS.gerencia, 'GERENCIA DEMO', '70000001', 'gerencia', null, 'Gerencia comercial'),
  usuario(IDS.supervisorNorte, 'MARÍA SALAZAR', '70000002', 'supervisor', IDS.gerencia, 'Supervisora norte'),
  usuario(IDS.supervisorSur, 'JOSÉ RIVAS', '70000003', 'supervisor', IDS.gerencia, 'Supervisor sur'),
  usuario(IDS.vendedorAna, 'ANA TORRES', '70000004', 'vendedor', IDS.supervisorNorte, 'Asesora de inversión'),
  usuario(IDS.vendedorBruno, 'BRUNO DÍAZ', '70000005', 'vendedor', IDS.supervisorNorte, 'Asesor de inversión'),
  usuario(IDS.vendedorCarla, 'CARLA MENDOZA', '70000006', 'vendedor', IDS.supervisorSur, 'Asesora de inversión'),
  usuario(IDS.vendedorDiego, 'DIEGO RAMOS', '70000007', 'vendedor', IDS.supervisorSur, 'Asesor de inversión'),
  usuario(IDS.directorio, 'DIRECTORIO DEMO', '70000008', 'directorio', null, 'Directorio'),
  {
    ...usuario(IDS.candidato, 'LUCÍA PAREDES', '70000009', null, null, 'Ejecutiva comercial'),
    estado: 'pendiente_rol',
    activo_crm: null,
    version_equipo: null,
  },
]

for (const fila of USUARIOS_BASE) fila.total = USUARIOS_BASE.length

function textoBusqueda(valor: string): string {
  return valor
    .normalize('NFD')
    .replaceAll(/\p{Diacritic}/gu, '')
    .toLocaleLowerCase('es-PE')
}

/** Listado paginado equivalente a la RPC, incluido `total` tras el filtro. */
export function usuariosAdministrablesDemo(
  busqueda = '',
  limite = 50,
  desde = 0,
): UsuarioAdministrable[] {
  const aguja = textoBusqueda(busqueda.trim())
  const filtrados = aguja
    ? USUARIOS_BASE.filter((fila) => textoBusqueda([
      fila.nombre_completo,
      fila.correo ?? '',
      fila.documento ?? '',
    ].join(' ')).includes(aguja))
    : USUARIOS_BASE
  return filtrados
    .slice(Math.max(0, desde), Math.max(0, desde) + Math.max(1, limite))
    .map((fila) => ({ ...fila, total: filtrados.length }))
}

export function catalogoUsuariosAdministrablesDemo(): UsuarioAdministrable[] {
  return USUARIOS_BASE.map((fila) => ({ ...fila, total: USUARIOS_BASE.length }))
}

const CONFIG_PRODUCTOS_BASE = {
  version: 1,
  generado_en: GENERADO_EN,
  puede_administrar: false,
  compatibilidad_altas_legacy: true,
  compatibilidad_revision: 3,
  productos: [
    {
      id: IDS.productoCrecimiento,
      codigo: 'CRECIMIENTO-12',
      estado: 'activo',
      revision: 6,
      creado_por: IDS.gerencia,
      creado_en: '2026-04-01T14:00:00.000Z',
      actualizado_por: IDS.gerencia,
      actualizado_en: GENERADO_EN,
      archivado_por: null,
      archivado_en: null,
      versiones: [
        {
          id: IDS.versionCrecimientoBorrador,
          numero_version: 3,
          estado: 'borrador',
          revision: 2,
          nombre: 'Crecimiento 12 · campaña primavera',
          descripcion: 'Próxima revisión comercial, todavía sin efecto contractual.',
          vigente_desde: '2026-09-01',
          vigente_hasta: null,
          creado_por: IDS.gerencia,
          creado_en: GENERADO_EN,
          actualizado_por: IDS.gerencia,
          actualizado_en: GENERADO_EN,
          publicada_por: null,
          publicada_por_nombre: null,
          publicada_en: null,
          retirada_por: null,
          retirada_en: null,
          condiciones: [
            {
              id: '23000000-0000-4000-8000-000000000001',
              orden: 1,
              categoria: 'nuevo',
              moneda: 'PEN',
              plazo_meses: 12,
              modalidad: 'mensual',
              tipo_interes: 'simple',
              capital_minimo: 10_000,
              capital_maximo: 500_000,
              tasa_referencia: 16,
              tasa_minima: 14,
              tasa_maxima: 18,
              activa: true,
              creado_en: GENERADO_EN,
              retirada_en: null,
            },
          ],
        },
        {
          id: IDS.versionCrecimientoPublicada,
          numero_version: 2,
          estado: 'publicada',
          revision: 4,
          nombre: 'Crecimiento 12 · vigente',
          descripcion: 'Alternativas a doce meses para nuevos aportes y renovaciones.',
          vigente_desde: '2026-07-01',
          vigente_hasta: null,
          creado_por: IDS.gerencia,
          creado_en: '2026-06-20T14:00:00.000Z',
          actualizado_por: IDS.gerencia,
          actualizado_en: '2026-07-01T13:00:00.000Z',
          publicada_por: IDS.gerencia,
          publicada_por_nombre: 'GERENCIA DEMO',
          publicada_en: '2026-07-01T13:00:00.000Z',
          retirada_por: null,
          retirada_en: null,
          condiciones: [
            {
              id: '23000000-0000-4000-8000-000000000002',
              orden: 1,
              categoria: 'nuevo',
              moneda: 'PEN',
              plazo_meses: 12,
              modalidad: 'mensual',
              tipo_interes: 'simple',
              capital_minimo: 10_000,
              capital_maximo: 500_000,
              tasa_referencia: 15,
              tasa_minima: 13,
              tasa_maxima: 17,
              activa: true,
              creado_en: '2026-06-20T14:00:00.000Z',
              retirada_en: null,
            },
            {
              id: '23000000-0000-4000-8000-000000000003',
              orden: 2,
              categoria: 'renovacion',
              moneda: 'PEN',
              plazo_meses: 12,
              modalidad: 'mensual',
              tipo_interes: 'simple',
              capital_minimo: 10_000,
              capital_maximo: 750_000,
              tasa_referencia: 16,
              tasa_minima: 14,
              tasa_maxima: 18,
              activa: true,
              creado_en: '2026-06-20T14:00:00.000Z',
              retirada_en: null,
            },
            {
              id: '23000000-0000-4000-8000-000000000004',
              orden: 3,
              categoria: 'upgrade',
              moneda: 'USD',
              plazo_meses: 12,
              modalidad: 'trimestral',
              tipo_interes: 'simple',
              capital_minimo: 5_000,
              capital_maximo: 200_000,
              tasa_referencia: 11,
              tasa_minima: 9,
              tasa_maxima: 13,
              activa: true,
              creado_en: '2026-06-20T14:00:00.000Z',
              retirada_en: null,
            },
          ],
        },
      ],
    },
    {
      id: IDS.productoFlexible,
      codigo: 'FLEXIBLE-24',
      estado: 'activo',
      revision: 3,
      creado_por: IDS.gerencia,
      creado_en: '2026-05-15T14:00:00.000Z',
      actualizado_por: IDS.gerencia,
      actualizado_en: '2026-07-15T14:00:00.000Z',
      archivado_por: null,
      archivado_en: null,
      versiones: [
        {
          id: IDS.versionFlexiblePublicada,
          numero_version: 1,
          estado: 'publicada',
          revision: 2,
          nombre: 'Flexible 24 · vigente',
          descripcion: 'Plazo de veinticuatro meses con opciones simples y compuestas.',
          vigente_desde: '2026-07-15',
          vigente_hasta: null,
          creado_por: IDS.gerencia,
          creado_en: '2026-07-10T14:00:00.000Z',
          actualizado_por: IDS.gerencia,
          actualizado_en: '2026-07-15T14:00:00.000Z',
          publicada_por: IDS.gerencia,
          publicada_por_nombre: 'GERENCIA DEMO',
          publicada_en: '2026-07-15T14:00:00.000Z',
          retirada_por: null,
          retirada_en: null,
          condiciones: [
            {
              id: '23000000-0000-4000-8000-000000000005',
              orden: 1,
              categoria: 'nuevo',
              moneda: 'USD',
              plazo_meses: 24,
              modalidad: 'anual',
              tipo_interes: 'compuesto',
              capital_minimo: 5_000,
              capital_maximo: 250_000,
              tasa_referencia: 12,
              tasa_minima: 10,
              tasa_maxima: 14,
              activa: true,
              creado_en: '2026-07-10T14:00:00.000Z',
              retirada_en: null,
            },
            {
              id: '23000000-0000-4000-8000-000000000006',
              orden: 2,
              categoria: 'renovacion',
              moneda: 'USD',
              plazo_meses: 24,
              modalidad: 'anual',
              tipo_interes: 'compuesto',
              capital_minimo: 5_000,
              capital_maximo: 350_000,
              tasa_referencia: 13,
              tasa_minima: 11,
              tasa_maxima: 15,
              activa: true,
              creado_en: '2026-07-10T14:00:00.000Z',
              retirada_en: null,
            },
            {
              id: '23000000-0000-4000-8000-000000000007',
              orden: 3,
              categoria: 'upgrade',
              moneda: 'PEN',
              plazo_meses: 24,
              modalidad: 'anual',
              tipo_interes: 'compuesto',
              capital_minimo: 20_000,
              capital_maximo: 1_000_000,
              tasa_referencia: 18,
              tasa_minima: 16,
              tasa_maxima: 20,
              activa: true,
              creado_en: '2026-07-10T14:00:00.000Z',
              retirada_en: null,
            },
          ],
        },
      ],
    },
  ],
} satisfies ConfiguracionProductos

export function configuracionProductosDemo(): ConfiguracionProductos {
  return clonar(CONFIG_PRODUCTOS_BASE)
}

/** El selector sale del mismo catálogo publicado; un borrador nunca se filtra. */
export function productosSeleccionablesDemo(): ProductoCondicionSeleccion[] {
  const filas: ProductoCondicionSeleccion[] = []
  for (const producto of CONFIG_PRODUCTOS_BASE.productos) {
    if (producto.estado !== 'activo') continue
    for (const version of producto.versiones) {
      if (version.estado !== 'publicada') continue
      for (const condicion of version.condiciones) {
        if (!condicion.activa) continue
        filas.push({
          condicion_id: condicion.id,
          producto_id: producto.id,
          producto_codigo: producto.codigo,
          producto_revision: producto.revision,
          version_id: version.id,
          numero_version: version.numero_version,
          version_nombre: version.nombre,
          vigente_desde: version.vigente_desde,
          vigente_hasta: version.vigente_hasta,
          categoria: condicion.categoria,
          moneda: condicion.moneda,
          plazo_meses: condicion.plazo_meses,
          modalidad: condicion.modalidad,
          tipo_interes: condicion.tipo_interes,
          capital_minimo: condicion.capital_minimo,
          capital_maximo: condicion.capital_maximo,
          tasa_referencia: condicion.tasa_referencia,
          tasa_minima: condicion.tasa_minima,
          tasa_maxima: condicion.tasa_maxima,
        })
      }
    }
  }
  return clonar(filas)
}

function detallesMeta(
  capitalPen: readonly [number, number, number],
  capitalUsd: readonly [number, number, number],
  contratos: readonly [number, number, number, number, number, number],
): DetalleMeta[] {
  return [
    { categoria: 'nuevo', moneda: 'PEN', capital_objetivo: capitalPen[0], contratos_objetivo: contratos[0] },
    { categoria: 'nuevo', moneda: 'USD', capital_objetivo: capitalUsd[0], contratos_objetivo: contratos[1] },
    { categoria: 'renovacion', moneda: 'PEN', capital_objetivo: capitalPen[1], contratos_objetivo: contratos[2] },
    { categoria: 'renovacion', moneda: 'USD', capital_objetivo: capitalUsd[1], contratos_objetivo: contratos[3] },
    { categoria: 'upgrade', moneda: 'PEN', capital_objetivo: capitalPen[2], contratos_objetivo: contratos[4] },
    { categoria: 'upgrade', moneda: 'USD', capital_objetivo: capitalUsd[2], contratos_objetivo: contratos[5] },
  ]
}

export function configuracionMetasDemo(periodo: string): ConfiguracionMetas {
  return {
    version: 1,
    periodo,
    // La demo enseña el roster completo y sano: todos con supervisor.
    sin_supervisor: [],
    revision: 5,
    publicada_en: GENERADO_EN,
    publicada_por: IDS.gerencia,
    publicada_por_nombre: 'GERENCIA DEMO',
    puede_editar: false,
    vendedores: [
      {
        vendedor_id: IDS.vendedorAna,
        nombre: 'ANA TORRES',
        supervisor_id: IDS.supervisorNorte,
        supervisor_nombre: 'MARÍA SALAZAR',
        conversion_objetivo: 25,
        detalles: detallesMeta([120_000, 75_000, 45_000], [18_000, 12_000, 8_000], [3, 1, 2, 1, 1, 1]),
      },
      {
        vendedor_id: IDS.vendedorBruno,
        nombre: 'BRUNO DÍAZ',
        supervisor_id: IDS.supervisorNorte,
        supervisor_nombre: 'MARÍA SALAZAR',
        conversion_objetivo: 23,
        detalles: detallesMeta([105_000, 65_000, 35_000], [16_000, 10_000, 7_000], [3, 1, 2, 1, 1, 1]),
      },
      {
        vendedor_id: IDS.vendedorCarla,
        nombre: 'CARLA MENDOZA',
        supervisor_id: IDS.supervisorSur,
        supervisor_nombre: 'JOSÉ RIVAS',
        conversion_objetivo: 24,
        detalles: detallesMeta([110_000, 70_000, 40_000], [17_000, 11_000, 7_500], [3, 1, 2, 1, 1, 1]),
      },
      {
        vendedor_id: IDS.vendedorDiego,
        nombre: 'DIEGO RAMOS',
        supervisor_id: IDS.supervisorSur,
        supervisor_nombre: 'JOSÉ RIVAS',
        conversion_objetivo: 22,
        detalles: detallesMeta([95_000, 60_000, 30_000], [14_000, 9_000, 6_500], [2, 1, 2, 1, 1, 1]),
      },
    ],
  }
}

/** Única política temporal del mundo demo: Config, métricas y leads la comparten. */
export const POLITICA_SLA_DEMO = {
  id: IDS.politicaSla,
  version: 3,
  version_anterior_id: '41000000-0000-4000-8000-000000000000',
  vigente_desde: '2026-08-01T05:00:00.000Z',
  zona_horaria: 'America/Lima',
  tipo_reloj: 'corrido',
  primera_gestion_minutos: 120,
  primer_contacto_minutos: 1_440,
  publicada_por: IDS.gerencia,
  publicada_por_nombre: 'GERENCIA DEMO',
  publicada_en: '2026-07-31T18:00:00.000Z',
  etapas: [
    { etapa: 'nuevo', maximo_minutos: 1_440 },
    { etapa: 'contactado', maximo_minutos: 4_320 },
    { etapa: 'reunion_agendada', maximo_minutos: 7_200 },
    { etapa: 'propuesta_enviada', maximo_minutos: 10_080 },
  ],
} satisfies ConfiguracionSla['politica']

const CONFIG_SLA_BASE = {
  version: 1,
  expected_version: POLITICA_SLA_DEMO.version,
  puede_editar: false,
  politica: POLITICA_SLA_DEMO,
} satisfies ConfiguracionSla

export function configuracionSlaDemo(): ConfiguracionSla {
  return clonar(CONFIG_SLA_BASE)
}

function grupoSla(objetivoMinutos: number, total: number, evaluables: number, cumplidos: number) {
  return {
    politica_id: POLITICA_SLA_DEMO.id,
    politica_version: POLITICA_SLA_DEMO.version,
    objetivo_minutos: objetivoMinutos,
    total,
    evaluables,
    cumplidos,
    fuera_objetivo: evaluables - cumplidos,
    pendientes: total - evaluables,
  }
}

export function metricasSlaDemo(desde: string, hasta: string): MetricasSla {
  const minutosEtapa = Object.fromEntries(
    POLITICA_SLA_DEMO.etapas.map((regla) => [regla.etapa, regla.maximo_minutos]),
  ) as Record<(typeof POLITICA_SLA_DEMO.etapas)[number]['etapa'], number>
  return {
    version: 1,
    generado_en: GENERADO_EN,
    periodo: { desde, hasta, zona: 'America/Lima' },
    ciclos: {
      primera_gestion: [grupoSla(POLITICA_SLA_DEMO.primera_gestion_minutos, 48, 44, 38)],
      primer_contacto: [grupoSla(POLITICA_SLA_DEMO.primer_contacto_minutos, 48, 39, 31)],
    },
    asignaciones: {
      primera_gestion: [grupoSla(POLITICA_SLA_DEMO.primera_gestion_minutos, 55, 51, 43)],
      primer_contacto: [grupoSla(POLITICA_SLA_DEMO.primer_contacto_minutos, 55, 46, 35)],
    },
    etapas: [
      { ...grupoSla(minutosEtapa.nuevo, 48, 43, 36), etapa: 'nuevo' },
      { ...grupoSla(minutosEtapa.contactado, 37, 32, 27), etapa: 'contactado' },
      { ...grupoSla(minutosEtapa.reunion_agendada, 24, 20, 18), etapa: 'reunion_agendada' },
      { ...grupoSla(minutosEtapa.propuesta_enviada, 15, 11, 9), etapa: 'propuesta_enviada' },
    ],
  }
}
