# Provisionamento de estação com Ansible — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruir este repositório em roles Ansible compartilhadas que
reproduzem a estação atual do zero, em Fedora e em Ubuntu.

**Architecture:** Dois playbooks (`fedora.yml`, `ubuntu.yml`) sobre oito roles
comuns. A diferença entre gerenciadores de pacote vive em `vars/<distro>.yml`
e em `roles/<role>/tasks/<distro>.yml`, incluído conforme `ansible_os_family`.
Nenhum segredo no repositório. Pacotes de hardware isolados por tag.

**Tech Stack:** ansible-core 2.19 (`ansible-core` do Fedora 43),
`community.general` para os módulos `copr` e `flatpak`, `ansible-lint`,
`node --test` para a mudança no cliente do Gather.

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

---

### Task 1: Esqueleto do projeto

**Files:**
- Create: `ansible.cfg`
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

- [ ] **Step 4: Criar `inventory/hosts.ini`**

```ini
[workstation]
localhost ansible_connection=local
```

- [ ] **Step 5: Criar `collections/requirements.yml`**

```yaml
---
collections:
  - name: community.general
```

- [ ] **Step 6: Criar `.gitignore`**

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

- [ ] **Step 7: Criar `group_vars/all.yml`**

```yaml
---
# Diretório de trabalho para downloads temporários (AWS CLI, azcopy).
tmp_folder: /tmp/ansible_provision

# Usuário provisionado. Deriva do usuário que invoca o playbook, para que o
# mesmo repositório sirva outra máquina sem edição.
target_user: "{{ ansible_user_id }}"
target_home: "{{ ansible_env.HOME }}"
```

- [ ] **Step 8: Criar `vars/fedora.yml` com o cabeçalho**

Só o esqueleto; as listas entram nas tasks 2 e 3.

```yaml
---
# Pacotes e repositórios específicos do Fedora.
# Listas preenchidas nas tasks seguintes.
```

- [ ] **Step 9: Criar `fedora.yml`**

```yaml
---
- name: Provision Fedora workstation
  hosts: workstation
  gather_facts: true
  vars_files:
    - vars/fedora.yml
  roles: []
```

- [ ] **Step 10: Remover os arquivos obsoletos**

```bash
git rm fedora/fedora.yaml fedora/amazon-ssm-agent.gpg fedora/peazip-flatpak.desktop.download
```

- [ ] **Step 11: Instalar a collection e rodar o syntax-check**

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --syntax-check
```

Esperado: `playbook: fedora.yml`, sem erro.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "feat: esqueleto do projeto Ansible

Substitui o playbook único por uma estrutura de roles com inventário
local, collections declaradas e gitignore que barra credencial.

Remove fedora/fedora.yaml, que descrevia uma máquina que não existe mais,
a chave GPG expirada do SSM Agent e o arquivo do PeaZip, desinstalado."
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

O teste é a execução real seguida de verificação do estado do sistema:

```bash
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags repos
dnf repolist --enabled | grep -E 'docker-ce-stable|gh-cli|hashicorp'
```

- [ ] **Step 2: Rodar e confirmar a falha**

Esperado: o playbook não executa nada, porque `roles:` está vazio. O `grep`
passa por acidente, já que os repositórios existem nesta máquina — por isso o
teste real de aceite desta role é `--check` em container limpo, no Step 8.

- [ ] **Step 3: Preencher `vars/fedora.yml` com os repositórios**

```yaml
---
# Repositórios de release entregues como .rpm.
rpm_url_repositories:
  - "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-{{ ansible_distribution_major_version }}.noarch.rpm"
  - "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-{{ ansible_distribution_major_version }}.noarch.rpm"
  - "https://repos.fyralabs.com/terra{{ ansible_distribution_major_version }}/terra-release.rpm"

# Repositórios definidos por arquivo .repo.
dnf_repositories:
  - name: google-chrome
    description: google-chrome
    baseurl: https://dl.google.com/linux/chrome/rpm/stable/x86_64
    gpgcheck: true
    gpgkey: https://dl.google.com/linux/linux_signing_key.pub

  - name: code
    description: Visual Studio Code
    baseurl: https://packages.microsoft.com/yumrepos/vscode
    gpgcheck: true
    gpgkey: https://packages.microsoft.com/keys/microsoft.asc

  - name: gh-cli
    description: packages for the GitHub CLI
    baseurl: https://cli.github.com/packages/rpm
    gpgcheck: true
    gpgkey: https://cli.github.com/packages/rpm/gpg.key

  - name: docker-ce-stable
    description: Docker CE Stable - x86_64
    baseurl: "https://download.docker.com/linux/fedora/{{ ansible_distribution_major_version }}/x86_64/stable"
    gpgcheck: true
    gpgkey: https://download.docker.com/linux/fedora/gpg

  - name: hashicorp
    description: Hashicorp Stable - x86_64
    baseurl: "https://rpm.releases.hashicorp.com/fedora/{{ ansible_distribution_major_version }}/x86_64/stable"
    gpgcheck: true
    gpgkey: https://rpm.releases.hashicorp.com/gpg

  - name: mongodb-org-8.2
    description: MongoDB Repository
    baseurl: https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.2/x86_64/
    gpgcheck: true
    gpgkey: https://pgp.mongodb.com/server-8.2.asc

  - name: anydesk
    description: AnyDesk Fedora - stable
    baseurl: http://rpm.anydesk.com/fedora/x86_64/
    gpgcheck: true
    gpgkey: https://keys.anydesk.com/repos/RPM-GPG-KEY
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
  ansible.builtin.dnf:
    name: "{{ rpm_url_repositories }}"
    state: present
    disable_gpg_check: true

- name: Add third party repositories
  become: true
  ansible.builtin.yum_repository:
    name: "{{ item.name }}"
    description: "{{ item.description }}"
    baseurl: "{{ item.baseurl }}"
    enabled: true
    gpgcheck: "{{ item.gpgcheck }}"
    gpgkey: "{{ item.gpgkey | default(omit) }}"
  loop: "{{ dnf_repositories }}"
  loop_control:
    label: "{{ item.name }}"

- name: Add Microsoft production repository
  become: true
  ansible.builtin.dnf:
    name: "https://packages.microsoft.com/config/fedora/{{ ansible_distribution_major_version }}/packages-microsoft-prod.rpm"
    state: present
    disable_gpg_check: true
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

- [ ] **Step 8: Execução e idempotência**

```bash
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags repos
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags repos
```

Esperado na segunda execução: `changed=0`. Se `yum_repository` reportar
`changed` sempre, é sinal de que algum campo do `.repo` existente difere do
declarado — comparar com `/etc/yum.repos.d/<name>.repo` e alinhar.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: role repos com os repositórios de terceiros do Fedora

Repositórios declarados em vars/fedora.yml, separados entre pacotes de
release e arquivos .repo.

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

```bash
rpm -q code gh terraform docker-ce discord antigravity mongodb-mongosh
```

- [ ] **Step 2: Rodar e confirmar o estado**

Nesta máquina todos já estão instalados, então o comando passa. O teste que
importa é a idempotência do Step 6 e o `--check` num container Fedora limpo.

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
  - gemini-desktop
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

O `changed_when` na primeira tarefa existe porque `state: latest` sobre `*`
reporta mudança sempre que há atualização a montante, o que não é mudança
causada pelo playbook e quebraria o critério de idempotência.

```yaml
---
- name: Update all system packages
  become: true
  ansible.builtin.dnf:
    name: "*"
    state: latest
  register: dnf_upgrade
  changed_when: false
  tags:
    - upgrade

- name: Install system packages
  become: true
  ansible.builtin.dnf:
    name: "{{ system_packages }}"
    state: present
```

- [ ] **Step 6: Ligar a role, lint, executar duas vezes**

Em `fedora.yml`, após `repos`:

```yaml
    - { role: packages, tags: [packages] }
```

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags packages
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags packages
```

Esperado na segunda: `changed=0`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: role packages com os pacotes dnf da estação

Lista agrupada por finalidade em vars/fedora.yml.

A atualização geral do sistema fica com changed_when: false — ela reporta
mudança sempre que há pacote novo no repositório, o que não é efeito do
playbook e inviabilizaria o teste de idempotência."
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

```bash
flatpak list --app --columns=application | sort > /tmp/flatpak-antes.txt
diff <(printf '%s\n' com.mongodb.Compass com.moonlight_stream.Moonlight com.spotify.Client io.dbeaver.DBeaverCommunity it.mijorus.gearlever org.ferdium.Ferdium org.kde.yakuake | sort) /tmp/flatpak-antes.txt
```

- [ ] **Step 2: Rodar e confirmar**

Esperado: sem diferença nesta máquina. Em máquina limpa, todas as sete linhas
aparecem como ausentes — é esse o estado que a role precisa produzir.

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
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags flatpak
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags flatpak
```

Esperado na segunda: `changed=0`.

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
- Consumes: `tmp_folder` de `group_vars/all.yml`.
- Produces: `/usr/local/bin/aws`, `/usr/local/bin/azcopy` e o pacote
  `session-manager-plugin`.

- [ ] **Step 1: Escrever o teste que falha**

```bash
command -v aws && aws --version
command -v session-manager-plugin && session-manager-plugin --version
command -v azcopy && azcopy --version
```

- [ ] **Step 2: Rodar e confirmar o estado**

Esperado nesta máquina: os três respondem. Em máquina limpa, os três falham
com `command not found`.

- [ ] **Step 3: Criar `roles/binaries/tasks/main.yml`**

```yaml
---
- name: Create temporary download folder
  become: true
  ansible.builtin.file:
    path: "{{ tmp_folder }}"
    state: directory
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

O instalador do AWS CLI não expõe estado consultável, então o `creates` do
`command` faz o papel do guard de idempotência: com `/usr/local/bin/aws`
presente, a tarefa é pulada.

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
  register: aws_install
  changed_when: "'already exists' not in aws_install.stderr"
```

- [ ] **Step 5: Criar `roles/binaries/tasks/fedora.yml`**

```yaml
---
- name: Install session-manager-plugin
  become: true
  ansible.builtin.dnf:
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
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags binaries
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags binaries
```

Esperado na segunda: `changed=0` nas tarefas de instalação. `get_url` e
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
de --update mais changed_when sobre a saída."
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
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags system_config
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags system_config
```

Esperado na segunda: `changed=0`.

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

Firewalld verificado: sem regra personalizada além do padrão da zona, então
não há nada a versionar."
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

- [ ] **Step 4: Revisar `files/dotfiles/gitconfig` à mão**

Abra o arquivo. Ele contém `credential.https://github.com.helper=!/usr/bin/gh
auth git-credential`, que é um comando, não um token — pode ficar. Confirme
que não há `[user] signingkey` apontando para caminho de chave privada nem
nenhum valor literal de credencial.

- [ ] **Step 5: Acrescentar a lista em `group_vars/all.yml`**

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

- [ ] **Step 6: Criar `roles/dotfiles/tasks/main.yml`**

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

- [ ] **Step 7: Ligar a role, lint, executar duas vezes**

```yaml
    - { role: dotfiles, tags: [dotfiles] }
```

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --tags dotfiles
ansible-playbook -i inventory/hosts.ini fedora.yml --tags dotfiles
```

Esperado na segunda: `changed=0`. Esta role não precisa de `--ask-become-pass`.

- [ ] **Step 8: Confirmar que o SSH continua funcionando**

```bash
ssh -T git@github.com-personal
```

Esperado: `Hi gleitoncampos! You've successfully authenticated`. Se falhar,
compare `~/.ssh/config` com o backup que o `backup: true` deixou ao lado.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: role dotfiles com shell, git e cliente SSH

Quatro arquivos, todos varridos por token, secret, password e cabeçalho de
chave privada antes de entrar no repositório.

Cria ~/.ssh em 0700 e ~/.aws vazio: a configuração é versionada, as
credenciais não. O helper do git é um comando do gh, não um token."
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

```bash
node --test files/gather/
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
node --test files/gather/
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

- [ ] **Step 5: Criar `roles/gather/templates/gather-ci-status.service.j2`**

```jinja
[Unit]
Description=Atualiza o Smart Object "Bot Status Monitor" com a saúde dos deploys (GitHub Actions)
After=network-online.target

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
  notify: Reload systemd user daemon

- name: Enable Gather units
  ansible.builtin.systemd_service:
    name: "{{ item }}"
    scope: user
    enabled: true
    daemon_reload: true
  loop:
    - gather-claude-status.service
    - gather-ci-status.timer
    - gather-prs.timer
```

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

O comportamento a garantir é que a role **não** rode sem a tag:

```bash
ansible-playbook -i inventory/hosts.ini fedora.yml --list-tasks | grep -c nvidia
```

- [ ] **Step 2: Rodar e confirmar**

Esperado antes: `0`, porque a role ainda não existe. Depois do Step 6, o
`--list-tasks` sem `--tags` deve continuar sem listar as tarefas de nvidia.

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
  ansible.builtin.dnf:
    name: "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-{{ ansible_distribution_major_version }}.noarch.rpm"
    state: present
    disable_gpg_check: true

- name: Install hardware specific packages
  become: true
  ansible.builtin.dnf:
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

Esperado: `0` no primeiro, número maior que zero no segundo.

- [ ] **Step 8: Lint e execução com a tag, duas vezes**

```bash
ansible-lint fedora.yml
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags hardware
ansible-playbook -i inventory/hosts.ini fedora.yml --ask-become-pass --tags hardware
```

Esperado na segunda: `changed=0`.

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

  - name: github-cli
    repo: "deb [arch=amd64] https://cli.github.com/packages stable main"
    key_url: https://cli.github.com/packages/githubcli-archive-keyring.gpg

  - name: hashicorp
    repo: "deb [arch=amd64] https://apt.releases.hashicorp.com {{ ansible_distribution_release }} main"
    key_url: https://apt.releases.hashicorp.com/gpg

  - name: mongodb
    repo: "deb [arch=amd64] https://repo.mongodb.org/apt/ubuntu {{ ansible_distribution_release }}/mongodb-org/8.2 multiverse"
    key_url: https://pgp.mongodb.com/server-8.2.asc

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
  - virtualbox-guest-additions-iso
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
    dest: "/etc/apt/keyrings/{{ item.name }}.asc"
    mode: "0644"
  loop: "{{ apt_repositories }}"
  loop_control:
    label: "{{ item.name }}"

- name: Add third party repositories
  become: true
  ansible.builtin.apt_repository:
    repo: "{{ item.repo | replace('[arch=amd64]', '[arch=amd64 signed-by=/etc/apt/keyrings/' ~ item.name ~ '.asc]') }}"
    filename: "{{ item.name }}"
    state: present
    update_cache: true
  loop: "{{ apt_repositories }}"
  loop_control:
    label: "{{ item.name }}"
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

- [ ] **Step 9: Registrar a limitação**

Não há máquina Ubuntu para executar. A validação para em syntax-check e lint;
os nomes de pacote de `vars/ubuntu.yml` não foram conferidos contra um
`apt-cache`. Isso vai para o README na Task 12 e para a mensagem de commit —
é uma limitação conhecida da entrega, não um descuido.

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
executar, e os nomes de pacote não foram conferidos contra apt-cache."
```

---

### Task 12: README

**Files:**
- Modify: `readme.md`

**Interfaces:**
- Consumes: tudo o que as tasks anteriores produziram.
- Produces: nada consumido por outra task.

- [ ] **Step 1: Reescrever `readme.md`**

```markdown
# ansible-playbooks

Provisiona uma estação de trabalho do zero, reproduzindo aplicações,
configuração de sistema e dotfiles. Dois playbooks sobre as mesmas roles:
`fedora.yml` e `ubuntu.yml`.

## Uso

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook fedora.yml --ask-become-pass
```

Pacotes ligados ao hardware desta máquina não rodam por padrão:

```bash
ansible-playbook fedora.yml --ask-become-pass --tags hardware
```

Tags disponíveis: `repos`, `packages`, `flatpak`, `binaries`,
`system_config`, `dotfiles`, `gather`, `hardware`.

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
segredo vazios; o conteúdo é seu.

Também fora: configuração do KDE Plasma e bibliotecas Python de projeto.

## Estado

`fedora.yml` roda e é idempotente na máquina de origem.

`ubuntu.yml` foi validado apenas por `--syntax-check` e `ansible-lint`. Não
houve máquina Ubuntu para executá-lo, e os nomes de pacote em
`vars/ubuntu.yml` não foram conferidos contra `apt-cache`. Trate a primeira
execução como um teste.

## Design

`docs/superpowers/specs/2026-08-20-ansible-provisionamento-desktop-design.md`
```

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
credencial.

Declara que ubuntu.yml nunca foi executado."
```
