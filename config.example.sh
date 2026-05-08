#!/usr/bin/env bash
# =============================================================================
# SSH Key Manager — Configuración
# =============================================================================
# INSTRUCCIONES:
#   1. Copia este archivo:  cp config.example.sh config.local.sh
#   2. Edita config.local.sh con tus datos
#   3. config.local.sh está en .gitignore — nunca se sube al repositorio
# =============================================================================

# --- Usuario de Windows (para construir la ruta /mnt/c/Users/<WIN_USERNAME>/) ---
# Ejemplo: si tu ruta en Windows es C:\Users\john → WIN_USERNAME="john"
WIN_USERNAME=""

# --- Nombre del archivo de llave SSH (sin extensión) ---
# El script buscará  <nombre>.pub  y  <nombre>  (privada)
# En Windows: /mnt/c/Users/<WIN_USERNAME>/.ssh/<KEY_NAME>
# En WSL:     ~/.ssh/<KEY_NAME>
# Ejemplo: si tu llave es ~/.ssh/id_ed25519 → KEY_NAME="id_ed25519"
KEY_NAME="vsCODE"

# --- Usuario SSH para filtrar hosts desde ~/.ssh/config ---
# Solo se procesarán los hosts que tengan  User == SSH_USER  en el config.
# Ejemplo: SSH_USER="john-doe"
SSH_USER=""

# --- Timeout de conexión en segundos ---
CONNECT_TIMEOUT=8
