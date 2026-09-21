---
tags: [crm, gestion-diaria, supervisor, f4, verificacion]
estado: etapa 2 publicada y verificada — cierre técnico
fecha: 2026-09-21
---

# Gestión Diaria F4 — detalle del analista publicado

Miguel pidió retomar F4, etapa 2. Se conserva el alcance del plan principal:
explicar los indicadores mediante sus actividades y abrir la ficha del lead
desde el registro, sin duplicar la pantalla del analista ni el historial F1.

La fila desplegable incorpora llamadas/contestadas por hora de Lima (08–20),
con las horas exteriores declaradas y los conteos visibles además del gráfico.
Un desglose inconsistente se avisa, no se convierte en ceros. El registro de la
fila abre Todo; el acceso desde el desglose abre Llamadas. El registro general
del equipo conserva Llamadas, como en la versión publicada. Se conserva fecha, analista,
filtros y foco al abrir/cerrar la ficha, que se relee bajo RLS aun si ya está
en memoria. La falta de un lead en la carga inicial no impide abrirlo.

El registro compartido respeta 16 px y distingue ausencia de resultados con
filtros, vacío del ámbito consultado, carga, error y falta de autorización.
Se descartan páginas acumuladas al cambiar identidad/día/ámbito o recibir
`42501`. Una prueba de navegador detectó y permitió corregir que «Actualizar»
desde la página 2 reutilizaba una primera página todavía fresca en la caché.

Claude revisó la primera candidata como asesor de sólo lectura. Sus hallazgos
confirmados sobre reapertura, errores transitorios y teclado quedaron corregidos
y protegidos por pruebas. Se documentaron también las hipótesis descartadas con
evidencia. Una revocación confirmada cierra el registro con aviso; un fallo
temporal del resumen no destruye sus páginas ni mueve el foco al recuperarse.

Los conteos horarios y el registro no son una auditoría de paridad SQL: el
registro sólo lista actividades de leads visibles y tiene otro corte de lectura.
La diferencia histórica entre contestadas por tipo y contacto útil se explica
sin alterar métricas ni migraciones. La UI informa de ambos límites.

Fuente local: rama `codex/gestion-diaria-f4-detalle-analista`, taller existente
`/private/tmp/avancecorp-gd-f4-vista.chvRqh`, base `b0d2ff89`. Esta base tiene el
mismo árbol que `5e538358`, desde el que comenzó el trabajo; no se sobreescribió
Main ni se incorporaron sus cambios ajenos sin commitear.

Acta técnica y estado exacto de los checks:
`CRM-Avance-Corp/docs/gestion-diaria/F4-DETALLE-ANALISTA.md`.
Plan vigente: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.

Durante la preparación no se ejecutaron migraciones, escrituras de negocio,
push ni deploy. Las SQL de la entrega anterior permanecen sin cambios.
Miguel expresó conformidad visual tras revisar la vista local el 21/09 («ok
listo si me gusta que sigue?»). Esa conformidad no fue la autorización de
publicación ni una prueba integral de negocio contra datos reales; después
se recibió una orden de release por separado.
La siguiente implementación es F4 etapa 3; mínimos del sábado y
otras decisiones de cortes siguen pendientes. TypeSafe continúa separado.

Actualización de release: Miguel invocó `$release-crm` después de la conformidad
visual y aprobó e integró el PR #64. **Publicada y verificada el 21/09 a las
15:07 Lima**, fuente `baa63aeac71e5a074309aae92a064b67756189f1`, build
`build-20260921T200508459Z`. Main y remoto coincidieron antes de construir
y subir; el árbol de app probado es idéntico al del artefacto. Preflight
SQL de lectura PASS para cinco identidades, roster, horarios, paginación y siete
rechazos esperados. Main se integró conservando sus cierres previos y los cambios
pendientes de otras tareas quedaron intactos. CI del PR: 4.051 pruebas y
232 E2E/26 omitidos PASS. Release/build y 110 comprobaciones HTTP finales PASS;
los 68 recursos JS/CSS coinciden con el manifiesto.

ZIP `crm-20260921T200509Z-baa63aeac71e.zip`, SHA-256
`d513d1265123d7c38f800ccec9805a9611749df5830dbf5909c2d505b81c20e3`.
Artefactos, recibo, evidencia y recuperación anterior conservados en
`CRM-Avance-Corp/releases/`. Acta vigente:
`CRM-Avance-Corp/docs/gestion-diaria/F4-ETAPA2-PUBLICACION-2026-09-21.md`.

La etapa 2 queda cerrada técnicamente, sin nuevas SQL ni activación de cortes.
Siguen NOT RUN el recorrido humano autenticado productivo, VoiceOver y la
matriz general Auth/HTTP. El script `gate:realidad` completo tampoco se ejecutó;
la evidencia SQL alternativa y sus límites están en el acta. No se declara F4
completa ni el piloto TypeSafe realizado.

Relacionadas: [[Gestion Diaria - publicacion de equipo y resultado (2026-09-21)]] ·
[[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] ·
[[Gestion Diaria F4 - vista del equipo validada localmente (2026-09-21)]] · [[Inicio]].
