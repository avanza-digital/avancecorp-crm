import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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

type Destinatario = {
  id: string
  nombre_completo: string
  nombres?: string | null
  correo: string
  asesor_perfil_id?: string | null
  asesor?: {
    nombre_completo: string | null
    whatsapp: string | null
    cargo: string | null
  } | null
  contrato?: {
    numero_contrato: string
    capital: number
    moneda: string
  } | null
}

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

    const authHeader = req.headers.get('Authorization')
    const token = authHeader?.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), { status: 401, headers: cors })
    }

    const { data: perfil } = await supabaseClient
      .from('perfiles')
      .select('rol, nombre_completo, activo')
      .eq('id', user.id)
      .single()

    if (!perfil || !perfil.activo || !['admin', 'superadmin'].includes(perfil.rol)) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), { status: 403, headers: cors })
    }

    const { titulo, mensaje, imagen_url, destinatario_id } = await req.json()

    let destinatarios: Destinatario[] = []

    if (destinatario_id) {
      // Envío individual: traemos perfil + asesor + último contrato activo
      const { data: p } = await supabaseClient
        .from('perfiles')
        .select('id, nombre_completo, nombres, correo, asesor_perfil_id, asesor:asesores(nombre_completo, whatsapp, cargo)')
        .eq('id', destinatario_id)
        .single()

      if (p) {
        const { data: contrato } = await supabaseClient
          .from('contratos')
          .select('numero_contrato, capital, moneda')
          .eq('cliente_id', destinatario_id)
          .eq('estado', 'activo')
          .order('creado_en', { ascending: false })
          .limit(1)
          .maybeSingle()

        destinatarios = [{ ...p, contrato: contrato || null } as Destinatario]
      }
    } else {
      // Envío masivo: perfiles activos + asesor (sin contrato)
      const { data } = await supabaseClient
        .from('perfiles')
        .select('id, nombre_completo, nombres, correo, asesor_perfil_id, asesor:asesores(nombre_completo, whatsapp, cargo)')
        .eq('rol', 'cliente')
        .eq('activo', true)
      destinatarios = (data || []) as Destinatario[]
    }

    destinatarios = destinatarios.filter(d => d.correo && d.correo.trim().length > 0)

    // Asesor del EQUIPO (auto-asignado): si el cliente tiene asesor_perfil_id, ese
    // miembro del equipo es su asesor y manda sobre el legacy (igual que el portal).
    const equipoIds = [...new Set(destinatarios.map(d => d.asesor_perfil_id).filter(Boolean))]
    if (equipoIds.length > 0) {
      const { data: equipo } = await supabaseClient
        .from('perfiles')
        .select('id, nombre_completo, whatsapp, cargo')
        .in('id', equipoIds as string[])
      const mapaEquipo = new Map((equipo || []).map((m: any) => [m.id, m]))
      for (const d of destinatarios) {
        const m = d.asesor_perfil_id ? mapaEquipo.get(d.asesor_perfil_id) : null
        if (m) d.asesor = { nombre_completo: m.nombre_completo, whatsapp: m.whatsapp, cargo: m.cargo }
      }
    }

    let enviados = 0
    let fallidos = 0

    const lotes: Array<typeof destinatarios> = []
    for (let i = 0; i < destinatarios.length; i += 10) {
      lotes.push(destinatarios.slice(i, i + 10))
    }

    for (const lote of lotes) {
      await Promise.all(lote.map(async (destinatario) => {
        try {
          const res = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({
              from: 'Avance Corp <info@miavance.com>',
              to: [destinatario.correo],
              subject: titulo,
              html: plantillaEmail(destinatario, titulo, mensaje, imagen_url)
            })
          })
          if (res.ok) enviados++
          else fallidos++
        } catch {
          fallidos++
        }
      }))
      await new Promise(r => setTimeout(r, 200))
    }

    let pushEnviados = 0
    let pushFallidos = 0
    try {
      const pushResp = await fetch(
        `${Deno.env.get('SUPABASE_URL')}/functions/v1/enviar-push`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': req.headers.get('Authorization') || ''
          },
          body: JSON.stringify({ titulo, mensaje, destinatario_id })
        }
      )
      if (pushResp.ok) {
        const pushResult = await pushResp.json()
        pushEnviados = pushResult.enviados || 0
        pushFallidos = pushResult.fallidos || 0
        console.log('[comunicado] push:', pushResult)
      } else {
        console.warn('[comunicado] enviar-push respondió', pushResp.status)
      }
    } catch (e) {
      console.warn('[comunicado] push falló (no crítico):', e)
    }

    return new Response(
      JSON.stringify({
        success: true,
        enviados,
        fallidos,
        total: destinatarios.length,
        pushEnviados,
        pushFallidos
      }),
      { headers: { ...cors, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } }
    )
  }
})

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

function formatMoney(amount: number, currency: string): string {
  const symbol = currency === 'USD' ? 'US$' : 'S/'
  return `${symbol} ${amount.toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function plantillaEmail(d: Destinatario, titulo: string, mensaje: string, imagenUrl: string | null): string {
  // Saludo por los NOMBRES de pila: con apellidos/nombres separados (2026-06-09) el
  // nombre_completo empieza por los apellidos; cliente viejo sin migrar → como antes.
  const nombre = escapeHtml(d.nombres || d.nombre_completo || 'estimado cliente')
  const tituloEsc = escapeHtml(titulo)
  const mensajeEsc = escapeHtml(mensaje).replace(/\n/g, '<br>')
  const preheader = escapeHtml(mensaje.slice(0, 110).replace(/\s+/g, ' ').trim())

  // Card del contrato (solo si individual y tiene contrato activo)
  const contratoCard = d.contrato ? `
    <tr>
      <td style="padding:24px 48px 0;">
        <table width="100%" cellpadding="0" cellspacing="0" style="background:#f7f5ef;border:1px solid #e8e0c8;border-radius:6px;">
          <tr>
            <td style="padding:18px 22px;">
              <div style="font-size:10px;color:#8a7340;letter-spacing:0.18em;font-weight:700;text-transform:uppercase;margin-bottom:10px;">Tu contrato</div>
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="vertical-align:top;">
                    <div style="font-size:11px;color:#8a8780;margin-bottom:2px;">N° contrato</div>
                    <div style="font-size:14px;color:#1a1f2e;font-weight:700;font-family:'SF Mono','Menlo','Consolas',monospace;">${escapeHtml(d.contrato.numero_contrato)}</div>
                  </td>
                  <td style="vertical-align:top;text-align:right;">
                    <div style="font-size:11px;color:#8a8780;margin-bottom:2px;">Capital invertido</div>
                    <div style="font-size:14px;color:#1a1f2e;font-weight:700;">${formatMoney(d.contrato.capital, d.contrato.moneda)}</div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </td>
    </tr>` : ''

  // WhatsApp del asesor (footer)
  const asesorNombre = d.asesor?.nombre_completo
  const asesorWa = d.asesor?.whatsapp?.replace(/[^0-9]/g, '') || null
  const asesorBlock = (asesorNombre && asesorWa) ? `
    <tr>
      <td style="padding:0 48px 32px;">
        <table width="100%" cellpadding="0" cellspacing="0" style="background:#fafaf7;border-radius:6px;">
          <tr>
            <td style="padding:18px 22px;">
              <div style="font-size:10px;color:#8a8780;letter-spacing:0.18em;font-weight:700;text-transform:uppercase;margin-bottom:8px;">Tu asesor</div>
              <div style="font-size:14px;color:#1a1f2e;font-weight:600;margin-bottom:10px;">${escapeHtml(asesorNombre)}${d.asesor?.cargo ? ` <span style="font-weight:400;color:#8a8780;">· ${escapeHtml(d.asesor.cargo)}</span>` : ''}</div>
              <a href="https://wa.me/${asesorWa}" style="display:inline-block;font-size:13px;color:#8a7340;text-decoration:none;font-weight:600;">
                <span style="border-bottom:1px solid #c9a96e;padding-bottom:1px;">WhatsApp directo →</span>
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>` : ''

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="x-apple-disable-message-reformatting">
<title>${tituloEsc}</title>
<!--[if mso]>
<style>body,table,td{font-family:'Segoe UI',Arial,sans-serif !important;}</style>
<![endif]-->
</head>
<body style="margin:0;padding:0;background:#f4f2ec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">

  <!-- Preheader oculto: aparece como preview en el inbox -->
  <div style="display:none;font-size:1px;color:#f4f2ec;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">
    ${preheader}
  </div>

  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ec;padding:32px 16px;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;max-width:600px;width:100%;border:1px solid #e8e3d4;">

        <!-- HEADER negro con dorado -->
        <tr>
          <td style="background:#0a0e1a;padding:36px 48px;text-align:center;border-bottom:3px solid #c9a96e;">
            <img src="https://miavance.com/img/avance-logo-full.png" alt="Avance Corp" width="180" style="display:block;margin:0 auto;max-width:180px;height:auto;">
            <div style="font-size:10px;color:#c9a96e;margin-top:14px;letter-spacing:0.22em;font-weight:600;">PORTAL DE INVERSIONES</div>
          </td>
        </tr>

        <!-- Saludo -->
        <tr>
          <td style="padding:40px 48px 0;">
            <p style="margin:0;font-size:13px;color:#8a8780;letter-spacing:0.04em;">Estimado(a)</p>
            <p style="margin:4px 0 0;font-size:18px;color:#1a1f2e;font-weight:600;">${nombre}</p>
          </td>
        </tr>

        <!-- Título del comunicado -->
        <tr>
          <td style="padding:28px 48px 0;">
            <div style="width:32px;height:2px;background:#c9a96e;margin-bottom:18px;"></div>
            <h1 style="margin:0;font-size:24px;color:#0a0e1a;font-weight:700;line-height:1.3;letter-spacing:-0.01em;">${tituloEsc}</h1>
          </td>
        </tr>

        <!-- Cuerpo del mensaje -->
        <tr>
          <td style="padding:24px 48px 0;">
            <p style="margin:0;font-size:15px;color:#3a3f4e;line-height:1.75;">${mensajeEsc}</p>
          </td>
        </tr>

        ${imagenUrl ? `
        <tr>
          <td style="padding:28px 48px 0;">
            <img src="${imagenUrl}" alt="" style="width:100%;max-width:504px;display:block;border:1px solid #e8e3d4;">
          </td>
        </tr>` : ''}

        ${contratoCard}

        <!-- CTA -->
        <tr>
          <td style="padding:36px 48px 8px;">
            <table cellpadding="0" cellspacing="0">
              <tr>
                <td style="background:#0a0e1a;">
                  <a href="https://miavance.com" style="display:inline-block;padding:14px 32px;color:#c9a96e;text-decoration:none;font-size:13px;font-weight:700;letter-spacing:0.12em;text-transform:uppercase;border:1px solid #c9a96e;">
                    Ingresar al portal
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        ${asesorBlock}

        <!-- Footer institucional -->
        <tr>
          <td style="background:#0a0e1a;padding:32px 48px;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td>
                  <div style="font-size:13px;color:#c9a96e;font-weight:700;letter-spacing:0.06em;margin-bottom:6px;">AVANCE CORP S.A.C.</div>
                  <div style="font-size:11px;color:#8a8a8a;line-height:1.7;">
                    RUC 20611392088<br>
                    San Isidro · Lima · Per&uacute;<br>
                    <a href="mailto:info@miavance.com" style="color:#c9a96e;text-decoration:none;">info@miavance.com</a> &nbsp;·&nbsp;
                    <a href="https://miavance.com" style="color:#c9a96e;text-decoration:none;">miavance.com</a>
                  </div>
                </td>
              </tr>
              <tr>
                <td style="padding-top:20px;border-top:1px solid #1a1f2e;margin-top:20px;">
                  <div style="font-size:10px;color:#5a5a5a;line-height:1.6;padding-top:16px;">
                    Recibiste este correo porque eres cliente activo de Avance Corp S.A.C.<br>
                    Comunicaci&oacute;n institucional. No respondas a este mensaje; usa los canales oficiales arriba.
                  </div>
                </td>
              </tr>
            </table>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`
}
