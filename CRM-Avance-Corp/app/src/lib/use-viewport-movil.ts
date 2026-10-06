import { useEffect, useState } from 'react'

/** El teclado reduce el viewport visual en Safari y Chrome, no siempre el layout. */
export function useViewportMovil(activo: boolean) {
  const [teclado, setTeclado] = useState(false)
  useEffect(() => {
    const viewport = window.visualViewport
    if (!activo || !viewport) return
    let cuadro = 0
    const actualizar = () => {
      if (viewport.scale !== 1) {
        setTeclado(false)
        document.documentElement.style.removeProperty('--crm-viewport-alto')
        return
      }
      const elemento = document.activeElement
      const editando = elemento instanceof HTMLElement && elemento.matches('input:not([type=checkbox]):not([type=radio]), textarea, select, [contenteditable=true]')
      const abierto = editando && window.innerHeight - viewport.height > 140
      setTeclado(abierto)
      document.documentElement.style.setProperty('--crm-viewport-alto', `${Math.round(viewport.height)}px`)
    }
    const alFoco = () => { cancelAnimationFrame(cuadro); cuadro = requestAnimationFrame(actualizar) }
    actualizar()
    viewport.addEventListener('resize', actualizar)
    viewport.addEventListener('scroll', actualizar)
    document.addEventListener('focusin', alFoco)
    document.addEventListener('focusout', alFoco)
    return () => {
      cancelAnimationFrame(cuadro)
      viewport.removeEventListener('resize', actualizar)
      viewport.removeEventListener('scroll', actualizar)
      document.removeEventListener('focusin', alFoco)
      document.removeEventListener('focusout', alFoco)
      document.documentElement.style.removeProperty('--crm-viewport-alto')
    }
  }, [activo])
  return activo && teclado
}
