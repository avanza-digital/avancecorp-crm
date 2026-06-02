/**
 * Edge Function: enviar-push
 * Envía notificaciones push a todas las suscripciones activas (o a un cliente
 * específico si se pasa `destinatario_id`).
 *
 * Solo admin/superadmin pueden invocar este endpoint.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

const ALLOWED_ORIGINS = new Set([
  "https://miavance.com",
  "https://www.miavance.com",
])

function corsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || ""
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : "https://miavance.com",
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

webpush.setVapidDetails(
  Deno.env.get('VAPID_SUBJECT')!,
  Deno.env.get('VAPID_PUBLIC_KEY')!,
  Deno.env.get('VAPID_PRIVATE_KEY')!
)

Deno.serve(async (req) => {
  const cors = corsHeaders(req)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const token = req.headers.get('Authorization')?.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'No autorizado' }),
        { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } }
      )
    }

    const { data: perfil } = await supabaseClient
      .from('perfiles').select('rol, activo').eq('id', user.id).single()
    if (!perfil || !perfil.activo || !['admin', 'superadmin'].includes(perfil.rol)) {
      return new Response(
        JSON.stringify({ error: 'No autorizado' }),
        { status: 403, headers: { ...cors, 'Content-Type': 'application/json' } }
      )
    }

    const { titulo, mensaje, destinatario_id } = await req.json()
    if (!titulo || !mensaje) {
      return new Response(
        JSON.stringify({ error: 'titulo y mensaje son requeridos' }),
        { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } }
      )
    }

    let query = supabaseClient
      .from('suscripciones_push')
      .select('id, endpoint, p256dh, auth, cliente_id')
      .eq('activo', true)

    if (destinatario_id) query = query.eq('cliente_id', destinatario_id)

    const { data: suscripciones, error: errSubs } = await query
    if (errSubs) throw errSubs

    if (!suscripciones || suscripciones.length === 0) {
      return new Response(
        JSON.stringify({ success: true, enviados: 0, fallidos: 0, expiradas: 0, total: 0 }),
        { headers: { ...cors, 'Content-Type': 'application/json' } }
      )
    }

    const payload = JSON.stringify({
      title: titulo,
      body: mensaje.length > 120 ? mensaje.substring(0, 117) + '…' : mensaje,
      icon: '/img/avance-icon-192.png',
      badge: '/img/favicon-32.png',
      url: '/novedades.html'
    })

    let enviados = 0
    let fallidos = 0
    const expiradas: string[] = []

    for (let i = 0; i < suscripciones.length; i += 10) {
      const lote = suscripciones.slice(i, i + 10)
      await Promise.all(lote.map(async (sub) => {
        try {
          await webpush.sendNotification(
            {
              endpoint: sub.endpoint,
              keys: { p256dh: sub.p256dh, auth: sub.auth }
            },
            payload,
            { TTL: 86400, urgency: 'normal' }
          )
          enviados++
        } catch (e: any) {
          fallidos++
          if (e?.statusCode === 404 || e?.statusCode === 410) {
            expiradas.push(sub.id)
          }
          console.warn(
            '[push] falló',
            sub.endpoint.substring(0, 50),
            'status:', e?.statusCode,
            'msg:', e?.message
          )
        }
      }))
      if (i + 10 < suscripciones.length) {
        await new Promise(r => setTimeout(r, 200))
      }
    }

    if (expiradas.length > 0) {
      await supabaseClient
        .from('suscripciones_push')
        .update({ activo: false, actualizado_en: new Date().toISOString() })
        .in('id', expiradas)
    }

    return new Response(
      JSON.stringify({
        success: true,
        total: suscripciones.length,
        enviados,
        fallidos,
        expiradas: expiradas.length
      }),
      { headers: { ...cors, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('[enviar-push] error:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } }
    )
  }
})
