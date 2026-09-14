# Tasas inferiores — publicado el 14/09/2026

Disponible en https://crm.miavance.com/. Nuevas inversiones admiten desde 0,01 %
hasta la base vigente (15 %), con dos decimales y coma o punto. Una tasa superior
requiere la aprobación exacta de Gerencia antes de convertir. Una solicitud
pendiente sigue bloqueando aunque se escriba una tasa inferior. Se conserva la
tasa elegida hasta el contrato; renovaciones, correcciones y PDF mantienen sus
protecciones.

Miguel autorizó el despliegue después de la pausa y el banco de PortalAvanceCorp
hasta US$1, eliminándolo al terminar. No queda pendiente otra autorización.

## Instalación y artefactos

- Producción Supabase: `dctqcbznekcyxhjujuci`; migración fuente inmutable
  `20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql`, instalada mediante
  merge del banco propio como **`20260914174353`**. No volver a aplicarla.
- Las 286 entradas anteriores del historial se conservaron; total 287. El merge
  segmentó la candidata en 11 sentencias: al reponer separadores y retirar líneas
  vacías se obtiene el mismo SQL fuente. Cuatro cuerpos modificados y un helper
  privado nuevo; 644 funciones y sus atributos coinciden con el banco probado.
- Las 19 Edge Functions coinciden con el banco. Las dos huellas de Vault de
  producción se conservaron; el banco tenía Vault vacío al fusionar. Esta tarea
  no activó ni desactivó F8 ni cambió la configuración de Citas.
- Publicación de Tasas desde Main/remoto limpio e idéntico:
  `faa1059745aa852c4fb8275ff23f5a039f09e2a4`, build `tasas-faa1059-20260914`.
  ZIP `crm-20260914T210900Z-faa1059745aa.zip`, 92 archivos, SHA-256
  `80fbb3b5788177c357062689997144d21de65b1ffcc0084dc6d6b08e50904d41`.
- Citas publicó después `32d57b5b3e155dd49a212afba40cd84056186581`, descendiente
  de nuestra fuente. **Build vigente al cierre: `build-20260914T211412536Z`.**
  Su ZIP `crm-20260914T211416Z-32d57b5b3e15.zip` tiene SHA-256
  `17fe0bf171b419a46e635b57a25f57acfba73c017c257b0d22240e91631c0545`.
  Se verificaron ambos ZIP y manifiestos. El cambio posterior solo toca avance
  de Citas y pruebas de tipo de cambio: conserva todo el código de Tasas.
  Se integró Main hasta `57883a4`, sin sobrescribir esa publicación ni F8.

## Verificación y límites

| Estado | Evidencia y alcance |
| --- | --- |
| PASS | Preparación integrada: 3.546 tests frontend con cobertura, lint, tipos, build, bundle y 16 E2E de tasas/Citas. Dos revisiones de Claude evaluadas y corregidas; dictámenes originales conservados. |
| PASS | SQL remoto con Citas/F8: siete tasas positivas, precisión antes del redondeo, cuatro regresiones y tres escenarios concurrentes; permisos, PDF y reversa antes/después del uso. |
| PASS | 15 comprobaciones Auth/HTTP: contratos 0,01/12,5/15, negativos, conversión a 12,5 y bloqueo de solicitud pendiente con ambas banderas. Conversión HTTP por cliente ficticio existente; sin correos. |
| PASS diferencial / FAIL global | Matriz general: mismos 42 fallos entre 1.828 aserciones antes/después, cero nuevos. Incluye expectativas antiguas de métricas/identidad y R1 que espera observación bajo política de enforcement. Comparación previa a Citas; después del rebase se repitieron dominio SQL, HTTP y E2E, no la matriz completa. |
| PASS | Reconstrucción limpia de dependencias y build desde `faa1059`; configuración productiva, modo demo desactivado y ZIP cotejado por archivo. Su código de producto era idéntico al de `f52a63c`, previamente probado. |
| PASS | Nueva lectura productiva al cierre: cuatro huellas aún iguales, migración presente, mínimo nuevo 0,01 y mínimo heredado conservado. |
| PASS | 67/67 recursos HTML/JS/CSS/JSON/manifest de la publicación vigente coinciden por SHA-256; raíz HTML correcta. Versionado, worker y manifest se sirven con `no-store`. `.htaccess` coincide con el paquete: el lector omite un salto final, repuesto según su tamaño declarado. |
| NOT RUN | Inspección autenticada manual de producción, creación Auth nueva/correos reales y replay histórico completo desde cero. El banco se reconstruyó por el fallo heredado del replay y se comprobó su paridad antes del merge. |

Los resultados remotos previos a la retoma constan en el registro de la sesión;
sus logs originales en `/private/tmp` no persistieron. No se presentan como una
nueva ejecución. Se adjuntan las comprobaciones productivas nuevas y se conserva
la evidencia local versionada en [verificacion.md](verificacion.md).

La primera lectura de nuestro paquete obtuvo 80 coincidencias HTTP y 11 PNG con
bytes distintos a los del ZIP, servidos por `hcdn`. Los tamaños en origen eran
correctos; seis PNG coincidían por píxeles RGBA y cinco no. No se afirma igualdad
binaria o visual de todas las imágenes ni se modificaron. Se limpió la caché del
CRM. La publicación posterior de Citas explica la sustitución de nuestros chunks;
se pasó a verificar su manifiesto vigente. Un intento con urllib obtuvo 504; el
acceso con curl respondió 200 y la comprobación completa final con curl pasó.
El diagnóstico original se conserva, sin convertir sus fallos en PASS.

Advisors: las mismas categorías del banco siguen presentes; producción añade
un aviso por `pg_net` en `public`, ajeno a este SQL que no crea ni mueve extensiones.
No se declara una base sin avisos. [Referencia del aviso](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public).

## Banco, respaldo y recuperación

Se eliminó exclusivamente `tasas-inferiores-20260914`, id
`3d023eaa-5999-4e1a-8f3e-6c1c7c600d79`, proyecto `gvstgldssatszdovumhe`, y se
confirmó su ausencia del listado. Creado 16:42:34 UTC, eliminado 21:05:56 UTC.
A US$0,01344/h, estimación **US$0,059**, inferior al máximo US$1; no es una factura.

Evidencia saneada: [evidencia-publicacion-20260914](evidencia-publicacion-20260914/).
ZIP, manifiestos y respaldo privado quedan fuera del web root en
`CRM-Avance-Corp/releases/tasas-inferiores-20260914/` del workspace principal.
La publicación posterior de Citas conserva el ZIP de Tasas como reversa inmediata;
consultar también `UX-UI-GERENCIA/citas-ticket-soles-2026-09-14/PUBLICACION.md`.

La reversa SQL rechaza reservas activas/selladas, conversiones comprometidas o
contratos inferiores ya registrados. Después del primer uso corresponde corregir
hacia delante, sin borrar registros para habilitar una reversa. Una reversa del
frontend requiere considerar la publicación posterior de Citas; no restaurar
automáticamente el paquete previo a Tasas.
