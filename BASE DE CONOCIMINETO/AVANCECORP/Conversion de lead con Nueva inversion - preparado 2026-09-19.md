---
tags: [crm, cartera, inversiones, conversion, preparado]
actualizado: 2026-09-19
---

# Conversión de lead mediante Nueva inversión

**PREPARADO Y VERIFICADO LOCALMENTE. SIN INSTALAR NI PUBLICAR EN PRODUCCIÓN.**

Miguel pidió que «Convertir a cliente» use el mismo proceso que «Nueva inversión»
de Cartera, que considera la referencia correcta. La conversión anterior tenía
un formulario y puertas de guardado propios: crear la identidad/cuenta podía
cerrar el lead antes de tener la inversión completa. El nuevo acceso reconoce
la identidad y delega campos, revisión y confirmación al formulario de Cartera.

## Decisiones de negocio

- Reconocer una persona o preparar su acceso Avance no convierte el lead.
  Sólo confirmar la inversión lo cierra como ganado, junto con su actividad.
- Avance conserva su contrato; Qorilazo y Prodelco conservan su registro de
  inversión y comprobante. Se usan los mismos componentes desde ambos accesos.
- Cerrar conserva la solicitud para continuar. Cancelarla es explícito y deja
  el lead abierto; permite volver a elegir empresa y moneda. No anula inversiones
  confirmadas. Un acceso Avance en curso se recupera antes de cancelar.
- Un reintento o dos pestañas no pueden producir dos conversiones del mismo lead.
  Se conserva la persona canónica, su analista y la primera conversión que
  alimenta Cartera y métricas. Una inversión adicional no repite ese indicador.
- El botón de conversión permite elegir empresa. Las restricciones de tasa de
  Avance se verifican dentro de su formulario común y otra vez en el servidor;
  no bloquean por adelantado la elección de una cooperativa.
- La bienvenida Avance va después de confirmar y puede reintentarse desde el
  lead convertido. Una respuesta incierta de más de 23 horas requiere verificar
  la entrega en el proveedor; no se vuelve a confirmar la inversión.

## Aislamiento y compatibilidad

Miguel confirmó que otra sesión seguía trabajando en citas y autorizó trasladar
únicamente los cambios de esta tarea. Se trasladaron y verificaron los 33 archivos
iniciales, conservando los cambios ajenos en su carpeta. Después de la pausa,
ordenó explícitamente retomar.

Trabajo: `/private/tmp/avancecorp-conversion-wt`, rama
`codex/conversion-inversion-20260919`. Se integró Main
`4d33785eddd629483ca26aefc606534a823be5ee`: se conservan el modo integral de
rentabilidad y la entrevista al asistir de la otra sesión.

## Evidencia y siguiente paso

PASS: 3.694 pruebas frontend y build, 15 casos HTTP con Auth/PostgREST/Storage
reales en banco sintético, oráculo económico y reversa, permisos, Edge y scripts.
Navegador con backend real: escritorio y móvil. Regresión general: 201 PASS,
26 SKIP y una expectativa antigua corregida; los tres tests del archivo afectado
pasaron al repetirlo. No se envió correo real.

La revisión independiente pidió cambios. El PRIMARY corrigió o contrastó cada
hallazgo con evidencia; no existe un dictamen posterior que deba citarse como PASS.

El [acta técnica](../../CRM-Avance-Corp/supabase/scripts/conversion-inversion/README.md)
incluye el SQL exacto `20260919161807_crm_conversion_inversion_unificada.sql`,
reversa, huellas y evidencia saneada. Añade dos columnas a solicitudes y conserva
los escritores contractuales del portal. No modifica objetos de `public`.

Pendientes: autorización del SQL exacto, ensayo remoto con matriz RLS/advisors,
instalación y publicación por el flujo del proyecto. No confundir esta entrega
local con un cambio ya visible para los analistas.

Relacionado: [[Cartera multiempresa - publicacion (2026-09-16)]],
[[Interruptor integral de rentabilidad - preparado 2026-09-18]],
[[Solicitud de tasa en el lead - publicada 2026-09-09]] y [[Inicio]].
