import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// ============================================================================
// importar-clientes — alta MASIVA de clientes desde un Excel.
//
// Modelada sobre `crear-cliente` (misma auth, misma clave temporal = DNI, mismo
// rollback), pero recibe un LOTE y lo procesa fila por fila. NO envía correos
// (decisión de negocio: las credenciales se comunican aparte). Inserta TODOS los
// campos del perfil en un solo insert (incluye bancarios + asesor), evitando el
// segundo UPDATE que hace el alta unitaria.
//
// Body: { clientes: [{ fila?, nombre_completo, dni, telefono?, correo,
//                       banco, numero_cuenta, tipo_cuenta, cci, asesor_perfil_id? }],
//         dry_run?: boolean }
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
      const { data } = await adminClient.from("perfiles").select("dni").in("dni", dnis);
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

    for (const f of filas) {
      if (!f.ok || f.error) continue;
      if (existingDnis.has(f.dni)) { f.ok = false; f.error = "El DNI ya está registrado"; continue; }
      if (existingCorreos.has(f.correo)) { f.ok = false; f.error = "El correo ya está registrado"; }
    }

    // 4) Procesar (secuencial: rollback limpio por fila, sin condiciones de carrera).
    const resultados: Array<{ fila: number; ok: boolean; error?: string; user_id?: string }> = [];
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

      const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
        email: f.correo,
        password: f.dni.padStart(8, "0"),
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
        dni: f.dni,
        telefono: f.telefono,
        correo: f.correo,
        rol: "cliente",
        activo: true,
        banco: f.banco,
        numero_cuenta: f.numero_cuenta,
        tipo_cuenta: f.tipo_cuenta,
        cci: f.cci,
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
  dni: string;
  correo: string;
  telefono: string | null;
  banco: string;
  numero_cuenta: string;
  tipo_cuenta: string;
  cci: string;
  asesor_perfil_id: string | null;
}

const RE_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RE_DNI = /^[0-9]{8,12}$/;
const RE_CCI = /^[0-9]{20}$/;
const RE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function str(v: unknown): string {
  return (v ?? "").toString().trim();
}

// Valida y normaliza una fila. Bancarios OBLIGATORIOS (decisión de negocio).
function normalizarFila(raw: unknown, idx: number): Fila {
  const c = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const filaNum = Number.isFinite(c.fila) ? Number(c.fila) : idx + 1;

  const f: Fila = {
    fila: filaNum,
    ok: true,
    nombre_completo: str(c.nombre_completo),
    dni: str(c.dni),
    correo: str(c.correo).toLowerCase(),
    telefono: str(c.telefono) || null,
    banco: str(c.banco),
    numero_cuenta: str(c.numero_cuenta),
    tipo_cuenta: str(c.tipo_cuenta).toLowerCase(),
    cci: str(c.cci),
    asesor_perfil_id: null,
  };

  // asesor_perfil_id: opcional; solo se acepta si es un uuid bien formado (el
  // frontend resuelve el nombre del analista→id; aquí solo defendemos contra basura).
  const aid = str(c.asesor_perfil_id);
  if (aid && RE_UUID.test(aid)) f.asesor_perfil_id = aid;

  const falla = (msg: string): Fila => ({ ...f, ok: false, error: msg });

  if (!f.nombre_completo) return falla("Falta el nombre completo");
  if (!f.dni) return falla("Falta el DNI");
  if (!RE_DNI.test(f.dni)) return falla("El DNI debe tener entre 8 y 12 dígitos (solo números)");
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

  return f;
}

function marcarDuplicadosIntraLote(filas: Fila[]): void {
  const dniSeen = new Map<string, number>();
  const correoSeen = new Map<string, number>();
  for (const f of filas) {
    if (!f.ok) continue;
    if (dniSeen.has(f.dni)) {
      f.ok = false;
      f.error = `DNI repetido en el archivo (ya aparece en la fila ${dniSeen.get(f.dni)})`;
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
function traducirError(msg: string): string {
  const m = msg || "";
  if (/duplicate key/i.test(m) && /dni/i.test(m)) return "El DNI ya está registrado";
  if (/duplicate key/i.test(m) && /correo/i.test(m)) return "El correo ya está registrado";
  if (/already.+(registered|exists)|email.+(exist|registr)/i.test(m)) return "El correo ya está registrado";
  if (/foreign key|asesor/i.test(m)) return "El analista indicado no existe";
  return m;
}

function json(cors: Record<string, string>, payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
