---
tags: [crm, multiempresa, f4, aceptacion, banco]
fecha: 2026-09-07
estado: motor-en-construccion-pruebas-parciales
---

# F4 — objetivo para darla por lista

F4 estará lista cuando el sistema permita registrar nuevas inversiones en
Avance, Qorilazo y Prodelco para una persona ya identificada, reutilizando su
identidad y su lead existente, conservando su historial y aplicando las reglas
comerciales vigentes.

## Evidencia exigida para cerrar G4

- Avance → Qorilazo, Qorilazo → Prodelco y Qorilazo → Avance funcionan sin
  duplicar persona, lead ni acceso al Portal.
- La persona puede invertir nuevamente en la misma empresa.
- Cada inversión conserva empresa, moneda, monto, fechas, documentos,
  titularidad y atribución. La relación neutral no copia el dinero de su fuente.
- Avance reutiliza contratos, cronogramas y acceso autorizado al Portal;
  cooperativas conservan depósito, referencia, vencimiento y evidencia.
- Los antecedentes se vinculan sin volver a crear los enlaces resueltos en F2.
- Se respetan rol, ámbito, responsable vigente, documento y veto. Una solicitud
  repetida devuelve el mismo resultado; la misma clave con datos distintos
  produce conflicto sin efectos. Dos solicitudes simultáneas del mismo depósito
  no crean dos operaciones.
- Los fallos permiten recuperar el proceso sin duplicados ni registros finales
  incompletos; también se demuestra cómo detener nuevas confirmaciones.
- Capital, comisión y conversión conservan sus reglas existentes. Esto incluye
  renovaciones ponderadas, upgrades elegibles en un mes comercial posterior,
  primera operación de cartera elegible por cliente/mes y anulaciones según ATR-4.
- Las fechas comerciales anteriores al registro y el tratamiento de meses
  sellados cumplen la decisión ya documentada; no se reescriben meses cerrados.

El cierre exige pruebas satisfactorias en un entorno separado, con datos
sintéticos y recuperación comprobada. G4 no autoriza el circuito con dinero
real: la conciliación corresponde a F7/G6 y el piloto a F8/G7.

## Preparación técnica completada en esta continuación

Se preparó un banco Supabase local independiente de producción y de `banco-f7`:

- proyecto Docker `avancecorp-f4-bank`, API `127.0.0.1:56321`, Postgres `56322`;
- PostgreSQL 17.6, esquema extraído en **solo lectura y sin datos** de producción;
- 29 funciones comparadas contra la captura productiva, todas con la misma huella;
- 7 usuarios ficticios creados con la API real de Auth, dos equipos comerciales
  y una identidad de cliente de prueba;
- inicio de sesión y RPC CRM comprobados por HTTP con JWT del usuario ficticio;
- semilla reejecutada sin recrear filas;
- cero contratos, cierres externos o inversiones en el momento de esta captura.

La red Docker es la local estándar. El banco está separado por proyecto, datos,
puertos y credenciales; no se afirma que esté aislado de Internet. No contiene
credenciales de producción ni se cargaron usuarios, depósitos o contratos reales.

Evidencia sin claves ni documentos:
`CRM-Avance-Corp/supabase/scripts/evidencia-f4/2026-09-07-banco-local.json`.
Utilidades reproducibles de preparación, acceso al banco y captura:
`CRM-Avance-Corp/supabase/scripts/f4/`.

## Estado y siguiente paso

**F4 está en construcción y G4 sigue abierto.** El 07/09 se instaló una candidata
en el banco local y se probaron los recorridos cooperativos, nuevas inversiones
Avance con perfil existente, reintentos, cuatro carreras observadas, fechas,
anulación adicional y protección del historial. No se publicaron migraciones ni
se encendió `inversiones_escritura` en producción.

La evidencia y el siguiente bloque están en
[[F4 multiempresa - construccion y pruebas parciales (2026-09-07)]]. Ya se ensayó
recuperación tras reasignación, corrección documental y fusión, incluidas carreras
reales con confirmación, dos fusiones sucesivas y un contexto Auth anterior.
La corrección/fusión conserva el bloqueo de F3 durante Auth: primero se recupera
el acceso y después Gerencia realiza el cambio. La generación y recuperación
PDF pasaron en 12 grupos/10 contratos y se ampliaron con 10 grupos/ocho contratos
de bordes técnicos; 42 pruebas del handler/Storage conformes. Contenido intacto
y aprobación previa exigida por Miguel para cualquier incorporación de cotitulares.
Quedan vinculación histórica canónica, lectores/permisos heredados,
cotitularidad neutral completa, renovaciones/comisión y reversa completa.
Qorilazo→Avance también pasó con respuesta inicial perdida, espera real del plazo
y No insistir entre pasos; el detalle actualizado está en la nota de construcción.
La auditoría adversaria se contrastó con el banco y permitió corregir el reintento
de inversiones confirmadas tras veto. Detalle: [[F4 multiempresa - PDF real, recuperacion y auditoria (2026-09-07)]].
Las pruebas parciales no sustituyen esos requisitos.

## Relacionado

- [[F4 multiempresa - reglas vigentes y punto de partida (2026-09-07)]]
- [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
- [[RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07)]]
- [[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]]
