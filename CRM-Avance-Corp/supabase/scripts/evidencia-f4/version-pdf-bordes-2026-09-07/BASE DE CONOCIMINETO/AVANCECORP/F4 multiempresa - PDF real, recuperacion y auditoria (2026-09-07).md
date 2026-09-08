---
tags: [crm, multiempresa, f4, pdf, auditoria, retomar]
fecha: 2026-09-07
actualizado: 2026-09-07T22:09:00-05:00
estado: avance-local-G4-abierto
---

# F4 — PDF real, recuperación y auditoría

**F4 sigue abierta.** Se avanzó el proceso documental y se corrigió un fallo
de relectura de inversiones confirmadas. Todo se ensayó en `avancecorp-f4-bank`,
con datos ficticios; no se publicó ni activó el nuevo circuito en producción.

## Decisión expresa de Miguel sobre el PDF

Conservar el contenido actual del contrato. Cualquier incorporación relativa a
cotitulares requiere mostrarle primero **el texto y la ubicación exactos** y
obtener su aprobación. No hay autorización para modificar otras partes.

La plantilla `contrato-aep-17-v7`, el renderer, firma, fondo y fuentes conservan
las mismas huellas que HEAD. No se incorporó texto, anexo ni firma de cotitular.
La base contractual y el snapshot guardan al cotitular; el PDF vigente no lo
imprime. Esto continúa pendiente de revisión con Miguel y no se da por aceptado.

## Qué se comprobó

- PDF generado y descargado por el servicio Deno real para Avance PEN y USD.
  Tres descargas repetidas conservan la misma huella, con un solo archivo y sello.
- Fallos de render, subida, descarga y firma; respuestas perdidas después de subir,
  verificar y sellar; dos generadores simultáneos. El ensayo completo pasó en
  **12 grupos y 10 contratos**. Se respetaron los **120 segundos reales** de reserva.
- La ampliación posterior recuperó también por Deno dos archivos que aún no
  existían. El adaptador reconoce su ausencia y logra el sello en el segundo
  intento. Los reintentos medidos tardaron 40–434 ms en este banco.
- Cuatro contratos de ensayos interrumpidos se recuperaron por Deno, sin otra
  fuente, inversión ni reserva documental.
- **42 pruebas** satisfactorias: 31 del handler y 11 del adaptador Storage. La revisión visual previa de dos contratos
  ficticios, PEN y USD, cubrió sus **14 páginas**: sin recortes ni desbordes
  observados. Se conservan en la carpeta privada del ensayo `33fecba4…`; no son
  contratos para entregar a clientes ni una aprobación del contenido legal.

La corrección técnica consulta un objeto existente antes de repetir su subida,
verifica sus bytes contra el render determinista y conserva la prohibición de
sobrescribirlo.

## Ampliación de recuperación — 22:09 Lima

Pasaron **10 grupos adicionales con ocho contratos nuevos**, y después la
regresión de **12 grupos con otros 10 contratos** sobre la candidata SQL actual:

- Las operaciones Storage tienen un plazo de 20 segundos que incluye cabeceras
  y cuerpo, con cancelación independiente. Cuatro cortes reales de transporte
  terminaron en 20,195–20,269 segundos y se recuperaron por el servicio Deno.
- Un generador retenido atravesó los 120 segundos reales de reserva. Después
  subió su archivo, pero su token vencido no pudo verificar/sellar (409). La
  colisión del otro generador devolvió 503 en 370 ms; el tercer intento recuperó
  los mismos bytes con un archivo, un sello y una inversión.
- Tres respuestas con versión incompatible dejaron la reserva libre, sin usar
  Storage ni cambiar snapshot/versión en SQL. Se recuperaron con la metadata real.
- Los dos contratos anteriores sin job devuelven `sin_reserva`, no reintentable,
  y permanecen intactos. No se les genera ni sustituye un documento histórico.
- Se verifica tamaño/formato antes de calcular la huella del PDF. Esto evita la
  copia adicional para una huella de un archivo excesivo; el SDK aún materializa
  el cuerpo descargado. No se afirma una solución completa a alteraciones privilegiadas.

El timeout cubre Storage; no es un límite global del proceso Auth/SQL/render.
Las incompatibilidades se simulan en respuestas al worker: no se fabrican estados
ni versiones contractuales en la base. La revisión visual citada corresponde a
los dos archivos anteriores; el contenido y sus recursos siguen byte-idénticos.

## Auditoría adversaria y corrección aceptada

Claude actuó como revisor secundario sin editar archivos ni delegar. Su informe
se contrastó con código, índices y ejecución real: no se convirtió en aprobación
de F4. El informe y la decisión sobre cada hallazgo se conservan en
[evaluación de la auditoría](../../CRM-Avance-Corp/supabase/scripts/evidencia-f4/auditoria-claude-2026-09-07/evaluacion-codex.md).

Se reprodujo un defecto: después de confirmar una inversión y marcar «No
insistir», repetir la solicitud fallaba como si fuera una inversión nueva.
Se separó la autorización vigente de las condiciones comerciales para escribir:

- una operación ya confirmada devuelve su misma fuente/inversión al actor que
  conserve permiso; no reescribe solicitud, historia, PDF ni Auth;
- una operación nueva o todavía preparada sigue bloqueada por el veto;
- un actor ajeno sigue sin acceso y una misma clave con otro contenido sigue
  produciendo conflicto;
- se vuelve a comprobar el origen de la solicitud después de bloquear su fila.

Pasaron los casos Avance y cooperativa con vendedor y Gerencia, más nueve
oráculos de regresión sobre Portal, veto, responsable, documento, fusión,
concurrencia y estructura. La candidata ahora tiene **34 funciones, 17 nuevas**,
y conserva las cuatro tablas nuevas con RLS y sin acceso directo desde la API.
El informe de Claude revisó la candidata anterior de 33 funciones; no se le
atribuye una revisión de esta corrección posterior.

## Qué sigue para cerrar G4

1. Vinculación histórica canónica: conservar lo resuelto por F2, ensayar faltantes
   y conflictos y preparar el tratamiento acotado tras un recenso actualizado.
2. Cotitularidad neutral, cambios de rol, multirrol, bajas, sin responsable y
   lectores heredados; conservar atribución histórica y permisos actuales.
   Antes de cualquier incorporación al PDF, mostrar texto/ubicación a Miguel
   y obtener su aprobación. No hay una propuesta aplicada ni aprobada.
3. Renovaciones ponderadas, comisión, demos, anulaciones iniciales/Avance y
   carrera entre alta y sello mensual, con Capital e historia intactos.
4. Corrección trazable de términos/datos preparados, validaciones de entradas,
   inventario de puertas, reconstrucción limpia y reversa/restauración integral.

## Evidencia y cierre del bloque

[Checkpoint vigente](../../CRM-Avance-Corp/supabase/scripts/evidencia-f4/2026-09-07-continuacion-pdf-bordes.json),
[checkpoint anterior](../../CRM-Avance-Corp/supabase/scripts/evidencia-f4/2026-09-07-continuacion-pdf-auditoria.json),
[matriz de aceptación](../../CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md)
y [plan HTML para lectura](../../PLAN-MAESTRO-MULTIEMPRESA.html#estado-actual-f4).
El escritor local queda apagado y el servidor temporal de funciones fue detenido.
El banco conserva antecedentes y solicitudes preparados para casos negativos;
no se afirma que todos sus jobs históricos estén terminados.

Se documentó una incidencia de evidencia: el verificador antiguo sobrescribió
su captura de estructura por usar nombre fijo. El checkpoint anterior identifica
la sustitución por una comprobación posterior y mantiene la huella original.
No se reconstruyó ni se atribuyó retrospectivamente la captura perdida.
Las nuevas capturas son únicas y la candidata histórica queda archivada.
Las fuentes y evaluaciones anteriores se archivan con sus huellas antes de
continuar editándolas. Claude no recibió la nueva versión del adaptador/worker;
la corrección y estas verificaciones corresponden a Codex.

## Relacionado

- [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
- [[F4 multiempresa - objetivo de cierre y banco aislado (2026-09-07)]]
- [[F4 multiempresa - construccion y pruebas parciales (2026-09-07)]]
- [[RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07)]]
