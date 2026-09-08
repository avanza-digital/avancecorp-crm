# F4 — cotitulares y corrección versionada

Continuación de [[F4 multiempresa - cotitularidad neutral y procedencia (2026-09-08)]]
y [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
Miguel encargó completar todos los pendientes F4 y conservar commits.

El banco tiene 47 cuerpos iguales a la candidata, 30 funciones nuevas, 11 módulos
y siete tablas F4 sin acceso directo API. La candidata sigue sin versionar hasta
su reconstrucción y revisión finales. Producción no fue modificada.

## Cotitulares

El módulo 10 vincula personas canónicas ya verificadas después de reservar el
snapshot documental del alta. Dos filas del mismo cotitular conservan dos
procedencias y una membresía; coincidir con el principal no degrada su rol.
Los documentos desconocidos quedan pendientes. Un documento reutilizado por
personas distintas requiere revisión. No se crea Auth, perfil, lead ni
responsable, ni se conceden permisos por ser cotitular. No se cambia el PDF.

`inversion_cotitulares_fn` lee el estado y `conciliar_cotitulares_inversion_fn`
recupera pendientes dentro del ámbito actual del principal. La procedencia
conserva persona e identificador originales con snapshots privados; después de
corregir/fusionar sigue la canónica vigente, sin resolver otra vez el documento
antiguo. Las fuentes ya vinculadas no admiten sustitución ni borrado. El
mantenimiento histórico privado requiere SQL administrativo y F4 apagada.

15 grupos conformes, incluida carrera documental, corrección y dos fusiones
reales, deduplicación contra principal, auditoría y recuperación. Son pruebas SQL
con claims sintéticos; el flujo documental reserva snapshot, no renderiza PDFs.

## Solicitudes

El módulo 11 permite `corregir_solicitud_inversion_fn` con clave, versión de datos,
contenido y motivo. Conserva la clave y huella de preparación inicial; registra
cada corrección inmutable. Mantiene persona, empresa, referencias de transporte
y ruta del comprobante. Una reserva Auth congela los datos de alta Portal.
`solicitud_inversion_fn` permite revisar el contenido vigente autorizado.

`confirmar_inversion_revisada_fn` exige la revisión observada para una pendiente.
La puerta anterior confirma revisión cero y conserva replay de una confirmada.
La revisión de responsable sigue separada y no cambia las condiciones originales.
20 grupos conformes: ambas cooperativas, Avance, reserva Auth real, datos
inválidos, permisos, auditoría y tres carreras entre corrección/confirmación.

## Permisos y configuración del banco

14 grupos de permisos dinámicos y 12 de pares Portal/CRM conformes: baja real,
reemplazo, sin responsable, rol y jerarquía reales, suspensión, ámbito y Directorio.
El dump de sólo esquema no transportaba `private.pares_autoridad`; se reproduce
exactamente la semilla publicada de nueve pares de la migración 20260830170000.
Cliente/vendedor en la misma cuenta sigue rechazado: F4 no inventa un par.

Checks de scripts y Edge preflight conformes. Seed/RLS preflight pasaron con
configuración local tras una primera ejecución sin SUPABASE_URL; esos dos son
offline, no sustituyen los oráculos SQL. Revisión Claude de diseño evaluada en
`evidencia-f4/auditoria-cierre-diseno-2026-09-08/`.

Pendiente del mismo encargo: corpus F2 completo, inventario de lectores/escritores,
matriz financiera ampliada, reconstrucción limpia/restauración, tipos y revisión
integral final. G4 no se declara cerrado con este checkpoint.
