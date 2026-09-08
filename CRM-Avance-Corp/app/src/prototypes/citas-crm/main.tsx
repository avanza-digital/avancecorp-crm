import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@/index.css'
import './presentacion.css'
import { PropuestaCitasCRM } from './propuesta'

// Entrada independiente: no carga sesión, store, RPC ni acciones del CRM.
createRoot(document.getElementById('root')!).render(<StrictMode><PropuestaCitasCRM /></StrictMode>)
