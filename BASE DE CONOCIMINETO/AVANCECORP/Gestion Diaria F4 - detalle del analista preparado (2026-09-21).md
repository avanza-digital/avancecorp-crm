---
tags: [crm, gestion-diaria, supervisor, f4, verificacion]
estado: etapa 2 implementada localmente — sin publicar
fecha: 2026-09-21
---

# Gestión Diaria F4 — detalle del analista preparado

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

No se ejecutaron migraciones, escrituras de negocio, push ni deploy para esta
etapa. Las SQL de la entrega anterior permanecen instaladas sin cambios. El
detalle necesita revisión humana y autorización de publicación antes de darse
por activado. La siguiente implementación es F4 etapa 3; mínimos del sábado y
otras decisiones de cortes siguen pendientes. TypeSafe continúa separado.

Relacionadas: [[Gestion Diaria - publicacion de equipo y resultado (2026-09-21)]] ·
[[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] ·
[[Gestion Diaria F4 - vista del equipo validada localmente (2026-09-21)]] · [[Inicio]].
