/**
 * Edge Function: notificar-cambio-cuenta (F3.3, 26/09/2026)
 *
 * Avisa al cliente que su cuenta de pago cambió (por su pedido), por 2 canales:
 *   1) Novedad in-portal (tabla `novedades`) → badge en vivo.
 *   2) Correo (Resend) con la plantilla institucional.
 *
 * Lo invoca el panel admin (ventana «Cuentas») justo después de
 * `crm.cambiar_cuenta_pago_contratos`, con `{ solicitud_id }`.
 *
 * Dos pasos (nada se da por avisado sin haber salido):
 *   1) `crm.reclamar_aviso_cambio_cuenta` reserva el envío (10 min, con token) y dice qué
 *      canales faltan. Un doble clic recibe `en_curso`; un aviso ya completo, `ya_notificada`;
 *      un cambio superado por otro posterior, `superada` (no se avisa una cuenta que ya no rige).
 *   2) Se envía SOLO lo pendiente y `crm.confirmar_aviso_cambio_cuenta` (con el token) registra
 *      lo que de verdad salió. El historial queda «avisado» solo con todos los canales
 *      entregados; si algo falló, el botón «Enviar aviso» reintenta únicamente lo que faltó.
 *   Si la función se cae entre enviar y confirmar, el reintento no duplica: el correo lleva
 *   `Idempotency-Key` por solicitud (Resend, 24 h) y una novedad idéntica no se vuelve a publicar.
 * `dry_run: true` devuelve el texto que se enviaría, sin reservar ni enviar.
 *
 * verify_jwt: TRUE (la puerta de Supabase exige un JWT válido); aquí dentro solo pasan
 * admin/superadmin activos, y la base vuelve a exigirlo para el actor (`p_actor`), incluida la
 * membresía CRM no revocada (P04): si la niega, 403.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { claveIdempotencia, plantillaEmail, redactarAviso } from './aviso.ts'

const ALLOWED_ORIGINS = new Set([
  'https://miavance.com',
  'https://www.miavance.com',
])

function corsHeaders(req: Request) {
  const origin = req.headers.get('Origin') || ''
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : 'https://miavance.com',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

function json(cors: Record<string, string>, payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

Deno.serve(async (req) => {
  const cors = corsHeaders(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json(cors, { error: 'Método no permitido' }, 405)

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    /* ---------- AUTENTICACIÓN: solo admin/superadmin activos ---------- */
    const token = req.headers.get('Authorization')?.replace('Bearer ', '')
    if (!token) return json(cors, { error: 'No autorizado' }, 401)
    const { data: { user } } = await supabase.auth.getUser(token)
    if (!user) return json(cors, { error: 'No autorizado' }, 401)
    const { data: perfil } = await supabase
      .from('perfiles').select('rol, activo').eq('id', user.id).single()
    if (!perfil?.activo || !['admin', 'superadmin'].includes(perfil.rol)) {
      return json(cors, { error: 'No autorizado' }, 403)
    }

    const body = await req.json().catch(() => ({}))
    const solicitudId: string = body?.solicitud_id
    const dryRun: boolean = body?.dry_run === true
    if (typeof solicitudId !== 'string' || !UUID.test(solicitudId)) {
      return json(cors, { error: 'solicitud_id inválido' }, 400)
    }

    /* ---------- PASO 1: RESERVA + DATOS ---------- */
    const crm = supabase.schema('crm')
    const { data: datos, error: errClaim } = await crm.rpc('reclamar_aviso_cambio_cuenta', {
      p_solicitud_id: solicitudId, p_actor: user.id, p_dry_run: dryRun,
    })
    if (errClaim?.code === '42501') return json(cors, { error: 'No autorizado' }, 403)
    if (errClaim) throw errClaim
    if (!datos?.encontrada) return json(cors, { error: 'Cambio no encontrado' }, 404)
    if (datos.ya_notificada) return json(cors, { success: true, ya_notificada: true })
    if (datos.superada) return json(cors, { success: false, superada: true })
    if (datos.en_curso) return json(cors, { success: false, en_curso: true })

    const { titulo, mensaje } = redactarAviso(datos)
    if (dryRun) return json(cors, { success: true, dry_run: true, correo: datos.correo, titulo, mensaje })

    const confirmar = async (novedad: boolean, correo: boolean, error: string | null) => {
      const { data, error: errConf } = await crm.rpc('confirmar_aviso_cambio_cuenta', {
        p_solicitud_id: solicitudId, p_reserva: datos.reserva,
        p_novedad: novedad, p_correo: correo, p_error: error,
      })
      if (errConf) throw errConf
      return data
    }

    if (!datos.activo) {
      const estado = await confirmar(false, false, 'Cliente inactivo: no se envió el aviso')
      return json(cors, { success: false, ...estado, detalle: 'Cliente inactivo' })
    }

    /* ---------- PASO 2: ENVÍO DE LO PENDIENTE ---------- */
    const errores: string[] = []
    let novedadAhora = false
    if (datos.pendiente_novedad) {
      // Un intento anterior pudo publicarla y caerse antes de confirmar: la misma novedad
      // (mismo cliente, título y texto) no se repite.
      const { data: previa, error: errPrevia } = await supabase.from('novedades')
        .select('id').eq('destinatario_id', datos.cliente_id).eq('titulo', titulo).eq('mensaje', mensaje).limit(1)
      if (!errPrevia && previa?.length) {
        novedadAhora = true
      } else {
        const { error: errNov } = await supabase.from('novedades').insert({
          titulo, mensaje, destinatario_id: datos.cliente_id, enviado_por: null,
        })
        if (errNov) {
          errores.push('No se pudo publicar el aviso en el portal')
          console.warn('[notificar-cambio-cuenta] novedad falló:', errNov.message)
        } else {
          novedadAhora = true
        }
      }
    }

    let correoAhora = false
    if (datos.pendiente_correo) {
      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
            'Content-Type': 'application/json',
            // Reintento tras una caída entre el envío y la confirmación: Resend no lo duplica (24 h).
            'Idempotency-Key': claveIdempotencia(solicitudId),
          },
          body: JSON.stringify({
            from: 'Avance Corp <info@miavance.com>',
            to: [datos.correo],
            subject: titulo,
            html: plantillaEmail(datos.nombre_completo || 'estimado cliente', titulo, mensaje),
          }),
        })
        correoAhora = res.ok
        if (!res.ok) errores.push(`El correo no se pudo enviar (Resend ${res.status})`)
      } catch (e) {
        errores.push('El correo no se pudo enviar')
        console.warn('[notificar-cambio-cuenta] correo falló:', e)
      }
    }

    const estado = await confirmar(novedadAhora, correoAhora, errores.length ? errores.join('; ') : null)
    return json(cors, { success: estado?.completo === true, ...estado })
  } catch (error) {
    console.error('[notificar-cambio-cuenta] error:', error)
    return json(cors, { error: 'No se pudo enviar el aviso' }, 500)
  }
})
