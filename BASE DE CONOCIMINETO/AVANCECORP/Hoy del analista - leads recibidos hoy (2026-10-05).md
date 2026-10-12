---
tags: [crm, hoy, analista, leads, recepcion]
fecha: 2026-10-05
estado: publicado, integrado en Main y sesión cerrada
---

# Hoy del analista - leads recibidos hoy (2026-10-05)

Miguel pidió que los analistas vean los leads nuevos dentro del dashboard HOY y
aclaró: **solo los que le llegaron hoy**, en el mismo módulo existente.

Se añadió «Leads recibidos hoy» encima de «Tus citas», conservando agenda y
cumplimiento. Usa el ledger de recepción mediante la consulta paginada existente,
con día de Lima y analista actual. No filtra por etapa ni por fecha de creación:
los reasignados de hoy entran y los ya contactados/convertidos/descartados permanecen.
Muestra total, nombre, teléfono, hora y acceso a la ficha. Actualiza cada minuto
visible y al pulsar Actualizar; el cambio de día renueva el filtro.

Verificación de la versión inicial: check 6.091/378 PASS, dirigidas
71 PASS, E2E Docker 26/26 sin fallos ni reintentos PASS. Capturas escritorio/portátil/móvil
revisadas. Claude aportó mejoras de actualización y accesibilidad, aplicadas.
Gate de realidad general NOT RUN por falta de SUPABASE_URL; contrato vivo de
cartera_filtrada_fn y consulta READ ONLY bajo authenticated PASS (9 recibidos,
todas las filas del titular y día correctos). Sin cambios de backend.

**PUBLICADO** en https://crm.miavance.com/ con autorización «publiquemos si todo
está bien». Build `build-20261005T154516511Z`, fuente limpia `a98cf73fbd2866`.
ZIP `crm-20261005T154517Z-a98cf73fbd28.zip`, SHA-256
`8f4bef27c3f705a601b7c3d4f8a41fda1ef753fbae486698081a69e35a395977`.
Portada y 96/96 HTML/JS/CSS/version: HTTP 200 y hash exacto. Acceso con sesión
real de gerencia PASS; recorrido HOY de analista cubierto en Docker, sin sesión
productiva de ese rol disponible.

Preflight rechazó el candidato de Main por no contener el historial vivo.
Rescate en copia aparte desde `27e6f24849aa`, integración de Main preservando su
árbol y aplicación del parche. Equivalencia exacta con el código probado;
preflight final PASS. PR https://github.com/avanza-digital/avancecorp-crm/pull/191.
El taller original conserva sus cambios ajenos. ZIP y manifiesto guardados en
CRM-Avance-Corp/releases. Respaldo anterior `crm-20261005T023047Z-27e6f24849aa`.


Detalle y decisiones del review:
`CRM-Avance-Corp/docs/encargos/2026-10-05-hoy-leads-recibidos.md`.
Implementación: `app/src/screens/hoy/leads-recibidos-hoy.tsx` y `vendedor.tsx`.

Relacionadas: [[Hoy del analista - sin espacios vacios (2026-09-28)]],
[[Boton GESTION DIARIA en Hoy del analista (2026-09-28)]],
[[Leads - filtro Gestionado (2026-10-03)]].

Cierre GitHub: app-check, verify y preflight PASS. Fusión normal bloqueada por
REVIEW_REQUIRED (falta aprobación de otro revisor); auto-merge deshabilitado.
No se eludieron protecciones. Miguel tiene la solicitud de gestionar la revisión.
La rama publicada queda conservada y la integración a Main es el único pendiente.


## Ajuste visual pedido después de publicar

Miguel vio citas demasiado pequeña. Quiere «Tu agenda de hoy» y «Leads de hoy»
como dos botones para alternar la tarjeta izquierda; citas conserva su columna
completa y cumplimiento queda debajo de la izquierda. Pidió «muéstrame cómo se
vería»: vista previa preparada con datos sintéticos, sin nueva publicación.
Typecheck/lint, 71 tests y Docker 2/2 PASS. Acta y ubicación del parche:
`CRM-Avance-Corp/docs/encargos/2026-10-05-hoy-pestanas-vista-previa.md`.

## Diseño definitivo aprobado e implementación

Miguel aprobó las pestañas y pidió urgencia sin texto adicional: número blanco
sobre naranja, dos latidos breves cada 30 segundos. Aclaró que el aviso debe
continuar también DESPUÉS de abrir «Leads de hoy». En esa primera aprobación era el total recibido
en el día, de todas las etapas; el criterio posterior de pendientes, registrado
abajo, sustituye ese significado. No es un contador de «sin leer». Abrir una
ficha tampoco lo borra. Se renueva con la jornada de Lima.

La implementación mantiene una consulta compartida entre pestaña y lista,
incluso mientras se ve agenda. Actualiza cada minuto visible; espera si se está
cargando otra página para no cancelarla. Los controles de simulación de las
propuestas quedan fuera del producto. El número permanece visible en móvil y
la preferencia de movimiento reducido elimina la animación.

Estado vigente: **PUBLICADO y verificado** con autorización «publica».
Build `build-20261005T164935122Z`, fuente limpia
`ac46b2d37702c62b0d2c6dc075d0da2cde929c79`.
ZIP `crm-20261005T164936Z-ac46b2d37702.zip`, SHA-256
`a0b7e735c16b1fb03ccde1f126e2306ed8b77486a89ce743044641475dd83b05`.
Check local 6.096/378 y Docker 26/26 + final HOY 2/2 PASS; preflight y
verificación del artefacto PASS. Portada y 97/97 archivos HTTP 200/hash exacto.
Ahora sí hubo sesión real de analista: 9 recibidos, pestañas operativas y aviso
naranja con latido mantenido al abrir Leads de hoy. Citas conserva su columna.
Sin escrituras de prueba en datos reales. El gate general de realidad sigue
NOT RUN por entorno; no se atribuye un PASS a ese comando.

La PR #191 conserva checks PASS del código publicado y requiere aprobación
externa para fusionar a Main. Se publicó desde la rama de rescate ya existente,
que contiene tanto el release anterior como Main. Recuperación conservada:
`crm-20261005T154517Z-a98cf73fbd28.zip` y manifiesto. El taller original mantiene
los cambios ajenos.
Detalle y verificaciones: `CRM-Avance-Corp/docs/encargos/2026-10-05-hoy-pestanas-implementacion.md`.


## Criterio vigente: etapas y pendientes de gestión (05/10/2026)

Miguel corrigió el significado del aviso: **el número de la pestaña debe ser
solo los leads recibidos HOY que no ha gestionado**. La lista conserva todos los
recibidos y cada fila muestra su etapa actual con las etiquetas de Leads/ficha,
incluido Gestionado. Abrir lista/ficha no reduce el contador. Registrar una
gestión válida desde la tenencia actual lo reduce; cero queda gris y sin latido.
No cuentan convertidos/descartados. Notas, contactos del titular anterior y
resultados deshechos no acreditan gestión actual. Una etapa heredada se conserva
como dato real y no sustituye el criterio de gestión actual del contador.

Reutiliza `cartera_filtrada_fn` con analista, recepción de Lima y
`gestion: sin_gestion`; el resumen `abiertos` cuenta todo antes de paginar.
La lista y el resumen se invalidan al gestionar y comparten el único sondeo
visible de 60 segundos. Error no se muestra como cero. Sin cambios de backend.

Fuente: `5002b29725943d281cad3dd1eeeef1ae989616b4`. Gate integral PASS 6.100/378,
87 dirigidas PASS, Docker 3/3 PASS (guardar No contestó: 1 → 0; fila Gestionado
conservada). Lectura SQL productiva READ ONLY PASS. Revisión independiente
resuelta con evidencia; acta y límites: `CRM-Avance-Corp/docs/encargos/2026-10-05-hoy-etapas-pendientes.md`.

La PR #191 anterior ya se fusionó el 05/10/2026 en Main `0dfb1b5c`. La nueva
corrección está en https://github.com/avanza-digital/avancecorp-crm/pull/192.
Corrección **PUBLICADA y verificada por HTTPS**: build `build-20261005T172100476Z`,
ZIP `crm-20261005T172101Z-5002b2972594.zip`, SHA-256
`c0f3799f0a75b9a203ab39eb0ad8369b4e25af59fe2ece1014a16d493d13c7cd`.
Portada y 97/97 archivos HTTP 200/hash exacto, versión exacta; release y preflight PASS.
La sesión del navegador disponible cambió a gerencia: recorrido de analista en
producción NOT RUN para esta versión; sí están verificados el recorrido local
Docker y el contrato productivo READ ONLY. No se modificaron datos reales.
PR #192 fusionada por squash en Main `618cf7ce` el 05/10/2026 12:29 Lima;
checks ejecutados PASS, árbol idéntico al publicado. Recuperación conservada: release
anterior `crm-20261005T164936Z-ac46b2d37702.zip` y manifiesto.


## Cierre de sesión (05/10/2026)

Miguel pidió cerrar lo innecesario. Vista local apagada (puerto 5187 cerrado),
pestañas temporales retiradas y PR #192 cerrada por integración. CRM publicado,
otras tareas y bancos compartidos conservados. Acta, evidencia y paquetes de
recuperación guardados. La fuente publicada sigue conservada en su rama de
rescate: Main recibió el mismo árbol por squash, no la misma ascendencia.
