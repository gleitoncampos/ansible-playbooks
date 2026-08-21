# Provisionamento de estação com Ansible — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruir este repositório em roles Ansible compartilhadas que
reproduzem a estação atual do zero, em Fedora e em Ubuntu.

**Architecture:** Dois playbooks (`fedora.yml`, `ubuntu.yml`) sobre oito roles
comuns. A diferença entre gerenciadores de pacote vive em `vars/<distro>.yml`
e em `roles/<role>/tasks/<distro>.yml`, incluído conforme `ansible_os_family`.
Nenhum segredo no repositório. Pacotes de hardware isolados por tag.

**Tech Stack:** ansible-core 2.18.18 (`ansible-core` do Fedora 43),
`community.general` para o módulo `flatpak`, `ansible-lint`, `node --test`
para a mudança no cliente do Gather, `podman` para validar cada role em
container limpo.

**Spec:** `docs/superpowers/specs/2026-08-20-ansible-provisionamento-desktop-design.md`

## Global Constraints

- Nenhuma credencial entra no repositório. Nem chave, nem token, nem
  `whsec_`, nem arquivo de `~/.ssh`, `~/.aws`, `~/.azure`, `~/.gnupg`,
  `~/.pki` ou `~/.config/gh`.
- Todas as tarefas rodam contra `localhost` com `ansible_connection=local`.
- Toda tarefa que precisa de root usa `become: true` na própria tarefa, nunca
  no play inteiro — o playbook roda com `--ask-become-pass`.
- Nomes de tarefa em inglês, no imperativo, seguindo o `fedora/fedora.yaml`
  original ("Install commom programs", "Add flathub repository").
- Comentários e documentação em português, como o restante do repositório.
- Pacotes de hardware ficam sob a tag `hardware` e nunca no fluxo padrão.
- Critério de idempotência: na segunda execução, toda tarefa declarativa sai
  `ok`. As três tarefas de atualização a montante (`dnf` update all,
  `flatpak update`, instalador do AWS CLI) recebem `changed_when` explícito.
- Commits ao fim de cada task.
- Módulo de pacote no Fedora é `ansible.builtin.dnf5`, nunca
  `ansible.builtin.dnf`. O Fedora 43 entrega dnf5; o módulo `dnf` exige os
  bindings dnf4 do `python3-dnf`, que nesta máquina está presente apenas como
  dependência transitiva e pode não existir numa instalação limpa — nesse caso
  toda tarefa de pacote falha com "Could not import the dnf python module".
- **Toda role tem um step de validação em container limpo, antes da execução
  na máquina real.** Isto não é zelo: a primeira versão deste plano carregava
  quatro URLs mortas e dois pacotes sem repositório, e nenhum dos seus testes
  de aceite os detectou, porque todos rodavam contra a máquina de origem, que
  já estava no estado desejado. `rpm -q` de pacote instalado e `dnf repolist`
  de repositório existente passam de graça e não provam nada sobre uma
  instalação limpa.

---

### Task 1: Esqueleto do projeto

**Files:**
- Create: `ansible.cfg`
- Create: `.ansible-lint`
- Create: `inventory/hosts.ini`
- Create: `collections/requirements.yml`
- Create: `.gitignore`
- Create: `fedora.yml`
- Create: `group_vars/all.yml`
- Create: `vars/fedora.yml`
- Delete: `fedora/fedora.yaml`, `fedora/amazon-ssm-agent.gpg`, `fedora/peazip-flatpak.desktop.download`

**Interfaces:**
- Consumes: nada.
- Produces: variável `tmp_folder` (string, `/tmp/ansible_provision`) em
  `group_vars/all.yml`, usada pelas roles `binaries` e `hardware`. Playbook
  `fedora.yml` com bloco `roles:` vazio, ao qual as tasks seguintes acrescentam
  uma role cada.

- [ ] **Step 1: Escrever o teste que falha**

Não há framework de teste em Ansible; o teste é o próprio `syntax-check`, que
falha enquanto o playbook não existe. Rode primeiro para ver o vermelho:

```bash
ansible-playbook -i inventory/hosts.ini fedora.yml --syntax-check
```

- [ ] **Step 2: Rodar e confirmar a falha**

Esperado: `ERROR! the playbook: fedora.yml could not be found`

- [ ] **Step 3: Criar `ansible.cfg`**

```ini
[defaults]
inventory = inventory/hosts.ini
collections_path = ./collections
roles_path = ./roles
stdout_callback = yaml
interpreter_python = auto_silent
nocows = True

[privilege_escalation]
become_method = sudo
```

- [ ] **Step 4: Criar `.ansible-lint`**

`package-latest` sinaliza `state: latest`, que é intencional na tarefa de
atualização geral do sistema. Sem esta exclusão o `ansible-lint` reprova o
código deste próprio plano, e ele é usado como portão em nove tasks.

```yaml
---
skip_list:
  - package-latest
```

- [ ] **Step 5: Criar `inventory/hosts.ini`**

```ini
[workstation]
localhost ansible_connection=local
```

- [ ] **Step 6: Criar `collections/requirements.yml`**

```yaml
---
collections:
  - name: community.general
```

- [ ] **Step 7: Criar `.gitignore`**

O primeiro bloco impede que a collection baixada entre no repositório; o
segundo é rede de segurança contra credencial commitada por engano.

```gitignore
collections/ansible_collections/
*.retry

# Rede de segurança: nada de credencial no repositório.
*.pem
*.key
id_rsa*
id_ed25519*
.vault_pass
secrets.yml
```

- [ ] **Step 8: Criar `group_vars/all.yml`**

```yaml
---
# Diretório de trabalho para downloads temporários (AWS CLI, azcopy).
tmp_folder: /tmp/ansible_provision

# Usuário provisionado. Deriva do usuário que invoca o playbook, para que o
# mesmo repositório sirva outra máquina sem edição.
target_user: "{{ ansible_user_id }}"
target_home: "{{ ansible_env.HOME }}"
```

- [ ] **Step 9: Criar `vars/fedora.yml` com o cabeçalho**

Só o esqueleto; as listas entram nas tasks 2 e 3.

```yaml
---
# Pacotes e repositórios específicos do Fedora.
# Listas preenchidas nas tasks seguintes.
```

- [ ] **Step 10: Criar `fedora.yml`**

```yaml
---
- name: Provision Fedora workstation
  hosts: workstation
  gather_facts: true
  vars_files:
    - vars/fedora.yml
  roles: []
```

- [ ] **Step 11: Remover os arquivos obsoletos**

```bash
git rm fedora/fedora.yaml fedora/amazon-ssm-agent.gpg fedora/peazip-flatpak.desktop.download
```

- [ ] **Step 12: Instalar a collection e rodar o syntax-check**

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --syntax-check
```

Esperado: `playbook: fedora.yml`, sem erro.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "feat: esqueleto do projeto Ansible

Substitui o playbook único por uma estrutura de roles com inventário
local, collections declaradas e gitignore que barra credencial.

Remove fedora/fedora.yaml, que descrevia uma máquina que não existe mais,
a chave GPG expirada do SSM Agent e o arquivo do PeaZip, desinstalado.

.ansible-lint exclui package-latest: state latest é intencional na
atualização geral e sem a exclusão o lint reprova o próprio plano."
```

---

### Task 2: Role `repos`

**Files:**
- Create: `roles/repos/tasks/main.yml`
- Create: `roles/repos/tasks/fedora.yml`
- Modify: `vars/fedora.yml`
- Modify: `fedora.yml`

**Interfaces:**
- Consumes: `ansible_os_family` (fact), `ansible_distribution_major_version` (fact).
- Produces: repositórios habilitados no sistema, pré-requisito da role `packages`.
  Define em `vars/fedora.yml` a lista `dnf_repositories` (lista de dicts com
  as chaves `name`, `description`, `baseurl`, `gpgcheck`, `gpgkey`) e a lista
  `rpm_url_repositories` (lista de strings com URLs de `.rpm` de release).

- [ ] **Step 1: Escrever o teste que falha**

Rodar `dnf repolist` nesta máquina não testa nada: os repositórios já existem
aqui e o comando passa mesmo com a role vazia. O teste desta role é a
resolubilidade de cada URL numa máquina que não tem nenhuma delas:

```bash
for u in \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-43.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm" \
  "https://dl.google.com/linux/linux_signing_key.pub" \
  "https://packages.microsoft.com/keys/microsoft.asc" \
  "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x23F3D4EA75716059" \
  "https://download.docker.com/linux/fedora/gpg" \
  "https://rpm.releases.hashicorp.com/gpg" \
  "https://www.mongodb.org/static/pgp/server-8.0.asc" \
  "https://keys.anydesk.com/repos/RPM-GPG-KEY" \
  "https://packages.microsoft.com/config/fedora/43/packages-microsoft-prod.rpm" \
  "https://repos.fyralabs.com/terra43" ; do
  printf '%-70s %s\n' "${u:0:70}" "$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 20 "$u")"
done
```

- [ ] **Step 2: Rodar e exigir 200 em todas**

Qualquer linha com `404` ou `000` para a task aqui. Foi assim que quatro URLs
mortas entraram na primeira versão deste plano sem que nenhum teste as
pegasse.

- [ ] **Step 3: Preencher `vars/fedora.yml` com os repositórios**

```yaml
---
# Repositórios de release entregues como .rpm.
rpm_url_repositories:
  - "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-{{ ansible_distribution_major_version }}.noarch.rpm"
  - "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-{{ ansible_distribution_major_version }}.noarch.rpm"

# Repositórios definidos por arquivo .repo. O campo `file` é obrigatório: o
# módulo grava `<name>.repo` por padrão, e três desses ids já vivem em
# arquivos de nome diferente nesta máquina — `docker-ce-stable` em
# docker-ce.repo, `code` em vscode.repo, `anydesk` em AnyDesk-Fedora.repo.
# Sem `file`, cada um passa a existir em dois arquivos com o mesmo id, e o
# dnf5 escolhe silenciosamente o primeiro em ordem alfabética.
dnf_repositories:
  - name: google-chrome
    file: google-chrome
    description: google-chrome
    baseurl: https://dl.google.com/linux/chrome/rpm/stable/x86_64
    gpgcheck: true
    gpgkey: https://dl.google.com/linux/linux_signing_key.pub

  - name: code
    file: vscode
    description: Visual Studio Code
    baseurl: https://packages.microsoft.com/yumrepos/vscode
    gpgcheck: true
    gpgkey: https://packages.microsoft.com/keys/microsoft.asc

  # A chave do gh não sai de cli.github.com: aquele caminho responde 404.
  # É a mesma chave que a máquina de origem usa, buscada no keyserver.
  - name: gh-cli
    file: gh-cli
    description: packages for the GitHub CLI
    baseurl: https://cli.github.com/packages/rpm
    gpgcheck: true
    gpgkey: "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x23F3D4EA75716059"

  - name: docker-ce-stable
    file: docker-ce
    description: Docker CE Stable - x86_64
    baseurl: "https://download.docker.com/linux/fedora/{{ ansible_distribution_major_version }}/x86_64/stable"
    gpgcheck: true
    gpgkey: https://download.docker.com/linux/fedora/gpg

  - name: hashicorp
    file: hashicorp
    description: Hashicorp Stable - x86_64
    baseurl: "https://rpm.releases.hashicorp.com/fedora/{{ ansible_distribution_major_version }}/x86_64/stable"
    gpgcheck: true
    gpgkey: https://rpm.releases.hashicorp.com/gpg

  # A MongoDB não publica chave 8.2: server-8.2.asc responde 404 e a série 8.2
  # é assinada pela chave 8.0. O baseurl segue o da máquina de origem
  # (redhat/8); o caminho redhat/9 também responde, mas nunca foi validado aqui.
  - name: mongodb-org-8.2
    file: mongodb-org-8.2
    description: MongoDB Repository
    baseurl: https://repo.mongodb.org/yum/redhat/8/mongodb-org/8.2/x86_64/
    gpgcheck: true
    gpgkey: https://www.mongodb.org/static/pgp/server-8.0.asc

  - name: anydesk
    file: AnyDesk-Fedora
    description: AnyDesk Fedora - stable
    baseurl: http://rpm.anydesk.com/fedora/x86_64/
    gpgcheck: true
    gpgkey: https://keys.anydesk.com/repos/RPM-GPG-KEY

  # Repositório do Google para o Antigravity. Não publica chave: os pacotes
  # vêm sem assinatura, então gpgcheck fica falso por imposição da origem.
  - name: antigravity-rpm
    file: antigravity
    description: Antigravity RPM Repository
    baseurl: https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm
    gpgcheck: false
    gpgkey: ""
```

- [ ] **Step 4: Criar `roles/repos/tasks/main.yml`**

```yaml
---
- name: Include distribution specific repositories
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

- [ ] **Step 5: Criar `roles/repos/tasks/fedora.yml`**

`disable_gpg_check` aparece só nos pacotes de release, que são assinados por
chaves ainda não importadas no momento em que são instalados.

```yaml
---
- name: Install release packages that define repositories
  become: true
  ansible.builtin.dnf5:
    name: "{{ rpm_url_repositories }}"
    state: present
    disable_gpg_check: true

- name: Add third party repositories
  become: true
  ansible.builtin.yum_repository:
    name: "{{ item.name }}"
    file: "{{ item.file }}"
    description: "{{ item.description }}"
    baseurl: "{{ item.baseurl }}"
    enabled: true
    gpgcheck: "{{ item.gpgcheck }}"
    gpgkey: "{{ item.gpgkey if item.gpgkey | default('') else omit }}"
  loop: "{{ dnf_repositories }}"
  loop_control:
    label: "{{ item.name }}"

- name: Add Microsoft production repository
  become: true
  ansible.builtin.dnf5:
    name: "https://packages.microsoft.com/config/fedora/{{ ansible_distribution_major_version }}/packages-microsoft-prod.rpm"
    state: present
    disable_gpg_check: true

# O Terra não publica terra-release.rpm num caminho estável: a URL usada na
# primeira versão deste plano responde 404. O método oficial monta o
# repositório em memória e instala o release a partir dele.
- name: Add Terra repository
  become: true
  ansible.builtin.command:
    cmd: >-
      dnf install -y --nogpgcheck
      --repofrompath 'terra,https://repos.fyralabs.com/terra{{ ansible_distribution_major_version }}'
      terra-release
    creates: /etc/yum.repos.d/terra.repo
```

- [ ] **Step 6: Ligar a role em `fedora.yml`**

```yaml
  roles:
    - { role: repos, tags: [repos] }
```

- [ ] **Step 7: Lint e syntax-check**

```bash
ansible-playbook -i inventory/hosts.ini fedora.yml --syntax-check
ansible-lint fedora.yml
```

Esperado: ambos sem erro.

- [ ] **Step 8: Validar em container limpo**

Este é o teste de aceite da role. O container não tem nenhum dos
repositórios, então o resultado é real:

```bash
podman run --rm -v "$PWD:/repo:ro,Z" -w /repo fedora:43 bash -c '
  dnf install -y ansible-core >/dev/null 2>&1
  ansible-playbook -i inventory/hosts.ini fedora.yml --tags repos --connection=local
  dnf repolist --enabled
'
```

Esperado: o playbook termina com `failed=0`, e o `repolist` mostra
`docker-ce-stable`, `gh-cli`, `hashicorp`, `mongodb-org-8.2`, `code`,
`google-chrome`, `anydesk`, `antigravity-rpm`, `terra` e as quatro da RPM
Fusion.

- [ ] **Step 9: Execução e idempotência na máquina real**

```bash
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags repos --check
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags repos
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags repos
```

Esperado na terceira: `changed=0`. Se `yum_repository` reportar `changed`
sempre, algum campo do `.repo` existente difere do declarado — comparar com
`/etc/yum.repos.d/<file>.repo` e alinhar.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: role repos com os repositórios de terceiros do Fedora

Repositórios declarados em vars/fedora.yml, separados entre pacotes de
release e arquivos .repo. Cada entrada traz 'file' explícito: três desses
ids já vivem em arquivos de nome diferente, e sem isso passariam a existir
em duplicata, com o dnf5 escolhendo um deles por ordem alfabética.

O Terra sai da lista de .rpm: aquela URL responde 404. Usa o método
oficial, que monta o repositório em memória para instalar o release.

A chave do gh vem do keyserver, não de cli.github.com, que dá 404. A do
MongoDB é a série 8.0, que assina também a 8.2 — não existe chave 8.2.

Fora: google-chrome-canary e os COPR de PyCharm e websocat, habilitados na
máquina mas sem pacote instalado. O repositório nvidia da RPM Fusion fica
na role hardware, junto dos pacotes que o usam."
```

---

### Task 3: Role `packages`

**Files:**
- Create: `roles/packages/tasks/main.yml`
- Create: `roles/packages/tasks/fedora.yml`
- Modify: `vars/fedora.yml`
- Modify: `fedora.yml`

**Interfaces:**
- Consumes: repositórios da role `repos`.
- Produces: define `system_packages` (lista de strings) em `vars/fedora.yml`.

- [ ] **Step 1: Escrever o teste que falha**

`rpm -q` nesta máquina passa para todos, porque todos já estão instalados —
não prova nada. O teste é a resolubilidade da lista inteira num container que
não tem nenhum deles. Ele detecta o pacote que não existe em repositório
algum, que foi como `gemini-desktop` entrou na primeira versão desta lista:

```bash
podman run --rm -v "$PWD:/repo:ro,Z" -w /repo fedora:43 bash -c '
  dnf install -y ansible-core >/dev/null 2>&1
  ansible-playbook -i inventory/hosts.ini fedora.yml --tags repos --connection=local >/dev/null
  dnf install --assumeno $(python3 -c "
import yaml,sys
print(\" \".join(yaml.safe_load(open(\"vars/fedora.yml\"))[\"system_packages\"]))")
'
```

- [ ] **Step 2: Rodar e exigir que a transação resolva**

Esperado: o dnf monta a transação e para no "Is this ok [y/N]" — o
`--assumeno` recusa e nada é instalado. Qualquer `No match for argument` ou
`Unable to find a match` aborta a task: aquele pacote não existe em nenhum
repositório declarado, e como a role instala a lista inteira numa tarefa só,
ele derrubaria **todos** os pacotes junto.

- [ ] **Step 3: Acrescentar a lista em `vars/fedora.yml`**

```yaml
system_packages:
  # Contêineres
  - docker-ce
  - docker-ce-cli
  - docker-buildx-plugin
  - docker-compose-plugin
  - docker-model-plugin
  - containerd.io

  # Navegadores
  - google-chrome-stable
  - chromium
  - firefox

  # Desenvolvimento e infraestrutura
  - code
  - gh
  - git
  - terraform
  - azure-cli
  - nodejs
  - python3-pip
  - pipx
  - ansible-core
  - python3-ansible-lint
  - vim-enhanced
  - mongodb-mongosh

  # Comunicação e produtividade
  - discord
  - anydesk
  - antigravity
  - libreoffice-writer
  - libreoffice-calc
  - libreoffice-impress
  - libreoffice-draw
  - libreoffice-math

  # Áudio, vídeo e captura
  - obs-studio
  - obs-studio-plugin-distroav
  - obs-studio-plugin-droidcam
  - obs-studio-plugin-pwvideo
  - obs-studio-plugin-vlc-video
  - obs-studio-plugin-webkitgtk
  - obs-studio-plugin-x264
  - ffmpeg
  - libavcodec-freeworld
  - gstreamer1-plugins-ugly
  - gstreamer1-plugins-bad-freeworld
  - ndi-sdk

  # Rede e acesso remoto
  - openfortivpn
  - krdc
  - krfb
  - kde-connect

  # Utilitários
  - mediawriter
  - flatpak
```

- [ ] **Step 4: Criar `roles/packages/tasks/main.yml`**

```yaml
---
- name: Include distribution specific packages
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

- [ ] **Step 5: Criar `roles/packages/tasks/fedora.yml`**

Módulo `dnf5`, não `dnf`: ver Global Constraints.

```yaml
---
- name: Update all system packages
  become: true
  ansible.builtin.dnf5:
    name: "*"
    state: latest
  changed_when: false
  tags:
    - upgrade
    - never

- name: Install system packages
  become: true
  ansible.builtin.dnf5:
    name: "{{ system_packages }}"
    state: present
```

A atualização geral leva `never`: ela reporta mudança sempre que existe
pacote novo a montante, o que não é efeito do playbook. Em vez de mascarar
isso com um `changed_when` que mente sobre o resultado, a tarefa sai do fluxo
padrão e roda sob demanda com `--tags upgrade`. O `changed_when: false`
continua ali para o caso de ela ser chamada junto de outras tags.

- [ ] **Step 6: Ligar a role, lint, executar duas vezes**

Em `fedora.yml`, após `repos`:

```yaml
    - { role: packages, tags: [packages] }
```

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags packages --check
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags packages
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags packages
```

Esperado na terceira: `changed=0`. O `--tags upgrade` não roda aqui: a
atualização geral leva `never` e é invocada à parte.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: role packages com os pacotes dnf da estação

Lista agrupada por finalidade em vars/fedora.yml.

A atualização geral do sistema leva a tag never: ela reporta mudança
sempre que há pacote novo no repositório, o que não é efeito do playbook.
Sai do fluxo padrão em vez de ser mascarada por um changed_when que
mentiria sobre o resultado.

Fora da lista: gemini-desktop, que não existe em repositório nenhum. É um
RPM sem assinatura, de vendor pessoa física, instalado à mão nesta máquina;
vai para a tabela de restauração manual do README."
```

---

### Task 4: Role `flatpak`

**Files:**
- Create: `roles/flatpak/tasks/main.yml`
- Modify: `group_vars/all.yml`
- Modify: `fedora.yml`

**Interfaces:**
- Consumes: pacote `flatpak`, instalado pela role `packages`.
- Produces: define `flatpak_apps` (lista de strings com application IDs) em
  `group_vars/all.yml`. A role é idêntica nas duas distribuições, por isso
  não tem arquivo por distro.

- [ ] **Step 1: Escrever o teste que falha**

Os sete já estão instalados aqui, então comparar contra o estado local não
testa nada. O que se testa é que os sete IDs existem no flathub — um ID
renomeado ou retirado só apareceria na hora de formatar:

```bash
podman run --rm fedora:43 bash -c '
  dnf install -y flatpak >/dev/null 2>&1
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  for id in com.mongodb.Compass com.moonlight_stream.Moonlight com.spotify.Client \
            io.dbeaver.DBeaverCommunity it.mijorus.gearlever org.ferdium.Ferdium \
            org.kde.yakuake; do
    printf "%-40s " "$id"
    flatpak remote-info flathub "$id" >/dev/null 2>&1 && echo OK || echo AUSENTE
  done
'
```

- [ ] **Step 2: Rodar e exigir OK nos sete**

Qualquer `AUSENTE` para a task: aquele application ID não existe mais no
flathub e precisa ser reencontrado antes de entrar na lista.

- [ ] **Step 3: Acrescentar a lista em `group_vars/all.yml`**

```yaml
flatpak_apps:
  - com.mongodb.Compass
  - com.moonlight_stream.Moonlight
  - com.spotify.Client
  - io.dbeaver.DBeaverCommunity
  - it.mijorus.gearlever
  - org.ferdium.Ferdium
  - org.kde.yakuake
```

- [ ] **Step 4: Criar `roles/flatpak/tasks/main.yml`**

```yaml
---
- name: Add flathub repository
  become: true
  community.general.flatpak_remote:
    name: flathub
    state: present
    flatpakrepo_url: https://dl.flathub.org/repo/flathub.flatpakrepo

- name: Install flatpak applications
  become: true
  community.general.flatpak:
    name: "{{ flatpak_apps }}"
    remote: flathub
    state: present
```

- [ ] **Step 5: Ligar a role, lint, executar duas vezes**

```yaml
    - { role: flatpak, tags: [flatpak] }
```

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags flatpak --check
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags flatpak
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags flatpak
```

Esperado na terceira: `changed=0`. Os sete estão em instalação `system`
nesta máquina, o que é o que o `become: true` da role produz — se você
removê-lo, os flatpaks passam a ser instalados por usuário e a role reporta
`changed` para sempre.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: role flatpak com o remote flathub e os sete aplicativos

Role sem variante por distribuição: flatpak se comporta igual nos dois
sistemas, então a lista mora em group_vars/all.yml.

Não replica o 'flatpak update' do playbook antigo: ele reportava mudança a
cada build novo no flathub, sem relação com o que o playbook faz."
```

---

### Task 5: Role `binaries`

**Files:**
- Create: `roles/binaries/tasks/main.yml`
- Create: `roles/binaries/tasks/aws_cli.yml`
- Create: `roles/binaries/tasks/fedora.yml`
- Create: `roles/binaries/tasks/debian.yml`
- Modify: `fedora.yml`

**Interfaces:**
- Consumes: `tmp_folder` e `target_user` de `group_vars/all.yml`.
- Produces: `/usr/local/bin/aws`, `/usr/local/bin/azcopy` e o pacote
  `session-manager-plugin`.

O diretório temporário é criado com `become` mas escrito sem, então precisa
de `owner: "{{ target_user }}"` — sem isso ele fica `root:root` e o `get_url`
seguinte, que roda como o usuário comum, falha com `EACCES`.

- [ ] **Step 1: Escrever o teste que falha**

`command -v` nesta máquina encontra os três e não prova nada. O teste é a
role inteira num container limpo:

```bash
podman run --rm -v "$PWD:/repo:ro,Z" -w /repo fedora:43 bash -c '
  dnf install -y ansible-core tar gzip unzip >/dev/null 2>&1
  ansible-playbook -i inventory/hosts.ini fedora.yml --tags binaries --connection=local
  aws --version && session-manager-plugin --version && azcopy --version
'
```

- [ ] **Step 2: Rodar e confirmar a falha**

Esperado antes da role existir: o playbook não executa nada e os três
comandos falham com `command not found`. É esse o vermelho que a role
precisa apagar.

- [ ] **Step 3: Criar `roles/binaries/tasks/main.yml`**

```yaml
---
- name: Create temporary download folder
  become: true
  ansible.builtin.file:
    path: "{{ tmp_folder }}"
    state: directory
    owner: "{{ target_user }}"
    mode: "0755"

- name: Install AWS CLI v2
  ansible.builtin.include_tasks: aws_cli.yml

- name: Include distribution specific binaries
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"

- name: Remove temporary download folder
  become: true
  ansible.builtin.file:
    path: "{{ tmp_folder }}"
    state: absent
```

- [ ] **Step 4: Criar `roles/binaries/tasks/aws_cli.yml`**

O instalador do AWS CLI não expõe estado consultável. Com `--update` ele é
seguro de reexecutar e imprime `Found same AWS CLI version: ... Skipping
install.` no stdout quando não há o que fazer — é essa string que dá a
idempotência. Sem `--update`, ele aborta com `Found preexisting AWS CLI
installation` no stderr.

```yaml
---
- name: Download AWS CLI v2
  ansible.builtin.get_url:
    url: https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
    dest: "{{ tmp_folder }}/awscliv2.zip"
    mode: "0644"

- name: Unpack AWS CLI v2
  ansible.builtin.unarchive:
    src: "{{ tmp_folder }}/awscliv2.zip"
    dest: "{{ tmp_folder }}"
    remote_src: true

- name: Install AWS CLI v2
  become: true
  ansible.builtin.command: "{{ tmp_folder }}/aws/install --update"
  register: binaries_aws_install
  changed_when: "'Skipping install' not in binaries_aws_install.stdout"
```

- [ ] **Step 5: Criar `roles/binaries/tasks/fedora.yml`**

```yaml
---
- name: Install session-manager-plugin
  become: true
  ansible.builtin.dnf5:
    name: https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
    state: present
    disable_gpg_check: true

- name: Download azcopy
  ansible.builtin.get_url:
    url: https://aka.ms/downloadazcopy-v10-linux
    dest: "{{ tmp_folder }}/azcopy.tar.gz"
    mode: "0644"

- name: Unpack azcopy
  ansible.builtin.unarchive:
    src: "{{ tmp_folder }}/azcopy.tar.gz"
    dest: "{{ tmp_folder }}"
    remote_src: true
    extra_opts:
      - --strip-components=1

- name: Install azcopy
  become: true
  ansible.builtin.copy:
    src: "{{ tmp_folder }}/azcopy"
    dest: /usr/local/bin/azcopy
    mode: "0755"
    remote_src: true
```

- [ ] **Step 6: Criar `roles/binaries/tasks/debian.yml`**

O bloco de azcopy é idêntico ao do Fedora e é repetido de propósito: extrair
para um terceiro arquivo economizaria seis linhas e custaria um nível de
indireção em cima da única diferença real entre as duas distribuições, que é
o pacote do session-manager-plugin.

```yaml
---
- name: Install session-manager-plugin
  become: true
  ansible.builtin.apt:
    deb: https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb

- name: Download azcopy
  ansible.builtin.get_url:
    url: https://aka.ms/downloadazcopy-v10-linux
    dest: "{{ tmp_folder }}/azcopy.tar.gz"
    mode: "0644"

- name: Unpack azcopy
  ansible.builtin.unarchive:
    src: "{{ tmp_folder }}/azcopy.tar.gz"
    dest: "{{ tmp_folder }}"
    remote_src: true
    extra_opts:
      - --strip-components=1

- name: Install azcopy
  become: true
  ansible.builtin.copy:
    src: "{{ tmp_folder }}/azcopy"
    dest: /usr/local/bin/azcopy
    mode: "0755"
    remote_src: true
```

- [ ] **Step 7: Ligar a role, lint, executar duas vezes**

```yaml
    - { role: binaries, tags: [binaries] }
```

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags binaries --check
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags binaries
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags binaries
```

Esperado na terceira: `changed=0` nas tarefas de instalação, incluindo
`Install AWS CLI v2` — se ela reportar `changed`, o `changed_when` está
testando a string errada; confira a saída real com `-v`. `get_url` e
`unarchive` reportam mudança porque o diretório temporário é apagado ao fim
de cada execução; isso é esperado e não conta para o critério.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: role binaries com AWS CLI, session-manager-plugin e azcopy

O session-manager-plugin vem do pacote oficial da AWS nas duas
distribuições. A chave GPG do SSM Agent que existia no repositório era de
outro produto e estava expirada desde fevereiro de 2025.

O instalador do AWS CLI não expõe estado consultável; a idempotência vem
de --update mais changed_when sobre 'Skipping install', que é o que o
instalador realmente imprime quando não há o que fazer.

O diretório temporário é criado com owner do usuário alvo: criado por root
e escrito sem become, ele quebrava com EACCES em qualquer máquina."
```

---

### Task 6: Role `system_config`

**Files:**
- Create: `roles/system_config/tasks/main.yml`
- Modify: `fedora.yml`

**Interfaces:**
- Consumes: `target_user` de `group_vars/all.yml`; pacotes `docker-ce` e
  `anydesk` da role `packages`.
- Produces: usuário nos grupos `wheel` e `docker`, serviços habilitados.

- [ ] **Step 1: Escrever o teste que falha**

```bash
id -nG | tr ' ' '\n' | grep -x docker
systemctl is-enabled docker.service anydesk.service
```

- [ ] **Step 2: Rodar e confirmar**

Esperado nesta máquina: `docker` aparece nos grupos e os dois serviços saem
`enabled`.

- [ ] **Step 3: Criar `roles/system_config/tasks/main.yml`**

```yaml
---
- name: Add user to system groups
  become: true
  ansible.builtin.user:
    name: "{{ target_user }}"
    groups:
      - wheel
      - docker
    append: true

- name: Enable system services
  become: true
  ansible.builtin.systemd_service:
    name: "{{ item }}"
    enabled: true
    state: started
  loop:
    - docker.service
    - anydesk.service
```

- [ ] **Step 4: Ligar a role, lint, executar duas vezes**

```yaml
    - { role: system_config, tags: [system_config] }
```

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags system_config --check
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags system_config
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags system_config
```

Esperado na terceira: `changed=0`.

Nota para o README: entrar no grupo `docker` só vale a partir de um novo
login. Na máquina recém-provisionada, `docker ps` falha com permissão negada
até o usuário deslogar e logar de novo.

- [ ] **Step 5: Verificar firewalld antes de fechar a task**

A spec deixou isso em aberto porque o levantamento não tinha sudo. Rode:

```bash
sudo firewall-cmd --list-all
```

Se houver porta ou serviço aberto além do padrão (`dhcpv6-client`, `mdns`,
`samba-client`, `ssh`), acrescente uma tarefa `ansible.posix.firewalld` para
cada, declare `ansible.posix` em `collections/requirements.yml` e repita o
Step 4. Se não houver, registre no commit que não há regra personalizada.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: role system_config com grupos e serviços

Usuário em wheel e docker; docker.service e anydesk.service habilitados.

<Escreva aqui o resultado real do Step 5, uma das duas linhas:>
<  'Firewalld verificado: sem regra personalizada além do padrão da zona.'>
<  'Firewalld: versiona as regras X e Y, encontradas fora do padrão.'>"
```

---

### Task 7: Role `dotfiles`

**Files:**
- Create: `roles/dotfiles/tasks/main.yml`
- Create: `files/dotfiles/bashrc`
- Create: `files/dotfiles/bash_profile`
- Create: `files/dotfiles/gitconfig`
- Create: `files/dotfiles/ssh_config`
- Modify: `group_vars/all.yml`
- Modify: `fedora.yml`

**Interfaces:**
- Consumes: `target_home` de `group_vars/all.yml`.
- Produces: define `dotfiles` (lista de dicts com `src`, `dest`, `mode`) em
  `group_vars/all.yml`.

- [ ] **Step 1: Escrever o teste que falha**

O teste é a varredura por credencial, que precisa sair vazia antes de qualquer
arquivo entrar no repositório:

```bash
grep -rniE 'token|secret|password|BEGIN [A-Z ]*PRIVATE KEY|whsec_|ghp_|gho_|AKIA' files/dotfiles/
```

- [ ] **Step 2: Rodar e confirmar**

Esperado antes de copiar: `grep: files/dotfiles/: No such file or directory`.
Depois do Step 3, esperado: saída vazia, código de saída 1. Se qualquer linha
aparecer, **pare** — remova o trecho do arquivo antes de seguir.

- [ ] **Step 3: Copiar os dotfiles para o repositório**

Os nomes perdem o ponto inicial para não ficarem ocultos no repositório; o
destino real é reposto pela role.

```bash
mkdir -p files/dotfiles
cp ~/.bashrc        files/dotfiles/bashrc
cp ~/.bash_profile  files/dotfiles/bash_profile
cp ~/.gitconfig     files/dotfiles/gitconfig
cp ~/.ssh/config    files/dotfiles/ssh_config
```

Rode o `grep` do Step 1 agora e confirme a saída vazia.

- [ ] **Step 4: Tirar o caminho fixo e o lixo de sessão**

Os arquivos de origem trazem `/home/nuvidio` literal e uma variável de
sessão morta. Versionados como estão, contradizem o objetivo de servir outra
máquina sem edição — o mesmo motivo pelo qual a role `gather` usa
`target_home`.

Em `files/dotfiles/bash_profile` linha 12 e `files/dotfiles/bashrc` linha 35,
troque:

```bash
export PATH="/home/nuvidio/.local/bin:$PATH"
```

por:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

E remova por inteiro a linha 37 de `files/dotfiles/bashrc`, que exporta um
`SCRATCH` apontando para um diretório de scratchpad de sessão que não existe
mais:

```bash
export SCRATCH=/tmp/claude-1000/-home-nuvidio-git-homelab/834778d3-.../scratchpad/coleta
```

Confirme que não sobrou nenhum caminho absoluto do home:

```bash
grep -n '/home/nuvidio' files/dotfiles/
```

Esperado: saída vazia.

- [ ] **Step 5: Revisar `files/dotfiles/gitconfig` à mão**

Abra o arquivo. Ele contém `credential.https://github.com.helper=!/usr/bin/gh
auth git-credential`, que é um comando, não um token — pode ficar. Confirme
que não há `[user] signingkey` apontando para caminho de chave privada nem
nenhum valor literal de credencial.

- [ ] **Step 6: Acrescentar a lista em `group_vars/all.yml`**

```yaml
dotfiles:
  - src: bashrc
    dest: "{{ target_home }}/.bashrc"
    mode: "0644"
  - src: bash_profile
    dest: "{{ target_home }}/.bash_profile"
    mode: "0644"
  - src: gitconfig
    dest: "{{ target_home }}/.gitconfig"
    mode: "0644"
  - src: ssh_config
    dest: "{{ target_home }}/.ssh/config"
    mode: "0600"
```

- [ ] **Step 7: Criar `roles/dotfiles/tasks/main.yml`**

`~/.ssh` precisa existir com 0700 antes do `config` ser escrito, senão o
cliente SSH recusa a configuração. `~/.aws` é criado vazio de propósito: o
`credentials` fica de fora e é restaurado à mão.

```yaml
---
- name: Create directories that hold credentials
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: directory
    mode: "{{ item.mode }}"
  loop:
    - { path: "{{ target_home }}/.ssh", mode: "0700" }
    - { path: "{{ target_home }}/.aws", mode: "0700" }
  loop_control:
    label: "{{ item.path }}"

- name: Install dotfiles
  ansible.builtin.copy:
    src: "dotfiles/{{ item.src }}"
    dest: "{{ item.dest }}"
    mode: "{{ item.mode }}"
    backup: true
  loop: "{{ dotfiles }}"
  loop_control:
    label: "{{ item.dest }}"
```

- [ ] **Step 8: Ligar a role, lint, executar duas vezes**

```yaml
    - { role: dotfiles, tags: [dotfiles] }
```

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --tags dotfiles --check
ansible-playbook -i inventory/hosts.ini fedora.yml --tags dotfiles
ansible-playbook -i inventory/hosts.ini fedora.yml --tags dotfiles
```

Esperado na terceira: `changed=0`. Esta role não precisa de
`--ask-become-pass`.

⚠️ Antes de commitar, note que `files/dotfiles/ssh_config` versiona
`Host 192.168.100.*` — a faixa de rede interna do homelab. É topologia de
rede num repositório. Risco baixo num repositório privado, mas se preferir
não registrar a faixa, generalize a entrada ou mova esse bloco para um
arquivo fora do versionamento.

- [ ] **Step 9: Confirmar que o SSH continua funcionando**

```bash
ssh -T git@github.com-personal
```

Esperado: `Hi gleitoncampos! You've successfully authenticated`. Se falhar,
compare `~/.ssh/config` com o backup que o `backup: true` deixou ao lado.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: role dotfiles com shell, git e cliente SSH

Quatro arquivos, todos varridos por token, secret, password e cabeçalho de
chave privada antes de entrar no repositório.

Cria ~/.ssh em 0700 e ~/.aws vazio: a configuração é versionada, as
credenciais não. O helper do git é um comando do gh, não um token.

/home/nuvidio literal vira \$HOME, e sai um SCRATCH que apontava para um
diretório de sessão morto."
```

---

### Task 8: Migrar os scripts do Gather e ler o segredo de `$CREDENTIALS_DIRECTORY`

**Files:**
- Create: `files/gather/gather_webhook.mjs`
- Create: `files/gather/gather_ci_status.mjs`
- Create: `files/gather/gather_ci_status_cron.sh`
- Create: `files/gather/gather_claude_status.mjs`
- Create: `files/gather/gather_prs.mjs`
- Create: `files/gather/gather_prs_cron.sh`
- Create: `files/gather/gather_webhook.test.mjs`

**Interfaces:**
- Consumes: nada do Ansible; é mudança de código Node.
- Produces: `loadSecret(envVar, credName)` em `gather_webhook.mjs`, com a
  assinatura `(envVar: string, credName?: string) => Buffer`. A role `gather`
  da Task 9 depende dos nomes de credencial `gather_claude`, `gather_status`
  e `gather_webhook`.

- [ ] **Step 1: Copiar os seis arquivos para o repositório**

```bash
mkdir -p files/gather
cp /home/nuvidio/nuvidio/temp_scripts/gather_webhook.mjs       files/gather/
cp /home/nuvidio/nuvidio/temp_scripts/gather_ci_status.mjs     files/gather/
cp /home/nuvidio/nuvidio/temp_scripts/gather_ci_status_cron.sh files/gather/
cp /home/nuvidio/nuvidio/temp_scripts/gather_claude_status.mjs files/gather/
cp /home/nuvidio/nuvidio/temp_scripts/gather_prs.mjs           files/gather/
cp /home/nuvidio/nuvidio/temp_scripts/gather_prs_cron.sh       files/gather/
grep -rniE 'whsec_[A-Za-z0-9+/=]|ghp_|gho_|AKIA' files/gather/
```

O `grep` precisa sair vazio. As URLs de Smart Object do Gather que aparecem
nos arquivos são endpoints, não segredos — a autenticação é a assinatura HMAC.

- [ ] **Step 2: Escrever o teste que falha**

Crie `files/gather/gather_webhook.test.mjs`. O segredo do teste é gerado na
hora, nunca fixo:

```javascript
import { test } from "node:test"
import assert from "node:assert/strict"
import { mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { randomBytes } from "node:crypto"
import { loadSecret } from "./gather_webhook.mjs"

const fakeSecret = () => "whsec_" + randomBytes(24).toString("base64")

test("lê o segredo de CREDENTIALS_DIRECTORY quando ele existe", () => {
  const dir = mkdtempSync(join(tmpdir(), "cred-"))
  const secret = fakeSecret()
  writeFileSync(join(dir, "gather_status"), secret + "\n")
  process.env.CREDENTIALS_DIRECTORY = dir
  delete process.env.GATHER_STATUS_SECRET

  const key = loadSecret("GATHER_STATUS_SECRET", "gather_status")
  assert.ok(Buffer.isBuffer(key))
  assert.ok(key.length >= 16)
})

test("cai na variável de ambiente quando não há credencial", () => {
  delete process.env.CREDENTIALS_DIRECTORY
  process.env.GATHER_STATUS_SECRET = fakeSecret()

  const key = loadSecret("GATHER_STATUS_SECRET", "gather_status")
  assert.ok(Buffer.isBuffer(key))
})

test("a credencial tem precedência sobre a variável de ambiente", () => {
  const dir = mkdtempSync(join(tmpdir(), "cred-"))
  const fromFile = fakeSecret()
  writeFileSync(join(dir, "gather_status"), fromFile + "\n")
  process.env.CREDENTIALS_DIRECTORY = dir
  process.env.GATHER_STATUS_SECRET = fakeSecret()

  const key = loadSecret("GATHER_STATUS_SECRET", "gather_status")
  const expected = Buffer.from(fromFile.slice("whsec_".length), "base64")
  assert.deepEqual(key, expected)
})

test("erra quando não há nem credencial nem variável", () => {
  delete process.env.CREDENTIALS_DIRECTORY
  delete process.env.GATHER_STATUS_SECRET

  assert.throws(() => loadSecret("GATHER_STATUS_SECRET", "gather_status"), /ausente/)
})
```

- [ ] **Step 3: Rodar o teste e confirmar que falha**

No Node 22 o argumento posicional de `--test` é arquivo ou glob, não
diretório a varrer; `node --test files/gather/` falha com `MODULE_NOT_FOUND`.

```bash
node --test 'files/gather/*.test.mjs'
```

Esperado: os testes 1 e 3 falham, porque `loadSecret` ainda ignora
`CREDENTIALS_DIRECTORY` e só lê a variável de ambiente.

- [ ] **Step 4: Alterar `loadSecret` em `files/gather/gather_webhook.mjs`**

Substitua o import e a função. O import atual é
`import { createHmac, randomUUID } from "node:crypto"`.

```javascript
import { createHmac, randomUUID } from "node:crypto"
import { readFileSync } from "node:fs"
import { join } from "node:path"

// O systemd monta as credenciais de LoadCredential= num tmpfs 0400 e exporta
// o diretório aqui. Preferimos esse caminho à variável de ambiente: o valor
// não entra no ambiente do processo, logo não vaza por /proc/<pid>/environ
// nem por core dump.
function readCredential(name) {
  const dir = process.env.CREDENTIALS_DIRECTORY
  if (!dir || !name) return null
  try {
    return readFileSync(join(dir, name), "utf8").trim()
  } catch {
    return null
  }
}

export function loadSecret(envVar = "GATHER_WEBHOOK_SECRET", credName = null) {
  // A variável de ambiente continua valendo para execução manual no terminal.
  const secret = readCredential(credName) ?? process.env[envVar]
  if (!secret || !secret.startsWith("whsec_")) {
    throw new Error(`${envVar} ausente ou não começa com 'whsec_'.`)
  }
  const key = Buffer.from(secret.slice("whsec_".length), "base64")
  if (key.length < 16) throw new Error(`${envVar} parece truncado.`)
  return key
}
```

- [ ] **Step 5: Rodar o teste e confirmar que passa**

```bash
node --test 'files/gather/*.test.mjs'
```

Esperado: `pass 4`, `fail 0`.

- [ ] **Step 6: Passar o nome da credencial nos dois chamadores existentes**

Em `files/gather/gather_ci_status.mjs`, linha 173:

```javascript
const key = loadSecret("GATHER_STATUS_SECRET", "gather_status")
```

Em `files/gather/gather_claude_status.mjs`, linha 218:

```javascript
const key = loadSecret("GATHER_CLAUDE_SECRET", "gather_claude")
```

- [ ] **Step 7: Fazer `gather_prs.mjs` usar o módulo compartilhado**

Este arquivo duplica a lógica em vez de importar `loadSecret`. Substitua o
bloco das linhas 23 a 32:

```javascript
const secret = process.env.GATHER_WEBHOOK_SECRET
if (!secret || !secret.startsWith("whsec_")) {
  console.error("ERRO: GATHER_WEBHOOK_SECRET ausente ou não começa com 'whsec_'.")
  process.exit(1)
}
const key = Buffer.from(secret.slice("whsec_".length), "base64")
if (key.length < 16) {
  console.error("ERRO: segredo parece truncado (chave decodificada muito curta).")
  process.exit(1)
}
```

por:

```javascript
let key
try {
  key = loadSecret("GATHER_WEBHOOK_SECRET", "gather_webhook")
} catch (err) {
  console.error(`ERRO: ${err.message}`)
  process.exit(1)
}
```

E acrescente `loadSecret` ao import, que hoje é
`import { createHmac, randomUUID } from "node:crypto"`:

```javascript
import { loadSecret } from "./gather_webhook.mjs"
```

Confira se `createHmac` e `randomUUID` continuam sendo usados no arquivo; se
a assinatura passou a vir de `createSender`, remova o import morto.

- [ ] **Step 8: Tirar a montagem do segredo dos dois `.sh`**

Em `files/gather/gather_ci_status_cron.sh`, o `SCRIPT_DIR` fixo em
`/home/nuvidio/` sai, o bloco do `SECRET_FILE` sai e o fallback de `GH_TOKEN`
sai — `~/.gh_token` não existe na máquina e o `gh` já resolve pelo keyring.
O arquivo passa a ser:

```bash
#!/usr/bin/env bash
# Atualiza o Smart Object "Bot Status Monitor" com a saúde dos deploys.
# Rodado de 10 em 10 minutos pelo systemd user timer `gather-ci-status.timer`.
# O segredo chega por LoadCredential=, lido pelo .mjs em $CREDENTIALS_DIRECTORY.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== $(date -Is) ==="

node "$SCRIPT_DIR/gather_ci_status.mjs" "$@"
```

E `files/gather/gather_prs_cron.sh`:

```bash
#!/usr/bin/env bash
# Atualiza o Smart Object "PRs" do Gather com os PRs abertos de minha autoria.
# Rodado de hora em hora pelo systemd user timer `gather-prs.timer`.
# O segredo chega por LoadCredential=, lido pelo .mjs em $CREDENTIALS_DIRECTORY.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local/state/gather-prs"
PRS="$STATE_DIR/prs.json"

mkdir -p "$STATE_DIR"
echo "=== $(date -Is) ==="

# Escreve em .tmp e só promove no sucesso, pra não deixar um prs.json truncado.
gh search prs --author "@me" --state open --limit 1000 \
  --json repository,number,title,url,updatedAt,isDraft >"$PRS.tmp"
mv "$PRS.tmp" "$PRS"
echo "PRs abertos: $(jq length "$PRS")"

node "$SCRIPT_DIR/gather_prs.mjs" "$PRS"
```

- [ ] **Step 9: Verificar os dois caminhos à mão**

Primeiro pela variável de ambiente, que precisa continuar funcionando:

```bash
GATHER_STATUS_SECRET="$(cat ~/.gather_status_secret)" \
  node files/gather/gather_ci_status.mjs --dry-run
```

Depois simulando o systemd:

```bash
CRED=$(mktemp -d) && install -m 0400 ~/.gather_status_secret "$CRED/gather_status"
CREDENTIALS_DIRECTORY="$CRED" node files/gather/gather_ci_status.mjs --dry-run
rm -rf "$CRED"
```

Esperado nos dois: o script chega ao `--dry-run` sem erro de segredo.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: versiona os scripts do Gather e lê o segredo do systemd

Os seis arquivos viviam em temp_scripts, fora de qualquer repositório: uma
formatação os perdia e as units voltariam apontando para o vazio.

loadSecret passa a ler \$CREDENTIALS_DIRECTORY, alimentado por
LoadCredential=. O systemd monta o arquivo num tmpfs 0400 visível só ao
serviço, então o segredo deixa de existir no ambiente do processo, onde era
legível por /proc/<pid>/environ e por core dump. A variável de ambiente
segue valendo para execução manual.

gather_prs.mjs duplicava o parse do segredo; passa a usar loadSecret.

Os dois .sh perdem o SCRIPT_DIR fixo em /home/nuvidio e o fallback de
GH_TOKEN a partir de ~/.gh_token, arquivo que não existe e que só serviria
para trazer um token em texto plano de volta ao home."
```

---

### Task 9: Role `gather`

**Files:**
- Create: `roles/gather/tasks/main.yml`
- Create: `roles/gather/handlers/main.yml`
- Create: `roles/gather/templates/gather-claude-status.service.j2`
- Create: `roles/gather/templates/gather-ci-status.service.j2`
- Create: `roles/gather/templates/gather-ci-status.timer.j2`
- Create: `roles/gather/templates/gather-prs.service.j2`
- Create: `roles/gather/templates/gather-prs.timer.j2`
- Modify: `group_vars/all.yml`
- Modify: `fedora.yml`

**Interfaces:**
- Consumes: `target_home`; `loadSecret(envVar, credName)` da Task 8; os nomes
  de credencial `gather_claude`, `gather_status`, `gather_webhook`.
- Produces: define `gather_dir` (`{{ target_home }}/.local/share/gather`) e
  `gather_cred_dir` (`{{ target_home }}/.config/gather`) em `group_vars/all.yml`.

- [ ] **Step 1: Escrever o teste que falha**

```bash
systemctl --user cat gather-claude-status.service | grep -q LoadCredential
```

- [ ] **Step 2: Rodar e confirmar a falha**

Esperado: código de saída 1. A unit atual monta o segredo por variável de
ambiente e não tem `LoadCredential`.

- [ ] **Step 3: Acrescentar as variáveis em `group_vars/all.yml`**

```yaml
gather_dir: "{{ target_home }}/.local/share/gather"
gather_cred_dir: "{{ target_home }}/.config/gather"

# nome do arquivo em gather_cred_dir -> nome da credencial exposta ao serviço
gather_credentials:
  - { file: claude, name: gather_claude }
  - { file: status, name: gather_status }
  - { file: webhook, name: gather_webhook }
```

- [ ] **Step 4: Criar `roles/gather/templates/gather-claude-status.service.j2`**

```jinja
[Unit]
Description=Reflete o uso do Claude Code num Smart Object do Gather
After=network-online.target
# Sem segredo preenchido o serviço não sobe, em vez de reiniciar em laço.
ConditionFileNotEmpty={{ gather_cred_dir }}/claude
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
# O segredo entra por LoadCredential: o systemd o monta num tmpfs 0400
# visível só a este serviço e exporta o diretório em $CREDENTIALS_DIRECTORY.
# Nunca pela linha de comando (visível em ps) nem pelo ambiente (legível em
# /proc/<pid>/environ).
LoadCredential=gather_claude:{{ gather_cred_dir }}/claude
ExecStart=/usr/bin/node {{ gather_dir }}/gather_claude_status.mjs
Restart=always
RestartSec=15

[Install]
WantedBy=default.target
```

`ConditionFileNotEmpty` é o que impede um laço de reinício em máquina
recém-provisionada: a role cria os arquivos de credencial vazios, e
`LoadCredential` aceita arquivo de zero byte sem reclamar. Sem a condição, o
`loadSecret` lançaria, o `Restart=always` reiniciaria a cada 15 segundos, e o
handler de restart falharia junto, derrubando a execução do playbook. Com
ela, o systemd apenas não inicia o serviço e registra a condição não
satisfeita. `StartLimitBurst` é a segunda barreira, para o caso de o serviço
falhar por outro motivo.

- [ ] **Step 5: Criar `roles/gather/templates/gather-ci-status.service.j2`**

```jinja
[Unit]
Description=Atualiza o Smart Object "Bot Status Monitor" com a saúde dos deploys (GitHub Actions)
After=network-online.target
ConditionFileNotEmpty={{ gather_cred_dir }}/status

[Service]
Type=oneshot
LoadCredential=gather_status:{{ gather_cred_dir }}/status
ExecStart={{ gather_dir }}/gather_ci_status_cron.sh
# Varredura de ~30 repos com concorrência 6, mais o envio throttled a 1 req/s.
TimeoutStartSec=300
```

- [ ] **Step 6: Criar `roles/gather/templates/gather-prs.service.j2`**

```jinja
[Unit]
Description=Atualiza o Smart Object "PRs" do Gather com os PRs abertos no GitHub
After=network-online.target
ConditionFileNotEmpty={{ gather_cred_dir }}/webhook

[Service]
Type=oneshot
LoadCredential=gather_webhook:{{ gather_cred_dir }}/webhook
ExecStart={{ gather_dir }}/gather_prs_cron.sh
# O envio faz ~24 requests a ~1 req/s (rate limit do space): ~30s. Margem folgada.
TimeoutStartSec=300
```

- [ ] **Step 7: Criar os dois timers**

`roles/gather/templates/gather-ci-status.timer.j2`:

```jinja
[Unit]
Description=Atualiza o indicador de saúde dos deploys a cada 10 minutos

[Timer]
OnCalendar=*:0/10
# Sem Persistent: estado atrasado não tem valor, o próximo ciclo já corrige.
RandomizedDelaySec=60
Unit=gather-ci-status.service

[Install]
WantedBy=timers.target
```

`roles/gather/templates/gather-prs.timer.j2`:

```jinja
[Unit]
Description=Atualiza o Smart Object "PRs" do Gather de hora em hora

[Timer]
OnCalendar=hourly
# Roda logo após o boot/login se a hora cheia passou com a máquina desligada.
Persistent=true
# Espalha o disparo pra não bater sempre no mesmo segundo da hora cheia.
RandomizedDelaySec=120
Unit=gather-prs.service

[Install]
WantedBy=timers.target
```

- [ ] **Step 8: Criar `roles/gather/tasks/main.yml`**

Os arquivos de credencial são criados vazios com `force: false`, para que uma
reexecução nunca sobrescreva um segredo já preenchido à mão.

```yaml
---
- name: Create Gather directories
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: directory
    mode: "{{ item.mode }}"
  loop:
    - { path: "{{ gather_dir }}", mode: "0755" }
    - { path: "{{ gather_cred_dir }}", mode: "0700" }
    - { path: "{{ target_home }}/.config/systemd/user", mode: "0755" }
  loop_control:
    label: "{{ item.path }}"

- name: Install Gather scripts
  ansible.builtin.copy:
    src: "gather/{{ item }}"
    dest: "{{ gather_dir }}/{{ item }}"
    mode: "{{ '0755' if item.endswith('.sh') else '0644' }}"
  loop:
    - gather_webhook.mjs
    - gather_ci_status.mjs
    - gather_ci_status_cron.sh
    - gather_claude_status.mjs
    - gather_prs.mjs
    - gather_prs_cron.sh
  notify: Restart gather claude status

- name: Create empty credential files
  ansible.builtin.copy:
    content: ""
    dest: "{{ gather_cred_dir }}/{{ item.file }}"
    mode: "0600"
    force: false
  loop: "{{ gather_credentials }}"
  loop_control:
    label: "{{ item.file }}"

- name: Install systemd user units
  ansible.builtin.template:
    src: "{{ item }}.j2"
    dest: "{{ target_home }}/.config/systemd/user/{{ item }}"
    mode: "0644"
  loop:
    - gather-claude-status.service
    - gather-ci-status.service
    - gather-ci-status.timer
    - gather-prs.service
    - gather-prs.timer
  notify:
    - Reload systemd user daemon
    - Restart gather claude status

- name: Enable and start Gather units
  ansible.builtin.systemd_service:
    name: "{{ item }}"
    scope: user
    enabled: true
    state: started
    daemon_reload: true
  loop:
    - gather-claude-status.service
    - gather-ci-status.timer
    - gather-prs.timer
```

Duas escolhas que parecem detalhe e não são. Alterar um template notifica os
dois handlers, não só o reload: sem o restart, o serviço em execução continua
rodando a unit antiga até o próximo boot. E `state: started` junto de
`enabled: true` porque `enabled` sozinho deixa os timers habilitados mas
parados até o próximo login — numa máquina recém-provisionada nada dispararia,
e o `list-timers` do Step 12 mostraria `n/a`.

- [ ] **Step 9: Criar `roles/gather/handlers/main.yml`**

```yaml
---
- name: Reload systemd user daemon
  ansible.builtin.systemd_service:
    scope: user
    daemon_reload: true

- name: Restart gather claude status
  ansible.builtin.systemd_service:
    name: gather-claude-status.service
    scope: user
    state: restarted
```

- [ ] **Step 10: Preencher os segredos à mão**

O playbook cria os arquivos vazios; o conteúdo vem dos arquivos antigos do
home, que depois somem:

```bash
install -m 0600 ~/.gather_claude_secret  ~/.config/gather/claude
install -m 0600 ~/.gather_status_secret  ~/.config/gather/status
install -m 0600 ~/.gather_webhook_secret ~/.config/gather/webhook
```

- [ ] **Step 11: Ligar a role, lint, executar duas vezes**

```yaml
    - { role: gather, tags: [gather] }
```

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --tags gather
ansible-playbook -i inventory/hosts.ini fedora.yml --tags gather
```

Esperado na segunda: `changed=0`.

- [ ] **Step 12: Verificar as cinco units em execução**

```bash
systemctl --user cat gather-claude-status.service | grep LoadCredential
systemctl --user status gather-claude-status.service
systemctl --user start gather-ci-status.service && systemctl --user status gather-ci-status.service
systemctl --user list-timers 'gather-*'
journalctl --user -u gather-ci-status.service -n 30 --no-pager
```

Esperado: `LoadCredential=gather_status:...` presente; o serviço oneshot
termina com `status=0/SUCCESS`; o log não traz "ausente ou não começa com
'whsec_'"; os dois timers aparecem com próximo disparo agendado.

Se algum serviço reportar `ConditionFileNotEmpty=... was not met`, o segredo
correspondente não foi preenchido no Step 10 — preencha e repita. Esse é o
comportamento correto: o serviço se recusa a subir em vez de reiniciar em
laço.

- [ ] **Step 13: Remover os arquivos de segredo antigos do home**

Só depois que o Step 12 passou:

```bash
shred -u ~/.gather_claude_secret ~/.gather_status_secret ~/.gather_webhook_secret
```

- [ ] **Step 14: Commit**

```bash
git add -A
git commit -m "feat: role gather com as cinco units e LoadCredential

Units viram templates: o caminho dos scripts deixa de ser /home/nuvidio
fixo e passa a sair de gather_dir, então o repositório serve outra máquina
sem edição.

Os três segredos saem soltos do home e vão para ~/.config/gather em 0700,
criados vazios com force: false para que reexecução não sobrescreva o
conteúdo preenchido à mão."
```

---

### Task 10: Role `hardware`

**Files:**
- Create: `roles/hardware/tasks/main.yml`
- Create: `roles/hardware/tasks/fedora.yml`
- Modify: `vars/fedora.yml`
- Modify: `fedora.yml`

**Interfaces:**
- Consumes: nada das roles anteriores.
- Produces: define `hardware_packages` (lista de strings) em `vars/fedora.yml`.
  A role só roda com `--tags hardware`; nunca no fluxo padrão.

- [ ] **Step 1: Escrever o teste que falha**

O comportamento a garantir é que a role **não** rode sem a tag. Note que
`grep nvidia` aqui seria um no-op: `--list-tasks` não expande `include_tasks`,
então o nome das tarefas de dentro do arquivo por distribuição nunca aparece,
com ou sem a tag. O que aparece é o nome da role:

```bash
ansible-playbook -i inventory/hosts.ini fedora.yml --list-tasks | grep -c hardware
```

- [ ] **Step 2: Rodar e confirmar**

Esperado antes: `0`, porque a role ainda não existe. Depois do Step 6, este
mesmo comando deve continuar retornando `0`, e a variante com
`--tags hardware` deve retornar mais que zero.

- [ ] **Step 3: Acrescentar a lista em `vars/fedora.yml`**

```yaml
hardware_packages:
  # Placa nvidia
  - akmod-nvidia
  - xorg-x11-drv-nvidia-cuda
  # Convidado de VM
  - virtualbox-guest-additions
  # Periférico Logitech Unifying
  - solaar
  - solaar-udev
  # Console serial
  - minicom
```

- [ ] **Step 4: Criar `roles/hardware/tasks/main.yml`**

```yaml
---
- name: Include distribution specific hardware packages
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

- [ ] **Step 5: Criar `roles/hardware/tasks/fedora.yml`**

O repositório nvidia mora aqui, não na role `repos`: assim uma execução sem a
tag não deixa repositório sem uso em `/etc/yum.repos.d`.

```yaml
---
- name: Add RPM Fusion nvidia driver repository
  become: true
  ansible.builtin.dnf5:
    name: "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-{{ ansible_distribution_major_version }}.noarch.rpm"
    state: present
    disable_gpg_check: true

- name: Install hardware specific packages
  become: true
  ansible.builtin.dnf5:
    name: "{{ hardware_packages }}"
    state: present
```

- [ ] **Step 6: Ligar a role com a tag e `never`**

`never` garante que a role só entre quando a tag é pedida explicitamente:

```yaml
    - { role: hardware, tags: [hardware, never] }
```

- [ ] **Step 7: Confirmar os dois modos**

```bash
ansible-playbook -i inventory/hosts.ini fedora.yml --list-tasks | grep -c hardware
ansible-playbook -i inventory/hosts.ini fedora.yml --list-tasks --tags hardware | grep -c hardware
```

Esperado: `0` no primeiro, número maior que zero no segundo. A tag da role se
propaga para as tarefas que o `include_tasks` traz, então declarar a tag uma
vez na role basta — não é preciso repeti-la dentro de `fedora.yml`.

- [ ] **Step 8: Lint e execução com a tag, duas vezes**

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags hardware --check
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags hardware
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags hardware
```

Esperado na terceira: `changed=0`.

Esta role não ganha step de container: `akmod-nvidia` compila contra o kernel
do host e `virtualbox-guest-additions` só faz sentido dentro de uma VM.
Validar em container daria um falso negativo, não um sinal.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: role hardware isolada por tag

nvidia, virtualbox-guest-additions, solaar e minicom só entram com
--tags hardware; a role leva 'never' para não rodar por engano. O
repositório nvidia acompanha os pacotes, em vez de ficar na role repos
sujando /etc/yum.repos.d de quem nunca usa a tag.

Fora da lista: openscad, que nunca esteve instalado (o pacote presente é
opensc, middleware de smartcard), e camset, que é binário Python em
~/.local/bin e não pacote do sistema."
```

---

### Task 11: Playbook do Ubuntu

**Files:**
- Create: `ubuntu.yml`
- Create: `vars/ubuntu.yml`
- Create: `roles/repos/tasks/debian.yml`
- Create: `roles/packages/tasks/debian.yml`
- Create: `roles/hardware/tasks/debian.yml`

**Interfaces:**
- Consumes: todas as roles das tasks 2 a 10.
- Produces: `vars/ubuntu.yml` com as mesmas chaves de `vars/fedora.yml`
  (`system_packages`, `hardware_packages`) mais `apt_repositories` (lista de
  dicts com `name`, `repo`, `key_url`).

- [ ] **Step 1: Escrever o teste que falha**

```bash
ansible-playbook -i inventory/hosts.ini ubuntu.yml --syntax-check
```

- [ ] **Step 2: Rodar e confirmar a falha**

Esperado: `ERROR! the playbook: ubuntu.yml could not be found`.

- [ ] **Step 3: Criar `vars/ubuntu.yml`**

```yaml
---
apt_repositories:
  - name: docker
    repo: "deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
    key_url: https://download.docker.com/linux/ubuntu/gpg

  - name: google-chrome
    repo: "deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main"
    key_url: https://dl.google.com/linux/linux_signing_key.pub

  - name: vscode
    repo: "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main"
    key_url: https://packages.microsoft.com/keys/microsoft.asc

  # A chave do gh é keyring binário, não armored. O apt decide o formato pela
  # extensão do arquivo, então esta entrada precisa terminar em .gpg — salva
  # como .asc, o apt rejeita o repositório.
  - name: github-cli
    ext: gpg
    repo: "deb [arch=amd64] https://cli.github.com/packages stable main"
    key_url: https://cli.github.com/packages/githubcli-archive-keyring.gpg

  - name: azure-cli
    repo: "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli {{ ansible_distribution_release }} main"
    key_url: https://packages.microsoft.com/keys/microsoft.asc

  - name: hashicorp
    repo: "deb [arch=amd64] https://apt.releases.hashicorp.com {{ ansible_distribution_release }} main"
    key_url: https://apt.releases.hashicorp.com/gpg

  # Mesma correção do Fedora: não existe chave 8.2; a série é assinada pela 8.0.
  - name: mongodb
    repo: "deb [arch=amd64] https://repo.mongodb.org/apt/ubuntu {{ ansible_distribution_release }}/mongodb-org/8.2 multiverse"
    key_url: https://www.mongodb.org/static/pgp/server-8.0.asc

  - name: anydesk
    repo: "deb [arch=amd64] http://deb.anydesk.com/ all main"
    key_url: https://keys.anydesk.com/repos/DEB-GPG-KEY

system_packages:
  - docker-ce
  - docker-ce-cli
  - docker-buildx-plugin
  - docker-compose-plugin
  - containerd.io
  - google-chrome-stable
  - chromium-browser
  - firefox
  - code
  - gh
  - git
  - terraform
  - azure-cli
  - nodejs
  - python3-pip
  - pipx
  - ansible-core
  - ansible-lint
  - vim
  - mongodb-mongosh
  - anydesk
  - libreoffice-writer
  - libreoffice-calc
  - libreoffice-impress
  - libreoffice-draw
  - libreoffice-math
  - obs-studio
  - ffmpeg
  - ubuntu-restricted-extras
  - openfortivpn
  - krdc
  - krfb
  - kdeconnect
  - flatpak

hardware_packages:
  - ubuntu-drivers-common
  # -iso é pacote de host; o convidado precisa destes dois.
  - virtualbox-guest-utils
  - virtualbox-guest-x11
  - solaar
  - minicom
```

- [ ] **Step 4: Criar `roles/repos/tasks/debian.yml`**

`apt_key` está obsoleto; a chave vai para `/etc/apt/keyrings` e o repositório
a referencia com `signed-by`.

```yaml
---
- name: Ensure keyring directory exists
  become: true
  ansible.builtin.file:
    path: /etc/apt/keyrings
    state: directory
    mode: "0755"

- name: Download repository signing keys
  become: true
  ansible.builtin.get_url:
    url: "{{ item.key_url }}"
    dest: "/etc/apt/keyrings/{{ item.name }}.{{ item.ext | default('asc') }}"
    mode: "0644"
  loop: "{{ apt_repositories }}"
  loop_control:
    label: "{{ item.name }}"

- name: Add third party repositories
  become: true
  ansible.builtin.apt_repository:
    repo: >-
      {{ item.repo | replace('[arch=amd64]',
         '[arch=amd64 signed-by=/etc/apt/keyrings/' ~ item.name ~ '.' ~ (item.ext | default('asc')) ~ ']') }}
    filename: "{{ item.name }}"
    state: present
    update_cache: false
  loop: "{{ apt_repositories }}"
  loop_control:
    label: "{{ item.name }}"

# update_cache uma vez ao final, em vez de sete vezes dentro do loop.
- name: Update apt cache
  become: true
  ansible.builtin.apt:
    update_cache: true
```

- [ ] **Step 5: Criar `roles/packages/tasks/debian.yml`**

```yaml
---
- name: Update all system packages
  become: true
  ansible.builtin.apt:
    upgrade: dist
    update_cache: true
    cache_valid_time: 3600
  changed_when: false
  tags:
    - upgrade

- name: Install system packages
  become: true
  ansible.builtin.apt:
    name: "{{ system_packages }}"
    state: present
```

- [ ] **Step 6: Criar `roles/hardware/tasks/debian.yml`**

O driver nvidia no Ubuntu não sai de uma lista fixa: `ubuntu-drivers` escolhe
a versão compatível com o hardware e com o Secure Boot da máquina.

```yaml
---
- name: Install hardware specific packages
  become: true
  ansible.builtin.apt:
    name: "{{ hardware_packages }}"
    state: present

- name: Install the recommended nvidia driver
  become: true
  ansible.builtin.command: ubuntu-drivers install
  register: nvidia_install
  changed_when: "'No drivers found' not in nvidia_install.stdout"
```

- [ ] **Step 7: Criar `ubuntu.yml`**

Mesma ordem de roles do `fedora.yml`. As roles `flatpak`, `binaries`,
`system_config`, `dotfiles` e `gather` não têm variante por distribuição:
o que muda entre os dois sistemas já está isolado em `repos`, `packages` e
`hardware`.

```yaml
---
- name: Provision Ubuntu workstation
  hosts: workstation
  gather_facts: true
  vars_files:
    - vars/ubuntu.yml
  roles:
    - { role: repos, tags: [repos] }
    - { role: packages, tags: [packages] }
    - { role: flatpak, tags: [flatpak] }
    - { role: binaries, tags: [binaries] }
    - { role: system_config, tags: [system_config] }
    - { role: dotfiles, tags: [dotfiles] }
    - { role: gather, tags: [gather] }
    - { role: hardware, tags: [hardware, never] }
```

- [ ] **Step 8: Syntax-check e lint**

```bash
ansible-playbook -i inventory/hosts.ini ubuntu.yml --syntax-check
ansible-lint ubuntu.yml
```

Esperado: ambos sem erro.

- [ ] **Step 9: Registrar a limitação e a perda de escopo**

Duas coisas precisam ficar escritas, não subentendidas.

A validação para em syntax-check e lint. Não há máquina Ubuntu, e os nomes de
pacote em `vars/ubuntu.yml` não foram conferidos contra `apt-cache`.

E o `ubuntu.yml` **não** cobre o mesmo conjunto que o `fedora.yml`, ao
contrário do que a spec afirma. Ficam de fora, sem equivalente resolvido:

| Ausente no Ubuntu | Motivo |
|---|---|
| `discord` | precisa do `.deb` oficial, não empacotado no plano |
| `antigravity` | repositório é RPM apenas |
| `ndi-sdk` | vem da RPM Fusion nonfree |
| `mediawriter` | disponível só por flatpak |
| `docker-model-plugin` | não publicado para Ubuntu |
| plugins do OBS (6) | empacotados só no Fedora/RPM Fusion |

Acrescente esta tabela ao README na Task 12. Uma omissão registrada é uma
decisão; uma omissão silenciosa é um bug que só aparece na hora de formatar.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: playbook do Ubuntu sobre as mesmas roles

Reaproveita as oito roles; a diferença de gerenciador fica em
vars/ubuntu.yml e nos tasks/debian.yml. Chaves de repositório vão para
/etc/apt/keyrings com signed-by, já que apt_key está obsoleto.

Mapeamentos sem equivalente direto: codecs da RPM Fusion viram
ubuntu-restricted-extras e o driver nvidia sai do ubuntu-drivers, que
escolhe a versão compatível com o hardware e com o Secure Boot.

Validado só por syntax-check e ansible-lint: não há máquina Ubuntu para
executar, e os nomes de pacote não foram conferidos contra apt-cache.

Não cobre o mesmo conjunto do Fedora: discord, antigravity, ndi-sdk,
mediawriter, docker-model-plugin e os seis plugins do OBS ficam de fora,
sem equivalente resolvido. A tabela está no README."
```

---

### Task 12: README

**Files:**
- Modify: `readme.md`

**Interfaces:**
- Consumes: tudo o que as tasks anteriores produziram.
- Produces: nada consumido por outra task.

- [ ] **Step 1: Reescrever `readme.md`**

A cerca externa usa til para que as cercas de crase de dentro não a fechem
antes da hora — o conteúdo entre as linhas de til é o arquivo inteiro.

~~~~
# ansible-playbooks

Provisiona uma estação de trabalho do zero, reproduzindo aplicações,
configuração de sistema e dotfiles. Dois playbooks sobre as mesmas roles:
`fedora.yml` e `ubuntu.yml`.

## Uso

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook fedora.yml --ask-become-pass
```

Pacotes ligados ao hardware desta máquina não rodam por padrão, nem a
atualização geral do sistema:

```bash
ansible-playbook fedora.yml --ask-become-pass --tags hardware
ansible-playbook fedora.yml --ask-become-pass --tags upgrade
```

Tags disponíveis: `repos`, `packages`, `flatpak`, `binaries`,
`system_config`, `dotfiles`, `gather`, `hardware`, `upgrade`.

Depois da primeira execução, **deslogue e logue de novo**: entrar no grupo
`docker` só vale a partir de uma nova sessão, e até lá `docker ps` falha com
permissão negada.

## O que não está aqui

Nenhuma credencial. Depois de rodar o playbook numa máquina nova, restaure à
mão, a partir do gerenciador de senhas ou de backup cifrado:

| O quê | Onde |
|---|---|
| Chaves SSH | `~/.ssh/github_personal`, `~/.ssh/home_lab` |
| Credenciais AWS | `~/.aws/credentials` |
| Login do gh | `gh auth login` |
| Login da Azure | `az login` |
| Segredos do Gather | `~/.config/gather/{claude,status,webhook}` |

O playbook cria os diretórios com as permissões corretas e os arquivos de
segredo vazios; o conteúdo é seu. Os serviços do Gather não sobem enquanto os
arquivos estiverem vazios — é intencional, e não um erro.

Também instalado à mão, por não existir em repositório nenhum:

| O quê | Onde |
|---|---|
| `gemini-desktop` | RPM de release em `github.com/bwendell/gemini-desktop` |

Ele não é assinado, então cada instalação é uma decisão consciente de rodar
binário não verificado. Por isso ficou fora do playbook.

Fora de escopo por decisão: configuração do KDE Plasma e bibliotecas Python
de projeto.

## Estado

`fedora.yml` roda e é idempotente na máquina de origem, e cada role foi
validada uma vez em container `fedora:43` limpo.

`ubuntu.yml` foi validado apenas por `--syntax-check` e `ansible-lint`. Não
houve máquina Ubuntu para executá-lo, e os nomes de pacote em
`vars/ubuntu.yml` não foram conferidos contra `apt-cache`. Trate a primeira
execução como um teste.

O `ubuntu.yml` também não cobre o mesmo conjunto do `fedora.yml`:

| Ausente no Ubuntu | Motivo |
|---|---|
| `discord` | precisa do `.deb` oficial, ainda não empacotado aqui |
| `antigravity` | repositório é RPM apenas |
| `ndi-sdk` | vem da RPM Fusion nonfree |
| `mediawriter` | disponível só por flatpak |
| `docker-model-plugin` | não publicado para Ubuntu |
| plugins do OBS (6) | empacotados só no Fedora/RPM Fusion |

## Design

`docs/superpowers/specs/2026-08-20-ansible-provisionamento-desktop-design.md`
~~~~

- [ ] **Step 2: Verificar os comandos do README**

```bash
ansible-playbook fedora.yml --list-tags
```

Esperado: as oito tags citadas aparecem na saída.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: reescreve o readme

Descreve uso, tags e — o que mais importa numa máquina recém-formatada — a
lista do que o playbook deliberadamente não restaura, com onde buscar cada
credencial, mais o gemini-desktop, que não existe em repositório nenhum e
não é assinado.

Declara que ubuntu.yml nunca foi executado e o que ele deixa de cobrir."
```
