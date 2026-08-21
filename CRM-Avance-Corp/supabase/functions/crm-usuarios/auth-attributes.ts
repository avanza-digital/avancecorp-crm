export function atributosCreacionAuthCrm(input: {
  correo: string;
  nombreCompleto: string;
  documento: string;
}) {
  return {
    email: input.correo,
    // Regla operativa exclusiva del CRM: el documento validado y normalizado
    // es la clave exacta. No se rellena, transforma ni devuelve al cliente.
    password: input.documento,
    // Admin createUser confirma sin iniciar los flujos de correo de Auth.
    email_confirm: true,
    user_metadata: {
      nombre_completo: input.nombreCompleto,
    },
    // El origen lo escribe el servidor. La autorizacion efectiva sigue en DB.
    app_metadata: {
      origen_app: "crm",
    },
  } as const;
}
