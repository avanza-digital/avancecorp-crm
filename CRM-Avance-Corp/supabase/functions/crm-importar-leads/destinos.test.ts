import { indexarDestinosImportacion } from "./destinos.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("normaliza los destinos entregados por el RPC canónico", () => {
  const destinos = indexarDestinosImportacion([
    { correo: " Vendedor@Avance.com ", perfil_id: "perfil-vendedor" },
  ]);

  assert(
    destinos.get("vendedor@avance.com") === "perfil-vendedor",
    "el correo debe quedar indexado en minúsculas",
  );
});

Deno.test("no reconstruye destinos ausentes desde filas crudas", () => {
  const destinos = indexarDestinosImportacion([]);
  assert(
    !destinos.has("superadmin@avance.com"),
    "un Superadmin omitido por private.rol_crm no puede reaparecer en Edge",
  );
});

Deno.test("falla cerrada ante una respuesta ambigua", () => {
  let fallo = false;
  try {
    indexarDestinosImportacion([
      { correo: "destino@avance.com", perfil_id: "perfil-1" },
      { correo: "DESTINO@AVANCE.COM", perfil_id: "perfil-2" },
    ]);
  } catch {
    fallo = true;
  }
  assert(fallo, "dos perfiles para el mismo correo deben abortar el lote");
});
