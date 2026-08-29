# Biblioteca del runner hermetico C0.1. Se carga unicamente desde el snapshot
# privado que crea run-test-c0-1-local.sh; no admite una conexion independiente.

c01_capture_candidate_state() {
  local destination="$1"
  local placeholder=""
  local signature=""
  local state=""
  : > "$destination"
  while IFS=$'\t' read -r placeholder signature; do
    [[ -n "$placeholder" && -n "$signature" ]] || continue
    state="$($PSQL -X -qAt \
      -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
      -c "select pg_catalog.md5(p.prosrc) || E'\\t' || coalesce(p.proacl::text, '<NULL>') from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('$signature')")"
    if [[ ! "$state" =~ ^[0-9a-f]{32}$'\t' ]]; then
      fail "estado de cuerpo/ACL ilegible para $signature"
    fi
    printf '%s\t%s\n' "$signature" "$state" >> "$destination"
  done < "$CANDIDATE_FILE"
  if [[ "$(wc -l < "$destination" | tr -d ' ')" -ne 2 ]]; then
    fail 'no se capturaron exactamente los dos cuerpos candidatos.'
  fi
}

c01_verify_candidate_hashes() {
  local state_file="$1"
  local placeholder=""
  local signature=""
  local expected_hash=""
  local current_hash=""
  while IFS=$'\t' read -r placeholder signature; do
    [[ -n "$placeholder" && -n "$signature" ]] || continue
    expected_hash="$(awk -F $'\t' -v buscado="$signature" \
      '$1 == buscado { print $2 }' "$CANDIDATE_BEFORE")"
    current_hash="$(awk -F $'\t' -v buscado="$signature" \
      '$1 == buscado { print $2 }' "$state_file")"
    if [[ ! "$expected_hash" =~ ^[0-9a-f]{32}$ \
       || "$current_hash" != "$expected_hash" ]]; then
      fail "el cuerpo canonico no se restauro antes del mutante: $signature"
    fi
  done < "$CANDIDATE_FILE"
}

c01_assert_fresh_candidate_state() {
  local current_state="$RUN_DIR/candidatos-estado-actual.tsv"
  c01_capture_candidate_state "$current_state"
  c01_verify_candidate_hashes "$current_state"
  if ! cmp -s "$BASELINE_TARGET_STATE" "$current_state"; then
    fail 'cuerpo o ACL de un candidato no coincide con la baseline restaurada.'
  fi
}

c01_reset_database_from_baseline() {
  if ! "$DROPDB" -h "$SOCKET_DIR" -p "$PORT" -U postgres \
    "$DB_NAME" >"$RUN_DIR/reset-drop.log" 2>&1; then
    sed -n '1,300p' "$RUN_DIR/reset-drop.log" >&2
    fail "no se pudo borrar la base exacta antes del mutante: $DB_NAME"
  fi
  DB_CREATED=false
  if ! "$CREATEDB" -h "$SOCKET_DIR" -p "$PORT" -U postgres \
    --owner=postgres --template=template0 --encoding=UTF8 "$DB_NAME" \
    >"$RUN_DIR/reset-create.log" 2>&1; then
    sed -n '1,300p' "$RUN_DIR/reset-create.log" >&2
    fail "no se pudo recrear la base exacta para el mutante: $DB_NAME"
  fi
  DB_CREATED=true
  if ! "$PG_RESTORE" --exit-on-error --single-transaction \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    "$BASELINE_DUMP" >"$RUN_DIR/reset-restore.log" 2>&1; then
    sed -n '1,700p' "$RUN_DIR/reset-restore.log" >&2
    fail 'no se pudo restaurar la baseline en la base nueva del mutante.'
  fi
  c01_assert_fresh_candidate_state
}

c01_assert_expected_mutant_failure() {
  local log_file="$1"
  local mutant_id="$2"
  local expected_state="$3"
  local expected_oracle="$4"
  local phase="$5"
  local error_count=""
  error_count="$(grep -Ec 'ERROR:  [A-Z0-9]{5}:' "$log_file" || true)"
  if [[ "$error_count" -ne 1 ]] \
     || ! grep -Fq "ERROR:  $expected_state: $expected_oracle" "$log_file"; then
    sed -n '1,1200p' "$log_file" >&2
    fail "mutante $mutant_id murio fuera del oraculo esperado ($phase/$expected_state/$expected_oracle)."
  fi
  if grep -Eiq \
    'syntax error|permission denied|BANCO C0\.1 requiere|BANCO C0\.1 vacuo|Mutante C0\.1 desconocido|does not exist|no existe' \
    "$log_file"; then
    sed -n '1,1200p' "$log_file" >&2
    fail "mutante $mutant_id murio por sintaxis, fixture o permiso."
  fi
  if grep -q '^C0\.1_BANCO_ADVERSARIO_OK$' "$log_file"; then
    sed -n '1,1200p' "$log_file" >&2
    fail "mutante $mutant_id emitio un OK incompatible con su oraculo."
  fi
}

c01_prepare_mutant_baseline() {
  local restore_log="$RUN_DIR/restaurar-candidatos.log"
  PG_DUMP="$PG_BIN/pg_dump"
  PG_RESTORE="$PG_BIN/pg_restore"
  if [[ ! -x "$PG_DUMP" || ! -x "$PG_RESTORE" ]]; then
    fail 'la matriz de mutantes requiere pg_dump y pg_restore de PostgreSQL 17.'
  fi

  if ! $PSQL -X -v ON_ERROR_STOP=1 -q \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -f "$BASELINE_CANDIDATE_DDL" >"$restore_log" 2>&1; then
    sed -n '1,500p' "$restore_log" >&2
    fail 'no se pudieron restaurar los dos cuerpos canonicos tras el caso real.'
  fi
  if ! $PSQL -X -v ON_ERROR_STOP=1 -q \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    >>"$restore_log" 2>&1 <<'SQL'
revoke all on function private.metricas_cartera_por_vendedor(date)
  from public, anon, authenticated, service_role;
revoke all on function crm.metricas_vendedores_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_vendedores_fn() to authenticated;
SQL
  then
    sed -n '1,500p' "$restore_log" >&2
    fail 'no se pudo restaurar la ACL exacta de los dos cuerpos canonicos.'
  fi

  BASELINE_TARGET_STATE="$RUN_DIR/candidatos-baseline-estado.tsv"
  c01_capture_candidate_state "$BASELINE_TARGET_STATE"
  c01_verify_candidate_hashes "$BASELINE_TARGET_STATE"

  BASELINE_DUMP="$RUN_DIR/baseline-canonica.dump"
  if ! "$PG_DUMP" -Fc \
    -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
    -f "$BASELINE_DUMP" >"$RUN_DIR/pg-dump.log" 2>&1; then
    sed -n '1,500p' "$RUN_DIR/pg-dump.log" >&2
    fail 'no se pudo fijar la baseline canonica para los mutantes.'
  fi
  if [[ ! -s "$BASELINE_DUMP" ]]; then
    fail 'el dump de baseline canonica quedo vacio.'
  fi
}

run_c01_body_mutants() {
  local mutants_dir="$RUN_DIR/mutantes"
  local manifest="$RUN_DIR/mutantes.tsv"
  local matrix="$RUN_DIR/mutantes-resultados.tsv"
  local mutant_id=""
  local mutant_slug=""
  local mutant_signature=""
  local expected_phase=""
  local expected_state=""
  local expected_oracle=""
  local mutant_token=""
  local mutation_count=""
  local token_count=""
  local original_body_sha=""
  local mutant_body_sha=""
  local mutant_prefix=""
  local mutant_template=""
  local mutant_ddl=""
  local mutant_sql=""
  local calibration_sql=""
  local calibration_log=""
  local application_sql=""
  local application_log=""
  local bank_sql=""
  local bank_log=""
  local mutant_hash=""
  local installed_mutant_hash=""
  local application_status=0
  local bank_status=0
  local ok_count=""
  local unique_count=""

  c01_prepare_mutant_baseline

  if ! node "$MUTATOR_SNAPSHOT" generate \
    "$MATERIALIZED_PROPOSAL" "$CANDIDATE_FILE" "$REPLACEMENTS_FILE" \
    "$mutants_dir" "$manifest" >"$RUN_DIR/mutantes-generar.log" 2>&1; then
    sed -n '1,700p' "$RUN_DIR/mutantes-generar.log" >&2
    fail 'la generacion exacta de los 17 mutantes fallo.'
  fi
  if [[ "$(wc -l < "$manifest" | tr -d ' ')" -ne 17 ]]; then
    fail 'el generador no materializo exactamente 17 casos identificables.'
  fi

  : > "$matrix"
  while IFS=$'\t' read -r \
    mutant_id mutant_slug mutant_signature expected_phase expected_state \
    expected_oracle mutant_token mutation_count token_count \
    original_body_sha mutant_body_sha
  do
    [[ -n "$mutant_id" ]] || continue
    if [[ ! "$mutant_id" =~ ^[0-9]{2}$ \
       || ! "$mutant_slug" =~ ^[a-z0-9_]+$ \
       || ( "$expected_phase" != proposal && "$expected_phase" != bank ) \
       || "$expected_state" != P0001 \
       || ! "$mutation_count" =~ ^[1-9][0-9]*$ \
       || ! "$token_count" =~ ^[2-9][0-9]*$ \
       || ! "$original_body_sha" =~ ^[0-9a-f]{64}$ \
       || ! "$mutant_body_sha" =~ ^[0-9a-f]{64}$ \
       || "$original_body_sha" == "$mutant_body_sha" ]]; then
      fail "manifest invalido para mutante $mutant_id-$mutant_slug"
    fi

    c01_reset_database_from_baseline

    mutant_prefix="$mutant_id-$mutant_slug"
    mutant_template="$mutants_dir/$mutant_prefix.template.sql"
    mutant_ddl="$mutants_dir/$mutant_prefix.ddl.sql"
    mutant_sql="$mutants_dir/$mutant_prefix.sql"
    calibration_sql="$mutants_dir/$mutant_prefix.calibrar.sql"
    calibration_log="$mutants_dir/$mutant_prefix.calibrar.log"
    application_sql="$mutants_dir/$mutant_prefix.aplicar.sql"
    application_log="$mutants_dir/$mutant_prefix.aplicar.log"
    bank_sql="$mutants_dir/$mutant_prefix.banco.sql"
    bank_log="$mutants_dir/$mutant_prefix.banco.log"

    {
      printf '%s\n' '\set ON_ERROR_STOP on' '\set VERBOSITY verbose' 'begin;'
      printf '\\i %s\n' "$mutant_ddl"
      printf "select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('%s');\n" \
        "$mutant_signature"
      printf '%s\n' 'rollback;'
    } > "$calibration_sql"
    if ! $PSQL -X -qAt -v ON_ERROR_STOP=1 \
      -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
      -f "$calibration_sql" >"$calibration_log" 2>&1; then
      sed -n '1,900p' "$calibration_log" >&2
      fail "mutante $mutant_prefix no compilo en calibracion transaccional."
    fi
    mutant_hash="$(grep -E '^[0-9a-f]{32}$' "$calibration_log" || true)"
    if [[ ! "$mutant_hash" =~ ^[0-9a-f]{32}$ ]]; then
      sed -n '1,900p' "$calibration_log" >&2
      fail "mutante $mutant_prefix no produjo un unico md5(prosrc) calibrado."
    fi
    c01_assert_fresh_candidate_state

    if ! node "$MUTATOR_SNAPSHOT" materialize \
      "$mutant_template" "$mutant_token" "$mutant_hash" "$mutant_sql" \
      >"$mutants_dir/$mutant_prefix.materializar.log" 2>&1; then
      sed -n '1,500p' "$mutants_dir/$mutant_prefix.materializar.log" >&2
      fail "no se pudo recalibrar el hash candidato de $mutant_prefix."
    fi
    if cmp -s "$MATERIALIZED_PROPOSAL" "$mutant_sql"; then
      fail "la propuesta mutada $mutant_prefix quedo vacia."
    fi

    {
      printf '%s\n' '\set ON_ERROR_STOP on' '\set VERBOSITY verbose'
      printf '\\i %s\n' "$mutant_sql"
    } > "$application_sql"
    if $PSQL -X -qAt -v ON_ERROR_STOP=1 \
      -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
      -f "$application_sql" >"$application_log" 2>&1; then
      application_status=0
    else
      application_status=$?
    fi

    if [[ "$expected_phase" == proposal ]]; then
      if [[ "$application_status" -eq 0 ]]; then
        fail "mutante estructural $mutant_prefix atraveso la propuesta."
      fi
      c01_assert_expected_mutant_failure \
        "$application_log" "$mutant_prefix" "$expected_state" \
        "$expected_oracle" proposal
      c01_assert_fresh_candidate_state
    else
      if [[ "$application_status" -ne 0 ]]; then
        sed -n '1,1200p' "$application_log" >&2
        fail "mutante semantico $mutant_prefix no atraveso la propuesta."
      fi
      installed_mutant_hash="$($PSQL -X -qAt \
        -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
        -c "select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('$mutant_signature')")"
      if [[ "$installed_mutant_hash" != "$mutant_hash" ]]; then
        fail "readback del mutante $mutant_prefix no coincide con su hash calibrado."
      fi

      {
        printf '%s\n' '\set ON_ERROR_STOP on' '\set VERBOSITY verbose'
        printf '\\i %s\n' "$BANK_SNAPSHOT"
      } > "$bank_sql"
      if $PSQL -X -qAt -v ON_ERROR_STOP=1 \
        -h "$SOCKET_DIR" -p "$PORT" -U postgres -d "$DB_NAME" \
        -f "$bank_sql" >"$bank_log" 2>&1; then
        bank_status=0
      else
        bank_status=$?
      fi
      if [[ "$bank_status" -eq 0 ]]; then
        sed -n '1,1200p' "$bank_log" >&2
        fail "mutante semantico $mutant_prefix sobrevivio al banco."
      fi
      c01_assert_expected_mutant_failure \
        "$bank_log" "$mutant_prefix" "$expected_state" \
        "$expected_oracle" bank
    fi

    printf '%s\t%s\t%s\t%s\n' \
      "$mutant_id" "$mutant_slug" "$expected_phase" "$expected_oracle" \
      >> "$matrix"
    log "mutante $mutant_prefix cazado por $expected_phase: $expected_oracle"
  done < "$manifest"

  ok_count="$(wc -l < "$matrix" | tr -d ' ')"
  unique_count="$(cut -f1 "$matrix" | sort -u | wc -l | tr -d ' ')"
  if [[ "$ok_count" -ne 17 || "$unique_count" -ne 17 ]]; then
    sed -n '1,80p' "$matrix" >&2
    fail "matriz de mutantes incompleta ($ok_count/$unique_count)."
  fi
  log 'matriz de cuerpos verde: 17/17 mutantes cazados por su oraculo declarado.'
}
