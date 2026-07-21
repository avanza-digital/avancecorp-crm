import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// Versión EXACTA (no `@2`): esta función corre con service_role; un rango podría
// resolver otra versión en un deploy futuro. Al subir, revisar contra la última 2.x.
import { createClient } from "jsr:@supabase/supabase-js@2.110.8";

// ============================================================================
// crm-importar-leads — conector hoja de Google → crm.leads (2026-07-20).
//
// La hoja "Leads AVANCE CORP — captura para CRM" (Drive de Miguel) corre un
// Apps Script con trigger de tiempo que empuja aquí las filas sin estado; esta
// función valida, deduplica por teléfono e inserta con service_role. Devuelve
// el resultado POR FILA y el script lo escribe en la columna "Estado
// importación" de la propia hoja (la hoja es la UI de rechazos).
//
// Auth en dos capas: verify_jwt=true (el script manda el anon key como Bearer)
// + secreto compartido en `x-importar-secret` (comparación de tiempo constante).
// El secreto vive en el ENV del edge (dashboard → Edge Functions → Secrets,
// clave CRM_IMPORTAR_SECRET) y en las Propiedades del Apps Script — NUNCA en
// el código (rotado 2026-07-21). Sin env la función falla CERRADA (401 todo).
// Rotar = nuevo valor en ambos lados; no hace falta redeploy.
//
// Reglas espejadas de la BD (CHECKs/triggers de crm.leads, verificados en prod):
//  - telefono celular peruano → E.164 +519######## (el trigger de BD re-normaliza)
//  - origen del catálogo · moneda PEN/USD · monto (0, 9_999_999_999.99] 2 dec
//  - dni 8 dígitos · genero F/M · fecha_nacimiento en [1900, 2100) y edad ≥ 18
//    (regla de capa app: se invierte capital, no hay producto para menores)
//  - consentimiento_fuente ≤ 80 chars
//  - vendedor destino debe estar ACTIVO en crm.equipo con rol vendedor|supervisor
//    (guard de tenencia); si el correo no resuelve, el lead entra SIN dueño
//    (cola "por repartir" — permitido en INSERT porque auth.uid() es null con
//    service_role) y el estado lo avisa.
//  - etapa siempre 'nuevo'; creado_por null = importación de sistema.
//
// Body: { filas: [{ fila, nombre, telefono, capital, moneda, canal, correo?,
//                   dni?, genero?, fecha_nacimiento?, distrito?, interes?,
//                   nota?, vendedor_correo?, autorizo?, fuente_consentimiento? }] }
// Resp: { resultados: [{ fila, estado }] }  — estado listo para pintar en la hoja.
// ============================================================================

// Secreto compartido con el Apps Script de la hoja — SOLO del entorno.
// Debe ser 64 hex (openssl rand -hex 32). Si falta o no cumple el formato,
// secretoValido() rechaza TODO (fail-closed): un valor débil no debe habilitar
// el conector por accidente.
const IMPORTAR_SECRET = Deno.env.get("CRM_IMPORTAR_SECRET") ?? "";
const SECRETO_BIEN_FORMADO = /^[0-9a-f]{64}$/i.test(IMPORTAR_SECRET);

const MAX_POR_LOTE = 200;
const MONTO_MAX = 9_999_999_999.99;
const EDAD_MINIMA = 18;

// Server-a-server (Apps Script): sin navegador no hay CORS real, pero se
// responde OPTIONS por higiene y se restringe a POST.
const CORS = {
  "Access-Control-Allow-Origin": "https://crm.miavance.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-importar-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/** Comparación de tiempo constante (evita timing attack sobre el secreto). */
function secretoValido(recibido: string | null): boolean {
  // Sin secreto (o mal formado) en el env, NADIE entra (fail-closed).
  if (!SECRETO_BIEN_FORMADO) return false;
  if (!recibido || recibido.length !== IMPORTAR_SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < IMPORTAR_SECRET.length; i++) {
    diff |= recibido.charCodeAt(i) ^ IMPORTAR_SECRET.charCodeAt(i);
  }
  return diff === 0;
}

/** Espejo de lib/validacion.ts del CRM y de private.normalizar_telefono. */
function normalizarTelefono(valor: string): string | null {
  const limpio = valor.replace(/[\s().-]/g, "");
  const sinMas = limpio.startsWith("+") ? limpio.slice(1) : limpio;
  if (/^9\d{8}$/.test(sinMas)) return `+51${sinMas}`;
  if (/^519\d{8}$/.test(sinMas)) return `+${sinMas}`;
  return null;
}

const CORREO_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Etiquetas de la hoja → claves del CHECK leads_origen_check. */
const CANALES: Record<string, string> = {
  referido: "referido",
  landing: "landing",
  formulario: "formulario",
  wallking: "oficina", // label comercial del catálogo del CRM
  walking: "oficina",
  oficina: "oficina",
  otro: "otro",
  web: "web",
  campania: "campania",
  "campaña": "campania",
  whatsapp: "whatsapp",
};

const INTERES: Record<string, string> = {
  nuevo: "nuevo",
  renovacion: "renovacion",
  "renovación": "renovacion",
  upgrade: "upgrade",
};

/** DD/MM/AAAA o AAAA-MM-DD (Sheets reformatea a gusto) → ISO o null. */
function parseFecha(valor: string): string | null {
  const v = valor.trim();
  let d: number, m: number, a: number;
  let match = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(v);
  if (match) {
    [d, m, a] = [Number(match[1]), Number(match[2]), Number(match[3])];
  } else {
    match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
    if (!match) return null;
    [a, m, d] = [Number(match[1]), Number(match[2]), Number(match[3])];
  }
  const fecha = new Date(Date.UTC(a, m - 1, d));
  if (
    fecha.getUTCFullYear() !== a || fecha.getUTCMonth() !== m - 1 ||
    fecha.getUTCDate() !== d
  ) return null;
  const iso = `${String(a).padStart(4, "0")}-${String(m).padStart(2, "0")}-${
    String(d).padStart(2, "0")
  }`;
  return iso;
}

function edadCumplida(isoNacimiento: string): number {
  // "Hoy" en calendario de LIMA (UTC-5, sin horario de verano). Sin el ajuste,
  // entre las 19:00 y 23:59 de Lima el edge ya está en el día UTC siguiente y
  // podría aceptar a alguien un día antes de cumplir 18 en su calendario local.
  const hoy = new Date(Date.now() - 5 * 60 * 60 * 1000);
  const nac = new Date(`${isoNacimiento}T00:00:00Z`);
  let edad = hoy.getUTCFullYear() - nac.getUTCFullYear();
  const mesDia = (hoy.getUTCMonth() - nac.getUTCMonth()) * 100 +
    (hoy.getUTCDate() - nac.getUTCDate());
  if (mesDia < 0) edad--;
  return edad;
}

/**
 * Capital de la hoja → número, con el ÚNICO formato aceptado: coma = millares,
 * punto = decimal (convención peruana y del CRM). Estricto a propósito: RECHAZA
 * (nunca reinterpreta ni redondea) los formatos ambiguos o con más de 2 decimales
 * — espejo de validacion.ts del CRM: mover de rango un capital es grave.
 *   OK:  "50000" · "50,000" · "50000.50" · "S/ 50,000.00" · "US$ 1,250.5"
 *   NO:  "5000.999" (3 dec) · "12,50" (millar mal puesto) · "50.000,00" (formato UE)
 */
function parseCapital(valor: string): number | null {
  const limpio = valor.replace(/US\$|S\/\.?|\$/gi, "").replace(/\s/g, "").trim();
  if (limpio === "") return null;
  // Solo dígitos, comas de millar en grupos de 3, y a lo sumo un punto decimal
  // con 1-2 dígitos. Cualquier otra cosa NO matchea → null (rechazo, no arreglo).
  const m = /^(\d{1,3}(?:,\d{3})*|\d+)(?:\.(\d{1,2}))?$/.exec(limpio);
  if (!m) return null;
  const entero = m[1].replace(/,/g, "");
  const n = Number(m[2] != null ? `${entero}.${m[2]}` : entero);
  if (!Number.isFinite(n) || n <= 0 || n > MONTO_MAX) return null;
  // Guard canónico redundante (el regex ya limita a 2 decimales), por si acaso.
  if (Math.round(n * 100) / 100 !== n) return null;
  return n;
}

type FilaHoja = {
  fila?: number;
  nombre?: string;
  telefono?: string;
  capital?: string;
  moneda?: string;
  canal?: string;
  correo?: string;
  dni?: string;
  genero?: string;
  fecha_nacimiento?: string;
  distrito?: string;
  interes?: string;
  nota?: string;
  vendedor_correo?: string;
  autorizo?: string;
  fuente_consentimiento?: string;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  if (!secretoValido(req.headers.get("x-importar-secret"))) {
    return json({ error: "No autorizado" }, 401);
  }

  let body: { filas?: FilaHoja[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body inválido" }, 400);
  }
  const filas = Array.isArray(body?.filas) ? body.filas : null;
  if (!filas || filas.length === 0) {
    return json({ error: "Sin filas que importar" }, 400);
  }
  if (filas.length > MAX_POR_LOTE) {
    return json({ error: `Máximo ${MAX_POR_LOTE} filas por lote` }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false }, db: { schema: "crm" } },
  );
  const adminPublic = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // ── Pase 1: validar cada fila en memoria ───────────────────────────────────
  type Valida = {
    fila: number;
    telefono: string;
    insert: Record<string, unknown>;
    vendedorCorreo: string | null;
    avisos: string[];
  };
  const resultados: { fila: number; estado: string }[] = [];
  const validas: Valida[] = [];
  const telefonosLote = new Set<string>();

  for (const f of filas) {
    const fila = typeof f.fila === "number" ? f.fila : -1;
    const rechazo = (motivo: string) =>
      resultados.push({ fila, estado: `RECHAZADO: ${motivo}` });

    const nombre = (f.nombre ?? "").trim();
    if (!nombre) {
      rechazo("falta el nombre");
      continue;
    }
    if (nombre.length > 160) {
      rechazo("nombre demasiado largo");
      continue;
    }

    const telefono = normalizarTelefono((f.telefono ?? "").trim());
    if (!telefono) {
      rechazo("teléfono inválido (celular de 9 dígitos que empiece en 9)");
      continue;
    }
    if (telefonosLote.has(telefono)) {
      rechazo("teléfono repetido en la misma hoja");
      continue;
    }

    const capital = parseCapital((f.capital ?? "").trim());
    if (capital === null) {
      rechazo("capital inválido (número mayor a 0, formato coma=millar punto=decimal, máx 2 decimales)");
      continue;
    }

    const monedaRaw = (f.moneda ?? "").trim().toUpperCase();
    const moneda = monedaRaw === "PEN" || monedaRaw === "SOLES"
      ? "PEN"
      : monedaRaw === "USD" || monedaRaw === "DOLARES" || monedaRaw === "DÓLARES"
      ? "USD"
      : null;
    if (!moneda) {
      rechazo("moneda debe ser PEN o USD");
      continue;
    }

    const canal = CANALES[(f.canal ?? "").trim().toLowerCase()];
    if (!canal) {
      rechazo("canal inválido (Referido / LANDING / FORMULARIO / Wallking / Otro)");
      continue;
    }

    const correo = (f.correo ?? "").trim().toLowerCase() || null;
    if (correo && !CORREO_RE.test(correo)) {
      rechazo("correo inválido");
      continue;
    }

    // El DNI puede venir con separadores si Sheets lo trató como número
    // (p.ej. "45,687,364"): se quitan espacios y comas antes de exigir 8 dígitos.
    const dni = (f.dni ?? "").replace(/[\s,]/g, "") || null;
    if (dni && !/^\d{8}$/.test(dni)) {
      rechazo("DNI inválido (deben ser 8 dígitos)");
      continue;
    }

    const generoRaw = (f.genero ?? "").trim().toUpperCase();
    const genero = generoRaw === "F" || generoRaw === "M" ? generoRaw : null;
    if (generoRaw && !genero) {
      rechazo("género debe ser F o M");
      continue;
    }

    let fechaNacimiento: string | null = null;
    const fechaRaw = (f.fecha_nacimiento ?? "").trim();
    if (fechaRaw) {
      fechaNacimiento = parseFecha(fechaRaw);
      if (!fechaNacimiento) {
        rechazo("fecha de nacimiento inválida (usar DD/MM/AAAA)");
        continue;
      }
      if (fechaNacimiento < "1900-01-01" || fechaNacimiento >= "2100-01-01") {
        rechazo("fecha de nacimiento fuera de rango");
        continue;
      }
      if (edadCumplida(fechaNacimiento) < EDAD_MINIMA) {
        rechazo(`el lead debe ser mayor de ${EDAD_MINIMA} años`);
        continue;
      }
    }

    const interesRaw = (f.interes ?? "").trim().toLowerCase();
    const interes = interesRaw ? INTERES[interesRaw] ?? null : null;
    if (interesRaw && !interes) {
      rechazo("interés inválido (Nuevo / Renovación / Upgrade)");
      continue;
    }

    // Consentimiento (Ley "No Insista"): SOLO valores explícitos. Un valor no
    // reconocido (typo tipo "N0", "FALSE") JAMÁS se interpreta como autorización;
    // se RECHAZA la fila para que un humano la corrija (nunca se fabrica un
    // consentimiento_en inexistente). Vacío = contactable por defecto (régimen de
    // opt-out) pero SIN registrar consentimiento.
    const autorizoRaw = (f.autorizo ?? "").trim().toUpperCase();
    let noContactar: boolean;
    let registrarConsentimiento = false;
    if (autorizoRaw === "") {
      noContactar = false;
    } else if (autorizoRaw === "SI" || autorizoRaw === "SÍ" || autorizoRaw === "S") {
      noContactar = false;
      registrarConsentimiento = true;
    } else if (autorizoRaw === "NO" || autorizoRaw === "N") {
      noContactar = true;
    } else {
      rechazo('¿Autorizó contacto? debe ser SI o NO (vacío = sin registrar consentimiento)');
      continue;
    }
    const fuente = (f.fuente_consentimiento ?? "").trim().slice(0, 80) || null;

    const avisos: string[] = [];
    telefonosLote.add(telefono);
    validas.push({
      fila,
      telefono,
      vendedorCorreo: (f.vendedor_correo ?? "").trim().toLowerCase() || null,
      avisos,
      insert: {
        nombre_completo: nombre,
        telefono,
        correo,
        dni,
        genero,
        fecha_nacimiento: fechaNacimiento,
        distrito: (f.distrito ?? "").trim().slice(0, 120) || null,
        origen: canal,
        etapa: "nuevo",
        monto_estimado: capital,
        moneda,
        categoria_interes: interes,
        nota: (f.nota ?? "").trim().slice(0, 2000) || null,
        no_contactar: noContactar,
        consentimiento_en: registrarConsentimiento ? new Date().toISOString() : null,
        consentimiento_fuente: registrarConsentimiento ? fuente : null,
        vendedor_id: null,
        asignado_supervisor_id: null,
        activo: true,
      },
    });
  }

  if (validas.length > 0) {
    // ── Pase 2: dedup contra la BD por teléfono ──────────────────────────────
    const { data: existentes, error: errDedup } = await admin
      .from("leads")
      .select("telefono")
      .in("telefono", validas.map((v) => v.telefono));
    if (errDedup) {
      return json({ error: `Error consultando duplicados: ${errDedup.message}` }, 500);
    }
    const yaEnCrm = new Set((existentes ?? []).map((r) => r.telefono));

    // ── Pase 3: resolver vendedor por correo (perfiles → crm.equipo) ─────────
    const correosVendedor = [
      ...new Set(validas.map((v) => v.vendedorCorreo).filter(Boolean)),
    ] as string[];
    const vendedorPorCorreo = new Map<string, string>();
    if (correosVendedor.length > 0) {
      const { data: perfiles, error: errPerfiles } = await adminPublic
        .from("perfiles")
        .select("id, correo")
        .in("correo", correosVendedor);
      // Un fallo aquí (permisos/columna/servicio) NO debe leerse como "vendedor no
      // encontrado" e importar todo sin dueño: se corta con 500 ANTES de cualquier
      // insert y el Apps Script reintenta el lote como "ERROR temporal".
      if (errPerfiles) {
        return json({ error: `Error resolviendo vendedores: ${errPerfiles.message}` }, 500);
      }
      const perfilIds = (perfiles ?? []).map((p) => p.id);
      if (perfilIds.length > 0) {
        const { data: equipo, error: errEquipo } = await admin
          .from("equipo")
          .select("perfil_id, rol_crm, activo")
          .in("perfil_id", perfilIds)
          .eq("activo", true)
          .in("rol_crm", ["vendedor", "supervisor"]);
        if (errEquipo) {
          return json({ error: `Error resolviendo equipo: ${errEquipo.message}` }, 500);
        }
        const habilitados = new Set((equipo ?? []).map((e) => e.perfil_id));
        for (const p of perfiles ?? []) {
          if (habilitados.has(p.id)) {
            vendedorPorCorreo.set((p.correo ?? "").toLowerCase(), p.id);
          }
        }
      }
    }

    // ── Pase 4: insertar UNA a una (un lead malo no tumba el lote) ───────────
    for (const v of validas) {
      if (yaEnCrm.has(v.telefono)) {
        resultados.push({ fila: v.fila, estado: "DUPLICADO: ya existe en el CRM" });
        continue;
      }
      if (v.vendedorCorreo) {
        const id = vendedorPorCorreo.get(v.vendedorCorreo);
        if (id) v.insert.vendedor_id = id;
        else v.avisos.push("vendedor no encontrado → quedó por repartir");
      }
      const { error: errIns } = await admin.from("leads").insert(v.insert);
      if (errIns) {
        resultados.push({
          fila: v.fila,
          estado: `RECHAZADO: ${errIns.message.slice(0, 120)}`,
        });
        continue;
      }
      const sufijo = v.avisos.length > 0 ? ` (${v.avisos.join("; ")})` : "";
      resultados.push({ fila: v.fila, estado: `IMPORTADO ✓${sufijo}` });
    }
  }

  resultados.sort((a, b) => a.fila - b.fila);
  return json({ resultados });
});
