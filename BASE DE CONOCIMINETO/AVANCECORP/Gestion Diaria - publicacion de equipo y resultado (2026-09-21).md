---
tags: [crm, gestion-diaria, f4, resultado-llamada, publicacion]
estado: publicado — recorrido humano pendiente
fecha: 2026-09-21
---

# Gestión Diaria — equipo y resultado publicados

Publicado en `https://crm.miavance.com/` el 21/09. Miguel autorizó las SQL exactas
`20260921040335` y `20260921153654` más `$release-crm`; aprobó e integró PR #62
como `miguejbs98`. Main local/remoto coincidieron antes de construir y desplegar.

Fuente `526e728e31ff64adaf9b737fa5e408ebe32005a2`, release
`crm-20260921T170501Z-526e728e31ff`, build `build-20260921T170500239Z`.
ZIP SHA-256 `15c7ff107559e80f6064cd545b7906e19a94a75bb2e82ab2be7feeb1e326dc7d`.
ZIP/manifiesto nuevo y anterior conservados fuera de la web en `CRM-Avance-Corp/releases/`.

El analista elige un resultado y las otras seis opciones se pliegan. «No le
interesa» y «Pide otro producto» permiten conservar el lead y agendar; descartar
es una decisión explícita. El veto «No volver a contactar» sigue impidiendo la
próxima acción. V3 y sus recibos se conservan sin reinterpretarlos como v4.

Supervisor y Gerencia ven el roster completo autorizado, incluso sin actividad.
La etapa 1 de F4 está publicada; no se activaron cortes, avisos, configuración
ni TypeSafe. Los trabajos ajenos del taller, incluida temperatura, quedaron fuera.

PASS: 4.016 pruebas, 231 E2E (26 omisiones), CI de PR y Main, SQL local y gates
productivos. Cinco identidades consultadas bajo authenticated solo lectura:
18/18/10/0/8 analistas, roster exacto y límites correctos. Tablas/ACL/RLS, policies,
objetos públicos, censo y v3 intactos. Advisors: solo el nuevo aviso esperado de
la RPC v4 DEFINER autorizada; rendimiento sin delta.

Portada, versión y JS/CSS coinciden con el artefacto. 106 recursos públicos HTTP
200, 95 idénticos por SHA; seis PNG con píxeles iguales y cinco logos servidos a
menor resolución, compatibles con optimización CDN. No se afirma igualdad de
todos los PNG. No había navegador conectado para inspección visual productiva.
La matriz Auth/HTTP completa y el recorrido humano no se acreditan con SQL/mocks.
El oráculo histórico F1 conserva su fallo previo de whitelist.

Acta detallada (incluye dictamen de Claude evaluado, SHA SQL y recuperación):
`CRM-Avance-Corp/docs/gestion-diaria/PUBLICACION-2026-09-21.md`.
Plan único actualizado: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.

**Checkpoint pedido por Miguel:** después de publicar expresó «perfecto ahora si
me gusta mas» y pidió guardar todo el progreso. Conformidad con la mejora visible
registrada; no equivale a una prueba completa de todos los roles ni autoriza otra
etapa. Plan, actas, ledger y memoria guardados en un commit documental local,
sin nuevo deploy ni SQL y sin incluir los trabajos ajenos. La fuente productiva
sigue siendo `526e728e`; la documentación posterior no cambia el artefacto servido.

**Retomar:** recorrido de uso normal con analista/supervisor y F4 etapa 2,
detalle → actividad → ficha, reutilizando el registro ya disponible. No repetir
instalaciones ni activar TypeSafe. Un rollback requiere coordinar guardados v4
inciertos; nunca retirar SQL automáticamente por un problema visual.

Relacionadas: [[Gestion Diaria - resultado separado del descarte (2026-09-21)]] ·
[[Gestion Diaria F4 - vista del equipo validada localmente (2026-09-21)]] ·
[[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] · [[Inicio]].
