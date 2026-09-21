---
tags: [crm, gestion-diaria, resultado-llamada, decision]
actualizado: 2026-09-21
---

# Gestion Diaria - resultado separado del descarte (2026-09-21)

Miguel confirmó «Sí, separar el resultado del descarte». Sustituye para la nueva
versión la decisión de F2 de descartar automáticamente al elegir «No le interesa»
o «Pide otro producto». No sustituir el contenido de recibos ya guardados por v3.

El resultado se registra con motivo y admite próxima acción (llamada, WhatsApp,
cita o tarea), o solo registro. Descartar es una elección aparte y explícita.
«No volver a contactar» mantiene su veto, aunque el lead no se descarte.

La interfaz conserva la opción elegida y contrae las otras seis; «Cambiar resultado»
las vuelve a mostrar. El motivo es un selector compacto para dejar espacio a la agenda.
Se reutilizan título, campos de cita y reglas de la ficha.

**PUBLICADO el 21/09** desde `526e728e`, PR #62, release
`crm-20260921T170501Z-526e728e31ff`. Después del banco local autorizado
`gestion_diaria_f4_vista_chvrqh`, Miguel autorizó la SQL exacta y `$release-crm`.
SQL `20260921153654`, puerta v4, instalada y registrada. V3, núcleo y recibos
conservados; reversa ensayada únicamente en local. Claude revisó y el PRIMARY
contrastó su dictamen con pruebas; no se atribuye un PASS final al reviewer.
Evidencia productiva y límites: [[Gestion Diaria - publicacion de equipo y resultado (2026-09-21)]].

Acta con verificación, límites y decisión sobre observaciones:
`CRM-Avance-Corp/docs/gestion-diaria/RESULTADO-LLAMADA-SEGUIMIENTO.md`.
Plan único actualizado: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.

Se relaciona con [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]],
[[Gestion Diaria F3 - el dia del analista (2026-09-20)]] y
[[Gestion Diaria F4 - vista del equipo validada localmente (2026-09-21)]].
Es una ampliación F2/F3; no cierra F4 ni activa su piloto TypeSafe.
