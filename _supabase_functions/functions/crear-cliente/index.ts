import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_ORIGINS = new Set([
  "https://miavance.com",
  "https://www.miavance.com",
]);

const PORTAL_URL = "https://miavance.com";
const GUIA_INSTALACION_URL = "https://miavance.com/instalar";
const FROM_EMAIL = "Avance Corp <info@miavance.com>";

function corsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin) ? origin : "https://miavance.com",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json(cors, { error: "Falta header Authorization" }, 401);

    const token = authHeader.replace("Bearer ", "");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    });

    const { data: userRes, error: userErr } = await adminClient.auth.getUser(token);
    if (userErr || !userRes?.user) return json(cors, { error: "Sesión inválida" }, 401);

    const { data: perfil } = await adminClient
      .from("perfiles")
      .select("rol, activo")
      .eq("id", userRes.user.id)
      .single();

    if (!perfil || !perfil.activo || !["admin", "superadmin"].includes(perfil.rol)) {
      return json(cors, { error: "No autorizado" }, 403);
    }

    const body = await req.json();
    const { email, password, nombre_completo, dni, telefono } = body || {};

    if (!email || !nombre_completo) {
      return json(cors, { error: "email y nombre_completo son obligatorios" }, 400);
    }

    const emailNormalizado = email.trim().toLowerCase();
    const nombreNormalizado = nombre_completo.trim();
    const dniLimpio = (dni ?? "").toString().trim();

    // La contraseña es OPCIONAL. Si el admin la envía, se usa tal cual (mín. 8).
    // Si NO la envía (alta sin escribir clave), se usa el DNI como CLAVE TEMPORAL,
    // completado a 8 caracteres con ceros a la izquierda (el DNI peruano son 8
    // dígitos; algunas hojas de cálculo borran el cero inicial → así se recupera).
    // En ese caso el cliente queda obligado a cambiar la clave en su primer ingreso.
    let passwordFinal: string;
    let claveTemporal = false;
    if (password) {
      if (String(password).length < 8) {
        return json(cors, { error: "La contraseña debe tener al menos 8 caracteres" }, 400);
      }
      passwordFinal = String(password);
    } else {
      if (!dniLimpio) {
        return json(cors, { error: "Sin contraseña explícita se necesita el DNI para generar la clave temporal" }, 400);
      }
      passwordFinal = dniLimpio.padStart(8, "0");
      claveTemporal = true;
    }

    const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
      email: emailNormalizado,
      password: passwordFinal,
      email_confirm: true,
      user_metadata: { nombre: nombreNormalizado },
    });

    if (createErr || !created?.user) {
      return json(cors, { error: createErr?.message || "No se pudo crear el usuario" }, 400);
    }

    const newUserId = created.user.id;

    const { error: perfilErr } = await adminClient
      .from("perfiles")
      .insert({
        id: newUserId,
        nombre_completo: nombreNormalizado,
        dni: dniLimpio || null,
        telefono: telefono?.trim() || null,
        correo: emailNormalizado,
        rol: "cliente",
        activo: true,
        creado_por: userRes.user.id,
        debe_cambiar_password: claveTemporal,
      });

    if (perfilErr) {
      await adminClient.auth.admin.deleteUser(newUserId);
      if (/duplicate key/i.test(perfilErr.message) && /dni/i.test(perfilErr.message)) {
        return json(cors, { error: "Este DNI ya está registrado" }, 409);
      }
      return json(cors, { error: `Error al crear perfil: ${perfilErr.message}` }, 400);
    }

    // === Envío de email de bienvenida (background, no bloqueante) ===
    const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
    let emailEnviado = false;
    let emailError: string | undefined;

    if (!RESEND_API_KEY) {
      emailError = "RESEND_API_KEY no configurada";
      console.warn("[crear-cliente] RESEND_API_KEY ausente; se omite envío de email");
    } else {
      // Intento síncrono pero tolerante: si Resend falla, NO rompemos la creación.
      // Esperamos al menos a obtener el status (rápido) para reportarlo al admin.
      try {
        const res = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${RESEND_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: FROM_EMAIL,
            to: [emailNormalizado],
            subject: "Bienvenido(a) a tu portal de inversiones Avance Corp",
            html: plantillaBienvenida({
              nombre: nombreNormalizado,
              correo: emailNormalizado,
              passwordInicial: passwordFinal,
              claveTemporal,
            }),
          }),
        });
        if (res.ok) {
          emailEnviado = true;
        } else {
          const txt = await res.text().catch(() => "");
          emailError = `Resend respondió ${res.status}: ${txt.slice(0, 200)}`;
          console.warn("[crear-cliente] Resend error:", emailError);
        }
      } catch (e) {
        emailError = (e as Error)?.message || "Error desconocido al enviar email";
        console.warn("[crear-cliente] excepción al enviar email:", emailError);
      }
    }

    return json(cors, {
      ok: true,
      user_id: newUserId,
      email: created.user.email,
      email_enviado: emailEnviado,
      ...(emailError ? { email_error: emailError } : {}),
    }, 200);

  } catch (e) {
    return json(corsHeaders(req), { error: (e as Error)?.message || "Error inesperado" }, 500);
  }
});

function json(cors: Record<string, string>, payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function plantillaBienvenida(opts: {
  nombre: string;
  correo: string;
  passwordInicial: string;
  claveTemporal?: boolean;
}): string {
  const nombre = escapeHtml(opts.nombre || "estimado(a) cliente");
  const correo = escapeHtml(opts.correo);
  const pwd = escapeHtml(opts.passwordInicial);
  const esTemporal = !!opts.claveTemporal;
  const labelPwd = esTemporal ? "Contraseña temporal" : "Contraseña";
  const avisoPwd = esTemporal
    ? "Tu contraseña temporal es tu número de documento (DNI). Por seguridad, la primera vez que ingreses el portal te pedirá crear tu propia contraseña."
    : "Por seguridad, te recomendamos cambiar tu contraseña la primera vez que ingreses al portal.";
  const preheader = `Tu portal de inversiones Avance Corp ya está listo. Estas son tus credenciales de acceso.`;

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="x-apple-disable-message-reformatting">
<title>Bienvenido a Avance Corp</title>
<!--[if mso]>
<style>body,table,td{font-family:'Segoe UI',Arial,sans-serif !important;}</style>
<![endif]-->
</head>
<body style="margin:0;padding:0;background:#f4f2ec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">

  <div style="display:none;font-size:1px;color:#f4f2ec;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">
    ${escapeHtml(preheader)}
  </div>

  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ec;padding:32px 16px;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;max-width:600px;width:100%;border:1px solid #e8e3d4;">

        <tr>
          <td style="background:#0a1f4a;padding:36px 48px;text-align:center;border-bottom:3px solid #c8922a;">
            <img src="https://miavance.com/img/avance-logo-full.png" alt="Avance Corp" width="180" style="display:block;margin:0 auto;max-width:180px;height:auto;">
            <div style="font-size:10px;color:#c8922a;margin-top:14px;letter-spacing:0.22em;font-weight:600;">PORTAL DE INVERSIONES</div>
          </td>
        </tr>

        <tr>
          <td style="padding:40px 48px 0;">
            <p style="margin:0;font-size:13px;color:#8a8780;letter-spacing:0.04em;">Bienvenido(a)</p>
            <p style="margin:4px 0 0;font-size:20px;color:#0a1f4a;font-weight:700;">Hola ${nombre}</p>
          </td>
        </tr>

        <tr>
          <td style="padding:18px 48px 0;">
            <div style="width:32px;height:2px;background:#c8922a;margin-bottom:18px;"></div>
            <p style="margin:0;font-size:15px;color:#3a3f4e;line-height:1.7;">
              Tu portal de inversiones <strong style="color:#0a1f4a;">AvanceCorp</strong> ya está listo.
              Desde aquí podrás consultar tus contratos, pagos, novedades y documentos en cualquier momento.
            </p>
          </td>
        </tr>

        <tr>
          <td style="padding:28px 48px 0;">
            <table width="100%" cellpadding="0" cellspacing="0" style="background:#f7f5ef;border:1px solid #e8e0c8;border-radius:6px;">
              <tr>
                <td style="padding:20px 22px 6px;">
                  <div style="font-size:10px;color:#8a7340;letter-spacing:0.18em;font-weight:700;text-transform:uppercase;margin-bottom:14px;">Tus datos de acceso</div>
                  <table width="100%" cellpadding="0" cellspacing="0" style="font-size:14px;color:#1a1f2e;">
                    <tr>
                      <td style="padding:6px 0;width:120px;color:#8a8780;font-size:12px;">Correo</td>
                      <td style="padding:6px 0;font-weight:600;font-family:'SF Mono','Menlo','Consolas',monospace;word-break:break-all;">${correo}</td>
                    </tr>
                    <tr>
                      <td style="padding:6px 0;width:120px;color:#8a8780;font-size:12px;border-top:1px solid #e8e0c8;">${escapeHtml(labelPwd)}</td>
                      <td style="padding:6px 0;font-weight:700;font-family:'SF Mono','Menlo','Consolas',monospace;color:#0a1f4a;border-top:1px solid #e8e0c8;">${pwd}</td>
                    </tr>
                  </table>
                </td>
              </tr>
              <tr>
                <td style="padding:0 22px 18px;">
                  <div style="font-size:11px;color:#8a7340;line-height:1.5;">
                    ${escapeHtml(avisoPwd)}
                  </div>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:32px 48px 8px;text-align:center;">
            <table cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;">
              <tr>
                <td style="background:#0a1f4a;">
                  <a href="${PORTAL_URL}" style="display:inline-block;padding:16px 38px;color:#c8922a;text-decoration:none;font-size:14px;font-weight:700;letter-spacing:0.12em;text-transform:uppercase;border:1px solid #c8922a;">
                    Acceder al portal
                  </a>
                </td>
              </tr>
            </table>
            <div style="font-size:12px;color:#8a8780;margin-top:12px;">${escapeHtml(PORTAL_URL)}</div>
          </td>
        </tr>

        <tr>
          <td style="padding:36px 48px 0;">
            <div style="width:32px;height:2px;background:#c8922a;margin-bottom:16px;"></div>
            <h2 style="margin:0 0 12px;font-size:17px;color:#0a1f4a;font-weight:700;letter-spacing:-0.01em;">
              ¿Cómo instalo la app en mi celular?
            </h2>
            <p style="margin:0 0 16px;font-size:14px;color:#3a3f4e;line-height:1.7;">
              Puedes usar el portal como una aplicación nativa en tu teléfono. Sigue estos 3 pasos:
            </p>
            <table width="100%" cellpadding="0" cellspacing="0" style="font-size:14px;color:#3a3f4e;line-height:1.65;">
              <tr>
                <td style="padding:8px 0;vertical-align:top;width:32px;">
                  <div style="width:24px;height:24px;background:#0a1f4a;color:#c8922a;border-radius:50%;text-align:center;font-weight:700;font-size:12px;line-height:24px;">1</div>
                </td>
                <td style="padding:8px 0 8px 12px;">
                  Entra a <a href="${PORTAL_URL}" style="color:#0a1f4a;font-weight:600;text-decoration:underline;">miavance.com</a> desde el navegador de tu celular (Safari en iPhone, Chrome en Android).
                </td>
              </tr>
              <tr>
                <td style="padding:8px 0;vertical-align:top;width:32px;">
                  <div style="width:24px;height:24px;background:#0a1f4a;color:#c8922a;border-radius:50%;text-align:center;font-weight:700;font-size:12px;line-height:24px;">2</div>
                </td>
                <td style="padding:8px 0 8px 12px;">
                  Toca el ícono <strong>Compartir</strong> (iPhone) o el menú <strong>de 3 puntos</strong> (Android).
                </td>
              </tr>
              <tr>
                <td style="padding:8px 0;vertical-align:top;width:32px;">
                  <div style="width:24px;height:24px;background:#0a1f4a;color:#c8922a;border-radius:50%;text-align:center;font-weight:700;font-size:12px;line-height:24px;">3</div>
                </td>
                <td style="padding:8px 0 8px 12px;">
                  Elige <strong>"Añadir a inicio"</strong> y listo: el portal aparecerá como una app en tu pantalla.
                </td>
              </tr>
            </table>
            <p style="margin:18px 0 0;font-size:13px;color:#3a3f4e;line-height:1.6;">
              Guía detallada paso a paso:
              <a href="${GUIA_INSTALACION_URL}" style="color:#0a1f4a;font-weight:600;text-decoration:underline;">${escapeHtml(GUIA_INSTALACION_URL)}</a>
            </p>
          </td>
        </tr>

        <tr>
          <td style="padding:32px 48px 8px;">
            <div style="border-top:1px solid #e8e3d4;padding-top:20px;font-size:13px;color:#3a3f4e;line-height:1.7;">
              Si tienes alguna duda, tu asesor asignado te contactará en los próximos días.
              También puedes escribirnos a <a href="mailto:info@miavance.com" style="color:#0a1f4a;font-weight:600;text-decoration:none;">info@miavance.com</a>.
            </div>
          </td>
        </tr>

        <tr>
          <td style="background:#0a1f4a;padding:32px 48px;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td>
                  <div style="font-size:13px;color:#c8922a;font-weight:700;letter-spacing:0.06em;margin-bottom:6px;">AVANCE CORP S.A.C.</div>
                  <div style="font-size:11px;color:#8a8a8a;line-height:1.7;">
                    RUC 20611392088<br>
                    San Isidro &middot; Lima &middot; Per&uacute;<br>
                    <a href="mailto:info@miavance.com" style="color:#c8922a;text-decoration:none;">info@miavance.com</a> &nbsp;&middot;&nbsp;
                    <a href="${PORTAL_URL}" style="color:#c8922a;text-decoration:none;">miavance.com</a>
                  </div>
                </td>
              </tr>
              <tr>
                <td style="padding-top:20px;">
                  <div style="font-size:10px;color:#5a5a5a;line-height:1.6;padding-top:16px;border-top:1px solid #1a2f5a;">
                    Recibiste este correo porque acabas de ser registrado(a) como cliente de Avance Corp S.A.C.<br>
                    Comunicaci&oacute;n institucional. Para cualquier consulta usa los canales oficiales arriba.
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
</html>`;
}
