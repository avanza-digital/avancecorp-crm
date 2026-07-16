import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Reglas de documento (DNI/CE/Pasaporte) — ESPEJO de ../_shared/documento.ts y del
// frontend documento-core.js. Inlineado a propósito (edge autocontenido): si se
// cambia una regla aquí, cambiarla también en el shared/core (misma que el CHECK de BD).
type TipoDocumento = "DNI" | "CE" | "PASAPORTE";
const TIPOS_DOCUMENTO: Record<TipoDocumento, { regex: RegExp; mayusculas: boolean; error: string }> = {
  DNI: { regex: /^\d{8}$/, mayusculas: false, error: "El DNI debe tener exactamente 8 dígitos." },
  CE: { regex: /^\d{9,12}$/, mayusculas: false, error: "El Carné de Extranjería debe tener entre 9 y 12 dígitos." },
  PASAPORTE: { regex: /^[A-Z0-9]{6,12}$/, mayusculas: true, error: "El Pasaporte debe tener entre 6 y 12 caracteres (solo letras y números)." },
};
function normalizarTipoDocumento(tipo: unknown): TipoDocumento {
  const t = String(tipo ?? "").trim().toUpperCase();
  return t in TIPOS_DOCUMENTO ? (t as TipoDocumento) : "DNI";
}
function esTipoDocumento(tipo: unknown): boolean {
  return String(tipo ?? "").trim().toUpperCase() in TIPOS_DOCUMENTO;
}
function normalizarDocumento(tipo: TipoDocumento, valor: unknown): string {
  const v = String(valor ?? "").trim();
  return TIPOS_DOCUMENTO[tipo].mayusculas ? v.toUpperCase() : v;
}
function validarDocumento(tipo: TipoDocumento, valor: string): string | null {
  return TIPOS_DOCUMENTO[tipo].regex.test(valor) ? null : TIPOS_DOCUMENTO[tipo].error;
}
function claveTemporalDesdeDocumento(documento: string): string {
  const doc = String(documento ?? "").trim();
  return doc.length >= 8 ? doc : doc.padStart(8, "0");
}

// El CRM vive en su propio subdominio (separación CRM/portal). CORS acotado a él.
const ALLOWED_ORIGINS = new Set([
  "https://crm.miavance.com",
  "https://www.crm.miavance.com",
]);

const PORTAL_URL = "https://miavance.com";
const GUIA_INSTALACION_URL = "https://miavance.com/instalar";
const FROM_EMAIL = "Avance Corp <info@miavance.com>";

function corsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin) ? origin : "https://crm.miavance.com",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json(cors, { error: "Falta header Authorization" }, 401);
    const token = authHeader.replace("Bearer ", "");

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    });
    // Cliente con la sesión del que llama: la RLS del esquema crm decide qué lead
    // ve y la RPC convertir_lead autoriza por auth.uid(). Nunca confiamos en ids
    // del body para el ámbito.
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });

    const { data: userRes, error: userErr } = await adminClient.auth.getUser(token);
    if (userErr || !userRes?.user) return json(cors, { error: "Sesión inválida" }, 401);
    const callerId = userRes.user.id;

    // El que convierte debe ser miembro escritor del equipo CRM (vendedor/supervisor/gerencia).
    const { data: miembro } = await adminClient
      .schema("crm").from("equipo")
      .select("rol_crm, activo").eq("perfil_id", callerId).maybeSingle();
    if (!miembro || !miembro.activo || !["vendedor", "supervisor", "gerencia"].includes(miembro.rol_crm)) {
      return json(cors, { error: "No autorizado para convertir leads" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const {
      lead_id, correo, tipo_documento, documento,
      nombre_completo, apellidos, nombres, telefono,
    } = body || {};

    if (!lead_id) return json(cors, { error: "Falta lead_id" }, 400);
    if (!correo || !nombre_completo) {
      return json(cors, { error: "Correo y nombre del cliente son obligatorios" }, 400);
    }
    const emailNormalizado = String(correo).trim().toLowerCase();

    // AUTORIZACIÓN DE ÁMBITO: leemos el lead con la sesión del que llama → la RLS
    // garantiza que solo pasa si el lead está en su ámbito (fail-closed).
    const { data: lead, error: leadErr } = await userClient
      .schema("crm").from("leads")
      .select("id, etapa, activo, dni, telefono, nombre_completo, vendedor_id, perfil_id")
      .eq("id", lead_id).maybeSingle();
    if (leadErr) return json(cors, { error: "No se pudo leer el lead" }, 400);
    if (!lead) return json(cors, { error: "Lead no encontrado o fuera de tu ámbito" }, 404);
    if (!lead.activo || lead.etapa === "convertido" || lead.etapa === "descartado") {
      return json(cors, { error: "El lead ya está cerrado" }, 409);
    }

    // Documento (DNI/CE/Pasaporte). Se valida en la FRONTERA (el navegador es espejo).
    if (tipo_documento && !esTipoDocumento(tipo_documento)) {
      return json(cors, { error: "Tipo de documento no reconocido: usa DNI, CE o PASAPORTE" }, 400);
    }
    const tipoDoc = normalizarTipoDocumento(tipo_documento);
    const dniLimpio = normalizarDocumento(tipoDoc, documento);
    if (!dniLimpio) {
      return json(cors, { error: "El documento del cliente es obligatorio para convertir" }, 400);
    }
    const errDoc = validarDocumento(tipoDoc, dniLimpio);
    if (errDoc) return json(cors, { error: errDoc }, 400);

    // Asesor del nuevo cliente = el VENDEDOR dueño del lead (si lo tiene), si no
    // el que convierte. Así el cliente entra en su cartera y puede hacerle el contrato.
    const asesorId = lead.vendedor_id ?? callerId;

    // DEDUP: ¿ese documento ya es un cliente del portal? Entonces se ENLAZA (no se
    // duplica ni se reenvía correo) — cubre el caso "colaborador que ya es cliente".
    const { data: existente } = await adminClient
      .from("perfiles").select("id, activo")
      .eq("dni", dniLimpio).eq("rol", "cliente").maybeSingle();

    let perfilId: string;
    let yaExistia = false;
    let emailEnviado = false;
    let emailError: string | undefined;

    if (existente) {
      if (!existente.activo) return json(cors, { error: "Ese cliente existe pero está inactivo en el portal" }, 409);
      perfilId = existente.id;
      yaExistia = true;
    } else {
      // Nombre canónico. Si vienen apellidos+nombres se respeta el orden del portal.
      const apellidosNorm = (apellidos ?? "").toString().trim() || null;
      const nombresNorm = (nombres ?? "").toString().trim() || null;
      if ((apellidosNorm && !nombresNorm) || (!apellidosNorm && nombresNorm)) {
        return json(cors, { error: "apellidos y nombres deben venir juntos (ambos o ninguno)" }, 400);
      }
      const nombreNormalizado = apellidosNorm && nombresNorm
        ? `${apellidosNorm} ${nombresNorm}`.replace(/\s+/g, " ").trim()
        : String(nombre_completo).trim();

      // Clave temporal = documento (regla del portal). Cambio obligatorio al ingresar.
      const passwordFinal = claveTemporalDesdeDocumento(dniLimpio);

      const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
        email: emailNormalizado,
        password: passwordFinal,
        email_confirm: true,
        user_metadata: { nombre: nombreNormalizado },
      });
      if (createErr || !created?.user) {
        const msg = createErr?.message || "";
        if (/already been registered|already exists/i.test(msg)) {
          return json(cors, { error: "Ese correo ya está registrado en el portal" }, 409);
        }
        return json(cors, { error: msg || "No se pudo crear el usuario" }, 400);
      }
      perfilId = created.user.id;

      const { error: perfilErr } = await adminClient.from("perfiles").insert({
        id: perfilId,
        nombre_completo: nombreNormalizado,
        apellidos: apellidosNorm,
        nombres: nombresNorm,
        tipo_documento: tipoDoc,
        dni: dniLimpio,
        telefono: (telefono ?? lead.telefono ?? "").toString().trim() || null,
        correo: emailNormalizado,
        rol: "cliente",
        activo: true,
        creado_por: callerId,
        debe_cambiar_password: true,
        asesor_perfil_id: asesorId,
      });
      if (perfilErr) {
        await adminClient.auth.admin.deleteUser(perfilId);
        if (/duplicate key/i.test(perfilErr.message) && /dni/i.test(perfilErr.message)) {
          return json(cors, { error: "Este documento ya está registrado" }, 409);
        }
        if (perfilErr.code === "23514") return json(cors, { error: "El tipo o número de documento no es válido" }, 400);
        return json(cors, { error: `Error al crear el cliente: ${perfilErr.message}` }, 400);
      }

      // Correo de bienvenida (background-tolerante: si Resend falla NO rompe la conversión).
      const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
      if (!RESEND_API_KEY) {
        emailError = "RESEND_API_KEY no configurada";
      } else {
        try {
          const res = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: { "Authorization": `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              from: FROM_EMAIL,
              to: [emailNormalizado],
              subject: "Bienvenido(a) a tu portal de inversiones Avance Corp",
              html: plantillaBienvenida({
                nombre: nombresNorm || nombreNormalizado,
                correo: emailNormalizado,
                passwordInicial: passwordFinal,
                claveTemporal: true,
              }),
            }),
          });
          if (res.ok) emailEnviado = true;
          else emailError = `Resend respondió ${res.status}`;
        } catch (e) {
          emailError = (e as Error)?.message || "Error al enviar el correo";
        }
      }
    }

    // ENLACE + cierre del lead como ganado (RPC privilegiada, autoriza por ámbito).
    const { error: convErr } = await userClient
      .schema("crm").rpc("convertir_lead", { p_lead_id: lead_id, p_perfil_id: perfilId });
    if (convErr) {
      // El cliente pudo haberse creado; NO se borra (el documento ya quedó registrado
      // y un reintento lo detecta por dedup y solo enlaza). Se reporta el fallo del enlace.
      return json(cors, {
        error: `El cliente quedó creado, pero no se pudo cerrar el lead: ${convErr.message}. Reintenta la conversión.`,
        perfil_id: perfilId, cliente_creado: !yaExistia,
      }, 409);
    }

    return json(cors, {
      ok: true,
      perfil_id: perfilId,
      ya_existia: yaExistia,
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
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function nombreSaludo(nombre: string): string {
  const primero = (nombre || "").trim().split(/\s+/)[0] || "";
  if (!primero) return "estimado(a) cliente";
  return primero.charAt(0).toUpperCase() + primero.slice(1).toLowerCase();
}

// Plantilla de bienvenida: ESPEJO de la de crear-cliente (misma identidad de marca
// navy+verde). Si se cambia una, cambiar la otra para no divergir.
function plantillaBienvenida(opts: {
  nombre: string;
  correo: string;
  passwordInicial: string;
  claveTemporal?: boolean;
}): string {
  const nombre = escapeHtml(nombreSaludo(opts.nombre));
  const correo = escapeHtml(opts.correo);
  const pwd = escapeHtml(opts.passwordInicial);
  const esTemporal = !!opts.claveTemporal;
  const labelPwd = esTemporal ? "Contraseña temporal" : "Contraseña";
  const avisoPwd = esTemporal
    ? "Tu contraseña temporal es tu número de documento. Por seguridad, la primera vez que ingreses el portal te pedirá crear tu propia contraseña."
    : "Por seguridad, te recomendamos cambiar tu contraseña la primera vez que ingreses al portal.";
  const preheader = `Tu Portal de Inversiones Avance Corp ya está listo. Estas son tus credenciales de acceso.`;

  return `<!DOCTYPE html>
<html lang="es" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>Bienvenido(a) a tu Portal de Inversiones — Avance Corp</title>
<!--[if mso]>
<noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript>
<![endif]-->
<style>
  html, body { margin: 0 !important; padding: 0 !important; height: 100% !important; width: 100% !important; }
  * { -ms-text-size-adjust: 100%; -webkit-text-size-adjust: 100%; }
  table, td { mso-table-lspace: 0pt !important; mso-table-rspace: 0pt !important; border-collapse: collapse !important; }
  img { -ms-interpolation-mode: bicubic; border: 0; height: auto; line-height: 100%; outline: none; text-decoration: none; }
  a { text-decoration: none; }
  .ExternalClass { width: 100%; }
  .ExternalClass, .ExternalClass p, .ExternalClass span, .ExternalClass font, .ExternalClass td, .ExternalClass div { line-height: 100%; }
  @media only screen and (max-width: 620px) {
    .ac-container { width: 100% !important; }
    .ac-px { padding-left: 24px !important; padding-right: 24px !important; }
    .ac-h1 { font-size: 22px !important; }
    .ac-btn a { display: block !important; }
  }
  @media (prefers-color-scheme: dark) {
    body, .ac-bg { background-color: #0a1224 !important; }
  }
</style>
</head>
<body style="margin:0; padding:0; width:100%; background-color:#eef1f7;">
  <div style="display:none; max-height:0; overflow:hidden; mso-hide:all; font-size:1px; line-height:1px; color:#eef1f7; opacity:0;">
    ${escapeHtml(preheader)}
    &#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;
  </div>
  <table role="presentation" class="ac-bg" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#eef1f7;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" class="ac-container" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px; max-width:600px;">
          <tr>
            <td style="height:6px; line-height:6px; font-size:6px; background-color:#2fa855; border-radius:16px 16px 0 0;">&nbsp;</td>
          </tr>
          <tr>
            <td style="background-color:#ffffff; border-radius:0 0 16px 16px; border:1px solid #e4e9f2; border-top:0;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="padding:34px 24px 4px 24px;">
                    <img src="https://miavance.com/img/avance-logo-full.png" width="164" alt="Avance Corp — Tu mejor opción de inversión" style="display:block; width:164px; max-width:164px; height:auto;">
                  </td>
                </tr>
                <tr>
                  <td align="center" style="padding:2px 24px 4px 24px;">
                    <span style="font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:10px; font-weight:700; letter-spacing:0.22em; color:#1f8a4a; text-transform:uppercase;">Portal de Inversiones</span>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="ac-px" align="center" style="padding:22px 40px 0 40px;">
                    <p style="margin:0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:13px; line-height:1.4; color:#8b95ac; letter-spacing:0.04em;">Te damos la bienvenida</p>
                    <h1 class="ac-h1" style="margin:6px 0 0 0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:27px; line-height:1.22; font-weight:800; letter-spacing:-0.02em; color:#0f1e3d;">
                      Hola ${nombre} 👋
                    </h1>
                  </td>
                </tr>
                <tr>
                  <td class="ac-px" align="center" style="padding:12px 44px 0 44px;">
                    <p style="margin:0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; line-height:1.65; color:#5a6480;">
                      Tu <strong style="color:#3a4a6b;">Portal de Inversiones</strong> ya está listo. Todo tu dinero trabajando, en un solo lugar y a un toque de distancia.
                    </p>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="ac-px" style="padding:26px 40px 0 40px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f7f9fc; border:1px solid #e4e9f2; border-radius:14px;">
                      <tr>
                        <td style="padding:20px 22px 4px 22px;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                            <tr>
                              <td width="26" valign="middle" style="padding-right:8px;">
                                <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="26" height="26" align="center" valign="middle" style="width:26px; height:26px; background-color:#0f1e3d; border-radius:7px; color:#ffffff; font-size:13px; line-height:26px;">&#128273;</td></tr></table>
                              </td>
                              <td valign="middle" style="font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:11px; font-weight:700; letter-spacing:0.14em; color:#0f1e3d; text-transform:uppercase;">Tus datos de acceso</td>
                            </tr>
                          </table>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:12px 22px 0 22px;">
                          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                            <tr><td style="padding:0 0 4px 0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:10px; font-weight:700; letter-spacing:0.1em; color:#8b95ac; text-transform:uppercase;">Correo</td></tr>
                            <tr><td style="padding:0 0 14px 0; font-family:'Consolas','Menlo',monospace; font-size:15px; font-weight:600; color:#0f1e3d; word-break:break-all;">${correo}</td></tr>
                            <tr><td style="padding:0; border-top:1px solid #e4e9f2;">&nbsp;</td></tr>
                            <tr><td style="padding:0 0 6px 0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:10px; font-weight:700; letter-spacing:0.1em; color:#8b95ac; text-transform:uppercase;">${escapeHtml(labelPwd)}</td></tr>
                            <tr><td style="padding:0 0 2px 0;">
                              <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td style="background-color:#eaf6ef; border-radius:8px; padding:8px 14px; font-family:'Consolas','Menlo',monospace; font-size:17px; font-weight:700; color:#1f8a4a; letter-spacing:0.06em;">${pwd}</td></tr></table>
                            </td></tr>
                          </table>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:14px 22px 18px 22px;">
                          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#ffffff; border:1px solid #e8ecf4; border-radius:8px;">
                            <tr><td style="padding:11px 14px; border-left:4px solid #2fa855; border-radius:8px; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:12px; line-height:1.55; color:#5a6480;">${escapeHtml(avisoPwd)}</td></tr>
                          </table>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="ac-btn" align="center" style="padding:26px 40px 6px 40px;">
                    <!--[if mso]>
                    <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="${PORTAL_URL}" style="height:52px;v-text-anchor:middle;width:300px;" arcsize="20%" strokecolor="#0f1e3d" fillcolor="#0f1e3d">
                      <w:anchorlock/>
                      <center style="color:#ffffff;font-family:Arial,sans-serif;font-size:16px;font-weight:bold;">Acceder al portal &#8594;</center>
                    </v:roundrect>
                    <![endif]-->
                    <!--[if !mso]><!-- -->
                    <a href="${PORTAL_URL}" target="_blank" style="display:inline-block; background-color:#0f1e3d; background-image:linear-gradient(135deg,#16294d 0%,#0f1e3d 100%); color:#ffffff; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:16px; font-weight:700; line-height:52px; text-align:center; text-decoration:none; padding:0 42px; border-radius:12px; letter-spacing:0.01em; box-shadow:0 8px 20px rgba(15,30,61,0.22);">
                      Acceder al portal &#8594;
                    </a>
                    <!--<![endif]-->
                  </td>
                </tr>
                <tr>
                  <td class="ac-px" align="center" style="padding:0 40px;">
                    <p style="margin:0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:12px; line-height:1.5; color:#8b95ac;">miavance.com</p>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="ac-px" style="padding:24px 40px 0 40px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="height:1px; line-height:1px; font-size:1px; background-color:#e8ecf4;">&nbsp;</td></tr></table>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="ac-px" style="padding:22px 40px 0 40px;">
                    <p style="margin:0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:13px; line-height:1.6; color:#5a6480;">
                      Guía de instalación en tu celular: <a href="${GUIA_INSTALACION_URL}" target="_blank" style="color:#1f8a4a; font-weight:600; text-decoration:underline;">miavance.com/instalar</a>
                    </p>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="ac-px" style="padding:22px 40px 34px 40px;">
                    <p style="margin:0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:14px; line-height:1.6; color:#5a6480;">
                      Un saludo,<br>
                      <strong style="color:#0f1e3d;">Equipo de Avance Corp</strong>
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 24px 8px 24px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:12px; line-height:1.7; color:#8b95ac;">
                    <strong style="color:#5a6480;">Avance Corp S.A.C.</strong> &nbsp;&middot;&nbsp; RUC 20611392088<br>
                    San Isidro, Lima &mdash; Per&uacute; &nbsp;&middot;&nbsp; Grupo MasCapital<br>
                    <a href="mailto:info@miavance.com" target="_blank" style="color:#1f8a4a; text-decoration:none; font-weight:600;">info@miavance.com</a> &nbsp;&middot;&nbsp;
                    <a href="${PORTAL_URL}" target="_blank" style="color:#1f8a4a; text-decoration:none; font-weight:600;">miavance.com</a>
                  </td>
                </tr>
                <tr>
                  <td align="center" style="padding-top:14px; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:11px; line-height:1.6; color:#aab3c6;">
                    Recibiste este correo porque acabas de ser registrado(a) como cliente de Avance Corp S.A.C.<br>
                    &copy; 2026 Avance Corp S.A.C. Todos los derechos reservados.
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}
