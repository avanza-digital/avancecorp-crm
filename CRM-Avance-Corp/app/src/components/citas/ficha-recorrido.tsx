import { useDatosCitas, horaLima } from './contexto'
import { ExternalLink, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { capitalLead, fmtFecha, money } from '@/lib/format'
import type { CitaConLead, Recuperacion } from './datos'
import { asistioTrasInasistencia, type DepositoEjemplo } from './depositos'

export function FichaRecorrido({ fila, depositos, citas, onCerrar, onCita }: {
  fila: Recuperacion | null
  depositos: DepositoEjemplo[]
  citas: CitaConLead[]
  onCerrar: () => void
  onCita: (cita: CitaConLead) => void
}) {
  const { corte: CORTE, nombreAnalista, depositosDisponibles } = useDatosCitas()
  const cantidad = citas.filter(cita => cita.leadId === fila?.original.leadId).length
  return <Sheet open={Boolean(fila)} onClose={onCerrar} className="gerencia-inteligencia citas-crm-dialogo citas-ficha-recorrido">
    <SheetHeader className="citas-ficha-cabecera">
      <div className="flex items-start justify-between gap-3">
        <div><SheetTitle className="text-xl">{fila?.original.nombre ?? 'Recorrido del lead'}</SheetTitle>
          {fila && <p className="mt-2 text-sm text-muted-foreground-strong">{nombreAnalista(fila.original.analista)} · {fila.original.leadId}</p>}
        </div>
        <Button variant="ghost" size="icon" aria-label="Cerrar recorrido" onClick={onCerrar}><X aria-hidden /></Button>
      </div>
    </SheetHeader>
    {fila && <SheetBody className="citas-ficha-cuerpo">
      <section aria-label="Citas del lead" className="pb-6">
        <p className="text-lg font-semibold tabular-nums">{cantidad} {cantidad === 1 ? 'cita' : 'citas'} en la consulta</p>
      </section>
      <h3 className="border-t border-border pt-5 text-base font-semibold">Su recorrido</h3>
      <p className="citas-nota">Incluye seguimiento fuera del período · horas de Lima.</p>
      <ol className="citas-recorrido-persona" aria-label="Recorrido de la persona">
        <li><h4>No asistió</h4><p>{fmtFecha(fila.original.fecha)} · {fila.original.hora} Lima</p></li>
        {fila.recorrido.map(cita => <li key={cita.id}>
          <h4>Reprogramó</h4><p>Registro: {fmtFecha(cita.reprogramadaEn!)} · {horaLima(cita.reprogramadaEn!)}</p>
          <p>Nueva cita: {fmtFecha(cita.fecha)} · {cita.hora}</p>
          {asistioTrasInasistencia(fila.original, cita, CORTE)
            ? <div className="mt-4"><h4>Asistió</h4><p>{fmtFecha(cita.asistioEn!)} · {horaLima(cita.asistioEn!)} Lima</p></div>
            : <p className="mt-2 text-xs">{cita.estado === 'no_show' ? 'Volvió a faltar a esta cita' : ['cancelada', 'sistema'].includes(cita.estado) ? 'Cita cancelada' : Date.parse(`${cita.fecha}T${cita.hora}:00-05:00`) > Date.parse(CORTE) ? 'Asistencia pendiente' : 'Sin asistencia registrada al corte'}</p>}
        </li>)}
        {!fila.nueva && <li><h4 className="text-warning-text">Sin nueva cita</h4><p>No hay una reprogramación vinculada al corte.</p></li>}
        {depositos.map(deposito => <li key={deposito.id}>
          <h4>Depositó</h4>{deposito.fuente==='conversion_cliente'
            ? <><p>Convertido a cliente</p><p>Fecha de conversión: {fmtFecha(deposito.depositadoEn)} · {horaLima(deposito.depositadoEn)} Lima</p></>
            : <><p>{money(deposito.monto, deposito.moneda)} · {fmtFecha(deposito.depositadoEn)} · {horaLima(deposito.depositadoEn)}</p><p>Confirmado: {fmtFecha(deposito.confirmadoEn!)} · {horaLima(deposito.confirmadoEn!)} Lima</p></>}
          <p className="mt-2 text-xs">{deposito.id}</p>
        </li>)}
      </ol>
      {depositos.length === 0 && <p className="mb-6 text-xs text-muted-foreground-strong">{depositosDisponibles ? 'Sin depósito confirmado dentro de este flujo de recuperación.' : 'La fuente de depósitos aún no está habilitada para esta consulta.'}</p>}
      <Button variant="accent" className="h-11 w-full" onClick={() => onCita(fila.nueva ?? fila.original)}><ExternalLink aria-hidden />Ver cita vinculada</Button>
      <details className="citas-info-persona mt-3">
        <summary>Información del prospecto</summary>
        <dl className="space-y-3 py-3 text-sm">
          <div><dt>Teléfono</dt><dd>{fila.original.telefono}</dd></div>
          <div><dt>Origen</dt><dd>{fila.original.origen}</dd></div>
          <div><dt>Monto estimado</dt><dd>{capitalLead(fila.original.monto, fila.original.moneda)}</dd></div>
          <div><dt>Contexto de la cita original</dt><dd>{fila.original.nota}</dd></div>
        </dl>
      </details>
    </SheetBody>}
  </Sheet>
}
