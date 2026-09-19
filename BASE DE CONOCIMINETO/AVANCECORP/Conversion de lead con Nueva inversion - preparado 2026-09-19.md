---
tags: [crm, cartera, inversiones, conversion, preparado]
actualizado: 2026-09-19
---

# Conversión de lead mediante Nueva inversión

**SQL AUTORIZADO; VERIFICADO LOCALMENTE Y EN SUPABASE. SIN PUBLICAR EN PRODUCCIÓN.**

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
`faccafe040abb88d37aabd68b2927362c4554b72`: se conservan el modo integral de
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

Miguel autorizó el SQL exacto con «HAZLO» y el banco con un límite de US$5.
PASS remoto: 15 pruebas HTTP (14 escenarios), oráculo SQL, 284 aserciones de
permisos/contratos y nueve aserciones de la Edge desplegada. Advisors revisados:
las cuatro puertas SECURITY DEFINER nuevas tienen permisos intencionales y
controles de actor/ámbito; no se amplían las fronteras de las funciones existentes.
El [acta remota](../../CRM-Avance-Corp/supabase/scripts/conversion-inversion/instalacion/README.md)
conserva equivalencia del esquema, resultados y límites. CI del
[PR #23](https://github.com/avanza-digital/avancecorp-crm/pull/23) aprobado.

Pendiente: instalación coordinada de SQL, Edge y frontend por el flujo del
proyecto. La candidata bloquea la conversión antigua, por lo que no debe
activarse antes de poder publicar la web correspondiente. La autorización del
SQL persiste; la publicación necesita la invocación humana de `$release-crm`.

Relacionado: [[Cartera multiempresa - publicacion (2026-09-16)]],
[[Interruptor integral de rentabilidad - preparado 2026-09-18]],
[[Solicitud de tasa en el lead - publicada 2026-09-09]] y [[Inicio]].
