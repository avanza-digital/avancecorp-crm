import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  authTieneMarca,
  correoYaRegistrado,
  decidirTrasFalloPerfil,
  interpretarReclamo,
} from "../_shared/saga-auth.mjs";
// Reglas de documento (DNI/CE/Pasaporte): única fuente compartida con
// `crear-cliente` y espejo del frontend (js/admin/documento-core.js).
import {
  claveTemporalDesdeDocumento,
  esTipoDocumento,
  normalizarDocumento,
  normalizarTipoDocumento,
  RE_DOC_GENERICO,
  type TipoDocumento,
  validarDocumento,
} from "../_shared/documento.ts";

// ============================================================================
// importar-clientes — alta MASIVA de clientes desde un Excel.
//
// Modelada sobre `crear-cliente` (misma auth, misma clave temporal = documento,
// mismo rollback), pero recibe un LOTE y lo procesa fila por fila. NO envía correos
// (decisión de negocio: las credenciales se comunican aparte). Inserta TODOS los
// campos del perfil en un solo insert (incluye bancarios + asesor), evitando el
// segundo UPDATE que hace el alta unitaria.
//
// Body: { clientes: [{ fila?, apellidos?, nombres?, nombre_completo?, tipo_documento?, dni,
//                       telefono?, correo, banco, numero_cuenta, tipo_cuenta, cci,
//                       beneficiario_nombre?, beneficiario_dni?, asesor_perfil_id? }],
//         dry_run?: boolean }
//   - Plantilla nueva (2026-06-09): vienen apellidos+nombres y el nombre_completo se
//     deriva APELLIDOS primero. Archivo viejo: solo nombre_completo (sigue válido).
//   - tipo_documento (2026-07-14): 'DNI' | 'CE' | 'PASAPORTE'. Opcional: sin la
//     columna, la fila se valida como DNI (8 dígitos exactos, default histórico).
//   - Si viene beneficiario_nombre/beneficiario_dni, la cuenta se marca como de un
//     tercero (titular_distinto=true) y ambos pasan a ser obligatorios.
//
//   - dry_run:true  → solo valida (formato + duplicados intra-lote + contra BD),
//                     NO crea nada. Alimenta el preview del frontend.
//   - dry_run:false → crea auth.user + perfil por cada fila válida.
//
// Respuesta: { dry_run, creados, errores, resultados:[{ fila, ok, error?, user_id? }] }
//   (en dry_run, `creados` = filas válidas listas para importar.)
// ============================================================================

const ALLOWED_ORIGINS = new Set([
  "https://miavance.com",
  "https://www.miavance.com",
]);

const MAX_POR_LOTE = 100;

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
    const dryRun = body?.dry_run === true;
    const clientesRaw = Array.isArray(body?.clientes) ? body.clientes : null;

    if (!clientesRaw || clientesRaw.length === 0) {
      return json(cors, { error: "No se recibió ninguna fila de clientes" }, 400);
    }
    if (clientesRaw.length > MAX_POR_LOTE) {
      return json(cors, { error: `Máximo ${MAX_POR_LOTE} clientes por lote` }, 400);
    }

    // 1) Normalizar + validar formato fila por fila.
    const filas = clientesRaw.map((c: unknown, i: number) => normalizarFila(c, i));

    // 2) Duplicados DENTRO del mismo lote (DNI / correo).
    marcarDuplicadosIntraLote(filas);

    // 3) Duplicados CONTRA LA BD — una query por columna sobre las candidatas.
    const candidatas = filas.filter((f) => f.ok && !f.error);
    const dnis = [...new Set(candidatas.map((f) => f.dni))];
    const correos = [...new Set(candidatas.map((f) => f.correo))];

    const existingDnis = new Set<string>();
    const existingCorreos = new Set<string>();

    if (dnis.length) {
      // DNI: se compara SOLO contra CLIENTES. El DNI es único entre clientes, pero un
      // colaborador (staff) puede tener además su cuenta de cliente con el mismo DNI
      // (índice parcial perfiles_dni_cliente_key). Sin este `.eq('rol','cliente')` el
      // Excel de clientes rechazaría a un colaborador que quiere invertir.
      const { data } = await adminClient.from("perfiles").select("dni").eq("rol", "cliente").in("dni", dnis);
      for (const r of data || []) if (r.dni) existingDnis.add(String(r.dni));
    }
    if (correos.length) {
      // Comparación CASE-INSENSITIVE: el correo en `perfiles` puede estar guardado
      // con mayúsculas (datos viejos), pero Auth lo trata en minúsculas. Sin ilike,
      // un `.in()` exacto deja pasar un correo que en realidad ya existe y el alta
      // real fallaría recién en createUser. Escapamos los wildcards de ILIKE.
      const escIlike = (s: string) => s.replace(/[\\%_,]/g, "\\$&");
      const orFilter = correos.map((c) => `correo.ilike.${escIlike(c)}`).join(",");
      const { data } = await adminClient.from("perfiles").select("correo").or(orFilter);
      for (const r of data || []) if (r.correo) existingCorreos.add(String(r.correo).toLowerCase());
    }

    // F2.b b3: la bandera se lee ANTES de decidir por existencia. Con ON, la SAGA manda: una fila
    // cuyo perfil ya existe puede ser un alta a medias que hay que reanudar (Codex E2 #7).
    const { data: banderaIdentidad, error: errBandera } = await adminClient
      .schema("crm").rpc("bandera_activa", { p_nombre: "resolver_en_puertas" });
    if (errBandera) {
      return json(cors, { error: `No se pudo leer la bandera de identidad: ${errBandera.message}` }, 500);
    }
    const identidadOn = banderaIdentidad === true;
    for (const f of filas) {
      if (!f.ok || f.error) continue;
      if (identidadOn) continue;
      if (existingDnis.has(f.dni)) { f.ok = false; f.error = "El documento ya está registrado"; continue; }
      if (existingCorreos.has(f.correo)) { f.ok = false; f.error = "El correo ya está registrado"; }
    }

    const rpcAlta = (paso: string, payload: Record<string, unknown>) =>
      adminClient.schema("crm").rpc("alta_cliente_identidad_fn", { p_paso: paso, p_payload: payload });

    // 4) Procesar (secuencial: rollback limpio por fila, sin condiciones de carrera).
    const resultados: Array<{ fila: number; ok: boolean; error?: string; user_id?: string; revision_responsable?: boolean }> = [];
    let creados = 0;
    let errores = 0;

    for (const f of filas) {
      if (!f.ok) {
        resultados.push({ fila: f.fila, ok: false, error: f.error });
        errores++;
        continue;
      }

      // dry_run: válida, pero NO se crea nada.
      if (dryRun) {
        resultados.push({ fila: f.fila, ok: true });
        creados++;
        continue;
      }

      if (!identidadOn) {
        const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
          email: f.correo,
          // Clave temporal = documento, garantizando el mínimo de 8 de Supabase
          // (misma regla que crear-cliente: única fuente en _shared/documento.ts).
          password: claveTemporalDesdeDocumento(f.dni),
          email_confirm: true,
          user_metadata: { nombre: f.nombre_completo },
        });

        if (createErr || !created?.user) {
          const msg = createErr?.message || "No se pudo crear el usuario";
          resultados.push({ fila: f.fila, ok: false, error: traducirError(msg) });
          errores++;
          continue;
        }

        const newUserId = created.user.id;

        const { error: perfilErr } = await adminClient.from("perfiles").insert({
          id: newUserId,
          nombre_completo: f.nombre_completo,
          apellidos: f.apellidos,
          nombres: f.nombres,
          tipo_documento: f.tipo_documento,
          dni: f.dni,
          telefono: f.telefono,
          correo: f.correo,
          rol: "cliente",
          activo: true,
          banco: f.banco,
          numero_cuenta: f.numero_cuenta,
          tipo_cuenta: f.tipo_cuenta,
          cci: f.cci,
          titular_distinto: f.titular_distinto,
          beneficiario_nombre: f.beneficiario_nombre,
          beneficiario_dni: f.beneficiario_dni,
          asesor_perfil_id: f.asesor_perfil_id,
          creado_por: userRes.user.id,
          debe_cambiar_password: true,
        });

        if (perfilErr) {
          // Rollback: borrar el auth.user para no dejar huérfanos.
          await adminClient.auth.admin.deleteUser(newUserId);
          resultados.push({ fila: f.fila, ok: false, error: traducirError(perfilErr.message) });
          errores++;
          continue;
        }

        resultados.push({ fila: f.fila, ok: true, user_id: newUserId });
        creados++;
        continue;
      }

      // ── F2.b b3 · con IDENTIDAD: reclamar → Auth (marcado) → perfil → enlazar ──
      const { data: reclamo, error: errReclamo } = await rpcAlta("reclamar", {
        tipo_documento: f.tipo_documento, documento: f.dni, correo: f.correo,
        nombre_completo: f.nombre_completo, apellidos: f.apellidos, nombres: f.nombres,
        telefono: f.telefono, asesor_id: f.asesor_perfil_id,
        // Proyección bancaria canónica completa en la huella (Codex E2 #7).
        bancarios: {
          banco: f.banco, numero_cuenta: f.numero_cuenta, tipo_cuenta: f.tipo_cuenta, cci: f.cci,
          titular_distinto: f.titular_distinto, beneficiario_nombre: f.beneficiario_nombre, beneficiario_dni: f.beneficiario_dni,
        },
      });
      if (errReclamo) { resultados.push({ fila: f.fila, ok: false, error: traducirError(errReclamo.message) }); errores++; continue; }
      let saga = interpretarReclamo(reclamo);
      if (saga.paso === "ya_existia") { resultados.push({ fila: f.fila, ok: false, error: "El documento ya está registrado" }); errores++; continue; }
      if (saga.paso === "listo") { resultados.push({ fila: f.fila, ok: true, user_id: saga.perfilId ?? undefined }); creados++; continue; }
      if (!saga.claimId || !saga.token || saga.version === null) { resultados.push({ fila: f.fila, ok: false, error: "El servidor no devolvió un claim válido" }); errores++; continue; }
      const avanzar = async (paso: string, extra: Record<string, unknown>) => {
        const { data, error } = await rpcAlta(paso, { claim_id: saga.claimId, token: saga.token, version: saga.version, ...extra });
        if (error) return { error };
        const r = interpretarReclamo(data);
        saga = { ...saga, estado: r.estado, version: r.version ?? saga.version, authUserId: r.authUserId ?? saga.authUserId, perfilId: r.perfilId ?? saga.perfilId, paso: r.paso };
        return { data };
      };
      let newUserId = "";
      if (saga.paso === "crear_auth") {
        const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
          email: f.correo,
          password: claveTemporalDesdeDocumento(f.dni),
          email_confirm: true,
          user_metadata: { nombre: f.nombre_completo },
          app_metadata: { claim_id: saga.claimId },
        });
        if (createErr || !created?.user) {
          if (correoYaRegistrado(createErr?.message)) {
            const { data: existenteAuth } = await adminClient.schema("crm").rpc("auth_usuario_por_correo_fn", { p_correo: f.correo });
            if (existenteAuth && authTieneMarca(existenteAuth, saga.claimId) && typeof existenteAuth.id === "string") {
              newUserId = existenteAuth.id;
            } else {
              resultados.push({ fila: f.fila, ok: false, error: "El correo ya está registrado con otra cuenta (revisión de Gerencia)" }); errores++; continue;
            }
          } else {
            resultados.push({ fila: f.fila, ok: false, error: traducirError(createErr?.message || "No se pudo crear el usuario") }); errores++; continue;
          }
        } else {
          newUserId = created.user.id;
        }
        const r = await avanzar("registrar_auth", { auth_user_id: newUserId });
        if (r.error) { resultados.push({ fila: f.fila, ok: false, error: traducirError(r.error.message) }); errores++; continue; }
      } else {
        if (!saga.authUserId) { resultados.push({ fila: f.fila, ok: false, error: "La saga no tiene usuario de Auth" }); errores++; continue; }
        const { data: authRes } = await adminClient.auth.admin.getUserById(saga.authUserId);
        if (!authRes?.user) {
          const rc = await avanzar("compensar_auth", {});
          resultados.push({ fila: f.fila, ok: false, error: rc.error ? traducirError(rc.error.message) : "El usuario de Auth de un intento anterior ya no existe; el alta se reinició. Reintenta el lote." }); errores++; continue;
        }
        if (!authTieneMarca(authRes.user, saga.claimId)) {
          resultados.push({ fila: f.fila, ok: false, error: "El usuario de Auth de esta alta no lleva la marca del claim (revisión de Gerencia)" }); errores++; continue;
        }
        newUserId = saga.authUserId;
      }
      if (saga.paso !== "enlazar") {
        const { error: perfilErr } = await adminClient.from("perfiles").insert({
          id: newUserId,
        nombre_completo: f.nombre_completo,
        apellidos: f.apellidos,
        nombres: f.nombres,
        tipo_documento: f.tipo_documento,
        dni: f.dni,
        telefono: f.telefono,
        correo: f.correo,
        rol: "cliente",
        activo: true,
        banco: f.banco,
        numero_cuenta: f.numero_cuenta,
        tipo_cuenta: f.tipo_cuenta,
        cci: f.cci,
        titular_distinto: f.titular_distinto,
        beneficiario_nombre: f.beneficiario_nombre,
        beneficiario_dni: f.beneficiario_dni,
        asesor_perfil_id: f.asesor_perfil_id,
        creado_por: userRes.user.id,
        debe_cambiar_password: true,
        });
        if (perfilErr) {
          const decision = decidirTrasFalloPerfil(perfilErr);
          if (decision === "compensar") {
            const { error: delErr } = await adminClient.auth.admin.deleteUser(newUserId);
            if (!delErr) { const rc = await avanzar("compensar_auth", {}); if (rc.error) console.warn("importar-clientes: compensar_auth pendiente:", rc.error.message); }
            resultados.push({ fila: f.fila, ok: false, error: traducirError(perfilErr.message) }); errores++; continue;
          }
          if (decision !== "perfil_ya_existia") {
            resultados.push({ fila: f.fila, ok: false, error: traducirError(perfilErr.message) }); errores++; continue;
          }
        }
        const r = await avanzar("perfil_creado", { perfil_id: newUserId });
        if (r.error) { resultados.push({ fila: f.fila, ok: false, error: traducirError(r.error.message) }); errores++; continue; }
      }
      const r = await avanzar("enlazar", { perfil_id: newUserId });
      if (r.error) { resultados.push({ fila: f.fila, ok: false, error: traducirError(r.error.message) }); errores++; continue; }
      const d = (r.data && typeof r.data === "object") ? r.data as Record<string, unknown> : {};
      resultados.push({ fila: f.fila, ok: true, user_id: newUserId, revision_responsable: d.revision_responsable === true });
      creados++;
    }

    return json(cors, { dry_run: dryRun, creados, errores, resultados }, 200);
  } catch (e) {
    return json(corsHeaders(req), { error: (e as Error)?.message || "Error inesperado" }, 500);
  }
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface Fila {
  fila: number;
  ok: boolean;
  error?: string;
  nombre_completo: string;
  apellidos: string | null;
  nombres: string | null;
  tipo_documento: TipoDocumento;
  dni: string;
  correo: string;
  telefono: string | null;
  banco: string;
  numero_cuenta: string;
  tipo_cuenta: string;
  cci: string;
  titular_distinto: boolean;
  beneficiario_nombre: string | null;
  beneficiario_dni: string | null;
  asesor_perfil_id: string | null;
}

const RE_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RE_CCI = /^[0-9]{20}$/;
const RE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function str(v: unknown): string {
  return (v ?? "").toString().trim();
}

// Valida y normaliza una fila. Bancarios OBLIGATORIOS (decisión de negocio).
function normalizarFila(raw: unknown, idx: number): Fila {
  const c = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const filaNum = Number.isFinite(c.fila) ? Number(c.fila) : idx + 1;

  // Beneficiario (cuenta a nombre de un tercero). Opcional: si viene el nombre, la
  // cuenta se marca como de un beneficiario. Nombre en MAYÚSCULA (igual criterio que
  // el alta manual; el trigger de BD solo normaliza `nombre_completo`, no este campo).
  const benNombre = str(c.beneficiario_nombre).replace(/\s+/g, " ").toUpperCase();
  const benDni = str(c.beneficiario_dni);
  const tieneBeneficiario = benNombre.length > 0 || benDni.length > 0;

  // Apellidos/Nombres separados (2026-06-09). Plantilla nueva: vienen ambos y el
  // nombre_completo se deriva APELLIDOS primero. Archivo viejo: solo nombre_completo.
  const apellidos = str(c.apellidos).replace(/\s+/g, " ").toUpperCase();
  const nombres = str(c.nombres).replace(/\s+/g, " ").toUpperCase();

  // Documento por TIPO (2026-07-14). Fila sin columna de tipo → DNI (default
  // histórico). El número se normaliza (trim + MAYÚSCULA si es pasaporte) para
  // que validación, persistencia y clave temporal usen el mismo valor.
  const tipoDoc = normalizarTipoDocumento(c.tipo_documento);

  const f: Fila = {
    fila: filaNum,
    ok: true,
    nombre_completo: (apellidos || nombres)
      ? `${apellidos} ${nombres}`.replace(/\s+/g, " ").trim()
      : str(c.nombre_completo),
    apellidos: apellidos || null,
    nombres: nombres || null,
    tipo_documento: tipoDoc,
    dni: normalizarDocumento(tipoDoc, c.dni),
    correo: str(c.correo).toLowerCase(),
    telefono: str(c.telefono) || null,
    banco: str(c.banco),
    numero_cuenta: str(c.numero_cuenta),
    tipo_cuenta: str(c.tipo_cuenta).toLowerCase(),
    cci: str(c.cci),
    titular_distinto: tieneBeneficiario,
    beneficiario_nombre: tieneBeneficiario ? benNombre : null,
    beneficiario_dni: tieneBeneficiario ? benDni : null,
    asesor_perfil_id: null,
  };

  // asesor_perfil_id: opcional; solo se acepta si es un uuid bien formado (el
  // frontend resuelve el nombre del analista→id; aquí solo defendemos contra basura).
  const aid = str(c.asesor_perfil_id);
  if (aid && RE_UUID.test(aid)) f.asesor_perfil_id = aid;

  const falla = (msg: string): Fila => ({ ...f, ok: false, error: msg });

  if (f.apellidos && !f.nombres) return falla("Falta la columna Nombres (escribiste los apellidos)");
  if (f.nombres && !f.apellidos) return falla("Falta la columna Apellidos (escribiste los nombres)");
  if (!f.nombre_completo) return falla("Faltan los Apellidos y Nombres del cliente");
  // Tipo PRESENTE pero desconocido → error explícito, NUNCA caer en silencio a
  // DNI (p.ej. "CARNÉ DE EXTRANJERÍA" escrito con la etiqueta larga del portal).
  {
    const tipoRaw = str(c.tipo_documento);
    if (tipoRaw && !esTipoDocumento(tipoRaw)) {
      return falla(`Tipo de documento "${tipoRaw}" no reconocido: usa DNI, CE o PASAPORTE`);
    }
  }
  if (!f.dni) return falla("Falta el documento");
  {
    // El TITULAR valida por su tipo (DNI exacto 8 / CE 9-12 / Pasaporte 6-12).
    const errDoc = validarDocumento(f.tipo_documento, f.dni);
    if (errDoc) return falla(errDoc);
  }
  if (!f.correo) return falla("Falta el correo");
  if (!RE_CORREO.test(f.correo)) return falla("El correo no tiene un formato válido");
  if (!f.banco) return falla("Falta el banco");
  if (!f.tipo_cuenta) return falla("Falta el tipo de cuenta");
  if (!["ahorros", "corriente"].includes(f.tipo_cuenta)) {
    return falla('El tipo de cuenta debe ser "ahorros" o "corriente"');
  }
  if (!f.numero_cuenta) return falla("Falta el número de cuenta");
  if (!f.cci) return falla("Falta el CCI");
  if (!RE_CCI.test(f.cci)) return falla("El CCI debe tener exactamente 20 dígitos");

  // Beneficiario: si se llenó uno de los dos campos, ambos son obligatorios.
  // OJO: el beneficiario es OTRA persona y aún no tiene tipo propio — conserva la
  // regla genérica histórica 8–12 dígitos (NO la del tipo del titular).
  if (f.titular_distinto) {
    if (!f.beneficiario_nombre) return falla("Falta el nombre del beneficiario (escribiste su DNI)");
    if (!f.beneficiario_dni) return falla("Falta el DNI del beneficiario (escribiste su nombre)");
    if (!RE_DOC_GENERICO.test(f.beneficiario_dni)) return falla("El DNI del beneficiario debe tener entre 8 y 12 dígitos");
  }

  return f;
}

function marcarDuplicadosIntraLote(filas: Fila[]): void {
  const dniSeen = new Map<string, number>();
  const correoSeen = new Map<string, number>();
  for (const f of filas) {
    if (!f.ok) continue;
    if (dniSeen.has(f.dni)) {
      f.ok = false;
      f.error = `Documento repetido en el archivo (ya aparece en la fila ${dniSeen.get(f.dni)})`;
      continue;
    }
    if (correoSeen.has(f.correo)) {
      f.ok = false;
      f.error = `Correo repetido en el archivo (ya aparece en la fila ${correoSeen.get(f.correo)})`;
      continue;
    }
    dniSeen.set(f.dni, f.fila);
    correoSeen.set(f.correo, f.fila);
  }
}

// Traduce errores técnicos (constraint, auth) a mensajes legibles para el admin.
// El disparador del duplicado sigue anclado al NOMBRE del constraint (dni /
// perfiles_dni_cliente_key): la columna no se renombró, solo cambió el candado.
function traducirError(msg: string): string {
  const m = msg || "";
  if (/duplicate key/i.test(m) && /dni/i.test(m)) return "El documento ya está registrado";
  if (/duplicate key/i.test(m) && /correo/i.test(m)) return "El correo ya está registrado";
  if (/already.+(registered|exists)|email.+(exist|registr)/i.test(m)) return "El correo ya está registrado";
  if (/foreign key|asesor/i.test(m)) return "El analista indicado no existe";
  // Violación de CHECK (formato/tipo): mensaje limpio, sin filtrar el valor (PII).
  if (/violates check constraint/i.test(m)) return "El tipo o número de documento no es válido";
  return m;
}

function json(cors: Record<string, string>, payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
