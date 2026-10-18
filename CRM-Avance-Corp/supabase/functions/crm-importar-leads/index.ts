import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { manejarImportacion } from "./handler.ts";

Deno.serve(manejarImportacion);
