# Upgrade Avance - tasa del nuevo aporte y solicitudes (2026-10-07)

Estado: PUBLICADO y verificado en https://crm.miavance.com el 07/10/2026.
SQL `20261007180108`; commit `ab361d4f6c6d2b9db2e36c5a6ece71894725398d`;
build `build-20261007T191820053Z`. Rama temporal eliminada.

Miguel pidió poder negociar la tasa al registrar un upgrade y recordó que debe
respetarse la configuración que desactiva las solicitudes de tasa.

El contrato activo elegido aporta una referencia; el nuevo aporte abre otro
contrato. Las condiciones del contrato anterior se conservan.

- Solicitudes desactivadas: tasa menor o mayor editable, dentro de los límites
  vigentes, sin solicitudes ni consumo de aprobaciones. Las pendientes no bloquean.
- Solicitudes activadas: menor o igual a la referencia sin excepción; superior
  mediante «Solicitar tasa superior», motivo y aprobación de Gerencia.
- La tasa de referencia se precarga al elegir el origen. Reabrir un borrador
  conserva la tasa pactada. Renovaciones y cooperativas mantienen sus reglas.

La migración `20261007180108_crm_upgrade_tasa_flexible.sql` modifica tres cuerpos
privados conservando permisos. Usa una capacidad nueva separada para que los
CRM anteriores sigan leyendo el mínimo heredado sin error. La reversa solo se
admite antes del primer uso y espera las escrituras concurrentes.

Verificado: 6.364 tests de app; E2E Docker completo 383 PASS y 26 omitidos;
SQL autenticado local/remoto, contratos anteriores intactos, aprobación única,
modo ON/OFF, reversa y concurrencia. RLS inicial 3.074/3.075: faltaba la fila de
configuración de Reparto en el fixture de la rama; restaurada, bloque completo
Reparto 117/117 PASS. Dos hallazgos de la revisión independiente corregidos.

Producción conserva observación v18 (solicitudes apagadas), base 15 y tope 25.
SQL y permisos comprobados tras la fusión; 436 migraciones anteriores y 22 Edge
Functions intactas. Portada y 118 archivos de código/estilos/version exactos;
acceso autenticado comprobado sin altas reales. Los PNG servidos por hcdn se
recomprimen (7 con píxeles iguales) o redimensionan (5 logos), registrado en acta.

Artefacto: `crm-20261007T191820Z-ab361d4f6c6d.zip`.
SHA-256: `0c8fe83fba846b7c33b7745aee3362a169638e7823cff2656428606e14f7f8dc`.
Acta y límites: `CRM-Avance-Corp/supabase/scripts/upgrade-tasa/PUBLICACION.md`.
La copia limpia de Main coincidía con `avancecorp/main` al construir y publicar;
los cambios ajenos del taller se preservaron. El ZIP anterior queda respaldado.

Limpieza solicitada por Miguel completada el 07/10/2026: eliminados la copia
temporal de publicación, el banco local `upgrade_tasa_20261007`, la rama
GitHub ya fusionada y los archivos auxiliares de esta sesión. Se conservan el
código, las pruebas reutilizables, el ZIP publicado y el respaldo, el acta y la
evidencia final. Inventario: `CRM-Avance-Corp/output/upgrade-tasa-20261007/limpieza.json`.

Relacionadas: [[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]],
[[Modo observacion mantiene solicitud de tasa - diagnostico 2026-09-18]],
[[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]],
[[Upgrade cooperativo separado de reinversion (2026-10-06)]].
