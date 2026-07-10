// Cliente Supabase ÚNICO y compartido (una sola sesión / un solo realtime).
// Si falta config (p. ej. antes de tener .env), la app sigue funcionando en modo demo.
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { CONFIG, HAY_SUPABASE } from './config'

export const sb: SupabaseClient | null = HAY_SUPABASE
  ? createClient(CONFIG.SUPABASE_URL!, CONFIG.SUPABASE_ANON_KEY!)
  : null
