// diagnostico-push — TOMBSTONE (410 Gone).
// Función de diagnóstico de push ya retirada. Se dejó desplegada como lápida que
// responde 410 a todo: no toca BD, no usa secrets ni service_role, exige JWT.
// Se versiona aquí (auditoría 2026-06-13) para cerrar el drift: estaba ACTIVE en
// Supabase sin fuente en el repo. Si se decide eliminarla del proyecto, borrar
// también esta carpeta.
Deno.serve(() => new Response('gone', { status: 410 }))
