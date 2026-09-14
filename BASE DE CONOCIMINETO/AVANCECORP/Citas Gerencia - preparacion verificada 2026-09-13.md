---
tags: [crm, citas, gerencia, verificacion, release]
fecha: 2026-09-13
estado: publicacion-existente-verificada
---

# Citas Gerencia — preparación verificada

## Estado vigente: publicación comprobada el 13/09

Ante «podemos publicar», se consultó nuevamente producción y se encontró la
entrega ya instalada y publicada por una acción externa a esta sesión. No se
volvió a instalar SQL ni a desplegar la web.

- Producción tiene las tres versiones `20260912151320`, `20260912181045` y
  `20260913173350` (278 migraciones). El control analítico pasa; las siete firmas
  de Citas conservan cuerpo, propietario y permisos idénticos al banco validado.
  El cuerpo de la RPC de Leads recibidos coincide con su migración.
- Se reprodujo el build público `build-20260913T191240365Z` desde el checkout
  limpio `d3ce2c18850d7c86bb90e2cfda7522e7333fadd1`, usando su configuración
  pública observada. **72/72 archivos HTTP coinciden por SHA-256**: aplicación,
  estilos, fuentes, HTML, versión, manifiesto y service worker.
- Leads recibidos se observó en una sesión autenticada de analista. La pantalla
  de Citas con Gerencia no se comprobó en el navegador productivo en esta sesión.
- La nueva corrida general sigue en **FAIL: 55/1.829**, con la semilla reutilizada
  tras los ensayos HTTP. No es un A/B y no reemplaza la comparación inicial de
  49 fallos iguales antes/después. Su diagnóstico continúa pendiente.
- Claude no entregó dictamen en los dos intentos de esta comprobación. No se
  contabiliza como PASS. El banco propio volvió a quedar `INACTIVE`.

Evidencia: `UX-UI-GERENCIA/citas-publicacion-2026-09-12/produccion-observada-2026-09-13.json`.
Artefacto reconstruido equivalente (no identifica el ZIP original subido):
`crm-20260913T203216Z-d3ce2c18850d`, SHA-256
`f10fb23f074aee2d74a412f34ea6c62a45a09e1d5cc6e27ac04060628a5030b1`.
Las nuevas metas y proyecciones mantienen el alcance pendiente documentado abajo.

## Historial de preparación

Miguel reanudó la preparación después de [[Citas Gerencia - publicacion pausada 2026-09-12]].
Se verificó la reparación de [[Citas Gerencia - conexiones corregidas en local 2026-09-12]]
sin instalarla ni publicarla en producción.

## Resultado

- Frontend aislado del resto de borradores: 3.413 pruebas, TypeScript, lint y
  build PASS. Playwright: 173 PASS, 26 omitidas bajo sus condiciones existentes.
- Banco Supabase propio: esquema completo contrastado con el padre, 32
  comprobaciones HTTP con Auth real, 52 comparaciones de núcleos/contratos,
  límite 10.000/10.001 y cohorte de 2.500 leads/10.000 citas/100 cierres PASS.
- Dos migraciones verificadas y registradas **sólo en la rama**
  `citas-validacion-20260912` (`xhgsjtzpmwlqfkninphl`):
  `20260912151320` y `20260912181045`. Gate analítico: 34 declarados, 30 sujetos
  al techo, cuatro auxiliares con cuerpo/propietario/ACL verificados.
- Deriva y fallo antes del COMMIT revierten íntegramente; mutantes rechazados.
  Revisión independiente de implementación PASS.
- Matriz RLS general A/B: mismos 49 fallos entre 1.827 comprobaciones;
  **sin regresiones, pero no PASS global**. Hay configuración incompleta en la
  semilla y casos que requieren diagnóstico; no se consideran todos inocuos.
  Advisors sin nuevos avisos de esquema o rendimiento de las candidatas.

La semilla general carecía del singleton de control SLA. Se completó después
del A/B copiando configuración de negocio y sustituyendo el actor por uno
ficticio; el recorrido HTTP de Citas sí se ejecutó con ese control activo.
No se cambió código productivo para acomodar la prueba.

## Alcance conservado

Conversión a cliente sigue siendo el hecho requerido para el indicador de
depósitos por lead. Una cooperativa sin perfil cliente no infla esa conversión.
Las anulaciones quitan el cierre del indicador conservando el historial;
las citas futuras respecto al cierre no reciben atribución retroactiva.

No se activan todavía la meta 1,25, las tasas del 70%, la proyección ni el ticket.
Siguen los pendientes de [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]]
y [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]].
El enlace de navegación del borrador había llegado a HEAD sin su ruta: el
artefacto de esta reparación lo excluye, preservando el borrador en el workspace.
También se fijó el reloj de un fixture de Rentabilidad que caducaba el 13/09.

## Entrega y límites

Evidencia detallada: `UX-UI-GERENCIA/citas-publicacion-2026-09-12/README.md`.
El manifiesto del artefacto debe identificar el commit idéntico en `main` y
`avancecorp/main`; no usar `origin/main` ni `tronco`.

La deuda global queda expuesta para la decisión de publicación. Instalar SQL
productivo, publicar web y verificar el despliegue real son **NOT RUN** en esta
preparación. La autorización de preparar/ensayar no se presenta como una
instalación productiva realizada.

Relacionado: [[Citas Gerencia - auditoria de conexion a nucleos 2026-09-11]].


## Integración con la entrega de Leads recibidos

Miguel confirmó que la otra sesión terminó. Se combinaron el commit de Citas
`f3146ec` y `9cf0c7b` (Leads recibidos). Se conservaron ambos cambios y se
resolvieron únicamente dos conflictos documentales. La copia integrada pasó
3.424 pruebas, TypeScript, lint y build; Playwright: 173 PASS y 26 omitidas.

El ensayo remoto combinado mantuvo idénticos el detalle de Citas y el control
analítico. La tercera función se probó en una transacción revertida; producción
permanece sin las candidatas. Evidencia actualizada en el README de la entrega.

El paquete final debe corresponder al commit integrado idéntico en `main` y
`avancecorp/main`; el ZIP anterior de `f3146ec` es histórico. El manifiesto del
paquete final y `CRM-Avance-Corp/releases/citas-entrega-2026-09-13.json` identifican
ese commit sin incorporar los borradores locales de nuevas metas/proyección.
