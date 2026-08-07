export type DestinoImportacion = {
  correo: string;
  perfil_id: string;
};

/**
 * Convierte exclusivamente la salida del RPC canónico en el índice usado por
 * el importador. Cualquier colisión ambigua falla cerrada antes de insertar.
 */
export function indexarDestinosImportacion(
  filas: unknown,
): Map<string, string> {
  if (!Array.isArray(filas)) {
    throw new Error("contrato de destinos inválido");
  }

  const destinos = new Map<string, string>();
  for (const fila of filas) {
    if (
      typeof fila !== "object" || fila === null ||
      typeof (fila as Partial<DestinoImportacion>).correo !== "string" ||
      typeof (fila as Partial<DestinoImportacion>).perfil_id !== "string"
    ) {
      throw new Error("contrato de destinos inválido");
    }

    const correo = (fila as DestinoImportacion).correo.trim().toLowerCase();
    const perfilId = (fila as DestinoImportacion).perfil_id.trim();
    if (!correo || !perfilId) {
      throw new Error("contrato de destinos inválido");
    }

    const previo = destinos.get(correo);
    if (previo !== undefined && previo !== perfilId) {
      throw new Error("correo de destino ambiguo");
    }
    destinos.set(correo, perfilId);
  }
  return destinos;
}
