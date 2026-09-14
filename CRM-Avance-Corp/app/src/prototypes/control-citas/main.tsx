import { StrictMode, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { Target } from 'lucide-react'
import '@/index.css'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { Sidebar } from '@/components/app/sidebar'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { ControlCitasEditor } from '@/components/config/control-citas-editor'
import { validarConsultaControlCitas, type ConsultaControlCitas, type GuardarControlCitasInput } from '@/lib/control-citas'

const CLAVE = 'avancecorp-control-citas-prueba-v1'
const vacia: ConsultaControlCitas = { version_actual: 0, ultimo: null, historial: [] }
const identidad: AuthContextValue = {
  fase: 'listo', error: null,
  yo: { id: '90000000-0000-4000-8000-000000000001', nombre_completo: 'SUPERADMIN', rol: 'directorio', rol_portal: 'superadmin', demo: true, puede_contratar: false },
  entrar: async () => ({ ok: false }), entrarDemo: () => {}, reintentar: () => {}, salir: async () => {},
}
export function Vista() {
  const [consulta, setConsulta] = useState(() => {
    try { return validarConsultaControlCitas(JSON.parse(sessionStorage.getItem(CLAVE) ?? 'null')) ?? vacia } catch { return vacia }
  })
  async function guardar(input: GuardarControlCitasInput): Promise<ConsultaControlCitas> {
    const ultimo = { version: consulta.version_actual + 1, configuracion: input.configuracion,
      guardado_por: identidad.yo!.id, guardado_en: new Date().toISOString(), estado: 'borrador' as const, nota: input.nota || null }
    const siguiente = { version_actual: ultimo.version, ultimo, historial: [ultimo, ...consulta.historial].slice(0, 20) }
    sessionStorage.setItem(CLAVE, JSON.stringify(siguiente))
    setConsulta(siguiente)
    return siguiente
  }
  return <AuthContext.Provider value={identidad}>
    <div className="flex min-h-svh bg-background">
      <div className="hidden md:block"><Sidebar vista="config-citas" onNavegar={vista => { if (vista !== 'config-citas') window.location.assign(`/#/${vista}`) }} /></div>
      <main className="min-w-0 flex-1 p-4 md:p-7">
        <p className="mx-auto mb-4 max-w-[1240px] text-xs text-muted-foreground">Vista local de prueba. Los borradores se guardan solo en esta pestaña.</p>
        <ConfiguracionShell icono={Target} titulo="Control de Citas" soloLectura={false} volverA="config-usuarios"
          descripcion="Prepara las metas y reglas de gestión. Completa las decisiones pendientes antes de aplicarlas al tablero."
          estado={{ etiqueta: 'En preparación', detalle: 'Administración exclusiva de Superadmin' }}>
          <ControlCitasEditor consulta={consulta} guardar={guardar} practica />
        </ConfiguracionShell>
      </main>
    </div>
  </AuthContext.Provider>
}
createRoot(document.getElementById('root')!).render(<StrictMode><Vista /></StrictMode>)
