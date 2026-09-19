---
tags: [crm, conversion, inversiones, cierre, publicado]
actualizado: 2026-09-19
---

# Conversión e inversiones — sesión cerrada

Miguel pidió guardar todo y cerrar la sesión. La implementación está terminada
y publicada: «Convertir a cliente» utiliza el proceso de «Nueva inversión» de
Cartera. No queda una instalación pendiente de esta tarea.

- Código integrado mediante [PR #23](https://github.com/avanza-digital/avancecorp-crm/pull/23).
  Fuente del artefacto publicado: `29d7aa202492ed7dbd9cbb62d7667953f50a1514`.
- SQL efectivo `20260919182218`, Edge de bienvenida y frontend verificados.
  El avance posterior de Main no cambia la fuente de ese artefacto.
- Corrección posterior del acceso integrada mediante
  [PR #27](https://github.com/avanza-digital/avancecorp-crm/pull/27), commit
  `7035feefbff5ade3e8a7b0a02c48c46fdac8f905`: portal v4 y bienvenida v2 publicados
  y comprobados byte a byte. No requirió nuevo SQL ni frontend.
- Estado final comprobado: inversión `confirmada`, acceso `enlazado`, un
  usuario Auth y un perfil, sin duplicados. CI `preflight`, `verify` y `e2e`
  SUCCESS; 119 pruebas del gate de Edges PASS. Miguel confirmó conformidad.
- Acta, recibo y ledger respaldados en la rama
  `codex/acta-conversion-publicada-20260919` y el
  [PR documental #25](https://github.com/avanza-digital/avancecorp-crm/pull/25).
  Al cerrar permanece abierto, sin integrar; eso no afecta la
  funcionalidad ya publicada. No confundir ese pendiente documental con un deploy.
- Ambos bancos temporales eliminados; gasto estimado total US$0,022142 de
  US$5 autorizados. El banco ajeno y el trabajo de la otra sesión se conservaron.
- Pruebas y comprobación HTTP conformes. La operación real del usuario se
  comprobó por consultas de solo lectura; navegación productiva por el PRIMARY
  y entrega efectiva del correo real: NOT RUN, según los límites del acta.

Respaldo local persistente, privado e ignorado por Git:
`CRM-Avance-Corp/releases/cierre-conversion-inversion-20260919/` en la carpeta
original del proyecto. Conserva los ZIP publicado/anterior y sus manifiestos,
evidencia y archivos de trabajo privados, inventario SHA-256 y esta nota. El
subdirectorio `correccion-acceso/` conserva los recibos del arreglo y el resultado
final saneado; no incluye las credenciales obtenidas durante el diagnóstico. Los
archivos privados no se suben a GitHub ni forman parte del build de la web.

Para retomar, leer [[Conversion de lead con Nueva inversion - preparado 2026-09-19]]
y [[Conversion - correccion de credencial de acceso 2026-09-19]], además del
[acta de publicación](../../CRM-Avance-Corp/supabase/scripts/conversion-inversion/instalacion/PUBLICADO-20260919.md).
No repetir SQL, merge, publicación ni creación de bancos. Continuar únicamente
si Miguel pide una tarea nueva. [[Inicio]] conserva la entrada de la funcionalidad.

Cierre final solicitado por Miguel: 19/09/2026, 15:19 Lima.
