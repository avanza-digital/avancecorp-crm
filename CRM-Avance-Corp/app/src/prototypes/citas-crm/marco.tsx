import { Sidebar } from '@/components/app/sidebar'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { hashDe, type Vista } from '@/lib/router'

const volverAlCRM = () => window.location.assign('/')

// Solo proporciona la identidad visual al menú compartido. No inicia sesión,
// monta AuthProvider ni accede a datos o acciones del CRM.
const identidadEjemplo: AuthContextValue = {
  fase: 'listo',
  yo: { id: 'citas-prototipo', nombre_completo: 'GERENCIA DEMO', rol: 'gerencia', demo: true, puede_contratar: false },
  error: null,
  entrar: async () => ({ ok: false, error: 'Vista previa con datos de ejemplo' }),
  entrarDemo: volverAlCRM,
  reintentar: volverAlCRM,
  salir: async () => volverAlCRM(),
}

export function MenuCRM() {
  function navegar(vista: Vista) {
    if (vista === 'reuniones') {
      document.getElementById('consulta-citas')?.focus()
      return
    }
    window.location.assign('/' + hashDe(vista))
  }
  return <AuthContext value={identidadEjemplo}><Sidebar vista="reuniones" onNavegar={navegar} /></AuthContext>
}
