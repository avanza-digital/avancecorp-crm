// Texto del aviso al cliente por un cambio de su cuenta de pago (F3.3, 26/09/2026).
// Puro y sin red: lo prueba aviso.test.ts. La cuenta nueva va TAPADA (••••1234); si es de
// un tercero, el aviso dice a nombre de quién está.

export type DatosAviso = {
  nombre_completo: string | null
  nombres: string | null
  banco_nuevo: string
  moneda: string
  ultimos_nuevo: string
  titular_distinto?: boolean
  beneficiario_nombre?: string | null
  contratos: string[]
  cambiado_en: string
}

// Fecha del cambio en hora de Lima: «26 de septiembre de 2026».
export function fechaLima(iso: string): string {
  const [y, m, d] = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date(iso)).split('-').map(Number)
  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
  return `${d} de ${meses[m - 1]} de ${y}`
}

// Clave del correo en Resend: una por solicitud, así un reintento no manda dos correos.
export function claveIdempotencia(solicitudId: string): string {
  return `cambio-cuenta-pago/${solicitudId.toLowerCase()}`
}

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

export function redactarAviso(d: DatosAviso): { titulo: string; mensaje: string } {
  const nombrePila = (d.nombres || d.nombre_completo || 'estimado cliente').split(' ')[0]
  const moneda = d.moneda === 'USD' ? 'dólares' : 'soles'
  const lista = d.contratos.length === 1
    ? `del contrato ${d.contratos[0]}`
    : `de los contratos ${d.contratos.slice(0, -1).join(', ')} y ${d.contratos[d.contratos.length - 1]}`
  const cuenta = d.titular_distinto
    ? `la cuenta ${d.banco_nuevo} en ${moneda} terminada en ••••${d.ultimos_nuevo}, a nombre de ${d.beneficiario_nombre || 'la persona que indicaste'}`
    : `tu cuenta ${d.banco_nuevo} en ${moneda} terminada en ••••${d.ultimos_nuevo}`
  const titulo = 'Cambio de tu cuenta de pago'
  const mensaje = `Hola ${nombrePila}, atendimos tu pedido: desde el ${fechaLima(d.cambiado_en)}, los pagos ${lista} se depositan en ${cuenta}. Los pagos ya realizados no cambian.\n\nSi tú no solicitaste este cambio, comunícate de inmediato con Avance Corp.`
  return { titulo, mensaje }
}

export function plantillaEmail(nombre: string, titulo: string, mensaje: string): string {
  const nombreEsc = escapeHtml(nombre)
  const tituloEsc = escapeHtml(titulo)
  const mensajeEsc = escapeHtml(mensaje).replace(/\n/g, '<br>')
  const preheader = escapeHtml(mensaje.slice(0, 110).replace(/\s+/g, ' ').trim())
  const etiqueta = 'CAMBIO DE CUENTA DE PAGO'

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
