import { useState } from 'react'
import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
import { Tabs } from '@/components/ui/tabs'
import { EstadoCortesEquipo } from './estado-cortes-equipo'
import { MiembrosAvisoCorte } from './miembros-aviso-corte'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { tituloCorte, horaCorte } from '@/lib/gestion-diaria-avisos'
import { Button } from '@/components/ui/button'
import { AccionesCorte } from './acciones-corte'
import { AlertasDelDia } from './alertas-del-dia'

export function AvisosEquipo({ consulta, abrirAnalista, alNavegar }: {
  consulta?: DiaEquipoHook; abrirAnalista?: (id: string) => void; alNavegar?: () => void
}) {
  const contexto = useGestionDiariaAvisos()
  const [pestana, setPestana] = useState<'cortes' | 'otros'>('cortes')
  const datos = contexto?.datos
  return <Tabs etiqueta="Tipo de aviso" tamano="grande" valor={pestana} onCambio={setPestana}
    pestanas={[{ valor: 'cortes', etiqueta: 'Cortes' }, { valor: 'otros', etiqueta: 'Otros pendientes' }]}>
    <div hidden={pestana !== 'cortes'} className="space-y-4 text-base">
      {consulta && abrirAnalista && <EstadoCortesEquipo consulta={consulta} abrirAnalista={abrirAnalista} />}
      <section aria-label="Avisos de cortes del equipo" className="space-y-3">
        <h3 className="text-lg font-semibold text-primary">Avisos de cortes</h3>
        {!contexto ? <p>Los avisos no están disponibles en esta sesión.</p>
          : contexto.error ? <div role="alert" className="space-y-3">
            <p>No pudimos confirmar los avisos de cortes. Esto no significa que no haya pendientes.</p>
            <Button variant="outline" className="min-h-11 text-base" onClick={contexto.recargar}>Actualizar avisos</Button>
          </div> : contexto.cargando ? <p role="status">Consultando los avisos del equipo…</p>
            : !datos ? <p>Los avisos no están disponibles en esta sesión.</p>
              : <>
                {contexto.errorPresentacion != null && <div role="status" className="space-y-3 rounded-xl border border-border p-3">
                  <p>No se pudo abrir el aviso emergente. Puedes atender los pendientes desde esta lista.</p>
                  <Button variant="outline" className="min-h-11 text-base" onClick={contexto.recargar}>Actualizar avisos</Button>
                </div>}
                {!datos.avisos_habilitados && <p role="status">Gerencia ha pausado los avisos. Los resultados y pendientes siguen visibles.</p>}
                {datos.estado_cortes === 'desactivados' ? <p>Los avisos de cortes están desactivados para esta jornada.</p>
                  : datos.estado_cortes === 'no_laborable' ? <p>Hoy no hay avisos de cortes por jornada no laborable.</p>
                    : datos.alertas.length === 0 ? <p>No hay cortes con pendientes al momento de la consulta. Los cortes futuros todavía no se evalúan.</p>
                      : datos.alertas.map((aviso) => <article key={aviso.id} aria-label={tituloCorte(aviso)} className="space-y-3 rounded-lg border border-border p-3">
                        <h4 className="font-semibold">{tituloCorte(aviso)} · {horaCorte(aviso.corte_en)} Lima</h4>
                        <MiembrosAvisoCorte aviso={aviso} />
                        <AccionesCorte aviso={aviso} />
                      </article>)}
                <p className="text-[var(--muted-foreground-strong)]">Consulta de avisos: {horaCorte(datos.generado_en)} Lima. Se revisa cada minuto mientras el CRM está abierto. Reconocer o posponer no borra el resultado del corte.</p>
              </>}
      </section>
    </div>
    <div hidden={pestana !== 'otros'}><AlertasDelDia alNavegar={alNavegar} /></div>
  </Tabs>
}
