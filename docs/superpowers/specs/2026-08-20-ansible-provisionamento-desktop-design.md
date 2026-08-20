# Provisionamento de estação de trabalho com Ansible

Data: 2026-08-20
Status: aprovado, aguardando plano de implementação

## Problema

Formatar a máquina hoje significa reinstalar dezenas de aplicações à mão e
reconstruir configuração de memória. O repositório já tem um playbook
(`fedora/fedora.yaml`), mas ele descreve uma máquina que não existe mais:
instala Franz, Notepadqq, Notion, fsearch, AppImageLauncher, qbittorrent,
GreenWithEnvy, Barrier, Deezer, OneDrive e PeaZip — nenhum deles presente no
sistema atual.

## Objetivo

Reproduzir o estado atual da estação a partir de uma instalação limpa, em
Fedora e em Ubuntu, cobrindo aplicações, configuração de sistema e os
dotfiles essenciais.

## Escopo

Dentro:

- Repositórios de terceiros, pacotes nativos, flatpaks e binários instalados
  fora de gerenciador de pacotes.
- Configuração de sistema: grupos do usuário, serviços habilitados.
- Dotfiles essenciais: shell, git e cliente SSH.
- Automações de usuário do Gather: cinco units systemd e os scripts que elas
  executam.

Fora:

- Configuração do KDE Plasma. São dezenas de arquivos em `~/.config`,
  reescritos pelo próprio ambiente a cada sessão; versioná-los produz ruído
  constante no diff sem ganho proporcional.
- Bibliotecas Python de projeto em `~/.local/bin` (torch, pyannote, optuna,
  huggingface, alembic, fabric). São dependências de projetos específicos,
  reinstaladas pelo `requirements.txt` de cada um. O playbook garante apenas
  `python3-pip` e `pipx`.
- Qualquer credencial. Ver "Segurança" abaixo.

## Segurança

Nenhum segredo entra no repositório, ainda que ele seja privado. Repositório
privado vira público por engano, é clonado em máquina de terceiro, e o
histórico do git é permanente.

Arquivos com credencial nesta máquina, todos excluídos do versionamento:

- `~/.ssh/` — chaves privadas `github_personal`, `home_lab`, `synapse-hml.pem`
- `~/.aws/credentials`, `~/.azure/`, `~/.docker/config.json`
- `~/.config/gh/hosts.yml` — token OAuth do GitHub
- `~/.gnupg/`, `~/.pki/`
- `~/.gather_claude_secret`, `~/.gather_status_secret`, `~/.gather_webhook_secret`

O playbook cria a estrutura e as permissões (`~/.ssh` em 0700, `~/.aws`
vazio) e versiona apenas a parte não sensível — `~/.ssh/config` sem chaves,
`~/.aws/config` sem `credentials`. O conteúdo sensível é restaurado à mão a
partir do gerenciador de senhas ou de backup cifrado.

## Estrutura do repositório

```
ansible-playbooks/
├── ansible.cfg
├── inventory/hosts.ini          # localhost, ansible_connection=local
├── fedora.yml
├── ubuntu.yml
├── group_vars/all.yml           # flatpaks, dotfiles, grupos — comum aos dois
├── vars/fedora.yml              # pacotes dnf, definições de repositório
├── vars/ubuntu.yml              # pacotes apt, keyrings e PPAs
├── files/
│   ├── dotfiles/
│   └── gather/                  # scripts e units do Gather
└── roles/
    ├── repos/
    ├── packages/
    ├── flatpak/
    ├── binaries/
    ├── system_config/
    ├── dotfiles/
    ├── gather/
    └── hardware/
```

As roles são compartilhadas entre as duas distribuições. A diferença de
gerenciador de pacotes vive em `vars/<distro>.yml` e em
`roles/<role>/tasks/<distro>.yml`, incluído conforme `ansible_os_family`.
Isso evita duplicar a lógica de flatpak, dotfiles, binários e Gather, que é
idêntica nos dois sistemas.

`fedora/fedora.yaml` é substituído. `fedora/amazon-ssm-agent.gpg` e
`fedora/peazip-flatpak.desktop.download` são removidos: o primeiro é a chave
de assinatura do SSM Agent, que não está instalado e cuja chave expirou; o
segundo pertence ao PeaZip, também ausente.

## Fase 1 — aplicações

Roles `repos`, `packages`, `flatpak`, `binaries`.

Repositórios de terceiros: RPM Fusion free e nonfree, Docker CE, Google
Chrome, Visual Studio Code, gh-cli, HashiCorp, MongoDB 8.2, Terra, AnyDesk,
Antigravity, Microsoft prod e Cisco openh264.

Três repositórios habilitados na máquina não entram: `google-chrome-canary`,
COPR `phracek/PyCharm` e COPR `atim/websocat`. Nenhum deles tem pacote
instalado — são resquício de teste. Provisionar repositório para pacote que
não se usa deixa origem órfã no `dnf list` sem contrapartida.

O repositório `rpmfusion-nonfree-nvidia-driver` não fica aqui: acompanha os
pacotes nvidia na role `hardware`, para que uma execução sem a tag não
adicione repositório sem uso.

Pacotes nativos: docker-ce com cli, buildx, compose e model plugin; code;
google-chrome-stable; chromium; firefox; gh; terraform; azure-cli; anydesk;
discord; antigravity; gemini-desktop; mongodb-mongosh; obs-studio com os
plugins distroav, droidcam, pwvideo, vlc-video, webkitgtk e x264; nodejs;
python3-pip; pipx; ansible-core; python3-ansible-lint; openfortivpn;
vim-enhanced; git; krdc; krfb; kde-connect; libreoffice writer, calc,
impress, draw e math; mediawriter; ffmpeg e codecs freeworld; ndi-sdk.

Flatpaks, via remote flathub: `com.mongodb.Compass`,
`com.moonlight_stream.Moonlight`, `com.spotify.Client`,
`io.dbeaver.DBeaverCommunity`, `it.mijorus.gearlever`, `org.ferdium.Ferdium`,
`org.kde.yakuake`.

Binários fora de gerenciador: AWS CLI v2, session-manager-plugin, azcopy.

O session-manager-plugin é instalado do pacote oficial da AWS, sem a chave
GPG antiga:

```yaml
# Fedora
- name: Install session-manager-plugin
  become: true
  dnf:
    name: https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
    state: present
    disable_gpg_check: true
```

No Ubuntu, o módulo `apt` aceita a URL diretamente em `deb:` e faz o
download sozinho, sem `get_url` intermediário:

```yaml
- name: Install session-manager-plugin
  become: true
  apt:
    deb: https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb
```

Ambos são idempotentes: os módulos resolvem a versão do pacote baixado e não
reinstalam quando ela já está presente.

## Fase 2 — configuração de sistema

Role `system_config`.

Usuário nos grupos `wheel` e `docker`. Serviços `docker.service` e
`anydesk.service` habilitados. Diretório temporário de trabalho do playbook
criado e limpo ao final.

Regras de firewalld não entram: a configuração atual não pôde ser lida sem
senha de sudo durante o levantamento. Verificar na implementação e incluir
apenas se houver regra personalizada.

## Fase 3 — dotfiles, Gather e Ubuntu

### Dotfiles

Role `dotfiles`. Versionados: `.bashrc` (37 linhas), `.bash_profile` (12),
`.gitconfig` (9) e `.ssh/config`. Uma varredura por `token`, `secret`, `key`
e `password` nos quatro não encontrou nada — vão para o repositório como
estão, sem edição.

`.vimrc` e `.gtkrc-2.0` foram listados por engano na primeira versão desta
spec: o primeiro não existe na máquina, o segundo tem zero bytes.

### Gather

Role `gather`. Cinco units de usuário em `~/.config/systemd/user/`:

| Unit | Tipo | Disparo |
|---|---|---|
| `gather-claude-status.service` | daemon, `Restart=always` | `default.target` |
| `gather-ci-status.service` | oneshot | timer |
| `gather-ci-status.timer` | timer | a cada 10 minutos |
| `gather-prs.service` | oneshot | timer |
| `gather-prs.timer` | timer | de hora em hora, `Persistent=true` |

Os scripts que as units executam estão hoje em
`/home/nuvidio/nuvidio/temp_scripts/`, que não é um repositório git. Sem
versionamento, formatar a máquina perde os scripts e o playbook restaura
units apontando para arquivos inexistentes, que falham em laço. Os seis
arquivos passam para `files/gather/` neste repositório:

- `gather_webhook.mjs` — cliente de Smart Object compartilhado
- `gather_ci_status.mjs` e `gather_ci_status_cron.sh`
- `gather_claude_status.mjs`
- `gather_prs.mjs` e `gather_prs_cron.sh`

O playbook os instala em `~/.local/share/gather/` e reescreve os `ExecStart`
para esse caminho, eliminando o `SCRIPT_DIR` fixo em `/home/nuvidio/`.

#### Mudança na passagem do segredo

Hoje o segredo é lido de um arquivo e exportado como variável de ambiente:

```
ExecStart=/bin/bash -c 'GATHER_CLAUDE_SECRET="$(cat %h/.gather_claude_secret)" exec /usr/bin/node ...'
```

Isso mantém o valor fora da linha de comando, mas o coloca no ambiente do
processo, legível em `/proc/<pid>/environ` por qualquer processo do mesmo
usuário e presente em core dumps.

Passa a usar `LoadCredential` do systemd. O segredo fica num arquivo fora do
repositório; o systemd o monta em tmpfs com modo 0400, acessível apenas ao
serviço, e exporta o caminho em `$CREDENTIALS_DIRECTORY`:

```ini
[Service]
LoadCredential=gather_claude:%h/.config/gather/claude
ExecStart=/usr/bin/node %h/.local/share/gather/gather_claude_status.mjs
```

Os três arquivos de segredo do home consolidam em `~/.config/gather/`, modo
0600, criados pelo playbook vazios e preenchidos à mão:

| Origem | Destino | Nome da credencial |
|---|---|---|
| `~/.gather_claude_secret` | `~/.config/gather/claude` | `gather_claude` |
| `~/.gather_status_secret` | `~/.config/gather/status` | `gather_status` |
| `~/.gather_webhook_secret` | `~/.config/gather/webhook` | `gather_webhook` |

A leitura muda em um único ponto, `loadSecret` em `gather_webhook.mjs`, que
os três scripts já compartilham. A função passa a ler
`$CREDENTIALS_DIRECTORY/<nome>` e mantém a variável de ambiente como
alternativa, para que execução manual em terminal continue funcionando.

Os dois scripts `.sh` deixam de montar a variável de ambiente antes de chamar
o node: `$CREDENTIALS_DIRECTORY` é herdado pelo processo filho e o `.mjs` lê
o arquivo diretamente.

O bloco de fallback de `GH_TOKEN` a partir de `~/.gh_token`, presente nos dois
scripts `.sh`, é removido: o arquivo não existe nesta máquina, o `gh` já
resolve autenticação pelo keyring, e o bloco só serviria para reintroduzir um
token em texto plano no home.

### Ubuntu

`ubuntu.yml` cobre o mesmo conjunto via apt. Mapeamentos que não são diretos:

| Fedora | Ubuntu |
|---|---|
| RPM Fusion (codecs) | `ubuntu-restricted-extras` |
| `akmod-nvidia`, `xorg-x11-drv-nvidia-cuda` | `ubuntu-drivers-common`, depois `ubuntu-drivers install` |
| Terra (`discord`) | `.deb` oficial do Discord |
| COPR `phracek/PyCharm` | snap ou tarball oficial |
| COPR `atim/websocat` | binário do release no GitHub |
| `session-manager-plugin.rpm` | `session-manager-plugin.deb` de `ubuntu_64bit/` |

## Hardware

Role `hardware`, sempre por tag, nunca no fluxo padrão: o repositório
`rpmfusion-nonfree-nvidia-driver` com `akmod-nvidia` e
`xorg-x11-drv-nvidia-cuda`; `virtualbox-guest-additions`; `solaar`, para
periférico Logitech; `minicom`, para console serial. Isso mantém o playbook
base executável em qualquer máquina.

Dois itens saíram desta lista depois de verificação na máquina. `openscad`
não está instalado — o pacote presente é `opensc`, middleware de smartcard,
que é biblioteca de sistema e não app de hardware. `camset` não é pacote RPM:
é um binário Python em `~/.local/bin`, portanto cai na exclusão de
ferramentas Python já declarada em Escopo.

## Dependências

`ansible-core` sozinho não basta. As roles usam `community.general.copr` e
`community.general.flatpak`, que vivem numa collection separada. Sem
declará-la, o playbook falha na primeira tarefa de repositório numa máquina
recém-formatada.

`collections/requirements.yml`:

```yaml
collections:
  - name: community.general
```

Instalada com `ansible-galaxy collection install -r collections/requirements.yml`,
e o `ansible.cfg` aponta `collections_path` para o diretório do projeto.

## Execução

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass
ansible-playbook -i inventory/hosts.ini fedora.yml --tags nvidia
```

## Verificação

Por fase, nesta ordem:

1. `ansible-playbook --syntax-check`
2. `ansible-lint`
3. Execução com `--check`
4. Execução real nesta máquina
5. Segunda execução real

O passo 5 é o teste de idempotência e é o critério de aceite de cada fase,
com uma ressalva: `changed=0` absoluto não é alcançável. Três tarefas
reportam mudança sempre que existe atualização disponível a montante, o que
independe do playbook:

| Tarefa | Motivo |
|---|---|
| `dnf: name="*" state=latest` | há pacote novo no repositório |
| `flatpak update` | há build novo no flathub |
| instalador shell do AWS CLI | não expõe estado consultável |

Essas três recebem `changed_when` explícito que reflita mudança real, e o
critério de aceite recai sobre as tarefas declarativas: instalação de
pacotes, repositórios, flatpaks, dotfiles e units devem sair todas `ok` na
segunda execução.

Para o Gather, acrescenta-se: `systemctl --user status` nas cinco units, e
uma execução manual de `gather_ci_status.mjs` com `--dry-run` confirmando que
o segredo é lido de `$CREDENTIALS_DIRECTORY`.

O `ubuntu.yml` fica limitado aos passos 1 e 2 enquanto não houver uma máquina
Ubuntu para executá-lo. Isso é uma limitação conhecida da entrega, não um
descuido.
