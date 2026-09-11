import { useState } from 'react'
import { Building2, CalendarClock, CheckCircle2, CircleAlert, Eye, RefreshCw, TrendingUp, Users } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { KpiCard } from '@/components/common/kpi-card'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { money, numero, porcentajeConversionCanonica, fmtFecha, fechaHora } from '@/lib/format'
import { CrmApiError } from '@/data/crm-api'
import { useMetricasMultiempresa } from '@/data/metricas-multiempresa'
import { metricasMultiempresaDemo } from '@/lib/demo-metricas-multiempresa'
import { EMPRESA_INFORME, TIPO_CAPITAL, estadoConciliacion, type MetricasMultiempresa } from '@/lib/metricas-multiempresa'

export function MetricasMultiempresa() {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  const [mes, setMes] = useState(() => `${hoy.slice(0, 7)}-01`)
  const demo = yo?.demo === true
  const { estado, informe } = useMetricasMultiempresa(yo?.id ?? '', yo?.rol === 'gerencia' && !demo, mes)
  const refrescar = () => { void estado.refetch(); if (estado.data?.habilitada) void informe.refetch() }
  const error = estado.error ?? informe.error
  const cerrado = error instanceof CrmApiError && error.code === '42501'
  const enPreparacion = error instanceof CrmApiError && error.code === 'P0409'
  let contenido
  if (yo?.rol !== 'gerencia' || (!demo && cerrado)) {
    contenido = <PanelVacio icono={Eye} titulo="Informe no disponible" detalle="Tu acceso actual no permite consultar este informe." />
  } else if (demo) {
    contenido = <ContenidoInforme datos={metricasMultiempresaDemo(mes, hoy)} />
  } else if (enPreparacion) {
    contenido = <PanelVacio icono={Building2} titulo="Informe en preparación" detalle="La vista por empresa estará disponible después de completar su revisión." />
  } else if (error) {
    contenido = <PanelError mensaje="No se pudo actualizar el informe." onReintentar={refrescar} reintentando={estado.isFetching || informe.isFetching} />
  } else if (estado.isPending) {
    contenido = <PanelCargando />
  } else if (!estado.data?.habilitada) {
    contenido = <PanelVacio icono={Building2} titulo="Informe en preparación" detalle="La vista por empresa estará disponible después de completar su revisión." />
  } else if (!informe.data) {
    contenido = <PanelCargando />
  } else {
    contenido = <ContenidoInforme datos={informe.data} />
  }
  return <div className="space-y-4 pb-6">
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div>
        <Badge variant="outline">Vista previa</Badge>
        <p className="mt-2 text-sm text-muted-foreground">Capital e inversionistas por empresa. Las comisiones se calculan fuera del CRM.</p>
      </div>
      <div className="flex flex-wrap items-end gap-2">
        <label className="text-xs font-semibold">Mes de producción
          <Input aria-label="Mes de producción" type="month" min="2000-01" max={hoy.slice(0, 7)} value={mes.slice(0, 7)}
            onChange={e => { if (/^\d{4}-(0[1-9]|1[0-2])$/.test(e.target.value) && e.target.value >= '2000-01' && e.target.value <= hoy.slice(0, 7)) setMes(`${e.target.value}-01`) }} className="mt-1" />
        </label>
        {!demo && <Button variant="outline" disabled={estado.isFetching || informe.isFetching} onClick={refrescar}><RefreshCw aria-hidden /> Actualizar</Button>}
      </div>
    </div>
    {demo && <p role="status" className="rounded-xl border border-border bg-muted/50 p-3 text-sm">Demostración: todas estas cifras son ficticias.</p>}
    {contenido}
  </div>
}

function TablaCapital({ titulo, filas }: {
  titulo: string
  filas: MetricasMultiempresa['vencimientos']
}) {
  return <TablaEnvoltura ariaLabel={titulo}>
    <TheadCrm><Th>Empresa</Th><Th>Moneda</Th><Th className="text-right">Inversiones</Th><Th className="text-right">Capital</Th></TheadCrm>
    <tbody>{filas.map(r => <tr key={`${r.empresa}:${r.moneda}`} className="border-b border-border/60">
      <Td className="font-semibold">{EMPRESA_INFORME[r.empresa]}</Td><Td>{r.moneda}</Td>
      <Td className="text-right tabular-nums">{r.operaciones}</Td><Td className="text-right font-semibold tabular-nums">{money(r.capital, r.moneda)}</Td>
    </tr>)}{!filas.length && <tr><Td colSpan={4} className="py-6 text-center text-muted-foreground">Sin movimientos para esta selección.</Td></tr>}</tbody>
  </TablaEnvoltura>
}

/** Solo presentación: recibe las cantidades agrupadas y conciliadas por SQL. */
export function ContenidoInforme({ datos: d }: { datos: MetricasMultiempresa }) {
  const [moneda, setMoneda] = useState('todas')
  const incluye = (r: { moneda: string }) => moneda === 'todas' || r.moneda === moneda
  const personas = d.personas
  const conciliacion = estadoConciliacion(d)
  return <div className="space-y-4">
    {d.mes_sellado && <p role="status" className="rounded-xl border border-border bg-muted/50 p-3 text-sm">
      Este mes ya está cerrado. El desglose de esta vista previa usa la información disponible hoy; el cierre firmado conserva sus cifras originales.
    </p>}
    <Card className="overflow-hidden">
      <SectionHead icon={Building2} title="Capital de las inversiones del mes" right={<label className="sr-only" htmlFor="moneda-informe">Moneda</label>} />
      <div className="flex flex-wrap items-center justify-between gap-3 px-5 pb-3">
        <p className="max-w-2xl text-xs text-muted-foreground">Del {fmtFecha(d.mes)} al {fmtFecha(d.hasta)}. Incluye capital completo de renovaciones y upgrades; cada empresa y moneda conserva su propio importe.</p>
        <div className="w-full shrink-0 sm:w-48"><Select id="moneda-informe" value={moneda} onChange={e => setMoneda(e.target.value)}><option value="todas">Todas las monedas</option><option value="PEN">Soles · PEN</option><option value="USD">Dólares · USD</option></Select></div>
      </div>
      <TablaCapital titulo="Capital por empresa y moneda" filas={d.produccion.filter(incluye)} />
      <details className="border-t border-border">
        <summary className="cursor-pointer px-5 py-3 text-sm font-semibold focus-visible:outline focus-visible:outline-2">Ver contratos nuevos, renovaciones y upgrades</summary>
        <TablaEnvoltura ariaLabel="Tipos de capital"><TheadCrm><Th>Empresa</Th><Th>Tipo</Th><Th>Moneda</Th><Th className="text-right">Inversiones</Th><Th className="text-right">Capital</Th></TheadCrm>
          <tbody>{d.tipos_capital.filter(incluye).map(r => <tr key={`${r.empresa}:${r.moneda}:${r.tipo_capital}`}><Td>{EMPRESA_INFORME[r.empresa]}</Td><Td>{TIPO_CAPITAL[r.tipo_capital] ?? r.tipo_capital}</Td><Td>{r.moneda}</Td><Td className="text-right">{r.operaciones}</Td><Td className="text-right tabular-nums">{money(r.capital, r.moneda)}</Td></tr>)}</tbody>
        </TablaEnvoltura>
      </details>
    </Card>
    <Card className="overflow-hidden">
      <SectionHead icon={TrendingUp} title="Primera registrada e inversiones posteriores" />
      <p className="px-5 pb-3 text-xs text-muted-foreground">Historia conocida del titular principal en el grupo. Estas cantidades no determinan la conversión comercial.</p>
      <TablaEnvoltura ariaLabel="Inversiones primeras y posteriores"><TheadCrm><Th>Empresa</Th><Th>Moneda</Th><Th className="text-right">Primera registrada</Th><Th className="text-right">Posterior</Th><Th className="text-right">Sin identidad</Th></TheadCrm>
        <tbody>{d.produccion.filter(incluye).map(r => <tr key={`${r.empresa}:${r.moneda}`}><Td>{EMPRESA_INFORME[r.empresa]}</Td><Td>{r.moneda}</Td><Td className="text-right">{r.primeras}</Td><Td className="text-right">{r.posteriores}</Td><Td className="text-right">{r.sin_identidad}</Td></tr>)}</tbody>
      </TablaEnvoltura>
    </Card>
    <div>
      <h2 className="text-base font-bold">Inversionistas en el grupo</h2>
      <p className="mt-1 mb-3 text-xs text-muted-foreground">Historia conocida al {fmtFecha(d.hoy)}, independiente del mes y la moneda seleccionados. Incluye titulares y cotitulares, una sola vez por persona.</p>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {[['Personas identificadas', personas.total], ['En una empresa', personas.una_empresa], ['En dos empresas', personas.dos_empresas], ['En tres empresas', personas.tres_empresas]].map(([label, value]) =>
          <KpiCard key={label} label={String(label)} value={String(value)} icon={Users} color="var(--primary)" />)}
      </div>
      {personas.fuentes_sin_identidad > 0 && <p role="status" className="mt-3 rounded-xl border border-border p-3 text-sm"><CircleAlert className="mr-2 inline size-4" aria-hidden />
        {personas.fuentes_sin_identidad} inversiones necesitan revisar su identidad. Su capital está incluido; las cantidades de personas y primeras inversiones aún pueden variar.
      </p>}
    </div>
    <div className="grid gap-4 xl:grid-cols-2">
      <Card className="overflow-hidden"><SectionHead icon={Users} title="Presencia y oportunidades por empresa" />
        <TablaEnvoltura ariaLabel="Presencia por empresa"><TheadCrm><Th>Empresa</Th><Th className="text-right">Personas</Th><Th className="text-right">Por explorar</Th></TheadCrm>
          <tbody>{d.oportunidades.map(r => <tr key={r.empresa}><Td>{EMPRESA_INFORME[r.empresa]}</Td><Td className="text-right">{personas.por_empresa.find(p => p.empresa === r.empresa)?.personas ?? 0}</Td><Td className="text-right">{r.personas}</Td></tr>)}</tbody>
        </TablaEnvoltura><p className="p-5 text-xs text-muted-foreground">Por explorar: personas de otra empresa sin inversión conocida aquí, disponibles para evaluar una propuesta. Excluye quienes no desean ser contactados.</p>
      </Card>
      <Card className="overflow-hidden"><SectionHead icon={CalendarClock} title="Próximos vencimientos · 30 días" />
        <TablaCapital titulo="Próximos vencimientos" filas={d.vencimientos.filter(incluye)} />
        <p className="p-5 text-xs text-muted-foreground">Desde {fmtFecha(d.hoy)}. Capital contractual vigente, sin intereses estimados. El mes de producción no cambia esta ventana.</p>
      </Card>
    </div>
    <Card><SectionHead icon={TrendingUp} title="Conversión comercial del mes" />
      <div className="grid gap-4 px-5 pb-4 sm:grid-cols-3">
        <div><p className="text-xs text-muted-foreground">Conversión global</p><p className="text-2xl font-bold text-primary">{d.conversion.tasa_pct === null ? 'Sin base de cálculo' : porcentajeConversionCanonica(d.conversion.tasa_pct)}</p></div>
        <div><p className="text-xs text-muted-foreground">Llegadas elegibles</p><p className="text-2xl font-bold">{d.conversion.divisor}</p></div>
        <div><p className="text-xs text-muted-foreground">Aporte comercial</p><p className="text-2xl font-bold">{numero(d.conversion.numerador, 2)}</p></div>
      </div>
      <p className="px-5 pb-4 text-xs text-muted-foreground">{d.conversion.renovaciones} renovaciones y {d.conversion.upgrades} upgrades elegibles. Se conservan las reglas de leads y operaciones del CRM; no se deduplican por identidad ni se crea una tasa por empresa.</p>
    </Card>
    <Card className="overflow-hidden"><SectionHead icon={Users} title="Atribución del capital del mes" />
      <TablaEnvoltura ariaLabel="Atribución por operación"><TheadCrm><Th>Analista atribuido</Th><Th>Empresa</Th><Th>Moneda</Th><Th className="text-right">Inversiones</Th><Th className="text-right">Capital</Th></TheadCrm>
        <tbody>{d.atribucion.filter(incluye).map(r => <tr key={`${r.empresa}:${r.moneda}:${r.analista_id}`}><Td>{r.analista_nombre ?? (r.analista_id ? 'Analista sin nombre disponible' : 'Sin analista atribuido')}</Td><Td>{EMPRESA_INFORME[r.empresa]}</Td><Td>{r.moneda}</Td><Td className="text-right">{r.operaciones}</Td><Td className="text-right tabular-nums">{money(r.capital, r.moneda)}</Td></tr>)}</tbody>
      </TablaEnvoltura><p className="p-5 text-xs text-muted-foreground">La atribución corresponde a la operación y su cadena comercial. Cambiar el responsable de la persona no la reasigna.</p>
    </Card>
    <Card><SectionHead icon={conciliacion === 'diferencias' ? CircleAlert : CheckCircle2} title="Comprobación de cifras" />
      <p role="status" className="px-5 pb-3 text-sm">{conciliacion === 'coincide' ? 'Capital, cantidad y atribución coinciden con las fuentes del CRM.' : conciliacion === 'diferencias' ? 'Hay diferencias que requieren revisión antes de aceptar el informe.' : 'No hay movimientos con los que comprobar este mes.'}</p>
      {d.fuentes_duplicadas > 0 && <p role="alert" className="px-5 pb-3 text-sm">{d.fuentes_duplicadas} {d.fuentes_duplicadas === 1 ? 'inversión aparece repetida' : 'inversiones aparecen repetidas'} en las fuentes. Es necesario revisar antes de aceptar las cifras.</p>}
      <details className="border-t border-border">
        <summary className="cursor-pointer px-5 py-3 text-sm font-semibold focus-visible:outline focus-visible:outline-2">Ver detalle de la comparación</summary>
        <TablaEnvoltura ariaLabel="Comparación de cifras"><TheadCrm><Th>Empresa</Th><Th>Moneda</Th><Th className="text-right">Capital del CRM</Th><Th className="text-right">Capital del informe</Th><Th className="text-right">Diferencia de capital</Th><Th className="text-right">Diferencia de inversiones</Th><Th className="text-right">Diferencia de atribución</Th></TheadCrm>
          <tbody>{d.conciliacion.filter(incluye).map(r => <tr key={`${r.empresa}:${r.moneda}`}><Td>{EMPRESA_INFORME[r.empresa]}</Td><Td>{r.moneda}</Td><Td className="text-right tabular-nums">{money(r.capital_nucleo, r.moneda)}</Td><Td className="text-right tabular-nums">{money(r.capital_informe, r.moneda)}</Td><Td className="text-right tabular-nums">{money(r.diferencia_capital, r.moneda)}</Td><Td className="text-right">{r.diferencia_operaciones}</Td><Td className="text-right tabular-nums">{money(r.diferencia_atribucion, r.moneda)}</Td></tr>)}</tbody>
        </TablaEnvoltura>
      </details>
      <p className="px-5 pb-4 text-xs text-muted-foreground">Esta comprobación automática no reemplaza la revisión y firma de conciliación.</p>
    </Card>
    <p className="text-right text-xs text-muted-foreground">Consulta actualizada: {fechaHora(d.generado_en)}</p>
  </div>
}
