#!/bin/sh
# Hook commit-msg: quita del mensaje la atribución de IA antes de que el commit exista.
# Borra los trailers «Co-Authored-By: … Claude/anthropic», la línea que es SOLO la firma
# «🤖 Generated with [Claude Code](…)» y «Claude-Session:». Una frase que la menciona en
# medio del texto se queda, y los coautores humanos también.
# Lo llama Lefthook (lefthook.yml → commit-msg) en el repo raíz y un hook directo en
# public_html. Decisión de Miguel, 03/10/2026: ningún commit lleva a Claude como coautor.
f="$1"
[ -f "$f" ] || exit 0
perl -0pi -e '
  s/^[ \t]*co-authored-by:[^\n]*(claude|anthropic)[^\n]*(\n|\z)//gim;
  s/^\W{0,8}generated with \[?claude code\]?(\([^)\n]*\))?[ \t]*(\n|\z)//gim;
  s/^[ \t]*claude-session:[^\n]*(\n|\z)//gim;
  s/\s+\z/\n/;
' "$f"
