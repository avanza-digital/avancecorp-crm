---
tags: [crm, gestion-diaria, f4, publicacion]
estado: etapa 3 publicada y verificada; cortes OFF
fecha: 2026-09-22
---

# Gestión Diaria F4 etapa 3 — publicada y verificada, cortes OFF

El frontend pendiente se publicó el 22/09/2026 a las 12:28 Lima. Fuente
`e22c0cab2db30c5f570adf28f998d4d773fb3ed9`, build servido
`build-20260922T165247339Z`. Artefacto:
`CRM-Avance-Corp/releases/crm-20260922T165248Z-e22c0cab2db3.zip`, SHA-256
`58f81cbf903ffdcef6d892dabd38d7f75cf99d4f81d6baae7eb87e3192989098`.

El conector oficial de Hostinger Hosting ya instalado permitió publicar con
`hosting_deployStaticWebsite`; se comprobaron sus 64 herramientas y el acceso
al sitio. La sesión nativa sólo exponía 15 de Agency Hosting. No se cambió
configuración MCP, DNS ni proveedor.

Se recuperó antes el sitio anterior completo: 107 archivos cotejados byte a
byte contra la recompilación de `59dd1480` con el build ID anterior. Respaldo:
`CRM-Avance-Corp/releases/crm-respaldo-live-20260922T172350Z.zip`, con su
manifiesto, SHA-256
`7b881ca493f16db24f048618c2ad0d3471df055014dc3a21cc9b1dcf0d635432`.
Es una captura verificada; no se recuperó el manifiesto original. Se usó el
origen HTTPS para evitar transformaciones de imágenes por CDN; todo queda
fuera del web root.

PASS: ZIP/manifiesto y 107 archivos, Main/remoto de la copia limpia, preflight
de ancestría/Ficha 360, seis gates SQL de Gestión Diaria/SLA, 107 archivos
servidos en origen y 106 recursos públicos. Login visible en Playwright aislado,
sin errores JavaScript; ZIP no descargable (404), rutas internas protegidas.
El gate completo previo del mismo commit se conserva como evidencia anterior,
no como una ejecución nueva. Recorrido autenticado con supervisor: pendiente.

Producción conserva una única política v1 con `cortes_activos=false`. No se
reinstaló SQL, no se activaron avisos ni TypeSafe. El taller principal sigue
divergente y con trabajo ajeno; la copia limpia de publicación coincidía con
`avancecorp/main`. Se preservó todo ese trabajo y sólo se reconcilió el plan
documental con las decisiones y evidencia del remoto.

Sigue **F4 etapa 4: pop-up, reconocimiento y posponer**, después configuración
(5), validación/activación futura (6), F5 y F6. F4.1 conserva preparación técnica
y banco sintético, con piloto humano e integración productiva pendientes.
Ya están aprobados sábado mínimo 3, excluir del aviso de ritmo a quien no
tenga cartera abierta y un único aplazamiento de una hora sin reaviso al cierre.

Pendientes separados: conciliar el taller antes de editar producto; reconciliar
la versión SQL remota `20260922164159` con el archivo `20260921214018` antes de
otra publicación por CLI; revisar después los dos INFO de índices ya documentados.
La revisión previa de Claude sigue en el acta; las consultas sin dictamen
recuperado no cuentan como PASS. No se solicitó una revisión adicional aquí.

Acta: `CRM-Avance-Corp/docs/gestion-diaria/F4-ETAPA3-PUBLICACION-2026-09-22.md`.
Plan: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.

Relacionado: [[Gestion Diaria F4 - SQL OFF publicado y frontend pendiente (2026-09-22)]],
[[Gestion Diaria F4 - release detenido por historial de ramas (2026-09-22)]],
[[Gestion Diaria F4 - detalle del analista preparado (2026-09-21)]], [[Inicio]].
