// Sólo se importa desde Playwright en el servidor de desarrollo. Monta el
// componente real para verificar sus capas sin habilitar avisos falsos en App.
import { createRoot } from 'react-dom/client'
import { VersionPublicadaAviso } from '../src/components/app/version-publicada'

export function montarAvisoVersion() {
  const host = document.createElement('div')
  host.dataset.avisoVersionPrueba = 'true'
  document.body.append(host)
  createRoot(host).render(<VersionPublicadaAviso
    activo
    buildActual="build-prueba-anterior"
    fetchVersion={async () => new Response(JSON.stringify({ schema: 1, buildId: 'build-prueba-nuevo' }))}
    onActualizar={() => { host.dataset.actualizacionSolicitada = 'true' }}
  />)
}
