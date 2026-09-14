import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { Propuesta } from './propuesta'
import '@/index.css'
import './presentacion.css'

// Entrada local independiente, sin AuthProvider, store, consultas ni escrituras de negocio.
createRoot(document.getElementById('root')!).render(<StrictMode><Propuesta /></StrictMode>)
