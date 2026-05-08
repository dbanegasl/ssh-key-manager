# SSH Key Manager

Script interactivo para instalar llaves SSH (Windows + WSL) en múltiples
servidores definidos en `~/.ssh/config`.

## Características

- Instala simultáneamente la llave **Windows** (`/mnt/c/...`) y la llave **WSL**
- Lee hosts, IPs y puertos directamente desde `~/.ssh/config` (sin duplicar datos)
- Detecta si la llave ya está instalada antes de intentar copiarla
- Verifica conectividad TCP antes de cada conexión
- Output con colores y resumen final
- Menú interactivo con selección por rangos (`1 3 5-8`)
- Modo dry-run para verificar estado sin modificar nada

## Requisitos

- Bash 4+
- `ssh-copy-id` disponible
- Hosts configurados en `~/.ssh/config` con `User` definido

## Uso

```bash
chmod +x ssh-key-manager.sh
./ssh-key-manager.sh
```

## Configuración

El script **nunca se edita directamente**. Toda la configuración va en `config.local.sh`,
que está en `.gitignore` y no se sube al repositorio.

### Primera vez (wizard automático)

Al ejecutar el script sin `config.local.sh`, lanza un wizard interactivo que:
- Detecta automáticamente usuarios de Windows en `/mnt/c/Users/`
- Detecta llaves `.pub` existentes en `~/.ssh/`
- Detecta usuarios SSH en `~/.ssh/config`
- Genera `config.local.sh` con tus valores

### Configuración manual

Copia la plantilla y edítala:

```bash
cp config.example.sh config.local.sh
```

```bash
# config.local.sh
WIN_USERNAME="tu-usuario-windows"   # C:\Users\<este valor>
KEY_NAME="vsCODE"                   # nombre del archivo de llave (sin .pub)
SSH_USER="tu-usuario-ssh"           # valor de User= en ~/.ssh/config
CONNECT_TIMEOUT=8
```

### Reconfigurar

Desde el menú del script, usa la opción **6 → Reconfigurar**.

## Estructura del proyecto

```
ssh-key-manager/
├── ssh-key-manager.sh    # Script principal
├── config.example.sh     # Plantilla de configuración (comprometer en git)
├── config.local.sh       # Tu configuración real (gitignored, NO subir)
├── README.md
└── .gitignore
```

## Menú

| Opción | Descripción |
|--------|-------------|
| `1` | Instalar en **todos** los servidores del config |
| `2` | Seleccionar servidores por número o rango |
| `3` | Listar todos los servidores configurados |
| `4` | Verificar estado WIN/WSL por servidor (dry-run) |
| `5` | Ver configuración activa |
| `6` | Reconfigurar (relanzar wizard) |
| `0` | Salir |

## Licencia

MIT
