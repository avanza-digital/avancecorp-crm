export const CONTRATO_PDF_BUCKET = "contratos-generados";
export const CONTRATO_DOCUMENTOS_BUCKET = "documentos";
export const CONTRATO_PDF_TEMPLATE_VERSION = "contrato-aep-17-v9";
export const CONTRATO_PDF_MAX_BYTES = 10 * 1024 * 1024;
export const CONTRATO_PDF_MAX_REQUEST_BYTES = 2 * 1024;

export type BackendError = {
  code?: string;
  message?: string;
  statusCode?: number;
};
export type BackendResult = { data: unknown; error: BackendError | null };

export interface ActorContratoPdfV2 {
  verificarSesion(): Promise<{ id: string } | null>;
  rpc(
    nombre: string,
    argumentos: Record<string, unknown>,
  ): Promise<BackendResult>;
}

export interface StorageContratoPdfV2 {
  subir(path: string, archivo: Blob): Promise<{ error: BackendError | null }>;
  descargar(
    path: string,
  ): Promise<{ data: Blob | null; error: BackendError | null }>;
  firmar(
    path: string,
    segundos: number,
    solicitud: Request,
  ): Promise<{ url: string | null; error: BackendError | null }>;
  eliminar(
    bucket: typeof CONTRATO_PDF_BUCKET | typeof CONTRATO_DOCUMENTOS_BUCKET,
    paths: readonly string[],
  ): Promise<{ error: BackendError | null }>;
}

export type RenderResult = {
  blob: Blob;
  sha256: string;
  bytes: number;
};

export interface DependenciasContratoPdfV2 {
  crearActor(token: string): ActorContratoPdfV2;
  rpcAdmin(
    nombre: string,
    argumentos: Record<string, unknown>,
  ): Promise<BackendResult>;
  renderizar(snapshot: unknown, renderizadoEn: string): Promise<RenderResult>;
  storage: StorageContratoPdfV2;
  origenesAdicionales?: readonly string[];
}

type EstadoNombre =
  | "sin_reserva"
  | "pendiente"
  | "procesando"
  | "subido_verificado"
  | "sellado"
  | "error_reintentable"
  | "integridad_bloqueada";

type ArchivoPdf = {
  contrato_id: string;
  job_id: string | null;
  storage_bucket: typeof CONTRATO_PDF_BUCKET;
  storage_path: string;
  nombre_archivo: string;
  sha256: string;
  bytes: number;
  template_version: string;
  generado_en: string;
};

type EstadoPdf = {
  contrato_id: string;
  job_id: string | null;
  estado: EstadoNombre;
  storage_bucket: typeof CONTRATO_PDF_BUCKET;
  storage_path: string | null;
  nombre_archivo: string | null;
  template_version: string | null;
  intentos: number;
  lease_expira_en: string | null;
  reintentable: boolean;
  sha256: string | null;
  bytes: number | null;
  archivo: ArchivoPdf | null;
  ok?: false;
  codigo?: "PDF_INTEGRIDAD_BLOQUEADA";
};

type ReclamoPdf = EstadoPdf & {
  adquirido: boolean;
  lease_token?: string;
  snapshot?: unknown;
  renderizado_en?: string;
};

type EstadoPdfPublico = Omit<EstadoPdf, "ok" | "codigo">;

const ORIGENES_PRODUCCION = new Set([
  "https://crm.miavance.com",
  "https://www.crm.miavance.com",
  "https://miavance.com",
  "https://www.miavance.com",
]);
const UUID_CANONICO_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA256_RE = /^[a-f0-9]{64}$/;
const ESTADOS = new Set<EstadoNombre>([
  "sin_reserva",
  "pendiente",
  "procesando",
  "subido_verificado",
  "sellado",
  "error_reintentable",
  "integridad_bloqueada",
]);

function cabeceras(
  origin: string | null,
  origenes: ReadonlySet<string>,
): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin && origenes.has(origin)
      ? origin
      : "https://crm.miavance.com",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "600",
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "Content-Security-Policy": "default-src 'none'",
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff",
  };
}

function json(
  origin: string | null,
  origenes: ReadonlySet<string>,
  cuerpo: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: cabeceras(origin, origenes),
  });
}

function esObjeto(valor: unknown): valor is Record<string, unknown> {
  return typeof valor === "object" && valor !== null && !Array.isArray(valor);
}

function clavesExactas(
  valor: Record<string, unknown>,
  esperadas: readonly string[],
): boolean {
  const actuales = Object.keys(valor).sort();
  const objetivo = [...esperadas].sort();
  return actuales.length === objetivo.length &&
    actuales.every((clave, indice) => clave === objetivo[indice]);
}

function bearer(req: Request): string | null {
  const value = req.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+([^\s]+)$/i.exec(value);
  if (!match || match[1].length > 8192) return null;
  return match[1];
}

function uuidCanonico(valor: unknown): valor is string {
  return typeof valor === "string" && UUID_CANONICO_RE.test(valor);
}

function fechaIso(valor: unknown): valor is string {
  return typeof valor === "string" && valor.length <= 40 &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
      .test(
        valor,
      ) &&
    Number.isFinite(Date.parse(valor));
}

function nombreValido(valor: unknown): valor is string {
  if (typeof valor !== "string" || valor !== valor.trim()) return false;
  const longitud = [...valor].length;
  return longitud >= 5 && longitud <= 255 &&
    valor.toLowerCase().endsWith(".pdf") &&
    !valor.includes("/") && !valor.includes("\\") &&
    !tieneControl(valor);
}

function tieneControl(valor: string): boolean {
  for (const caracter of valor) {
    const codigo = caracter.codePointAt(0) ?? 0;
    if (codigo <= 0x1f || (codigo >= 0x7f && codigo <= 0x9f)) return true;
  }
  return false;
}

function versionJobLegible(valor: unknown): valor is string {
  return valor === "contrato-aep-17-v2" ||
    valor === "contrato-aep-17-v5" ||
    valor === "contrato-aep-17-v6" ||
    valor === "contrato-aep-17-v7" ||
    valor === "contrato-aep-17-v8" ||
    valor === CONTRATO_PDF_TEMPLATE_VERSION;
}

function rutaValida(
  contratoId: string,
  jobId: string | null,
  templateVersion: string | null,
  ruta: unknown,
): ruta is string {
  if (typeof ruta !== "string") return false;
  if (jobId) {
    return versionJobLegible(templateVersion) &&
      ruta === `${contratoId}/v2/${jobId}/contrato.pdf`;
  }
  // Compatibilidad de lectura con el ledger v1 durante el despliegue aditivo.
  return ruta === `${contratoId}/contrato.pdf`;
}

function statusErrorBackend(error: BackendError | null): number {
  if (!error) return 502;
  if (error.code === "42501") return 403;
  if (error.code === "P0002" || error.code === "PGRST116") return 404;
  if (
    error.code === "22023" || error.code === "23514" ||
    error.code === "23503" ||
    error.code === "55000" || error.code === "54000" ||
    error.code === "P0409" || error.code === "55P03" || error.code === "40P01"
  ) return 409;
  return 503;
}

const MENSAJES_ELIMINACION_PUBLICOS = new Set([
  "El contrato forma parte del historial de inversiones; conserva el registro y utiliza la anulación comercial que corresponda",
  "Solo Admin o Superadmin puede eliminar contratos",
  "El contrato tiene dependencias nuevas; requiere revisión antes de eliminarlo",
  "La inversión del contrato tiene dependencias nuevas; requiere revisión antes de eliminarla",
  "La inversión de este contrato ya tiene historial propio (eventos, solicitudes, ajustes o vínculos históricos de cotitulares) y se conserva; requiere revisión antes de eliminarla",
  "El identificador del contrato ya tiene una eliminación auditada y requiere revisión",
  "El contrato tiene una eliminación anterior pendiente; requiere revisión antes de archivarlo",
  "El contrato pertenece a un mes comercial cerrado y no se puede eliminar",
  "Contrato no encontrado",
  "El PDF se está generando; reintenta la eliminación en unos minutos",
  "Un documento del contrato tiene una ruta Storage inválida",
  "El contrato supera el límite seguro de archivos para borrar",
  "La preparación de eliminación no existe o venció",
]);

/** Solo expone diagnósticos contractuales deliberadamente públicos. */
function mensajeErrorEliminacion(
  error: BackendError,
  fallback: string,
): string {
  if (error.code === "23503") {
    return "El contrato tiene operaciones o referencias vinculadas que impiden eliminarlo";
  }
  const mensaje = error.message?.trim() ?? "";
  return MENSAJES_ELIMINACION_PUBLICOS.has(mensaje) ? mensaje : fallback;
}

export function normalizarUrlFirmadaV2(
  urlFirmada: string,
  basePublica: string,
  storagePathEsperado?: string,
): string | null {
  try {
    const firmada = new URL(urlFirmada);
    const publica = new URL(basePublica);
    const loopback = new Set(["localhost", "127.0.0.1", "[::1]"]);
    const transporteSeguro = publica.protocol === "https:" ||
      (publica.protocol === "http:" && loopback.has(publica.hostname));
    const prefijo = `/storage/v1/object/sign/${CONTRATO_PDF_BUCKET}/`;
    if (
      !transporteSeguro || publica.username || publica.password ||
      firmada.username || firmada.password ||
      !firmada.pathname.startsWith(prefijo) ||
      firmada.pathname.slice(prefijo.length).length === 0 ||
      firmada.pathname.includes("\\") ||
      !firmada.searchParams.has("token") ||
      !firmada.searchParams.get("token")
    ) return null;
    if (storagePathEsperado !== undefined) {
      let pathFirmado: string;
      try {
        pathFirmado = decodeURIComponent(
          firmada.pathname.slice(prefijo.length),
        );
      } catch {
        return null;
      }
      if (pathFirmado !== storagePathEsperado) return null;
    }
    firmada.protocol = publica.protocol;
    firmada.host = publica.host;
    return firmada.toString();
  } catch {
    return null;
  }
}

function parseArchivo(
  valor: unknown,
  contratoId: string,
): ArchivoPdf | null {
  if (!esObjeto(valor)) return null;
  const jobId = valor.job_id;
  if (jobId !== null && !uuidCanonico(jobId)) return null;
  if (
    valor.contrato_id !== contratoId ||
    valor.storage_bucket !== CONTRATO_PDF_BUCKET ||
    !rutaValida(
      contratoId,
      jobId,
      typeof valor.template_version === "string"
        ? valor.template_version
        : null,
      valor.storage_path,
    ) ||
    !nombreValido(valor.nombre_archivo) ||
    typeof valor.sha256 !== "string" || !SHA256_RE.test(valor.sha256) ||
    typeof valor.bytes !== "number" || !Number.isSafeInteger(valor.bytes) ||
    valor.bytes <= 0 || valor.bytes > CONTRATO_PDF_MAX_BYTES ||
    typeof valor.template_version !== "string" ||
    valor.template_version.length < 1 || valor.template_version.length > 100 ||
    !fechaIso(valor.generado_en)
  ) return null;
  return {
    contrato_id: contratoId,
    job_id: jobId,
    storage_bucket: CONTRATO_PDF_BUCKET,
    storage_path: valor.storage_path,
    nombre_archivo: valor.nombre_archivo,
    sha256: valor.sha256,
    bytes: valor.bytes,
    template_version: valor.template_version,
    generado_en: valor.generado_en,
  };
}

function parseEstado(valor: unknown, contratoId: string): EstadoPdf | null {
  if (!esObjeto(valor) || valor.contrato_id !== contratoId) return null;
  const estado = valor.estado;
  if (typeof estado !== "string" || !ESTADOS.has(estado as EstadoNombre)) {
    return null;
  }
  const jobId = valor.job_id;
  if (jobId !== null && !uuidCanonico(jobId)) return null;
  const path = valor.storage_path;
  const templateVersion = valor.template_version;
  if (
    valor.storage_bucket !== CONTRATO_PDF_BUCKET ||
    (path !== null && typeof path !== "string") ||
    (valor.nombre_archivo !== null && !nombreValido(valor.nombre_archivo)) ||
    (templateVersion !== null && typeof templateVersion !== "string") ||
    typeof valor.intentos !== "number" ||
    !Number.isSafeInteger(valor.intentos) || valor.intentos < 0 ||
    (valor.lease_expira_en !== null && !fechaIso(valor.lease_expira_en)) ||
    typeof valor.reintentable !== "boolean" ||
    (valor.sha256 !== null &&
      (typeof valor.sha256 !== "string" || !SHA256_RE.test(valor.sha256))) ||
    (valor.bytes !== null &&
      (typeof valor.bytes !== "number" || !Number.isSafeInteger(valor.bytes) ||
        valor.bytes <= 0 || valor.bytes > CONTRATO_PDF_MAX_BYTES))
  ) return null;
  if (
    path !== null &&
    !rutaValida(
      contratoId,
      jobId,
      typeof templateVersion === "string" ? templateVersion : null,
      path,
    )
  ) return null;
  const archivo = valor.archivo === null
    ? null
    : parseArchivo(valor.archivo, contratoId);
  if (valor.archivo !== null && !archivo) return null;
  // `reintentable` NO se exige aquí. Desde 2026-08-20 un contrato firmado antes
  // del 19-ago es del régimen documental anterior —ya tiene su contrato, el
  // sistema no le emite ninguno— y la RPC responde `sin_reserva` con
  // `reintentable: false`. Exigir `true`, como se hacía, descartaría la
  // respuesta entera (502) y rompería el detalle de todo contrato antiguo.
  if (
    estado === "sin_reserva" &&
    (jobId !== null || path !== null || valor.nombre_archivo !== null ||
      templateVersion !== null || valor.intentos !== 0 ||
      valor.lease_expira_en !== null ||
      valor.sha256 !== null || valor.bytes !== null || archivo !== null)
  ) return null;
  if (estado !== "sin_reserva" && estado !== "sellado" && jobId === null) {
    return null;
  }
  if (
    jobId !== null &&
    (!versionJobLegible(templateVersion) || path === null ||
      valor.nombre_archivo === null)
  ) return null;
  if (
    archivo &&
    (archivo.job_id !== jobId || archivo.storage_path !== path ||
      archivo.nombre_archivo !== valor.nombre_archivo ||
      archivo.template_version !== templateVersion ||
      archivo.sha256 !== valor.sha256 || archivo.bytes !== valor.bytes)
  ) return null;
  const integridad = estado === "integridad_bloqueada" ||
    (estado === "sellado" && archivo === null) ||
    (valor.ok === false && valor.codigo === "PDF_INTEGRIDAD_BLOQUEADA");
  return {
    contrato_id: contratoId,
    job_id: jobId,
    estado: estado as EstadoNombre,
    storage_bucket: CONTRATO_PDF_BUCKET,
    storage_path: path,
    nombre_archivo: valor.nombre_archivo as string | null,
    template_version: templateVersion as string | null,
    intentos: valor.intentos,
    lease_expira_en: valor.lease_expira_en as string | null,
    reintentable: valor.reintentable,
    sha256: valor.sha256 as string | null,
    bytes: valor.bytes as number | null,
    archivo,
    ...(integridad
      ? { ok: false as const, codigo: "PDF_INTEGRIDAD_BLOQUEADA" as const }
      : {}),
  };
}

function estadoIntegridad(estado: EstadoPdf): boolean {
  return estado.estado === "integridad_bloqueada" || estado.ok === false;
}

function estadoHttp(estado: EstadoPdf): number {
  if (estadoIntegridad(estado)) return 409;
  return estado.estado === "sellado" ? 200 : 202;
}

function pdfPublico(estado: EstadoPdf): EstadoPdfPublico {
  return {
    contrato_id: estado.contrato_id,
    job_id: estado.job_id,
    estado: estado.estado,
    storage_bucket: estado.storage_bucket,
    storage_path: estado.storage_path,
    nombre_archivo: estado.nombre_archivo,
    template_version: estado.template_version,
    intentos: estado.intentos,
    lease_expira_en: estado.lease_expira_en,
    reintentable: estado.reintentable,
    sha256: estado.sha256,
    bytes: estado.bytes,
    archivo: estado.archivo,
  };
}

function respuestaBackend(
  result: BackendResult,
  contratoId: string,
): { estado: EstadoPdf | null; status: number } {
  if (result.error) {
    const code = result.error.code;
    if (code === "42501") return { estado: null, status: 403 };
    if (code === "P0002" || code === "PGRST116") {
      return { estado: null, status: 404 };
    }
    if (code === "22023" || code === "23514" || code === "55000") {
      return { estado: null, status: 409 };
    }
    return { estado: null, status: 503 };
  }
  const estado = parseEstado(result.data, contratoId);
  return { estado, status: estado ? estadoHttp(estado) : 502 };
}

async function leerJsonLimitado(req: Request): Promise<unknown> {
  const longitud = req.headers.get("Content-Length");
  if (longitud !== null) {
    const n = Number(longitud);
    if (!Number.isSafeInteger(n) || n < 0) {
      throw new Error("SOLICITUD_INVALIDA");
    }
    if (n > CONTRATO_PDF_MAX_REQUEST_BYTES) throw new Error("SOLICITUD_GRANDE");
  }
  if (!req.body) throw new Error("SOLICITUD_INVALIDA");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > CONTRATO_PDF_MAX_REQUEST_BYTES) {
      await reader.cancel();
      throw new Error("SOLICITUD_GRANDE");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let texto: string;
  try {
    texto = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new Error("SOLICITUD_INVALIDA");
  }
  try {
    return JSON.parse(texto);
  } catch {
    throw new Error("SOLICITUD_INVALIDA");
  }
}

async function fingerprint(
  blob: Blob,
): Promise<{ sha256: string; bytes: number }> {
  const buffer = await blob.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return {
    sha256: [...new Uint8Array(digest)]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join(""),
    bytes: buffer.byteLength,
  };
}

async function pdfValido(blob: Blob): Promise<boolean> {
  if (blob.size <= 5 || blob.size > CONTRATO_PDF_MAX_BYTES) return false;
  const encabezado = new Uint8Array(await blob.slice(0, 5).arrayBuffer());
  return new TextDecoder().decode(encabezado) === "%PDF-";
}

function esConflictoObjeto(error: BackendError): boolean {
  const codigo = (error.code ?? "").toLowerCase();
  return error.statusCode === 409 || codigo === "409" ||
    codigo === "duplicate" || codigo === "resource_already_exists";
}

export function crearHandlerContratoPdfV2(deps: DependenciasContratoPdfV2) {
  const origenes = new Set(ORIGENES_PRODUCCION);
  for (const origen of deps.origenesAdicionales ?? []) origenes.add(origen);

  return async (req: Request): Promise<Response> => {
    const origin = req.headers.get("Origin");
    if (req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: cabeceras(origin, origenes),
      });
    }
    if (req.method !== "POST") {
      return json(origin, origenes, {
        error: "Método no permitido",
        codigo: "METODO",
      }, 405);
    }
    const contentType = req.headers.get("Content-Type") ?? "";
    if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(contentType)) {
      return json(
        origin,
        origenes,
        { error: "Se requiere application/json", codigo: "TIPO_CONTENIDO" },
        415,
      );
    }

    let cuerpo: unknown;
    try {
      cuerpo = await leerJsonLimitado(req);
    } catch (error) {
      const grande = error instanceof Error &&
        error.message === "SOLICITUD_GRANDE";
      return json(
        origin,
        origenes,
        {
          error: grande ? "Solicitud demasiado grande" : "JSON inválido",
          codigo: grande ? "SOLICITUD_GRANDE" : "JSON_INVALIDO",
        },
        grande ? 413 : 400,
      );
    }
    if (
      !esObjeto(cuerpo) || !clavesExactas(cuerpo, ["action", "contratoId"]) ||
      (cuerpo.action !== "ensure" && cuerpo.action !== "status" &&
        cuerpo.action !== "delete" && cuerpo.action !== "delete-audited") ||
      !uuidCanonico(cuerpo.contratoId)
    ) {
      return json(
        origin,
        origenes,
        { error: "Solicitud inválida", codigo: "SOLICITUD_INVALIDA" },
        400,
      );
    }

    const token = bearer(req);
    if (!token) {
      return json(origin, origenes, {
        error: "Sesión inválida",
        codigo: "SESION",
      }, 401);
    }
    const actor = deps.crearActor(token);
    const sesion = await actor.verificarSesion();
    if (!sesion || !uuidCanonico(sesion.id)) {
      return json(origin, origenes, {
        error: "Sesión inválida",
        codigo: "SESION",
      }, 401);
    }
    const contratoId = cuerpo.contratoId;

    if (cuerpo.action === "delete" || cuerpo.action === "delete-audited") {
      // La copia de datos y el borrado son una sola transacción. Los objetos
      // privados permanecen como evidencia referenciada por la auditoría.
      const resultado = await deps.rpcAdmin("contrato_eliminar_auditado", {
        p_contrato_id: contratoId,
        p_actor_id: sesion.id,
      });
      if (resultado.error) {
        return json(origin, origenes, {
          error: ["55P03", "40P01"].includes(resultado.error.code ?? "")
            ? "El contrato está siendo actualizado. Espera unos segundos y reintenta."
            : mensajeErrorEliminacion(
              resultado.error,
              "No se pudo eliminar el contrato con su copia de auditoría",
            ),
          codigo: "CONTRATO_ELIMINACION_AUDITADA",
        }, statusErrorBackend(resultado.error));
      }
      const d = resultado.data;
      if (
        !esObjeto(d) ||
        !clavesExactas(d, [
          "ok",
          "contrato_id",
          "auditoria_id",
          "archivos_conservados",
        ]) ||
        d.ok !== true || d.contrato_id !== contratoId ||
        !uuidCanonico(d.auditoria_id) ||
        !Number.isInteger(d.archivos_conservados) ||
        (d.archivos_conservados as number) < 0
      ) {
        return json(origin, origenes, {
          error: "La confirmación de eliminación es incoherente",
          codigo: "INTEGRIDAD_ELIMINACION",
        }, 409);
      }
      if (cuerpo.action === "delete") {
        return json(origin, origenes, {
          ok: true,
          contratoId,
          archivosEliminados: 0,
        });
      }
      return json(origin, origenes, {
        ok: true,
        contratoId,
        auditoriaId: d.auditoria_id,
        archivosConservados: d.archivos_conservados,
      });
    }

    const firmar = async (
      estado: EstadoPdf,
      yaVerificado = false,
    ): Promise<Response> => {
      const archivo = estado.archivo;
      if (estado.estado !== "sellado" || !archivo) {
        return json(
          origin,
          origenes,
          { error: "Metadata PDF incoherente", codigo: "INTEGRIDAD_METADATA" },
          409,
        );
      }
      if (!yaVerificado) {
        const descarga = await deps.storage.descargar(archivo.storage_path);
        if (descarga.error || !descarga.data) {
          return json(
            origin,
            origenes,
            {
              error: "PDF no disponible temporalmente",
              codigo: "STORAGE_DESCARGA",
            },
            503,
          );
        }
        const fp = await pdfValido(descarga.data)
          ? await fingerprint(descarga.data)
          : null;
        if (
          !fp || fp.sha256 !== archivo.sha256 ||
          fp.bytes !== archivo.bytes
        ) {
          return json(
            origin,
            origenes,
            {
              error: "Integridad del PDF bloqueada",
              codigo: "INTEGRIDAD_OBJETO",
            },
            409,
          );
        }
      }
      const firma = await deps.storage.firmar(archivo.storage_path, 300, req);
      if (firma.error || !firma.url) {
        return json(
          origin,
          origenes,
          { error: "No se pudo firmar la descarga", codigo: "STORAGE_FIRMA" },
          503,
        );
      }
      return json(origin, origenes, {
        pdf: pdfPublico(estado),
        url: firma.url,
      });
    };

    if (cuerpo.action === "status") {
      const result = respuestaBackend(
        await actor.rpc("contrato_pdf_estado_fn", {
          p_contrato_id: contratoId,
        }),
        contratoId,
      );
      if (!result.estado) {
        return json(
          origin,
          origenes,
          { error: "No se pudo consultar el PDF", codigo: "PDF_ESTADO" },
          result.status,
        );
      }
      if (result.estado.estado === "sellado") {
        return await firmar(result.estado);
      }
      return json(
        origin,
        origenes,
        { pdf: pdfPublico(result.estado) },
        result.status,
      );
    }

    const reserva = respuestaBackend(
      await deps.rpcAdmin("contrato_pdf_reservar", {
        p_contrato_id: contratoId,
        p_actor_id: sesion.id,
      }),
      contratoId,
    );
    if (!reserva.estado) {
      return json(
        origin,
        origenes,
        { error: "No se pudo reservar el PDF", codigo: "PDF_RESERVA" },
        reserva.status,
      );
    }
    if (estadoIntegridad(reserva.estado)) {
      return json(origin, origenes, { pdf: pdfPublico(reserva.estado) }, 409);
    }
    if (reserva.estado.estado === "sellado") {
      return await firmar(reserva.estado);
    }

    // Régimen documental anterior: la reserva no creó ni creará job, así que
    // reclamar levantaría P0002 («no tiene una reserva PDF v2») y el vendedor
    // vería un error de fontanería en vez de la razón. Se devuelve el estado tal
    // cual: el navegador ya sabe leerlo y decir que ese contrato es del formato
    // anterior.
    if (
      reserva.estado.estado === "sin_reserva" && !reserva.estado.reintentable
    ) {
      return json(
        origin,
        origenes,
        { pdf: pdfPublico(reserva.estado) },
        estadoHttp(reserva.estado),
      );
    }

    // Un servicio que no conoce la plantilla no debe tomar un lease y forzar
    // a esperar su vencimiento. Tampoco debe invalidar un documento de otra versión.
    if (reserva.estado.template_version !== CONTRATO_PDF_TEMPLATE_VERSION) {
      return json(origin, origenes, {
        error: "El PDF todavía no puede generarse; requiere revisión",
        codigo: "PDF_VERSION_NO_SOPORTADA",
        pdf: pdfPublico(reserva.estado),
      }, 409);
    }

    const reclamoRaw = await deps.rpcAdmin("contrato_pdf_reclamar", {
      p_contrato_id: contratoId,
      p_actor_id: sesion.id,
      p_lease_segundos: 120,
    });
    const raw = esObjeto(reclamoRaw.data) ? reclamoRaw.data : {};
    const reclamoBase = respuestaBackend(reclamoRaw, contratoId);
    if (!reclamoBase.estado) {
      // Incluso si una versión futura cambió la respuesta, devolver un lease
      // identificable a su dueño evita bloquear la recuperación. No se lee ni
      // escribe Storage usando metadata que este servicio no pudo validar.
      if (
        !reclamoRaw.error && raw.adquirido === true &&
        raw.contrato_id === contratoId && uuidCanonico(raw.job_id) &&
        uuidCanonico(raw.lease_token) &&
        raw.storage_bucket === CONTRATO_PDF_BUCKET &&
        raw.storage_path === `${contratoId}/v2/${raw.job_id}/contrato.pdf`
      ) {
        await deps.rpcAdmin("contrato_pdf_marcar_error", {
          p_job_id: raw.job_id,
          p_lease_token: raw.lease_token,
          p_actor_id: sesion.id,
          p_error_codigo: "RESPUESTA_RECLAMO_INVALIDA",
        });
      }
      return json(
        origin,
        origenes,
        { error: "No se pudo reclamar el job PDF", codigo: "PDF_RECLAMO" },
        reclamoBase.status,
      );
    }
    const reclamo: ReclamoPdf = {
      ...reclamoBase.estado,
      adquirido: raw.adquirido === true,
      ...(raw.lease_token !== undefined
        ? { lease_token: raw.lease_token as string }
        : {}),
      ...(raw.snapshot !== undefined ? { snapshot: raw.snapshot } : {}),
      ...(raw.renderizado_en !== undefined
        ? { renderizado_en: raw.renderizado_en as string }
        : {}),
    };
    if (!reclamo.adquirido) {
      if (reclamo.estado === "sellado") return await firmar(reclamo);
      return json(
        origin,
        origenes,
        { pdf: pdfPublico(reclamoBase.estado) },
        estadoHttp(reclamo),
      );
    }
    if (
      !uuidCanonico(reclamo.job_id) || !uuidCanonico(reclamo.lease_token)
    ) {
      return json(
        origin,
        origenes,
        { error: "Job PDF incoherente", codigo: "INTEGRIDAD_JOB" },
        409,
      );
    }

    const jobId = reclamo.job_id;
    const leaseToken = reclamo.lease_token;
    const marcarError = async (codigo: string): Promise<EstadoPdf | null> => {
      const resultado = await deps.rpcAdmin("contrato_pdf_marcar_error", {
        p_job_id: jobId,
        p_lease_token: leaseToken,
        p_actor_id: sesion.id,
        p_error_codigo: codigo,
      });
      return respuestaBackend(resultado, contratoId).estado;
    };

    // La revisión pudo cambiar entre reserva y reclamo. Liberar este lease sin
    // clasificar como corrupción una plantilla que otro servicio sí soporte.
    if (reclamo.template_version !== CONTRATO_PDF_TEMPLATE_VERSION) {
      const estado = await marcarError("PLANTILLA_NO_SOPORTADA");
      return json(origin, origenes, {
        error: "El PDF todavía no puede generarse; requiere revisión",
        codigo: "PDF_VERSION_NO_SOPORTADA",
        ...(estado ? { pdf: pdfPublico(estado) } : {}),
      }, 409);
    }
    if (
      !fechaIso(reclamo.renderizado_en) || reclamo.snapshot === undefined ||
      !reclamo.storage_path
    ) {
      const estado = await marcarError("INTEGRIDAD_JOB");
      return json(origin, origenes, {
        error: "Job PDF incoherente",
        codigo: "INTEGRIDAD_JOB",
        ...(estado ? { pdf: pdfPublico(estado) } : {}),
      }, 409);
    }

    let render: RenderResult;
    try {
      render = await deps.renderizar(reclamo.snapshot, reclamo.renderizado_en);
      const fpRender = await pdfValido(render.blob)
        ? await fingerprint(render.blob)
        : null;
      if (
        !fpRender || render.bytes !== fpRender.bytes ||
        render.sha256 !== fpRender.sha256
      ) throw new Error("RENDER_INVALIDO");
    } catch (error) {
      const integridad = error instanceof TypeError;
      const estado = await marcarError(
        integridad ? "INTEGRIDAD_SNAPSHOT_INVALIDO" : "RENDER_FALLO",
      );
      return estado
        ? json(
          origin,
          origenes,
          { pdf: pdfPublico(estado) },
          integridad ? 409 : 503,
        )
        : json(
          origin,
          origenes,
          {
            error: integridad
              ? "Snapshot PDF inválido"
              : "No se pudo renderizar el PDF",
            codigo: integridad
              ? "INTEGRIDAD_SNAPSHOT_INVALIDO"
              : "RENDER_FALLO",
          },
          integridad ? 409 : 503,
        );
    }

    // Una respuesta perdida puede dejar el objeto guardado aunque el job siga
    // procesando. En un nuevo intento se recuperan esos bytes antes de volver
    // a subir: su huella se contrasta abajo con el render determinista. Nunca
    // se sobrescribe el archivo ni se presupone que un error sea ausencia.
    let descargaRecuperada: { data: Blob; error: null } | null = null;
    if (reclamo.intentos > 1 && reclamo.estado !== "subido_verificado") {
      const previa = await deps.storage.descargar(reclamo.storage_path);
      if (!previa.error && previa.data) {
        descargaRecuperada = { data: previa.data, error: null };
      } else if (
        previa.error?.statusCode !== 404 &&
        previa.error?.code !== "NoSuchKey"
      ) {
        const estado = await marcarError("STORAGE_DESCARGA");
        return estado
          ? json(origin, origenes, { pdf: pdfPublico(estado) }, 503)
          : json(
            origin,
            origenes,
            {
              error: "PDF no disponible temporalmente",
              codigo: "STORAGE_DESCARGA",
            },
            503,
          );
      }
    }

    if (reclamo.estado !== "subido_verificado" && !descargaRecuperada) {
      const subida = await deps.storage.subir(
        reclamo.storage_path,
        render.blob,
      );
      if (subida.error && !esConflictoObjeto(subida.error)) {
        const estado = await marcarError("STORAGE_SUBIDA");
        return estado
          ? json(origin, origenes, { pdf: pdfPublico(estado) }, 503)
          : json(
            origin,
            origenes,
            { error: "No se pudo subir el PDF", codigo: "STORAGE_SUBIDA" },
            503,
          );
      }
    }

    const descarga = descargaRecuperada ??
      await deps.storage.descargar(reclamo.storage_path);
    if (descarga.error || !descarga.data) {
      const estado = await marcarError("STORAGE_DESCARGA");
      return estado
        ? json(origin, origenes, { pdf: pdfPublico(estado) }, 503)
        : json(
          origin,
          origenes,
          {
            error: "PDF no disponible temporalmente",
            codigo: "STORAGE_DESCARGA",
          },
          503,
        );
    }
    const fpObjeto = await pdfValido(descarga.data)
      ? await fingerprint(descarga.data)
      : null;
    if (
      !fpObjeto || fpObjeto.sha256 !== render.sha256 ||
      fpObjeto.bytes !== render.bytes
    ) {
      const estado = await marcarError("INTEGRIDAD_OBJETO_DIVERGENTE");
      return estado
        ? json(origin, origenes, { pdf: pdfPublico(estado) }, 409)
        : json(
          origin,
          origenes,
          {
            error: "Integridad del PDF bloqueada",
            codigo: "INTEGRIDAD_OBJETO",
          },
          409,
        );
    }

    const subido = respuestaBackend(
      await deps.rpcAdmin("contrato_pdf_marcar_subido", {
        p_job_id: jobId,
        p_lease_token: leaseToken,
        p_actor_id: sesion.id,
        p_sha256: fpObjeto.sha256,
        p_bytes: fpObjeto.bytes,
      }),
      contratoId,
    );
    if (!subido.estado) {
      return json(
        origin,
        origenes,
        { error: "No se pudo verificar el PDF", codigo: "PDF_MARCAR_SUBIDO" },
        subido.status,
      );
    }
    if (estadoIntegridad(subido.estado)) {
      return json(origin, origenes, { pdf: pdfPublico(subido.estado) }, 409);
    }

    const final = respuestaBackend(
      await deps.rpcAdmin("contrato_pdf_finalizar", {
        p_job_id: jobId,
        p_lease_token: leaseToken,
        p_actor_id: sesion.id,
      }),
      contratoId,
    );
    if (!final.estado) {
      return json(
        origin,
        origenes,
        { error: "No se pudo sellar el PDF", codigo: "PDF_FINALIZAR" },
        final.status,
      );
    }
    if (final.estado.estado !== "sellado") {
      return json(
        origin,
        origenes,
        { pdf: pdfPublico(final.estado) },
        estadoHttp(final.estado),
      );
    }
    const archivo = final.estado.archivo;
    if (!archivo) {
      return json(
        origin,
        origenes,
        { error: "Ledger PDF incompleto", codigo: "INTEGRIDAD_LEDGER" },
        409,
      );
    }
    if (
      archivo.storage_path !== reclamo.storage_path ||
      archivo.sha256 !== fpObjeto.sha256 || archivo.bytes !== fpObjeto.bytes ||
      archivo.template_version !== CONTRATO_PDF_TEMPLATE_VERSION
    ) {
      return json(
        origin,
        origenes,
        { error: "Ledger PDF incoherente", codigo: "INTEGRIDAD_LEDGER" },
        409,
      );
    }
    return await firmar(final.estado, true);
  };
}
