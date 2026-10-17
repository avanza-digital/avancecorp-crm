// deno-lint-ignore-file no-import-prefix no-unversioned-import
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { crearHandlerTipoCambio } from "./handler.ts";

// Una sola frontera HTTP para el TC del ranking. El handler conserva el cache
// durante la vida caliente del isolate y recibe `fetch` como dependencia para
// poder probar el contrato sin llamar al BCRP real.
Deno.serve(crearHandlerTipoCambio({ fetch, ahora: () => Date.now() }));
