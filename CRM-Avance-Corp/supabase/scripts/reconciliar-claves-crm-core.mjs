const REGLAS_DOCUMENTO = Object.freeze({
  DNI: /^[0-9]{8}$/,
  CE: /^[0-9]{9,12}$/,
  PASAPORTE: /^[A-Z0-9]{6,12}$/,
});

function objeto(valor) {
  return typeof valor === 'object' && valor !== null && !Array.isArray(valor)
    ? valor
    : {};
}

export function normalizarDocumentoCrm(tipoOriginal, documentoOriginal) {
  const tipo = String(tipoOriginal ?? '').trim().toUpperCase();
  const documentoBase = String(documentoOriginal ?? '').trim();
  const documento = tipo === 'PASAPORTE'
    ? documentoBase.toUpperCase()
    : documentoBase;
  const regla = REGLAS_DOCUMENTO[tipo];
  if (!regla || !regla.test(documento)) return null;
  return { tipo, documento };
}

export function clasificarCuentasCrm(
  usuariosAuth,
  perfilesComerciales,
  idsLegacyAuditados = new Set(),
) {
  const authPorId = new Map(usuariosAuth.map((usuario) => [usuario.id, usuario]));
  const perfilesPorId = new Map(
    perfilesComerciales.map((perfil) => [perfil.id, perfil]),
  );
  const candidatas = [];
  let sinAuth = 0;
  let sinMarcaOrigen = 0;
  let marcaLegacySinAuditoria = 0;
  let documentoInvalido = 0;
  let marcadasFueraDeComercial = 0;

  for (const perfil of perfilesComerciales) {
    const usuario = authPorId.get(perfil.id);
    if (!usuario) {
      sinAuth++;
      continue;
    }
    const appMetadata = objeto(usuario.app_metadata);
    const userMetadata = objeto(usuario.user_metadata);
    const origenServidor = appMetadata.origen_app === 'crm';
    const origenLegacy = userMetadata.origen === 'crm';
    const legacyAuditado = origenLegacy && idsLegacyAuditados.has(usuario.id);
    if (!origenServidor && !legacyAuditado) {
      if (origenLegacy) {
        marcaLegacySinAuditoria++;
        continue;
      }
      sinMarcaOrigen++;
      continue;
    }
    const credencial = normalizarDocumentoCrm(
      perfil.tipo_documento,
      perfil.dni,
    );
    if (!credencial) {
      documentoInvalido++;
      continue;
    }
    candidatas.push({
      id: usuario.id,
      documento: credencial.documento,
      appMetadata: { ...appMetadata, origen_app: 'crm' },
    });
  }

  for (const usuario of usuariosAuth) {
    const appMetadata = objeto(usuario.app_metadata);
    const userMetadata = objeto(usuario.user_metadata);
    const marcada = appMetadata.origen_app === 'crm'
      || userMetadata.origen === 'crm';
    if (marcada && !perfilesPorId.has(usuario.id)) {
      marcadasFueraDeComercial++;
    }
  }

  return {
    candidatas,
    resumen: {
      perfiles_comerciales: perfilesComerciales.length,
      elegibles_solo_crm: candidatas.length,
      comerciales_sin_auth: sinAuth,
      comerciales_sin_marca_origen: sinMarcaOrigen,
      marcas_legacy_sin_auditoria: marcaLegacySinAuditoria,
      documentos_invalidos: documentoInvalido,
      marcas_crm_fuera_de_comercial: marcadasFueraDeComercial,
    },
  };
}
