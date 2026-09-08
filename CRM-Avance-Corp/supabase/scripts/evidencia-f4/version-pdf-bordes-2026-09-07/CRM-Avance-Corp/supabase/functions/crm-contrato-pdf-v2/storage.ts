import { createClient } from "@supabase/supabase-js";
import {
  type BackendError,
  CONTRATO_PDF_BUCKET,
  normalizarUrlFirmadaV2,
  type StorageContratoPdfV2,
} from "./handler.ts";

export const STORAGE_PLAZO_MS = 20_000;

export function errorBackend(error: unknown): BackendError | null {
  if (!error || typeof error !== "object") return null;
  const valor = error as {
    code?: unknown;
    message?: unknown;
    statusCode?: unknown;
    status?: unknown;
  };
  // El SDK 2.110.8 coloca un `code` simbólico en statusCode cuando la API no
  // envía statusCode numérico. Conservarlo permite distinguir NoSuchKey de red.
  const code = typeof valor.code === "string"
    ? valor.code
    : typeof valor.statusCode === "string" && !/^\d{3}$/.test(valor.statusCode)
    ? valor.statusCode
    : undefined;
  const statusRaw = typeof valor.statusCode === "number" ||
      (typeof valor.statusCode === "string" && /^\d{3}$/.test(valor.statusCode))
    ? valor.statusCode
    : valor.status;
  const statusCode = typeof statusRaw === "number"
    ? statusRaw
    : typeof statusRaw === "string" && /^\d{3}$/.test(statusRaw)
    ? Number(statusRaw)
    : undefined;
  return {
    ...(code !== undefined ? { code } : {}),
    ...(typeof valor.message === "string" ? { message: valor.message } : {}),
    ...(statusCode !== undefined ? { statusCode } : {}),
  };
}

type OpcionesStorage = {
  supabaseUrl: string;
  secretKey: string;
  basePublica(req: Request): string;
  fetchImpl?: typeof fetch;
  plazoMs?: number;
};

// El límite incluye la lectura del cuerpo que hace el SDK, no solo recibir
// cabeceras. Cada operación posee su señal: cancelar una no afecta otra petición.
export function crearStorageContratoPdfV2(
  opciones: OpcionesStorage,
): StorageContratoPdfV2 {
  const plazo = opciones.plazoMs ?? STORAGE_PLAZO_MS;
  if (!Number.isInteger(plazo) || plazo < 1 || plazo > 30_000) {
    throw new RangeError("Plazo Storage inválido");
  }
  const fetchImpl = opciones.fetchImpl ?? fetch;
  type ClienteStorage = ReturnType<typeof createClient>["storage"];
  const conLimite = async <T>(
    ejecutar: (storage: ClienteStorage) => Promise<T>,
  ): Promise<T> => {
    const control = new AbortController();
    let temporizador: ReturnType<typeof setTimeout> | undefined;
    const vencimiento = new Promise<never>((_resolver, rechazar) => {
      temporizador = setTimeout(() => {
        const error = Object.assign(
          new Error("Almacenamiento no disponible a tiempo"),
          {
            code: "STORAGE_TIMEOUT",
            statusCode: 504,
          },
        );
        rechazar(error);
        control.abort(error);
      }, plazo);
    });
    try {
      const cliente = createClient(opciones.supabaseUrl, opciones.secretKey, {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
          detectSessionInUrl: false,
        },
        global: {
          fetch(input, init) {
            const previa = init?.signal ??
              (input instanceof Request ? input.signal : null);
            const signal = previa
              ? AbortSignal.any([previa, control.signal])
              : control.signal;
            return fetchImpl(input, { ...init, signal });
          },
        },
      });
      return await Promise.race([ejecutar(cliente.storage), vencimiento]);
    } finally {
      clearTimeout(temporizador);
      control.abort();
    }
  };
  const fallo = (error: unknown): BackendError =>
    errorBackend(error) ?? { code: "STORAGE_FALLO" };

  return {
    async subir(path, archivo) {
      try {
        const { error } = await conLimite((s) =>
          s.from(CONTRATO_PDF_BUCKET).upload(path, archivo, {
            contentType: "application/pdf",
            upsert: false,
            cacheControl: "0",
          })
        );
        return { error: errorBackend(error) };
      } catch (error) {
        return { error: fallo(error) };
      }
    },
    async descargar(path) {
      try {
        const { data, error } = await conLimite((s) =>
          s.from(CONTRATO_PDF_BUCKET).download(path)
        );
        return { data: error ? null : data, error: errorBackend(error) };
      } catch (error) {
        return { data: null, error: fallo(error) };
      }
    },
    async firmar(path, segundos, solicitud) {
      try {
        const { data, error } = await conLimite((s) =>
          s.from(CONTRATO_PDF_BUCKET).createSignedUrl(path, segundos, {
            download: false,
          })
        );
        const url = error || !data?.signedUrl ? null : normalizarUrlFirmadaV2(
          data.signedUrl,
          opciones.basePublica(solicitud),
          path,
        );
        return {
          url,
          error: errorBackend(error) ??
            (url ? null : { code: "SIGNED_URL_INVALID" }),
        };
      } catch (error) {
        return { url: null, error: fallo(error) };
      }
    },
    async eliminar(bucket, paths) {
      try {
        const { error } = await conLimite((s) =>
          s.from(bucket).remove([...paths])
        );
        return { error: errorBackend(error) };
      } catch (error) {
        return { error: fallo(error) };
      }
    },
  };
}
