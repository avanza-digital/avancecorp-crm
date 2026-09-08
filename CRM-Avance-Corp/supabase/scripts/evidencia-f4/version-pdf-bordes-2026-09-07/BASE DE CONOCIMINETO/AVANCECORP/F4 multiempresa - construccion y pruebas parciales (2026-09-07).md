---
tags: [crm, multiempresa, f4, pruebas, retomar]
fecha: 2026-09-07
actualizado: 2026-09-07-pdf-bordes
estado: candidata-local-G4-abierto
---

# F4 — construcción y pruebas parciales

El motor ya tiene una candidata instalada **solo en el banco local**, con
preparación y confirmación transaccional de nuevas inversiones. **F4 todavía
no está lista.** Su objetivo íntegro continúa siendo el de
[[F4 multiempresa - objetivo de cierre y banco aislado (2026-09-07)]].

La continuación vigente está en [[F4 multiempresa - PDF real, recuperacion y auditoria (2026-09-07)]]: PDF real, recuperación,
auditoría adversaria, corrección del reintento confirmado y contenido del contrato protegido.

## Evidencia obtenida

- Avance→Qorilazo, Qorilazo→Prodelco y otra inversión Qorilazo funcionan con el
  mismo lead/persona, depósito, referencia, fechas y comprobante real de prueba.
- Avance crea contratos PEN/USD para el perfil existente, con cuenta, cronograma,
  principal y cotitular documental, snapshot PDF y reserva de generación. Se
  conserva el flujo libre: el catálogo **no se volvió obligatorio**.
- El comprobante se descarga con los mismos bytes; el actor ajeno, Directorio y
  cliente no obtienen acceso a evidencia cooperativa. El cliente sí ve su contrato
  Avance por el Portal y el analista ajeno no lo ve.
- Cuatro carreras se observaron dentro de PostgreSQL antes de soltar sus
  candados: depósito compartido entre empresas/personas, confirmación repetida,
  misma clave con datos distintos y apagado con una confirmación en curso.
- Paridad de seis fuentes anteriores: S/8000, 52 cuotas y reglas de upgrades
  iguales antes/después de instalar. El upgrade elegible posterior aporta 1;
  el del mismo mes y el segundo elegible del mes no añaden aportes.
- Una fecha comercial anterior se imputa en su mes abierto; si el mes ya está
  sellado se conserva esa fecha y se registra un ajuste posterior. Julio se selló
  mediante la RPC vigente y su sello/fotografías permanecen idénticos.
- Anular una inversión cooperativa adicional conserva Capital y su historial
  sin anular el cierre inicial del lead. Un fallo en el cotitular revierte toda
  el alta Avance, incluidas cuenta, cuotas, inversión y reserva PDF.
- El borrado de un contrato vinculado se rechaza antes de reservar la eliminación
  de archivos; tampoco se enlaza una fuente que ya esté en ese proceso.
- Qorilazo→Avance ya crea o recupera un único acceso al Portal y un contrato,
  conservando al responsable aunque registre un supervisor o Gerencia. Pasaron
  cuatro cortes con Auth/SQL reales y el entrypoint Deno por HTTP local.
- Al perder el primer reclamo sin recibir su token, el proceso respeta los diez
  minutos reales de espera y después se recupera sin duplicarse. No se alteró
  la versión, el estado ni el plazo en SQL para acelerar esta prueba.
- No insistir bloquea la inversión entre cuatro pasos del acceso. Solo Gerencia
  puede levantarlo; entonces la misma solicitud continúa sin otro Auth/contrato.
- El cambio de equipo se recupera en cinco momentos del alta. La revisión de la
  misma solicitud conserva sus datos, huella y proceso Auth. El nuevo responsable
  también recuperó sin el token anterior, después de la espera original real.
- El bloqueo real de un perfil revierte la revisión completa; al liberarlo se
  repite sin duplicados. Las revisiones son inmutables y su excepción para alinear
  el asesor no se reutiliza desde otra transacción ni permite cambiar otros campos.
- Siete momentos de corrección documental pasaron, incluida DNI→CE. La corrección
  publicada exige completar el Auth pendiente antes de corregir; la misma inversión
  continúa después. No cambia automáticamente la clave, según lo decidido el 06/09
  en [[RETOMAR-60 - F2.b E3 (b5) construida y ensayada, pendiente del ! (2026-09-05)]].
- La fusión canónica pasó en cinco recorridos Avance y tres cooperativos. La
  solicitud conserva su origen y contenido; fuentes y titulares quedan en la
  identidad vigente. El equipo anterior pierde acceso a las puertas F4 y al
  comprobante, que conserva su ruta y bytes originales.
- Dos fusiones sucesivas conservan el acceso creado en la identidad intermedia.
  También se recuperó un contexto Auth del formato anterior real del banco.
- Cuatro carreras entre corrección/fusión y confirmación se observaron en
  PostgreSQL, en ambos órdenes. Se respetan revisión, rechazo por cambio de
  identidad y previsualización caducada; la recuperación termina con una inversión.
  La corrección seguida de fusión también conserva el Auth y usa el documento actual.

Después del bloque PDF y la auditoría se verificaron los 34 cuerpos de funciones
de la candidata, propietarios, ejecución de las 17 funciones nuevas y ACL/RLS
de las cuatro tablas nuevas. La relectura confirmada tras veto pasó en Avance
y cooperativa, seguida de nueve oráculos de regresión satisfactorios.
Los diagnósticos posteriores a Auth, revisión y fusión conservan las seis
advertencias del esquema anterior, sin advertencias nuevas en esos resultados.
Esto es evidencia acotada, no una auditoría que cierre todos los requisitos.

## Siguiente bloque obligatorio

Los bordes técnicos PDF ya pasaron: 10 grupos nuevos/ocho contratos, regresión
de 12 grupos/10 contratos y 42 pruebas del handler/Storage. La revisión visual
previa cubre 14 páginas. Los dos antecedentes sin job conservan su régimen, sin
generarles un documento nuevo. Contenido intacto; cualquier incorporación de
cotitulares exige texto/ubicación y aprobación previa de Miguel.

1. Ensayar la vinculación histórica por el proceso canónico F2: preservar enlaces
   resueltos, clasificar faltantes/conflictos y preparar el tratamiento acotado
   del faltante productivo observado en [[F4 multiempresa - reglas vigentes y punto de partida (2026-09-07)]].
2. Completar cambio de rol, multirrol, sin responsable y lectores heredados que
   aún autorizan por atribución histórica. Ampliar cotitularidad neutral y su
   corrección/fusión; corregir términos del payload requiere su propio tratamiento.
3. Completar renovaciones ponderadas, comisión, atribución reasignada, anulaciones
   iniciales/Avance y carreras de cierre de mes; conservar los núcleos vigentes.
4. Ensayar la candidata completa desde una base reconstruida y su reversa antes
   del cierre técnico. Producción continúa fuera de esta prueba.

El desglose por requisito, pruebas y límites está en
`CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md`.
Los comandos están en `scripts/f4/README.md` y los resultados en
`supabase/scripts/evidencia-f4/`. No contiene claves ni documentos reales.

El escritor local queda apagado al terminar esta tanda y se detuvo el servidor
temporal de funciones. No se publicó SQL, edge ni encendido en producción.

## Relacionado

- [[RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07)]]
- [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
- [[F4 multiempresa - objetivo de cierre y banco aislado (2026-09-07)]]
- [[F4 multiempresa - reglas vigentes y punto de partida (2026-09-07)]]
