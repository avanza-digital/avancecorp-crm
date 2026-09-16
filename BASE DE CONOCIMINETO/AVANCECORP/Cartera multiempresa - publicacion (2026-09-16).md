---
tags: [crm, cartera, multiempresa, gestion, publicacion]
fecha: 2026-09-16
estado: publicado-y-verificado
---

# Cartera multiempresa — publicación del 16/09/2026

La gestión integral de la ficha multiempresa está publicada en
[crm.miavance.com](https://crm.miavance.com). Se completó el
[[Cartera multiempresa - plan de gestion integral (2026-09-16)|plan aprobado]];
[[Cartera multiempresa - gestion integral preparada (2026-09-16)]] conserva
el historial del ensayo local. Miguel autorizó la publicación con `$release-crm`
y el SQL `20260916152851` con un banco Supabase de hasta US$0,10.

## Versión efectiva

- Fuente limpia: `14be1e0581d8a739138c9f5eabeabd6e58beb27b`, Main igual a
  `avancecorp/main` al construir y publicar; integrado por
  [PR #3](https://github.com/avanza-digital/avancecorp-crm/pull/3).
- Build: `build-20260916T182803403Z`.
- Artefacto: `crm-20260916T182804Z-14be1e0581d8.zip`, 2.084.095 bytes.
- SHA-256: `4178865fd0ecc1247019005d7897ca4df3b3eb0fd076e2737c9f3f29a836981d`.
- SQL aprobado: `20260916152851_crm_gestion_integral_multiempresa.sql`, registro
  remoto `20260916174727`; promovido a PortalAvanceCorp por `merge_branch`.
- SHA-256 SQL: `e2ebc90220da5b671d873a3e5899f6f09f981becad6b1beb0dc7c7a78d7ca361`.
  Las 27 sentencias registradas coinciden literalmente y en orden con ese archivo.

Los ZIP y manifiestos publicado/anterior se conservan en
`CRM-Avance-Corp/releases/` de la carpeta original. El posterior commit de actas
no cambia el commit fuente del despliegue ni requiere publicar otra vez.
[Acta completa](https://github.com/avanza-digital/avancecorp-crm/blob/main/CRM-Avance-Corp/supabase/scripts/gestion-multiempresa/PUBLICACION.json),
[SQL y ensayo remoto](https://github.com/avanza-digital/avancecorp-crm/blob/main/CRM-Avance-Corp/supabase/scripts/gestion-multiempresa/REMOTO.md).

## Qué quedó disponible

La ficha concentra las correcciones y el detalle financiero/documental de Avance
y COOPAC, con precarga y bloqueos explícitos. Contacto neutral, cuentas, contratos,
pagos, PDF, tasas y atribución usan sus autoridades existentes. Supervisión y
Gerencia recuperan Nuevo cliente según capacidad; el analista convierte desde
Leads. La ventana de cinco horas se mide desde el registro original, sin reiniciar
por vinculación/fusión. Versión y recibos controlan conflictos y respuestas perdidas.

## Verificación y límites

- **PASS:** gate local completo, 3.654 pruebas unitarias, 199 E2E; 26 omisiones
  existentes declaradas. Cuatro E2E repetidos tras ajustar el botón móvil.
- **PASS:** CI final de `bd4ab4cd`: verify, e2e y preflight. Su árbol completo es
  idéntico a la fuente publicada `14be1e0581d8`.
- **PASS:** 1.866 aserciones RLS remotas y 24 grupos Auth/HTTP/SQL reales, con
  usuarios sintéticos. Selector del caso de lead archivado corregido y suite repetida.
- **PASS:** lecturas productivas para 23 cuentas activas, 63 contextos de persona,
  36 contratos Avance y 23 fuentes COOPAC, mediante rol SQL y ROLLBACK.
- **PASS:** datos, permisos, flags e historial anterior intactos. 651 funciones
  previas conservadas, dos adaptadas y cuatro nuevas. Las 657 finales coinciden
  con el banco probado. Cero filas de contacto creadas al instalar.
- **PASS:** 95 comprobaciones HTTP del despliegue; bytes HTML/JS/CSS y demás
  recursos no transformados iguales al manifiesto. Login visible, sin errores JS.
- Las dos revisiones Claude emitieron CHANGES_REQUESTED; el PRIMARY resolvió los
  hallazgos acreditados y ejecutó los gates. No se atribuye un dictamen PASS al reviewer.
- **NOT RUN:** recorrido autenticado con usuarios humanos, `gate:realidad` completo
  y caso de metas retroactivas sin meses cerrados en el banco. No se escribieron
  datos de clientes reales para probar.

Supabase republicó las Edge existentes durante el merge: las 48 fuentes de las
20 funciones resultaron idénticas; sí cambiaron versiones/paquetes. Advisors:
tabla RLS intencionalmente cerrada, tres RPC DEFINER con autorización probada y
un aviso informativo de FK sin índice sobre el autor. Detalles en el acta remota.

## Coste, recuperación y trabajos conservados

Rama propia `gestion-multiempresa-20260916` eliminada y ausencia confirmada.
Tarifa US$0,01344/h; estimación conservadora hasta la confirmación de cierre:
**US$0,009353**, inferior a US$0,10. Es una estimación, no la factura del proveedor.
No se tocó la rama F7 ajena.

Recuperación frontend: `crm-20260916T170732Z-1f9e5f83fa08.zip`, SHA-256
`6e37f4aa87db16982776e8b0d034534681bed2b13434c60af256ede541f90263`.
La reversa SQL preparada es no destructiva y conserva datos y auditoría; se
recupera primero la web anterior. No se ejecutó ninguna reversa en producción.

Los cambios publicados de contratos/PDF y leads propios siguen incluidos.
Los siete archivos ajenos modificados de la carpeta original se conservaron.
El menú local `f15061b6` quedó en `codex/menu-gerencia-pendiente-20260916`,
sin incluirse en el artefacto. Main se mantiene en el worktree autorizado
`/private/tmp/avancecorp-gestion-worktree`.

Relacionadas: [[F9 - apertura general autorizada (2026-09-15)]],
[[Eliminar contrato vinculado sin historial - preparado 2026-09-16]],
[[Lead propio del supervisor - 2026-09-16]]. G7/G8 mantienen su estado previo.
