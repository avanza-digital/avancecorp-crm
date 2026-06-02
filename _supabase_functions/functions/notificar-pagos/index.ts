/**
 * Edge Function: notificar-pagos
 *
 * Avisa al cliente sobre eventos de pago de sus cuotas, por 3 canales:
 *   1) Novedad in-portal (tabla `novedades`) → el cliente la ve en /novedades.html
 *      y el badge sube en vivo (Supabase Realtime ya escucha INSERT en novedades).
 *   2) Push al celular (Web Push / VAPID) a sus suscripciones activas.
 *   3) Correo (Resend) con plantilla institucional.
 *
 * Dos eventos:
 *   - 'pagado'       → "Te depositamos tu cuota". Lo dispara el panel admin tras
 *                      registrar un pago (manual o por import de Excel). Recibe
 *                      `cuota_ids: string[]`. Auth: token de admin/superadmin.
 *   - 'recordatorio' → "En 3 días te toca tu pago". Lo dispara el cron diario.
 *                      Calcula solo las cuotas que vencen en 3 días (hora Perú).
 *                      Auth: header `x-cron-secret` (verificado contra Vault).
 *
 * Idempotencia: cada cuota lleva un sello (`notif_pago_enviada_en` /
 * `recordatorio_3d_enviado_en`). Solo se notifican cuotas con el sello en NULL,
 * y se estampa al notificar → reintentos/reimports no duplican avisos.
 *
 * `dry_run: true` devuelve a quién se notificaría SIN enviar ni estampar nada
 * (para probar sin molestar a clientes reales).
 *
 * verify_jwt: FALSE — auth custom aquí dentro (token admin válido vía getUser,
 * o secreto del cron). Se rechaza cualquier otra cosa.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

const ALLOWED_ORIGINS = new Set([
  'https://miavance.com',
  'https://www.miavance.com',
])

function corsHeaders(req: Request) {
  const origin = req.headers.get('Origin') || ''
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : 'https://miavance.com',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
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

webpush.setVapidDetails(
  Deno.env.get('VAPID_SUBJECT')!,
  Deno.env.get('VAPID_PUBLIC_KEY')!,
  Deno.env.get('VAPID_PRIVATE_KEY')!,
)

type Cuota = {
  id: string
  numero_cuota: number
  fecha_programada: string
  monto_programado: number
  tipo: string
  estado: string
  contratos: {
    numero_contrato: string
    moneda: string
    cliente_id: string
    perfiles: { id: string; nombre_completo: string | null; correo: string | null; activo: boolean } | null
  } | null
}

/** Fecha (YYYY-MM-DD) en zona horaria de Lima, hoy + `dias`. Evita el corrimiento UTC-5. */
function fechaPeruMasDias(dias: number): string {
  const hoyLima = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date())
  const [y, m, d] = hoyLima.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d))
  dt.setUTCDate(dt.getUTCDate() + dias)
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`
}

function simbolo(moneda: string): string {
  return moneda === 'USD' ? 'US$' : 'S/'
}

function formatMoney(monto: number, moneda: string): string {
  return `${simbolo(moneda)} ${Number(monto).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

/** YYYY-MM-DD → "22 de mayo de 2026" (parseo local, sin corrimiento UTC). */
function fechaLarga(iso: string): string {
  const m = iso.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return iso
  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
  return `${Number(m[3])} de ${meses[Number(m[2]) - 1]} de ${m[1]}`
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

function conceptoCuota(c: Cuota): string {
  return c.tipo === 'retorno' ? 'el retorno de tu capital' : `tu cuota #${c.numero_cuota}`
}

Deno.serve(async (req) => {
  const cors = corsHeaders(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const body = await req.json().catch(() => ({}))
    const evento: string = body?.evento
    const dryRun: boolean = body?.dry_run === true

    if (evento !== 'pagado' && evento !== 'recordatorio') {
      return json(cors, { error: "evento debe ser 'pagado' o 'recordatorio'" }, 400)
    }

    /* ---------- AUTENTICACIÓN ---------- */
    // Camino A: secreto del cron (recordatorio automático).
    const cronSecret = req.headers.get('x-cron-secret')
    let autorizado = false
    if (cronSecret) {
      const { data: ok } = await supabase.rpc('verificar_cron_secret', { p_secret: cronSecret })
      autorizado = ok === true
    }
    // Camino B: token de admin/superadmin (panel o prueba manual).
    if (!autorizado) {
      const token = req.headers.get('Authorization')?.replace('Bearer ', '')
      if (token) {
        const { data: { user } } = await supabase.auth.getUser(token)
        if (user) {
          const { data: perfil } = await supabase
            .from('perfiles').select('rol, activo').eq('id', user.id).single()
          if (perfil?.activo && ['admin', 'superadmin'].includes(perfil.rol)) autorizado = true
        }
      }
    }
    if (!autorizado) return json(cors, { error: 'No autorizado' }, 401)

    /* ---------- CARGAR CUOTAS A NOTIFICAR ---------- */
    const selectCuota = `
      id, numero_cuota, fecha_programada, monto_programado, tipo, estado,
      contratos!inner(
        numero_contrato, moneda, cliente_id,
        perfiles!contratos_cliente_id_fkey(id, nombre_completo, correo, activo)
      )
    `
    const selloCol = evento === 'pagado' ? 'notif_pago_enviada_en' : 'recordatorio_3d_enviado_en'

    let cuotas: Cuota[] = []
    if (evento === 'pagado') {
      const ids: string[] = Array.isArray(body?.cuota_ids) ? body.cuota_ids : []
      if (ids.length === 0) return json(cors, { error: 'cuota_ids vacío' }, 400)
      const { data, error } = await supabase
        .from('cronograma_pagos')
        .select(selectCuota)
        .in('id', ids)
        .eq('estado', 'pagado')
        .is('notif_pago_enviada_en', null)
      if (error) throw error
      cuotas = (data || []) as unknown as Cuota[]
    } else {
      const objetivo = fechaPeruMasDias(3)
      const { data, error } = await supabase
        .from('cronograma_pagos')
        .select(selectCuota)
        .eq('estado', 'pendiente')
        .eq('fecha_programada', objetivo)
        .is('recordatorio_3d_enviado_en', null)
      if (error) throw error
      cuotas = (data || []) as unknown as Cuota[]
    }

    // Solo clientes activos con su relación intacta.
    cuotas = cuotas.filter(c => c.contratos?.perfiles?.activo)

    if (cuotas.length === 0) {
      return json(cors, { success: true, evento, dryRun, clientes: 0, cuotas: 0, detalle: 'Nada que notificar.' })
    }

    /* ---------- AGRUPAR POR CLIENTE ---------- */
    const porCliente = new Map<string, { perfil: NonNullable<NonNullable<Cuota['contratos']>['perfiles']>; cuotas: Cuota[] }>()
    for (const c of cuotas) {
      const p = c.contratos!.perfiles!
      if (!porCliente.has(p.id)) porCliente.set(p.id, { perfil: p, cuotas: [] })
      porCliente.get(p.id)!.cuotas.push(c)
    }

    const dryDetalle: Array<{ cliente: string; correo: string | null; cuotas: number }> = []
    let novedades = 0, push = 0, correos = 0

    for (const { perfil, cuotas: cc } of porCliente.values()) {
      const nombrePila = (perfil.nombre_completo || 'estimado cliente').split(' ')[0]

      // Texto del aviso (1 o varias cuotas del mismo cliente en esta corrida).
      let titulo: string, mensaje: string
      if (evento === 'pagado') {
        titulo = '💰 Pago realizado'
        if (cc.length === 1) {
          const c = cc[0]
          mensaje = `Hola ${nombrePila}, confirmamos el depósito de ${conceptoCuota(c)} del contrato ${c.contratos!.numero_contrato} por ${formatMoney(c.monto_programado, c.contratos!.moneda)}, con fecha ${fechaLarga(c.fecha_programada)}. Gracias por confiar en Avance Corp.`
        } else {
          const lista = cc.map(c => `• ${conceptoCuota(c)} (${c.contratos!.numero_contrato}): ${formatMoney(c.monto_programado, c.contratos!.moneda)}`).join('\n')
          mensaje = `Hola ${nombrePila}, confirmamos los siguientes depósitos a tu favor:\n${lista}\n\nGracias por confiar en Avance Corp.`
        }
      } else {
        titulo = '📅 Tu próximo pago se acerca'
        if (cc.length === 1) {
          const c = cc[0]
          mensaje = `Hola ${nombrePila}, te recordamos que en 3 días, el ${fechaLarga(c.fecha_programada)}, está programado el pago de ${conceptoCuota(c)} del contrato ${c.contratos!.numero_contrato} por ${formatMoney(c.monto_programado, c.contratos!.moneda)}. Mantente atento a tu cuenta.`
        } else {
          const lista = cc.map(c => `• ${conceptoCuota(c)} (${c.contratos!.numero_contrato}): ${formatMoney(c.monto_programado, c.contratos!.moneda)} el ${fechaLarga(c.fecha_programada)}`).join('\n')
          mensaje = `Hola ${nombrePila}, te recordamos que en 3 días tienes pagos programados a tu favor:\n${lista}\n\nMantente atento a tu cuenta.`
        }
      }

      if (dryRun) {
        dryDetalle.push({ cliente: perfil.nombre_completo || '—', correo: perfil.correo, cuotas: cc.length })
        continue
      }

      // 1) Novedad in-portal (Realtime sube el badge). enviado_por = NULL (sistema).
      const { error: errNov } = await supabase.from('novedades').insert({
        titulo, mensaje, destinatario_id: perfil.id, enviado_por: null,
      })
      if (!errNov) novedades++
      else console.warn('[notificar-pagos] novedad falló:', errNov.message)

      // 2) Push al celular.
      try {
        const { data: subs } = await supabase
          .from('suscripciones_push')
          .select('id, endpoint, p256dh, auth')
          .eq('cliente_id', perfil.id)
          .eq('activo', true)
        const expiradas: string[] = []
        for (const s of (subs || [])) {
          try {
            await webpush.sendNotification(
              { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
              JSON.stringify({
                title: titulo,
                body: mensaje.length > 120 ? mensaje.slice(0, 117) + '…' : mensaje,
                icon: '/img/avance-icon-192.png',
                badge: '/img/favicon-32.png',
                url: '/novedades.html',
              }),
              { TTL: 86400, urgency: 'normal' },
            )
            push++
          } catch (e: any) {
            if (e?.statusCode === 404 || e?.statusCode === 410) expiradas.push(s.id)
          }
        }
        if (expiradas.length) {
          await supabase.from('suscripciones_push')
            .update({ activo: false }).in('id', expiradas)
        }
      } catch (e) {
        console.warn('[notificar-pagos] push falló (no crítico):', e)
      }

      // 3) Correo (Resend).
      if (perfil.correo) {
        try {
          const res = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              from: 'Avance Corp <info@miavance.com>',
              to: [perfil.correo],
              subject: titulo,
              html: plantillaEmail(perfil.nombre_completo || 'estimado cliente', titulo, mensaje, evento),
            }),
          })
          if (res.ok) correos++
        } catch (e) {
          console.warn('[notificar-pagos] correo falló (no crítico):', e)
        }
      }
    }

    if (dryRun) {
      return json(cors, { success: true, evento, dryRun: true, clientes: porCliente.size, cuotas: cuotas.length, detalle: dryDetalle })
    }

    // 4) Estampar el sello para no re-notificar.
    const idsNotificadas = cuotas.map(c => c.id)
    await supabase.from('cronograma_pagos')
      .update({ [selloCol]: new Date().toISOString() })
      .in('id', idsNotificadas)

    return json(cors, {
      success: true, evento,
      clientes: porCliente.size, cuotas: cuotas.length,
      novedades, push, correos,
    })
  } catch (error) {
    console.error('[notificar-pagos] error:', error)
    return json(cors, { error: (error as Error).message }, 500)
  }
})

function plantillaEmail(nombre: string, titulo: string, mensaje: string, evento: string): string {
  const nombreEsc = escapeHtml(nombre)
  const tituloEsc = escapeHtml(titulo)
  const mensajeEsc = escapeHtml(mensaje).replace(/\n/g, '<br>')
  const preheader = escapeHtml(mensaje.slice(0, 110).replace(/\s+/g, ' ').trim())
  const etiqueta = evento === 'pagado' ? 'CONFIRMACIÓN DE PAGO' : 'RECORDATORIO DE PAGO'

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="x-apple-disable-message-reformatting">
<title>${tituloEsc}</title>
</head>
<body style="margin:0;padding:0;background:#f4f2ec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">
  <div style="display:none;font-size:1px;color:#f4f2ec;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">${preheader}</div>
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ec;padding:32px 16px;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;max-width:600px;width:100%;border:1px solid #e8e3d4;">
        <tr>
          <td style="background:#0a0e1a;padding:36px 48px;text-align:center;border-bottom:3px solid #c9a96e;">
            <img src="https://miavance.com/img/avance-logo-full.png" alt="Avance Corp" width="180" style="display:block;margin:0 auto;max-width:180px;height:auto;">
            <div style="font-size:10px;color:#c9a96e;margin-top:14px;letter-spacing:0.22em;font-weight:600;">${etiqueta}</div>
          </td>
        </tr>
        <tr>
          <td style="padding:40px 48px 0;">
            <p style="margin:0;font-size:13px;color:#8a8780;letter-spacing:0.04em;">Estimado(a)</p>
            <p style="margin:4px 0 0;font-size:18px;color:#1a1f2e;font-weight:600;">${nombreEsc}</p>
          </td>
        </tr>
        <tr>
          <td style="padding:28px 48px 0;">
            <div style="width:32px;height:2px;background:#c9a96e;margin-bottom:18px;"></div>
            <h1 style="margin:0;font-size:24px;color:#0a0e1a;font-weight:700;line-height:1.3;letter-spacing:-0.01em;">${tituloEsc}</h1>
          </td>
        </tr>
        <tr>
          <td style="padding:24px 48px 0;">
            <p style="margin:0;font-size:15px;color:#3a3f4e;line-height:1.75;">${mensajeEsc}</p>
          </td>
        </tr>
        <tr>
          <td style="padding:36px 48px 8px;">
            <table cellpadding="0" cellspacing="0"><tr>
              <td style="background:#0a0e1a;">
                <a href="https://miavance.com" style="display:inline-block;padding:14px 32px;color:#c9a96e;text-decoration:none;font-size:13px;font-weight:700;letter-spacing:0.12em;text-transform:uppercase;border:1px solid #c9a96e;">Ingresar al portal</a>
              </td>
            </tr></table>
          </td>
        </tr>
        <tr>
          <td style="background:#0a0e1a;padding:32px 48px;margin-top:24px;">
            <div style="font-size:13px;color:#c9a96e;font-weight:700;letter-spacing:0.06em;margin-bottom:6px;">AVANCE CORP S.A.C.</div>
            <div style="font-size:11px;color:#8a8a8a;line-height:1.7;">
              RUC 20611392088<br>San Isidro · Lima · Per&uacute;<br>
              <a href="mailto:info@miavance.com" style="color:#c9a96e;text-decoration:none;">info@miavance.com</a> &nbsp;·&nbsp;
              <a href="https://miavance.com" style="color:#c9a96e;text-decoration:none;">miavance.com</a>
            </div>
            <div style="font-size:10px;color:#5a5a5a;line-height:1.6;padding-top:16px;margin-top:16px;border-top:1px solid #1a1f2e;">
              Recibiste este correo porque eres cliente de Avance Corp S.A.C. Comunicaci&oacute;n institucional automatizada.
            </div>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`
}
