// Cliente Supabase ÚNICO y compartido (una sola sesión / un solo realtime).
// Tipado con Database (lib/database.types.ts): un rename de columna en el
// esquema deja de compilar aquí en vez de fallar en silencio en producción.
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './database.types'
import { CONFIG, HAY_SUPABASE, PROBLEMAS_CONFIG } from './config'
import {
  instalarObservabilidadGlobal,
  registrarAviso,
  registrarError,
} from './observabilidad'

instalarObservabilidadGlobal()

if (PROBLEMAS_CONFIG.length > 0) {
  registrarAviso('config.supabase_rechazada', { problemas: PROBLEMAS_CONFIG })
}

export type ClienteCrm = SupabaseClient<Database>

function crearCliente(): ClienteCrm | null {
  if (!HAY_SUPABASE || !CONFIG.SUPABASE_URL || !CONFIG.SUPABASE_ANON_KEY) return null
  try {
    return createClient<Database>(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        // El CRM solo usa correo/contraseña; no debe interpretar tokens que
        // aparezcan accidental o maliciosamente en la URL.
        detectSessionInUrl: false,
      },
    })
  } catch (error) {
    registrarError('supabase.cliente_no_creado', error)
    return null
  }
}

export const sb: ClienteCrm | null = crearCliente()
