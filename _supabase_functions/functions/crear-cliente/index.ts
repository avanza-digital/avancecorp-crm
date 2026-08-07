import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
// Reglas de documento (DNI/CE/Pasaporte): única fuente compartida con
// `importar-clientes` y espejo del frontend (js/admin/documento-core.js).
import {
  claveTemporalDesdeDocumento,
  esTipoDocumento,
  normalizarDocumento,
  normalizarTipoDocumento,
  validarDocumento,
} from "../_shared/documento.ts";
// Datos bancarios: misma frontera que usa crm-convertir-lead, para que las dos
// puertas de alta de clientes no puedan divergir.
import { validarBancarios } from "../_shared/bancarios.mjs";

const ALLOWED_ORIGINS = new Set([
  "https://miavance.com",
  "https://www.miavance.com",
  // El alta de clientes también vive en el CRM (traspaso del panel analista,
  // 2026-07-16). El CORS solo decide desde qué páginas puede llamar un
  // navegador; la autorización real sigue siendo el JWT + rol de abajo.
  "https://crm.miavance.com",
  // localhost:5173 (desarrollo local) se RETIRÓ el 2026-07-27 (go-live del
  // equipo): en dev el alta real se prueba contra el mock de Playwright, no
  // contra prod. Si algún día hace falta de nuevo, es re-agregarlo y redeploy.
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

    // El portal conserva sus roles. La única ampliación es Gerencia ACTIVA del
    // CRM: puede dar de alta desde crm.miavance.com sin volverse admin global.
    const portalPuedeCrear = perfil?.activo && ["admin", "superadmin", "analista"].includes(perfil.rol);
    let gerenciaCrm = false;
    if (perfil?.activo && !portalPuedeCrear) {
      const { data: miembro } = await adminClient
        .schema("crm")
        .from("equipo")
        .select("rol_crm, activo")
        .eq("perfil_id", userRes.user.id)
        .maybeSingle();
      gerenciaCrm = miembro?.activo === true && miembro.rol_crm === "gerencia";
    }
    if (!perfil || !perfil.activo || (!portalPuedeCrear && !gerenciaCrm)) {
      return json(cors, { error: "No autorizado" }, 403);
    }

    const body = await req.json();
    const { email, password, nombre_completo, apellidos, nombres, dni, telefono, tipo_documento, bancarios } = body || {};

    if (!email || !nombre_completo) {
      return json(cors, { error: "email y nombre_completo son obligatorios" }, 400);
    }

    // DATOS BANCARIOS (2026-07-27) — ADITIVO Y RETROCOMPATIBLE. El portal
    // (js/admin/clientes.js) NO manda este bloque y sigue con su flujo de
    // siempre: crea el cliente aquí y escribe las cuentas en un UPDATE aparte.
    // El CRM SÍ lo manda, y entonces las cuentas entran en el MISMO INSERT del
    // cliente — sin ventana en la que exista un cliente, con su correo ya
    // enviado, al que el área de pagos no le puede transferir. Si el bloque
    // viene, se valida completo (fail-closed): mandarlo a medias es un 400.
    let columnasBancarias = {};
    if (bancarios !== undefined && bancarios !== null) {
      const valBancarios = validarBancarios(bancarios);
      if (!valBancarios.ok) return json(cors, { error: valBancarios.error }, 400);
      columnasBancarias = valBancarios.columnas;
    }

    const emailNormalizado = email.trim().toLowerCase();
    // apellidos/nombres separados (2026-06-09). Opcionales para retrocompatibilidad:
    // si vienen, se persisten y nombre_completo debe venir derivado APELLIDOS primero
    // (lo arma el frontend); si no vienen (caller viejo), solo se guarda nombre_completo.
    const apellidosNorm = (apellidos ?? "").toString().trim() || null;
    const nombresNorm = (nombres ?? "").toString().trim() || null;
    if ((apellidosNorm && !nombresNorm) || (!apellidosNorm && nombresNorm)) {
      return json(cors, { error: "apellidos y nombres deben venir juntos (ambos o ninguno)" }, 400);
    }
    const nombreNormalizado = apellidosNorm && nombresNorm
      ? `${apellidosNorm} ${nombresNorm}`.replace(/\s+/g, " ").trim()
      : nombre_completo.trim();

    // Documento por TIPO (DNI/CE/Pasaporte, 2026-07-14). Callers viejos no mandan
    // tipo → default DNI. VALIDAMOS EN LA FRONTERA (el navegador es solo espejo):
    // el documento además se vuelve la clave temporal, no puede entrar basura.
    // Tipo PRESENTE pero desconocido → error explícito, nunca DNI en silencio.
    if (tipo_documento && !esTipoDocumento(tipo_documento)) {
      return json(cors, { error: "Tipo de documento no reconocido: usa DNI, CE o PASAPORTE" }, 400);
    }
    const tipoDoc = normalizarTipoDocumento(tipo_documento);
    const dniLimpio = normalizarDocumento(tipoDoc, dni);
    if (dniLimpio) {
      const errDoc = validarDocumento(tipoDoc, dniLimpio);
      if (errDoc) return json(cors, { error: errDoc }, 400);
    }

    // La contraseña es OPCIONAL. Si el admin la envía, se usa tal cual (mín. 8).
    // Si NO la envía (alta sin escribir clave), se usa el DOCUMENTO como CLAVE
    // TEMPORAL, completado a un mínimo de 8 caracteres con ceros a la izquierda
    // (Supabase Auth exige ≥ 8; además recupera el cero inicial que las hojas de
    // cálculo borran de los DNI). El cliente queda obligado a cambiar la clave
    // en su primer ingreso.
    let passwordFinal: string;
    let claveTemporal = false;
    if (password) {
      if (String(password).length < 8) {
        return json(cors, { error: "La contraseña debe tener al menos 8 caracteres" }, 400);
      }
      passwordFinal = String(password);
    } else {
      if (!dniLimpio) {
        return json(cors, { error: "Sin contraseña explícita se necesita el número de documento para generar la clave temporal" }, 400);
      }
      passwordFinal = claveTemporalDesdeDocumento(dniLimpio);
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
        apellidos: apellidosNorm,
        nombres: nombresNorm,
        tipo_documento: tipoDoc,
        dni: dniLimpio || null,
        telefono: telefono?.trim() || null,
        correo: emailNormalizado,
        rol: "cliente",
        activo: true,
        creado_por: userRes.user.id,
        debe_cambiar_password: claveTemporal,
        // El analista se autoasigna. Gerencia y administradores crean al cliente
        // sin asesor; la distribución comercial se mantiene como acto separado.
        asesor_perfil_id: perfil.rol === "analista" ? userRes.user.id : null,
        // Vacío cuando el caller no manda el bloque (portal): el insert queda
        // EXACTAMENTE como antes.
        ...columnasBancarias,
      });

    if (perfilErr) {
      await adminClient.auth.admin.deleteUser(newUserId);
      // El disparador sigue anclado al NOMBRE del constraint (perfiles_dni_key),
      // no al texto visible: la columna no se renombró.
      if (/duplicate key/i.test(perfilErr.message) && /dni/i.test(perfilErr.message)) {
        return json(cors, { error: "Este documento ya está registrado" }, 409);
      }
      // Violación de CHECK (23514): mensaje limpio, sin filtrar el valor del
      // documento (PII) ni la definición del constraint en la respuesta.
      if (perfilErr.code === "23514") {
        return json(cors, { error: "El tipo o número de documento no es válido" }, 400);
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
              // Saludo por el primer NOMBRE de pila, no por el apellido: con la
              // separación apellidos/nombres el nombre_completo empieza por los
              // apellidos, así que el saludo sale del campo nombres si existe.
              nombre: nombresNorm || nombreNormalizado,
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

// Saludo del email: usa solo el PRIMER nombre con Mayúscula-inicial (ej. "JOSÉ
// PÉREZ GARCÍA" → "José"), un saludo más cálido que el nombre completo en
// mayúsculas. El resto del sistema guarda el nombre completo en MAYÚSCULA (norma
// de datos); esto es solo presentación del saludo.
function nombreSaludo(nombre: string): string {
  const primero = (nombre || "").trim().split(/\s+/)[0] || "";
  if (!primero) return "estimado(a) cliente";
  return primero.charAt(0).toUpperCase() + primero.slice(1).toLowerCase();
}

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
                  <td class="ac-px" style="padding:24px 40px 0 40px;">
                    <div style="font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:10px; font-weight:700; letter-spacing:0.16em; color:#1f8a4a; text-transform:uppercase; padding-bottom:12px;">Con tu portal puedes</div>
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:14px; color:#3a4a6b; line-height:1.5;">
                      <tr>
                        <td width="30" valign="top" style="padding:6px 0;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="22" height="22" align="center" valign="middle" style="width:22px; height:22px; background-color:#2fa855; border-radius:50%; color:#ffffff; font-size:12px; font-weight:700; line-height:22px;">&#10003;</td></tr></table>
                        </td>
                        <td valign="middle" style="padding:6px 0 6px 10px;">Consultar tus <strong style="color:#0f1e3d;">contratos y rendimientos</strong> al día</td>
                      </tr>
                      <tr>
                        <td width="30" valign="top" style="padding:6px 0;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="22" height="22" align="center" valign="middle" style="width:22px; height:22px; background-color:#2fa855; border-radius:50%; color:#ffffff; font-size:12px; font-weight:700; line-height:22px;">&#10003;</td></tr></table>
                        </td>
                        <td valign="middle" style="padding:6px 0 6px 10px;">Seguir tu <strong style="color:#0f1e3d;">cronograma de pagos</strong> y tus abonos</td>
                      </tr>
                      <tr>
                        <td width="30" valign="top" style="padding:6px 0;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="22" height="22" align="center" valign="middle" style="width:22px; height:22px; background-color:#2fa855; border-radius:50%; color:#ffffff; font-size:12px; font-weight:700; line-height:22px;">&#10003;</td></tr></table>
                        </td>
                        <td valign="middle" style="padding:6px 0 6px 10px;">Acceder a tus <strong style="color:#0f1e3d;">documentos y novedades</strong> cuando quieras</td>
                      </tr>
                    </table>
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
                            <tr>
                              <td style="padding:0 0 4px 0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:10px; font-weight:700; letter-spacing:0.1em; color:#8b95ac; text-transform:uppercase;">Correo</td>
                            </tr>
                            <tr>
                              <td style="padding:0 0 14px 0; font-family:'Consolas','Menlo',monospace; font-size:15px; font-weight:600; color:#0f1e3d; word-break:break-all;">${correo}</td>
                            </tr>
                            <tr>
                              <td style="padding:0; border-top:1px solid #e4e9f2;">&nbsp;</td>
                            </tr>
                            <tr>
                              <td style="padding:0 0 6px 0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:10px; font-weight:700; letter-spacing:0.1em; color:#8b95ac; text-transform:uppercase;">${escapeHtml(labelPwd)}</td>
                            </tr>
                            <tr>
                              <td style="padding:0 0 2px 0;">
                                <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td style="background-color:#eaf6ef; border-radius:8px; padding:8px 14px; font-family:'Consolas','Menlo',monospace; font-size:17px; font-weight:700; color:#1f8a4a; letter-spacing:0.06em;">${pwd}</td></tr></table>
                              </td>
                            </tr>
                          </table>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:14px 22px 18px 22px;">
                          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#ffffff; border:1px solid #e8ecf4; border-radius:8px;">
                            <tr>
                              <td style="padding:11px 14px; border-left:4px solid #2fa855; border-radius:8px; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:12px; line-height:1.55; color:#5a6480;">
                                ${escapeHtml(avisoPwd)}
                              </td>
                            </tr>
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
                  <td class="ac-px" style="padding:28px 40px 0 40px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="height:1px; line-height:1px; font-size:1px; background-color:#e8ecf4;">&nbsp;</td></tr></table>
                  </td>
                </tr>
              </table>

              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="ac-px" style="padding:26px 40px 0 40px;">
                    <div style="font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:10px; font-weight:700; letter-spacing:0.16em; color:#1f8a4a; text-transform:uppercase; padding-bottom:8px;">En tu celular</div>
                    <h2 style="margin:0 0 6px 0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:17px; font-weight:800; letter-spacing:-0.01em; color:#0f1e3d;">
                      Instala el portal como una app
                    </h2>
                    <p style="margin:0 0 16px 0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:14px; line-height:1.65; color:#5a6480;">
                      Tenlo siempre a mano, como una aplicación. Solo 3 pasos:
                    </p>
                  </td>
                </tr>
                <tr>
                  <td class="ac-px" style="padding:0 40px 0 40px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:14px; color:#3a4a6b; line-height:1.6;">
                      <tr>
                        <td width="34" valign="top" style="padding:7px 0;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="24" height="24" align="center" valign="middle" style="width:24px; height:24px; background-color:#0f1e3d; color:#ffffff; border-radius:50%; font-size:12px; font-weight:700; line-height:24px;">1</td></tr></table>
                        </td>
                        <td valign="top" style="padding:7px 0 7px 10px;">
                          Entra a <a href="${PORTAL_URL}" target="_blank" style="color:#1f8a4a; font-weight:600; text-decoration:underline;">miavance.com</a> desde el navegador de tu celular (Safari en iPhone, Chrome en Android).
                        </td>
                      </tr>
                      <tr>
                        <td width="34" valign="top" style="padding:7px 0;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="24" height="24" align="center" valign="middle" style="width:24px; height:24px; background-color:#0f1e3d; color:#ffffff; border-radius:50%; font-size:12px; font-weight:700; line-height:24px;">2</td></tr></table>
                        </td>
                        <td valign="top" style="padding:7px 0 7px 10px;">
                          Toca el ícono <strong style="color:#0f1e3d;">Compartir</strong> (iPhone) o el menú de <strong style="color:#0f1e3d;">3 puntos</strong> (Android).
                        </td>
                      </tr>
                      <tr>
                        <td width="34" valign="top" style="padding:7px 0;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="24" height="24" align="center" valign="middle" style="width:24px; height:24px; background-color:#0f1e3d; color:#ffffff; border-radius:50%; font-size:12px; font-weight:700; line-height:24px;">3</td></tr></table>
                        </td>
                        <td valign="top" style="padding:7px 0 7px 10px;">
                          Elige <strong style="color:#0f1e3d;">"Añadir a inicio"</strong> y listo: el portal aparecerá como una app en tu pantalla.
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td class="ac-px" style="padding:14px 40px 0 40px;">
                    <p style="margin:0; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:13px; line-height:1.6; color:#5a6480;">
                      Guía detallada paso a paso: <a href="${GUIA_INSTALACION_URL}" target="_blank" style="color:#1f8a4a; font-weight:600; text-decoration:underline;">miavance.com/instalar</a>
                    </p>
                  </td>
                </tr>
              </table>

              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="ac-px" style="padding:26px 40px 0 40px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f7fb; border-radius:12px;">
                      <tr>
                        <td style="padding:16px 18px; border-left:4px solid #2fa855; border-radius:12px; font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:13px; line-height:1.6; color:#5a6480;">
                          <strong style="color:#3a4a6b;">¿Tienes dudas?</strong> Tu asesor asignado te contactará en los próximos días. También puedes escribirnos a <a href="mailto:info@miavance.com" style="color:#1f8a4a; font-weight:600; text-decoration:none;">info@miavance.com</a>.
                        </td>
                      </tr>
                    </table>
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
