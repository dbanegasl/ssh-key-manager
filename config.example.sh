#!/usr/bin/env bash
# =============================================================================
# SSH Key Manager — Configuración
# Compatible con: macOS, Linux, WSL (Windows)
# =============================================================================
# INSTRUCCIONES:
#   1. Copia este archivo:  cp config.example.sh config.local.sh
#   2. Edita config.local.sh con tus datos
#   3. config.local.sh está en .gitignore — nunca se sube al repositorio
# =============================================================================

# --- Usuario de Windows (solo relevante en WSL) ---
# WSL:          Pon tu usuario de Windows (C:\Users\<WIN_USERNAME>\.ssh\)
#               Ejemplo: WIN_USERNAME="john"
# macOS/Linux:  Deja vacío o pon cualquier valor — el script lo ignora
WIN_USERNAME=""

# --- Nombre del archivo de llave SSH (sin extensión) ---
# El script buscará  ~/.ssh/<KEY_NAME>.pub  y  ~/.ssh/<KEY_NAME>  (privada)
# WSL:          También busca /mnt/c/Users/<WIN_USERNAME>/.ssh/<KEY_NAME>
# macOS/Linux:  Solo usa ~/.ssh/<KEY_NAME>
# Ejemplo: si tu llave es ~/.ssh/id_ed25519 → KEY_NAME="id_ed25519"
KEY_NAME="vsCODE"

# --- Usuario SSH para filtrar hosts desde ~/.ssh/config ---
# Solo se procesarán los hosts que tengan  User == SSH_USER  en el config.
# Ejemplo: SSH_USER="john-doe"
SSH_USER=""

# --- Timeout de conexión en segundos ---
CONNECT_TIMEOUT=8
