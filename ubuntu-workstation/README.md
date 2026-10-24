# ubuntu-workstation

Provisiona um PC novo com **Ubuntu 26.04 LTS** replicando os apps da estação
Fedora 43 anterior. Organizado por **fonte de instalação** (apt / PPA / repo de
terceiro / .deb avulso / flatpak / binário / driver).

Sem snap, por decisão: Firefox e Chromium vêm de PPA, não do snap padrão do Ubuntu.

## Pré-requisitos

- Ubuntu 26.04 LTS recém-instalado, com o usuário desktop criado.
- `sudo` disponível para o usuário.
- Internet.

Instalar Ansible + collections (uma vez):

```bash
sudo apt update && sudo apt install -y ansible
cd ubuntu-workstation
ansible-galaxy collection install -r requirements.yml
```

## Antes de rodar — ajustar

Edite `group_vars/all.yml`:

- `target_user`: usuário desktop (default `nuvidio`).
- `kiro_ide_version`: versão do .deb do Kiro IDE (default `1.2.56`, validada). Para
  atualizar, troque a versão — a URL é montada a partir dela. Confira a versão
  stable atual em https://kiro.dev/downloads/ .
- Versões pinadas (`go_version`, `flyway_version`): confira se são as desejadas
  antes de rodar.

As URLs dos instaladores (`kiro-cli` → `cli.kiro.dev/install`, `claude` →
`claude.ai/install.sh`, Go, Flyway) foram validadas em 2026-10-09. Se der 404 no
futuro, confira a versão/URL oficial.

## Rodar

Dry-run primeiro (não aplica nada, mostra o que mudaria):

```bash
ansible-playbook site.yml --check --diff
```

Aplicar:

```bash
ansible-playbook site.yml --ask-become-pass
```

Rodar só uma parte (ex.: só os repos e apt):

```bash
ansible-playbook site.yml --ask-become-pass --tags apt_repos,apt_base
# (requer adicionar tags às roles em site.yml se quiser esse filtro)
```

## O que o playbook instala

| Fonte | Role | Apps |
|---|---|---|
| Repos de terceiros | `apt_repos` + `apt_base` | Docker CE, VS Code, GitHub CLI, Terraform, Tailscale, Cloudflare WARP, AnyDesk, mongosh |
| PPA (sem snap) | `apt_base` | Firefox, Chromium, OBS Studio |
| apt universe | `apt_base` | qBittorrent, VLC, LibreOffice, Solaar, git/curl/wget etc.; ansible-core, ansible-lint, shellcheck, psql (`postgresql-client`), nodejs/npm, screen |
| .deb avulso | `deb_direct` | Discord, Vibe, WinBoat (+ `freerdp3-x11`) |
| Flatpak (Flathub) | `flatpak` | MongoDB Compass, Moonlight, Spotify, Bottles, DBeaver, Gear Lever, Ferdium, Yakuake, Trayscale |
| Binário / tarball / installer | `binaries` | AWS CLI v2, session-manager-plugin, Go + ferramentas (golangci-lint, gofumpt, gci, fieldalignment em `~/go/bin`), Flyway, Zanshin e camset (pipx), kiro-cli, claude |
| Driver | `nvidia` | `nvidia-driver-580` + utils (RTX 4050 Laptop) — **exige reboot** |
| .deb oficial | `kiro_ide` | Kiro IDE (pacote .deb; dispensa wrapper/symlink) |
| sysctl | `rede` | `arp_ignore=1` + `arp_announce=2` em `/etc/sysctl.d/90-arp-multihome.conf` — cabo e Wi-Fi na mesma rede sem ARP flux; Wi-Fi com MAC de fábrica (`wifi.cloned-mac-address=permanent`, `/etc/NetworkManager/conf.d/90-wifi-mac-permanent.conf`) para casar com a reserva DHCP |

## O que fica de FORA (intencional)

- **Stack ML Python do projeto `telegram_bots`** (torch, pyannote, huggingface,
  ctranslate2, onnxruntime, optuna, rapidocr, yt-dlp, gallery-dl, fabric etc.).
  No Fedora estava poluindo o `~/.local` (user-site global). No PC novo, recrie
  **dentro do venv do projeto**:
  ```bash
  cd ~/git/telegram_bots
  python3 -m venv venv && source venv/bin/activate
  pip install -r requirements.txt
  ```
- **Antigravity, Gemini Desktop** — removidos a pedido, não usados mais.
- **PyCharm, websocat, azure-cli** — removidos a pedido.
- **azcopy, deno** — fora a pedido (scan de 2026-10-23).
- **Google Chrome (stable e Canary)** — Chromium (PPA xtradeb) substitui.
- Stack base do KDE/firmware/kernel — vem com a instalação do Ubuntu KDE/desktop.

## Pós-instalação (manual)

1. **Reboot** depois do primeiro run (driver NVIDIA + grupo `docker` do usuário).
2. `tailscale up` / login no WARP / login no AnyDesk conforme necessário.
3. `aws sso login --sso-session Nuvidio` para configurar perfis.
4. Validar GPU: `nvidia-smi`.
5. Validar Docker sem sudo: `docker run hello-world` (após relogin).
