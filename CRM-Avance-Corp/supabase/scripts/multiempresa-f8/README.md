# F8 multiempresa — piloto económico controlado

Estado al 13/09/2026: **candidata preparada y probada en el banco local y en
una rama Supabase aislada; no instalada ni activada en producción**. G6 está
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

El control exige F3 encendida, F4–F7 globales apagadas, ventana vigente de
máximo 30 días, equipo exacto y cobertura completa de la Ficha 360. Si cambia
la membresía CRM o vence la ventana, el usuario deja de obtener la capacidad.

## Punto de partida real

Lectura administrativa, sin PII, del 13/09/2026 a las 17:09 Lima:

- F3 ON; F4/F5/F6/F7 OFF.
- Equipo disponible: 2 Gerencia, 3 supervisores y 18 vendedores activos.
- 598 fuentes totales: 593 reales y 5 demo.
- 14 fuentes bloquean hoy la cobertura exacta de F5/F8: **10 reales y 4 demo**.
- Identidades coherentes conocidas: Avance 425, Qorilazo 16 y Prodelco 4.
- Cero personas multiempresa conocidas y 14 inversiones relacionales F4.

Los diez casos reales son los revisados comercialmente durante G6. Esa
conformidad no decide por sí sola la ficha canónica; faltan los enlaces técnicos.
Las cuatro fuentes demo también deben quedar coherentes porque F8 conserva sin
rebajas el gate completo de F5. Prodelco necesita al menos una quinta identidad
real durante el piloto y los seis recorridos multiempresa deben ejecutarse; no
se fabrican para adelantar G7.

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

La prueba recrea el destino desde el banco sintético F7, instala el archivo
exacto y comprueba: instalación OFF, RLS/ACL, equipo inválido, usuario ajeno,
perfil inactivo, revocación nominal, cobertura rota, sincronización sin ampliar
permisos, vencimiento automático, exclusión del
rollout global, cinco carreras de encendido y reversa sin diferencias en siete
superficies de datos.
Estas carreras prueban el control F8; las cinco carreras económicas y los diez
reintentos idempotentes exigidos por G7 se ejecutan después en la rama aislada.
[Verificación local](VERIFICACION-LOCAL-2026-09-13.md) y
[verificación remota](VERIFICACION-RAMA-2026-09-13.md), junto con las
[decisiones de la revisión independiente](REVISION.md).

La rama remota ejecutó las mismas 11 pruebas, incluidos cinco encendidos
concurrentes, y conservó las seis huellas económicas medidas. RLS, ACL y los
tipos de las dos tablas F8 coincidieron con la candidata. Supabase no pudo
reconstruir automáticamente el historial posterior al 11/08 porque una
migración histórica exige datos que las ramas no copian. Por eso el ensayo usó
el banco sintético y **no produjo una rama mergeable**.

El acceso temporal de la CLI que apareció en la salida del ensayo fue retirado
y verificado, con el servicio saludable. La contraseña principal y las claves
API se conservaron. [Corrección del aviso y cierre](CIERRE-CREDENCIAL-CLI-2026-09-13.md).

## Secuencia pendiente antes de iniciar el piloto

1. Resolver con evidencia los 14 enlaces que bloquean la cobertura, sin unir
   personas por nombre, teléfono o correo.
2. Elegir nominalmente un representante de Gerencia, un supervisor y dos
   vendedores. No se versionan nombres ni UUID reales en Git.
3. Resolver la deuda del historial de ramas o preparar un mecanismo compatible
   con el ciclo obligatorio; el ensayo remoto aislado ya pasó, pero la rama no
   fue mergeable.
4. Con autorización concreta, integrar e instalar OFF, verificar producción y
   publicar desde el mismo commit de `avancecorp/main`.
5. Cargar las cuatro membresías con vencimiento, comprobar soporte/reversa y
   pedir la autorización concreta para encender el piloto.
6. Ejecutar los casos reales y completar [ACTA-G7.md](ACTA-G7.md). No hay una
   espera de cinco días: G7 cierra al cumplir toda la evidencia.

La preparación no autoriza un backfill ni una inversión real. La activación se
hará con el equipo y el SQL de configuración exactos, revisables antes del paso.
