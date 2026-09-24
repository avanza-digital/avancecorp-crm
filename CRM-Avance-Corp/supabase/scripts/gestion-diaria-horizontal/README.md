# Banco H3 del supervisor horizontal

Banco local sintético, separado de producción y del banco F4 original.
`banco.mjs` fija contenedor, socket, base y comentario esperado; rechaza otro
destino. Ningún comando acepta URL o proyecto de nube por entorno.

La copia `gestion_diaria_h3_20260923` vive en el contenedor existente
`supabase_db_avancecorp-f5-bank`, puerto local 58322. Fue creada con
`supabase_admin`, propietario postgres, a partir de
`gestion_diaria_f4_vista_chvrqh`. Su comentario es
`BANCO SINTETICO H3 20260923 / sin produccion`.

En esa copia se instalaron los antecedentes ya versionados:
20260921214018, 20260922184459, 20260922185138, 20260922204125,
20260922220800 y 20260923021512. El preflight exige las huellas exactas
anteriores del núcleo y del gate de equipo; no adapta silenciosamente deriva.

Desde `CRM-Avance-Corp`:

```sh
node supabase/scripts/gestion-diaria-horizontal/ensayar.mjs
node supabase/scripts/gestion-diaria-horizontal/contrato-http.mjs
node supabase/scripts/gestion-diaria-horizontal/verificar-tipos.mjs
node supabase/scripts/gestion-diaria-horizontal/rendimiento.mjs
```

- `ensayar`: reversa exacta, instalación, comparación de todo el JSON con el
  núcleo previo en la misma sentencia, precedencia de errores, gerencia/global,
  puente inactivo/ciclo, regresiones F4, 1.008 tareas/11 páginas, referencias,
  errores, permisos, revocación, vacío, concurrencia y mutantes. Fixtures con
  `ROLLBACK`; lecturas como authenticated/anon. Termina con H3 instalada.
- `contrato-http`: crea una segunda copia desechable y un PostgREST 14.5 propio
  en 127.0.0.1:58441, con JWT sintéticos efímeros. Usa el rol authenticator
  existente sin alterar contraseñas/grants. Borra únicamente su contenedor y
  copia al terminar. Prueba 1.008 tareas, roles denegados, anon y revocación.
- `verificar-tipos`: genera desde la base instalada y coteja sólo la RPC H3;
  evita perder otros contratos posteriores que no contiene la copia local.
- `rendimiento`: cinco lecturas bajo authenticated sobre 1.008 tareas, con
  tiempos de la función. No representa latencia de nube ni carga productiva.
- `reversa.sql`: restaura los tres cuerpos anteriores, retira sólo funciones
  H3 y comprueba el gate original. Usar mediante el ejecutor protegido.
- `sellar.mjs`: preparación de una migración nueva sin versionar, dentro de
  rollback. No modificar migraciones comprometidas ni reemplazar sus sellos.

Las pruebas no ejecutan comandos de negocio desde la interfaz. La preparación
SQL desactiva triggers de usuario sólo dentro del fixture local y los restaura.
No son instrucciones para producción. H6 debe integrar Main, ensayar contra su
base vigente, instalar la migración aditiva antes del cliente y verificar ambos.

El catálogo verifica INVOKER, propietario, search_path, cuerpos y ACL; no
reemplaza las lecturas de la matriz RLS. La matriz general remota y advisors
hosted no forman parte de este banco. Véase el acta H3 para límites y resultados.
