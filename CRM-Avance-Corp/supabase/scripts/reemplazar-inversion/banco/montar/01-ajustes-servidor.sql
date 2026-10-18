-- Banco reemplazo-inv (copiado de foto-sla-f2) · ajustes del servidor IGUALES a producción (dctqcbznekcyxhjujuci, plan Medium).
-- Valores leídos en producción el 15/10/2026 (pg_settings, solo lectura). Se aplican con ALTER SYSTEM
-- (quedan en postgresql.auto.conf del volumen, con source = "configuration file", como en producción).
-- Requiere reiniciar el contenedor después (shared_buffers, max_connections, etc. son de arranque).
-- Ejecutar como supabase_admin.

-- Memoria
alter system set shared_buffers = '512MB';                 -- prod 131072 x 8kB
alter system set effective_cache_size = '1536MB';           -- prod 393216 x 8kB
alter system set work_mem = '7MB';                       -- prod 7168 kB
alter system set hash_mem_multiplier = 2;                -- prod 2
alter system set maintenance_work_mem = '256MB';         -- prod 262144 kB
alter system set temp_buffers = '8MB';                   -- prod 1024 x 8kB (valor por defecto)
alter system set wal_buffers = '16MB';                   -- prod 2048 x 8kB

-- Conexiones y procesos
alter system set max_connections = 120;
alter system set max_worker_processes = 6;
alter system set max_parallel_workers = 2;
alter system set max_parallel_workers_per_gather = 1;
alter system set max_parallel_maintenance_workers = 1;
alter system set max_replication_slots = 10;
alter system set max_wal_senders = 10;

-- Planificador
alter system set jit = off;
alter system set random_page_cost = 1.1;
alter system set enable_memoize = on;
alter system set effective_io_concurrency = 200;
alter system set default_statistics_target = 100;

-- WAL y checkpoints (no afectan a la memoria, pero son los de producción)
alter system set max_wal_size = '4GB';
alter system set min_wal_size = '1GB';
alter system set checkpoint_completion_target = 0.9;
alter system set checkpoint_flush_after = '256kB';       -- prod 32 x 8kB
alter system set wal_compression = 'zstd';
alter system set max_slot_wal_keep_size = '2GB';
-- Producción archiva el WAL (proceso "archiver"). Aquí se replica el proceso sin enviar nada a ningún sitio.
alter system set archive_mode = on;
alter system set archive_command = '/bin/true';
alter system set archive_timeout = '120s';

-- Tiempos de espera (a nivel servidor; los de cada rol están en pg_db_role_setting)
alter system set statement_timeout = '120s';             -- prod 120000 ms, source "configuration file"

-- Registro (igual que producción, salvo que aquí va a la salida del contenedor: docker logs)
alter system set log_statement = 'ddl';
alter system set log_lock_waits = on;
alter system set log_connections = on;
alter system set auto_explain.log_min_duration = '10s';

-- Varios de producción
alter system set timezone = 'UTC';
alter system set extra_float_digits = 0;
alter system set default_text_search_config = 'pg_catalog.english';
alter system set pg_net.username = 'postgres';
