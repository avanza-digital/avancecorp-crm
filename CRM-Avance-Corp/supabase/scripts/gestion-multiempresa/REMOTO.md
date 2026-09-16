# Ensayo remoto e instalación — 16/09/2026

Miguel autorizó el SQL `20260916152851` y un banco de Supabase hasta US$0,10.
La publicación web tiene la autorización independiente de `$release-crm`.
[Recibo productivo, hashes y coste](PRODUCCION.json).

## Banco y evidencia

La rama propia `gestion-multiempresa-20260916` se creó en PortalAvanceCorp.
El replay histórico falla por depender de datos ausentes. Se reconstruyeron
solo los esquemas vigentes `public,crm,private`, con comentarios, permisos,
rol privado y trigger diferido de correo Auth. Las 653 funciones coincidieron
exactamente en cuerpo, owner, ACL y search_path. No se copiaron clientes reales.
Se cargaron configuración sin personas y los 13 usuarios ficticios del seed.

El historial de la rama se alineó con las 300 migraciones productivas: misma
huella `755b4bfc5db1b04a81b3816901b529a2`. Se completaron las columnas y la
restricción única de idempotencia que faltaban en el historial antiguo de la
rama. Un primer intento había confirmado el DDL pero fallado al registrar la
migración; se reconstruyó la copia de ensayo antes de instalar y registrar la
candidata de forma limpia. Producción permaneció intacta durante esos pasos.

- **PASS:** matriz global, 1.866 aserciones, exit 0. [Salida](RLS-REMOTO.txt).
- **PASS:** 24 grupos con Auth, HTTP y SQL reales. [Recibo](HTTP-REMOTO.json).
- **PASS:** la tabla queda sin grants API, con RLS; el helper es privado.
- **PASS:** 651 funciones anteriores intactas, dos adaptadas como se aprobó y
  cuatro nuevas. Las 657 definiciones finales coinciden entre banco y producción.
- **NOT RUN:** candado de metas retroactivas: el banco no tiene meses cerrados.

El primer ensayo de los 24 grupos eligió por UUID una fuente con lead activo,
pero el caso pretendía comprobar un lead archivado. Había cinco fuentes
archivadas y dos activas elegibles. Se corrigió exclusivamente el selector para
exigir el estado histórico que se mide y se repitieron los 24 grupos completos.
[Salida original conservada](HTTP-REMOTO-SELECTOR-INICIAL.txt). No se alteró el
SQL ni se redujo ninguna expectativa para obtener PASS.

## Promoción y comprobaciones

`merge_branch` promovió únicamente la migración nueva `20260916174727`.
SHA-256 del archivo aprobado y ensayado:
`e2ebc90220da5b671d873a3e5899f6f09f981becad6b1beb0dc7c7a78d7ca361`.
El servicio registra 27 sentencias separadas en producción. Cada una se cotejó
literalmente y en orden con el archivo: solo cambian espacios/separadores entre
sentencias en el registro; por eso su hash concatenado es distinto.

Se conservaron las huellas completas de contratos, titulares, cronogramas,
documentos, perfiles, inversiones, identidades, cierres, gestiones, equipo,
auditoría de eliminaciones, banderas y miembros/control F8. También los permisos
y policies existentes y las 300 entradas previas del historial. Cero contactos
nuevos al instalar: no hubo backfill ni correcciones de personas productivas.

La [sonda de lectura](sonda-lectura.sql) pasó para 23 cuentas activas: 2 Gerencia,
3 supervisores y 18 vendedores; 63 contextos de persona, 36 contratos Avance y
23 fuentes COOPAC. Usa claims y rol SQL `authenticated` con ROLLBACK; no representa
navegación humana ni escrituras de negocio. Los resultados no exponen PII.

La promoción de Supabase también republicó las Edge existentes. Se descargaron
las fuentes completas de ambos proyectos: **20 funciones, 48 archivos idénticos
byte a byte**, permisos/estado/verify_jwt conservados. Las versiones y huellas
del paquete recompuesto cambiaron; no se confunden con cambios de fuente.
[Comparación y hashes](EDGE-PARIDAD.json).

## Advisors revisados

Seguridad: 272 → 276. Los cuatro avisos añadidos corresponden a las decisiones
revisadas y probadas de esta migración:

- [RLS sin policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy): la tabla de contacto es intencionalmente cerrada y sin grants API.
- [Tres RPC SECURITY DEFINER para authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable): acceso intencional por puertas con rol, ámbito, ventana, candados, versión e idempotencia; nunca acceso directo a la tabla.

Rendimiento: 114 → 115. Se añade un [aviso informativo de FK sin índice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys)
sobre `actualizado_por`. Las lecturas/escrituras del módulo acceden por la clave
primaria de persona, no por ese autor. Se registra como optimización futura ante
borrados/cambios masivos de perfiles; no se amplía el SQL exacto autorizado.
Los avisos heredados de Auth y otros módulos se conservan, sin atribuirles PASS.

## Cierre

La rama propia se eliminó y se verificó su ausencia. La rama F7 ajena permaneció
intacta. El recibo documenta el coste estimado por tiempo y tarifa, inferior a
US$0,10; no es una factura. Las credenciales privadas del banco no se versionan.

El frontend se publica desde un commit limpio de Main igual a `avancecorp/main`.
La versión web publicada y su smoke PASS constan en
[PUBLICACION.json](PUBLICACION.json). Se conserva el ZIP publicado anterior para recuperación.
