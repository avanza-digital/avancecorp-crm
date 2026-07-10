// Config del cliente. NUNCA el service_role acá (solo la publishable/anon key).
export const CONFIG = {
  SUPABASE_URL: import.meta.env.VITE_SUPABASE_URL as string | undefined,
  SUPABASE_ANON_KEY: import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined,
  MARCA: 'Avance Corp',
  MARCA_SUB: 'CRM Comercial',
} as const

export const HAY_SUPABASE = Boolean(CONFIG.SUPABASE_URL && CONFIG.SUPABASE_ANON_KEY)
