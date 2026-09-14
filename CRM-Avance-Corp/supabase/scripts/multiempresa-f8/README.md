# F8 multiempresa — piloto económico controlado

Estado al 13/09/2026: **control probado en banco y rama; corrección demo probada
localmente; no instalados ni activados en producción**. G6 está
cerrado. F8 y G7 siguen abiertos hasta completar casos reales, conciliaciones y
firmas.

F8 habilita las capacidades ya publicadas de F4, F5 y F6 exclusivamente para
un equipo nominal de cuatro personas: Gerencia, un supervisor y dos vendedores.
Las banderas globales F4–F7 permanecen apagadas y el alcance de cartera de cada
rol sigue siendo el que ya aplica el CRM. Las comisiones se calculan fuera del
sistema.

## Qué añade

- [Migración candidata](../../migrations/20260913215240_crm_f8_piloto_controlado.sql):
  control temporal del piloto y cuatro membresías nominales, ambas tablas RLS
  y sin acceso por Data API; nace apagada y sin miembros.
- Revalidación de perfil activo, membresía CRM activa y rol esperado en cada
  llamada. No confía en metadatos JWT para decidir el equipo.
- F4/F5/F6 solo se abren para un miembro vigente. F7 queda apagada y la
  conciliación del piloto se obtiene administrativamente.
- Las altas económicas legadas de usuarios ajenos mantienen automáticamente el
  espejo relacional mientras el control está vigente, sin obtener la pantalla ni
  la operación F4 nueva. Así una venta normal no vuelve parcial la Ficha 360.
- Bloqueo transaccional que impide tener F8 y el rollout global activos a la
  vez, incluso con cambios concurrentes.
- [Reversa operativa](reversa-operativa.sql) que apaga el control y desactiva
  membresías sin borrar inversiones, postventa, auditoría ni historia.
- [Corrección demo y SQL revisable](demos/README.md): excluye las fuentes de prueba
  de la cobertura y los lectores operativos, conserva historia y bloquea cualquier
  hueco real. Nueva migración posterior al control, ensayada solo localmente.

El control exige F3 encendida, F4–F7 globales apagadas, ventana vigente de
máximo 30 días, equipo exacto y cobertura completa de la Ficha 360. Si cambia
la membresía CRM o vence la ventana, el usuario deja de obtener la capacidad.

## Punto de partida real

Lectura administrativa, sin PII, del 13/09/2026 a las 17:09 Lima:

- F3 ON; F4/F5/F6/F7 OFF.
- Equipo disponible: 2 Gerencia, 3 supervisores y 18 vendedores activos.
- 598 fuentes totales: 593 reales y 5 demo.
- En ese corte, 14 fuentes bloqueaban la cobertura F5/F8: **10 reales y 4 demo**.
- Identidades coherentes conocidas: Avance 425, Qorilazo 16 y Prodelco 4.
- Cero personas multiempresa conocidas y 14 inversiones relacionales F4.

Los diez casos reales son los revisados comercialmente durante G6. Esa
conformidad no decidía por sí sola la ficha canónica; los enlaces técnicos
requirieron el diagnóstico y la aprobación específicos completados después.
La [revisión dirigida de identidades](REVISION-IDENTIDADES-2026-09-13.md),
completada a las 20:02 Lima, clasificó los catorce movimientos: ocho reales
posteriores a la carga F2, dos de una misma ficha multirrol y cuatro demo.
Los diez reales corresponden a siete fichas. No hay un identificador existente
coincidente que permita elegir automáticamente otra identidad.

Miguel confirmó la correspondencia multirrol y aprobó el SQL exacto. Los diez
enlaces reales están [aplicados y verificados](identidades/APLICACION-2026-09-13.md):
la lectura de las 21:29 Lima encontró cero huecos reales y cuatro demo,
conservando las 598 fuentes, los hechos económicos, las cuentas y las banderas.

El gate instalado todavía exige coherencia a las cuatro fuentes demo. La
[corrección preparada](demos/README.md) alinea cartera, ficha, documentos,
postventa y cobertura con las fuentes reales. Pasó 20 pruebas específicas y las
11 del control F8 en el banco; falta aprobar su SQL, ensayarlo en el ciclo remoto
e instalarlo. Los diez bloqueos reales sí están resueltos en producción.
Prodelco necesita al menos una quinta
identidad real durante el piloto y los seis recorridos multiempresa deben
ejecutarse con evidencia.

## Verificación local

El banco está cerrado por código al contenedor
`supabase_db_avancecorp-f5-bank`, fuente `multiempresa_f7_20260911` y destino
descartable `multiempresa_f8_20260913`. No acepta URL ni base del llamador y no
descarga producción.

Desde `CRM-Avance-Corp`:

```sh
npm run check:multiempresa:f8
npm run test:multiempresa:f8
```

Las pruebas recrean secuencialmente el destino desde el banco sintético F7,
instalan las dos migraciones exactas y comprueban: instalación OFF, RLS/ACL, equipo inválido, usuario ajeno,
perfil inactivo, revocación nominal, cobertura rota, sincronización sin ampliar
permisos, vencimiento automático, exclusión del
rollout global, cinco carreras de encendido y reversa sin diferencias en siete
superficies de datos.
Estas carreras prueban el control F8; las cinco carreras económicas y los diez
reintentos idempotentes exigidos por G7 se ejecutan después en la rama aislada.
[Verificación local](VERIFICACION-LOCAL-2026-09-13.md) y
[verificación remota](VERIFICACION-RAMA-2026-09-13.md), junto con las
[decisiones de la revisión independiente](REVISION.md).

La rama remota anterior ejecutó las 11 pruebas del control original, incluidos cinco encendidos
concurrentes, y conservó las seis huellas económicas medidas. RLS, ACL y los
tipos de las dos tablas F8 coincidieron con esa candidata; no incluye la nueva
corrección demo. Supabase no pudo
reconstruir automáticamente el historial posterior al 11/08 porque una
migración histórica exige datos que las ramas no copian. Por eso el ensayo usó
el banco sintético y **no produjo una rama mergeable**.

El acceso temporal de la CLI que apareció en la salida del ensayo fue retirado
y verificado, con el servicio saludable. La contraseña principal y las claves
API se conservaron. [Corrección del aviso y cierre](CIERRE-CREDENCIAL-CLI-2026-09-13.md).

## Secuencia pendiente antes de iniciar el piloto

1. Aprobar el [SQL de exclusión demo](demos/README.md), ya implementado y ensayado
   localmente; verificarlo en el ciclo de rama antes de instalar OFF.
   El lote de los diez movimientos reales ya fue aprobado, aplicado y verificado.
2. Elegir nominalmente un representante de Gerencia, un supervisor y dos
   vendedores. No se versionan nombres ni UUID reales en Git.
3. Resolver la deuda del historial de ramas o preparar un mecanismo compatible
   con el ciclo obligatorio; el ensayo remoto aislado ya pasó, pero la rama no
   fue mergeable. [Paquete y procedimiento de instalación](INSTALACION-2026-09-13.md)
   preparados: reconstrucción de estructura y paridad de historial/Edge en una
   rama exclusiva; todavía no ejecutados para este paquete.
4. Con autorización concreta, integrar e instalar OFF, verificar producción y
   publicar desde el mismo commit de `avancecorp/main`.
5. Cargar las cuatro membresías con vencimiento, comprobar soporte/reversa y
   pedir la autorización concreta para encender el piloto.
6. Ejecutar los casos reales y completar [ACTA-G7.md](ACTA-G7.md). No hay una
   espera de cinco días: G7 cierra al cumplir toda la evidencia.

La preparación no autoriza un backfill ni una inversión real. La activación se
hará con el equipo y el SQL de configuración exactos, revisables antes del paso.
