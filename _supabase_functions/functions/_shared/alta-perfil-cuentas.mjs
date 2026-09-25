// Resultado de la RPC atomica perfil+cuentas. Un error de transporte no prueba
// que PostgreSQL haya revertido: la respuesta pudo perderse tras el COMMIT.
const RECHAZOS_SQL = new Set(["22023", "23505", "23514", "42501", "P0409"]);

/**
 * @param {{ from: (tabla: string) => unknown }} adminClient cliente service_role
 * @param {string} id identificador del Auth recien creado
 * @param {{ data?: unknown, error?: { code?: string|null }|null }} resultado
 * @param {(() => PromiseLike<{ data?: unknown, error?: { code?: string|null }|null }>)=} reintentar misma RPC idempotente
 * @returns {Promise<'confirmada'|'rechazada'|'incierta'>}
 */
export async function clasificarAltaPerfilConCuentas(adminClient, id, resultado, reintentar) {
  if (!resultado.error && resultado.data === id) return "confirmada";

  // Ante una respuesta perdida, repetir la MISMA transaccion idempotente puede
  // confirmar el commit sin consultar ni registrar cifras bancarias en logs.
  // Un perfil previo por si solo no prueba que las cuentas solicitadas existan.
  if (!RECHAZOS_SQL.has(String(resultado.error?.code ?? "")) && reintentar) {
    try {
      resultado = await reintentar();
      if (!resultado.error && resultado.data === id) return "confirmada";
    } catch {
      return "incierta";
    }
  }

  const { data: perfil, error: lecturaError } = await adminClient
    .from("perfiles").select("id").eq("id", id).maybeSingle();
  if (lecturaError) return "incierta";
  if (perfil?.id === id) return "incierta";
  return RECHAZOS_SQL.has(String(resultado.error?.code ?? ""))
    ? "rechazada" : "incierta";
}

/**
 * Solo compensa cuando la RPC devolvio un rechazo SQL y la lectura confirma
 * que no existe perfil. Un error de delete deja el Auth para revision.
 */
export async function compensarAuthAltaRechazada(adminClient, id) {
  const { error } = await adminClient.auth.admin.deleteUser(id);
  return !error;
}
