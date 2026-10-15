# Formulario 3 — origen nativo publicado

Publicado y verificado el **15/10/2026** en [crm.miavance.com](https://crm.miavance.com/). Formulario 3 usa `crm.leads.origen = formulario_3`, con las mismas tablas, permisos y puertas de negocio. Tiene filtros y métricas propios; conserva el turno operativo Formulario. Repartir usa una tabla por origen y supervisora. La ficha muestra una sola identificación «Formulario 3».

## Resultado y conservación

- **116 leads nativos, cero legados** `formulario` + campaña exacta. Un convertido y su acreditación abierta cambiaron únicamente el origen.
- Huellas de los 116 leads antes/después idénticas excluyendo solo origen y timestamp técnico. También idénticas: asignaciones, historial, tareas, acreditaciones salvo origen, contratos, inversiones, solicitudes y fotos/meses sellados. La transacción B verifica además todos los demás leads y la conversión agregada.
- No se repitió el reparto de los Excel ni se reactivaron descartados. Se conservó el estado productivo vigente, incluidas las gestiones posteriores del equipo.
- n8n `BjI5m1PKVWhO0NDb` sigue activo, versión publicada/draft `e2f62a7e-7675-414d-a7b0-b617e2528c72`, 22 nodos, **152 recibos**. No se modificó el flujo, su payload, credenciales ni recibos.

## Publicación exacta

| Componente | Versión y verificación |
| --- | --- |
| Fuente web | PR #294 fusionada, `597cab1cbfe68d53a2742073cfc7fc3292901af5`; Main local = `avancecorp/main` antes de construir y subir |
| Build | `build-20261015T212300418Z` |
| ZIP | `crm-20261015T212301Z-597cab1cbfe6.zip`, 2.577.181 bytes, 162 archivos |
| SHA256 ZIP | `7fd053eda9631665791c6a72959ea60e0959e1e73c99b13833a83f7ecea1bbd8` |
| SQL A | `20261015171407_crm_formulario3_origen_compatibilidad`; MD5 del archivo registrado `b7f8878b3dcd95e0da737897dd3b44bb` |
| SQL B | `20261015173031_crm_formulario3_origen_activacion`; MD5 del archivo registrado `0f8f34071f7565105f8e8af2f410e420` |
| Edge | `crm-importar-leads` v26, JWT requerido; ocho fuentes descargadas idénticas al candidato; huella `96720d80a77fa7a41e70abc349af58cf88ef87474d17c8dc13456ff55d1c0a3a` |

Miguel invocó `$release-crm` y autorizó específicamente A/B e importador. Se cumplieron los gates de rama Supabase, RLS focalizada y advisors antes de retirar la rama autorizada. Como ya estaba retirada, se promovieron **los SQL exactos en dos pasos**, mediante `supabase db query --linked --project-ref dctqcbznekcyxhjujuci --file`, seguidos de su registro idempotente y verificación de contenido. Es una excepción acotada al mecanismo de merge, respaldada por la autorización y el precedente de fase 4; no fue un merge de Supabase ni un `db push` general. No se creó otro recurso de pago. Los registradores se probaron en Docker con ROLLBACK, repetición idempotente y rechazo de colisión antes de usarlos.

Orden real: preflight de 22 funciones y dos restricciones → A y registro → Edge v26 → frontend y HTTP → Miguel confirmó que el equipo terminó borradores y recargó → preflight transaccional B → B y registro → conciliación y lecturas. Los archivos versionados A/B no se editaron.

El conector oficial Hostinger local cacheado confirmó acceso al dominio exacto. Usó la sesión OAuth existente solo en memoria, sin cambiar MCP, instalar paquetes ni abrir el navegador. `hosting_deployStaticWebsite` aceptó el ZIP tras pasar el preflight obligatorio. La respuesta de subida no se tomó como prueba suficiente: se verificaron los bytes publicados.

## Evidencia y límites

- Build, manifiesto, ZIP y preflight: **PASS**. Código idéntico al árbol probado de `d889fd00`; se reutilizaron los gates existentes conforme a release-crm. Una acta posterior no cambia el commit publicado.
- **126 comprobaciones HTTP PASS**: portada, index, versión y todos los JS/CSS, comparados por bytes y SHA256. La Edge rechaza petición vacía sin credencial con 401. No se crearon datos reales para probar.
- Lecturas SQL productivas READ ONLY como `authenticated`, con identidad existente de Coordinación, Gerencia, Supervisor y Vendedor: contratos anteriores y filtro F3 **PASS** antes/después de B. Cola, agenda y conversión de Coordinación **PASS**. No equivalen a inicio de sesión Auth humano.
- Captura aportada por Miguel (15/10, 16:39 Lima) inspeccionada: etiqueta y campo Origen **Formulario 3**, sin FORMULARIO adicional; estado Descartado y responsable visibles. **PASS de ficha**. Smoke visual completo de todas las pantallas con sesiones productivas **NOT RUN**; Cartera/Repartir/Coordinación/Gerencia tienen cobertura previa E2E Docker. No se controló el navegador.
- Advisors: mismas cinco categorías/conteos de seguridad que el ensayo y seis de rendimiento; persiste deuda previa. El número de índices sin uso difiere por actividad, no se presenta como saneamiento. URLs de remediación y resultados en [evidencia](../supabase/scripts/formulario3-origen/publicacion-verificacion.json).
- Gates previos: 6.915 unitarias + check completo PASS; Docker 419 passed, 26 skipped, 1 flaky de foco que pasó al reintentar y tres repeticiones sin retries. Rama: 111 aserciones HTTP/RLS/Edge con ocho sesiones reales. Gate seed-demo general NOT RUN sobre la copia con datos. [Ensayos y límites](../supabase/scripts/formulario3-origen/LEEME.md).

La rama temporal y sus credenciales ya estaban retiradas. Se preservó el paquete anterior `crm-20261015T193534Z-e25c8b8f9a21.zip`, SHA256 `7ff97d50321fb321d25fd9753d5436e70d78ce06f614134cba8294137e041278`, junto a su manifiesto. **Después de B no se restaura automáticamente ese cliente antiguo**: la recuperación debe ser compatible con nuevas altas/cierres nativos y revisada según el estado real. No se revierte SQL ni auditoría por defecto.

El caso de dos leads con el mismo nombre y teléfonos distintos no se fusionó: el nombre por sí solo no demuestra identidad. Esta publicación corrige el origen; no combina fichas.

[Plan actualizado en Figma](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).
