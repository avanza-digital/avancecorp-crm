/**
 * Edge Function: ciclo-contratos
 *
 * Corrida diaria del ciclo de vida de contratos (la dispara el cron
 * `ciclo-contratos-diario`, 09:10 Lima). Dos pasos:
 *
 *   1) MARCAR VENCIDOS — llama a la RPC `marcar_contratos_vencidos()`
 *      (contratos 'activo' con fecha_vencimiento ya pasada → 'vencido').
 *      Silencioso: el cliente lo ve como "Finalizado" en su portal.
 *
 *   2) AVISOS PREVIOS AL VENCIMIENTO — por VENTANAS disjuntas con sello
 *      (nunca por igualdad de fecha: un día caído se auto-recupera):
 *        · 7d : vence entre hoy y hoy+7   → sello `aviso_venc_7d_enviado_en`
 *        · 30d: vence entre hoy+8 y hoy+30 → sello `aviso_venc_30d_enviado_en`
 *      CLIENTE: novedad in-portal + push + correo (igual que notificar-pagos).
 *      ASESOR : correo + push best-effort (SIN novedad: los analistas no
 *               tienen pantalla de novedades — sería un canal muerto).
 *
 * Idempotencia: claim atómico del sello (`UPDATE ... SET sello=now()
 * WHERE id IN (...) AND sello IS NULL RETURNING id`) ANTES de enviar —
 * corridas solapadas reclaman 0 y no duplican avisos.
 *
 * `dry_run: true` devuelve qué marcaría y a quién avisaría SIN tocar nada.
 *
 * verify_jwt: FALSE — auth custom aquí dentro (x-cron-secret contra Vault,
 * o token admin/superadmin). ⚠️ Un redeploy por CLI sin fijar verify_jwt
 * lo revertiría a true y rompería el cron en silencio (ver CLAUDE.md §8).
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

type PerfilMin = {
  id: string
  nombre_completo: string | null
  nombres: string | null
  correo: string | null
  activo: boolean
  asesor_perfil_id: string | null
}

type Contrato = {
  id: string
  numero_contrato: string
  capital: number
  moneda: string
  fecha_vencimiento: string
  cliente_id: string
  perfiles: PerfilMin | null
}

type Asesor = {
  id: string
  nombre_completo: string | null
  nombres: string | null
  correo: string | null
  activo: boolean
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

/** Días de diferencia entre dos fechas YYYY-MM-DD (b - a), sin líos de zona horaria. */
function diasEntreISO(a: string, b: string): number {
  const [ya, ma, da] = a.split('-').map(Number)
  const [yb, mb, db] = b.split('-').map(Number)
  return Math.round((Date.UTC(yb, mb - 1, db) - Date.UTC(ya, ma - 1, da)) / 86400000)
}

function simbolo(moneda: string): string {
  return moneda === 'USD' ? 'US$' : 'S/'
}

function formatMoney(monto: number, moneda: string): string {
  return `${simbolo(moneda)} ${Number(monto).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

/** YYYY-MM-DD → "23 de septiembre de 2026" (parseo local, sin corrimiento UTC). */
function fechaLarga(iso: string): string {
  const m = iso.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return iso
  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
  return `${Number(m[3])} de ${meses[Number(m[2]) - 1]} de ${m[1]}`
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

function plural(n: number, uno: string, varios: string): string {
  return n === 1 ? uno : varios
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

    if (evento !== 'diario') {
      return json(cors, { error: "evento debe ser 'diario'" }, 400)
    }

    /* ---------- AUTENTICACIÓN (idéntica a notificar-pagos) ---------- */
    const cronSecret = req.headers.get('x-cron-secret')
    let autorizado = false
    if (cronSecret) {
      const { data: ok } = await supabase.rpc('verificar_cron_secret', { p_secret: cronSecret })
      autorizado = ok === true
    }
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

    const hoy = fechaPeruMasDias(0)

    /* ---------- PASO 1: MARCAR VENCIDOS ---------- */
    let marcados = 0
    if (dryRun) {
      const { count } = await supabase
        .from('contratos')
        .select('id', { count: 'exact', head: true })
        .eq('estado', 'activo')
        .lt('fecha_vencimiento', hoy)
      marcados = count || 0
    } else {
      const { data: vencidos, error: errMarcar } = await supabase.rpc('marcar_contratos_vencidos')
      if (errMarcar) throw errMarcar
      marcados = (vencidos || []).length
    }

    /* ---------- PASO 2: AVISOS PREVIOS (ventanas disjuntas + sello) ---------- */
    const selectContrato = `
      id, numero_contrato, capital, moneda, fecha_vencimiento, cliente_id,
      perfiles!contratos_cliente_id_fkey(id, nombre_completo, nombres, correo, activo, asesor_perfil_id)
    `

    // Ventana 7d: vence entre hoy y hoy+7 (incluye el primer run con contratos ya encima).
    const { data: cand7, error: err7 } = await supabase
      .from('contratos')
      .select(selectContrato)
      .eq('estado', 'activo')
      .gte('fecha_vencimiento', hoy)
      .lte('fecha_vencimiento', fechaPeruMasDias(7))
      .is('aviso_venc_7d_enviado_en', null)
    if (err7) throw err7

    // Ventana 30d: vence entre hoy+8 y hoy+30 (disjunta de la de 7d).
    const { data: cand30, error: err30 } = await supabase
      .from('contratos')
      .select(selectContrato)
      .eq('estado', 'activo')
      .gte('fecha_vencimiento', fechaPeruMasDias(8))
      .lte('fecha_vencimiento', fechaPeruMasDias(30))
      .is('aviso_venc_30d_enviado_en', null)
    if (err30) throw err30

    // Solo clientes activos con su relación intacta.
    const ventanas: Array<{ sello: string; contratos: Contrato[] }> = [
      { sello: 'aviso_venc_7d_enviado_en', contratos: ((cand7 || []) as unknown as Contrato[]).filter(c => c.perfiles?.activo) },
      { sello: 'aviso_venc_30d_enviado_en', contratos: ((cand30 || []) as unknown as Contrato[]).filter(c => c.perfiles?.activo) },
    ]

    /* ---------- CLAIM ATÓMICO por ventana (idempotencia) ---------- */
    if (!dryRun) {
      for (const v of ventanas) {
        if (v.contratos.length === 0) continue
        const ids = v.contratos.map(c => c.id)
        const { data: reclamados, error: errClaim } = await supabase
          .from('contratos')
          .update({ [v.sello]: new Date().toISOString() })
          .in('id', ids)
          .is(v.sello, null)
          .select('id')
        if (errClaim) throw errClaim
        const set = new Set((reclamados || []).map((r: { id: string }) => r.id))
        v.contratos = v.contratos.filter(c => set.has(c.id))
      }
    }

    const avisar = ventanas.flatMap(v => v.contratos)

    if (avisar.length === 0) {
      return json(cors, {
        success: true, evento, dryRun, marcados,
        avisos: 0, detalle: 'Nada que avisar.',
      })
    }

    /* ---------- AGRUPAR: por CLIENTE y por ASESOR ---------- */
    const porCliente = new Map<string, { perfil: PerfilMin; contratos: Contrato[] }>()
    for (const c of avisar) {
      const p = c.perfiles!
      if (!porCliente.has(p.id)) porCliente.set(p.id, { perfil: p, contratos: [] })
      porCliente.get(p.id)!.contratos.push(c)
    }

    // Asesores en una consulta aparte (sin adivinar nombres de FK anidadas).
    const asesorIds = [...new Set(avisar.map(c => c.perfiles?.asesor_perfil_id).filter(Boolean))] as string[]
    const asesores = new Map<string, Asesor>()
    if (asesorIds.length) {
      const { data: rows } = await supabase
        .from('perfiles')
        .select('id, nombre_completo, nombres, correo, activo')
        .in('id', asesorIds)
      for (const a of (rows || []) as Asesor[]) {
        if (a.activo) asesores.set(a.id, a)
      }
    }
    const porAsesor = new Map<string, { asesor: Asesor; items: Array<{ cliente: string; c: Contrato }> }>()
    for (const c of avisar) {
      const aId = c.perfiles?.asesor_perfil_id
      if (!aId || !asesores.has(aId)) continue
      const a = asesores.get(aId)!
      if (!porAsesor.has(aId)) porAsesor.set(aId, { asesor: a, items: [] })
      porAsesor.get(aId)!.items.push({ cliente: c.perfiles?.nombre_completo || '—', c })
    }

    const dryDetalle: Array<{ tipo: string; nombre: string; correo: string | null; contratos: number }> = []
    let novedades = 0, push = 0, correos = 0

    /** Push a las suscripciones activas de un perfil (cliente o asesor). */
    async function enviarPush(perfilId: string, titulo: string, mensaje: string) {
      try {
        const { data: subs } = await supabase
          .from('suscripciones_push')
          .select('id, endpoint, p256dh, auth')
          .eq('cliente_id', perfilId)
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
        console.warn('[ciclo-contratos] push falló (no crítico):', e)
      }
    }

    /** Correo institucional (Resend). */
    async function enviarCorreo(correo: string, nombre: string, titulo: string, mensaje: string) {
      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: 'Avance Corp <info@miavance.com>',
            to: [correo],
            subject: titulo,
            html: plantillaEmail(nombre, titulo, mensaje),
          }),
        })
        if (res.ok) correos++
      } catch (e) {
        console.warn('[ciclo-contratos] correo falló (no crítico):', e)
      }
    }

    /* ---------- AVISOS AL CLIENTE (novedad + push + correo) ---------- */
    for (const { perfil, contratos: cc } of porCliente.values()) {
      const nombrePila = (perfil.nombres || perfil.nombre_completo || 'estimado cliente').split(' ')[0]
      const titulo = '⏳ Tu contrato está por vencer'
      let mensaje: string
      if (cc.length === 1) {
        const c = cc[0]
        const dias = diasEntreISO(hoy, c.fecha_vencimiento)
        mensaje = `Hola ${nombrePila}, tu contrato ${c.numero_contrato} por ${formatMoney(c.capital, c.moneda)} vence el ${fechaLarga(c.fecha_vencimiento)} (${dias === 0 ? 'hoy' : `en ${dias} ${plural(dias, 'día', 'días')}`}). Tu asesor se pondrá en contacto contigo para coordinar la renovación; también puedes escribirle desde tu portal.`
      } else {
        const lista = cc.map(c => {
          const dias = diasEntreISO(hoy, c.fecha_vencimiento)
          return `• ${c.numero_contrato} (${formatMoney(c.capital, c.moneda)}): vence el ${fechaLarga(c.fecha_vencimiento)} (${dias === 0 ? 'hoy' : `en ${dias} ${plural(dias, 'día', 'días')}`})`
        }).join('\n')
        mensaje = `Hola ${nombrePila}, tienes contratos próximos a vencer:\n${lista}\n\nTu asesor se pondrá en contacto contigo para coordinar la renovación; también puedes escribirle desde tu portal.`
      }

      if (dryRun) {
        dryDetalle.push({ tipo: 'cliente', nombre: perfil.nombre_completo || '—', correo: perfil.correo, contratos: cc.length })
        continue
      }

      const { error: errNov } = await supabase.from('novedades').insert({
        titulo, mensaje, destinatario_id: perfil.id, enviado_por: null,
      })
      if (!errNov) novedades++
      else console.warn('[ciclo-contratos] novedad falló:', errNov.message)

      await enviarPush(perfil.id, titulo, mensaje)
      if (perfil.correo) await enviarCorreo(perfil.correo, perfil.nombre_completo || 'estimado cliente', titulo, mensaje)
    }

    /* ---------- AVISOS AL ASESOR (correo + push; sin novedad) ---------- */
    for (const { asesor, items } of porAsesor.values()) {
      const nombrePila = (asesor.nombres || asesor.nombre_completo || 'estimado asesor').split(' ')[0]
      const titulo = '⏳ Contratos de tu cartera por vencer'
      const lista = items.map(({ cliente, c }) => {
        const dias = diasEntreISO(hoy, c.fecha_vencimiento)
        return `• ${cliente} — ${c.numero_contrato} (${formatMoney(c.capital, c.moneda)}): vence el ${fechaLarga(c.fecha_vencimiento)} (${dias === 0 ? 'hoy' : `en ${dias} ${plural(dias, 'día', 'días')}`})`
      }).join('\n')
      const mensaje = `Hola ${nombrePila}, ${items.length === 1 ? 'hay 1 contrato' : `hay ${items.length} contratos`} de tu cartera próximos a vencer:\n${lista}\n\nCoordina con cada cliente la renovación o el retiro; el equipo admin cierra el ciclo en el panel.`

      if (dryRun) {
        dryDetalle.push({ tipo: 'asesor', nombre: asesor.nombre_completo || '—', correo: asesor.correo, contratos: items.length })
        continue
      }

      await enviarPush(asesor.id, titulo, mensaje)
      if (asesor.correo) await enviarCorreo(asesor.correo, asesor.nombre_completo || 'estimado asesor', titulo, mensaje)
    }

    if (dryRun) {
      return json(cors, {
        success: true, evento, dryRun: true, marcados,
        avisos: avisar.length, clientes: porCliente.size, asesores: porAsesor.size,
        detalle: dryDetalle,
      })
    }

    return json(cors, {
      success: true, evento, marcados,
      avisos: avisar.length, clientes: porCliente.size, asesores: porAsesor.size,
      novedades, push, correos,
    })
  } catch (error) {
    console.error('[ciclo-contratos] error:', error)
    return json(cors, { error: (error as Error).message }, 500)
  }
})

function plantillaEmail(nombre: string, titulo: string, mensaje: string): string {
  const nombreEsc = escapeHtml(nombre)
  const tituloEsc = escapeHtml(titulo)
  const mensajeEsc = escapeHtml(mensaje).replace(/\n/g, '<br>')
  const preheader = escapeHtml(mensaje.slice(0, 110).replace(/\s+/g, ' ').trim())
  const etiqueta = 'AVISO DE VENCIMIENTO'

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
