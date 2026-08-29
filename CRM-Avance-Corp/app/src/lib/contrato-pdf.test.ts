import { describe, expect, it } from 'vitest'
import { construirContratoPdf, nombreArchivoContrato, type ContratoPdfDatos } from './contrato-pdf'

const DATOS: ContratoPdfDatos = {
  contrato: {
    numero: '2026-01-000903',
    capital: 80_000,
    moneda: 'PEN',
    porcentaje: 10,
    fechaInicio: '2026-01-15',
    fechaVencimiento: '2027-01-15',
  },
  titular: {
    nombreCompleto: 'GLADYS PILAR YUPANQUI ROJAS',
    tipoDocumento: 'DNI',
    documento: '40928175',
    domicilio: 'Av. Los Laureles 456, San Isidro, Lima',
    correo: 'gladys.yupanqui@correo.pe',
  },
  analista: {
    nombreCompleto: 'ANALISTA UNO',
    documento: '10000001',
    celular: '+51 987 654 321',
    correo: 'analista.uno@avancecorp.pe',
  },
  cotitulares: [
    {
      nombreCompleto: 'CÉSAR AUGUSTO ROMERO DELGADO',
      tipoDocumento: 'DNI',
      documento: '41563209',
    },
  ],
}

function todosLosTextos(valor: unknown): string {
  if (typeof valor === 'string') return valor
  if (Array.isArray(valor)) return valor.map(todosLosTextos).join(' ')
  if (valor && typeof valor === 'object') {
    return Object.values(valor as Record<string, unknown>).map(todosLosTextos).join(' ')
  }
  return ''
}

describe('contrato PDF legal', () => {
  it('usa el número CRM en el nombre del archivo', () => {
    expect(nombreArchivoContrato(DATOS)).toBe(
      'Contrato-2026-01-000903-GLADYS-PILAR-YUPANQUI-ROJAS.pdf',
    )
  })

  it('construye las 17 cláusulas con los datos variables del titular y excluye cotitulares', () => {
    const definicion = construirContratoPdf(DATOS, {
      fondo: 'data:image/png;base64,FONDO',
      firmaAsociante: 'data:image/png;base64,FIRMA',
    })
    const texto = todosLosTextos(definicion)

    expect(texto).toContain('2026-01-000903')
    expect(texto).toContain('GLADYS PILAR YUPANQUI ROJAS')
    expect(texto).toContain('DNI N.° 40928175')
    expect(texto).toContain('Av. Los Laureles 456, San Isidro, Lima')
    expect(texto).toContain('S/ 80,000.00')
    expect(texto).toContain('OCHENTA MIL Y 00/100 SOLES')
    expect(texto).toContain('diez por ciento (10.00 %)')
    expect(texto).toContain('ANALISTA UNO')
    expect(texto).toContain('DÉCIMA SÉTIMA: DECLARACIÓN FINAL DE LAS PARTES')
    expect(texto).not.toContain('CÉSAR AUGUSTO ROMERO DELGADO')
  })

  it('adapta la identificación cuando el titular usa Carné de Extranjería', () => {
    const definicion = construirContratoPdf({
      ...DATOS,
      titular: {
        ...DATOS.titular,
        tipoDocumento: 'CE',
        documento: '001987654',
      },
    }, {
      fondo: 'data:image/png;base64,FONDO',
      firmaAsociante: 'data:image/png;base64,FIRMA',
    })

    expect(todosLosTextos(definicion)).toContain(
      'Carné de Extranjería N.° 001987654',
    )
  })

  it('no añade títulos ni referencias que no existen en la zona de firmas original', () => {
    const definicion = construirContratoPdf(DATOS, {
      fondo: 'data:image/png;base64,FONDO',
      firmaAsociante: 'data:image/png;base64,FIRMA',
    })
    const texto = todosLosTextos(definicion)

    expect(texto).not.toContain('FIRMAS DE CONFORMIDAD')
    expect(texto).not.toContain('Contrato de Asociación en Participación N.° 2026-01-000903')
  })

  it('inicia la página final con la cláusula décima séptima y mantiene las firmas a continuación', () => {
    const definicion = construirContratoPdf(DATOS, {
      fondo: 'data:image/png;base64,FONDO',
      firmaAsociante: 'data:image/png;base64,FIRMA',
    })
    const contenido = definicion.content as unknown as Array<Record<string, unknown>>
    const declaracionFinal = contenido.find(
      (nodo) => nodo.text === 'DÉCIMA SÉTIMA: DECLARACIÓN FINAL DE LAS PARTES',
    )
    const firmas = contenido.find((nodo) => Array.isArray(nodo.columns))

    expect(declaracionFinal).toMatchObject({ pageBreak: 'before' })
    expect(firmas).not.toHaveProperty('pageBreak')
  })

  it('mantiene completas las filas de la tabla de liquidación al cambiar de página', () => {
    const definicion = construirContratoPdf(DATOS, {
      fondo: 'data:image/png;base64,FONDO',
      firmaAsociante: 'data:image/png;base64,FIRMA',
    })
    const contenido = definicion.content as unknown as Array<Record<string, unknown>>
    const tablaLiquidacion = contenido.find((nodo) => {
      const tabla = nodo.table as { body?: unknown[][] } | undefined
      return tabla?.body?.[0]?.some((celda) => (
        typeof celda === 'object'
        && celda !== null
        && (celda as { text?: unknown }).text === 'Hito'
      ))
    })

    expect(tablaLiquidacion?.table).toMatchObject({
      headerRows: 1,
      dontBreakRows: true,
    })
  })

  it('ancla el fondo al lienzo para no recortar el encabezado en páginas continuadas', () => {
    const definicion = construirContratoPdf(DATOS, {
      fondo: 'data:image/png;base64,FONDO',
      firmaAsociante: 'data:image/png;base64,FIRMA',
    })
    const background = definicion.background as unknown as () => Record<string, unknown>

    expect(background()).toMatchObject({
      image: 'data:image/png;base64,FONDO',
      absolutePosition: { x: 0, y: 0 },
    })
  })
})
