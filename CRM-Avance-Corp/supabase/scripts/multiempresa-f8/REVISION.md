# F8 — revisión secundaria y decisión del PRIMARY

Claude actuó como `SECONDARY_REVIEWER` sobre la migración completa después de
la primera prueba local. Dictamen: **CHANGES_REQUESTED**, confianza media. La
primera consulta de arquitectura había terminado sin dictamen y no se contó
como gate aprobado; esta segunda consulta agotó el presupuesto normal de dos.

## Hallazgos aceptados y resueltos

- **P1, quinto integrante futuro:** la activación contaba solo miembros vigentes
  en ese instante. Ahora cuenta todas las filas activas y exige que las cuatro
  estén dentro de la ventana; una quinta fila activa, incluso futura, bloquea.
- **P2, ventana renovable:** ahora la duración total es máximo 30 días, los
  miembros tienen el mismo límite y una ventana activa solo puede acortarse.
- **P2, equipo degradado:** cada llamada exige nuevamente la composición exacta.
  La revocación nominal apaga automáticamente el control; un cambio externo de
  perfil/rol suspende las capacidades para todos.
- **P2, cobertura y doble ruta F4:** se inspeccionaron las nueve llamadas del
  helper. Los triggers y conversiones existentes necesitan mantener el espejo
  relacional también para altas legadas de usuarios ajenos. Se separó esa
  sincronización automática de la autorización interactiva: el espejo acompaña
  a todas las altas mientras el control está vigente, pero
  `private.inversion_persona_autorizada` exige actor piloto y cobertura F5.
  Una prueba rompe la cobertura de forma transaccional y confirma el rechazo.
- **P3, INSERT/isolation:** el bloqueo de banderas cubre INSERT y UPDATE y ambos
  encendidos exigen `READ COMMITTED`.
- **P3, postflight/ACL:** ahora verifica la fila única, todos los ACL de tabla y
  columna, ACL de cada función, propietario/search path y cinco triggers activos.
  El preflight fija también el ACL de las cinco funciones reemplazadas.
- **P3, autor de activación:** la activación y las cuatro membresías requieren
  un perfil responsable explícito.

## Hallazgos evaluados con evidencia

- **Posible inversión de locks:** descartada. `private.cartera_f5_fuentes()` es
  un `SELECT` estable sin locks de banderas; la activación no vuelve desde la
  llave F8 a los advisory locks F3/F4.
- **Edición inocua de motivo bloqueada:** se conserva deliberadamente mientras
  F8 está activo. Reduce las mutaciones permitidas y falla de forma segura.
- **TRUNCATE por propietario:** los roles de Data API carecen de todo ACL. Las
  operaciones administrativas siguen sujetas al procedimiento y a la reversa.

La opinión del reviewer no sustituyó los tests. La candidata corregida volvió a
pasar el banco completo; una nueva revisión de IA no se solicitó para perseguir
un dictamen favorable.
