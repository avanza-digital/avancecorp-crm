// Ejecutar con el renderer real dentro de denoland/deno:2.9.4.
// Los PDF resultantes se descargan después desde Chromium/Playwright.
import {
  renderizarAnexoPdfV1,
  renderizarContratoPdfV2,
} from "../../functions/crm-contrato-pdf-v2/renderer.ts";

const directorio = new URL(
  "../../../app/e2e/fixtures/contrato-correcciones/",
  import.meta.url,
);
const snapshot = JSON.parse(
  await Deno.readTextFile(new URL("snapshot.json", directorio)),
);
const fecha = "2026-09-01T12:00:00Z";
for (
  const [nombre, render] of [
    ["contrato-v10.pdf", renderizarContratoPdfV2],
    ["anexo-v2.pdf", renderizarAnexoPdfV1],
  ] as const
) {
  const resultado = await render(snapshot, fecha);
  await Deno.writeFile(
    new URL(nombre, directorio),
    new Uint8Array(await resultado.blob.arrayBuffer()),
  );
  console.log(
    JSON.stringify({
      nombre,
      bytes: resultado.bytes,
      sha256: resultado.sha256,
    }),
  );
}
